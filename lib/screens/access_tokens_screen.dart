import '../core/app_clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/i18n_date_format.dart';
import 'package:provider/provider.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../widgets/brand_background.dart';
import '../widgets/surface_components.dart';

class AccessTokensScreen extends StatefulWidget {
  const AccessTokensScreen({super.key});

  @override
  State<AccessTokensScreen> createState() => _AccessTokensScreenState();
}

class _AccessTokensScreenState extends State<AccessTokensScreen> {
  List<Map<String, dynamic>> _tokens = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    final client = auth.client;
    try {
      final tokens = await auth.listAccessTokens();
      if (!mounted || !identical(client, auth.client)) return;
      setState(() {
        _tokens = tokens;
        _error = null;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = userVisibleApiError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final input = await showDialog<({String name, int? days})>(
      context: context,
      builder: (_) => const _CreateTokenDialog(),
    );
    if (input == null || !mounted) return;
    setState(() => _busy = true);
    final auth = context.read<AuthProvider>();
    final client = auth.client;
    try {
      final result = await auth.createAccessToken(
        name: input.name,
        expiresInDays: input.days,
      );
      if (!mounted || !identical(client, auth.client)) return;
      final secret = result['token'] as String;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text(I18n.tr('tokens.created')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(I18n.tr('tokens.copy_notice')),
                const SizedBox(height: DesignTokens.spaceLg),
                Text(I18n.tr('auth.server.address')),
                SelectableText(
                  auth.baseUrl.isEmpty ? Uri.base.origin : auth.baseUrl,
                ),
                const SizedBox(height: DesignTokens.spaceLg),
                SelectableText(
                  secret,
                  key: const ValueKey('created-access-token'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: secret));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(I18n.tr('tokens.copied'))),
                );
              },
              icon: const Icon(Icons.copy_outlined),
              label: Text(I18n.tr('tokens.copy')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(I18n.tr('action.complete')),
            ),
          ],
        ),
      );
      if (mounted) await _load();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = userVisibleApiError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(Map<String, dynamic> token) async {
    final current = token['current'] == true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(I18n.tr('tokens.revoke_title')),
        content: Text(
          I18n.tr(current ? 'tokens.revoke_current' : 'tokens.revoke_message'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(I18n.tr('action.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(I18n.tr('tokens.revoke')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<AuthProvider>().revokeAccessToken(
        token['id'].toString(),
        current: current,
      );
      if (!mounted) return;
      if (current) {
        Navigator.of(context).pop();
      } else {
        await _load();
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = userVisibleApiError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _date(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    return date == null
        ? I18n.tr('tokens.not_used')
        : I18nDateFormat.fullDateTime(AppClock.toLocal(date));
  }

  Widget _tokenCard(Map<String, dynamic> token) {
    final revoked = token['revoked_at'] != null;
    final expiration = DateTime.tryParse(token['expires_at']?.toString() ?? '');
    final expired = expiration != null && expiration.isBefore(DateTime.now());
    final inactive = revoked || expired;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: DesignTokens.spaceMd),
      child: AppSurfaceCard(
        padding: const EdgeInsets.all(DesignTokens.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  inactive ? Icons.key_off_outlined : Icons.key_outlined,
                  color: inactive
                      ? theme.disabledColor
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: DesignTokens.spaceMd),
                Expanded(
                  child: Text(
                    token['name'].toString(),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (!inactive)
                  TextButton(
                    onPressed: _busy ? null : () => _revoke(token),
                    child: Text(I18n.tr('tokens.revoke')),
                  ),
              ],
            ),
            Text('${token['prefix'] ?? ''}…', style: theme.textTheme.bodySmall),
            const SizedBox(height: DesignTokens.spaceSm),
            Text(
              '${I18n.tr('tokens.last_used')}: ${_date(token['last_used_at'])}',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              expiration == null
                  ? I18n.tr('tokens.never_expires')
                  : '${I18n.tr('tokens.expires_at')}: ${_date(token['expires_at'])}',
              style: theme.textTheme.bodySmall,
            ),
            if (revoked || expired || token['current'] == true) ...[
              const SizedBox(height: DesignTokens.spaceSm),
              Text(
                I18n.tr(
                  revoked
                      ? 'tokens.revoked'
                      : expired
                      ? 'tokens.expired'
                      : 'tokens.current',
                ),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    return BrandBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(I18n.tr('tokens.title')),
          titleTextStyle: appSecondaryRouteTitleTextStyle(context),
          backgroundColor: Colors.transparent,
        ),
        body: SafeArea(
          top: false,
          child: RefreshIndicator(
            onRefresh: _busy ? () async {} : _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(DesignTokens.spaceLg),
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          I18n.tr('tokens.subtitle'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: DesignTokens.spaceMd),
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(I18n.tr('auth.token.use_token')),
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: DesignTokens.spaceLg,
                              ),
                              child: Text(I18n.tr('tokens.help')),
                            ),
                          ],
                        ),
                        const SizedBox(height: DesignTokens.spaceMd),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: _loading || _busy ? null : _create,
                            icon: const Icon(Icons.add),
                            label: Text(I18n.tr('action.create')),
                          ),
                        ),
                        if (_loading || _busy) const LinearProgressIndicator(),
                        if (_error != null) ...[
                          const SizedBox(height: DesignTokens.spaceMd),
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          TextButton(
                            onPressed: _busy ? null : _load,
                            child: Text(I18n.tr('action.retry')),
                          ),
                        ],
                        if (!_loading && _error == null && _tokens.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: DesignTokens.spaceXxl,
                            ),
                            child: Text(I18n.tr('tokens.empty')),
                          ),
                        ..._tokens.map(_tokenCard),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateTokenDialog extends StatefulWidget {
  const _CreateTokenDialog();

  @override
  State<_CreateTokenDialog> createState() => _CreateTokenDialogState();
}

class _CreateTokenDialogState extends State<_CreateTokenDialog> {
  final _name = TextEditingController();
  int _days = 0;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(I18n.tr('action.create')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppFormFieldTheme(
              child: TextField(
                controller: _name,
                autofocus: true,
                maxLength: 80,
                decoration: InputDecoration(
                  labelText: I18n.tr('tokens.name'),
                  hintText: I18n.tr('tokens.name_hint'),
                  errorText: _error,
                ),
              ),
            ),
            const SizedBox(height: DesignTokens.spaceMd),
            AppFormFieldTheme(
              child: DropdownButtonFormField<int>(
                initialValue: _days,
                decoration: InputDecoration(
                  labelText: I18n.tr('tokens.expiry'),
                ),
                items: [
                  for (final item in {
                    0: 'tokens.never_expires',
                    30: 'tokens.days_30',
                    90: 'tokens.days_90',
                    365: 'tokens.days_365',
                  }.entries)
                    DropdownMenuItem(
                      value: item.key,
                      child: Text(I18n.tr(item.value)),
                    ),
                ],
                onChanged: (value) => setState(() => _days = value ?? 0),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(I18n.tr('action.cancel')),
        ),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty) {
              setState(() => _error = I18n.tr('tokens.name_required'));
              return;
            }
            Navigator.pop(context, (
              name: _name.text.trim(),
              days: _days == 0 ? null : _days,
            ));
          },
          child: Text(I18n.tr('action.create')),
        ),
      ],
    );
  }
}
