import 'dart:async';
import 'dart:io' show Directory, File;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/design_tokens.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/user_provider.dart';
import '../services/api_client.dart';
import '../widgets/cached_avatar_image.dart';
import '../widgets/surface_components.dart';
import 'login_screen.dart';
import 'access_tokens_screen.dart';

const double _profileActionButtonHeight = 36;
const double _profileActionButtonWidth = 68;
const double _profileLongActionButtonWidth = 96;

double _profileInlineActionWidth(BuildContext context) {
  return MediaQuery.sizeOf(context).width < 360
      ? _profileActionButtonWidth
      : _profileLongActionButtonWidth;
}

class ProfileScreen extends StatelessWidget {
  final bool openAvatarSheetOnStart;

  const ProfileScreen({super.key, this.openAvatarSheetOnStart = false});

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = context.select<AuthProvider, bool>(
      (auth) => auth.state.isLoggedIn,
    );
    return isLoggedIn
        ? _AccountProfileEditor(openAvatarSheetOnStart: openAvatarSheetOnStart)
        : _LocalProfileEditor(openAvatarSheetOnStart: openAvatarSheetOnStart);
  }
}

class _ProfileAvatarPreview extends StatelessWidget {
  final String? avatar;
  final String displayName;
  final double radius;
  final Object? cacheKey;

  const _ProfileAvatarPreview({
    required this.avatar,
    required this.displayName,
    required this.radius,
    this.cacheKey,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final value = avatar?.trim() ?? '';
    final networkUrl = _networkAvatarUrl(value);
    final localPath = _localAvatarPath(value);
    final fallback = (networkUrl != null || localPath != null)
        ? displayName
        : (value.isNotEmpty ? value : displayName);
    final letter = fallback.isNotEmpty ? fallback.characters.first : '我';

    return CircleAvatar(
      radius: radius,
      backgroundColor: cs.primary,
      child: networkUrl != null
          ? ClipOval(
              child: CachedAvatarImage(
                url: networkUrl,
                cacheKey: cacheKey ?? _avatarCacheKey(networkUrl, null),
                width: radius * 2,
                height: radius * 2,
                fallbackBuilder: (_) => _ProfileAvatarLetter(
                  letter: letter,
                  radius: radius,
                  color: cs.onPrimary,
                ),
              ),
            )
          : localPath != null
          ? ClipOval(
              child: Image.file(
                File(localPath),
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _ProfileAvatarLetter(
                  letter: letter,
                  radius: radius,
                  color: cs.onPrimary,
                ),
              ),
            )
          : _ProfileAvatarLetter(
              letter: letter,
              radius: radius,
              color: cs.onPrimary,
            ),
    );
  }
}

class _ProfileAvatarLetter extends StatelessWidget {
  final String letter;
  final double radius;
  final Color color;

  const _ProfileAvatarLetter({
    required this.letter,
    required this.radius,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      letter,
      style: TextStyle(
        fontSize: radius * 0.62,
        color: color,
        fontWeight: DesignTokens.fontWeightStrong,
      ),
    );
  }
}

class _ProfileActionField extends StatelessWidget {
  final Widget field;
  final Widget action;

  const _ProfileActionField({required this.field, required this.action});

  @override
  Widget build(BuildContext context) {
    final stacked = MediaQuery.sizeOf(context).width < 360;
    final actionBox = SizedBox(
      width: stacked ? double.infinity : _profileInlineActionWidth(context),
      height: DesignTokens.formFieldMinHeight,
      child: action,
    );
    if (stacked) {
      return Column(
        key: const ValueKey('profile_action_field_stacked'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [field, const SizedBox(height: 8), actionBox],
      );
    }
    return Row(
      key: const ValueKey('profile_action_field_inline'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: field),
        const SizedBox(width: 8),
        actionBox,
      ],
    );
  }
}

class _ProfileAvatarEditBadge extends StatelessWidget {
  final bool busy;

  const _ProfileAvatarEditBadge({required this.busy});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: cs.primary,
        shape: BoxShape.circle,
        border: Border.all(
          color: cs.surface.withValues(alpha: 0.90),
          width: 0.45,
        ),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.08),
            blurRadius: 5,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: busy
          ? const Padding(
              padding: EdgeInsets.all(6),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(Icons.edit_outlined, color: cs.onPrimary, size: 14),
    );
  }
}

class _ProfileAvatarWithEdit extends StatelessWidget {
  final Widget child;
  final double size;
  final bool busy;
  final VoidCallback? onPreview;
  final VoidCallback? onEdit;

  const _ProfileAvatarWithEdit({
    required this.child,
    required this.size,
    required this.busy,
    required this.onPreview,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Tooltip(
              message: '查看头像',
              child: Semantics(
                button: true,
                label: '查看头像',
                child: InkWell(
                  key: const ValueKey('profile_avatar_preview_button'),
                  customBorder: const CircleBorder(),
                  onTap: busy ? null : onPreview,
                  child: Center(child: child),
                ),
              ),
            ),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Tooltip(
              message: '修改头像',
              child: Semantics(
                button: true,
                label: '修改头像',
                child: SizedBox.square(
                  key: const ValueKey('profile_avatar_edit_button'),
                  dimension: 44,
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: busy ? null : onEdit,
                      child: Center(child: _ProfileAvatarEditBadge(busy: busy)),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (busy)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.surface.withValues(alpha: 0.54),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileAvatarFullScreen extends StatelessWidget {
  final String? avatar;
  final String displayName;
  final Object? cacheKey;
  final VoidCallback? onEdit;

  const _ProfileAvatarFullScreen({
    required this.avatar,
    required this.displayName,
    this.cacheKey,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: appSecondaryRouteTitleTextStyle(
          context,
        ).copyWith(color: Colors.white),
        title: const Text('头像'),
        actions: [
          if (onEdit != null)
            IconButton(
              tooltip: '修改头像',
              onPressed: () {
                Navigator.of(context).pop();
                WidgetsBinding.instance.addPostFrameCallback((_) => onEdit!());
              },
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: Center(
        child: Hero(
          tag: 'profile-avatar-preview',
          child: _ProfileAvatarFullImage(
            avatar: avatar,
            displayName: displayName,
            cacheKey: cacheKey,
          ),
        ),
      ),
    );
  }
}

class _ProfileAvatarFullImage extends StatelessWidget {
  final String? avatar;
  final String displayName;
  final Object? cacheKey;

  const _ProfileAvatarFullImage({
    required this.avatar,
    required this.displayName,
    this.cacheKey,
  });

  @override
  Widget build(BuildContext context) {
    final value = avatar?.trim() ?? '';
    final networkUrl = _networkAvatarUrl(value);
    final localPath = _localAvatarPath(value);
    final image = networkUrl != null
        ? CachedAvatarImage(
            url: networkUrl,
            cacheKey: cacheKey ?? _avatarCacheKey(networkUrl, null),
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.contain,
            fallbackBuilder: _fallbackAvatar,
          )
        : localPath != null
        ? Image.file(
            File(localPath),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _fallbackAvatar(context),
          )
        : null;

    return SizedBox.expand(
      child: InteractiveViewer(
        minScale: 0.8,
        maxScale: 4,
        child: Center(child: image ?? _fallbackAvatar(context)),
      ),
    );
  }

  Widget _fallbackAvatar(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final radius = (size.shortestSide * 0.28).clamp(84.0, 150.0);
    final value = avatar?.trim() ?? '';
    final networkUrl = _networkAvatarUrl(value);
    final localPath = _localAvatarPath(value);
    final fallback = (networkUrl != null || localPath != null)
        ? displayName
        : (value.isNotEmpty ? value : displayName);
    final letter = fallback.isNotEmpty ? fallback.characters.first : '我';
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: _ProfileAvatarLetter(
        letter: letter,
        radius: radius,
        color: Theme.of(context).colorScheme.onPrimary,
      ),
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _currentCtrl.text;
    final next = _newCtrl.text;
    final confirm = _confirmCtrl.text;
    if (current.isEmpty) {
      setState(() => _error = I18n.tr('profile.current_password'));
      return;
    }
    if (next.length < 6) {
      setState(() => _error = I18n.tr('auth.error.new_password_short'));
      return;
    }
    if (next != confirm) {
      setState(() => _error = I18n.tr('auth.error.new_password_mismatch'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<AuthProvider>().changePassword(
        currentPassword: current,
        newPassword: next,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = userVisibleApiError(e));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: Text(I18n.tr('profile.change_password')),
      icon: const Icon(Icons.lock_reset_outlined),
      content: AppFormFieldTheme(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _currentCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: I18n.tr('profile.current_password'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _newCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: I18n.tr('auth.new_password'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _confirmCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: I18n.tr('profile.confirm_new_password'),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              AppInfoBanner(
                icon: Icons.error_outline,
                title: I18n.tr('profile.save_failed'),
                message: _error!,
                color: Theme.of(context).colorScheme.error,
                margin: EdgeInsets.zero,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(I18n.tr('action.cancel')),
        ),
        SizedBox(
          width: _profileActionButtonWidth,
          height: _profileActionButtonHeight,
          child: FilledButton(
            onPressed: _saving ? null : _submit,
            style: appSecondaryFilledButtonStyle(context),
            child: _saving
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(I18n.tr('action.save'), maxLines: 1),
                  ),
          ),
        ),
      ],
    );
  }
}

class _EmailBindingDialog extends StatefulWidget {
  final String initialEmail;

  const _EmailBindingDialog({required this.initialEmail});

  @override
  State<_EmailBindingDialog> createState() => _EmailBindingDialogState();
}

class _EmailBindingDialogState extends State<_EmailBindingDialog> {
  late final TextEditingController _emailCtrl;
  late final TextEditingController _emailCodeCtrl;
  bool _sending = false;
  bool _binding = false;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;
  String? _message;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.initialEmail);
    _emailCodeCtrl = TextEditingController();
    _emailCtrl.addListener(_refresh);
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailCtrl.removeListener(_refresh);
    _emailCtrl.dispose();
    _emailCodeCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldownSeconds = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldownSeconds <= 1) {
        timer.cancel();
        setState(() => _cooldownSeconds = 0);
      } else {
        setState(() => _cooldownSeconds -= 1);
      }
    });
  }

  Future<void> _sendEmailCode() async {
    if (_sending || _binding || _cooldownSeconds > 0) return;
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = I18n.tr('auth.error.email_required'));
      return;
    }
    if (!_looksLikeEmail(email)) {
      setState(() => _error = I18n.tr('auth.error.email_invalid'));
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
      _message = null;
    });
    try {
      final result = await context.read<AuthProvider>().sendBindEmailCode(
        email: email,
      );
      final devCode = (result['dev_code'] ?? '').toString();
      final message = (result['message'] ?? I18n.tr('auth.email_code.sent'))
          .toString();
      if (!mounted) return;
      _startCooldown();
      setState(() {
        _message = devCode.isEmpty
            ? message
            : '$message ${I18n.tr('auth.email_code.code_prefix')}$devCode';
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = userVisibleApiError(e));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _bindEmail() async {
    if (_sending || _binding) return;
    final email = _emailCtrl.text.trim();
    final code = _emailCodeCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = I18n.tr('auth.error.email_required'));
      return;
    }
    if (!_looksLikeEmail(email)) {
      setState(() => _error = I18n.tr('auth.error.email_invalid'));
      return;
    }
    if (code.isEmpty) {
      setState(() => _error = I18n.tr('auth.error.email_code_required'));
      return;
    }
    setState(() {
      _binding = true;
      _error = null;
      _message = null;
    });
    try {
      await context.read<AuthProvider>().bindEmail(email: email, code: code);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = userVisibleApiError(e));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _binding = false);
    }
  }

  Widget _sendButton(BuildContext context) {
    final email = _emailCtrl.text.trim();
    final canSend = email.isNotEmpty && _looksLikeEmail(email);
    return SizedBox(
      height: _profileActionButtonHeight,
      child: FilledButton(
        onPressed: (_sending || _binding || _cooldownSeconds > 0 || !canSend)
            ? null
            : _sendEmailCode,
        style: appSecondaryFilledButtonStyle(context),
        child: _sending
            ? const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _cooldownSeconds > 0
                      ? '${_cooldownSeconds}s'
                      : I18n.tr('auth.send'),
                  maxLines: 1,
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: Text(I18n.tr('profile.email.binding')),
      icon: const Icon(Icons.alternate_email_outlined),
      content: AppFormFieldTheme(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: I18n.tr('auth.email'),
                prefixIcon: const Icon(Icons.mail_outline),
              ),
            ),
            const SizedBox(height: 12),
            _ProfileActionField(
              field: TextField(
                controller: _emailCodeCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: I18n.tr('auth.email_code'),
                  helperText: I18n.tr('profile.email_code.helper'),
                ),
              ),
              action: _sendButton(context),
            ),
            if (_message != null) ...[
              const SizedBox(height: 10),
              AppInfoBanner(
                icon: Icons.check_circle_outline,
                title: I18n.tr('profile.saved'),
                message: _message!,
                color: Colors.green,
                margin: EdgeInsets.zero,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              AppInfoBanner(
                icon: Icons.error_outline,
                title: I18n.tr('profile.save_failed'),
                message: _error!,
                color: Theme.of(context).colorScheme.error,
                margin: EdgeInsets.zero,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: (_sending || _binding)
              ? null
              : () => Navigator.pop(context, false),
          child: Text(I18n.tr('action.cancel')),
        ),
        SizedBox(
          width: _profileLongActionButtonWidth,
          height: _profileActionButtonHeight,
          child: FilledButton(
            onPressed: (_sending || _binding) ? null : _bindEmail,
            style: appSecondaryFilledButtonStyle(context),
            child: _binding
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(I18n.tr('profile.email.binding')),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ProfileMetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ProfileMetricChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: '$label $value',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.52),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: cs.onPrimaryContainer),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                '$label $value',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: cs.onPrimaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _ProfileSectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.62),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AccountProfileEditor extends StatefulWidget {
  final bool openAvatarSheetOnStart;

  const _AccountProfileEditor({this.openAvatarSheetOnStart = false});

  @override
  State<_AccountProfileEditor> createState() => _AccountProfileEditorState();
}

class _AccountProfileEditorState extends State<_AccountProfileEditor> {
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _displayNameCtrl;
  late final TextEditingController _avatarCtrl;
  late final TextEditingController _bioCtrl;
  AuthProvider? _authProvider;
  String? _lastAccountSnapshot;
  bool _syncingControllers = false;
  bool _hasLocalProfileEdits = false;
  bool _busy = false;
  bool _avatarBusy = false;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    final state = context.read<AuthProvider>().state;
    _usernameCtrl = TextEditingController(text: state.username ?? '');
    _displayNameCtrl = TextEditingController(text: state.displayName ?? '');
    _avatarCtrl = TextEditingController(text: state.avatar ?? '');
    _bioCtrl = TextEditingController(text: state.bio ?? '');
    _lastAccountSnapshot = _accountProfileSnapshot(state);
    for (final controller in [
      _usernameCtrl,
      _displayNameCtrl,
      _avatarCtrl,
      _bioCtrl,
    ]) {
      controller.addListener(_handleProfileFieldChanged);
    }
    if (widget.openAvatarSheetOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _uploadAvatar();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextAuth = context.read<AuthProvider>();
    if (_authProvider == nextAuth) return;
    _authProvider?.removeListener(_handleAuthStateChanged);
    _authProvider = nextAuth..addListener(_handleAuthStateChanged);
    _syncAccountStateIfClean(nextAuth.state);
  }

  @override
  void dispose() {
    _authProvider?.removeListener(_handleAuthStateChanged);
    for (final controller in [
      _usernameCtrl,
      _displayNameCtrl,
      _avatarCtrl,
      _bioCtrl,
    ]) {
      controller.removeListener(_handleProfileFieldChanged);
    }
    _usernameCtrl.dispose();
    _displayNameCtrl.dispose();
    _avatarCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  void _refreshPreview() {
    if (mounted) setState(() {});
  }

  void _handleProfileFieldChanged() {
    if (_syncingControllers) return;
    _hasLocalProfileEdits = true;
    _refreshPreview();
  }

  void _handleAuthStateChanged() {
    final state = _authProvider?.state;
    if (state == null || !mounted) return;
    _syncAccountStateIfClean(state);
  }

  void _syncAccountStateIfClean(AuthState state) {
    final nextSnapshot = _accountProfileSnapshot(state);
    if (nextSnapshot == _lastAccountSnapshot) return;
    if (_hasLocalProfileEdits || _busy || _avatarBusy) {
      return;
    }
    _applyAccountState(state);
  }

  void _applyAccountState(AuthState state) {
    _syncingControllers = true;
    try {
      _setControllerText(_usernameCtrl, state.username ?? '');
      _setControllerText(_displayNameCtrl, state.displayName ?? '');
      _setControllerText(_avatarCtrl, state.avatar ?? '');
      _setControllerText(_bioCtrl, state.bio ?? '');
    } finally {
      _syncingControllers = false;
    }
    _lastAccountSnapshot = _accountProfileSnapshot(state);
    _hasLocalProfileEdits = false;
    _refreshPreview();
  }

  void _applyUploadedAvatar(AuthState state) {
    _syncingControllers = true;
    try {
      _setControllerText(_avatarCtrl, state.avatar ?? '');
    } finally {
      _syncingControllers = false;
    }
    _lastAccountSnapshot = _accountProfileSnapshot(state);
    _refreshPreview();
  }

  void _setControllerText(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  Future<void> _uploadAvatar() async {
    if (_busy || _avatarBusy) return;
    final auth = context.read<AuthProvider>();
    final userProvider = context.read<UserProvider>();
    setState(() {
      _avatarBusy = true;
      _error = null;
      _message = null;
    });
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Image',
            extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
            mimeTypes: ['image/jpeg', 'image/png', 'image/webp', 'image/gif'],
          ),
        ],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        if (mounted) {
          setState(() => _error = I18n.tr('profile.avatar.empty'));
        }
        return;
      }
      if (bytes.length > 3 * 1024 * 1024) {
        if (mounted) {
          setState(() => _error = I18n.tr('profile.avatar.too_large'));
        }
        return;
      }
      await auth.uploadAvatarBytes(filename: file.name, bytes: bytes);
      final state = auth.state;
      _applyUploadedAvatar(state);
      await userProvider.updateProfile(
        username: _firstNonEmptyProfileText([
          state.username,
          _usernameCtrl.text,
          userProvider.profile.username,
        ]),
        displayName: state.displayName ?? '',
        email: state.email ?? '',
        emailVerified: state.emailVerified,
        avatarUrl: state.avatar ?? '',
        bio: state.bio ?? '',
      );
      if (!mounted) return;
      setState(() => _message = I18n.tr('profile.avatar.saved'));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = userVisibleApiError(e));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  void _showAvatarPreview() {
    if (_busy || _avatarBusy) return;
    final displayName = _firstNonEmptyProfileText([
      _displayNameCtrl.text,
      _usernameCtrl.text,
      context.read<AuthProvider>().state.displayName,
      context.read<AuthProvider>().state.username,
      I18n.tr('profile.default_user'),
    ]);
    final avatar = _avatarCtrl.text.trim().isEmpty
        ? context.read<AuthProvider>().state.avatar
        : _avatarCtrl.text.trim();
    final auth = context.read<AuthProvider>().state;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ProfileAvatarFullScreen(
          avatar: avatar,
          displayName: displayName,
          cacheKey: _avatarCacheKey(avatar, auth.userId),
          onEdit: _uploadAvatar,
        ),
      ),
    );
  }

  Future<void> _showChangePasswordDialog() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (!mounted || changed != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(I18n.tr('profile.password.updated'))),
    );
  }

  Future<void> _showEmailBindingDialog() async {
    if (_busy || _avatarBusy) return;
    final auth = context.read<AuthProvider>();
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _EmailBindingDialog(initialEmail: auth.state.email ?? ''),
    );
    if (!mounted || updated != true) return;
    final userProvider = context.read<UserProvider>();
    final state = auth.state;
    if (_hasLocalProfileEdits) {
      _lastAccountSnapshot = _accountProfileSnapshot(state);
      _refreshPreview();
    } else {
      _applyAccountState(state);
    }
    await userProvider.updateProfile(
      username: _firstNonEmptyProfileText([
        state.username,
        userProvider.profile.username,
      ]),
      displayName: state.displayName ?? '',
      email: state.email ?? '',
      emailVerified: state.emailVerified,
      avatarUrl: state.avatar ?? '',
      bio: state.bio ?? '',
    );
    if (!mounted) return;
    setState(() {
      _error = null;
      _message = I18n.tr('profile.updated');
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(I18n.tr('profile.updated'))));
  }

  Future<void> _save() async {
    if (_busy || _avatarBusy) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final auth = context.read<AuthProvider>();
      final userProvider = context.read<UserProvider>();
      await auth.updateProfile(
        displayName: _displayNameCtrl.text.trim(),
        bio: _bioCtrl.text.trim(),
      );
      final state = auth.state;
      _applyAccountState(state);
      await userProvider.updateProfile(
        username: _firstNonEmptyProfileText([
          state.username,
          _usernameCtrl.text,
          userProvider.profile.username,
        ]),
        displayName: state.displayName ?? '',
        email: state.email ?? '',
        emailVerified: state.emailVerified,
        avatarUrl: state.avatar ?? '',
        bio: state.bio ?? '',
      );
      if (!mounted) return;
      setState(() => _message = I18n.tr('profile.updated'));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(I18n.tr('profile.updated'))));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = userVisibleApiError(e));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _saveButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        width: _profileActionButtonWidth,
        height: _profileActionButtonHeight,
        child: FilledButton(
          onPressed: (_busy || _avatarBusy) ? null : _save,
          style: appSecondaryFilledButtonStyle(context),
          child: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(I18n.tr('action.save'), maxLines: 1),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final account = context
        .select<
          AuthProvider,
          ({
            String? userId,
            String? username,
            String? email,
            bool emailVerified,
            String? displayName,
            String? avatar,
          })
        >((auth) {
          final state = auth.state;
          return (
            userId: state.userId,
            username: state.username,
            email: state.email,
            emailVerified: state.emailVerified,
            displayName: state.displayName,
            avatar: state.avatar,
          );
        });
    final avatarFrame = context.select<ThemeProvider, AvatarFrameReward>(
      (provider) => provider.activeAvatarFrame,
    );
    final displayName = _firstNonEmptyProfileText([
      _displayNameCtrl.text,
      _usernameCtrl.text,
      account.displayName,
      account.username,
    ]);
    final previewAvatar = _avatarCtrl.text.trim().isEmpty
        ? account.avatar
        : _avatarCtrl.text.trim();
    final avatarCacheKey = _avatarCacheKey(previewAvatar, account.userId);
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Colors.transparent;

    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: Text(I18n.tr('profile.title')),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        actions: [_saveButton(context)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          AppSurfaceCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _ProfileAvatarWithEdit(
                  size: 76,
                  busy: _avatarBusy,
                  onPreview: _showAvatarPreview,
                  onEdit: _uploadAvatar,
                  child: Container(
                    width: 76,
                    height: 76,
                    padding:
                        avatarFrame.id == ThemeProvider.defaultAvatarFrameId
                        ? EdgeInsets.zero
                        : const EdgeInsets.all(3),
                    decoration:
                        avatarFrame.id == ThemeProvider.defaultAvatarFrameId
                        ? null
                        : BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: avatarFrame.colors,
                            ),
                          ),
                    child: Hero(
                      tag: 'profile-avatar-preview',
                      child: _ProfileAvatarPreview(
                        avatar: previewAvatar,
                        displayName: displayName.isEmpty ? '我' : displayName,
                        radius: 36,
                        cacheKey: avatarCacheKey,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName.isEmpty
                            ? I18n.tr('profile.display_name.empty')
                            : displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: appSecondaryRouteTitleTextStyle(context),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        account.email?.isNotEmpty == true
                            ? '${account.email}${account.emailVerified ? ' · ${I18n.tr('profile.email.verified')}' : ' · ${I18n.tr('profile.email.unverified')}'}'
                            : I18n.tr('profile.email.unbound'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.62),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if (account.username?.trim().isNotEmpty == true)
                            _ProfileMetricChip(
                              icon: Icons.badge_outlined,
                              label: I18n.tr('profile.account_id'),
                              value: account.username!.trim(),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppFormFieldTheme(
            child: AppSurfaceCard(
              padding: const EdgeInsets.all(DesignTokens.spaceXl),
              child: Column(
                children: [
                  TextField(
                    controller: _displayNameCtrl,
                    decoration: InputDecoration(
                      labelText: I18n.tr('profile.nickname'),
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spaceXl),
                  TextField(
                    controller: _usernameCtrl,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: I18n.tr('auth.username'),
                      helperText: I18n.tr('profile.username.locked'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          AppSecondaryControlTheme(
            child: AppSurfaceCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ProfileSectionHeader(
                    icon: Icons.alternate_email_outlined,
                    title: I18n.tr('profile.email.binding'),
                    subtitle: account.emailVerified
                        ? I18n.tr('profile.email.verified')
                        : I18n.tr('profile.email.unverified_or_pending'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    account.email?.trim().isEmpty != false
                        ? I18n.tr('profile.email.unbound')
                        : account.email!.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: cs.onSurface),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      height: _profileActionButtonHeight,
                      child: TextButton.icon(
                        onPressed: (_busy || _avatarBusy)
                            ? null
                            : _showEmailBindingDialog,
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          textStyle: appSecondaryControlTextStyle(context),
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: Text(I18n.tr('profile.email.binding')),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          AppSurfaceCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProfileSectionHeader(
                  icon: Icons.security_outlined,
                  title: I18n.tr('profile.account_security'),
                  subtitle: I18n.tr('profile.account_security.subtitle'),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    height: _profileActionButtonHeight,
                    child: TextButton.icon(
                      onPressed: (_busy || _avatarBusy)
                          ? null
                          : _showChangePasswordDialog,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        textStyle: appSecondaryControlTextStyle(context),
                      ),
                      icon: const Icon(Icons.lock_reset_outlined, size: 16),
                      label: Text(I18n.tr('profile.change_password')),
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: (_busy || _avatarBusy)
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AccessTokensScreen(),
                          ),
                        ),
                  icon: const Icon(Icons.key_outlined),
                  label: Text(I18n.tr('tokens.title')),
                ),
                const SizedBox(height: 8),
                AppFormFieldTheme(
                  child: TextField(
                    controller: _bioCtrl,
                    minLines: 3,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: I18n.tr('profile.bio'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            AppInfoBanner(
              icon: Icons.check_circle_outline,
              title: I18n.tr('profile.saved'),
              message: _message!,
              color: Colors.green,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            AppInfoBanner(
              icon: Icons.error_outline,
              title: I18n.tr('profile.save_failed'),
              message: _error!,
              color: Colors.red,
            ),
          ],
        ],
      ),
    );
  }
}

class _LocalProfileEditor extends StatefulWidget {
  final bool openAvatarSheetOnStart;

  const _LocalProfileEditor({this.openAvatarSheetOnStart = false});

  @override
  State<_LocalProfileEditor> createState() => _LocalProfileEditorState();
}

class _LocalProfileEditorState extends State<_LocalProfileEditor> {
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _displayNameCtrl;
  late final TextEditingController _avatarCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _bioCtrl;
  bool _busy = false;
  bool _avatarBusy = false;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    final profile = context.read<UserProvider>().profile;
    _usernameCtrl = TextEditingController(text: profile.username);
    _displayNameCtrl = TextEditingController(text: profile.displayName);
    _avatarCtrl = TextEditingController(text: profile.avatarUrl);
    _emailCtrl = TextEditingController(text: profile.email);
    _bioCtrl = TextEditingController(text: profile.bio);
    _usernameCtrl.addListener(_refreshPreview);
    _displayNameCtrl.addListener(_refreshPreview);
    _avatarCtrl.addListener(_refreshPreview);
    _emailCtrl.addListener(_refreshPreview);
    _bioCtrl.addListener(_refreshPreview);
    if (widget.openAvatarSheetOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pickLocalAvatar();
      });
    }
  }

  @override
  void dispose() {
    _usernameCtrl.removeListener(_refreshPreview);
    _displayNameCtrl.removeListener(_refreshPreview);
    _avatarCtrl.removeListener(_refreshPreview);
    _emailCtrl.removeListener(_refreshPreview);
    _bioCtrl.removeListener(_refreshPreview);
    _usernameCtrl.dispose();
    _displayNameCtrl.dispose();
    _avatarCtrl.dispose();
    _emailCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  void _refreshPreview() {
    if (mounted) setState(() {});
  }

  Future<void> _pickLocalAvatar() async {
    if (_busy || _avatarBusy) return;
    setState(() {
      _avatarBusy = true;
      _error = null;
      _message = null;
    });
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Image',
            extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
            mimeTypes: ['image/jpeg', 'image/png', 'image/webp', 'image/gif'],
          ),
        ],
      );
      if (file == null) return;
      final storedPath = await _copyLocalAvatarFile(file);
      if (!mounted) return;
      setState(() {
        _avatarCtrl.text = storedPath;
        _avatarBusy = false;
      });
      await _save(showSnackBar: false);
      if (!mounted) return;
      setState(() => _message = I18n.tr('profile.avatar.saved'));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  void _showAvatarPreview() {
    if (_busy || _avatarBusy) return;
    final displayName = _firstNonEmptyProfileText([
      _displayNameCtrl.text,
      _usernameCtrl.text,
      I18n.tr('profile.default_user'),
    ]);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ProfileAvatarFullScreen(
          avatar: _avatarCtrl.text.trim(),
          displayName: displayName,
          cacheKey: _avatarCacheKey(_avatarCtrl.text.trim(), null),
          onEdit: _pickLocalAvatar,
        ),
      ),
    );
  }

  Future<void> _save({bool showSnackBar = true}) async {
    if (_busy || _avatarBusy) return;
    final currentProfile = context.read<UserProvider>().profile;
    final username = currentProfile.username.trim().isNotEmpty
        ? currentProfile.username.trim()
        : _usernameCtrl.text.trim();
    if (username.isEmpty) {
      setState(() => _error = I18n.tr('profile.error.nickname_required'));
      return;
    }
    final displayName = _displayNameCtrl.text.trim();
    final avatar = _avatarCtrl.text.trim();
    final avatarIsUrl = _isHttpAvatar(avatar);
    final avatarIsLocalFile = _localAvatarPath(avatar) != null;
    final avatarIsImage = avatarIsUrl || avatarIsLocalFile;
    final avatarInitials = avatarIsImage
        ? _firstNonEmptyProfileText([displayName, username])
        : avatar;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await context.read<UserProvider>().updateProfile(
        username: username,
        avatarInitials: avatarInitials,
        displayName: displayName,
        email: _emailCtrl.text.trim(),
        avatarUrl: avatarIsImage ? avatar : '',
        bio: _bioCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() => _message = I18n.tr('profile.local.updated'));
      if (showSnackBar) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(I18n.tr('profile.local.updated'))),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _saveButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        width: _profileActionButtonWidth,
        height: _profileActionButtonHeight,
        child: FilledButton(
          onPressed: _busy || _avatarBusy ? null : _save,
          style: appSecondaryFilledButtonStyle(context),
          child: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(I18n.tr('action.save'), maxLines: 1),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _firstNonEmptyProfileText([
      _displayNameCtrl.text,
      _usernameCtrl.text,
      I18n.tr('profile.default_user'),
    ]);
    final previewAvatar = _avatarCtrl.text.trim();
    final avatarCacheKey = _avatarCacheKey(previewAvatar, null);
    final subtitle = _firstNonEmptyProfileText([
      _bioCtrl.text,
      _emailCtrl.text,
      I18n.tr('profile.local'),
    ]);
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Colors.transparent;

    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: Text(I18n.tr('profile.title')),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        actions: [_saveButton(context)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          AppSurfaceCard(
            padding: const EdgeInsets.all(14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 330;
                final avatarSize = compact ? 68.0 : 76.0;
                final avatar = _ProfileAvatarWithEdit(
                  size: avatarSize,
                  busy: _avatarBusy,
                  onPreview: _showAvatarPreview,
                  onEdit: _pickLocalAvatar,
                  child: Hero(
                    tag: 'profile-avatar-preview',
                    child: _ProfileAvatarPreview(
                      avatar: previewAvatar,
                      displayName: displayName,
                      radius: avatarSize / 2 - 2,
                      cacheKey: avatarCacheKey,
                    ),
                  ),
                );
                final loginButton = SizedBox(
                  width: compact ? 82 : _profileInlineActionWidth(context),
                  height: _profileActionButtonHeight,
                  child: TextButton(
                    key: const ValueKey('profile_local_login_button'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      textStyle: appSecondaryControlTextStyle(context),
                    ),
                    onPressed: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        I18n.tr('profile.login_account'),
                        maxLines: 1,
                      ),
                    ),
                  ),
                );
                final textColumn = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (compact) ...[
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: appSecondaryRouteTitleTextStyle(context),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: loginButton,
                      ),
                    ] else
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: appSecondaryRouteTitleTextStyle(context),
                            ),
                          ),
                          const SizedBox(width: 8),
                          loginButton,
                        ],
                      ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.62),
                        height: 1.25,
                      ),
                    ),
                  ],
                );
                return Row(
                  key: const ValueKey('profile_local_header_row'),
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    avatar,
                    SizedBox(width: compact ? 10 : 14),
                    Expanded(child: textColumn),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          AppFormFieldTheme(
            child: AppSurfaceCard(
              padding: const EdgeInsets.all(DesignTokens.spaceXl),
              child: Column(
                children: [
                  TextField(
                    controller: _displayNameCtrl,
                    decoration: InputDecoration(
                      labelText: I18n.tr('profile.display_name'),
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spaceXl),
                  TextField(
                    controller: _usernameCtrl,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: I18n.tr('profile.local_nickname'),
                      helperText: I18n.tr('profile.username.locked'),
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spaceXl),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: I18n.tr('profile.email.local_display'),
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spaceXl),
                  TextField(
                    controller: _bioCtrl,
                    minLines: 3,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: I18n.tr('profile.bio'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            AppInfoBanner(
              icon: Icons.error_outline,
              title: I18n.tr('profile.save_failed'),
              message: _error!,
              color: Colors.red,
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 12),
            AppInfoBanner(
              icon: Icons.check_circle_outline,
              title: I18n.tr('profile.saved'),
              message: _message!,
              color: Colors.green,
            ),
          ],
        ],
      ),
    );
  }
}

String _firstNonEmptyProfileText(List<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  }
  return '';
}

String _accountProfileSnapshot(AuthState state) {
  return [
    state.username ?? '',
    state.email ?? '',
    state.emailVerified.toString(),
    state.displayName ?? '',
    state.avatar ?? '',
    state.bio ?? '',
  ].join('\n');
}

bool _isHttpAvatar(String value) {
  return _networkAvatarUrl(value) != null;
}

bool _looksLikeEmail(String value) {
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());
}

String? _localAvatarPath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  if (_networkAvatarUrl(trimmed) != null) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.scheme == 'file') {
    return uri.toFilePath();
  }
  if (trimmed.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(trimmed)) {
    return trimmed;
  }
  return null;
}

String? _networkAvatarUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    return trimmed;
  }
  final pathSegments = Uri.tryParse(trimmed)?.pathSegments ?? const <String>[];
  if (pathSegments.isNotEmpty &&
      (pathSegments.first == 'api' || pathSegments.first == 'uploads')) {
    final base = Uri.base;
    if (base.scheme == 'http' || base.scheme == 'https') {
      return base.resolve(trimmed).toString();
    }
    return trimmed;
  }
  return null;
}

String _avatarCacheKey(String? avatarUrl, String? userId) {
  return '${userId ?? ''}|${avatarUrl?.trim() ?? ''}';
}

Future<String> _copyLocalAvatarFile(XFile file) async {
  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) {
    throw Exception(I18n.tr('profile.avatar.empty'));
  }
  if (bytes.length > 3 * 1024 * 1024) {
    throw Exception(I18n.tr('profile.avatar.too_large'));
  }
  final root = await getApplicationDocumentsDirectory();
  final dir = Directory('${root.path}/profile_avatars');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  final filename =
      'avatar_${DateTime.now().microsecondsSinceEpoch}${_avatarExtensionFor(file.name)}';
  final target = File('${dir.path}/$filename');
  await target.writeAsBytes(bytes, flush: true);
  return target.path;
}

String _avatarExtensionFor(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.jpeg')) return '.jpg';
  for (final extension in ['.jpg', '.png', '.webp', '.gif']) {
    if (lower.endsWith(extension)) return extension;
  }
  return '.png';
}
