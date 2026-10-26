"""Run the real Automotive template host against WireDash and a local demo broker.

This is a runtime screenshot harness, not an approximation of the car UI.
Requires the SDK emulator + API 35-ext15 Automotive Google APIs image and KVM.
"""
from pathlib import Path
import json
import os
import re
import socket
import subprocess
import threading
import time
import xml.etree.ElementTree as ET


root = Path(__file__).resolve().parents[2]
output = root / "build/car-preview"
output.mkdir(parents=True, exist_ok=True)
sdk = Path(os.environ["ANDROID_HOME"])
adb = str(sdk / "platform-tools/adb")
package = "pro.surpin.wiredash"
image = "system-images;android-35-ext15;android-automotive;x86_64"
processes = []


def run(*args, timeout=60, **kwargs):
    return subprocess.run(args, check=True, timeout=timeout, **kwargs)


def shell(*args, timeout=60):
    return subprocess.check_output([adb, "shell", *args], timeout=timeout, text=True).strip()


def screenshot(name, optional=False):
    for attempt in range(6):
        if attempt == 0:
            result = subprocess.run([adb, "exec-out", "screencap", "-p"],
                                    capture_output=True, timeout=30)
        else:
            # Some emulator builds race screencap's stdout Binder teardown.
            # A device file also preserves the PNG if teardown prints a warning.
            shell("rm", "-f", "/sdcard/wiredash-screen.png")
            shot = subprocess.run([adb, "shell", "screencap", "-p", "/sdcard/wiredash-screen.png"],
                                  capture_output=True, timeout=30)
            result = subprocess.run([adb, "exec-out", "cat", "/sdcard/wiredash-screen.png"],
                                    capture_output=True, timeout=30)
            result.stderr += shot.stdout + shot.stderr
        start = result.stdout.find(b"\x89PNG\r\n\x1a\n")
        end = result.stdout.find(b"IEND\xaeB`\x82", max(start, 0))
        if start >= 0 and end >= 0:
            (output / name).write_bytes(result.stdout[start:end + 8])
            print("Captured", name, flush=True)
            return
        (output / f"screencap-failure-{attempt}.txt").write_bytes(result.stdout + result.stderr)
        time.sleep(2)
    if not optional:
        raise RuntimeError("screencap did not return an image after startup retries")


def ui(name="current-ui.xml"):
    shell("uiautomator", "dump", "/sdcard/wiredash-preview.xml", timeout=30)
    data = subprocess.check_output([adb, "exec-out", "cat", "/sdcard/wiredash-preview.xml"], timeout=15)
    (output / name).write_bytes(data)
    return ET.fromstring(data)


def find(tree, text):
    return next((n for n in tree.iter() if text in
                 [n.attrib.get("text"), n.attrib.get("content-desc")]), None)


def wait_text(text, name, seconds=60):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        tree = ui(name)
        node = find(tree, text)
        if node is not None:
            return node
        time.sleep(2)
    screenshot("unexpected-screen.png")
    raise RuntimeError(f"The car host did not display {text!r}; see screenshots/UI XML/logcat")


def tap(node):
    bounds = [int(x) for x in re.findall(r"\d+", node.attrib["bounds"])]
    assert len(bounds) == 4
    shell("input", "tap", str((bounds[0] + bounds[2]) // 2), str((bounds[1] + bounds[3]) // 2))


def mirror_switches(stream):
    with (output / "mqtt-traffic.log").open("w") as log:
        for line in stream:
            log.write(line)
            log.flush()
            topic, _, payload = line.rstrip("\n").partition("|")
            if re.fullmatch(r"/devices/preview/controls/K[1-4]/on", topic):
                subprocess.run(["mosquitto_pub", "-p", "18884", "-t", topic[:-3],
                                "-m", payload, "-r"], check=True)


try:
    assert Path("/dev/kvm").exists(), "KVM is required for this CI emulator harness"
    avd_home = root / "build/car-preview-avds"
    avd_home.mkdir(parents=True, exist_ok=True)
    os.environ["ANDROID_AVD_HOME"] = str(avd_home)
    avd_path = avd_home / "wiredash-car-preview.avd"
    run(str(sdk / "cmdline-tools/latest/bin/avdmanager"), "create", "avd", "--force",
        "--name", "wiredash-car-preview", "--package", image, "--path", str(avd_path), input=b"no\n")
    avd = avd_path / "config.ini"
    config = avd.read_text()
    for key, value in [("hw.lcd.width", 1280), ("hw.lcd.height", 720), ("hw.lcd.density", 160)]:
        config = re.sub(rf"^{re.escape(key)}=.*\n?", "", config, flags=re.MULTILINE)
        config += f"\n{key}={value}\n"
    avd.write_text(config)
    emulator_log = (output / "emulator.log").open("w")
    processes.append(subprocess.Popen([
        str(sdk / "emulator/emulator"), "-avd", "wiredash-car-preview", "-no-window",
        "-no-audio", "-no-snapshot", "-no-boot-anim", "-gpu", "swiftshader",
        "-memory", "2048", "-cores", "2", "-wipe-data", "-port", "5554",
    ], stdout=emulator_log, stderr=subprocess.STDOUT))
    run(adb, "wait-for-device", timeout=240)
    for _ in range(120):
        if shell("getprop", "sys.boot_completed") == "1":
            break
        time.sleep(2)
    else:
        raise RuntimeError("Automotive emulator did not finish booting")
    user = shell("am", "get-current-user")
    shell("settings", "put", "global", "device_provisioned", "1")
    shell("settings", "--user", user, "put", "secure", "user_setup_complete", "1")
    for setting in ["window_animation_scale", "transition_animation_scale", "animator_duration_scale"]:
        shell("settings", "put", "global", setting, "0")
    shell("input", "keyevent", "82")
    time.sleep(10)  # Automotive's foreground user unlocks after sys.boot_completed.
    screenshot("emulator-boot.png", optional=True)

    broker_config = output / "mosquitto.conf"
    broker_config.write_text("listener 18884 127.0.0.1\nallow_anonymous true\npersistence false\n")
    # Ubuntu confines Mosquitto's config access to /etc/mosquitto.
    installed_config = "/etc/mosquitto/wiredash-preview.conf"
    run("sudo", "install", "-m", "644", str(broker_config), installed_config)
    broker_log = (output / "broker.log").open("w")
    broker = subprocess.Popen(["mosquitto", "-c", installed_config, "-v"],
                              stdout=broker_log, stderr=subprocess.STDOUT)
    processes.append(broker)
    for _ in range(50):
        if broker.poll() is not None:
            raise RuntimeError((output / "broker.log").read_text())
        try:
            with socket.create_connection(("127.0.0.1", 18884), timeout=1):
                break
        except OSError:
            time.sleep(0.2)
    else:
        raise RuntimeError("Demo MQTT broker did not start: " + (output / "broker.log").read_text())
    watcher = subprocess.Popen(["mosquitto_sub", "-p", "18884", "-t", "/devices/preview/controls/#",
                                "-F", "%t|%p"], stdout=subprocess.PIPE, text=True)
    processes.append(watcher)
    threading.Thread(target=mirror_switches, args=(watcher.stdout,), daemon=True).start()
    for index in range(1, 5):
        run("mosquitto_pub", "-p", "18884", "-t", f"/devices/preview/controls/K{index}",
            "-m", "1" if index % 2 else "0", "-r")

    apk = root / "build/app/outputs/flutter-apk/app-x86_64-foss-debug.apk"
    run(adb, "install", "-r", str(apk), timeout=120)
    shell("run-as", package, "--user", user, "mkdir", "-p", "app_flutter")
    run(adb, "shell", f"run-as {package} --user {user} sh -c 'cat > app_flutter/zigdash.sqlite'",
        input=(output / "zigdash.sqlite").read_bytes())
    shell("am", "start", "--user", user, "-n", f"{package}/androidx.car.app.activity.CarAppActivity")
    tap(wait_text("My home", "catalog-ui.xml"))
    enter = wait_text("Enter", "dashboard-ui.xml")
    time.sleep(2)  # Allow the local MQTT connection to settle before capturing.
    screenshot("car-dashboard-top.png")
    tap(enter)
    screenshot("car-dashboard-spinner.png")
    time.sleep(2)
    width, height = [int(x) for x in re.findall(r"\d+", shell("wm", "size"))][-2:]
    for _ in range(2):
        shell("input", "swipe", str(width // 2), str(height * 4 // 5),
              str(width // 2), str(height // 4), "500")
        time.sleep(1)
    wait_text("Evening", "scrolled-ui.xml", seconds=30)
    screenshot("car-dashboard-scrolled.png")
    traffic = (output / "mqtt-traffic.log").read_text()
    assert "/devices/preview/controls/Curtain 1 Open/on|1" in traffic, traffic
    provenance = {
        "environment": "Android Automotive OS emulator / Google Automotive App Host",
        "projectedAndroidAuto": False,
        "systemImage": image, "resolution": [width, height], "androidUser": user,
        "sourceRevision": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        "fixture": "Isolated demo home, local Mosquitto broker, no user data",
        "carUiCodeChangedForHarness": False,
        "verified": ["dashboard opened in real template host", "direct gate command published",
                     "scroll reached the last control without paging"],
    }
    (output / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
finally:
    try:
        (output / "logcat.txt").write_bytes(subprocess.check_output([adb, "logcat", "-d"], timeout=30))
        (output / "host-packages.txt").write_text(shell("pm", "list", "packages", "-f"))
    except Exception as error:
        print("Could not collect all runtime logs:", error, flush=True)
    for process in reversed(processes):
        process.terminate()
