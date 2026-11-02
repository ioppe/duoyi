#!/usr/bin/env python3
"""CI client that streams one built Web artifact to the restricted server entry.

Runs on a GitHub-hosted runner after the same run's ``web`` job succeeded.  It
reads the public profile ``config/web-deploy.json``, selects exactly one
``duoyi-web-desktop-*.tar.gz`` from ``--artifact-dir``, requires the full commit
SHA to appear in that file name, and pipes the tarball over OpenSSH to
``deploy <sha> <sha256>``.  The private key comes only from the
``DUOYI_WEB_DEPLOY_SSH_KEY`` environment variable, is written to a 0700/0600
temporary file and removed afterwards.  Standard library only.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlsplit

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PROFILE = REPO_ROOT / "config" / "web-deploy.json"
DEFAULT_KNOWN_HOSTS = REPO_ROOT / "config" / "web-deploy.known_hosts"
KEY_ENV = "DUOYI_WEB_DEPLOY_SSH_KEY"
ARTIFACT_PREFIX = "duoyi-web-desktop-"
ARTIFACT_SUFFIX = ".tar.gz"
SHA_RE = re.compile(r"\A[0-9a-f]{40}\Z")
HOST_RE = re.compile(r"\A[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?\Z")
USER_RE = re.compile(r"\A[A-Za-z_][A-Za-z0-9_.-]{0,31}\Z")
BRANCH_PART_RE = re.compile(r"\A[A-Za-z0-9._-]+\Z")
KEY_BEGIN = "-----BEGIN OPENSSH PRIVATE KEY-----"
KEY_END = "-----END OPENSSH PRIVATE KEY-----"


class DeployError(Exception):
    """Invalid configuration/environment or failed remote deployment."""


@dataclass(frozen=True)
class Profile:
    host: str
    port: int
    user: str
    branch: str
    public_url: str
    web_root: str
    releases_root: str


def _safe_absolute(value: object, name: str) -> str:
    if not isinstance(value, str) or not value.startswith("/"):
        raise DeployError(f"{name} must be an absolute path")
    if any(char in value for char in "\x00 \t\r\n\\"):
        raise DeployError(f"{name} contains unsupported characters")
    parts = [part for part in value.split("/") if part]
    if not parts or any(part in (".", "..") for part in parts):
        raise DeployError(f"{name} must not contain '.' or '..'")
    if "/" + "/".join(parts) != value.rstrip("/"):
        raise DeployError(f"{name} is not normalized")
    return value.rstrip("/")


def load_profile(path: Path = DEFAULT_PROFILE) -> Profile:
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except OSError as exc:
        raise DeployError(f"cannot read profile {path}: {exc.strerror}") from exc
    except json.JSONDecodeError as exc:
        raise DeployError(f"profile {path} is not valid JSON") from exc
    if not isinstance(data, dict):
        raise DeployError("profile must be a JSON object")
    host = data.get("host")
    if not isinstance(host, str) or not HOST_RE.match(host) or host.startswith("-"):
        raise DeployError("profile host is invalid")
    port = data.get("port")
    if not isinstance(port, int) or isinstance(port, bool) or not 1 <= port <= 65535:
        raise DeployError("profile port is invalid")
    user = data.get("user")
    if not isinstance(user, str) or not USER_RE.match(user) or user.startswith("-"):
        raise DeployError("profile user is invalid")
    branch = data.get("branch")
    if not isinstance(branch, str) or not branch or branch.startswith(("-", "/")):
        raise DeployError("profile branch is invalid")
    parts = branch.split("/")
    if len(parts) > 16 or any(
        part in (".", "..", "") or not BRANCH_PART_RE.match(part) for part in parts
    ):
        raise DeployError("profile branch must be a plain branch name")
    url = data.get("public_url")
    if not isinstance(url, str) or any(char in url for char in "\x00 \t\r\n"):
        raise DeployError("profile public_url is invalid")
    split = urlsplit(url)
    if split.scheme != "https" or not split.hostname:
        raise DeployError("profile public_url must be an https URL")
    if split.username or split.password:
        raise DeployError("profile public_url must not embed credentials")
    if split.query or split.fragment:
        raise DeployError("profile public_url must not contain query or fragment")
    web_root = _safe_absolute(data.get("web_root"), "web_root")
    releases_root = _safe_absolute(data.get("releases_root"), "releases_root")
    if web_root == releases_root:
        raise DeployError("web_root and releases_root must differ")
    return Profile(
        host=host,
        port=port,
        user=user,
        branch=branch,
        public_url=url.rstrip("/"),
        web_root=web_root,
        releases_root=releases_root,
    )


def validate_git_env(profile: Profile, env: dict[str, str]) -> str:
    """Only the profile branch may deploy, from a push, with a full commit SHA."""
    sha = env.get("GITHUB_SHA", "")
    if not SHA_RE.match(sha):
        raise DeployError(
            "GITHUB_SHA must be a full 40-character lowercase commit SHA"
        )
    expected_ref = f"refs/heads/{profile.branch}"
    ref = env.get("GITHUB_REF", "")
    if ref != expected_ref:
        raise DeployError(
            f"only pushes to {expected_ref} may deploy Web; got {ref or '(empty)'}"
        )
    event = env.get("GITHUB_EVENT_NAME")
    if event != "push":
        raise DeployError(f"only push runs may deploy Web; got {event or '(empty)'}")
    return sha


def select_artifact(directory: Path, sha: str) -> Path:
    """Return exactly one regular desktop tarball ending in -<sha7>.tar.gz."""
    if not SHA_RE.match(sha):
        raise DeployError("commit SHA must be 40 lowercase hex characters")
    root = Path(directory)
    if root.is_symlink() or not root.is_dir():
        raise DeployError(f"artifact directory {root} is not a real directory")
    candidates = sorted(
        path
        for path in root.iterdir()
        if path.name.startswith(ARTIFACT_PREFIX) and path.name.endswith(ARTIFACT_SUFFIX)
    )
    if len(candidates) != 1:
        raise DeployError(
            "expected exactly one duoyi-web-desktop-*.tar.gz artifact, "
            f"found {len(candidates)}"
        )
    artifact = candidates[0]
    info = os.lstat(artifact)
    if not stat.S_ISREG(info.st_mode):
        raise DeployError("Web artifact must be a regular file, not a link")
    if not artifact.name.endswith(f"-{sha[:7]}{ARTIFACT_SUFFIX}"):
        raise DeployError("Web artifact file name must end with the commit SHA")
    return artifact


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


@contextmanager
def ssh_material(env: dict[str, str]):
    """Yield a 0600 key file inside a 0700 temp dir; always remove both."""
    raw = env.get(KEY_ENV, "")
    if not raw.strip():
        raise DeployError(f"{KEY_ENV} repository secret is missing")
    if "\x00" in raw:
        raise DeployError(f"{KEY_ENV} contains invalid characters")
    text = raw.replace("\r\n", "\n").strip() + "\n"
    if KEY_BEGIN not in text or KEY_END not in text:
        raise DeployError(f"{KEY_ENV} must be an OpenSSH private key (PEM)")
    directory = Path(tempfile.mkdtemp(prefix="duoyi-web-deploy-"))
    try:
        os.chmod(directory, 0o700)
        key_path = directory / "id_ed25519"
        descriptor = os.open(key_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            os.write(descriptor, text.encode("utf-8"))
        finally:
            os.close(descriptor)
        os.chmod(key_path, 0o600)
        yield key_path
    finally:
        shutil.rmtree(directory, ignore_errors=True)


def ssh_command(
    profile: Profile,
    key_path: Path,
    known_hosts: Path,
    sha: str,
    archive_hash: str,
) -> list[str]:
    """Build the fixed OpenSSH invocation; never uses a shell."""
    target = f"{profile.user}@{profile.host}"
    return [
        "ssh",
        "-i",
        str(key_path),
        "-o",
        "IdentitiesOnly=yes",
        "-o",
        "BatchMode=yes",
        "-o",
        "StrictHostKeyChecking=yes",
        "-o",
        f"UserKnownHostsFile={known_hosts}",
        "-o",
        "ConnectTimeout=20",
        "-p",
        str(profile.port),
        "--",
        target,
        f"deploy {sha} {archive_hash}",
    ]


def deploy_artifact(
    profile: Profile,
    artifact: Path,
    known_hosts: Path,
    env: dict[str, str],
    runner=subprocess.run,
) -> str:
    sha = validate_git_env(profile, env)
    archive_hash = sha256_file(artifact)
    with ssh_material(env) as key_path:
        with open(artifact, "rb") as payload:
            completed = runner(
                ssh_command(profile, key_path, known_hosts, sha, archive_hash),
                stdin=payload,
                shell=False,
                check=False,
            )
    if completed.returncode != 0:
        raise DeployError(
            f"remote deployment failed with exit code {int(completed.returncode)}"
        )
    return archive_hash


def main(argv: list[str] | None = None, env: dict[str, str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Deploy the same-run Web desktop artifact to the self-hosted site"
    )
    parser.add_argument("--profile", default=str(DEFAULT_PROFILE))
    parser.add_argument("--known-hosts", default=str(DEFAULT_KNOWN_HOSTS))
    parser.add_argument("--artifact-dir")
    parser.add_argument(
        "--check-config",
        action="store_true",
        help="validate the public profile only; touches no artifact or network",
    )
    args = parser.parse_args(argv)
    environment = dict(os.environ if env is None else env)
    try:
        profile = load_profile(Path(args.profile))
        if args.check_config:
            print(
                "web deploy config ok: "
                f"{profile.user}@{profile.host}:{profile.port} "
                f"branch={profile.branch} url={profile.public_url}"
            )
            return 0
        if not args.artifact_dir:
            raise DeployError("--artifact-dir is required to deploy")
        known_hosts = Path(args.known_hosts)
        if not known_hosts.is_file():
            raise DeployError(f"known_hosts file not found: {known_hosts}")
        sha = validate_git_env(profile, environment)
        artifact = select_artifact(Path(args.artifact_dir), sha)
        deploy_artifact(profile, artifact, known_hosts, environment)
        print(f"deployed Web {sha} ({artifact.name}) to {profile.public_url}")
        return 0
    except DeployError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
