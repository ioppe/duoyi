#!/usr/bin/env python3
"""Bounded local Android loop: inspect devices, flutter run, hot reload/restart/stop."""
from __future__ import annotations

import argparse
import json
import os
import platform
import re
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import urlsplit

from project_config import PROJECT_ROOT, ConfigurationError, load_toolchain

DEFAULT_CONFIG = PROJECT_ROOT / "config/android-local.local.json"
RUN_HELPER = PROJECT_ROOT / "scripts/flutter_with_config.py"
PID_FILE = PROJECT_ROOT / "build/local-dev/flutter.pid"
LOCK_FILE = PROJECT_ROOT / "build/local-dev/launch.lock"
DEVICE_TIMEOUT = 30.0
PROCESS_TIMEOUT = 15.0
CONFIG_KEYS = ("flutter_bin", "sdk_root", "java_home", "device_id", "gradle_user_home", "flutter_storage_base_url")
CONTROL_SIGNALS = {"reload": "SIGUSR1", "restart": "SIGUSR2", "stop": "SIGINT"}


def load_local_config(path: Path, required: bool = False) -> dict[str, str]:
    if not path.is_file():
        if required:
            raise ConfigurationError(f"--config file not found: {path}; create that file, or drop --config to use the optional {DEFAULT_CONFIG.name}")
        return {}
    try:
        values = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise ConfigurationError(f"{path} must be readable JSON without comments") from error
    if not isinstance(values, dict):
        raise ConfigurationError(f"{path} must contain a JSON object")
    unknown = sorted(set(values) - set(CONFIG_KEYS))
    if unknown:
        raise ConfigurationError(f"{path} has unsupported keys: {', '.join(unknown)}; allowed: {', '.join(CONFIG_KEYS)}")
    for key, value in values.items():
        if not isinstance(value, str) or not value.strip():
            raise ConfigurationError(f"{path}: {key} must be a non-empty string")
    return {key: value.strip() for key, value in values.items()}


def pick(candidates: list[tuple[str, str | None]]) -> tuple[str | None, str]:
    for source, value in candidates:
        if value:
            return value, source
    return None, "unset"


def default_flutter(pinned: str) -> str:
    home = Path.home()
    base = "Library/Developer/duoyi" if platform.system() == "Darwin" else "Developer/duoyi"
    return str(home / base / f"flutter-{pinned}/bin/flutter")


def default_sdk() -> str:
    home = Path.home()
    return str(home / ("Library/Android/sdk" if platform.system() == "Darwin" else "Android/Sdk"))


def resolve_flutter(settings: dict[str, str], pinned: str) -> tuple[Path, str]:
    explicit, source = pick(
        [
            ("FLUTTER_BIN", os.environ.get("FLUTTER_BIN")),
            (DEFAULT_CONFIG.name, settings.get("flutter_bin")),
        ]
    )
    if explicit:
        binary = Path(explicit).expanduser()
        if not binary.is_file() or not os.access(binary, os.X_OK):
            raise ConfigurationError(f"Flutter executable from {source} is missing or not executable: {binary}; fix FLUTTER_BIN or flutter_bin in config/android-local.local.json")
        # Follow real symlinks so bin/cache/flutter.version.json is read from the install itself.
        return binary.resolve(), source
    for source, value in (("default pinned location", default_flutter(pinned)), ("PATH", shutil.which("flutter"))):
        if not value:
            continue
        binary = Path(value).expanduser()
        if binary.is_file() and os.access(binary, os.X_OK):
            return binary.resolve(), source
    raise ConfigurationError(f"Flutter executable not found; install the pinned {pinned} toolchain, put flutter on PATH, or set FLUTTER_BIN")


def check_flutter_version(flutter_bin: Path, pinned: str) -> str:
    metadata = flutter_bin.parent / "cache" / "flutter.version.json"
    if not metadata.is_file():
        raise ConfigurationError(f"Pinned version metadata missing at {metadata}; run '{flutter_bin} --version' once or point flutter_bin at the pinned {pinned} install")
    try:
        values = json.loads(metadata.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise ConfigurationError(f"Cannot read {metadata}") from error
    version = values.get("frameworkVersion") if isinstance(values, dict) else None
    if version != pinned:
        raise ConfigurationError(f"{flutter_bin} reports Flutter {version or 'unknown'}, but config/toolchain.json pins {pinned}; install the pinned toolchain instead of switching the project")
    return str(version)


def resolve_sdk(settings: dict[str, str]) -> tuple[Path, str]:
    value, source = pick(
        [
            ("ANDROID_SDK_ROOT", os.environ.get("ANDROID_SDK_ROOT")),
            ("ANDROID_HOME", os.environ.get("ANDROID_HOME")),
            (DEFAULT_CONFIG.name, settings.get("sdk_root")),
        ]
    )
    if not value:
        convention = Path(default_sdk()).expanduser()
        if not convention.is_dir():
            raise ConfigurationError("Android SDK location unknown; set ANDROID_SDK_ROOT/ANDROID_HOME or sdk_root in config/android-local.local.json")
        value, source = str(convention), "default location"
    root = Path(value).expanduser()
    if root.name == "platform-tools":
        raise ConfigurationError(f"SDK root from {source} points at platform-tools ({root}); use the full SDK root that contains platform-tools/")
    if not root.is_dir():
        raise ConfigurationError(f"Android SDK root from {source} does not exist: {root}; install the SDK or set sdk_root")
    if not (root / "platform-tools").is_dir():
        raise ConfigurationError(f"{root} is not a complete SDK root: platform-tools/ is missing; install SDK platform-tools")
    if not any((root / name).is_dir() for name in ("platforms", "emulator", "cmdline-tools", "system-images")):
        raise ConfigurationError(f"{root} only has platform-tools/; install build-tools/platforms via the official SDK manager")
    return root, source


def macos_java_home(pinned: str) -> str | None:
    helper = Path("/usr/libexec/java_home")
    if not helper.is_file():
        return None
    result = subprocess.run([str(helper), "-v", pinned], capture_output=True, text=True)
    return (result.stdout.strip() or None) if result.returncode == 0 else None


def java_major_version(home: Path) -> str:
    java = home / "bin/java"
    if not java.is_file():
        raise ConfigurationError(f"Java home {home} has no bin/java")
    javac = home / "bin/javac"
    if not javac.is_file() or not os.access(javac, os.X_OK):
        raise ConfigurationError(f"Java home {home} has no executable bin/javac; the Android toolchain needs a full JDK, not a runtime-only JRE")
    result = subprocess.run([str(java), "-version"], capture_output=True, text=True)
    match = re.search(r'version "(\d+)(?:\.(\d+))?', f"{result.stdout}\n{result.stderr}")
    if not match:
        raise ConfigurationError(f"Cannot determine the Java version of {java}")
    return match.group(2) if match.group(1) == "1" and match.group(2) else match.group(1)


def resolve_java(settings: dict[str, str], pinned: str) -> tuple[Path, str]:
    value, source = pick(
        [
            ("JAVA_HOME", os.environ.get("JAVA_HOME")),
            (DEFAULT_CONFIG.name, settings.get("java_home")),
        ]
    )
    detected = macos_java_home(pinned)
    if value:
        home, source = Path(value).expanduser(), source
    elif detected:
        home, source = Path(detected).expanduser(), "/usr/libexec/java_home"
    else:
        raise ConfigurationError(f"No Java {pinned} found; set JAVA_HOME or java_home in config/android-local.local.json")
    major = java_major_version(home)
    if major != pinned:
        hint = f"; /usr/libexec/java_home -v {pinned} reports {detected}" if detected and Path(detected).expanduser() != home else ""
        raise ConfigurationError(f"Java {major} at {home} (from {source}) does not match the pinned Java {pinned}{hint}; set JAVA_HOME or java_home")
    return home, source


def resolve_python() -> str:
    for candidate in (os.environ.get("PYTHON_BIN"), shutil.which("python3"), sys.executable):
        if candidate and Path(candidate).is_file():
            return candidate
    raise ConfigurationError("No python3 interpreter found for scripts/flutter_with_config.py")


def resolve_adb(settings: dict[str, str], sdk_root: Path) -> Path:
    explicit, source = pick([("ADB_BIN", os.environ.get("ADB_BIN"))])
    if explicit:
        binary = Path(explicit).expanduser()
        if not binary.is_file() or not os.access(binary, os.X_OK):
            raise ConfigurationError(f"adb from {source} is missing or not executable: {binary}; fix ADB_BIN or install SDK platform-tools")
        return binary
    for source, value in (("SDK platform-tools", sdk_root / "platform-tools/adb"), ("PATH", shutil.which("adb"))):
        binary = Path(value).expanduser() if value else None
        if binary is not None and binary.is_file() and os.access(binary, os.X_OK):
            return binary
    raise ConfigurationError(f"adb not found; expected {sdk_root}/platform-tools/adb or adb on PATH; install SDK platform-tools")


def resolve_gradle_user_home(settings: dict[str, str]) -> tuple[Path | None, str]:
    """Optional isolated Gradle home; its contents stay private and are never written here."""
    value, source = pick(
        [
            ("GRADLE_USER_HOME", os.environ.get("GRADLE_USER_HOME")),
            (DEFAULT_CONFIG.name, settings.get("gradle_user_home")),
        ]
    )
    if not value:
        return None, "unset"
    home = Path(value).expanduser()
    if not home.is_absolute():
        raise ConfigurationError(f"gradle_user_home from {source} must be an absolute directory after ~ expansion: {value}")
    if not home.is_dir():
        raise ConfigurationError(f"gradle_user_home from {source} is not an existing directory: {home}; create it outside the repository first")
    resolved = home.resolve()
    repository = PROJECT_ROOT.resolve()
    if resolved == repository or repository in resolved.parents:
        raise ConfigurationError(f"gradle_user_home from {source} is inside the repository ({resolved}); keep the isolated Gradle home outside the project so it stays private")
    return home, source


def resolve_flutter_storage_url(settings: dict[str, str]) -> tuple[str | None, str]:
    """Optional Flutter artifact mirror; validated so it cannot carry credentials or query data."""
    value, source = pick(
        [
            ("FLUTTER_STORAGE_BASE_URL", os.environ.get("FLUTTER_STORAGE_BASE_URL")),
            (DEFAULT_CONFIG.name, settings.get("flutter_storage_base_url")),
        ]
    )
    if not value:
        return None, "unset"
    parts = urlsplit(value)
    if parts.scheme != "https" or not parts.hostname or parts.username or parts.password or parts.query or parts.fragment:
        raise ConfigurationError(f"flutter_storage_base_url from {source} must be an https URL without credentials, query, or fragment")
    return value, source


def adb_devices(adb: Path) -> list[tuple[str, str, str]]:
    try:
        result = subprocess.run([str(adb), "devices", "-l"], capture_output=True, text=True, timeout=DEVICE_TIMEOUT)
    except subprocess.TimeoutExpired as error:
        raise ConfigurationError(f"'adb devices -l' did not answer within {DEVICE_TIMEOUT:.0f}s; check that the adb server and the target respond, then retry") from error
    if result.returncode != 0:
        raise ConfigurationError(f"'adb devices' failed: {(result.stderr or result.stdout).strip()}")
    entries = []
    for line in result.stdout.splitlines():
        fields = line.split()
        if len(fields) < 2 or line.startswith("List of devices") or fields[0].startswith("*"):
            continue
        entries.append((fields[0], fields[1], line.strip()))
    return entries


def describe_devices(entries: list[tuple[str, str, str]]) -> str:
    return "; ".join(f"{serial} ({state})" for serial, state, _ in entries) or "none"


def list_avds(sdk_root: Path) -> list[str]:
    emulator = sdk_root / "emulator/emulator"
    if not emulator.is_file():
        return []
    try:
        result = subprocess.run([str(emulator), "-list-avds"], capture_output=True, text=True, timeout=DEVICE_TIMEOUT)
    except subprocess.TimeoutExpired as error:
        raise ConfigurationError(f"'{emulator} -list-avds' did not answer within {DEVICE_TIMEOUT:.0f}s; inspect the emulator installation, then retry") from error
    if result.returncode != 0:
        return []
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def select_device(adb: Path, requested: str | None) -> str:
    entries = adb_devices(adb)
    if requested:
        for serial, state, _ in entries:
            if serial == requested:
                if state != "device":
                    raise ConfigurationError(f"Device {requested} is '{state}', not 'device'; unlock it and accept the USB debugging prompt (attached: {describe_devices(entries)})")
                return requested
        raise ConfigurationError(f"Requested device {requested} is not attached; run 'python3 scripts/android_local_dev.py devices' (attached: {describe_devices(entries)})")
    ready = [serial for serial, state, _ in entries if state == "device"]
    if len(ready) == 1:
        return ready[0]
    if len(ready) > 1:
        raise ConfigurationError("Several Android targets are ready (" + ", ".join(ready) + "); pass --device SERIAL instead of letting the wrapper choose")
    if not entries:
        raise ConfigurationError("No Android device or emulator attached; start the official Android Emulator AVD or connect a phone with USB debugging, then retry")
    raise ConfigurationError("No Android target is ready (" + describe_devices(entries) + "); authorize the USB debugging prompt or reboot an offline emulator")


def read_pid(pid_file: Path = PID_FILE) -> int | None:
    try:
        raw = pid_file.read_text(encoding="utf-8").strip()
    except OSError:
        return None
    if not raw.isdigit():
        return None
    pid = int(raw)
    return pid if pid > 1 else None


def process_command(pid: int) -> str | None:
    if os.name != "posix":
        raise ConfigurationError("Live session control requires macOS or Linux; this platform cannot signal a Flutter run session")
    try:
        os.kill(pid, 0)
    except (ProcessLookupError, PermissionError):
        return None
    try:
        result = subprocess.run(["ps", "-p", str(pid), "-o", "command="], capture_output=True, text=True, timeout=PROCESS_TIMEOUT)
    except subprocess.TimeoutExpired as error:
        raise ConfigurationError(f"'ps -p {pid}' did not answer within {PROCESS_TIMEOUT:.0f}s; verify the recorded session manually before signalling or stopping it") from error
    if result.returncode != 0:
        return None
    return result.stdout.strip() or None


def verified_flutter_pid(pid_file: Path = PID_FILE) -> int | None:
    """Return the recorded PID only when it is a live Flutter run session for this workspace."""
    pid = read_pid(pid_file)
    if pid is None or pid == os.getpid():
        return None
    command = process_command(pid)
    if not command or str(pid_file) not in command:
        return None
    if "flutter_tools.snapshot" in command or re.search(r"/flutter(?:\.bat)?\s+run\b", command):
        return pid
    return None


def release_pid_file(pid_file: Path, pid: int) -> None:
    if pid <= 1:
        return
    try:
        if pid_file.read_text(encoding="utf-8").strip() == str(pid):
            pid_file.unlink()
    except OSError:
        return


def wait_until_gone(pid: int, timeout: float) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process_command(pid) is None:
            return True
        time.sleep(0.2)
    return process_command(pid) is None


def control(name: str, pid_file: Path = PID_FILE) -> int:
    pid = verified_flutter_pid(pid_file)
    if pid is None:
        raise ConfigurationError(f"No verified Flutter run session is recorded in {pid_file}; start one with 'run' first (no signal was sent)")
    signal_name = CONTROL_SIGNALS[name]
    try:
        os.kill(pid, getattr(signal, signal_name))
    except ProcessLookupError as error:
        raise ConfigurationError(f"Flutter session {pid} already exited; no signal was sent") from error
    print(f"Sent {signal_name} to Flutter run session {pid}")
    if name != "stop":
        return 0
    if not wait_until_gone(pid, 15.0):
        raise ConfigurationError(f"Flutter session {pid} is still running after SIGINT; inspect it before doing anything else (pid file kept)")
    release_pid_file(pid_file, pid)
    print("Flutter run session stopped")
    return 0


def run_command(python: str, flutter_bin: Path, device: str, apk: Path | None) -> list[str]:
    command = [python, str(RUN_HELPER), "--flutter-bin", str(flutter_bin), "run", "-d", device, "--pid-file", str(PID_FILE)]
    if apk is not None:
        command += ["--use-application-binary", str(apk)]
    return command


def scoped_environment(
    flutter_bin: Path,
    sdk_root: Path,
    java_home: Path,
    gradle_user_home: Path | None = None,
    storage_url: str | None = None,
) -> dict[str, str]:
    """Add these values for the child only; never write global Flutter, Gradle, or shell config."""
    environment = dict(os.environ)
    environment["FLUTTER_BIN"] = str(flutter_bin)
    environment["JAVA_HOME"] = str(java_home)
    environment["ANDROID_SDK_ROOT"] = environment["ANDROID_HOME"] = str(sdk_root)
    if gradle_user_home is not None:
        environment["GRADLE_USER_HOME"] = str(gradle_user_home)
    if storage_url is not None:
        environment["FLUTTER_STORAGE_BASE_URL"] = storage_url
    entries = [
        str(java_home / "bin"),
        str(sdk_root / "platform-tools"),
        str(sdk_root / "emulator"),
        str(sdk_root / "cmdline-tools/latest/bin"),
    ]
    environment["PATH"] = os.pathsep.join([*entries, environment.get("PATH", "")]).rstrip(os.pathsep)
    return environment


def launch(
    python: str,
    flutter_bin: Path,
    sdk_root: Path,
    java_home: Path,
    gradle_user_home: Path | None,
    storage_url: str | None,
    device: str,
    apk: Path | None,
    dry_run: bool,
) -> int:
    if apk is not None and not apk.is_file():
        raise ConfigurationError(f"--apk file not found: {apk}")
    active = verified_flutter_pid()
    command = run_command(python, flutter_bin, device, apk)
    if dry_run:
        print(
            json.dumps(
                {
                    "command": command,
                    "flutter_bin": str(flutter_bin),
                    "sdk_root": str(sdk_root),
                    "java_home": str(java_home),
                    "gradle_user_home": str(gradle_user_home) if gradle_user_home else None,
                    "flutter_storage_base_url": storage_url,
                    "device": device,
                    "apk": str(apk) if apk else None,
                    "pid_file": str(PID_FILE),
                    "active_session": active,
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return 0
    if os.name != "posix":
        raise ConfigurationError("Starting a Flutter session needs POSIX flock and signals (macOS or Linux); this platform is unsupported, while devices and doctor stay read-only")
    PID_FILE.parent.mkdir(parents=True, exist_ok=True)
    environment = scoped_environment(flutter_bin, sdk_root, java_home, gradle_user_home, storage_url)
    import fcntl

    # The lock file stays on disk on purpose: unlinking it would let a second launcher lock a fresh inode.
    with LOCK_FILE.open("a+", encoding="utf-8") as lock:
        try:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            raise ConfigurationError(f"Another local Android launch already holds {LOCK_FILE}; wait for it to finish or stop that session first (nothing was launched)") from error
        active = verified_flutter_pid()
        if active is not None:
            raise ConfigurationError(f"A Flutter run session (pid {active}) already owns {PID_FILE}; use reload/restart/stop or exit it first (nothing was launched)")
        try:
            return subprocess.run(command, cwd=PROJECT_ROOT, env=environment).returncode
        except KeyboardInterrupt:
            pid = read_pid()
            if pid is not None and wait_until_gone(pid, 15.0):
                release_pid_file(PID_FILE, pid)
            return 130


def command_devices(settings: dict[str, str]) -> int:
    sdk_root = resolve_sdk(settings)[0]
    adb = resolve_adb(settings, sdk_root)
    entries = adb_devices(adb)
    for _, _, line in entries:
        print(line)
    print(f"Attached Android targets: {describe_devices(entries)}")
    ready = [serial for serial, state, _ in entries if state == "device"]
    if len(ready) == 1:
        print(f"Only ready target: {ready[0]} (run will use it unless --device is given)")
    elif ready:
        print("Several ready targets; pass --device SERIAL to choose one.")
    else:
        print("No target in state 'device'; authorize the USB debugging prompt or start an emulator.")
    avds = list_avds(sdk_root)
    if avds:
        print("Available AVDs: " + ", ".join(avds))
        print(f"Start one manually first: {sdk_root}/emulator/emulator -avd {avds[0]}")
    elif (sdk_root / "emulator/emulator").is_file():
        print("No AVD installed yet; create one with the official Android Studio Device Manager or avdmanager.")
    return 0


def command_doctor(settings: dict[str, str], requested: str | None) -> int:
    toolchain = load_toolchain()
    pinned_flutter, pinned_java = toolchain["flutter"], toolchain["java"]
    failures = 0

    def report(label: str, action) -> object | None:
        nonlocal failures
        try:
            value = action()
        except ConfigurationError as error:
            failures += 1
            print(f"[fail] {label}: {error}")
            return None
        print(f"[ok] {label}: {value if value is not None else 'ok'}")
        return value

    flutter_bin = report("Flutter executable", lambda: resolve_flutter(settings, pinned_flutter)[0])
    if flutter_bin is not None:
        report(f"Flutter {pinned_flutter}", lambda: check_flutter_version(flutter_bin, pinned_flutter))
    sdk_root = report("Android SDK root", lambda: resolve_sdk(settings)[0])
    adb = report("adb", lambda: resolve_adb(settings, sdk_root)) if sdk_root is not None else None
    if sdk_root is None:
        print("[skip] adb: no usable SDK root yet, so platform-tools cannot be checked here")
    report(f"Java {pinned_java}", lambda: resolve_java(settings, pinned_java)[0])
    for label, resolver in (
        ("Gradle user home", lambda: resolve_gradle_user_home(settings)),
        ("Flutter storage base URL", lambda: resolve_flutter_storage_url(settings)),
    ):
        try:
            value, source = resolver()
        except ConfigurationError as error:
            failures += 1
            print(f"[fail] {label}: {error}")
            continue
        print(f"[info] {label}: {'unset' if value is None else f'{value} (from {source})'}")
    if sdk_root is not None:
        try:
            avds = list_avds(sdk_root)
        except ConfigurationError as error:
            print(f"[warn] AVDs: {error}")
        else:
            if avds:
                print(f"[ok] AVDs: {', '.join(avds)}")
            else:
                print("[warn] AVDs: none detected; create one in the official Device Manager or use a USB phone")
    device = report("Android target", lambda: select_device(adb, requested)) if adb is not None else None
    try:
        pid = verified_flutter_pid()
    except ConfigurationError as error:
        pid = None
        print(f"[warn] Flutter run session: {error}")
    else:
        print(f"[info] Flutter run session: {'pid ' + str(pid) if pid else 'none recorded in ' + str(PID_FILE)}")
    if failures:
        print("Local Android loop is not ready; fix the [fail] lines above.")
        return 1
    print(f"Ready. Next: python3 scripts/android_local_dev.py run --device {device}")
    return 0


def command_run(settings: dict[str, str], args: argparse.Namespace, toolchain: dict[str, str]) -> int:
    flutter_bin = resolve_flutter(settings, toolchain["flutter"])[0]
    check_flutter_version(flutter_bin, toolchain["flutter"])
    sdk_root = resolve_sdk(settings)[0]
    java_home = resolve_java(settings, toolchain["java"])[0]
    adb = resolve_adb(settings, sdk_root)
    gradle_user_home = resolve_gradle_user_home(settings)[0]
    storage_url = resolve_flutter_storage_url(settings)[0]
    if not RUN_HELPER.is_file():
        raise ConfigurationError(f"Missing helper {RUN_HELPER}")
    device = select_device(adb, args.device or settings.get("device_id"))
    apk = args.apk.expanduser().resolve() if args.apk else None
    return launch(
        resolve_python(),
        flutter_bin,
        sdk_root,
        java_home,
        gradle_user_home,
        storage_url,
        device,
        apk,
        getattr(args, "dry_run", False),
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="Private machine config; must exist when given, defaults to the optional config/android-local.local.json")
    parser.add_argument("--device", help="Serial from 'adb devices'; defaults to the single ready target")
    parser.add_argument("--dry-run", action="store_true", help="With run: validate and print the command without launching or signalling")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("devices", help="List attached Android targets and installed AVDs")
    doctor = subparsers.add_parser("doctor", aliases=["status"], help="Check toolchain, SDK, Java, and target readiness")
    run = subparsers.add_parser("run", help="Start flutter run with the public defines and a pid file")
    run.add_argument("--apk", type=Path, help="Reuse an existing debug APK via --use-application-binary")
    for name, help_text in (
        ("reload", "Send SIGUSR1 (hot reload) to the recorded session"),
        ("restart", "Send SIGUSR2 (hot restart) to the recorded session"),
        ("stop", "Send SIGINT and wait for the recorded session to exit"),
    ):
        subparsers.add_parser(name, help=help_text)
    for child in (doctor, run):
        child.add_argument("--device", default=argparse.SUPPRESS)
    run.add_argument("--dry-run", action="store_true", default=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    config_path = args.config.expanduser() if args.config else DEFAULT_CONFIG
    try:
        settings = load_local_config(config_path, required=args.config is not None)
        toolchain = load_toolchain()
        if args.command == "devices":
            return command_devices(settings)
        if args.command in {"doctor", "status"}:
            return command_doctor(settings, args.device or settings.get("device_id"))
        if args.command == "run":
            return command_run(settings, args, toolchain)
        return control(args.command)
    except (ConfigurationError, OSError) as error:
        print(f"Configuration error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
