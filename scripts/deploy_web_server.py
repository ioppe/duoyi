#!/usr/bin/env python3
"""Restricted Web release publisher for the duoyi self-hosted site.

Installed as root:root 0755 ``/usr/local/sbin/duoyi-web-deploy`` and exposed to
one SSH key through ``authorized_keys`` with a forced command.  The only input
from the SSH client is ``SSH_ORIGINAL_COMMAND``:

    status
    deploy <40-char lowercase hex commit> <64-char lowercase hex sha256>

The archive itself is read from stdin as tar.gz.  This program never runs a
shell, never accepts a path/URL/command from the client, never writes outside
``releases_root`` and never touches the backend, database, Nginx config or old
releases.  Site changes are a single symlink swap; any failed verification
restores the previous symlink and exits non-zero.

Standard library only (Python 3.12+); no repository modules are imported.
"""

from __future__ import annotations

import fcntl
import hashlib
import json
import logging
import os
import re
import shutil
import signal
import ssl
import sys
import tarfile
import tempfile
import time
import urllib.request
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

CONFIG_PATH = Path("/etc/duoyi/web-deploy.json")
LOCK_PATH = Path("/run/lock/duoyi-web-deploy.lock")
MANIFEST_NAME = "duoyi-deployment.json"
PAYLOAD_NAME = ".payload.tar.gz"
MAX_ARCHIVE_BYTES = 512 * 1024 * 1024
MAX_EXTRACT_BYTES = 2 * 1024 * 1024 * 1024
MAX_MEMBERS = 20000
REQUIRED_FILES = ("index.html", "main.dart.js", "version.json")
SHA_RE = re.compile(r"\A[0-9a-f]{40}\Z")
ARCHIVE_RE = re.compile(r"\A[0-9a-f]{64}\Z")
BASE_HREF_RE = re.compile(r"""<base\s[^>]*href\s*=\s*["']/["']""", re.IGNORECASE)
HEALTH_ATTEMPTS = 3
HEALTH_TIMEOUT = 10

LOG = logging.getLogger("duoyi-web-deploy")


class DeployError(Exception):
    """Rejected input or failed verification; the site is left consistent."""


def _absolute_path(value: object, name: str) -> Path:
    if not isinstance(value, str) or not value.startswith("/"):
        raise DeployError(f"{name} must be an absolute path")
    if "\x00" in value or " " in value or "\\" in value:
        raise DeployError(f"{name} contains unsupported characters")
    parts = [part for part in value.split("/") if part]
    if any(part in (".", "..") for part in parts):
        raise DeployError(f"{name} must not contain '.' or '..'")
    if not parts:
        raise DeployError(f"{name} must not be '/'")
    normalized = "/" + "/".join(parts)
    if normalized != value.rstrip("/"):
        raise DeployError(f"{name} is not normalized")
    return Path(normalized)


@dataclass(frozen=True)
class Config:
    """Public server profile installed by the operator at CONFIG_PATH."""

    host: str
    port: int
    user: str
    branch: str
    public_url: str
    web_root: Path
    releases_root: Path

    @classmethod
    def load(cls, path: Path = CONFIG_PATH) -> "Config":
        try:
            data = json.loads(Path(path).read_text(encoding="utf-8"))
        except OSError as exc:
            raise DeployError(f"cannot read profile {path}: {exc.strerror}") from exc
        except json.JSONDecodeError as exc:
            raise DeployError(f"profile {path} is not valid JSON") from exc
        if not isinstance(data, dict):
            raise DeployError("profile must be a JSON object")
        host = data.get("host")
        if not isinstance(host, str) or not host or host.startswith("-"):
            raise DeployError("profile host is invalid")
        port = data.get("port")
        if not isinstance(port, int) or isinstance(port, bool) or not 1 <= port <= 65535:
            raise DeployError("profile port is invalid")
        user = data.get("user")
        if not isinstance(user, str) or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.-]*", user):
            raise DeployError("profile user is invalid")
        public_url = data.get("public_url")
        if not isinstance(public_url, str) or not public_url.startswith("https://"):
            raise DeployError("profile public_url must be https")
        if any(char in public_url for char in " \t\r\n") or "@" in public_url.split("/")[2]:
            raise DeployError("profile public_url must not embed credentials")
        branch = data.get("branch")
        if not isinstance(branch, str) or not branch:
            raise DeployError("profile branch is invalid")
        web_root = _absolute_path(data.get("web_root"), "web_root")
        releases_root = _absolute_path(data.get("releases_root"), "releases_root")
        if web_root == releases_root:
            raise DeployError("web_root and releases_root must differ")
        return cls(
            host=host,
            port=port,
            user=user,
            branch=branch,
            public_url=public_url.rstrip("/"),
            web_root=web_root,
            releases_root=releases_root,
        )


def parse_command(raw: str | None) -> tuple[str, ...]:
    """Accept exactly ``status`` or ``deploy <sha40> <sha256-64>``."""
    if raw is None or not isinstance(raw, str):
        raise DeployError("missing SSH_ORIGINAL_COMMAND")
    command = raw.strip()
    if command == "status":
        return ("status",)
    parts = command.split()
    if (
        len(parts) == 3
        and parts[0] == "deploy"
        and SHA_RE.match(parts[1])
        and ARCHIVE_RE.match(parts[2])
    ):
        return ("deploy", parts[1], parts[2])
    raise DeployError(
        "unsupported command; expected 'status' or "
        "'deploy <40-hex-commit> <64-hex-sha256>'"
    )


def _inside(root: Path, candidate: Path) -> bool:
    root_text = os.path.normpath(str(root))
    candidate_text = os.path.normpath(str(candidate))
    if candidate_text == root_text:
        return False
    try:
        return os.path.commonpath([root_text, candidate_text]) == root_text
    except ValueError:
        return False


def _member_path(name: str) -> Path | None:
    """Map a tar member name into a safe relative path; reject escapes/types."""
    if not name or name.startswith("/") or "\\" in name or "\x00" in name:
        raise DeployError("tar member has an unsafe absolute or encoded path")
    parts = []
    for part in name.split("/"):
        if part in ("", "."):
            continue
        if part == "..":
            raise DeployError("tar member escapes the release directory")
        parts.append(part)
    if not parts:
        return None  # normal "./" root entry produced by `tar -C dir .`
    return Path(*parts)


@contextmanager
def interrupt_guard():
    """Turn SIGTERM/SIGHUP into DeployError so deploy() can roll back safely."""
    previous = {}

    def _interrupt(signum, _frame):
        raise DeployError(f"deployment interrupted by signal {signum}")

    for signum in (signal.SIGTERM, signal.SIGHUP):
        previous[signum] = signal.signal(signum, _interrupt)
    try:
        yield
    finally:
        for signum, handler in previous.items():
            signal.signal(signum, handler)


class Publisher:
    """Publish, verify and roll back one Web release under ``releases_root``."""

    def __init__(
        self,
        config: Config,
        lock_path: Path = LOCK_PATH,
        healthcheck=None,
    ):
        self.config = config
        self.lock_path = Path(lock_path)
        self.healthcheck = healthcheck or https_healthcheck

    # -- shared helpers ----------------------------------------------------
    @contextmanager
    def _exclusive(self):
        self.lock_path.parent.mkdir(parents=True, exist_ok=True)
        with open(self.lock_path, "a+", encoding="utf-8") as handle:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(handle.fileno(), fcntl.LOCK_UN)

    def _releases_root(self) -> Path:
        root = self.config.releases_root
        if root.is_symlink() or not root.is_dir():
            raise DeployError(f"releases_root {root} must be a real directory")
        return root

    def _current(self, root: Path) -> Path:
        link = self.config.web_root
        if not link.is_symlink():
            raise DeployError(f"web_root {link} must be a symlink, not a directory")
        raw_target = os.readlink(link)
        target = Path(raw_target)
        if not target.is_absolute():
            target = Path(os.path.normpath(str(link.parent / target)))
        if not _inside(root, target):
            raise DeployError("current symlink points outside releases_root")
        if target.is_symlink() or not target.is_dir():
            raise DeployError("current symlink target is not a real release directory")
        return target

    # -- read-only status --------------------------------------------------
    def status(self) -> dict:
        root = self._releases_root()
        target = self._current(root)
        info = {
            "ok": True,
            "web_root": str(self.config.web_root),
            "releases_root": str(root),
            "current": str(target),
        }
        manifest_path = target / MANIFEST_NAME
        if manifest_path.is_file():
            try:
                manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                raise DeployError("current manifest is unreadable")
            if isinstance(manifest, dict):
                for key in (
                    "commit",
                    "archive_sha256",
                    "version",
                    "build",
                    "deployed_at",
                ):
                    if key in manifest:
                        info[key] = manifest[key]
        return info

    # -- deploy ------------------------------------------------------------
    def deploy(self, sha: str, archive_hash: str, stream) -> dict:
        if not isinstance(sha, str) or not SHA_RE.match(sha):
            raise DeployError("commit must be 40 lowercase hex characters")
        if not isinstance(archive_hash, str) or not ARCHIVE_RE.match(archive_hash):
            raise DeployError("archive sha256 must be 64 lowercase hex characters")
        with interrupt_guard(), self._exclusive():
            root = self._releases_root()
            old_target = self._current(root)
            final = root / f"{sha}-{archive_hash[:12]}"
            created = False
            if final.is_symlink() or final.exists():
                self._verify_existing(final, sha, archive_hash)
            else:
                stage = Path(tempfile.mkdtemp(prefix=".stage-", dir=root))
                try:
                    archive_path = stage / PAYLOAD_NAME
                    actual_hash = self._spool(stream, archive_path)
                    if actual_hash != archive_hash:
                        raise DeployError("archive sha256 mismatch; site is unchanged")
                    self._extract(archive_path, stage)
                    archive_path.unlink()
                    version, build = self._validate_tree(stage)
                    self._write_manifest(stage, sha, archive_hash, version, build)
                    stage.rename(final)
                    created = True
                except BaseException:
                    shutil.rmtree(stage, ignore_errors=True)
                    raise
            try:
                manifest = json.loads(
                    (final / MANIFEST_NAME).read_text(encoding="utf-8")
                )
                self._switch(final)
                self.healthcheck(self.config, sha, archive_hash)
            except BaseException:
                try:
                    self._switch(old_target)
                finally:
                    if created and final != old_target:
                        shutil.rmtree(final, ignore_errors=True)
                raise
            LOG.info(
                "deployed commit=%s archive=%s version=%s build=%s release=%s",
                sha,
                archive_hash[:12],
                manifest.get("version"),
                manifest.get("build"),
                final.name,
            )
            return manifest

    def _spool(self, stream, archive_path: Path) -> str:
        digest = hashlib.sha256()
        total = 0
        with open(archive_path, "xb") as handle:
            while True:
                chunk = stream.read(1024 * 1024)
                if not chunk:
                    break
                total += len(chunk)
                if total > MAX_ARCHIVE_BYTES:
                    raise DeployError("archive exceeds the compressed size limit")
                digest.update(chunk)
                handle.write(chunk)
        if total == 0:
            raise DeployError("archive stdin is empty")
        return digest.hexdigest()

    def _extract(self, archive_path: Path, stage: Path) -> None:
        members = 0
        unpacked = 0
        with tarfile.open(archive_path, mode="r:gz") as archive:
            for member in archive:
                members += 1
                if members > MAX_MEMBERS:
                    raise DeployError("archive contains too many members")
                relative = _member_path(member.name)
                if relative is None:
                    continue
                if relative.parts in ((PAYLOAD_NAME,), (MANIFEST_NAME,)):
                    raise DeployError("archive uses a reserved release file name")
                target = stage / relative
                if not _inside(stage, target):
                    raise DeployError("tar member escapes the release directory")
                if member.isdir():
                    if target.exists() and not target.is_dir():
                        raise DeployError("archive contains conflicting paths")
                    try:
                        target.mkdir(parents=True, exist_ok=True)
                    except (NotADirectoryError, FileExistsError, IsADirectoryError) as exc:
                        raise DeployError("archive contains conflicting paths") from exc
                    continue
                if not member.isfile():
                    raise DeployError(
                        "archive contains a non-regular member (link/device/fifo)"
                    )
                unpacked += member.size
                if member.size < 0 or unpacked > MAX_EXTRACT_BYTES:
                    raise DeployError("archive exceeds the extracted size limit")
                if target.exists() or target.is_symlink():
                    raise DeployError("archive contains duplicate members")
                try:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    source = archive.extractfile(member)
                    if source is None:
                        raise DeployError("archive member cannot be read")
                    with source, open(target, "xb") as handle:
                        shutil.copyfileobj(source, handle, 1024 * 1024)
                except (NotADirectoryError, FileExistsError, IsADirectoryError) as exc:
                    raise DeployError("archive contains conflicting paths") from exc
                os.chmod(target, 0o644)

    def _validate_tree(self, stage: Path) -> tuple[str, str]:
        for name in REQUIRED_FILES:
            path = stage / name
            if path.is_symlink() or not path.is_file():
                raise DeployError(f"release is missing required file {name}")
        index_text = (stage / "index.html").read_text(
            encoding="utf-8", errors="replace"
        )[: 512 * 1024]
        if not BASE_HREF_RE.search(index_text):
            raise DeployError("index.html must use the site root base href '/'")
        try:
            version_data = json.loads(
                (stage / "version.json").read_text(encoding="utf-8")
            )
        except (OSError, json.JSONDecodeError) as exc:
            raise DeployError("version.json is not valid JSON") from exc
        if not isinstance(version_data, dict):
            raise DeployError("version.json must be a JSON object")
        version = str(version_data.get("version", "")).strip()
        build_value = version_data.get("build_number")
        if build_value in (None, ""):
            # Historic artifacts used "build"; current Flutter output uses build_number.
            build_value = version_data.get("build", "")
        build = str(build_value).strip()
        if not version or not build:
            raise DeployError(
                "version.json must contain version and build_number values"
            )
        for path in sorted(stage.rglob("*"), reverse=True):
            if path.is_symlink():
                raise DeployError("release must not contain symlinks")
            os.chmod(path, 0o755 if path.is_dir() else 0o644)
        os.chmod(stage, 0o755)
        return version, build

    def _write_manifest(
        self, stage: Path, sha: str, archive_hash: str, version: str, build: str
    ) -> None:
        manifest = {
            "commit": sha,
            "archive_sha256": archive_hash,
            "version": version,
            "build": build,
            "deployed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        }
        path = stage / MANIFEST_NAME
        path.write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        os.chmod(path, 0o644)

    def _verify_existing(self, final: Path, sha: str, archive_hash: str) -> None:
        if final.is_symlink() or not final.is_dir():
            raise DeployError("existing release path is not a real directory")
        manifest_path = final / MANIFEST_NAME
        if not manifest_path.is_file():
            raise DeployError("existing release directory has no manifest")
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise DeployError("existing release manifest is unreadable") from exc
        if not isinstance(manifest, dict):
            raise DeployError("existing release manifest is invalid")
        if manifest.get("commit") != sha:
            raise DeployError("existing release directory belongs to another commit")
        if manifest.get("archive_sha256") != archive_hash:
            raise DeployError("existing release directory has another archive hash")

    def _switch(self, target: Path) -> None:
        link = self.config.web_root
        if not link.is_symlink():
            raise DeployError(f"web_root {link} must be a symlink")
        temporary = link.parent / f".{link.name}.swap-{os.getpid()}-{time.time_ns()}"
        os.symlink(str(target), str(temporary))
        try:
            os.replace(temporary, link)
        except BaseException:
            try:
                temporary.unlink()
            except OSError:
                pass
            raise


def _fetch(url: str, context: ssl.SSLContext, timeout: int) -> bytes:
    request = urllib.request.Request(
        url, headers={"Cache-Control": "no-cache", "User-Agent": "duoyi-web-deploy/1"}
    )
    with urllib.request.urlopen(request, timeout=timeout, context=context) as response:
        if response.status != 200:
            raise DeployError(f"{url} returned HTTP {response.status}")
        return response.read(1024 * 1024)


def https_healthcheck(
    config: Config,
    sha: str,
    archive_hash: str,
    attempts: int = HEALTH_ATTEMPTS,
    timeout: int = HEALTH_TIMEOUT,
) -> dict:
    """Verify the live manifest and index over verified TLS with limited retries."""
    context = ssl.create_default_context()
    manifest_url = f"{config.public_url}/{MANIFEST_NAME}?sha={sha}"
    index_url = f"{config.public_url}/"
    last_error: Exception | None = None
    for attempt in range(1, attempts + 1):
        try:
            manifest = json.loads(_fetch(manifest_url, context, timeout))
            if not isinstance(manifest, dict):
                raise DeployError("online manifest is not a JSON object")
            if manifest.get("commit") != sha:
                raise DeployError("online manifest commit does not match")
            if manifest.get("archive_sha256") != archive_hash:
                raise DeployError("online manifest archive hash does not match")
            index = _fetch(index_url, context, timeout)
            if b"<" not in index:
                raise DeployError("online index response is not HTML")
            return manifest
        except Exception as exc:  # noqa: BLE001 - retried, then reported
            last_error = exc
            if attempt < attempts:
                time.sleep(2 * attempt)
    raise DeployError(f"online verification failed: {last_error}")


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(
        stream=sys.stderr,
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )
    arguments = list(sys.argv[1:] if argv is None else argv)
    raw = os.environ.get("SSH_ORIGINAL_COMMAND")
    if not raw or not raw.strip():
        raw = " ".join(arguments)
    try:
        command = parse_command(raw)
        config = Config.load(CONFIG_PATH)
        publisher = Publisher(config)
        if command[0] == "status":
            print(json.dumps(publisher.status(), ensure_ascii=False, sort_keys=True))
            return 0
        manifest = publisher.deploy(command[1], command[2], sys.stdin.buffer)
        print(
            json.dumps(
                {
                    "ok": True,
                    "commit": command[1],
                    "version": manifest.get("version"),
                    "build": manifest.get("build"),
                },
                ensure_ascii=False,
                sort_keys=True,
            )
        )
        return 0
    except DeployError as exc:
        LOG.error("deployment rejected: %s", exc)
        print(json.dumps({"ok": False, "error": str(exc)}))
        return 1
    except Exception as exc:  # noqa: BLE001 - never leak payloads or secrets
        LOG.exception("deployment failed unexpectedly")
        print(json.dumps({"ok": False, "error": type(exc).__name__}))
        return 1


if __name__ == "__main__":
    sys.exit(main())
