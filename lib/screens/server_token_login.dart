import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../widgets/auth_page_frame.dart';

class ServerTokenLogin extends StatefulWidget {
  final VoidCallback onPasswordLogin;
  final bool asEntry;

  const ServerTokenLogin({
    super.key,
    required this.onPasswordLogin,
    this.asEntry = false,
  });

  @override
  State<ServerTokenLogin> createState() => _ServerTokenLoginState();
}

class _ServerTokenLoginState extends State<ServerTokenLogin> {
  late final TextEditingController _server;
  final _token = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _server = TextEditingController(
      text: kIsWeb ? Uri.base.origin : context.read<AuthProvider>().baseUrl,
    );
  }

  @override
  void dispose() {
    _server.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthProvider>().loginWithToken(
        serverUrl: _server.text,
        token: _token.text,
      );
      if (!mounted) return;
      _token.clear();
      if (!widget.asEntry && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = userVisibleApiError(error));
    } catch (_) {
      if (mounted) {
        setState(() => _error = I18n.tr('auth.token.invalid_response'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AuthPageFrame(
      allowBack: !widget.asEntry,
      title: I18n.tr('auth.design.welcome'),
      subtitle: I18n.tr(
        kIsWeb ? 'auth.token.subtitle.web' : 'auth.token.subtitle',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('token-server-url'),
            controller: _server,
            enabled: !_busy,
            readOnly: kIsWeb,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: I18n.tr('auth.server.address'),
              hintText: I18n.tr('auth.server.hint'),
              helperText: kIsWeb ? I18n.tr('auth.server.current_site') : null,
              helperMaxLines: 3,
              suffixIcon: kIsWeb ? const Icon(Icons.lock_outline) : null,
              prefixIcon: const Icon(Icons.dns_outlined),
            ),
          ),
          const SizedBox(height: DesignTokens.spaceLg),
          TextField(
            key: const ValueKey('access-token'),
            controller: _token,
            enabled: !_busy,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _connect(),
            decoration: InputDecoration(
              labelText: I18n.tr('auth.token.label'),
              prefixIcon: const Icon(Icons.key_outlined),
              suffixIcon: IconButton(
                tooltip: I18n.tr(
                  _obscure ? 'auth.token.show' : 'auth.token.hide',
                ),
                onPressed: _busy
                    ? null
                    : () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: DesignTokens.spaceLg),
          Text(
            I18n.tr('auth.token.help'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: DesignTokens.spaceLg),
            AuthNotice(message: _error!, isError: true),
          ],
          const SizedBox(height: DesignTokens.spaceXxl),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, DesignTokens.formFieldMinHeight),
              padding: const EdgeInsets.all(DesignTokens.spaceLg),
              shape: const RoundedRectangleBorder(
                borderRadius: DesignTokens.borderRadiusLg,
              ),
            ),
            onPressed: _busy ? null : _connect,
            child: _busy
                ? const SizedBox(
                    width: DesignTokens.spaceXl,
                    height: DesignTokens.spaceXl,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(I18n.tr('auth.login')),
          ),
          const SizedBox(height: DesignTokens.spaceSm),
          TextButton(
            onPressed: _busy ? null : widget.onPasswordLogin,
            child: Text(
              I18n.tr('auth.token.password_login'),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
