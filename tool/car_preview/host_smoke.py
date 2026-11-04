"""Drive the real debug CarAppService over Binder from its separate test host.

Invoked only by headless_smoke.py on the isolated CI emulator/loopback broker.
This exercises the real protocol and foreground lifetime, not the AA renderer.
"""
from pathlib import Path
import json
import re
import subprocess
import time


PACKAGE = "pro.surpin.wiredash"
OUT = Path(__file__).resolve().parents[2] / "build/video-preview"


def run_host_smoke(shell, probe, traffic):
    def events():
        log = shell("logcat", "-d", "-s", "WireDashAutoHostProbe:I", "*:S")
        return [json.loads(m.group(1)) for line in log.splitlines()
                if (m := re.search(r"(\{.*\})$", line))]

    def since():
        return max((v.get("at", 0) for v in events()), default=0)

    def host(command):
        shell("am", "start-foreground-service", "-n", PACKAGE + "/.car.CarHostProbeService",
              "--es", "cmd", command)

    def snapshot(predicate, after=0):
        deadline = time.monotonic() + 35
        while time.monotonic() < deadline:
            current = [v for v in events() if v.get("at", 0) > after]
            failures = [v for v in current if v.get("failure")]
            assert not failures, failures
            matches = [v for v in current if v.get("phase") == "template" and predicate(v)]
            if matches:
                return matches[-1]
            time.sleep(0.25)
        raise AssertionError("Real car-service host did not receive the expected template")

    def catalog(after=0):
        return snapshot(lambda v: not v.get("loading") and v.get("browsable") == 1
                        and v.get("toggles") == 0, after)

    def dashboard(on, after=0):
        return snapshot(lambda v: v.get("rows", 0) >= 10 and v.get("known")
                        and v.get("toggles", 0) > 0 and v.get("on") == on, after)

    def state(value):
        subprocess.run(["mosquitto_pub", "-p", "18884", "-t", "/devices/preview/controls/K1",
                        "-m", value, "-r"], check=True, timeout=10)

    def tap(payload):
        mark = since()
        before = len(traffic)
        host("tap")
        end = time.monotonic() + 10
        while time.monotonic() < end:
            if "/devices/preview/controls/K1/on|" + payload in traffic[before:]:
                return dashboard(payload == "1", mark)
            time.sleep(0.1)
        raise AssertionError("Car-service row did not publish its actual MQTT command")

    print("Car-service check: cold bind, handshake and native chooser without phone UI", flush=True)
    shell("am", "force-stop", PACKAGE)
    state("0")
    mark = since()
    host("start")
    root = catalog(mark)
    assert PACKAGE + "/.MainActivity" not in shell("dumpsys", "activity", "activities")
    assert shell("pidof", PACKAGE) != shell("pidof", PACKAGE + ":auto_probe")
    service = shell("dumpsys", "activity", "services", PACKAGE + "/.car.WireDashCarService")
    assert "isForeground=true" in service, service[-3000:]
    (OUT / "car-service-foreground.log").write_text(service)
    mark = since()
    host("open")
    opened = dashboard(False, mark)

    print("Car-service check: phone-origin state and real row taps preserve template ID", flush=True)
    mark = since()
    state("1")
    changed = dashboard(True, mark)
    assert changed["templateId"] == opened["templateId"]
    tapped = tap("0")
    assert tapped["templateId"] == opened["templateId"]

    print("Car-service check: removing phone task leaves bound foreground Auto session alive", flush=True)
    shell("am", "start", "-W", "-n", PACKAGE + "/.MainActivity")
    time.sleep(3)
    assert probe("removePhoneTask")["removedTasks"] == 1
    tapped_again = tap("1")
    assert tapped_again["templateId"] == opened["templateId"]
    assert "isForeground=true" in shell("dumpsys", "activity", "services", PACKAGE + "/.car.WireDashCarService")

    print("Car-service check: Back restores chooser identity; forward uses a new screen", flush=True)
    mark = since()
    host("back")
    returned = catalog(mark)
    assert returned["templateId"] == root["templateId"]
    mark = since()
    host("open")
    reopened = dashboard(True, mark)
    assert reopened["templateId"] != opened["templateId"]
    host("stop")
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        service = shell("dumpsys", "activity", "services", PACKAGE + "/.car.WireDashCarService")
        if "isForeground=true" not in service:
            break
        time.sleep(0.25)
    assert "isForeground=true" not in service
    history = events()
    assert not [v for v in history if v.get("failure")]
    worst = max(v.get("worstMs", v.get("ms", 0)) for v in history)
    assert worst < 5000, f"Car-service main thread stalled for {worst}ms"
    (OUT / "car-host-summary.log").write_text(json.dumps({
        "coldChooserWithoutPhone": True, "foregroundService": True,
        "phoneStateStableTemplateId": True, "realRowCommands": 2,
        "phoneTaskRemovedWithSessionAlive": True, "backRestoresChooserId": True,
        "forwardCreatesNewScreenId": True, "foregroundReleasedOnStop": True,
        "worstCallbackMs": worst, "events": history,
        "actualAndroidAutoRendererTested": False,
    }, indent=2) + "\n")
    print("Real cross-process car-service protocol, foreground and task-removal checks passed.", flush=True)
