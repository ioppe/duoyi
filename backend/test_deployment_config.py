import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import deployment_config as deployment

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT / 'scripts'))
import flutter_with_config


class DeploymentConfigTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.profile = self.root / 'deployment.json'

    def load(self, values, environ=None):
        self.profile.write_text(json.dumps(values))
        return deployment.load_deployment_config(self.profile, environ=environ or {})

    def test_deployment_paths_are_normalized_before_protected_directory_checks(self):
        for value in ['/var/www/', '/var/www/.', '//var//www//', '/opt/.', '/home//']:
            with self.subTest(value=value), self.assertRaises(deployment.ConfigurationError):
                self.load({'DUOYI_WEB_ROOT': value})
        config = self.load({'DUOYI_WEB_ROOT': '/srv/duoyi/./site//'})
        self.assertEqual(config.values['DUOYI_WEB_ROOT'], '/srv/duoyi/site')

    def test_public_environment_overrides_profile_including_same_origin(self):
        config = self.load({'DUOYI_SERVER_URL': 'https://profile.example'}, {'DUOYI_SERVER_URL': ''})
        self.assertEqual(config.values['DUOYI_SERVER_URL'], '')
        self.assertNotIn('CORS_ORIGINS', config.backend_defaults())

    def test_profiles_drive_client_and_backend_from_one_value(self):
        config = self.load({'DUOYI_SERVER_URL': 'https://todo.example/app/', 'DUOYI_UPDATE_REPOSITORY': 'owner/fork'})
        self.assertEqual(config.client_defines()['DUOYI_SERVER_URL'], 'https://todo.example/app')
        self.assertEqual(config.client_defines()['DUOYI_UPDATE_REPOSITORY'], 'owner/fork')
        self.assertEqual(config.backend_defaults(), {'APP_UPDATE_REPOSITORY': 'owner/fork', 'CORS_ORIGINS': 'https://todo.example'})

    def test_invalid_urls_do_not_echo_credentials(self):
        for value in ['ftp://example.com', '/relative', 'https://secret:password@example.com', 'https://example.com?', 'https://example.com#', 'https://example.com:0']:
            with self.subTest(value=value), self.assertRaises(deployment.ConfigurationError) as caught:
                self.load({'DUOYI_SERVER_URL': value})
            self.assertNotIn('password', str(caught.exception))
            self.assertNotIn(value, str(caught.exception))

    def test_unknown_or_private_keys_are_rejected_without_values(self):
        with self.assertRaises(deployment.ConfigurationError) as caught:
            self.load({'AI_API_KEY': 'do-not-display-this'})
        self.assertNotIn('do-not-display-this', str(caught.exception))
        self.assertIn('AI_API_KEY', str(caught.exception))

    def test_environment_secrets_never_enter_client_defines(self):
        config = self.load({}, {'AI_API_KEY': 'private', 'ADMIN_BOOTSTRAP_PASSWORD': 'private'})
        self.assertNotIn('private', json.dumps(config.client_defines()))
        self.assertEqual(set(config.client_defines()), set(deployment.CLIENT_KEYS))

    def test_timeout_type_and_bounds_are_checked(self):
        for value in [True, 1.5, 0, -1, 3601, '', 'nonsense']:
            with self.subTest(value=value), self.assertRaises(deployment.ConfigurationError):
                self.load({'DUOYI_HTTP_TIMEOUT_SECONDS': value})
        self.assertEqual(self.load({}, {'DUOYI_HTTP_TIMEOUT_SECONDS': '23'}).values['DUOYI_HTTP_TIMEOUT_SECONDS'], 23)

    def test_repository_target_and_base_path_validation(self):
        for key, value in [('DUOYI_UPDATE_REPOSITORY', 'https://github.com/a/b'), ('DUOYI_WEB_TARGET', 'unknown'), ('DUOYI_WEB_BASE_HREF', 'relative/'), ('DUOYI_WEB_BASE_HREF', '/a/../'), ('DUOYI_WEB_ROOT', '/')]:
            with self.subTest(key=key), self.assertRaises(deployment.ConfigurationError):
                self.load({key: value})

    def test_duplicate_and_non_object_json_are_rejected(self):
        for value in ['[]', '{"DUOYI_SERVER_URL":"", "DUOYI_SERVER_URL":"https://other.example"}']:
            self.profile.write_text(value)
            with self.assertRaises(deployment.ConfigurationError):
                deployment.load_deployment_config(self.profile, environ={})

    def test_explicit_missing_file_fails_but_standalone_default_is_neutral(self):
        with self.assertRaises(deployment.ConfigurationError):
            deployment.load_deployment_config(self.profile, environ={})
        with patch.object(deployment, 'DEFAULT_CONFIG_FILE', self.profile):
            config = deployment.load_deployment_config(environ={})
        self.assertIsNone(config.source)
        self.assertEqual(config.values['DUOYI_SERVER_URL'], '')
        self.assertEqual(config.values['DUOYI_UPDATE_REPOSITORY'], '')

    def test_configuration_values_are_immutable(self):
        config = self.load({})
        with self.assertRaises(TypeError):
            config.values['DUOYI_SERVER_URL'] = 'https://other.example'

    def test_module_import_has_no_database_side_effect(self):
        code = (
            'from unittest.mock import patch\n'
            'with patch("sqlite3.connect") as connect:\n'
            '    import deployment_config\n'
            '    connect.assert_not_called()\n'
        )
        subprocess.run([sys.executable, '-c', code], cwd=PROJECT_ROOT / 'backend', capture_output=True, text=True, check=True)

    def test_shell_export_quotes_values_without_running_them(self):
        marker = self.root / 'must-not-exist'
        value = f'/var/www/duoyi-$(touch {marker})'
        self.profile.write_text(json.dumps({'DUOYI_WEB_ROOT': value}))
        environment = {key: value for key, value in os.environ.items() if key not in deployment.DEFAULTS and key not in {'WEB_ROOT', 'DUOYI_CONFIG_FILE'}}
        result = subprocess.run([sys.executable, str(PROJECT_ROOT / 'scripts/project_config.py'), '--config', str(self.profile), 'shell'], env=environment, capture_output=True, text=True, check=True)
        shell = subprocess.run(['bash', '-c', result.stdout + '\nprintf "%s" "$WEB_ROOT"'], env=environment, capture_output=True, text=True, check=True)
        self.assertEqual(shell.stdout, value)
        self.assertFalse(marker.exists())


class FlutterConfigCommandTest(unittest.TestCase):
    def test_web_uses_profile_path_and_explicit_flags_remain_last(self):
        command = flutter_with_config.build_command('flutter', ['build', 'web', '--release', '--dart-define=DUOYI_SERVER_URL='], Path('defines.json'), {'DUOYI_WEB_BASE_HREF': '/app/'})
        self.assertIn('--base-href=/app/', command)
        self.assertEqual(command[-1], '--dart-define=DUOYI_SERVER_URL=')
        self.assertIn('--dart-define-from-file=defines.json', command)

    def test_explicit_web_path_wins_over_profile(self):
        command = flutter_with_config.build_command('flutter', ['build', 'web', '--base-href=/pages/'], Path('defines.json'), {'DUOYI_WEB_BASE_HREF': '/'})
        self.assertIn('--base-href=/pages/', command)
        self.assertNotIn('--base-href=/', command)

    def test_analysis_does_not_receive_unsupported_dart_define_flags(self):
        self.assertEqual(flutter_with_config.build_command('flutter', ['analyze'], Path('defines.json'), {}), ['flutter', 'analyze'])

    def test_wrapper_passes_allowlisted_file_to_real_subprocess(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            profile = root / 'public.json'
            profile.write_text(json.dumps({'DUOYI_SERVER_URL': 'https://custom.example', 'DUOYI_UPDATE_REPOSITORY': 'owner/fork'}))
            fake = root / 'flutter'
            fake.write_text('#!' + sys.executable + '\nimport json,pathlib,sys\npathlib.Path(' + repr(str(root / 'arguments.json')) + ').write_text(json.dumps(sys.argv[1:]))\n')
            fake.chmod(0o755)
            with patch.object(flutter_with_config, 'PROJECT_ROOT', root), patch.dict(os.environ, {}, clear=True):
                result = flutter_with_config.main(['--config', str(profile), '--flutter-bin', str(fake), 'build', 'apk', '--release'])
            self.assertEqual(result, 0)
            arguments = json.loads((root / 'arguments.json').read_text())
            defines = json.loads((root / 'build/config/client-defines.json').read_text())
            self.assertIn('--dart-define-from-file=' + str(root / 'build/config/client-defines.json'), arguments)
            self.assertEqual(defines['DUOYI_SERVER_URL'], 'https://custom.example')
            self.assertEqual(set(defines), set(deployment.CLIENT_KEYS))

    def test_missing_flutter_reports_a_configuration_error(self):
        with patch('shutil.which', return_value=None), contextlib.redirect_stderr(io.StringIO()) as errors:
            result = flutter_with_config.main(['--flutter-bin', 'missing-flutter', 'build', 'apk'])
        self.assertEqual(result, 2)
        self.assertIn('Flutter executable not found', errors.getvalue())


if __name__ == '__main__':
    unittest.main()
