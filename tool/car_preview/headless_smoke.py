"""CI emulator check of the real Auto bridge without a phone activity.

Uses an isolated fixture and loopback broker. Clears the emulator app's data;
never run this against a personal device. No Android Auto renderer is involved.
"""
from pathlib import Path
import json
import os
import re
import subprocess
import threading
import time
import uuid


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/video-preview"
ADB = str(Path(os.environ["ANDROID_HOME"]) / "platform-tools/adb")
PACKAGE = "pro.surpin.wiredash"
processes = []
traffic = []
results = []


def run(*args, **kwargs):
    return subprocess.run(args, check=True, timeout=30, **kwargs)


def shell(*args):
    return subprocess.check_output([ADB, "shell", *args], text=True, timeout=30).strip()


def probe(method, **args):
    token = uuid.uuid4().hex
    command = ["am", "broadcast", "--include-stopped-packages", "-n",
               PACKAGE + "/.ShortcutDebugReceiver", "--es", "cmd", method,
               "--es", "probe", token]
    for key, value in args.items():
        command.extend(["--es", key, str(value)])
    shell(*command)
    deadline = time.monotonic() + 18
    while time.monotonic() < deadline:
        log = shell("logcat", "-d", "-s", "WireDashAutoProbe:I", "*:S")
        for line in log.splitlines():
            match = re.search(r"(\{.*\})$", line)
            if match:
                data = json.loads(match[1])
                if data.get("probe") == token:
                    assert data.get("outcome", "ok") == "ok" or (
                        method == "carCommand" and data.get("outcome") == "sent"
                    ), data
                    results.append(data)
                    return data
        time.sleep(0.25)
    raise AssertionError(f"Headless bridge did not respond to {method}")


def opened(expected=None):
    for _ in range(20):
        data = probe("carOpen", dashboardId="preview", controlId="K1")
        assert data["controls"] >= 10, data
        if data["connected"] and (expected is None or data.get("state") == expected):
            return data
        time.sleep(0.4)
    raise AssertionError("Headless MQTT connection/state did not recover")


def command(action, payload):
    before = len(traffic)
    probe("carCommand", dashboardId="preview", controlId="K1", actionId=action)
    for _ in range(40):
        if "/devices/preview/controls/K1/on|" + payload in traffic[before:]:
            opened(action)
            return
        time.sleep(0.1)
    raise AssertionError("The real broker did not receive the headless command")


def mirror(stream):
    with (OUT / "headless-mqtt.log").open("w") as log:
        for line in stream:
            message = line.rstrip("\n")
            traffic.append(message)
            log.write(message + "\n")
            log.flush()
            topic, _, payload = message.partition("|")
            if topic.endswith("/on"):
                run("mosquitto_pub", "-p", "18884", "-t", topic[:-3], "-m", payload, "-r")


try:
    assert os.environ.get("GITHUB_ACTIONS") == "true", "This destructive fixture is CI-only"
    assert shell("getprop", "ro.kernel.qemu") == "1", "An isolated emulator is required"
    fixture = ROOT / "build/car-preview/zigdash.sqlite"
    assert fixture.is_file()
    OUT.mkdir(parents=True, exist_ok=True)
    broker_log = (OUT / "headless-broker.log").open("w")
    broker = subprocess.Popen(["mosquitto", "-p", "18884", "-v"],
                              stdout=broker_log, stderr=subprocess.STDOUT)
    processes.append(broker)
    for attempt in range(30):
        try:
            run("mosquitto_pub", "-p", "18884", "-t", "/devices/preview/controls/K1", "-m", "0", "-r",
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            break
        except subprocess.CalledProcessError:
            if attempt == 29:
                raise
            time.sleep(0.1)
    subscriber = subprocess.Popen(["mosquitto_sub", "-p", "18884", "-t",
                                   "/devices/preview/controls/+/on", "-F", "%t|%p"],
                                  stdout=subprocess.PIPE, text=True)
    processes.append(subscriber)
    threading.Thread(target=mirror, args=(subscriber.stdout,), daemon=True).start()
    shell("am", "force-stop", PACKAGE)
    assert shell("pm", "clear", PACKAGE) == "Success"
    run(ADB, "push", str(fixture), "/data/local/tmp/wiredash-headless.sqlite")
    shell("run-as", PACKAGE, "mkdir", "-p", "app_flutter")
    shell("run-as", PACKAGE, "cp", "/data/local/tmp/wiredash-headless.sqlite", "app_flutter/zigdash.sqlite")
    shell("logcat", "-c")

    print("Headless check: first engine starts without opening MainActivity", flush=True)
    assert probe("carCatalog")["dashboards"] == 1
    assert PACKAGE + "/.MainActivity" not in shell("dumpsys", "activity", "activities")
    opened("OFF")
    command("ON", "1")
    probe("carClose")

    print("Headless check: phone task removed while Auto engine is alive", flush=True)
    shell("am", "start", "-W", "-n", PACKAGE + "/.MainActivity")
    time.sleep(3)
    before = shell("pidof", PACKAGE)
    assert probe("removePhoneTask")["removedTasks"] == 1
    time.sleep(1)
    assert probe("removePhoneTask")["removedTasks"] == 0
    opened("ON")
    command("OFF", "0")
    results.append({"phoneTaskRemoved": True, "processRetained": before == shell("pidof", PACKAGE)})
    probe("carClose")

    print("Headless check: restart after the entire app process was killed", flush=True)
    before = shell("pidof", PACKAGE)
    shell("am", "force-stop", PACKAGE)
    assert probe("carCatalog")["dashboards"] == 1
    assert before != shell("pidof", PACKAGE)
    opened("OFF")
    command("ON", "1")
    probe("carClose")
    assert probe("removePhoneTask")["removedTasks"] == 0
    from host_smoke import run_host_smoke
    run_host_smoke(shell, probe, traffic)
    log = shell("logcat", "-d")
    assert "FATAL EXCEPTION" not in log and "Unhandled Exception:" not in log
    assert "ANR in " + PACKAGE not in log
    (OUT / "headless-summary.log").write_text(json.dumps(results, indent=2) + "\n")
    print("Three real headless lifecycle checks passed; no phone activity required.", flush=True)
finally:
    if OUT.exists():
        (OUT / "headless-logcat.log").write_text(shell("logcat", "-d"))
    for process in reversed(processes):
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
