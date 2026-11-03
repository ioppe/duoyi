import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stable tag releases wait for every platform and become Latest', () {
    final workflow = File('.github/workflows/build-apk.yml').readAsStringSync();
    final match = RegExp(
      r'^  release:\n([\s\S]*)',
      multiLine: true,
    ).firstMatch(workflow);
    expect(match, isNotNull, reason: '正式发布必须保留独立的 release 作业');
    final release = match!.group(1)!;

    expect(release, contains('needs: [android, web, macos]'));
    expect(release, contains("startsWith(github.ref, 'refs/tags/v')"));
    for (final platform in ['android', 'web', 'macos']) {
      expect(release, contains("needs.$platform.result == 'success'"));
    }
    expect(release, contains('make_latest: true'));
    expect(
      release,
      contains('body_path: \${{ steps.release_notes.outputs.body_path }}'),
    );
    expect(release, contains('name: duoyi-android'));
    expect(release, contains('name: duoyi-web'));
    expect(release, contains('name: duoyi-macos-universal-unsigned'));
    expect(release, isNot(contains('draft: true')));
    expect(release, isNot(contains('prerelease: true')));
  });
}
