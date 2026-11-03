"""Web build policy tests; stdlib only, also run by backend unittest discovery."""
import contextlib
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import flutter_with_config
import prepare_web_fonts as fonts
from generate_web_startup_font import startup_codepoints


class WebFontBuildTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.build = self.root / "build/web"
        for asset in (fonts.FULL_ASSET, fonts.STARTUP_ASSET, fonts.LICENSE_ASSET,
                      fonts.METADATA):
            target = self.root / asset
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / asset, target)
        (self.root / "pubspec.yaml").write_text((ROOT / "pubspec.yaml").read_text())
        built_font = self.build / "assets" / fonts.FULL_ASSET
        built_font.parent.mkdir(parents=True)
        shutil.copyfile(ROOT / fonts.FULL_ASSET, built_font)
        self.manifest = self.build / "assets/FontManifest.json"
        self.original = [
            {"family": "MaterialIcons", "fonts": [{"asset": "icons.otf"}]},
            {"family": fonts.FAMILY, "fonts": [
                {"asset": fonts.FULL_ASSET, "weight": weight}
                for weight in (400, 500, 600, 700)
            ]},
        ]
        self.manifest.write_text(json.dumps(self.original))

    def prepare(self):
        with contextlib.redirect_stdout(io.StringIO()):
            return fonts.prepare_web_fonts(self.root, self.build)

    def test_web_startup_has_one_small_variable_font_and_keeps_full_for_later(self):
        native_before = (self.root / "pubspec.yaml").read_bytes()
        result = self.prepare()
        entries = json.loads(self.manifest.read_text())
        self.assertEqual(entries[0], self.original[0])
        self.assertEqual(entries[1]["fonts"], [{"asset": fonts.STARTUP_ASSET}])
        self.assertNotIn(fonts.FULL_ASSET, self.manifest.read_text())
        self.assertLess(result["startup_bytes"], 3_000_000)
        self.assertEqual((self.root / "pubspec.yaml").read_bytes(), native_before)
        self.assertEqual((self.build / "assets" / fonts.FULL_ASSET).read_bytes(),
                         (ROOT / fonts.FULL_ASSET).read_bytes())
        self.assertTrue((self.build / "assets" / fonts.LICENSE_ASSET).exists())

    def test_preparation_is_idempotent(self):
        self.prepare()
        first = self.manifest.read_bytes()
        self.prepare()
        self.assertEqual(self.manifest.read_bytes(), first)

    def test_tampered_subset_is_rejected_before_manifest_write(self):
        (self.root / fonts.STARTUP_ASSET).write_bytes(b"invalid")
        with self.assertRaisesRegex(ValueError, "hash"):
            self.prepare()
        self.assertEqual(json.loads(self.manifest.read_text()), self.original)

    def test_changed_full_font_is_rejected(self):
        (self.root / fonts.FULL_ASSET).write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "regenerate"):
            self.prepare()

    def test_unexpected_family_does_not_silently_ship_blocking_fonts(self):
        self.manifest.write_text(json.dumps(self.original[:1]))
        with self.assertRaisesRegex(ValueError, "exactly one"):
            self.prepare()

    def test_deploy_verifier_rejects_the_old_full_font_manifest(self):
        self.prepare()
        (self.build / "version.json").write_text(
            json.dumps({"version": "1.1.47", "build_number": "140013"}))
        (self.build / "index.html").write_text('<base href="/">')
        (self.build / "main.dart.js").write_text('const version="1.1.47";')
        script = (ROOT / "scripts/deploy_web_prod.sh").read_text()
        verifier = "verify_web_build() {" + script.split("verify_web_build() {", 1)[1].split("\n}\n", 1)[0] + "\n}\n"
        header = ("set -euo pipefail\nVERSION_NAME=1.1.47\nVERSION_CODE=140013\n"
                  "BASE_HREF=/\nPYTHON_BIN=" + repr(sys.executable) + "\n")
        command = header + verifier + '\nverify_web_build "$1" fixture\n'
        result = subprocess.run(["bash", "-c", command, "verify", str(self.build)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.manifest.write_text(json.dumps(self.original))
        result = subprocess.run(["bash", "-c", command, "verify", str(self.build)],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("full font", result.stderr)

    def test_explicit_output_directory_is_supported(self):
        for arguments in (["build", "web", "--output=custom/web"],
                          ["build", "web", "--output", "custom/web"],
                          ["build", "web", "-o", "custom/web"]):
            with self.subTest(arguments=arguments):
                self.assertEqual(fonts.web_output_directory(arguments, self.root),
                                 (self.root / "custom/web").resolve())
        self.assertEqual(fonts.web_output_directory(["build", "web"], self.root),
                         (self.root / "build/web").resolve())

    def test_wrapper_only_prepares_successful_web_build(self):
        for target, status, expected in (("web", 0, 1), ("web", 1, 0),
                                         ("apk", 0, 0)):
            with self.subTest(target=target, status=status), \
                 patch.object(flutter_with_config, "PROJECT_ROOT", self.root), \
                 patch("shutil.which", return_value="flutter"), \
                 patch("subprocess.run", return_value=subprocess.CompletedProcess([], status)), \
                 patch.object(fonts, "prepare_web_fonts") as prepare:
                self.assertEqual(flutter_with_config.main(["build", target]), status)
                self.assertEqual(prepare.call_count, expected)

    def test_dry_run_never_prepares_assets(self):
        with patch.object(fonts, "prepare_web_fonts") as prepare, \
             contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(flutter_with_config.main(["--dry-run", "build", "web"]), 0)
            prepare.assert_not_called()

    def test_checked_in_subset_covers_common_and_ui_chinese(self):
        metadata = json.loads((ROOT / fonts.METADATA).read_text())
        covered = set(metadata["codepoints"])
        self.assertGreater(len(covered), 4000)
        for text in ("登录用户名密码今日待办习惯专注日历我的龟", "0123456789ABCabc"):
            self.assertTrue(set(map(ord, text)) <= covered)
        self.assertEqual(metadata["variable_axes"], ["wght"])
        self.assertEqual(hashlib.sha256((ROOT / fonts.STARTUP_ASSET).read_bytes()).hexdigest(),
                         metadata["subset_sha256"])
        self.assertTrue(startup_codepoints(ROOT).issuperset(covered))
        ui_han = set()
        for path in (ROOT / "lib").rglob("*"):
            if path.suffix in {".dart", ".arb"} and "generated" not in path.parts:
                ui_han.update(ord(c) for c in path.read_text(encoding="utf-8")
                              if 0x3400 <= ord(c) <= 0x9FFF)
        self.assertTrue(ui_han <= covered,
                        "New CJK copy requires scripts/generate_web_startup_font.py")


if __name__ == "__main__":
    unittest.main()
