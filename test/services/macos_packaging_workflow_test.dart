import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

List<String> _verificationCommands() {
  final commands = File('.github/workflows/build-macos.yml')
      .readAsLinesSync()
      .map((line) => line.trim())
      .where(
        (line) => line.startsWith('lipo ') && line.contains('-verify_arch'),
      )
      .toList();
  expect(commands, isNotEmpty, reason: 'macOS 打包前必须执行架构校验');
  return commands;
}

const String _fixtureInfoPlist = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>CFBundleIdentifier</key>
\t<string>com.duoyi.duoyi</string>
\t<key>CFBundleExecutable</key>
\t<string>Duoyi</string>
\t<key>CFBundleName</key>
\t<string>Duoyi</string>
\t<key>CFBundlePackageType</key>
\t<string>APPL</string>
\t<key>CFBundleShortVersionString</key>
\t<string>2.0.0</string>
\t<key>CFBundleVersion</key>
\t<string>140023</string>
\t<key>LSMinimumSystemVersion</key>
\t<string>11.0</string>
</dict>
</plist>
''';

/// 旧发行包的受限 entitlements：普通 `codesign --verify` 仍会通过。
const String _restrictedEntitlements = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>com.apple.security.app-sandbox</key>
\t<true/>
\t<key>com.apple.security.network.client</key>
\t<true/>
\t<key>com.apple.security.files.user-selected.read-write</key>
\t<true/>
\t<key>com.apple.security.get-task-allow</key>
\t<true/>
\t<key>keychain-access-groups</key>
\t<array>
\t\t<string>com.duoyi.duoyi</string>
\t</array>
</dict>
</plist>
''';

const Set<String> _expectedAdhocEntitlements = <String>{
  'com.apple.security.app-sandbox',
  'com.apple.security.network.client',
  'com.apple.security.files.user-selected.read-write',
};

Future<Directory> _buildAppFixture(List<String> architectures) async {
  final temporary = await Directory.systemTemp.createTemp('duoyi lipo ');
  addTearDown(() => temporary.delete(recursive: true));
  final app = Directory('${temporary.path}/多仪 sample.app');
  final executable = File('${app.path}/Contents/MacOS/Duoyi');
  await executable.parent.create(recursive: true);
  await File(
    '${app.path}/Contents/Info.plist',
  ).writeAsString(_fixtureInfoPlist);
  final source = File('${temporary.path}/main.c');
  await source.writeAsString('int main(void) { return 0; }\n');
  final result = await Process.run('xcrun', [
    'clang',
    for (final architecture in architectures) ...['-arch', architecture],
    source.path,
    '-o',
    executable.path,
  ]).timeout(const Duration(seconds: 30));
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  return app;
}

Future<ProcessResult> _verifyApp(Directory app) => Process.run(
  '/bin/bash',
  ['-euo', 'pipefail', '-c', _verificationCommands().join('\n')],
  environment: {'APP_PATH': app.path, 'APP_EXECUTABLE': 'Duoyi'},
).timeout(const Duration(seconds: 30));

/// 运行仓库里的 ad-hoc 打包脚本，路径与工作流保持一致。
Future<ProcessResult> _runAdhocPackage(List<String> arguments) => Process.run(
  'python3',
  <String>['scripts/macos_adhoc_package.py', ...arguments],
).timeout(const Duration(minutes: 2));

Future<void> _signAdhoc(Directory app, File entitlements) async {
  final result = await Process.run('/usr/bin/codesign', <String>[
    '--force',
    '--sign',
    '-',
    '--timestamp=none',
    '--entitlements',
    entitlements.path,
    app.path,
  ]).timeout(const Duration(seconds: 60));
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
}

/// 独立于脚本实现读取真实签名 entitlements：`codesign -d :-` 输出 XML 后转 JSON。
Future<Map<String, dynamic>> _signedEntitlements(Directory app) async {
  final dumped = await Process.run('/usr/bin/codesign', <String>[
    '-d',
    '--entitlements',
    ':-',
    app.path,
  ]).timeout(const Duration(seconds: 30));
  expect(dumped.exitCode, 0, reason: '${dumped.stdout}\n${dumped.stderr}');
  final raw = dumped.stdout as String;
  final start = raw.indexOf('<?xml');
  expect(start, isNonNegative, reason: 'codesign 未输出 XML entitlements: $raw');
  final plist = File('${app.parent.path}/signed-entitlements.plist');
  await plist.writeAsString(raw.substring(start));
  final converted = await Process.run('/usr/bin/plutil', <String>[
    '-convert',
    'json',
    '-o',
    '-',
    plist.path,
  ]).timeout(const Duration(seconds: 30));
  expect(
    converted.exitCode,
    0,
    reason: '${converted.stdout}\n${converted.stderr}',
  );
  return jsonDecode(converted.stdout as String) as Map<String, dynamic>;
}

Map<String, dynamic> _checkResult(ProcessResult result, String name) {
  final report = jsonDecode(result.stdout as String) as Map<String, dynamic>;
  final checks = (report['checks'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  return checks.firstWhere((check) => check['name'] == name);
}

void main() {
  test(
    'macOS packaging accepts a real universal executable in a path with spaces',
    () async {
      final app = await _buildAppFixture(['arm64', 'x86_64']);
      final result = await _verifyApp(app);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
    skip: !Platform.isMacOS,
  );

  test(
    'macOS packaging rejects an executable missing the Intel architecture',
    () async {
      final app = await _buildAppFixture(['arm64']);
      final result = await _verifyApp(app);
      expect(result.exitCode, isNot(0), reason: '单架构二进制不能作为 universal 安装包发布');
    },
    skip: !Platform.isMacOS,
  );

  test(
    'ad-hoc packaging rejects a restricted keychain group that ordinary codesign accepts',
    () async {
      final app = await _buildAppFixture(['arm64', 'x86_64']);
      final entitlements = File('${app.parent.path}/restricted.entitlements');
      await entitlements.writeAsString(_restrictedEntitlements);
      await _signAdhoc(app, entitlements);

      final ordinary = await Process.run('/usr/bin/codesign', <String>[
        '--verify',
        '--deep',
        '--strict',
        app.path,
      ]).timeout(const Duration(seconds: 30));
      expect(
        ordinary.exitCode,
        0,
        reason: '回归前提：普通 codesign verify 对带受限 group 的错误包仍通过',
      );

      final beforeInfo = await File(
        '${app.path}/Contents/Info.plist',
      ).readAsBytes();
      final rejected = await _runAdhocPackage(<String>[
        'verify',
        '--app',
        app.path,
      ]);
      expect(
        rejected.exitCode,
        isNot(0),
        reason: '带 keychain-access-groups 的旧包必须在签名校验阶段被拒绝',
      );
      expect(
        _checkResult(rejected, 'codesign-deep-strict')['ok'],
        isTrue,
        reason: '拒绝原因必须是 entitlements，而不是 codesign 本身失败',
      );
      final rejectedEntitlements = _checkResult(
        rejected,
        'signed-entitlements',
      );
      expect(rejectedEntitlements['ok'], isFalse);
      expect(
        rejectedEntitlements['detail'],
        contains('keychain-access-groups'),
      );

      final prepared = await _runAdhocPackage(<String>[
        'prepare',
        '--app',
        app.path,
      ]);
      expect(
        prepared.exitCode,
        0,
        reason: '${prepared.stdout}\n${prepared.stderr}',
      );

      final signed = await _signedEntitlements(app);
      expect(
        signed.keys.toSet(),
        _expectedAdhocEntitlements,
        reason: '重签外层后必须恰好保留三个 ad-hoc entitlements',
      );
      expect(signed.values.every((value) => value == true), isTrue);
      expect(signed.containsKey('keychain-access-groups'), isFalse);
      expect(signed.containsKey('com.apple.security.get-task-allow'), isFalse);
      expect(
        await File('${app.path}/Contents/Info.plist').readAsBytes(),
        beforeInfo,
        reason: 'prepare 不得改写 Info.plist（标识与版本保持原样）',
      );
      final identity = await Process.run('/usr/libexec/PlistBuddy', <String>[
        '-c',
        'Print CFBundleIdentifier',
        '${app.path}/Contents/Info.plist',
      ]).timeout(const Duration(seconds: 30));
      expect((identity.stdout as String).trim(), 'com.duoyi.duoyi');

      final verified = await _runAdhocPackage(<String>[
        'verify',
        '--app',
        app.path,
      ]);
      expect(
        verified.exitCode,
        0,
        reason: '${verified.stdout}\n${verified.stderr}',
      );
      final deepStrict = await Process.run('/usr/bin/codesign', <String>[
        '--verify',
        '--deep',
        '--strict',
        '--verbose=2',
        app.path,
      ]).timeout(const Duration(seconds: 30));
      expect(
        deepStrict.exitCode,
        0,
        reason: '只重签外层后 deep strict 仍必须通过：${deepStrict.stderr}',
      );
    },
    skip: !Platform.isMacOS,
  );

  test(
    'packaging rejects team downgrade and surfaces cleanup failures',
    () async {
      final result = await Process.run(
        Platform.environment['PYTHON_BIN'] ?? 'python3',
        <String>[
          '-B',
          '-c',
          r'''
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
from unittest import mock

spec = importlib.util.spec_from_file_location('adhoc_package', 'scripts/macos_adhoc_package.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)
app = Path('/tmp/duoyi-cleanup-regression/Duoyi sample.app').resolve()
team_display = subprocess.CompletedProcess(
    [], 0, '', 'Signature size=9000\nAuthority=Developer ID Application: Fixture\nTeamIdentifier=TESTTEAM01\n'
)
with mock.patch.object(package, 'run', return_value=team_display) as commands:
    assert package.signature_report(app)['team_identifier'] == 'TESTTEAM01'
    with mock.patch.object(package.sys, 'platform', 'darwin'), mock.patch.object(
        package, 'bundle_info', return_value={'bundle_id': 'com.duoyi.duoyi', 'executable_name': 'Duoyi'}
    ):
        try:
            package.prepare(app)
        except package.PackagingError as error:
            assert 'refusing to downgrade' in str(error) and 'TESTTEAM01' in str(error)
        else:
            raise AssertionError('team-signed application was allowed to reach re-signing')
    assert len(commands.call_args_list) == 2
    assert all('--force' not in call.args[0] for call in commands.call_args_list)

adhoc_display = subprocess.CompletedProcess([], 0, '', 'Signature=adhoc\nTeamIdentifier=not set\n')
with mock.patch.object(package, 'run', return_value=adhoc_display):
    signature = package.signature_report(app)
    assert signature['adhoc'] is True and signature['team_identifier'] == ''

new_process = {'pid': 424242, 'bundlePath': str(app), 'terminated': False}
with mock.patch.object(package, 'inspect_application', side_effect=[
    [], package.PackagingError('startup observation failed'), [new_process]
]), mock.patch.object(package, 'run', return_value=subprocess.CompletedProcess([], 0, '', '')), mock.patch.object(
    package, 'terminate_application', return_value='sigterm'
) as terminate:
    try:
        package.smoke_launch(Path('/unused-probe'), app)
    except package.PackagingError as error:
        assert 'startup observation failed' in str(error)
    else:
        raise AssertionError('startup observation failure was swallowed')
    terminate.assert_called_once_with(Path('/unused-probe'), app, 424242)

fixture = {'executable': Path('/unused-probe'), 'bundleId': 'com.duoyi.fixture'}
with mock.patch.object(package, 'build_keychain_fixture', return_value=fixture), mock.patch.object(
    package, '_run_keychain_phase', side_effect=[
        {'status': 0}, package.PackagingError('keychain read failed'),
        subprocess.TimeoutExpired('fixture delete', 60),
    ]
):
    try:
        package.keychain_round_trip(Path('/unused-scratch'), Path('/unused-binary'))
    except package.PackagingError as error:
        assert 'keychain read failed' in str(error) and 'cleanup failed' in str(error)
    else:
        raise AssertionError('keychain cleanup failure was swallowed')

with tempfile.TemporaryDirectory(prefix='duoyi-detach-test-') as directory, mock.patch.object(
    package, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'volume busy')
):
    try:
        package._detach_dmg(Path(directory))
    except package.PackagingError as error:
        assert 'hdiutil detach failed' in str(error) and 'volume busy' in str(error)
    else:
        raise AssertionError('DMG detach failure was swallowed')
print(json.dumps({'teamDowngradeRejected': True, 'cleanupFailuresReported': True}))
''',
        ],
      ).timeout(const Duration(seconds: 30));
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final report = jsonDecode((result.stdout as String).trim()) as Map;
      expect(report['teamDowngradeRejected'], isTrue);
      expect(report['cleanupFailuresReported'], isTrue);
    },
  );

  test(
    'macOS workflow builds with the legacy keychain switch and validates real packages before upload',
    () {
      final workflow = File(
        '.github/workflows/build-macos.yml',
      ).readAsLinesSync();
      const legacySwitch =
          '--dart-define=DUOYI_MACOS_USE_DATA_PROTECTION_KEYCHAIN=false';

      final buildCommands = workflow
          .where(
            (line) =>
                line.contains('scripts/flutter_with_config.py') &&
                line.contains('build macos'),
          )
          .toList();
      expect(
        buildCommands,
        hasLength(2),
        reason: 'dry-run 与真实构建都要构建同一个 ad-hoc 应用',
      );
      for (final command in buildCommands) {
        expect(
          command,
          contains(legacySwitch),
          reason: 'ad-hoc 发行构建必须关闭 Data Protection Keychain',
        );
      }

      final prepareIndex = workflow.indexWhere(
        (line) => line.contains('scripts/macos_adhoc_package.py prepare'),
      );
      final lipoIndex = workflow.indexWhere(
        (line) =>
            line.trimLeft().startsWith('lipo ') && line.contains('-archs'),
      );
      final checkIndex = workflow.indexWhere(
        (line) =>
            line.contains('scripts/macos_adhoc_package.py check-packages'),
      );
      final uploadIndex = workflow.indexWhere(
        (line) => line.contains('Upload macOS packages'),
      );
      expect(prepareIndex, isNonNegative, reason: '打包步骤必须调用 prepare');
      expect(checkIndex, isNonNegative, reason: '打包步骤必须校验真实 ZIP/DMG');
      expect(uploadIndex, isNonNegative);
      expect(
        prepareIndex,
        lessThan(lipoIndex),
        reason: 'prepare 必须在架构校验与打包之前重签外层 app',
      );
      expect(checkIndex, greaterThan(lipoIndex), reason: 'check 需要真实安装包');
      expect(
        checkIndex,
        lessThan(uploadIndex),
        reason: '真实 ZIP/DMG 启动与 keychain 校验必须在上传前执行',
      );
      expect(
        workflow.any((line) => line.contains('continue-on-error')),
        isFalse,
        reason: 'smoke 与 keychain 失败必须让作业失败，不能 softfail',
      );
      final checkStep = workflow
          .skip(checkIndex)
          .takeWhile((line) => !line.contains('Upload macOS packages'))
          .join('\n');
      expect(checkStep, contains('--package-dir'));
      expect(checkStep, contains('--output'));
      expect(checkStep, contains(r'${{ runner.temp }}'));
      expect(
        workflow.join('\n'),
        contains('duoyi-macos-validation'),
        reason: '验证报告用独立 artifact 上传，不混入用户安装包',
      );
    },
  );
}
