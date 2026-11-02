"""Tests for the restricted self-hosted Web deployment path.

Covers the server-side publisher (``scripts/deploy_web_server.py``) against a
real temporary release tree and the CI client (``scripts/deploy_web_ci.py``)
with local fixtures and a mocked SSH runner.  Nothing touches the real server,
the network, any repository Secret or the checked-in known_hosts file.
"""

import hashlib
import io
import json
import os
import signal
from pathlib import Path
import stat
import sys
import tarfile
import tempfile
import types
import unittest

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import deploy_web_ci as ci  # noqa: E402
import deploy_web_server as server  # noqa: E402

COMMIT = "a" * 40
OTHER_COMMIT = "b" * 40
OLD_RELEASE = "v1.1.47-1944aed-startup-sync"
INDEX_HTML = (
    b'<!DOCTYPE html>\n<html><head><base href="/"></head><body>duoyi</body></html>\n'
)
VERSION_JSON = (
    b'{"app_name": "duoyi", "version": "1.1.47", '
    b'"build_number": "140013", "package_name": "duoyi"}\n'
)
BASE_FILES = {
    "./": None,
    "./index.html": INDEX_HTML,
    "./main.dart.js": b"self.console.log('duoyi');\n",
    "./version.json": VERSION_JSON,
    "./assets/fonts/NotoSansSC.woff2": b"font-bytes",
}
PROFILE_DATA = {
    "host": "207.58.173.213",
    "port": 22,
    "user": "root",
    "branch": "build/macos-dmg",
    "public_url": "https://todo.skydrow.site",
    "web_root": "/var/www/duoyi/current",
    "releases_root": "/var/www/duoyi/releases",
}
KEY_TEXT = (
    "-----BEGIN OPENSSH PRIVATE KEY-----\n"
    "b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtz\n"
    "-----END OPENSSH PRIVATE KEY-----\n"
)


def make_archive(files=None, extra=None):
    """Build a small tar.gz; ``None`` payload means a directory member."""
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz") as archive:
        for name, payload in (BASE_FILES if files is None else files).items():
            info = tarfile.TarInfo(name)
            if payload is None:
                info.type = tarfile.DIRTYPE
                info.mode = 0o755
                archive.addfile(info)
            else:
                info.size = len(payload)
                info.mode = 0o644
                archive.addfile(info, io.BytesIO(payload))
        for info, payload in extra or ():
            archive.addfile(info, None if payload is None else io.BytesIO(payload))
    return buffer.getvalue()


class DeployServerTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.releases = self.root / "releases"
        self.releases.mkdir()
        self.old = self.releases / OLD_RELEASE
        self.old.mkdir()
        (self.old / "index.html").write_text(
            INDEX_HTML.decode("utf-8"), encoding="utf-8"
        )
        (self.old / server.MANIFEST_NAME).write_text(
            json.dumps(
                {
                    "commit": OTHER_COMMIT,
                    "archive_sha256": "c" * 64,
                    "version": "1.1.47",
                    "build": "140013",
                    "deployed_at": "2026-01-01T00:00:00Z",
                }
            ),
            encoding="utf-8",
        )
        self.web_root = self.root / "current"
        os.symlink(self.old, self.web_root)
        self.config = server.Config(
            host="207.58.173.213",
            port=22,
            user="root",
            branch="build/macos-dmg",
            public_url="https://todo.skydrow.site",
            web_root=self.web_root,
            releases_root=self.releases,
        )
        self.health_calls = []
        self.health_error = None
        self.publisher = server.Publisher(
            self.config,
            lock_path=self.root / "deploy.lock",
            healthcheck=self.healthcheck,
        )

    def healthcheck(self, config, sha, archive_hash):
        self.health_calls.append((sha, archive_hash))
        if self.health_error is not None:
            raise self.health_error

    def deploy(self, payload=None, commit=COMMIT, archive_hash=None):
        payload = make_archive() if payload is None else payload
        digest = archive_hash or hashlib.sha256(payload).hexdigest()
        return self.publisher.deploy(commit, digest, io.BytesIO(payload))

    def release_names(self):
        return sorted(path.name for path in self.releases.iterdir())

    def current_target(self):
        return Path(os.readlink(self.web_root))

    def test_deploy_switches_atomically_and_writes_public_manifest(self):
        payload = make_archive()
        digest = hashlib.sha256(payload).hexdigest()
        manifest = self.publisher.deploy(COMMIT, digest, io.BytesIO(payload))
        release = self.releases / f"{COMMIT}-{digest[:12]}"
        self.assertEqual(self.current_target(), release)
        self.assertTrue(release.is_dir())
        self.assertTrue(self.old.is_dir(), "old releases must be retained")
        self.assertEqual(manifest["commit"], COMMIT)
        self.assertEqual(manifest["archive_sha256"], digest)
        self.assertEqual(manifest["version"], "1.1.47")
        self.assertEqual(manifest["build"], "140013")
        on_disk = json.loads((release / server.MANIFEST_NAME).read_text("utf-8"))
        self.assertEqual(on_disk, manifest)
        self.assertEqual(stat.S_IMODE((release / "index.html").stat().st_mode), 0o644)
        self.assertEqual(stat.S_IMODE(release.stat().st_mode), 0o755)
        self.assertEqual(
            sorted(path.name for path in self.releases.iterdir() if path.name[0] == "."),
            [],
            "staging directories must be cleaned up",
        )
        self.assertEqual(len(self.health_calls), 1)

    def test_health_failure_rolls_back_to_previous_release(self):
        self.health_error = server.DeployError("online manifest mismatch")
        with self.assertRaises(server.DeployError):
            self.deploy()
        self.assertEqual(self.current_target(), self.old)
        self.assertEqual(self.release_names(), [OLD_RELEASE])
        self.assertTrue((self.old / "index.html").is_file())

    def test_checksum_mismatch_never_switches_the_site(self):
        payload = make_archive()
        with self.assertRaises(server.DeployError):
            self.publisher.deploy(COMMIT, "0" * 64, io.BytesIO(payload))
        self.assertEqual(self.current_target(), self.old)
        self.assertEqual(self.release_names(), [OLD_RELEASE])
        self.assertEqual(self.health_calls, [])

    def test_archive_escapes_links_and_special_files_are_rejected(self):
        symlink = tarfile.TarInfo("./link")
        symlink.type = tarfile.SYMTYPE
        symlink.linkname = "index.html"
        symlink.mode = 0o777
        hardlink = tarfile.TarInfo("./hard")
        hardlink.type = tarfile.LNKTYPE
        hardlink.linkname = "./index.html"
        fifo = tarfile.TarInfo("./fifo")
        fifo.type = tarfile.FIFOTYPE
        cases = {
            "parent-escape": make_archive({**BASE_FILES, "../escape.txt": b"x"}),
            "absolute": make_archive({**BASE_FILES, "/etc/passwd": b"x"}),
            "symlink": make_archive(extra=[(symlink, None)]),
            "hardlink": make_archive(extra=[(hardlink, None)]),
            "fifo": make_archive(extra=[(fifo, None)]),
        }
        for label, payload in cases.items():
            with self.subTest(label):
                with self.assertRaises(server.DeployError):
                    self.deploy(payload)
                self.assertEqual(self.current_target(), self.old)
                self.assertEqual(self.release_names(), [OLD_RELEASE])
                self.assertEqual(self.health_calls, [])

    def test_release_content_is_validated_before_switching(self):
        cases = {
            "base-href": {**BASE_FILES, "./index.html": b"<html></html>"},
            "missing-file": {
                key: value
                for key, value in BASE_FILES.items()
                if key != "./main.dart.js"
            },
            "empty-build-number": {
                **BASE_FILES,
                "./version.json": b'{"version": "1.1.47", "build_number": ""}',
            },
            "missing-build-number": {
                **BASE_FILES,
                "./version.json": b'{"version": "1.1.47"}',
            },
        }
        for label, files in cases.items():
            with self.subTest(label):
                with self.assertRaises(server.DeployError):
                    self.deploy(make_archive(files))
                self.assertEqual(self.current_target(), self.old)
                self.assertEqual(self.release_names(), [OLD_RELEASE])

    def test_command_parsing_is_strict(self):
        self.assertEqual(server.parse_command("status"), ("status",))
        self.assertEqual(
            server.parse_command(f" deploy {COMMIT} {'d' * 64} "),
            ("deploy", COMMIT, "d" * 64),
        )
        rejected = (
            "",
            "deploy",
            f"deploy {COMMIT}",
            f"deploy {COMMIT.upper()} {'d' * 64}",
            f"deploy {COMMIT} {'d' * 63}",
            f"deploy {COMMIT} {'d' * 64} extra",
            f"status {COMMIT}",
            "rm -rf /var/www/duoyi",
            f"deploy {COMMIT} {'d' * 64}\nrm -rf /",
        )
        for command in rejected:
            with self.subTest(command=command):
                with self.assertRaises(server.DeployError):
                    server.parse_command(command)
        with self.assertRaises(server.DeployError):
            server.parse_command(None)

    def test_web_root_must_stay_a_symlink(self):
        self.web_root.unlink()
        self.web_root.mkdir()
        with self.assertRaises(server.DeployError):
            self.deploy()
        self.assertTrue(self.web_root.is_dir())
        self.assertFalse(self.web_root.is_symlink())
        self.assertEqual(self.release_names(), [OLD_RELEASE])

    def test_repeating_the_same_sha_is_idempotent(self):
        payload = make_archive()
        digest = hashlib.sha256(payload).hexdigest()
        first = self.publisher.deploy(COMMIT, digest, io.BytesIO(payload))
        second = self.publisher.deploy(COMMIT, digest, io.BytesIO(payload))
        self.assertEqual(first, second)
        self.assertEqual(len(self.health_calls), 2)
        release = self.releases / f"{COMMIT}-{digest[:12]}"
        self.assertEqual(self.current_target(), release)
        self.assertEqual(self.release_names(), [f"{COMMIT}-{digest[:12]}", OLD_RELEASE])
        # A same-commit retry with another archive must not overwrite the release.
        with self.assertRaises(server.DeployError):
            self.publisher.deploy(COMMIT, "e" * 64, io.BytesIO(payload))
        self.assertEqual(self.current_target(), release)

    def test_conflicting_paths_are_rejected(self):
        cases = {
            "file-then-child": make_archive(
                {**BASE_FILES, "./conflict": b"x", "./conflict/child": b"y"}
            ),
            "dir-then-file": make_archive(
                {**BASE_FILES, "./conflict/": None, "./conflict": b"x"}
            ),
        }
        for label, payload in cases.items():
            with self.subTest(label):
                with self.assertRaises(server.DeployError):
                    self.deploy(payload)
                self.assertEqual(self.current_target(), self.old)
                self.assertEqual(self.release_names(), [OLD_RELEASE])

    def test_sigterm_during_healthcheck_rolls_back(self):
        payload = make_archive()
        digest = hashlib.sha256(payload).hexdigest()
        original_handler = signal.getsignal(signal.SIGTERM)

        def cancel(config, sha, archive_hash):
            signal.raise_signal(signal.SIGTERM)

        publisher = server.Publisher(
            self.config,
            lock_path=self.root / "cancel.lock",
            healthcheck=cancel,
        )
        with self.assertRaises(server.DeployError):
            publisher.deploy(COMMIT, digest, io.BytesIO(payload))
        self.assertEqual(self.current_target(), self.old)
        self.assertEqual(self.release_names(), [OLD_RELEASE])
        self.assertEqual(signal.getsignal(signal.SIGTERM), original_handler)

    def test_existing_release_with_conflicting_manifest_is_rejected(self):
        payload = make_archive()
        digest = hashlib.sha256(payload).hexdigest()
        final = self.releases / f"{COMMIT}-{digest[:12]}"
        final.mkdir()
        (final / "index.html").write_text(
            INDEX_HTML.decode("utf-8"), encoding="utf-8"
        )
        manifests = {
            "other-commit": {"commit": OTHER_COMMIT, "archive_sha256": digest},
            "other-archive": {"commit": COMMIT, "archive_sha256": "c" * 64},
        }
        for label, fields in manifests.items():
            with self.subTest(label):
                (final / server.MANIFEST_NAME).write_text(
                    json.dumps(fields), encoding="utf-8"
                )
                with self.assertRaises(server.DeployError):
                    self.publisher.deploy(COMMIT, digest, io.BytesIO(payload))
                self.assertEqual(self.current_target(), self.old)
                self.assertEqual(self.health_calls, [])
        (final / server.MANIFEST_NAME).unlink()
        with self.assertRaises(server.DeployError):
            self.publisher.deploy(COMMIT, digest, io.BytesIO(payload))
        self.assertEqual(self.current_target(), self.old)
        self.assertIn(final.name, self.release_names())

    def test_status_is_read_only(self):
        before = self.release_names()
        info = self.publisher.status()
        self.assertEqual(info["current"], str(self.old))
        self.assertEqual(info["commit"], OTHER_COMMIT)
        self.assertEqual(info["version"], "1.1.47")
        self.assertEqual(self.release_names(), before)


class WebDeployCiTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.profile_path = self.root / "web-deploy.json"
        self.profile_path.write_text(json.dumps(PROFILE_DATA), encoding="utf-8")
        self.profile = ci.load_profile(self.profile_path)
        self.artifacts = self.root / "artifacts"
        self.artifacts.mkdir()

    def write_artifact(self, name, payload=b"web-payload"):
        path = self.artifacts / name
        path.write_bytes(payload)
        return path

    def test_profile_and_check_config(self):
        output = io.StringIO()
        stdout = sys.stdout
        sys.stdout = output
        try:
            code = ci.main(["--check-config", "--profile", str(self.profile_path)])
        finally:
            sys.stdout = stdout
        self.assertEqual(code, 0)
        self.assertIn("root@207.58.173.213:22", output.getvalue())
        invalid = (
            {"host": "-oProxyCommand=curl"},
            {"host": "bad host"},
            {"user": "root;rm -rf /"},
            {"port": "22"},
            {"port": 70000},
            {"branch": "../main"},
            {"branch": "-upload-pack"},
            {"public_url": "http://todo.skydrow.site"},
            {"public_url": "https://user:pass@todo.skydrow.site"},
            {"public_url": "https://todo.skydrow.site/?token=1"},
            {"web_root": "relative/current"},
            {"releases_root": "/var/www/../etc"},
            {"releases_root": "/var/www/duoyi/current"},
        )
        for mutation in invalid:
            with self.subTest(mutation=mutation):
                path = self.root / "bad-profile.json"
                path.write_text(
                    json.dumps({**PROFILE_DATA, **mutation}), encoding="utf-8"
                )
                with self.assertRaises(ci.DeployError):
                    ci.load_profile(path)

    def test_only_push_to_profile_branch_with_full_sha(self):
        env = {
            "GITHUB_SHA": COMMIT,
            "GITHUB_REF": "refs/heads/build/macos-dmg",
            "GITHUB_EVENT_NAME": "push",
        }
        self.assertEqual(ci.validate_git_env(self.profile, env), COMMIT)
        rejected = (
            {**env, "GITHUB_REF": "refs/heads/main"},
            {**env, "GITHUB_REF": "refs/heads/self-hosted-skydrow"},
            {**env, "GITHUB_REF": "refs/tags/v1.1.47"},
            {**env, "GITHUB_REF": "build/macos-dmg"},
            {**env, "GITHUB_SHA": COMMIT[:7]},
            {**env, "GITHUB_SHA": COMMIT.upper()},
            {**env, "GITHUB_EVENT_NAME": "pull_request"},
            {"GITHUB_REF": env["GITHUB_REF"], "GITHUB_SHA": COMMIT},
        )
        for bad in rejected:
            with self.subTest(bad=bad):
                with self.assertRaises(ci.DeployError):
                    ci.validate_git_env(self.profile, bad)

    def test_artifact_selection_requires_one_matching_desktop_tarball(self):
        mobile = self.write_artifact("duoyi-web-mobile-20260101-aaaaaaa.tar.gz")
        generic = self.write_artifact("duoyi-web-20260101-aaaaaaa.tar.gz")
        self.assertIsNotNone(mobile)
        self.assertIsNotNone(generic)
        with self.assertRaises(ci.DeployError):
            ci.select_artifact(self.artifacts, COMMIT)

        desktop = self.write_artifact(
            f"duoyi-web-desktop-20260101-{COMMIT[:7]}.tar.gz"
        )
        self.assertEqual(ci.select_artifact(self.artifacts, COMMIT), desktop)

        second = self.write_artifact(
            f"duoyi-web-desktop-20260102-{COMMIT[:7]}.tar.gz"
        )
        with self.assertRaises(ci.DeployError):
            ci.select_artifact(self.artifacts, COMMIT)

        desktop.unlink()
        second.unlink()
        wrong = self.write_artifact("duoyi-web-desktop-20260103-bbbbbbb.tar.gz")
        self.assertIsNotNone(wrong)
        with self.assertRaises(ci.DeployError):
            ci.select_artifact(self.artifacts, COMMIT)

        wrong.unlink()
        target = self.write_artifact("deploy-payload.bin")
        link = self.artifacts / f"duoyi-web-desktop-20260104-{COMMIT[:7]}.tar.gz"
        os.symlink(target, link)
        with self.assertRaises(ci.DeployError):
            ci.select_artifact(self.artifacts, COMMIT)

    def test_artifact_sha7_must_be_the_final_suffix(self):
        embedded = self.write_artifact(
            f"duoyi-web-desktop-{COMMIT[:7]}-20260101.tar.gz"
        )
        with self.assertRaises(ci.DeployError):
            ci.select_artifact(self.artifacts, COMMIT)
        embedded.unlink()
        self.write_artifact("duoyi-web-desktop-20260101-bbbbbbb.tar.gz")
        with self.assertRaises(ci.DeployError):
            ci.select_artifact(self.artifacts, COMMIT)

    def test_ssh_material_is_private_and_cleaned_up(self):
        env = {ci.KEY_ENV: KEY_TEXT}
        with ci.ssh_material(env) as key_path:
            self.assertEqual(stat.S_IMODE(key_path.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(key_path.parent.stat().st_mode), 0o700)
            command = ci.ssh_command(
                self.profile,
                key_path,
                Path("config/web-deploy.known_hosts"),
                COMMIT,
                "e" * 64,
            )
            self.assertEqual(command[0], "ssh")
            for option in (
                "IdentitiesOnly=yes",
                "BatchMode=yes",
                "StrictHostKeyChecking=yes",
                "UserKnownHostsFile=config/web-deploy.known_hosts",
                "ConnectTimeout=20",
            ):
                self.assertIn(option, command)
            self.assertIn("root@207.58.173.213", command)
            self.assertEqual(command[-1], f"deploy {COMMIT} {'e' * 64}")
            self.assertFalse(any("ProxyCommand" in part for part in command))
        self.assertFalse(key_path.exists())
        self.assertFalse(key_path.parent.exists())

    def test_missing_or_malformed_key_is_rejected(self):
        for env in ({}, {ci.KEY_ENV: "   "}, {ci.KEY_ENV: "not-a-key"}):
            with self.subTest(env=env):
                with self.assertRaises(ci.DeployError):
                    with ci.ssh_material(env):
                        self.fail("ssh_material must not yield without a key")

    def test_deploy_artifact_streams_tar_with_matching_hash(self):
        payload = make_archive()
        artifact = self.write_artifact(
            f"duoyi-web-desktop-20260101-{COMMIT[:7]}.tar.gz", payload
        )
        calls = {}

        def runner(command, stdin, shell, check):
            calls["command"] = command
            calls["payload"] = stdin.read()
            calls["shell"] = shell
            calls["check"] = check
            return types.SimpleNamespace(returncode=0)

        env = {
            "GITHUB_SHA": COMMIT,
            "GITHUB_REF": "refs/heads/build/macos-dmg",
            "GITHUB_EVENT_NAME": "push",
            ci.KEY_ENV: KEY_TEXT,
        }
        digest = ci.deploy_artifact(
            self.profile, artifact, Path("known_hosts"), env, runner=runner
        )
        self.assertEqual(digest, hashlib.sha256(payload).hexdigest())
        self.assertEqual(calls["payload"], payload)
        self.assertFalse(calls["shell"])
        self.assertEqual(calls["command"][-1], f"deploy {COMMIT} {digest}")
        key_path = Path(calls["command"][2])
        self.assertFalse(key_path.exists(), "temporary key must be removed")
        self.assertFalse(key_path.parent.exists())

    def test_remote_nonzero_exit_fails(self):
        artifact = self.write_artifact(
            f"duoyi-web-desktop-20260101-{COMMIT[:7]}.tar.gz"
        )
        env = {
            "GITHUB_SHA": COMMIT,
            "GITHUB_REF": "refs/heads/build/macos-dmg",
            "GITHUB_EVENT_NAME": "push",
            ci.KEY_ENV: KEY_TEXT,
        }
        with self.assertRaises(ci.DeployError):
            ci.deploy_artifact(
                self.profile,
                artifact,
                Path("known_hosts"),
                env,
                runner=lambda *args, **kwargs: types.SimpleNamespace(returncode=255),
            )

    def test_sha256_file_matches_artifact_bytes(self):
        artifact = self.write_artifact("duoyi-web-desktop-x.tar.gz", b"payload")
        self.assertEqual(
            ci.sha256_file(artifact), hashlib.sha256(b"payload").hexdigest()
        )


if __name__ == "__main__":
    unittest.main()
