import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('admin settings expose account and reminder email controls', () {
    final adminScreen = File(
      'lib/screens/admin_screen.dart',
    ).readAsStringSync();
    final backend = File('backend/main.py').readAsStringSync();
    final defaults = File('backend/settings_defaults.py').readAsStringSync();

    for (final key in [
      'email_service_enabled',
      'email_title',
      'email_sender_name',
      'email_code_primary_provider',
      'email_code_backup_provider',
      'email_code_active_slot',
      'email_auto_switch_enabled',
      'openclaw_mail_user',
      'openclaw_mail_api_key',
      'resend_base_url',
      'resend_api_key',
      'resend_from',
      'system_notice_email_to',
      'email_smtp_host',
      'email_smtp_port',
      'email_smtp_username',
      'email_smtp_password',
      'email_smtp_from',
      'reminder_email_enabled',
      'reminder_email_to',
      'reminder_email_from',
      'reminder_email_smtp_host',
      'reminder_email_smtp_port',
      'reminder_email_smtp_username',
      'reminder_email_smtp_password',
    ]) {
      expect(adminScreen, contains(key));
      expect(backend, contains(key));
    }
    expect(adminScreen, contains('账号验证码邮件'));
    expect(adminScreen, contains('账号邮件标题'));
    expect(adminScreen, contains('兼容 RE0 的 TITLE，默认使用多仪'));
    expect(adminScreen, contains('注册验证、邮箱登录和找回密码共用主备通道'));
    expect(adminScreen, contains('Claw163'));
    expect(adminScreen, contains('Resend'));
    expect(adminScreen, contains('备用成功后自动切换'));
    expect(adminScreen, contains('_mailProviderValue'));
    expect(adminScreen, contains('_mailProviderItems'));
    expect(adminScreen, contains('_openclawMailKeyMasked'));
    expect(adminScreen, contains('_resendApiKeyMasked'));
    expect(adminScreen, contains('_accountSmtpPasswordMasked'));
    expect(adminScreen, contains("payload['email_smtp_password']"));
    expect(
      adminScreen,
      contains("'email_smtp_from': _accountSmtpFromCtrl.text.trim()"),
    );
    expect(adminScreen, contains("payload['openclaw_mail_api_key']"));
    expect(adminScreen, contains("payload['resend_api_key']"));
    expect(
      adminScreen,
      contains("'email_code_primary_provider': _emailPrimaryProvider"),
    );
    expect(
      adminScreen,
      contains("'email_code_backup_provider': _emailBackupProvider"),
    );
    expect(adminScreen, contains("'email_code_active_slot': _emailActiveSlot"));
    expect(adminScreen, contains('reminder_email_smtp_password_set'));

    expect(adminScreen, contains('邮件提醒投递'));
    expect(adminScreen, contains('默认提醒收件人'));
    expect(adminScreen, contains('提醒 SMTP Host'));
    expect(adminScreen, contains('提醒 SMTP 密码'));
    expect(adminScreen, contains('测试提醒邮件'));
    expect(adminScreen, contains('_testReminderEmail'));
    expect(adminScreen, contains('testReminderEmail()'));
    expect(adminScreen, contains('测试账号邮件'));
    expect(adminScreen, contains('_testingAccountEmail'));
    expect(adminScreen, contains('_testAccountEmail'));
    expect(adminScreen, contains('testAccountEmail()'));
    expect(adminScreen, contains('_reminderSmtpPasswordMasked'));
    expect(adminScreen, contains("payload['reminder_email_smtp_password']"));
    expect(backend, contains('"reminder_email_smtp_password",'));
    expect(defaults, contains('account_primary_provider_default'));
    expect(defaults, contains('default="resend"'));
    expect(backend, contains('TITLE, EMAIL_ADDRESS'));
    expect(backend, contains('"title": "email_title"'));
    expect(backend, contains('"email_address": "email_smtp_username"'));
    expect(backend, contains('"smtp_host": "email_smtp_host"'));
    expect(backend, contains('smtp_fallback'));
    expect(backend, contains('f"{secret_key}_set"'));
    expect(backend, contains('@app.post("/api/admin/reminders/email/test")'));
    expect(backend, contains('def admin_reminder_email_test'));
    expect(backend, contains('@app.post("/api/admin/account-email/test")'));
    expect(backend, contains('def admin_account_email_test'));
    expect(backend, contains('_account_email_test_recipient'));
    expect(backend, contains('account_email.test'));
    final adminApi = File('lib/services/admin_api.dart').readAsStringSync();
    expect(adminApi, contains('testReminderEmail'));
    expect(adminApi, contains('/api/admin/reminders/email/test'));
    expect(adminApi, contains('testAccountEmail'));
    expect(adminApi, contains('/api/admin/account-email/test'));
  });
}
