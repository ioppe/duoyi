import 'dart:convert';

import 'package:duoyi/screens/admin_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy coins-only admin permissions never become wildcard access', () {
    expect(parseAdminPermissions(['coins'], isAdmin: true), ['coins']);
    expect(parseAdminPermissions(['coins', 'feedback'], isAdmin: true), [
      'coins',
      'feedback',
    ]);
    expect(parseAdminPermissions([], isAdmin: true), isEmpty);
    expect(parseAdminPermissions(['unknown'], isAdmin: true), isEmpty);
    expect(parseAdminPermissions(['__none__'], isAdmin: true), isEmpty);
    expect(parseAdminPermissions(['*'], isAdmin: true), ['*']);
    expect(parseAdminPermissions(null, isAdmin: true), ['*']);
    expect(parseAdminPermissions(null, isAdmin: false), isEmpty);
  });

  test(
    'historical descriptions and audits hide currency and retain other details',
    () {
      expect(
        adminVisibleDescription('新注册用户默认分组。注册赠送 100 时光币。用于测试'),
        '新注册用户默认分组。用于测试',
      );
      expect(adminAuditActionVisible('user.coins_adjust'), isFalse);
      expect(adminAuditActionVisible('welfare.create'), isFalse);
      expect(adminAuditActionVisible('user.update'), isTrue);
      final detail =
          jsonDecode(
                adminVisibleAuditDetail(
                  jsonEncode({
                    'group_id': 'group_default',
                    'coin_balance': 100,
                    'default_time_coins': 100,
                    'charged': 140,
                    'balance': 100,
                    'lifetime': 200,
                    'ledger_entry': {'coins': 100},
                    'virtual_rewards': {'balance': 100},
                    'creditBalance': 100,
                    'nested': {'email_verified': true, 'lifetime_coins': 200},
                    'permissions': ['coins', 'feedback'],
                  }),
                ),
              )
              as Map<String, dynamic>;
      expect(detail, {
        'group_id': 'group_default',
        'nested': {'email_verified': true},
        'permissions': ['feedback'],
      });
      expect(adminVisibleAuditDetail('注册赠送 100 时光币'), isEmpty);
      expect(adminVisibleAuditDetail('邮箱已验证'), '邮箱已验证');
    },
  );
}
