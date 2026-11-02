import 'dart:io';

import 'package:test/test.dart';

/// 读取 [key] 在 [indent] 空格缩进层级的区块正文（不含标题行）。
///
/// 只收集比标题缩进更深的行，遇到同级或更浅的键即结束，因此断言只会命中
/// 目标事件/作业区块，而不会在整份文件里误中注释或其它作业的同名配置。
String _block(String source, String key, {int indent = 0}) {
  final header = '${' ' * indent}$key:';
  final lines = source.split('\n');
  final start = lines.indexWhere((line) => line == header);
  if (start < 0) {
    throw StateError('Missing "$header" block in workflow source');
  }
  final body = <String>[];
  for (var i = start + 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) {
      body.add(line);
      continue;
    }
    final leading = line.length - line.trimLeft().length;
    if (leading <= indent) {
      break;
    }
    body.add(line);
  }
  return body.join('\n');
}

/// 解析 `key: [a, b]` 形式的行内列表，未加引号/带引号都支持。
List<String> _inlineList(String block, String key) {
  final match = RegExp(
    '^\\s*${RegExp.escape(key)}:\\s*\\[([^\\]]*)\\]',
    multiLine: true,
  ).firstMatch(block);
  if (match == null) {
    throw StateError('Missing inline list "$key: [...]"');
  }
  return match
      .group(1)!
      .split(',')
      .map((value) => _unquote(value.trim()))
      .where((value) => value.isNotEmpty)
      .toList();
}

String _unquote(String value) {
  final quoted =
      value.length >= 2 && value.startsWith("'") && value.endsWith("'") ||
      value.length >= 2 && value.startsWith('"') && value.endsWith('"');
  return quoted ? value.substring(1, value.length - 1) : value;
}

/// 取出 `key: value` 的标量值；缺失返回 null。
String? _scalar(String block, String key) {
  final match = RegExp(
    '^\\s*${RegExp.escape(key)}:\\s*(.+)\$',
    multiLine: true,
  ).firstMatch(block);
  return match?.group(1)?.trim();
}

/// 列出区块内恰好位于 [indent] 缩进的键名，用于判断触发了哪些事件。
Set<String> _keysAt(String block, int indent) {
  final keys = <String>{};
  for (final line in block.split('\n')) {
    if (line.length <= indent) {
      continue;
    }
    if (line.substring(0, indent).trim().isNotEmpty) {
      continue;
    }
    if (line[indent] == ' ') {
      continue;
    }
    final match = RegExp(
      r'^([A-Za-z_][A-Za-z0-9_-]*):',
    ).firstMatch(line.substring(indent));
    if (match != null) {
      keys.add(match.group(1)!);
    }
  }
  return keys;
}

void main() {
  test('push 到受支持分支时同时触发 Android 与 macOS 安装包构建', () {
    final workflow = File('.github/workflows/build-apk.yml').readAsStringSync();
    final on = _block(workflow, 'on');
    final push = _block(on, 'push', indent: 2);

    expect(
      _inlineList(push, 'branches'),
      containsAll(<String>['main', 'self-hosted-skydrow', 'build/macos-dmg']),
      reason: '推送 main/self-hosted-skydrow/build/macos-dmg 都必须触发多端安装包构建.',
    );
    expect(
      _inlineList(push, 'tags'),
      contains('v*'),
      reason: '版本标签推送仍需触发安装包构建与 Release.',
    );

    final pullRequest = _block(on, 'pull_request', indent: 2);
    expect(
      _inlineList(pullRequest, 'branches'),
      unorderedEquals(<String>['main', 'self-hosted-skydrow']),
      reason: '分支推送纳入自动构建不应扩大拉取请求的触发范围.',
    );
  });

  test('macOS 子流程只允许主流程调用或手动触发，不再自行响应 push', () {
    final child = File('.github/workflows/build-macos.yml').readAsStringSync();
    final on = _block(child, 'on');

    expect(
      _keysAt(on, 2),
      unorderedEquals(<String>['workflow_dispatch', 'workflow_call']),
      reason: '子流程保留 push 会与主流程重复构建 macOS 安装包.',
    );

    final call = _block(on, 'workflow_call', indent: 2);
    final inputs = _block(call, 'inputs', indent: 4);
    final profile = _block(inputs, 'deployment_profile', indent: 6);
    expect(_scalar(profile, 'type'), 'string');
    expect(
      _scalar(profile, 'required'),
      'true',
      reason: '被调用时必须收到主流程校验过的部署配置.',
    );

    expect(_block(child, 'permissions'), contains('contents: read'));
    expect(_block(child, 'concurrency'), contains('macos-'));
  });

  test(
    'android/macOS/Web 都复用共享 analyze/configuration，macOS 复用子流程并传递共享 profile',
    () {
      final workflow = File(
        '.github/workflows/build-apk.yml',
      ).readAsStringSync();
      final jobs = _block(workflow, 'jobs');
      final android = _block(jobs, 'android', indent: 2);
      final macos = _block(jobs, 'macos', indent: 2);
      final web = _block(jobs, 'web', indent: 2);

      final platformJobs = <String, String>{
        'android': android,
        'macos': macos,
        'web': web,
      };
      for (final entry in platformJobs.entries) {
        expect(
          _inlineList(entry.value, 'needs'),
          containsAll(<String>['analyze', 'configuration']),
          reason: '${entry.key} 作业必须等待共享的配置校验与测试门禁.',
        );
      }

      expect(
        _scalar(macos, 'uses'),
        './.github/workflows/build-macos.yml',
        reason: 'macOS 打包逻辑应保留在可复用子流程中.',
      );
      expect(
        _scalar(_block(macos, 'with', indent: 4), 'deployment_profile'),
        r'${{ needs.configuration.outputs.profile }}',
        reason: 'macOS 必须使用同一 SHA 下共享的部署配置 profile.',
      );
    },
  );

  test('手动触发 macOS 默认构建，但分支推送不会被输入跳过', () {
    final workflow = File('.github/workflows/build-apk.yml').readAsStringSync();
    final on = _block(workflow, 'on');
    final inputs = _block(
      _block(on, 'workflow_dispatch', indent: 2),
      'inputs',
      indent: 4,
    );
    final macosInput = _block(inputs, 'build_macos', indent: 6);
    expect(_scalar(macosInput, 'type'), 'boolean');
    expect(_scalar(macosInput, 'default'), 'true');

    final jobs = _block(workflow, 'jobs');
    final guard = _scalar(_block(jobs, 'macos', indent: 2), 'if') ?? '';
    expect(guard, contains("github.event_name != 'workflow_dispatch'"));
    expect(
      guard,
      contains('|| inputs.build_macos'),
      reason: 'build_macos 只能跳过手动运行，push 必须始终构建 macOS 安装包.',
    );
  });

  test('Web 作业在 main、自动分支推送、手动构建与标签时都产出 duoyi-web 安装包', () {
    final workflow = File('.github/workflows/build-apk.yml').readAsStringSync();
    final jobs = _block(workflow, 'jobs');
    final web = _block(jobs, 'web', indent: 2);

    // 折叠 if 只取 Web 作业自己的六空格续行，避免命中注释或其它作业的同名文本。
    final lines = web.split('\n');
    final start = lines.indexWhere((line) => line.trim() == 'if: >');
    expect(start, isNonNegative, reason: 'Web 作业的条件必须保持折叠写法.');
    final guardLines = <String>[];
    for (var i = start + 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty || line.length - line.trimLeft().length != 6) {
        break;
      }
      guardLines.add(line.trim());
    }
    final guard = guardLines.join(' ');

    expect(guard, contains("github.ref == 'refs/heads/main'"));
    expect(guard, contains("github.event.inputs.build_web == 'true'"));
    expect(guard, contains("startsWith(github.ref, 'refs/tags/v')"));
    expect(
      guard,
      contains(
        "github.event_name == 'push' && (github.ref == 'refs/heads/self-hosted-skydrow' || github.ref == 'refs/heads/build/macos-dmg')",
      ),
      reason: '推送 self-hosted-skydrow / build/macos-dmg 时也要构建 Web 桌面/手机包.',
    );
    expect(web, contains('name: duoyi-web'));
    expect(
      _scalar(_block(jobs, 'deploy-pages', indent: 2), 'if') ?? '',
      contains("github.ref == 'refs/heads/main'"),
      reason: 'Pages 部署仍只允许 main.',
    );
  });

  test('Release 仅由版本标签触发，Android 缺少 release keystore 时直接失败', () {
    final workflow = File('.github/workflows/build-apk.yml').readAsStringSync();
    final jobs = _block(workflow, 'jobs');

    final release = _block(jobs, 'release', indent: 2);
    expect(
      _scalar(release, 'if'),
      contains("startsWith(github.ref, 'refs/tags/v')"),
      reason: '分支推送只产出 CI 安装包，不应自动发布 Release.',
    );
    expect(
      _inlineList(release, 'needs'),
      containsAll(<String>['android', 'web', 'macos']),
      reason: 'Release 需要全部平台的构建结果.',
    );

    final android = _block(jobs, 'android', indent: 2);
    expect(android, contains('Require release keystore'));
    expect(
      android,
      contains('refusing to build release artifacts with debug signing'),
    );
    expect(android, contains('exit 1'));
    expect(
      android,
      isNot(contains('--debug')),
      reason: '缺少签名密钥时必须失败，不能降级为 debug 签名.',
    );
  });
}
