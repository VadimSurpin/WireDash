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


def run_host_smoke(shell, probe, traffic, feedback_allowed):
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
        started = time.monotonic()
        mark = since()
        before = len(traffic)
        host("tap")
        end = time.monotonic() + 10
        while time.monotonic() < end:
            if "/devices/preview/controls/K1/on|" + payload in traffic[before:]:
                result = dashboard(payload == "1", mark)
                assert time.monotonic() - started < 5, "Auto action stalled after the phone task was removed"
                return result
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
    assert changed["iconFingerprint"] == opened["iconFingerprint"]

    print("Car-service check: delayed MQTT feedback keeps UI responsive and actual switch state", flush=True)
    mark = since()
    before = len(traffic)
    feedback_allowed.clear()
    try:
        host("tap")
        deadline = time.monotonic() + 10
        while "/devices/preview/controls/K1/on|0" not in traffic[before:]:
            assert time.monotonic() < deadline, "Command did not reach broker"
            time.sleep(0.1)
        time.sleep(2)
        waiting = [v for v in events() if v.get("at", 0) > mark]
        templates = [v for v in waiting if v.get("phase") == "template" and v.get("known")]
        assert len(templates) >= 3, "Host stopped responding while awaiting MQTT feedback"
        assert all(v.get("on") is True for v in templates), "Switch claimed the unconfirmed target"
        assert all(v.get("iconFingerprint") == opened["iconFingerprint"] for v in templates)
        assert any(v.get("phase") == "toast" and v.get("working") for v in waiting), "No action progress popup"
    finally:
        feedback_allowed.set()
    tapped = dashboard(False, since())
    assert tapped["templateId"] == opened["templateId"]
    assert tapped["iconFingerprint"] == opened["iconFingerprint"]

    auto_worst = max(v.get("worstMs", v.get("ms", 0)) for v in events())
    assert auto_worst < 5000, f"Auto-only service stalled for {auto_worst}ms"

    print("Car-service check: removing phone task leaves bound foreground Auto session alive", flush=True)
    shell("am", "start", "-W", "-n", PACKAGE + "/.MainActivity")
    time.sleep(3)
    assert probe("removePhoneTask")["removedTasks"] == 1
    tapped_again = tap("1")
    assert tapped_again["templateId"] == opened["templateId"]
    assert "isForeground=true" in shell("dumpsys", "activity", "services", PACKAGE + "/.car.WireDashCarService")

    print("Car-service check: Back restores chooser identity; forward uses a new screen", flush=True)
    mark = since()
    started = time.monotonic()
    host("back")
    returned = catalog(mark)
    assert time.monotonic() - started < 5, "Back navigation stalled with the phone closed"
    assert returned["templateId"] == root["templateId"]
    mark = since()
    started = time.monotonic()
    host("open")
    reopened = dashboard(True, mark)
    assert time.monotonic() - started < 5, "Dashboard selection stalled with the phone closed"
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
    # Cold-starting a second, visible Flutter engine also JIT-compiles the phone
    # UI on this debug emulator. Keep that measurement separate from Auto-only
    # latency; Auto taps, Back and dashboard selection retain strict 5s limits.
    (OUT / "car-host-summary.log").write_text(json.dumps({
        "coldChooserWithoutPhone": True, "foregroundService": True,
        "phoneStateStableTemplateId": True, "realRowCommands": 2,
        "backgroundCommandWorker": True, "staticIcons": True,
        "responsiveWhileAwaitingFeedback": True, "actionProgressPopup": True,
        "switchUsesActualStateAfterFeedback": True,
        "phoneTaskRemovedWithSessionAlive": True, "backRestoresChooserId": True,
        "forwardCreatesNewScreenId": True, "foregroundReleasedOnStop": True,
        "worstCallbackMs": auto_worst, "includingColdPhoneStartupWorstCallbackMs": worst,
        "phoneClosedActionsUnderFiveSeconds": True, "events": history,
        "actualAndroidAutoRendererTested": False,
    }, indent=2) + "\n")
    print("Real cross-process car-service protocol, foreground and task-removal checks passed.", flush=True)
