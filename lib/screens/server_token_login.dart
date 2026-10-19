import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_client.dart';
import '../widgets/brand_background.dart';
import '../widgets/surface_components.dart';

class ServerTokenLogin extends StatefulWidget {
  final VoidCallback onPasswordLogin;

  const ServerTokenLogin({super.key, required this.onPasswordLogin});

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
      _token.clear();
      if (mounted) Navigator.of(context).pop();
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
    final strings = context.watch<ThemeProvider>().brand.strings;
    final theme = Theme.of(context);
    return BrandBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(I18n.tr('auth.login.title')),
          titleTextStyle: appSecondaryRouteTitleTextStyle(context),
          backgroundColor: Colors.transparent,
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(DesignTokens.spaceXl),
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: AppSurfaceCard(
                    padding: const EdgeInsets.all(DesignTokens.spaceLg),
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            strings.appTitle,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: DesignTokens.spaceSm),
                          Text(
                            I18n.tr('auth.token.title'),
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: DesignTokens.spaceSm),
                          Text(
                            I18n.tr(
                              kIsWeb
                                  ? 'auth.token.subtitle.web'
                                  : 'auth.token.subtitle',
                            ),
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: DesignTokens.spaceXxl),
                          AppFormFieldTheme(
                            child: TextField(
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
                                helperText: kIsWeb
                                    ? I18n.tr('auth.server.current_site')
                                    : null,
                                suffixIcon: kIsWeb
                                    ? const Icon(Icons.lock_outline)
                                    : null,
                                prefixIcon: const Icon(Icons.dns_outlined),
                              ),
                            ),
                          ),
                          const SizedBox(height: DesignTokens.spaceLg),
                          AppFormFieldTheme(
                            child: TextField(
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
                                    _obscure
                                        ? 'auth.token.show'
                                        : 'auth.token.hide',
                                  ),
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: DesignTokens.spaceLg),
                          Text(
                            I18n.tr('auth.token.help'),
                            style: theme.textTheme.bodySmall,
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: DesignTokens.spaceMd),
                            Text(
                              _error!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ],
                          const SizedBox(height: DesignTokens.spaceXxl),
                          FilledButton(
                            onPressed: _busy ? null : _connect,
                            child: _busy
                                ? const SizedBox(
                                    width: DesignTokens.spaceXl,
                                    height: DesignTokens.spaceXl,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(I18n.tr('auth.login')),
                          ),
                          const SizedBox(height: DesignTokens.spaceSm),
                          TextButton(
                            onPressed: _busy ? null : widget.onPasswordLogin,
                            child: Text(I18n.tr('auth.token.password_login')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
