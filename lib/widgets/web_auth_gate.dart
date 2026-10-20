import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../providers/auth_provider.dart';
import '../screens/login_screen.dart';
import 'auth_page_frame.dart';

typedef _SessionIdentity = ({String server, String token, String? userId});

/// Sits above the application's Navigator so logout removes every private route.
/// Native clients retain their existing offline workflow.
class WebAuthGate extends StatefulWidget {
  final bool enabled;
  final Widget child;

  const WebAuthGate({super.key, required this.enabled, required this.child});

  @override
  State<WebAuthGate> createState() => _WebAuthGateState();
}

class _WebAuthGateState extends State<WebAuthGate> {
  _SessionIdentity? _observed;
  _SessionIdentity? _verified;
  int _verificationSerial = 0;
  bool _checking = false;
  bool _unavailable = false;

  _SessionIdentity? _identity(AuthProvider auth) {
    final state = auth.state;
    return state.isLoggedIn
        ? (server: auth.baseUrl, token: state.token!, userId: state.userId)
        : null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _observe(context.watch<AuthProvider>());
  }

  @override
  void didUpdateWidget(WebAuthGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      _verificationSerial++;
      _observed = null;
      _verified = null;
      _checking = false;
      _unavailable = false;
      _observe(context.read<AuthProvider>());
    }
  }

  void _observe(AuthProvider auth) {
    if (!widget.enabled) return;
    final identity = _identity(auth);
    if (_observed == identity) return;
    _verificationSerial++;
    _observed = identity;
    _verified = null;
    _unavailable = false;
    _checking = identity != null;
    if (identity != null) {
      final serial = _verificationSerial;
      unawaited(Future.microtask(() => _verify(auth, identity, serial)));
    }
  }

  Future<void> _verify(
    AuthProvider auth,
    _SessionIdentity identity,
    int serial,
  ) async {
    try {
      await auth.verifyWebSession();
      if (!mounted ||
          serial != _verificationSerial ||
          _identity(auth) != identity) {
        return;
      }
      setState(() {
        _verified = identity;
        _checking = false;
        _unavailable = false;
      });
    } catch (_) {
      if (!mounted ||
          serial != _verificationSerial ||
          _identity(auth) != identity) {
        return;
      }
      setState(() {
        _checking = false;
        _unavailable = true;
      });
    }
  }

  void _retry() {
    final auth = context.read<AuthProvider>();
    final identity = _identity(auth);
    if (identity == null) return;
    setState(() {
      _checking = true;
      _unavailable = false;
    });
    unawaited(_verify(auth, identity, ++_verificationSerial));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!widget.enabled) return widget.child;
    if (_verified != null && _verified == _identity(auth)) {
      return KeyedSubtree(
        key: ValueKey((auth.baseUrl, auth.state.userId ?? auth.state.username)),
        child: widget.child,
      );
    }
    // This Navigator belongs only to public authentication (e.g. recovery dialogs).
    // It never contains the authenticated application's routes.
    return Navigator(
      pages: [
        MaterialPage<void>(
          key: const ValueKey('web-auth-entry'),
          child: _checking || _unavailable
              ? AuthPageFrame(
                  allowBack: false,
                  title: I18n.tr('auth.session.title'),
                  subtitle: I18n.tr(
                    _checking
                        ? 'auth.session.checking'
                        : 'auth.session.unavailable',
                  ),
                  child: _checking
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FilledButton(
                              onPressed: _retry,
                              child: Text(I18n.tr('action.retry')),
                            ),
                            const SizedBox(height: DesignTokens.spaceSm),
                            TextButton(
                              onPressed: () => auth.logout(),
                              child: Text(
                                I18n.tr('auth.session.sign_in_again'),
                              ),
                            ),
                          ],
                        ),
                )
              : const LoginScreen(asEntry: true),
        ),
      ],
      onDidRemovePage: (_) {},
    );
  }
}
