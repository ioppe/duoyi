import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'account-scoped providers guard reset against stale storage reloads',
    () {
      for (final path in const [
        'lib/providers/user_provider.dart',
        'lib/providers/achievement_provider.dart',
        'lib/providers/theme_provider.dart',
        'lib/providers/preferences_provider.dart',
        'lib/providers/habit_provider.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(source, contains('int _storageGeneration = 0;'), reason: path);
        expect(
          source,
          contains('final generation = _storageGeneration;'),
          reason: path,
        );
        expect(
          source,
          contains('if (generation != _storageGeneration) return;'),
          reason: path,
        );
        final reset = _sourceBlock(
          source,
          'void resetLocalState() {',
          'notifyListeners();',
        );
        expect(reset, contains('_storageGeneration++;'), reason: path);
      }
    },
  );

  test('AuthProvider supports account profile and password reset APIs', () {
    final source = File('lib/providers/auth_provider.dart').readAsStringSync();

    for (final field in [
      'final String? email;',
      'final String? displayName;',
      'final String? avatar;',
      'final String? bio;',
      'final int coinBalance;',
      'final int lifetimeCoins;',
      'final List<String>? adminPermissions;',
      "'coin_balance': coinBalance",
      "'lifetime_coins': lifetimeCoins",
      "'admin_permissions': adminPermissions",
      "'display_name': displayName",
      "'avatar': avatar",
      "'bio': bio",
    ]) {
      expect(source, contains(field));
    }

    expect(source, contains("'/api/me/profile'"));
    expect(source, contains("'/api/me/email'"));
    expect(source, contains('Future<void> updateProfile'));
    final updateProfileBody = source.substring(
      source.indexOf('Future<void> updateProfile({'),
      source.indexOf('Future<void> bindEmail'),
    );
    expect(updateProfileBody, isNot(contains('String? username')));
    expect(updateProfileBody, isNot(contains("'username'")));
    expect(updateProfileBody, isNot(contains('String? avatar')));
    expect(updateProfileBody, isNot(contains("'avatar'")));
    expect(updateProfileBody, isNot(contains('String? email')));
    expect(updateProfileBody, isNot(contains("'email'")));
    expect(source, contains('Future<void> bindEmail'));
    expect(source, contains('Future<void> changePassword'));
    expect(source, contains("'/api/auth/change-password'"));
    expect(source, contains('Future<void> uploadAvatarBytes'));
    expect(source, contains("'/api/me/avatar'"));
    expect(source, contains("fieldName: 'avatar'"));
    expect(source, contains('_stringListFromJson'));
    expect(
      source,
      contains(
        'Future<void> Function(AuthState state)? onAccountProfileChanged',
      ),
    );
    expect(source, contains('Future<void> Function()? onAccountLoggedOut'));
    expect(source, contains('await _notifyAccountProfileChanged();'));
    expect(source, contains('await _notifyAccountLoggedOut();'));
    expect(source, contains("'/api/auth/password-reset/request'"));
    expect(
      source,
      contains('Future<Map<String, dynamic>> requestPasswordReset'),
    );
    expect(source, contains("'/api/auth/password-reset/confirm'"));
    expect(source, contains('Future<void> confirmPasswordReset'));
    expect(source, contains('bool get registrationEmailRequired'));
    expect(
      source,
      contains("_serverConfig['registration_email_required'] != false"),
    );
    final loginScreen = File(
      'lib/screens/login_screen.dart',
    ).readAsStringSync();
    expect(
      loginScreen,
      contains(
        'final registrationEmailRequired = auth.registrationEmailRequired',
      ),
    );
    expect(
      loginScreen,
      isNot(
        contains('bool get _registrationEmailVerificationRequired => true'),
      ),
    );
    expect(source, contains('_stateFromAuthResponse'));
    final apiClient = File('lib/services/api_client.dart').readAsStringSync();
    expect(apiClient, contains('Future<Map<String, dynamic>> put('));
    expect(apiClient, contains("case 'PUT':"));
    final backend = File('backend/main.py').readAsStringSync();
    expect(backend, contains('"identifier": row["username"]'));
    expect(backend, contains('"can_edit_username": False'));
  });

  test(
    'Profile screen supports RE0-style profile, avatar and email binding UX',
    () {
      final mine = File('lib/screens/mine_screen.dart').readAsStringSync();
      final source = File('lib/screens/profile_screen.dart').readAsStringSync();

      expect(mine, contains("import 'profile_screen.dart';"));
      expect(mine, contains('onTap: () => _openProfileEditor(context)'));
      expect(
        mine,
        isNot(contains('void _showProfileDetailsSheet(BuildContext context)')),
      );
      expect(mine, contains('void _openProfileEditor(BuildContext context'));
      expect(
        mine,
        contains('ProfileScreen(openAvatarSheetOnStart: avatarOnly)'),
      );
      expect(mine, contains('onTap: () => _showAvatarPreview(context)'));
      expect(mine, contains('void _showAvatarPreview(BuildContext context)'));
      expect(mine, contains('uploadAvatarBytes('));
      expect(mine, contains('_copyLocalAvatarFile(file)'));
      expect(mine, contains("message: I18n.tr('mine.avatar.edit')"));
      expect(mine, contains('onTap: () => _pickAndSaveAvatar(context)'));
      expect(mine, isNot(contains("label: '个人资料'")));
      expect(
        mine,
        isNot(contains('void _openAvatarEditor(BuildContext context)')),
      );
      expect(mine, isNot(contains('onTap: () => _openAvatarEditor(context)')));
      expect(mine, isNot(contains('class _ProfileEditDialog')));
      expect(mine, isNot(contains('class _LocalProfileEditDialog')));

      for (final field in [
        "package:file_selector/file_selector.dart",
        'class ProfileScreen',
        'class _AccountProfileEditor',
        'class _EmailBindingDialog',
        'class _ProfileMetricChip',
        'class _ProfileSectionHeader',
        "I18n.tr('profile.nickname')",
        "I18n.tr('auth.username')",
        "I18n.tr('profile.username.locked')",
        'readOnly: true',
        "I18n.tr('profile.email.binding')",
        'Future<void> _sendEmailCode()',
        'Future<void> _bindEmail()',
        'Future<void> _showEmailBindingDialog()',
        'controller: _emailCtrl',
        'controller: _emailCodeCtrl',
        'action: _sendButton(context)',
        "I18n.tr('profile.account_id')",
        'addListener(_refreshPreview)',
        'removeListener(_refreshPreview)',
        '_emailCtrl.addListener(_refreshPreview)',
        '_emailCtrl.removeListener(_refreshPreview)',
        'AuthProvider? _authProvider',
        '_authProvider?.removeListener(_handleAuthStateChanged)',
        'controller.addListener(_handleProfileFieldChanged)',
        'controller.removeListener(_handleProfileFieldChanged)',
        'void _handleAuthStateChanged()',
        'void _syncAccountStateIfClean(AuthState state)',
        'void _applyAccountState(AuthState state)',
        'bool _hasLocalProfileEdits = false',
        'if (_hasLocalProfileEdits || _busy || _avatarBusy)',
        'void _setControllerText(TextEditingController controller, String value)',
        'String _accountProfileSnapshot(AuthState state)',
        'openFile(',
        'XTypeGroup(',
        "extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif']",
        'uploadAvatarBytes(',
        'bytes.length > 3 * 1024 * 1024',
        "I18n.tr('profile.avatar.too_large')",
        "I18n.tr('profile.avatar.saved')",
        'sendBindEmailCode(',
        'bindEmail(email: email, code: code)',
        'final userProvider = context.read<UserProvider>()',
        'await userProvider.updateProfile(',
        'displayName: state.displayName ??',
        'email: state.email ??',
        'emailVerified: state.emailVerified',
        'avatarUrl: state.avatar ??',
        'bio: state.bio ??',
        'class _LocalProfileEditor',
        'height: _profileActionButtonHeight',
        "I18n.tr('profile.display_name')",
        "I18n.tr('profile.local_nickname')",
        "I18n.tr('profile.email.local_display')",
        "I18n.tr('profile.bio')",
        'Future<void> _pickLocalAvatar()',
        '_copyLocalAvatarFile(file)',
        'await _save(showSnackBar: false)',
        'class _ProfileAvatarFullScreen',
        'class _ProfileAvatarEditBadge',
        'class _ProfileAvatarWithEdit',
        'void _showAvatarPreview()',
        'onPreview: _showAvatarPreview',
        'onEdit: _uploadAvatar',
        'onEdit: _pickLocalAvatar',
        "message: '查看头像'",
        "message: '修改头像'",
        "title: const Text('头像')",
        'titleTextStyle: appSecondaryRouteTitleTextStyle(',
        ').copyWith(color: Colors.white)',
        "tag: 'profile-avatar-preview'",
        'class _ProfileAvatarFullImage',
        'InteractiveViewer',
        'fit: BoxFit.contain',
        'Icons.edit_outlined',
        'await context.read<UserProvider>().updateProfile(',
        'final avatarIsLocalFile = _localAvatarPath(avatar) != null',
        'final avatarIsImage = avatarIsUrl || avatarIsLocalFile',
        'final avatarInitials = avatarIsImage',
        "avatarUrl: avatarIsImage ? avatar : ''",
        'bool _isHttpAvatar(String value)',
        'String? _localAvatarPath(String value)',
        'Future<String> _copyLocalAvatarFile(XFile file)',
        "final dir = Directory('\${root.path}/profile_avatars')",
        "I18n.tr('profile.local.updated')",
        "I18n.tr('profile.account_security')",
      ]) {
        expect(source, contains(field));
      }

      expect(source, contains("I18n.tr('profile.change_password')"));
      expect(source, contains('class _ChangePasswordDialog'));
      expect(source, contains('changePassword('));
      expect(source, contains("I18n.tr('profile.password.updated')"));
      final fullImageStart = source.indexOf('class _ProfileAvatarFullImage');
      final fullImageEnd = source.indexOf(
        'class _ChangePasswordDialog',
        fullImageStart,
      );
      expect(fullImageStart, greaterThanOrEqualTo(0));
      expect(fullImageEnd, greaterThan(fullImageStart));
      final fullImage = source.substring(fullImageStart, fullImageEnd);
      expect(fullImage, isNot(contains('ClipOval')));
      expect(fullImage, isNot(contains('BoxFit.cover')));

      final accountBody = source.substring(
        source.indexOf('class _AccountProfileEditor'),
        source.indexOf('class _LocalProfileEditor'),
      );
      expect(
        accountBody,
        isNot(contains("I18n.tr('profile.avatar.url_or_text')")),
      );
      expect(
        accountBody,
        isNot(contains("I18n.tr('profile.avatar.url_file_or_text')")),
      );
      expect(
        accountBody,
        isNot(contains('username: username')),
        reason: '账号唯一标识不能通过资料保存路径编辑',
      );
      expect(
        accountBody,
        isNot(contains("I18n.tr('auth.error.username_length')")),
        reason: '只读账号标识不能阻断资料保存',
      );
      expect(
        accountBody,
        isNot(contains("I18n.tr('auth.error.username_no_space')")),
        reason: '只读账号标识不能阻断资料保存',
      );
      expect(accountBody, contains('onPreview: _showAvatarPreview'));
      expect(accountBody, isNot(contains('Icons.photo_camera_outlined')));
      expect(accountBody, isNot(contains("I18n.tr('profile.avatar.upload')")));
      expect(accountBody, isNot(contains('查看当前头像，选择图片后会直接保存')));
      expect(accountBody, isNot(contains('用户名和账号标识不会随头像保存而改变')));
      expect(accountBody, contains('_showEmailBindingDialog'));
      expect(accountBody, contains("Text(I18n.tr('profile.email.binding'))"));
      expect(accountBody, isNot(contains('controller: _emailCodeCtrl')));
      expect(accountBody, isNot(contains('action: _sendButton(context)')));
      expect(
        accountBody,
        isNot(contains("label: Text(I18n.tr('action.edit'))")),
      );
      expect(source, contains('AppSecondaryControlTheme('));
      expect(source, contains('class _ProfileActionField'));
      expect(source, contains('const double _profileActionButtonHeight = 36'));
      expect(source, contains('const double _profileActionButtonWidth = 68'));
      expect(
        source,
        contains('const double _profileLongActionButtonWidth = 96'),
      );
      expect(source, contains('double _profileInlineActionWidth'));
      expect(source, contains('height: _profileActionButtonHeight'));
      expect(accountBody, isNot(contains('ListTile(')));
      expect(
        accountBody,
        isNot(contains('prefixIcon: const Icon(Icons.mail_outline)')),
      );
    },
  );

  test('UserProvider persists editable local profile fields', () {
    final source = File('lib/providers/user_provider.dart').readAsStringSync();
    final recalcBody = source.substring(
      source.indexOf('void recalc({'),
      source.indexOf('void _notifyListenersSafely()'),
    );

    for (final field in [
      'Future<void> updateProfile({',
      'required String username',
      'String? avatarInitials',
      'String? displayName',
      'String? email',
      'bool? emailVerified',
      'String? avatarUrl',
      'String? bio',
      'String syncSignature()',
      'void recalc({',
      '// ignore: discarded_futures',
      'final unchanged =',
      'if (unchanged) return;',
      "_profile.username = cleanName",
      'final nextAvatarInitials = cleanInitials.isNotEmpty',
      '_profile.avatarInitials = nextAvatarInitials',
      '_profile.displayName = nextDisplayName',
      '_profile.email = nextEmail',
      '_profile.emailVerified = nextEmailVerified',
      '_profile.avatarUrl = nextAvatarUrl',
      '_profile.bio = nextBio',
      'await _save()',
      'Future<void> clearAccountProfileCache() async',
      "_profile.username = '用户'",
      "_profile.email = ''",
      '_profile.emailVerified = false',
      "_profile.avatarUrl = ''",
      "_profile.bio = ''",
      'Future<void> setUsername(String name) async',
      'await updateProfile(username: name)',
    ]) {
      expect(source, contains(field));
    }
    expect(recalcBody, isNot(contains('_profile.updatedAt = DateTime.now()')));
  });

  test('Mine screen uses synced local account profile as display fallback', () {
    final source = File('lib/screens/mine_screen.dart').readAsStringSync();

    for (final field in [
      'p.displayName',
      'p.avatarUrl',
      'final avatarValue = auth.isLoggedIn',
      'auth.avatar',
      'profile.avatarUrl',
      'profile.avatarInitials',
      'avatar: avatarValue',
      'final metadata = <Widget>[',
      'return SizedBox(',
      "key: const ValueKey('mine_header_stable_box')",
      'height: headerHeight',
      'child: Row(',
      'crossAxisAlignment: CrossAxisAlignment.center',
      "key: const ValueKey('mine_avatar_row')",
      'child: avatar',
      'SizedBox(width: compact ? 10 : 12)',
      "label: I18n.tr('mine.view_profile_semantics')",
      "key: const ValueKey('mine_user_info_row')",
      'Wrap(',
      'runSpacing: 4',
      'class _MineUserLineChip extends StatelessWidget',
      "label: '@\$usernameText'",
      'Image.file(',
      'String? _localAvatarPath(String value)',
    ]) {
      expect(source, contains(field));
    }
    expect(source, isNot(contains("I18n.tr('profile.coins')")));
    expect(
      File('lib/screens/profile_screen.dart').readAsStringSync(),
      isNot(contains("I18n.tr('profile.coins')")),
    );
  });

  test('Login screen supports password, email-code login and reset flow', () {
    final source = File('lib/screens/login_screen.dart').readAsStringSync();

    for (final field in [
      "I18n.tr('auth.account')",
      "I18n.tr('auth.verified_email')",
      'bool _registerWithEmail = true;',
      'final shouldBindRegistrationEmail =',
      'Switch.adaptive(',
      "I18n.tr('profile.email.binding')",
      'await auth.login(',
      'await auth.emailLogin(',
      "purpose: _isRegister ? 'bind' : 'login'",
      "I18n.tr('auth.email.optional')",
      "I18n.tr('auth.forgot_password')",
      'class _PasswordResetDialog',
      'requestPasswordReset(',
      'confirmPasswordReset(',
      "I18n.tr('auth.reset_account')",
      "I18n.tr('auth.reset_account.helper')",
      "I18n.tr('auth.email_code')",
      'account: account',
      'code: code',
      'bool _looksLikeEmail(String value)',
      'Timer? _emailCooldownTimer',
      'Timer? _cooldownTimer',
      "I18n.tr('auth.confirm_password')",
    ]) {
      expect(source, contains(field));
    }
    final frame = File('lib/widgets/auth_page_frame.dart').readAsStringSync();
    expect(source, contains('AuthMethodSelector('));
    expect(frame, contains("I18n.tr('auth.password_login')"));
    expect(frame, contains("I18n.tr('auth.email_code_login')"));
    expect(source, isNot(contains("labelText: '邮件 token'")));
    expect(source, isNot(contains("setState(() => _error = '请填写账号已绑定邮箱')")));
    expect(source, isNot(contains('重置邮件已发送，请查收邮件中的 token。')));
  });

  test('Profile and auth email-code UX is responsive and guarded', () {
    final profile = File('lib/screens/profile_screen.dart').readAsStringSync();
    final login = File('lib/screens/login_screen.dart').readAsStringSync();

    for (final field in [
      'Semantics(',
      'button: true',
      'class _ProfileAvatarFullScreen',
      'void _showAvatarPreview()',
      "tooltip: '修改头像'",
      'WidgetsBinding.instance.addPostFrameCallback',
      'onPreview: _showAvatarPreview',
      'onEdit: _uploadAvatar',
      'onEdit: _pickLocalAvatar',
      'onTap: busy ? null : onEdit',
      'if (mounted) _uploadAvatar();',
      'if (mounted) _pickLocalAvatar();',
      'class _ProfileAvatarEditBadge',
      'class _ProfileAvatarWithEdit',
      'const double _profileActionButtonHeight = 36',
      'const double _profileActionButtonWidth = 68',
      'const double _profileLongActionButtonWidth = 96',
      'height: _profileActionButtonHeight',
      "setState(() => _error = I18n.tr('auth.error.email_invalid'))",
      '_cooldownSeconds > 0',
      "'\${_cooldownSeconds}s'",
      'appSecondaryFilledButtonStyle(context)',
      'FittedBox(',
      'maxLines: 1',
      'if (_busy || _avatarBusy) return;',
      'if (_sending || _binding) return;',
      'onPressed: _busy || _avatarBusy ? null : _save',
    ]) {
      expect(profile, contains(field), reason: field);
    }

    expect(profile, isNot(contains('class _ProfileInlineActionField')));

    for (final field in [
      'class _LoginActionField',
      'final actionWidth = constraints.maxWidth < 360 ? 64.0 : 72.0',
      'height: DesignTokens.formFieldMinHeight',
      '_userCtrl.addListener(_refreshControls)',
      '_emailCtrl.addListener(_refreshControls)',
      'if (_busy || _sendingEmailCode) return;',
      'if (!_canSendEmailCode) return;',
      'bool get _canSendEmailCode',
      'final canSend = _canSendEmailCode',
      'onPressed: canSend ? _sendEmailCode : null',
      "'\${_emailCooldownSeconds}s 后'",
      'appSecondaryFilledButtonStyle(context)',
      'FittedBox(',
      'maxLines: 1',
      'Widget _emailCodeField({',
      '_emailCodeField(',
      'Widget _emailCodeSendField({',
      '_emailCodeSendField(',
      'return email.isNotEmpty && _looksLikeEmail(email);',
      '_sendingEmailCode ||',
      "I18n.tr('auth.error.username_required')",
    ]) {
      expect(login, contains(field), reason: field);
    }

    expect(login, isNot(contains('class _LoginInlineActionField')));
  });

  test('App startup refreshes account profile into local profile cache', () {
    final source = File('lib/main.dart').readAsStringSync();

    for (final field in [
      'authProvider.onAccountProfileChanged = (state) async',
      'await cloudSyncProvider.suppressDirtyMarkWhile(',
      '() => userProvider.applyAccountSnapshot(',
      'displayName: state.displayName ??',
      'email: state.email ??',
      'emailVerified: state.emailVerified',
      'avatarUrl: state.avatar ??',
      'bio: state.bio ??',
      'authProvider.onAccountLoggedOut = ()',
      "clearAccountLocalData(reason: 'logout')",
      'authProvider.loadFromStorage(refreshServerConfig: false)',
      "'server config refresh'",
      'authProvider.refreshServerConfigFromServer()',
      "'auth profile refresh'",
      'authProvider.refreshMe()',
      "await authProvider.refreshMe(reason: 'cloud_sync_account_snapshot');",
    ]) {
      expect(source, contains(field));
    }
  });

  test(
    'App refreshes account profile after cloud sync and foreground resume',
    () {
      final source = File('lib/main.dart').readAsStringSync();

      for (final field in [
        'void _refreshAccountProfileOnResume()',
        '_refreshAccountProfileOnResume();',
        'Provider.of<AuthProvider>(ctx, listen: false)',
        'if (!auth.state.isLoggedIn) return;',
        'await auth.refreshMe();',
        'refresh account profile failed',
        'cloudSyncProvider.onSynced = (changedCollections)',
        "changedCollections.contains('user_profile')",
        'reloadTasks.add(userProvider.loadFromStorage)',
        "await authProvider.refreshMe(reason: 'cloud_sync_account_snapshot');",
        "changedCollections.contains('virtual_rewards')",
      ]) {
        expect(source, contains(field));
      }
    },
  );
}

String _sourceBlock(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  expect(start, isNonNegative, reason: startMarker);
  final end = source.indexOf(endMarker, start + startMarker.length);
  expect(end, isNonNegative, reason: endMarker);
  return source.substring(start, end);
}
