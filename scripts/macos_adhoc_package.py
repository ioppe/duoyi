#!/usr/bin/env python3
"""Prepare and verify the ad-hoc (team-less) macOS release package.

The published macOS build is intentionally unsigned by a Developer ID team, so
macOS treats it as an ad-hoc (``-``) build. The Xcode entitlements used for
developer builds include ``keychain-access-groups`` and
``$(AppIdentifierPrefix)``, which only a real team-signed build may carry.
On macOS 27 amfid rejects such a launch with Code=-424 while ``codesign``
verification still succeeds.

``prepare`` therefore re-signs only the outer ``.app`` with
``macos/Runner/AdHocRelease.entitlements`` (sandbox, network client, user
selected files only) and leaves every nested framework untouched. ``verify``
asserts the resulting package can actually be trusted to launch: ad-hoc
signature, no team identifier, universal binary, the exact three entitlements
and a sandbox plus classic-login-keychain fixture round trip.

``check-packages`` runs the real ZIP/DMG artifacts through that verification,
launches the ZIP application and checks the native keychain probe.

All commands print structured JSON and exit non-zero on a real problem.
"""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
ADHOC_ENTITLEMENTS = PROJECT_ROOT / "macos" / "Runner" / "AdHocRelease.entitlements"
SMOKE_SOURCE = PROJECT_ROOT / "test" / "native" / "macos_application_smoke.swift"

EXPECTED_BUNDLE_ID = "com.duoyi.duoyi"
EXPECTED_ENTITLEMENTS = {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.network.client": True,
    "com.apple.security.files.user-selected.read-write": True,
}
REQUIRED_ARCHITECTURES = ("arm64", "x86_64")

CODESIGN = "/usr/bin/codesign"
LIPO = "/usr/bin/lipo"
DITTO = "/usr/bin/ditto"
HDIUTIL = "/usr/bin/hdiutil"
OPEN = "/usr/bin/open"
SWIFTC = "/usr/bin/xcrun"

LAUNCH_TIMEOUT_SECONDS = 30
STABLE_LAUNCH_SECONDS = 3
POLL_INTERVAL_SECONDS = 0.5


class PackagingError(Exception):
    """A real packaging/verification failure with the checks collected so far."""

    def __init__(self, message: str, checks: list[dict] | None = None) -> None:
        super().__init__(message)
        self.checks = checks or []
        self.report: dict = {}


def require(condition: bool, message: str, checks: list[dict] | None = None) -> None:
    if not condition:
        raise PackagingError(message, checks)


def run(
    command: list[str],
    *,
    timeout: int = 120,
    cwd: Path | str | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
        cwd=cwd,
    )


# --------------------------------------------------------------------------- #
# Bundle and signature inspection
# --------------------------------------------------------------------------- #


def bundle_info(app: Path) -> dict:
    """Validate the bundle layout and return its identity and main executable."""
    require(app.is_dir() and app.suffix == ".app", f"not an .app bundle: {app}")
    info_path = app / "Contents" / "Info.plist"
    require(info_path.is_file(), f"missing Info.plist: {info_path}")
    try:
        info = plistlib.loads(info_path.read_bytes())
    except Exception as error:  # noqa: BLE001 - surfaced as a packaging failure
        raise PackagingError(f"unreadable Info.plist ({error}): {info_path}") from error
    require(isinstance(info, dict), f"Info.plist is not a dictionary: {info_path}")

    executable_name = info.get("CFBundleExecutable")
    require(
        isinstance(executable_name, str) and bool(executable_name),
        f"CFBundleExecutable missing in {info_path}",
    )
    executable = app / "Contents" / "MacOS" / executable_name
    require(executable.is_file(), f"missing main executable: {executable}")
    require(os.access(executable, os.X_OK), f"main executable lacks the exec bit: {executable}")

    bundle_id = info.get("CFBundleIdentifier")
    require(
        isinstance(bundle_id, str) and bool(bundle_id),
        f"CFBundleIdentifier missing in {info_path}",
    )
    return {
        "path": str(app),
        "name": app.name,
        "info": info,
        "executable": executable,
        "executable_name": executable_name,
        "bundle_id": bundle_id,
        "short_version": str(info.get("CFBundleShortVersionString", "")),
        "build_version": str(info.get("CFBundleVersion", "")),
    }


def signature_report(app: Path) -> dict:
    """Read the signing identity; unsigned bundles are reported, not raised."""
    result = run([CODESIGN, "--display", "--verbose=4", str(app)])
    text = f"{result.stdout}\n{result.stderr}"
    if result.returncode != 0:
        return {
            "signed": False,
            "adhoc": False,
            "team_identifier": "",
            "detail": text.strip(),
        }
    team = ""
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("TeamIdentifier="):
            team = stripped.split("=", 1)[1].strip()
    return {
        "signed": True,
        "adhoc": bool(re.search(r"Signature=adhoc", text)),
        "team_identifier": "" if team in {"", "not set"} else team,
        "detail": "Signature=adhoc" if "Signature=adhoc" in text else "",
    }


def _plist_from_output(raw: str) -> dict | None:
    start = raw.find("<?xml")
    if start < 0:
        start = raw.find("<plist")
    if start < 0:
        return None
    try:
        parsed = plistlib.loads(raw[start:].encode("utf-8"))
    except Exception:  # noqa: BLE001 - not a plist, try the next codesign form
        return None
    return parsed if isinstance(parsed, dict) else None


def _human_value(lines: list[str]) -> object:
    if lines == ["[Bool] true"]:
        return True
    if lines == ["[Bool] false"]:
        return False
    if len(lines) == 1 and lines[0].startswith("[String] "):
        return lines[0][len("[String] ") :]
    prefixes = ("[string] ", "[String] ")
    if lines and lines[0] == "[Array]" and all(
        line.startswith(prefixes) for line in lines[1:]
    ):
        return [line.split("] ", 1)[1] for line in lines[1:]]
    return None


def _dict_from_human_dump(raw: str) -> dict | None:
    """Parse the human readable ``[Dict]`` dump some codesign versions print."""
    lines = [line.strip() for line in raw.splitlines()]
    try:
        start = lines.index("[Dict]")
    except ValueError:
        return None
    parsed: dict = {}
    index = start + 1
    while index < len(lines):
        line = lines[index]
        index += 1
        if not line:
            continue
        if line == "[Dict]":  # end of this dump
            break
        if not line.startswith("[Key] "):
            return None
        key = line[len("[Key] ") :]
        if index >= len(lines) or lines[index] != "[Value]":
            return None
        index += 1
        value_lines: list[str] = []
        while (
            index < len(lines)
            and not lines[index].startswith("[Key] ")
            and lines[index] != "[Dict]"
        ):
            if lines[index]:
                value_lines.append(lines[index])
            index += 1
        value = _human_value(value_lines)
        if value is None:
            return None
        parsed[key] = value
    return parsed


def signed_entitlements(app: Path) -> dict:
    """Read the entitlements that are actually embedded in [app].

    ``codesign -d --entitlements :- <app>`` prints the XML plist on stdout and at
    most a notice on stderr, which is not a failure. The ``--xml`` form is
    deliberately avoided: on macOS 15/27 codesign treats ``--xml`` as the output
    path of ``--entitlements``, drops a stray file named ``--xml`` in the working
    directory and prints the human readable ``[Dict]`` dump. That dump is parsed
    explicitly instead of being ignored, and a real signing error is surfaced.
    """
    result = run(
        [CODESIGN, "-d", "--entitlements", ":-", str(app.resolve())],
        cwd=tempfile.gettempdir(),
    )
    parsed = _plist_from_output(result.stdout)
    if parsed is None:
        parsed = _dict_from_human_dump(result.stdout)
    if parsed is not None:
        return parsed
    detail = (result.stderr or result.stdout or "").strip()
    raise PackagingError(f"cannot read signed entitlements of {app}: {detail}")


def architectures(executable: Path) -> list[str]:
    result = run([LIPO, "-archs", str(executable)])
    require(
        result.returncode == 0,
        f"lipo -archs failed for {executable}: {result.stderr.strip()}",
    )
    return result.stdout.split()


def load_adhoc_entitlements(path: Path) -> dict:
    require(path.is_file(), f"missing entitlements file: {path}")
    try:
        parsed = plistlib.loads(path.read_bytes())
    except Exception as error:  # noqa: BLE001 - surfaced as a packaging failure
        raise PackagingError(f"unreadable entitlements file ({error}): {path}") from error
    require(
        parsed == EXPECTED_ENTITLEMENTS,
        f"{path} must contain exactly the ad-hoc entitlements "
        f"{sorted(EXPECTED_ENTITLEMENTS)}, found {sorted(parsed) if isinstance(parsed, dict) else parsed}",
    )
    return parsed


# --------------------------------------------------------------------------- #
# verify
# --------------------------------------------------------------------------- #


def verify(app: Path, *, expected_bundle_id: str = EXPECTED_BUNDLE_ID) -> dict:
    """Verify the outer app of an ad-hoc release package.

    Every check is recorded; the first aggregate failure raises so the CLI can
    exit non-zero even when ``codesign --verify`` alone would have passed.
    """
    checks: list[dict] = []
    failures: list[str] = []

    def record(name: str, detail: str, ok: bool = True) -> None:
        checks.append({"name": name, "ok": ok, "detail": detail})
        if not ok:
            failures.append(f"{name}: {detail}")

    try:
        info = bundle_info(app)
        record(
            "bundle-structure",
            f"{info['bundle_id']} {info['executable_name']} {info['short_version']}+{info['build_version']}",
        )
    except PackagingError as error:
        record("bundle-structure", str(error), False)
        raise PackagingError("; ".join(failures), checks) from error

    verify_result = run([CODESIGN, "--verify", "--deep", "--strict", "--verbose=2", str(app)])
    record(
        "codesign-deep-strict",
        "codesign --verify --deep --strict passed"
        if verify_result.returncode == 0
        else (verify_result.stderr or verify_result.stdout).strip(),
        verify_result.returncode == 0,
    )

    signature = signature_report(app)
    record(
        "adhoc-no-team",
        f"adhoc={signature['adhoc']} teamIdentifier={signature['team_identifier'] or '<none>'}",
        bool(signature["signed"] and signature["adhoc"] and not signature["team_identifier"]),
    )

    found_architectures: list[str] = []
    try:
        info = bundle_info(app)
        found_architectures = architectures(info["executable"])
        record(
            "universal-architecture",
            " ".join(found_architectures),
            set(REQUIRED_ARCHITECTURES) <= set(found_architectures),
        )
    except PackagingError as error:
        record("universal-architecture", str(error), False)

    record(
        "bundle-identifier",
        f"{info['bundle_id']}"
        if info["bundle_id"] == expected_bundle_id
        else f"expected {expected_bundle_id}, found {info['bundle_id']}",
        info["bundle_id"] == expected_bundle_id,
    )

    entitlements: dict = {}
    try:
        entitlements = signed_entitlements(app)
        record(
            "signed-entitlements",
            f"{sorted(entitlements)}",
            entitlements == EXPECTED_ENTITLEMENTS,
        )
    except PackagingError as error:
        record("signed-entitlements", str(error), False)

    if failures:
        raise PackagingError("; ".join(failures), checks)
    return {
        "app": str(app),
        "name": app.name,
        "bundleIdentifier": info["bundle_id"],
        "shortVersion": info["short_version"],
        "buildVersion": info["build_version"],
        "architectures": sorted(found_architectures),
        "entitlements": sorted(entitlements),
        "checks": checks,
    }


# --------------------------------------------------------------------------- #
# prepare
# --------------------------------------------------------------------------- #


def prepare(app: Path, entitlements_path: Path = ADHOC_ENTITLEMENTS) -> dict:
    """Re-sign only the outer app bundle with the ad-hoc release entitlements."""
    require(sys.platform == "darwin", "prepare requires macOS")
    entitlements = load_adhoc_entitlements(entitlements_path)
    info = bundle_info(app)
    require(
        info["bundle_id"] == EXPECTED_BUNDLE_ID,
        f"unexpected CFBundleIdentifier {info['bundle_id']}; macOS packaging keeps {EXPECTED_BUNDLE_ID}",
    )

    previous = signature_report(app)
    require(
        not previous["team_identifier"],
        f"refusing to downgrade a team-signed app to ad-hoc (TeamIdentifier={previous['team_identifier']})",
    )

    require(
        (app / "Contents" / "MacOS" / info["executable_name"]).is_file(),
        "main executable disappeared before signing",
    )

    result = run(
        [
            CODESIGN,
            "--force",
            "--sign",
            "-",
            "--timestamp=none",
            "--entitlements",
            str(entitlements_path),
            str(app),
        ]
    )
    require(
        result.returncode == 0,
        f"codesign failed for {app}: {(result.stderr or result.stdout).strip()}",
    )

    verified = verify(app)
    return {
        "app": str(app),
        "bundleIdentifier": info["bundle_id"],
        "entitlements": sorted(entitlements),
        "previousSignature": {
            "signed": previous["signed"],
            "adhoc": previous["adhoc"],
            "teamIdentifier": previous["team_identifier"],
        },
        "reSignedOnlyOuterBundle": True,
        "frameworksUntouched": True,
        "verify": verified,
    }


# --------------------------------------------------------------------------- #
# Native smoke helpers
# --------------------------------------------------------------------------- #


def compile_smoke(scratch: Path, source: Path = SMOKE_SOURCE) -> Path:
    require(source.is_file(), f"missing native smoke source: {source}")
    binary = scratch / "macos-application-smoke"
    result = run([SWIFTC, "swiftc", "-O", str(source), "-o", str(binary)], timeout=300)
    require(
        result.returncode == 0 and binary.is_file(),
        f"swiftc failed for {source}: {(result.stderr or result.stdout).strip()}",
    )
    return binary


def inspect_application(smoke_binary: Path, app: Path) -> list[dict]:
    result = run([str(smoke_binary), "inspect", str(app)], timeout=60)
    require(
        result.returncode == 0,
        f"native inspect failed for {app}: {(result.stderr or result.stdout).strip()}",
    )
    try:
        payload = json.loads(result.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError) as error:
        raise PackagingError(f"native inspect returned invalid JSON: {result.stdout!r}") from error
    return list(payload.get("applications") or [])


def _same_bundle(application: dict, app: Path) -> bool:
    reported = application.get("bundlePath") or ""
    if not reported:
        return False
    return Path(reported).resolve() == app.resolve()


def terminate_application(smoke_binary: Path, app: Path, pid: int) -> str:
    """Terminate exactly the process this run launched, never by app name."""
    matches = [entry for entry in inspect_application(smoke_binary, app) if entry.get("pid") == pid]
    if not matches:
        return "already-exited"
    require(
        _same_bundle(matches[0], app),
        f"refusing to terminate pid {pid}: bundle path {matches[0].get('bundlePath')} != {app}",
    )
    os.kill(pid, signal.SIGTERM)
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        remaining = [
            entry
            for entry in inspect_application(smoke_binary, app)
            if entry.get("pid") == pid and not entry.get("terminated")
        ]
        if not remaining:
            return "sigterm"
        time.sleep(POLL_INTERVAL_SECONDS)
    os.kill(pid, signal.SIGKILL)
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        remaining = [
            entry
            for entry in inspect_application(smoke_binary, app)
            if entry.get("pid") == pid and not entry.get("terminated")
        ]
        if not remaining:
            return "sigkill"
        time.sleep(POLL_INTERVAL_SECONDS)
    raise PackagingError(f"pid {pid} of {app} survived SIGKILL")


def smoke_launch(smoke_binary: Path, app: Path) -> dict:
    """Launch a new instance and clean it up even if startup observation fails."""
    existing = inspect_application(smoke_binary, app)
    require(
        not existing,
        f"refusing to launch {app}: {len(existing)} process(es) already running for this bundle",
    )
    observed_pids: set[int] = set()
    result: dict = {}
    try:
        open_result = run([OPEN, "-n", "-g", str(app)], timeout=60)
        require(
            open_result.returncode == 0,
            f"open -n -g failed for {app}: {open_result.stderr.strip()}",
        )
        deadline = time.monotonic() + LAUNCH_TIMEOUT_SECONDS
        record: dict | None = None
        polls = 0
        while time.monotonic() < deadline:
            polls += 1
            running = [
                entry for entry in inspect_application(smoke_binary, app)
                if not entry.get("terminated") and _same_bundle(entry, app)
            ]
            observed_pids.update(int(entry["pid"]) for entry in running)
            if running:
                record = running[0]
                if record.get("finishedLaunching") and int(record.get("windowCount") or 0) >= 1:
                    break
            time.sleep(POLL_INTERVAL_SECONDS)
        require(record is not None, f"{app} never appeared as a running application within {LAUNCH_TIMEOUT_SECONDS}s")
        pid = int(record["pid"])
        result.update({
            "pid": pid,
            "finishedLaunching": bool(record.get("finishedLaunching")),
            "windowCount": int(record.get("windowCount") or 0),
            "polls": polls,
            "stableSeconds": STABLE_LAUNCH_SECONDS,
        })
        require(result["finishedLaunching"], f"{app} (pid {pid}) never finished launching")
        require(result["windowCount"] >= 1, f"{app} (pid {pid}) created no window")
        time.sleep(STABLE_LAUNCH_SECONDS)
        stable = [
            entry for entry in inspect_application(smoke_binary, app)
            if entry.get("pid") == pid and not entry.get("terminated") and _same_bundle(entry, app)
        ]
        require(bool(stable), f"{app} (pid {pid}) exited within {STABLE_LAUNCH_SECONDS}s of launch")
        result["aliveAfterStableWindow"] = True
    finally:
        original_error = sys.exc_info()[1]
        cleanup_errors: list[str] = []
        try:
            latest = inspect_application(smoke_binary, app)
            observed_pids.update(
                int(entry["pid"]) for entry in latest
                if not entry.get("terminated") and _same_bundle(entry, app)
            )
        except (PackagingError, OSError, subprocess.SubprocessError) as error:
            cleanup_errors.append(f"final process inspection: {error}")
        for pid in sorted(observed_pids):
            try:
                result["termination"] = terminate_application(smoke_binary, app, pid)
            except (PackagingError, OSError, subprocess.SubprocessError) as error:
                cleanup_errors.append(f"pid {pid}: {error}")
        if cleanup_errors:
            detail = "launch cleanup failed: " + "; ".join(cleanup_errors)
            if original_error is not None:
                detail = f"{original_error}; {detail}"
            raise PackagingError(detail) from original_error
    return result


# --------------------------------------------------------------------------- #
# Native keychain probe
# --------------------------------------------------------------------------- #


def _write_plist(path: Path, payload: dict) -> None:
    path.write_bytes(plistlib.dumps(payload))
    path.chmod(0o644)


def build_keychain_fixture(scratch: Path, smoke_binary: Path) -> dict:
    """Create a throw-away sandbox fixture app with a brand new bundle id."""
    fixture_bundle_id = f"com.duoyi.duoyi.adhocprobe.{uuid.uuid4()}"
    fixture_root = scratch / "keychain-fixture"
    app = fixture_root / "DuoyiAdHocProbe.app"
    executable = app / "Contents" / "MacOS" / "DuoyiAdHocProbe"
    executable.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(smoke_binary, executable)
    _write_plist(
        app / "Contents" / "Info.plist",
        {
            "CFBundleName": "DuoyiAdHocProbe",
            "CFBundleDisplayName": "DuoyiAdHocProbe",
            "CFBundleIdentifier": fixture_bundle_id,
            "CFBundleExecutable": "DuoyiAdHocProbe",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "0.0.1",
            "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "11.0",
        },
    )
    entitlements_path = fixture_root / "Probe.entitlements"
    _write_plist(entitlements_path, EXPECTED_ENTITLEMENTS)
    result = run(
        [
            CODESIGN,
            "--force",
            "--sign",
            "-",
            "--timestamp=none",
            "--entitlements",
            str(entitlements_path),
            str(app),
        ]
    )
    require(
        result.returncode == 0,
        f"fixture codesign failed: {(result.stderr or result.stdout).strip()}",
    )
    signature = signature_report(app)
    require(
        signature["signed"] and signature["adhoc"] and not signature["team_identifier"],
        f"fixture must be ad-hoc without a team: {signature['detail']}",
    )
    require(
        signed_entitlements(app) == EXPECTED_ENTITLEMENTS,
        "fixture entitlements are not the three ad-hoc keys",
    )
    return {"app": app, "executable": executable, "bundleId": fixture_bundle_id}


def _run_keychain_phase(executable: Path, phase: str, service: str) -> dict:
    result = run([str(executable), "keychain", phase, service], timeout=60)
    require(
        result.returncode == 0,
        f"keychain {phase} process failed: {(result.stderr or result.stdout).strip()}",
    )
    try:
        payload = json.loads(result.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError) as error:
        raise PackagingError(f"keychain {phase} returned invalid JSON: {result.stdout!r}") from error
    require(
        payload.get("phase") == phase,
        f"keychain {phase} reported phase {payload.get('phase')!r}",
    )
    return payload


def keychain_round_trip(scratch: Path, smoke_binary: Path) -> dict:
    """Run write/read/delete in three processes against the classic keychain."""
    fixture = build_keychain_fixture(scratch, smoke_binary)
    service = f"com.duoyi.duoyi.adhocprobe.{uuid.uuid4()}"
    statuses: dict[str, int] = {}
    deleted = False
    try:
        write = _run_keychain_phase(fixture["executable"], "write", service)
        statuses["write"] = int(write.get("status", -1))
        require(
            statuses["write"] == 0,
            f"classic login keychain write failed with status {statuses['write']}",
        )
        read = _run_keychain_phase(fixture["executable"], "read", service)
        statuses["read"] = int(read.get("status", -1))
        require(
            statuses["read"] == 0 and read.get("roundTripMatched") is True,
            f"classic login keychain read failed with status {statuses['read']} "
            f"(roundTripMatched={read.get('roundTripMatched')})",
        )
        delete = _run_keychain_phase(fixture["executable"], "delete", service)
        statuses["delete"] = int(delete.get("status", -1))
        require(
            statuses["delete"] == 0,
            f"classic login keychain delete failed with status {statuses['delete']}",
        )
        deleted = True
    finally:
        original_error = sys.exc_info()[1]
        if not deleted:
            try:
                cleanup = _run_keychain_phase(fixture["executable"], "delete", service)
                require(
                    int(cleanup.get("status", -1)) in (0, -25300),
                    f"temporary keychain item cleanup failed: status {cleanup.get('status')}",
                )
            except (PackagingError, OSError, subprocess.SubprocessError) as error:
                detail = f"temporary keychain item cleanup failed: {error}"
                if original_error is not None:
                    detail = f"{original_error}; {detail}"
                raise PackagingError(detail) from original_error
    return {
        "dataProtectionKeychain": False,
        "fixtureBundleId": fixture["bundleId"],
        "separateProcesses": True,
        "writeStatus": statuses.get("write", -1),
        "readStatus": statuses.get("read", -1),
        "roundTripMatched": True,
        "deleteStatus": statuses.get("delete", -1),
        "realConfigurationTouched": False,
    }


# --------------------------------------------------------------------------- #
# check-packages
# --------------------------------------------------------------------------- #


def _single_app(directory: Path, label: str) -> Path:
    apps = sorted(path for path in directory.iterdir() if path.suffix == ".app")
    require(
        len(apps) == 1,
        f"expected exactly one .app in the {label} payload, found {len(apps)}: {[p.name for p in apps]}",
    )
    return apps[0]


def _attach_dmg(dmg: Path, mount_point: Path) -> None:
    result = run(
        [HDIUTIL, "attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", str(mount_point), str(dmg)],
        timeout=300,
    )
    require(
        result.returncode == 0,
        f"hdiutil attach failed for {dmg}: {(result.stderr or result.stdout).strip()}",
    )


def _detach_dmg(mount_point: Path) -> None:
    if not mount_point.is_dir():
        return
    result = run([HDIUTIL, "detach", str(mount_point), "-force"], timeout=180)
    require(
        result.returncode == 0,
        f"hdiutil detach failed for {mount_point}: {(result.stderr or result.stdout).strip()}",
    )


def check_packages(
    package_dir: Path,
    output: Path,
    *,
    work_dir: Path | None = None,
    smoke_source: Path = SMOKE_SOURCE,
) -> dict:
    require(sys.platform == "darwin", "check-packages requires macOS")
    require(package_dir.is_dir(), f"package directory does not exist: {package_dir}")
    zips = sorted(package_dir.glob("*.zip"))
    dmgs = sorted(package_dir.glob("*.dmg"))
    require(
        len(zips) == 1,
        f"expected exactly one .zip in {package_dir}, found {len(zips)}: {[p.name for p in zips]}",
    )
    require(
        len(dmgs) == 1,
        f"expected exactly one .dmg in {package_dir}, found {len(dmgs)}: {[p.name for p in dmgs]}",
    )
    zip_path, dmg_path = zips[0], dmgs[0]

    base = work_dir or Path(os.environ.get("RUNNER_TEMP") or tempfile.gettempdir())
    base.mkdir(parents=True, exist_ok=True)
    scratch = Path(tempfile.mkdtemp(prefix="duoyi-macos-check-", dir=str(base)))
    mount_point = scratch / "dmg-mount"
    mounted = False
    report: dict = {
        "command": "check-packages",
        "packageDirectory": str(package_dir),
        "packages": {"zip": zip_path.name, "dmg": dmg_path.name},
        "checks": [],
        "smoke": None,
        "keychain": None,
        "limits": {
            "fullFunctionalityVerified": False,
            "gatekeeperAssessment": "not required for an unsigned ad-hoc build",
            "developerIdNotarization": "not configured",
        },
    }
    try:
        smoke_binary = compile_smoke(scratch, smoke_source)

        zip_dir = scratch / "zip-payload"
        zip_dir.mkdir()
        extract = run([DITTO, "-x", "-k", str(zip_path), str(zip_dir)], timeout=600)
        require(
            extract.returncode == 0,
            f"ditto failed to expand {zip_path.name}: {(extract.stderr or extract.stdout).strip()}",
        )
        zip_app = _single_app(zip_dir, "zip")
        zip_report = verify(zip_app)
        report["zip"] = zip_report

        report["smoke"] = smoke_launch(smoke_binary, zip_app)
        report["keychain"] = keychain_round_trip(scratch, smoke_binary)

        mount_point.mkdir()
        _attach_dmg(dmg_path, mount_point)
        mounted = True
        dmg_app = _single_app(mount_point, "dmg")
        dmg_report = verify(dmg_app)
        report["dmg"] = dmg_report

        # The DMG copy is deliberately renamed (Duoyi.app -> 多仪.app) for the
        # installer volume, so bundle names may differ; every identity field and
        # the signed entitlements must not.
        report["zipAppName"] = zip_app.name
        report["dmgAppName"] = dmg_app.name
        for key in ("bundleIdentifier", "shortVersion", "buildVersion", "architectures", "entitlements"):
            require(
                zip_report[key] == dmg_report[key],
                f"ZIP and DMG differ on {key}: {zip_report[key]!r} != {dmg_report[key]!r}",
            )
        report["checks"].append(
            {
                "name": "zip-dmg-identity",
                "ok": True,
                "detail": f"{dmg_report['bundleIdentifier']} {dmg_report['shortVersion']}+{dmg_report['buildVersion']} "
                f"{' '.join(dmg_report['architectures'])} {sorted(dmg_report['entitlements'])}",
            }
        )
        report["ok"] = True
        return report
    except PackagingError as error:
        error.report = report  # keep partial ZIP/smoke/keychain diagnostics
        raise
    finally:
        original_error = sys.exc_info()[1]
        if mounted:
            try:
                _detach_dmg(mount_point)
            except (PackagingError, OSError, subprocess.SubprocessError) as error:
                detail = f"DMG cleanup failed: {error}"
                if original_error is not None:
                    detail = f"{original_error}; {detail}"
                failed_cleanup = PackagingError(detail)
                failed_cleanup.report = report
                raise failed_cleanup from original_error
        shutil.rmtree(scratch, ignore_errors=True)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #


def _write_report(output: Path, payload: dict) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")


def _emit(payload: dict) -> None:
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)

    prepare_parser = commands.add_parser("prepare", help="re-sign only the outer app for ad-hoc release")
    prepare_parser.add_argument("--app", required=True, type=Path)
    prepare_parser.add_argument("--entitlements", type=Path, default=ADHOC_ENTITLEMENTS)

    verify_parser = commands.add_parser("verify", help="verify an ad-hoc release app bundle")
    verify_parser.add_argument("--app", required=True, type=Path)
    verify_parser.add_argument("--bundle-id", default=EXPECTED_BUNDLE_ID)

    check_parser = commands.add_parser("check-packages", help="verify and smoke test real ZIP/DMG artifacts")
    check_parser.add_argument("--package-dir", required=True, type=Path)
    check_parser.add_argument("--output", required=True, type=Path)
    check_parser.add_argument("--work-dir", type=Path, default=None)
    check_parser.add_argument("--smoke-source", type=Path, default=SMOKE_SOURCE)

    args = parser.parse_args(argv)

    if args.command == "prepare":
        try:
            payload = {"command": "prepare", "ok": True, **prepare(args.app, args.entitlements)}
        except PackagingError as error:
            _emit({"command": "prepare", "ok": False, "app": str(args.app), "error": str(error), "checks": error.checks})
            return 1
        except (OSError, subprocess.SubprocessError) as error:
            _emit({"command": "prepare", "ok": False, "app": str(args.app), "error": str(error), "checks": []})
            return 1
        _emit(payload)
        return 0

    if args.command == "verify":
        try:
            payload = {"command": "verify", "ok": True, **verify(args.app, expected_bundle_id=args.bundle_id)}
        except PackagingError as error:
            _emit({"command": "verify", "ok": False, "app": str(args.app), "error": str(error), "checks": error.checks})
            return 1
        except (OSError, subprocess.SubprocessError) as error:
            _emit({"command": "verify", "ok": False, "app": str(args.app), "error": str(error), "checks": []})
            return 1
        _emit(payload)
        return 0

    try:
        report = check_packages(
            args.package_dir,
            args.output,
            work_dir=args.work_dir,
            smoke_source=args.smoke_source,
        )
    except PackagingError as error:
        failed = {
            **error.report,
            "command": "check-packages",
            "ok": False,
            "packageDirectory": str(args.package_dir),
            "error": str(error),
            "checks": error.checks or error.report.get("checks", []),
        }
        _write_report(args.output, failed)
        _emit(failed)
        return 1
    except (OSError, subprocess.SubprocessError) as error:
        failed = {
            "command": "check-packages",
            "ok": False,
            "packageDirectory": str(args.package_dir),
            "error": str(error),
            "checks": [],
        }
        _write_report(args.output, failed)
        _emit(failed)
        return 1

    _write_report(args.output, report)
    summary = {
        "command": "check-packages",
        "ok": report["ok"],
        "report": str(args.output),
        "smoke": report.get("smoke"),
        "keychain": report.get("keychain"),
    }
    _emit(summary)
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
