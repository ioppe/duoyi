import json
import os
import tempfile
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

# 与 test_workspaces.py 相同的测试引导凭据；生产没有默认密码。
with patch.dict(os.environ, {"ADMIN_BOOTSTRAP_PASSWORD": "admin123"}):
    import main as api


class MobileUpdateVersionSemanticsTest(unittest.TestCase):
    """版本名优先 + 可信 build 的回归测试。

    事故场景：生产 `_version_to_code` 用 versionName 合成 code，
    GitHub Release 的 tag 2.0.0 合成出 200000，大于真机已装 2.0.0/142023，
    于是客户端被要求更新（甚至强制更新），但版本名其实没有变化。
    """

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self._old_db_path = api.DB_PATH
        self._old_repository = api.APP_UPDATE_REPOSITORY
        self._old_mobile_apk_dir = api.MOBILE_APK_DIR
        api.DB_PATH = os.path.join(self._tmp.name, "duoyi-test.db")
        api.TOKENS.clear()
        api.TOKEN_LAST_ACTIVE.clear()
        api.init_db()
        api.MOBILE_APK_DIR = os.path.join(self._tmp.name, "mobile_apps")
        api.APP_UPDATE_REPOSITORY = ""

    def tearDown(self):
        api.DB_PATH = self._old_db_path
        api.APP_UPDATE_REPOSITORY = self._old_repository
        api.MOBILE_APK_DIR = self._old_mobile_apk_dir
        api.TOKENS.clear()
        api.TOKEN_LAST_ACTIVE.clear()
        self._tmp.cleanup()

    def _set_settings(self, **values):
        db = api.get_db()
        try:
            for key, value in values.items():
                api._setting_set(db, key, value)
            db.commit()
        finally:
            db.close()

    def _mobile_update(self, version_name, version_code):
        with TestClient(api.app) as client:
            response = client.get(
                "/api/mobile/apps/duoyi/update",
                params={
                    "current_version": version_name,
                    "current_version_code": str(version_code),
                },
            )
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def _install_local_apk(self, version_name, version_code):
        app_dir = os.path.join(api.MOBILE_APK_DIR, "duoyi")
        os.makedirs(app_dir, exist_ok=True)
        with open(os.path.join(app_dir, "app-release.apk"), "wb") as handle:
            handle.write(b"fake-apk")
        manifest = {
            "version_name": version_name,
            "apk_name": "app-release.apk",
        }
        if version_code is not None:
            manifest["version_code"] = version_code
        with open(os.path.join(app_dir, "manifest.json"), "w", encoding="utf-8") as f:
            json.dump(manifest, f)

    def test_update_is_available_ignores_bigger_code_for_older_name(self):
        self.assertFalse(api._update_is_available("2.0.0", 142023, "1.1.20", 200000))
        self.assertTrue(api._update_is_available("2.0.0", 142023, "2.0.1", None))
        self.assertFalse(api._update_is_available("2.0.0", 142023, "2.0.0", None))
        self.assertTrue(api._update_is_available("2.0.0", 142023, "2.0.0", 202000))

    def test_github_release_without_real_build_does_not_claim_version_code(self):
        def release():
            return {
                "latest_version_name": "2.0.0",
                "latest_version_code": None,
                "latest_version_code_source": api.RELEASE_CODE_SOURCE_UNKNOWN,
                "download_url": "https://example.test/duoyi-2.0.0.apk",
                "release_notes": "same version release",
            }

        with patch.object(api, "_github_latest_mobile_release", release):
            self._set_settings(
                force_update_required=True,
                force_app_update_enabled=True,
                minimum_supported_version=api.APP_CURRENT_VERSION,
            )
            payload = self._mobile_update("2.0.0", 142023)

        self.assertEqual(payload["latest_version_name"], "2.0.0")
        self.assertIsNone(payload["latest_version_code"])
        self.assertEqual(
            payload["latest_version_code_source"],
            api.RELEASE_CODE_SOURCE_UNKNOWN,
        )
        self.assertFalse(payload["available"])
        self.assertFalse(payload["force_update"])

    def test_github_release_still_offers_newer_version_name(self):
        def release():
            return {
                "latest_version_name": "2.0.1",
                "latest_version_code": None,
                "latest_version_code_source": api.RELEASE_CODE_SOURCE_UNKNOWN,
                "download_url": "https://example.test/duoyi-2.0.1.apk",
            }

        with patch.object(api, "_github_latest_mobile_release", release):
            self._set_settings(
                force_update_required=True,
                force_app_update_enabled=True,
            )
            payload = self._mobile_update("2.0.0", 142023)

        self.assertEqual(payload["latest_version_name"], "2.0.1")
        self.assertTrue(payload["available"])
        self.assertTrue(payload["force_update"])

    def test_local_manifest_build_is_trusted_for_same_version_name(self):
        self._install_local_apk("2.0.0", 202000)
        self._set_settings(
            force_update_required=True,
            force_app_update_enabled=True,
        )
        payload = self._mobile_update("2.0.0", 142023)

        self.assertEqual(payload["latest_version_name"], "2.0.0")
        self.assertEqual(payload["latest_version_code"], 202000)
        self.assertEqual(
            payload["latest_version_code_source"],
            api.RELEASE_CODE_SOURCE_MANIFEST,
        )
        self.assertTrue(payload["available"])
        self.assertTrue(payload["force_update"])

    def test_explicit_admin_build_is_trusted_but_derived_build_is_not(self):
        with patch.object(api, "_github_latest_mobile_release", lambda: None):
            self._set_settings(latest_version_name="2.0.0", latest_version="2.0.0")
            derived = self._mobile_update("2.0.0", 142023)
            self.assertEqual(
                derived["latest_version_code_source"],
                api.RELEASE_CODE_SOURCE_DERIVED,
            )
            self.assertFalse(derived["available"])

            self._set_settings(latest_version_code=202000)
            configured = self._mobile_update("2.0.0", 142023)

        self.assertEqual(
            configured["latest_version_code_source"],
            api.RELEASE_CODE_SOURCE_CONFIGURED,
        )
        self.assertEqual(configured["latest_version_code"], 202000)
        self.assertTrue(configured["available"])

    def test_minimum_version_without_real_build_does_not_force_update(self):
        def release():
            return {
                "latest_version_name": "2.0.0",
                "latest_version_code": None,
                "latest_version_code_source": api.RELEASE_CODE_SOURCE_UNKNOWN,
                "download_url": "https://example.test/duoyi-2.0.0.apk",
            }

        with patch.object(api, "_github_latest_mobile_release", release):
            self._set_settings(
                force_update_required=True,
                force_app_update_enabled=True,
                minimum_supported_version="2.0.0",
            )
            payload = self._mobile_update("2.0.0", 142023)

        self.assertEqual(
            payload["minimum_supported_version_code_source"],
            api.RELEASE_CODE_SOURCE_DERIVED,
        )
        self.assertFalse(payload["available"])
        self.assertFalse(payload["force_update"])

    def test_newer_installed_client_is_never_told_to_downgrade(self):
        def stale_release():
            return {
                "latest_version_name": "1.1.20",
                "latest_version_code": 200000,
                "latest_version_code_source": api.RELEASE_CODE_SOURCE_MANIFEST,
                "download_url": "https://example.test/duoyi-1.1.20.apk",
            }

        with patch.object(api, "_github_latest_mobile_release", stale_release):
            self._set_settings(
                force_update_required=True,
                force_app_update_enabled=True,
            )
            payload = self._mobile_update("2.0.0", 142023)

        self.assertEqual(payload["latest_version_name"], api.APP_CURRENT_VERSION)
        self.assertFalse(payload["available"])
        self.assertFalse(payload["force_update"])

    def test_stored_legacy_formula_is_not_promoted_to_a_configured_build(self):
        with patch.object(api, "_github_latest_mobile_release", lambda: None):
            self._set_settings(
                latest_version_name="2.0.0",
                latest_version="2.0.0",
                latest_version_code=200000,
                minimum_supported_version="2.0.0",
                force_update_required=True,
                force_app_update_enabled=True,
            )
            payload = self._mobile_update("2.0.0", 142023)
        self.assertEqual(payload["latest_version_code_source"], api.RELEASE_CODE_SOURCE_DERIVED)
        self.assertEqual(payload["minimum_supported_version_code_source"], api.RELEASE_CODE_SOURCE_DERIVED)
        self.assertFalse(payload["available"])
        self.assertFalse(payload["force_update"])

    def test_minimum_build_does_not_reuse_a_different_release_build(self):
        with patch.object(api, "_github_latest_mobile_release", lambda: None):
            self._set_settings(
                latest_version_name="2.0.1",
                latest_version="2.0.1",
                latest_version_code=202001,
                minimum_supported_version="2.0.0",
            )
            payload = self._mobile_update("2.0.0", 142023)
        self.assertEqual(payload["latest_version_code_source"], api.RELEASE_CODE_SOURCE_CONFIGURED)
        self.assertEqual(payload["minimum_supported_version_code_source"], api.RELEASE_CODE_SOURCE_DERIVED)


if __name__ == "__main__":
    unittest.main()
