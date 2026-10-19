import 'dart:io';

import 'package:test/test.dart';

import '../test_support/bash_test_utils.dart';

void main() {
  late Directory tempDir;
  late Directory binDir;
  late Directory sdkDir;
  late Directory outputDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('duoyi-device-ready-');
    binDir = Directory('${tempDir.path}/bin')..createSync(recursive: true);
    sdkDir = Directory('${tempDir.path}/android-sdk')..createSync();
    outputDir = Directory('${tempDir.path}/report');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'device readiness report records missing Android and iOS runtimes',
    () async {
      final flutter = _writeExecutable(
        '${binDir.path}/flutter',
        '''#!/usr/bin/env bash
if [[ "\$1" == "devices" && "\${2:-}" == "--machine" ]]; then
  printf '[{"name":"Linux","targetPlatform":"linux-arm64"}]\n'
else
  printf 'Found 1 connected device:\n  Linux (desktop)\n'
fi
''',
      );
      final adb = _writeExecutable('${binDir.path}/adb', '''#!/usr/bin/env bash
printf 'List of devices attached\n\n'
''');

      final result = await Process.run(
        'bash',
        ['scripts/generate_device_readiness_report.sh'],
        workingDirectory: Directory.current.path,
        environment: bashEnvironment(
          {
            'FLUTTER_BIN': flutter.path,
            'ADB_BIN': adb.path,
            'ANDROID_SDK_ROOT': sdkDir.path,
            'OUTPUT_DIR': outputDir.path,
          },
          pathVariables: {
            'FLUTTER_BIN',
            'ADB_BIN',
            'ANDROID_SDK_ROOT',
            'OUTPUT_DIR',
          },
        ),
        includeParentEnvironment: true,
      );

      expect(result.exitCode, 0, reason: _combinedOutput(result));
      final status = _readStatus(outputDir);
      expect(status['host_architecture'], 'available');
      expect(status['android_runtime'], 'missing');
      expect(status['ios_runtime'], 'missing');
      expect(status['adb_device'], 'missing');
      expect(status['android_emulator_binary'], 'missing');
      expect(status['android_emulator_launchability'], 'missing');
      final iosHostReady =
          Platform.isMacOS &&
          Process.runSync('bash', [
                '-c',
                'command -v xcrun >/dev/null && command -v xcodebuild >/dev/null',
              ]).exitCode ==
              0;
      expect(status['ios_host'], iosHostReady ? 'ready' : 'missing');
      expect(File('${outputDir.path}/host_uname.txt').existsSync(), isTrue);

      final validation = await _runValidator(outputDir);
      expect(validation.exitCode, 0, reason: _combinedOutput(validation));
    },
  );

  test(
    'device readiness treats an empty system-images directory as missing',
    () async {
      final flutter = _writeExecutable(
        '${binDir.path}/flutter',
        '''#!/usr/bin/env bash
if [[ "\$1" == "devices" && "\${2:-}" == "--machine" ]]; then
  printf '[]\n'
else
  printf 'No devices\n'
fi
''',
      );
      final adb = _writeExecutable('${binDir.path}/adb', '''#!/usr/bin/env bash
printf 'List of devices attached\n\n'
''');
      Directory('${sdkDir.path}/system-images').createSync(recursive: true);

      final result = await Process.run(
        'bash',
        ['scripts/generate_device_readiness_report.sh'],
        workingDirectory: Directory.current.path,
        environment: bashEnvironment(
          {
            'FLUTTER_BIN': flutter.path,
            'ADB_BIN': adb.path,
            'ANDROID_SDK_ROOT': sdkDir.path,
            'OUTPUT_DIR': outputDir.path,
            'KVM_DEVICE': '${tempDir.path}/missing-kvm',
          },
          pathVariables: {
            'FLUTTER_BIN',
            'ADB_BIN',
            'ANDROID_SDK_ROOT',
            'OUTPUT_DIR',
            'KVM_DEVICE',
          },
        ),
        includeParentEnvironment: true,
      );

      expect(result.exitCode, 0, reason: _combinedOutput(result));
      final status = _readStatus(outputDir);
      expect(status['android_system_images'], 'missing');
      expect(status['kvm'], 'missing');
      expect(status['android_emulator_launchability'], 'missing');
    },
  );

  test('device readiness validator rejects duplicate rows', () async {
    outputDir.createSync(recursive: true);
    File('${outputDir.path}/summary.tsv').writeAsStringSync(
      '''check\tstatus\tdetail
android_runtime\tmissing\tone
android_runtime\tmissing\ttwo
''',
    );
    File('${outputDir.path}/summary.md').writeAsStringSync(
      '# Device Readiness Report\nandroid_runtime\nios_host\n',
    );
    for (final artifact in [
      'flutter_devices.txt',
      'flutter_devices_machine.json',
      'adb_devices.txt',
      'sdkmanager_list.txt',
      'avd_list.txt',
      'host_uname.txt',
    ]) {
      File('${outputDir.path}/$artifact').writeAsStringSync(artifact);
    }

    final result = await _runValidator(outputDir);

    expect(result.exitCode, isNot(0));
    expect(
      _combinedOutput(result),
      contains('summary.tsv must contain exactly one row for android_runtime'),
    );
  });

  test('missing readiness summary extracts only missing rows', () async {
    outputDir.createSync(recursive: true);
    File('${outputDir.path}/summary.tsv').writeAsStringSync(
      '''check\tstatus\tdetail
android_runtime\tmissing\tno Android runtime
ios_runtime\tmissing\tno iOS runtime
kvm\tavailable\t/dev/kvm exists
''',
    );
    File('${outputDir.path}/summary.md').writeAsStringSync(
      '# Device Readiness Report\nandroid_runtime\nios_host\n',
    );
    for (final artifact in [
      'flutter_devices.txt',
      'flutter_devices_machine.json',
      'adb_devices.txt',
      'sdkmanager_list.txt',
      'avd_list.txt',
    ]) {
      File('${outputDir.path}/$artifact').writeAsStringSync(artifact);
    }
    final missingDir = Directory('${tempDir.path}/missing');

    final result = await Process.run(
      'bash',
      ['scripts/summarize_device_readiness_missing.sh'],
      workingDirectory: Directory.current.path,
      environment: bashEnvironment(
        {'READINESS_DIR': outputDir.path, 'OUTPUT_DIR': missingDir.path},
        pathVariables: {'READINESS_DIR', 'OUTPUT_DIR'},
      ),
      includeParentEnvironment: true,
    );

    expect(result.exitCode, 0, reason: _combinedOutput(result));
    final missing = File('${missingDir.path}/missing.tsv').readAsStringSync();
    expect(missing, contains('android_runtime\tno Android runtime'));
    expect(missing, contains('ios_runtime\tno iOS runtime'));
    expect(missing, isNot(contains('kvm')));

    final validation = await Process.run(
      'bash',
      ['scripts/validate_device_readiness_missing.sh'],
      workingDirectory: Directory.current.path,
      environment: bashEnvironment(
        {'REPORT_DIR': missingDir.path},
        pathVariables: {'REPORT_DIR'},
      ),
      includeParentEnvironment: true,
    );
    expect(validation.exitCode, 0, reason: _combinedOutput(validation));
  });
}

File _writeExecutable(String path, String content) {
  final file = File(path)..writeAsStringSync(content);
  final result = chmodForBash(path);
  if (result.exitCode != 0) {
    throw StateError(_combinedOutput(result));
  }
  return file;
}

Future<ProcessResult> _runValidator(Directory outputDir) {
  return Process.run(
    'bash',
    ['scripts/validate_device_readiness_report.sh'],
    workingDirectory: Directory.current.path,
    environment: bashEnvironment(
      {'REPORT_DIR': outputDir.path},
      pathVariables: {'REPORT_DIR'},
    ),
    includeParentEnvironment: true,
  );
}

Map<String, String> _readStatus(Directory dir) {
  final rows = File('${dir.path}/summary.tsv').readAsLinesSync().skip(1);
  return {for (final row in rows) row.split('\t')[0]: row.split('\t')[1]};
}

String _combinedOutput(ProcessResult result) {
  return '${result.stdout}\n${result.stderr}';
}
