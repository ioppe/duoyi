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

Future<Directory> _buildAppFixture(List<String> architectures) async {
  final temporary = await Directory.systemTemp.createTemp('duoyi lipo ');
  addTearDown(() => temporary.delete(recursive: true));
  final app = Directory('${temporary.path}/Duoyi sample.app');
  final executable = File('${app.path}/Contents/MacOS/Duoyi');
  await executable.parent.create(recursive: true);
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
}
