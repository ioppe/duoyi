import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/i18n.dart';
import '../core/design_tokens.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import 'package:flutter/services.dart';
import '../widgets/auth_page_frame.dart';
import '../widgets/surface_components.dart';
import 'server_token_login.dart';

class LoginScreen extends StatefulWidget {
  final bool asEntry;

  const LoginScreen({super.key, this.asEntry = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginActionField extends StatelessWidget {
  final Widget field;
  final Widget action;

  const _LoginActionField({required this.field, required this.action});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final actionWidth = constraints.maxWidth < 360 ? 64.0 : 72.0;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: field),
            const SizedBox(width: 8),
            SizedBox(
              width: actionWidth,
              height: DesignTokens.formFieldMinHeight,
              child: action,
            ),
          ],
        );
      },
    );
  }
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _emailCodeCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _confirmPwdCtrl = TextEditingController();
  final _inviteCtrl = TextEditingController();
  final _serverCtrl = TextEditingController();
  bool _tokenLogin = false;
  bool _obscurePassword = true;
  final _pwdFocus = FocusNode();
  bool _isRegister = false;
  bool _emailLogin = false;
  bool _registerWithEmail = true;
  bool _busy = false;
  bool _sendingEmailCode = false;
  int _emailCooldownSeconds = 0;
  Timer? _emailCooldownTimer;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    _serverCtrl.text = context.read<AuthProvider>().baseUrl;
    _userCtrl.addListener(_refreshControls);
    _emailCtrl.addListener(_refreshControls);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(context.read<AuthProvider>().refreshServerConfigFromServer());
      }
    });
  }

  @override
  void dispose() {
    _emailCooldownTimer?.cancel();
    _userCtrl.removeListener(_refreshControls);
    _emailCtrl.removeListener(_refreshControls);
    _userCtrl.dispose();
    _emailCtrl.dispose();
    _emailCodeCtrl.dispose();
    _displayNameCtrl.dispose();
    _pwdCtrl.dispose();
    _confirmPwdCtrl.dispose();
    _inviteCtrl.dispose();
    _serverCtrl.dispose();
    _pwdFocus.dispose();
    super.dispose();
  }

  void _refreshControls() {
    if (mounted) setState(() {});
  }

  Future<void> _submit() async {
    if (_busy || _sendingEmailCode) return;
    final auth = context.read<AuthProvider>();
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    final passwordLogin = !_isRegister && !_emailLogin;
    try {
      if (!kIsWeb) await auth.configureServer(_serverCtrl.text);
      if (_isRegister) await auth.refreshServerConfigFromServer();
      if (!mounted) return;
      final validationError = _validateSubmit(auth);
      if (validationError != null) {
        setState(() => _error = validationError);
        return;
      }
      if (_isRegister) {
        await auth.register(
          username: _userCtrl.text.trim(),
          password: _pwdCtrl.text,
          email: _emailCtrl.text.trim(),
          emailCode: _emailCodeCtrl.text.trim(),
          displayName: _displayNameCtrl.text.trim(),
          inviteCode: auth.inviteCodeRequired ? _inviteCtrl.text.trim() : null,
        );
      } else if (_emailLogin) {
        await auth.emailLogin(
          email: _userCtrl.text.trim(),
          code: _emailCodeCtrl.text.trim(),
        );
      } else {
        await auth.login(
          username: _userCtrl.text.trim(),
          password: _pwdCtrl.text,
        );
      }
      TextInput.finishAutofillContext();
      if (mounted && !widget.asEntry && Navigator.of(context).canPop()) {
        Navigator.pop(context);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (passwordLogin && _isInvalidCredentialsError(e)) {
        setState(() {
          _error = I18n.tr('auth.error.invalid_credentials');
          _pwdCtrl.clear();
        });
        _pwdFocus.requestFocus();
      } else {
        setState(() => _error = userVisibleApiError(e));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendEmailCode() async {
    if (!_canSendEmailCode) return;
    final auth = context.read<AuthProvider>();
    final email = _isRegister ? _emailCtrl.text.trim() : _userCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = I18n.tr('auth.error.email_required'));
      return;
    }
    if (!_looksLikeEmail(email)) {
      setState(() => _error = I18n.tr('auth.error.email_invalid'));
      return;
    }
    setState(() {
      _sendingEmailCode = true;
      _error = null;
      _message = null;
    });
    try {
      if (!kIsWeb) await auth.configureServer(_serverCtrl.text);
      final result = await auth.sendEmailCode(
        email: email,
        purpose: _isRegister ? 'bind' : 'login',
      );
      final devCode = (result['dev_code'] ?? '').toString();
      final message = (result['message'] ?? I18n.tr('auth.email_code.sent'))
          .toString();
      if (!mounted) return;
      _startEmailCooldown();
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
      if (mounted) setState(() => _sendingEmailCode = false);
    }
  }

  bool get _canSendEmailCode {
    if (_busy || _sendingEmailCode || _emailCooldownSeconds > 0) return false;
    final email = _isRegister ? _emailCtrl.text.trim() : _userCtrl.text.trim();
    return email.isNotEmpty && _looksLikeEmail(email);
  }

  String? _validateSubmit(AuthProvider auth) {
    final account = _userCtrl.text.trim();
    if (account.isEmpty) {
      return _isRegister
          ? I18n.tr('auth.error.username_required')
          : I18n.tr('auth.error.account_required');
    }
    if (_isRegister) {
      final shouldBindEmail =
          auth.registrationEmailRequired || _registerWithEmail;
      if (account.length < 3 || account.length > 64) {
        return I18n.tr('auth.error.username_length');
      }
      if (RegExp(r'\s').hasMatch(account)) {
        return I18n.tr('auth.error.username_no_space');
      }
      final email = _emailCtrl.text.trim();
      if (shouldBindEmail && email.isEmpty) {
        return I18n.tr('auth.error.email_required');
      }
      if (email.isNotEmpty && !_looksLikeEmail(email)) {
        return I18n.tr('auth.error.email_invalid');
      }
      if (shouldBindEmail && _emailCodeCtrl.text.trim().isEmpty) {
        return I18n.tr('auth.error.email_code_required');
      }
      if (_pwdCtrl.text.length < 6) return I18n.tr('auth.error.password_short');
      if (_confirmPwdCtrl.text != _pwdCtrl.text) {
        return I18n.tr('auth.error.password_mismatch');
      }
      if (auth.inviteCodeRequired && _inviteCtrl.text.trim().isEmpty) {
        return I18n.tr('auth.error.invite_required');
      }
    } else if (_emailLogin) {
      if (!_looksLikeEmail(account)) {
        return I18n.tr('auth.error.verified_email_required');
      }
      if (_emailCodeCtrl.text.trim().isEmpty) {
        return I18n.tr('auth.error.email_code_input_required');
      }
    } else if (_pwdCtrl.text.isEmpty) {
      return I18n.tr('auth.error.password_required');
    }
    return null;
  }

  void _startEmailCooldown() {
    _emailCooldownTimer?.cancel();
    setState(() => _emailCooldownSeconds = 60);
    _emailCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_emailCooldownSeconds <= 1) {
        timer.cancel();
        setState(() => _emailCooldownSeconds = 0);
      } else {
        setState(() => _emailCooldownSeconds -= 1);
      }
    });
  }

  Widget _emailCodeButton() {
    final canSend = _canSendEmailCode;
    return FilledButton(
      onPressed: canSend ? _sendEmailCode : null,
      style: appSecondaryFilledButtonStyle(context),
      child: _sendingEmailCode
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _emailCooldownSeconds > 0
                    ? '${_emailCooldownSeconds}s 后'
                    : I18n.tr('auth.send'),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
    );
  }

  Widget _emailCodeField({
    required TextEditingController controller,
    required String labelText,
  }) {
    return AppFormFieldTheme(
      child: TextField(
        controller: controller,
        enabled: !_busy && !_sendingEmailCode,
        keyboardType: TextInputType.number,
        autofillHints: const [AutofillHints.oneTimeCode],
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: labelText,
          prefixIcon: const Icon(Icons.pin_outlined),
        ),
      ),
    );
  }

  Widget _emailCodeSendField({
    required TextEditingController controller,
    required String labelText,
  }) {
    return _LoginActionField(
      field: _emailCodeField(controller: controller, labelText: labelText),
      action: _emailCodeButton(),
    );
  }

  Widget _field({
    required String key,
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboard,
    Iterable<String>? autofillHints,
  }) => TextField(
    key: ValueKey(key),
    controller: controller,
    enabled: !_busy && !_sendingEmailCode,
    keyboardType: keyboard,
    autocorrect: false,
    textInputAction: TextInputAction.next,
    autofillHints: autofillHints,
    decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
  );

  Widget _passwordField({bool confirm = false}) => TextField(
    key: ValueKey(confirm ? 'auth-confirm-password' : 'auth-password'),
    controller: confirm ? _confirmPwdCtrl : _pwdCtrl,
    focusNode: confirm ? null : _pwdFocus,
    enabled: !_busy && !_sendingEmailCode,
    obscureText: _obscurePassword,
    autocorrect: false,
    enableSuggestions: false,
    autofillHints: [
      _isRegister ? AutofillHints.newPassword : AutofillHints.password,
    ],
    textInputAction: _isRegister && !confirm
        ? TextInputAction.next
        : TextInputAction.done,
    onSubmitted: _isRegister && !confirm ? null : (_) => _submit(),
    decoration: InputDecoration(
      labelText: confirm
          ? I18n.tr('auth.confirm_password')
          : I18n.tr('auth.password'),
      prefixIcon: const Icon(Icons.lock_outline_rounded),
      suffixIcon: IconButton(
        tooltip: I18n.tr(
          _obscurePassword ? 'auth.password.show' : 'auth.password.hide',
        ),
        onPressed: _busy || _sendingEmailCode
            ? null
            : () => setState(() => _obscurePassword = !_obscurePassword),
        icon: Icon(
          _obscurePassword
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
        ),
      ),
    ),
  );

  void _switchRegistration() {
    setState(() {
      _isRegister = !_isRegister;
      _emailLogin = false;
      _registerWithEmail = true;
      _emailCodeCtrl.clear();
      _pwdCtrl.clear();
      _confirmPwdCtrl.clear();
      _obscurePassword = true;
      _error = null;
      _message = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_tokenLogin) {
      return ServerTokenLogin(
        asEntry: widget.asEntry,
        onPasswordLogin: () => setState(() {
          _tokenLogin = false;
          _emailLogin = false;
          _serverCtrl.text = context.read<AuthProvider>().baseUrl;
        }),
      );
    }
    final auth = context.watch<AuthProvider>();
    final cs = Theme.of(context).colorScheme;
    final registrationEmailRequired = auth.registrationEmailRequired;
    final shouldBindRegistrationEmail =
        registrationEmailRequired || _registerWithEmail;
    final disabled = _busy || _sendingEmailCode;
    return AuthPageFrame(
      allowBack: !widget.asEntry,
      title: I18n.tr(
        _isRegister ? 'auth.design.signup' : 'auth.design.welcome',
      ),
      subtitle: I18n.tr(
        _isRegister
            ? 'auth.design.signup_subtitle'
            : 'auth.design.login_subtitle',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (auth.maintenanceMode) ...[
            AuthNotice(
              message: auth.maintenanceMessage.isEmpty
                  ? I18n.tr('auth.maintenance')
                  : auth.maintenanceMessage,
            ),
            const SizedBox(height: DesignTokens.spaceLg),
          ],
          if (!_isRegister) ...[
            AppSecondaryControlTheme(
              child: Wrap(
                spacing: DesignTokens.spaceSm,
                runSpacing: DesignTokens.spaceSm,
                children: [
                  ChoiceChip(
                    label: Text(I18n.tr('auth.password_login')),
                    selected: !_emailLogin,
                    showCheckmark: false,
                    onSelected: disabled
                        ? null
                        : (_) => setState(() {
                            _emailLogin = false;
                            _emailCodeCtrl.clear();
                            _error = null;
                            _message = null;
                          }),
                  ),
                  ChoiceChip(
                    label: Text(I18n.tr('auth.email_code_login')),
                    selected: _emailLogin,
                    showCheckmark: false,
                    onSelected: disabled
                        ? null
                        : (_) => setState(() {
                            _emailLogin = true;
                            _pwdCtrl.clear();
                            _error = null;
                            _message = null;
                          }),
                  ),
                  ChoiceChip(
                    label: Text(I18n.tr('auth.token.login')),
                    selected: false,
                    showCheckmark: false,
                    onSelected: disabled
                        ? null
                        : (_) => setState(() => _tokenLogin = true),
                  ),
                ],
              ),
            ),
            const SizedBox(height: DesignTokens.spaceXl),
          ],
          if (!kIsWeb) ...[
            _field(
              key: 'password-server-url',
              controller: _serverCtrl,
              label: I18n.tr('auth.server.address'),
              icon: Icons.dns_outlined,
              keyboard: TextInputType.url,
            ),
            const SizedBox(height: DesignTokens.spaceLg),
          ],
          _field(
            key: 'auth-account',
            controller: _userCtrl,
            label: _isRegister
                ? I18n.tr('auth.username')
                : (_emailLogin
                      ? I18n.tr('auth.verified_email')
                      : I18n.tr('auth.account')),
            icon: _emailLogin
                ? Icons.mail_outline_rounded
                : Icons.person_outline_rounded,
            keyboard: _emailLogin
                ? TextInputType.emailAddress
                : TextInputType.text,
            autofillHints: [
              _isRegister ? AutofillHints.newUsername : AutofillHints.username,
            ],
          ),
          const SizedBox(height: DesignTokens.spaceLg),
          if (_isRegister || !_emailLogin) _passwordField(),
          if (_isRegister) ...[
            const SizedBox(height: DesignTokens.spaceLg),
            _passwordField(confirm: true),
            const SizedBox(height: DesignTokens.spaceLg),
            _field(
              key: 'auth-display-name',
              controller: _displayNameCtrl,
              label: I18n.tr('auth.display_name.optional'),
              icon: Icons.badge_outlined,
              autofillHints: const [AutofillHints.nickname],
            ),
            const SizedBox(height: DesignTokens.spaceLg),
            if (!registrationEmailRequired) ...[
              AppSecondaryControlTheme(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(I18n.tr('profile.email.binding')),
                          const SizedBox(height: DesignTokens.spaceXs),
                          Text(
                            I18n.tr('auth.email.optional'),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: _registerWithEmail,
                      onChanged: disabled
                          ? null
                          : (value) => setState(() {
                              _registerWithEmail = value;
                              _error = null;
                              _message = null;
                              if (!value) {
                                _emailCtrl.clear();
                                _emailCodeCtrl.clear();
                              }
                            }),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: DesignTokens.spaceLg),
            ],
            if (shouldBindRegistrationEmail) ...[
              _field(
                key: 'auth-email',
                controller: _emailCtrl,
                label: registrationEmailRequired
                    ? I18n.tr('auth.email')
                    : I18n.tr('auth.email.optional'),
                icon: Icons.mail_outline_rounded,
                keyboard: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
              ),
              const SizedBox(height: DesignTokens.spaceSm),
              if (registrationEmailRequired) ...[
                Text(
                  I18n.tr('auth.email.required_helper'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: DesignTokens.spaceSm),
              ],
              _emailCodeSendField(
                controller: _emailCodeCtrl,
                labelText: I18n.tr('auth.email_code'),
              ),
              const SizedBox(height: DesignTokens.spaceLg),
            ],
            if (auth.inviteCodeRequired) ...[
              _field(
                key: 'auth-invite-code',
                controller: _inviteCtrl,
                label: I18n.tr('auth.invite_code'),
                icon: Icons.confirmation_number_outlined,
              ),
              const SizedBox(height: DesignTokens.spaceLg),
            ],
          ] else if (_emailLogin) ...[
            _emailCodeSendField(
              controller: _emailCodeCtrl,
              labelText: I18n.tr('auth.email_code'),
            ),
            const SizedBox(height: DesignTokens.spaceLg),
          ] else ...[
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: disabled ? null : _showPasswordResetDialog,
                child: Text(I18n.tr('auth.forgot_password')),
              ),
            ),
          ],
          if (_isRegister && !auth.registrationEnabled) ...[
            AuthNotice(message: I18n.tr('auth.registration_closed')),
            const SizedBox(height: DesignTokens.spaceLg),
          ],
          if (_error != null) ...[
            AuthNotice(message: _error!, isError: true),
            const SizedBox(height: DesignTokens.spaceLg),
          ],
          if (_message != null) ...[
            AuthNotice(message: _message!),
            const SizedBox(height: DesignTokens.spaceLg),
          ],
          FilledButton(
            key: const ValueKey('auth-submit'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, DesignTokens.formFieldMinHeight),
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spaceLg,
                vertical: DesignTokens.spaceLg,
              ),
              shape: const RoundedRectangleBorder(
                borderRadius: DesignTokens.borderRadiusLg,
              ),
            ),
            onPressed:
                _busy ||
                    _sendingEmailCode ||
                    (_isRegister && !auth.registrationEnabled)
                ? null
                : _submit,
            child: _busy
                ? const SizedBox(
                    width: DesignTokens.spaceXl,
                    height: DesignTokens.spaceXl,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _isRegister
                        ? I18n.tr('auth.register')
                        : I18n.tr('auth.login'),
                  ),
          ),
          const SizedBox(height: DesignTokens.spaceSm),
          TextButton(
            key: const ValueKey('auth-switch-mode'),
            onPressed: disabled ? null : _switchRegistration,
            child: Text(
              _isRegister
                  ? I18n.tr('auth.switch_to_login')
                  : I18n.tr('auth.switch_to_register'),
              textAlign: TextAlign.center,
            ),
          ),
          if (kIsWeb && !_isRegister) ...[
            const SizedBox(height: DesignTokens.spaceMd),
            Text(
              I18n.tr('auth.design.first_admin'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.6,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showPasswordResetDialog() async {
    if (!kIsWeb) {
      try {
        await context.read<AuthProvider>().configureServer(_serverCtrl.text);
      } on ApiException catch (e) {
        if (mounted) setState(() => _error = userVisibleApiError(e));
        return;
      }
      if (!mounted) return;
    }
    await showDialog(
      context: context,
      builder: (_) => const _PasswordResetDialog(),
    );
  }
}

class _PasswordResetDialog extends StatefulWidget {
  const _PasswordResetDialog();

  @override
  State<_PasswordResetDialog> createState() => _PasswordResetDialogState();
}

class _PasswordResetDialogState extends State<_PasswordResetDialog> {
  final _accountCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _newPwdCtrl = TextEditingController();
  bool _requested = false;
  bool _busy = false;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;
  String? _error;
  String? _message;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _accountCtrl.dispose();
    _codeCtrl.dispose();
    _newPwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    final account = _accountCtrl.text.trim();
    if (account.isEmpty) {
      setState(() => _error = I18n.tr('auth.error.reset_account_required'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final result = await context.read<AuthProvider>().requestPasswordReset(
        account: account,
      );
      _startCooldown();
      final devCode = (result['dev_code'] ?? '').toString();
      final message =
          (result['message'] ?? I18n.tr('auth.password_reset.email_sent'))
              .toString();
      setState(() {
        _requested = true;
        _message = devCode.isEmpty
            ? message
            : '$message ${I18n.tr('auth.email_code.code_prefix')}$devCode';
      });
    } on ApiException catch (e) {
      setState(() => _error = userVisibleApiError(e));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final account = _accountCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _error = I18n.tr('auth.error.mail_code_required'));
      return;
    }
    if (_newPwdCtrl.text.length < 6) {
      setState(() => _error = I18n.tr('auth.error.new_password_short'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final accountLooksEmail = _looksLikeEmail(account);
      await context.read<AuthProvider>().confirmPasswordReset(
        account: account,
        email: accountLooksEmail ? account : null,
        code: code,
        newPassword: _newPwdCtrl.text,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(I18n.tr('auth.password_reset.done'))),
      );
    } on ApiException catch (e) {
      setState(() => _error = userVisibleApiError(e));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppDialog(
      title: Text(I18n.tr('auth.password_reset.title')),
      icon: const Icon(Icons.lock_reset_outlined),
      shiftForKeyboard: true,
      content: AppFormFieldTheme(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _accountCtrl,
              enabled: !_requested,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(
                labelText: I18n.tr('auth.reset_account'),
                helperText: I18n.tr('auth.reset_account.helper'),
              ),
            ),
            if (_requested) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: I18n.tr('auth.email_code'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newPwdCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: I18n.tr('auth.new_password'),
                ),
              ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(
                _message!,
                style: TextStyle(color: cs.primary, fontSize: 12, height: 1.25),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: cs.error, fontSize: 12, height: 1.25),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(I18n.tr('action.cancel')),
        ),
        FilledButton(
          onPressed: _busy || (!_requested && _cooldownSeconds > 0)
              ? null
              : (_requested ? _confirm : _request),
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  _requested
                      ? I18n.tr('auth.password_reset.confirm')
                      : (_cooldownSeconds > 0
                            ? '${_cooldownSeconds}s'
                            : I18n.tr('auth.password_reset.send_email')),
                ),
        ),
      ],
    );
  }
}

bool _looksLikeEmail(String value) {
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());
}

bool _isInvalidCredentialsError(ApiException error) {
  final message = error.message.toLowerCase();
  return message.contains('invalid credentials') ||
      message.contains('invalid username or password') ||
      message.contains('incorrect username or password') ||
      message.contains('账号或密码') ||
      message.contains('用户名或密码') ||
      (message.startsWith('401:') && message.contains('credentials'));
}
