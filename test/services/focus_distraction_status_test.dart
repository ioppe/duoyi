import 'dart:typed_data';

import 'package:duoyi/services/focus_distraction_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 最小合法 PNG 头 + 内容（1x1 透明像素）。只用于验证“合法字节被接受”，
/// 不参与真实渲染。
Uint8List validPngBytes() => Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

void main() {
  group('FocusDistractionStatus 保留授权字段', () {
    const granted = FocusDistractionStatus(
      supported: true,
      accessGranted: true,
      accessibilityGranted: true,
      accessibilityActive: true,
      blockerConfigured: true,
      blockerExpiresAtMs: 1700000000000,
      foregroundPackage: 'com.example.reader',
      lastBlockedPackage: 'com.tencent.mm',
      lastBlockedAtMs: 1699999999000,
    );

    test('copyWith 只改指定字段，授权/拦截状态原样保留', () {
      final next = granted.copyWith(foregroundPackage: 'com.android.chrome');
      expect(next.foregroundPackage, 'com.android.chrome');
      expect(next.accessibilityGranted, isTrue);
      expect(next.accessibilityActive, isTrue);
      expect(next.accessGranted, isTrue);
      expect(next.blockerConfigured, isTrue);
      expect(next.blockerExpiresAtMs, 1700000000000);
      expect(next.lastBlockedPackage, 'com.tencent.mm');
      expect(next.lastBlockedAtMs, 1699999999000);
      expect(next.canBlockForeground, isTrue);
    });

    test('withForeground 不丢弃上次授权结果，也不清空原生拦截事件', () {
      const partial = FocusDistractionStatus(
        supported: false,
        accessGranted: false,
        accessibilityGranted: true,
        blockerConfigured: true,
        lastBlockedPackage: 'com.ss.android.ugc.aweme',
        lastBlockedAtMs: 42,
      );
      final merged = partial.withForeground('com.tencent.mm');
      expect(merged.foregroundPackage, 'com.tencent.mm');
      expect(merged.accessibilityGranted, isTrue);
      expect(merged.blockerConfigured, isTrue);
      expect(merged.lastBlockedPackage, 'com.ss.android.ugc.aweme');
      expect(merged.lastBlockedAtMs, 42);
      // 拿到前台包意味着使用情况访问实际可用。
      expect(merged.accessGranted, isTrue);
      // 通道失败（supported=false）不得因为一次前台更新被伪造成 supported。
      expect(merged.supported, isFalse);
    });

    test('fromMap 解析原生新增字段并容忍缺失/非法值', () {
      final status = FocusDistractionStatus.fromMap(<String, dynamic>{
        'supported': true,
        'accessGranted': true,
        'accessibilityGranted': true,
        'accessibilityActive': false,
        'blockerConfigured': true,
        'blockerExpiresAt': 1700000000000,
        'lastBlockedPackage': ' com.tencent.mm ',
        'lastBlockedAt': 1699999999000,
        'foregroundPackage': '  ',
      });
      expect(status.accessibilityActive, isFalse);
      expect(status.blockerExpiresAtMs, 1700000000000);
      expect(status.lastBlockedPackage, 'com.tencent.mm');
      expect(status.lastBlockedAtMs, 1699999999000);
      expect(status.foregroundPackage, isNull);

      final malformed = FocusDistractionStatus.fromMap(<String, dynamic>{
        'supported': true,
        'accessGranted': false,
        'blockerExpiresAt': 'not-a-number',
        'lastBlockedAt': -3,
      });
      expect(malformed.blockerExpiresAtMs, isNull);
      expect(malformed.lastBlockedAtMs, isNull);
      expect(malformed.lastBlockedPackage, isNull);
    });
  });

  group('InstalledFocusApp 图标解析', () {
    test('合法 PNG 字节被保留，顺序与原生返回一致', () {
      final apps = <InstalledFocusApp>[];
      for (final raw in <Map<String, dynamic>>[
        {
          'label': '微信',
          'packageName': 'com.tencent.mm',
          'iconBytes': validPngBytes(),
        },
        {
          'label': '设置',
          'packageName': 'com.android.settings',
          'isSystemApp': true,
        },
      ]) {
        final app = InstalledFocusApp.fromMap(raw);
        if (app != null) apps.add(app);
      }
      expect(apps.map((app) => app.packageName).toList(), <String>[
        'com.tencent.mm',
        'com.android.settings',
      ]);
      expect(apps.first.hasIcon, isTrue);
      expect(apps.last.hasIcon, isFalse);
      expect(apps.last.isSystemApp, isTrue);
    });

    test('损坏/截断/非 PNG/类型错误的数据回退为无图标', () {
      final corrupt = <Object?>[
        Uint8List.fromList(<int>[0x89, 0x50, 0x4E]), // 截断
        Uint8List.fromList(<int>[
          0xFF,
          0xD8,
          0xFF,
          0xE0,
          0,
          0,
          0,
          0,
          0,
        ]), // JPEG
        'not-bytes',
        <int>[1, 2, 3, 4, 5, 6, 7, 8, 9],
        const <int>[],
      ];
      for (final raw in corrupt) {
        final app = InstalledFocusApp.fromMap(<String, dynamic>{
          'label': 'Broken',
          'packageName': 'com.example.broken',
          'iconBytes': raw,
        });
        expect(app, isNotNull);
        expect(app!.hasIcon, isFalse, reason: 'raw=$raw');
        expect(app.iconBytes, isNull);
      }
    });

    test('缺包名的记录被丢弃，空标签回退包名', () {
      expect(
        InstalledFocusApp.fromMap(<String, dynamic>{'label': 'x'}),
        isNull,
      );
      final app = InstalledFocusApp.fromMap(<String, dynamic>{
        'label': '  ',
        'packageName': ' com.example.app ',
      });
      expect(app!.packageName, 'com.example.app');
      expect(app.displayLabel, 'com.example.app');
    });
  });

  group('原生拦截事件消费与去重', () {
    FocusNativeBlockEvent event(String package, int at) =>
        FocusNativeBlockEvent(packageName: package, blockedAtMs: at);

    test('fromStatus 忽略空包名/缺失时间/时间非正', () {
      expect(
        FocusNativeBlockEvent.fromStatus(
          const FocusDistractionStatus(
            supported: true,
            accessGranted: true,
            lastBlockedPackage: 'com.tencent.mm',
          ),
        ),
        isNull,
      );
      expect(
        FocusNativeBlockEvent.fromStatus(
          const FocusDistractionStatus(
            supported: true,
            accessGranted: true,
            lastBlockedPackage: '  ',
            lastBlockedAtMs: 10,
          ),
        ),
        isNull,
      );
      final parsed = FocusNativeBlockEvent.fromStatus(
        const FocusDistractionStatus(
          supported: true,
          accessGranted: true,
          lastBlockedPackage: ' com.tencent.mm ',
          lastBlockedAtMs: 10,
        ),
      );
      expect(parsed!.packageName, 'com.tencent.mm');
      expect(parsed.blockedAtMs, 10);
    });

    test('新事件记录一次，重复时间戳不重复记录', () {
      final blocked = <String>['com.tencent.mm'];
      expect(
        event('com.tencent.mm', 100).shouldRecord(
          lastConsumedBlockedAtMs: 0,
          lastRecordedPackage: null,
          blockedPackages: blocked,
        ),
        isTrue,
      );
      expect(
        event('com.tencent.mm', 100).shouldRecord(
          lastConsumedBlockedAtMs: 100,
          lastRecordedPackage: 'com.tencent.mm',
          blockedPackages: blocked,
        ),
        isFalse,
      );
    });

    test('轮询已记录同一包名时原生事件去重', () {
      expect(
        event('com.tencent.mm', 200).shouldRecord(
          lastConsumedBlockedAtMs: 0,
          lastRecordedPackage: 'com.tencent.mm',
          blockedPackages: const <String>['com.tencent.mm'],
        ),
        isFalse,
      );
    });

    test('不在拦截集合内的事件不记录；用户回到多仪后可再次记录', () {
      expect(
        event('com.example.reader', 300).shouldRecord(
          lastConsumedBlockedAtMs: 0,
          lastRecordedPackage: null,
          blockedPackages: const <String>['com.tencent.mm'],
        ),
        isFalse,
      );
      // 回到多仪会把 lastRecordedPackage 清空 => 新的原生拦截事件再次记录。
      expect(
        event('com.tencent.mm', 400).shouldRecord(
          lastConsumedBlockedAtMs: 300,
          lastRecordedPackage: null,
          blockedPackages: const <String>['com.tencent.mm'],
        ),
        isTrue,
      );
    });
  });

  group('blocker 失效时间', () {
    const now = 1700000000000;

    test('倒计时对齐会话结束锚点', () {
      expect(
        FocusBlockerLease.expiresAtMs(
          isCountUp: false,
          activeAnchorMs: now + 600000,
          remainingSeconds: 600,
          nowMs: now,
        ),
        now + 600000,
      );
    });

    test('锚点缺失/已过期时退回剩余时长', () {
      expect(
        FocusBlockerLease.expiresAtMs(
          isCountUp: false,
          activeAnchorMs: null,
          remainingSeconds: 90,
          nowMs: now,
        ),
        now + 90000,
      );
      expect(
        FocusBlockerLease.expiresAtMs(
          isCountUp: false,
          activeAnchorMs: now - 1,
          remainingSeconds: 0,
          nowMs: now,
        ),
        now,
      );
    });

    test('正计时给出有限租约而不是无限拦截', () {
      expect(
        FocusBlockerLease.expiresAtMs(
          isCountUp: true,
          activeAnchorMs: now - 3600000,
          remainingSeconds: 3600,
          nowMs: now,
        ),
        now + FocusBlockerLease.countUpLeaseSeconds * 1000,
      );
    });

    test('剩余有效期不足续租窗口才需要续租', () {
      expect(
        FocusBlockerLease.needsRenewal(expiresAtMs: null, nowMs: now),
        isTrue,
      );
      expect(
        FocusBlockerLease.needsRenewal(expiresAtMs: now + 600000, nowMs: now),
        isFalse,
      );
      expect(
        FocusBlockerLease.needsRenewal(expiresAtMs: now + 1000, nowMs: now),
        isTrue,
      );
      expect(
        FocusBlockerLease.needsRenewal(expiresAtMs: now - 1000, nowMs: now),
        isTrue,
      );
    });
  });
}
