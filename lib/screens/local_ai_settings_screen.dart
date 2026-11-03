import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../services/ai_service.dart';
import '../widgets/surface_components.dart';

/// 本机 AI 配置页。
///
/// 未登录远程账号（本机模式）时可编辑并保存本机模型服务配置；已登录远程
/// 账号时只展示服务器当前 AI 状态与说明，表单整体隐藏，密钥输入框同步清空，
/// 不提供本机配置编辑或直连测试入口。
class LocalAiSettingsScreen extends StatefulWidget {
  const LocalAiSettingsScreen({super.key});

  @override
  State<LocalAiSettingsScreen> createState() => _LocalAiSettingsScreenState();
}

class _LocalAiSettingsScreenState extends State<LocalAiSettingsScreen> {
  final _baseUrlCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();

  bool _enabled = false;
  bool _showApiKey = false;
  bool _loading = true;
  bool _busy = false;
  bool _dirty = false;
  // 程序化回填/清空不算用户草稿，避免覆盖已填草稿的脏标记误置位。
  bool _suppressDirty = false;
  bool _localMode = true;
  String? _error;
  String? _notice;

  /// 每次加载/切模式自增；迟到的异步结果与 generation 不一致时直接丢弃，
  /// 避免把旧草稿写回已切换的界面。
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    final ai = context.read<AiService>();
    _localMode = ai.usingLocalConfiguration;
    _loading = _localMode;
    _baseUrlCtrl.addListener(_markDirty);
    _modelCtrl.addListener(_markDirty);
    _apiKeyCtrl.addListener(_markDirty);
    if (_localMode) {
      unawaited(_loadConfiguration());
    }
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _modelCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (_suppressDirty) return;
    _dirty = true;
  }

  void _setControllerText(TextEditingController controller, String value) {
    if (controller.text == value) return;
    _suppressDirty = true;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _suppressDirty = false;
  }

  void _clearApiKeyField() {
    if (_apiKeyCtrl.text.isEmpty) return;
    _suppressDirty = true;
    _apiKeyCtrl.clear();
    _suppressDirty = false;
  }

  Future<void> _loadConfiguration() async {
    final ai = context.read<AiService>();
    final generation = ++_generation;
    if (!_loading) {
      setState(() {
        _loading = true;
        _error = null;
        _notice = null;
      });
    }
    await ai.loadLocalConfiguration();
    if (!mounted || generation != _generation) return;
    setState(() {
      _loading = false;
      _busy = false;
      if (ai.localConfigError != null && !ai.localConfigLoaded) {
        _error = I18n.tr('ai.local.error_storage');
        return;
      }
      if (_dirty) return;
      _enabled = ai.localConfig.enabled;
      _setControllerText(_baseUrlCtrl, ai.localConfig.baseUrl);
      _setControllerText(_modelCtrl, ai.localConfig.model);
      // 已保存的密钥从不回显：输入框永远从空白开始。
      _clearApiKeyField();
      _dirty = false;
    });
  }

  void _handleModeChanged(bool localMode) {
    if (!mounted) return;
    _generation++;
    _dirty = false;
    _showApiKey = false;
    _clearApiKeyField();
    if (localMode) {
      setState(() {
        _enabled = false;
        _error = null;
        _notice = null;
      });
      _setControllerText(_baseUrlCtrl, '');
      _setControllerText(_modelCtrl, '');
      _dirty = false;
      unawaited(_loadConfiguration());
      return;
    }
    // 切到服务器 AI：立即收起表单，丢弃未完成的本机结果。
    setState(() {
      _loading = false;
      _busy = false;
      _error = null;
      _notice = null;
    });
  }

  String? _validateDraft({required bool requireEndpoint}) {
    if (!requireEndpoint) return null;
    if (_baseUrlCtrl.text.trim().isEmpty) {
      return I18n.tr('ai.local.error_url');
    }
    if (_modelCtrl.text.trim().isEmpty) {
      return I18n.tr('ai.local.error_model');
    }
    return null;
  }

  String? _draftApiKey() {
    final key = _apiKeyCtrl.text.trim();
    return key.isEmpty ? null : key;
  }

  Future<void> _save() async {
    if (_busy) return;
    final validation = _validateDraft(requireEndpoint: _enabled);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    final ai = context.read<AiService>();
    final generation = _generation;
    final apiKey = _draftApiKey();
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await ai.saveLocalConfiguration(
        enabled: _enabled,
        baseUrl: _baseUrlCtrl.text.trim(),
        model: _modelCtrl.text.trim(),
        apiKey: apiKey,
      );
      if (!mounted || generation != _generation) return;
      // 保存成功后只清空密钥输入框，保留用户已填的地址/模型草稿。
      _clearApiKeyField();
      setState(() {
        _busy = false;
        _dirty = false;
        _showApiKey = false;
        _notice = I18n.tr('ai.local.saved');
      });
    } on AiException catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _error = I18n.tr('ai.local.error_storage');
      });
    }
  }

  Future<void> _testConnection() async {
    if (_busy) return;
    final validation = _validateDraft(requireEndpoint: true);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    final ai = context.read<AiService>();
    final generation = _generation;
    final apiKey = _draftApiKey();
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      // 只测当前草稿，不写存储，也不改变启用状态。
      await ai.testLocalConfiguration(
        baseUrl: _baseUrlCtrl.text.trim(),
        model: _modelCtrl.text.trim(),
        apiKey: apiKey,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _notice = I18n.tr('ai.local.test_ok');
      });
    } on AiException catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _error = I18n.tr('ai.local.unavailable');
      });
    }
  }

  Future<void> _clearConfiguration() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text(I18n.tr('ai.local.clear_title')),
        content: Text(I18n.tr('ai.local.clear_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(I18n.tr('action.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(I18n.tr('action.confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ai = context.read<AiService>();
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await ai.clearLocalConfiguration();
      if (!mounted || generation != _generation) return;
      _setControllerText(_baseUrlCtrl, '');
      _setControllerText(_modelCtrl, '');
      _clearApiKeyField();
      setState(() {
        _enabled = false;
        _dirty = false;
        _busy = false;
        _showApiKey = false;
        _notice = I18n.tr('ai.local.cleared');
      });
    } on AiException catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _error = I18n.tr('ai.local.error_storage');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ai = context.watch<AiService>();
    final localMode = ai.usingLocalConfiguration;
    if (localMode != _localMode) {
      _localMode = localMode;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            context.read<AiService>().usingLocalConfiguration != localMode) {
          return;
        }
        _handleModeChanged(localMode);
      });
    }
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          I18n.tr('ai.local.title'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            DesignTokens.spaceMd,
            DesignTokens.spaceSm,
            DesignTokens.spaceMd,
            DesignTokens.spaceXxl,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: DesignTokens.creationFormMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: localMode
                    ? _buildLocalBody(context, ai, cs)
                    : _buildRemoteBody(context, ai, cs),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildLocalBody(
    BuildContext context,
    AiService ai,
    ColorScheme cs,
  ) {
    if (_loading) {
      return [
        AppSurfaceCard(
          key: const ValueKey('local_ai_loading'),
          padding: const EdgeInsets.all(DesignTokens.spaceXl),
          child: const Center(
            child: SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ];
    }
    return [
      AppInfoBanner(
        key: const ValueKey('local_ai_description'),
        icon: Icons.shield_outlined,
        message: I18n.tr('ai.local.description'),
        color: cs.primary,
      ),
      const SizedBox(height: DesignTokens.spaceMd),
      AppFormFieldTheme(
        child: AppSurfaceCard(
          padding: const EdgeInsets.all(DesignTokens.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSwitchTile(
                key: const ValueKey('local_ai_enabled_switch'),
                icon: Icons.auto_awesome_outlined,
                title: I18n.tr('ai.local.enabled'),
                color: cs.primary,
                value: _enabled,
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                        _enabled = value;
                        _dirty = true;
                      }),
              ),
              const SizedBox(height: DesignTokens.spaceMd),
              _buildBaseUrlField(),
              const SizedBox(height: DesignTokens.spaceMd),
              _buildModelField(),
              const SizedBox(height: DesignTokens.spaceMd),
              _buildApiKeyField(ai),
            ],
          ),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: DesignTokens.spaceMd),
        AppInfoBanner(
          key: const ValueKey('local_ai_error'),
          icon: Icons.error_outline,
          message: _error!,
          color: cs.error,
        ),
      ],
      if (_notice != null) ...[
        const SizedBox(height: DesignTokens.spaceMd),
        AppInfoBanner(
          key: const ValueKey('local_ai_notice'),
          icon: Icons.check_circle_outline,
          message: _notice!,
          color: Colors.green,
        ),
      ],
      const SizedBox(height: DesignTokens.spaceLg),
      _buildActions(context, cs),
    ];
  }

  Widget _buildBaseUrlField() {
    return TextField(
      key: const ValueKey('local_ai_base_url_field'),
      controller: _baseUrlCtrl,
      enabled: !_busy,
      keyboardType: TextInputType.url,
      autocorrect: false,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: I18n.tr('ai.local.base_url'),
        hintText: I18n.tr('ai.local.base_url_hint'),
      ),
    );
  }

  Widget _buildModelField() {
    return TextField(
      key: const ValueKey('local_ai_model_field'),
      controller: _modelCtrl,
      enabled: !_busy,
      autocorrect: false,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: I18n.tr('ai.local.model'),
        hintText: I18n.tr('ai.local.model_hint'),
      ),
    );
  }

  Widget _buildApiKeyField(AiService ai) {
    final hasSavedKey = ai.localConfig.hasApiKey;
    return TextField(
      key: const ValueKey('local_ai_api_key_field'),
      controller: _apiKeyCtrl,
      enabled: !_busy,
      autocorrect: false,
      enableSuggestions: false,
      obscureText: !_showApiKey,
      decoration: InputDecoration(
        labelText: I18n.tr('ai.local.api_key'),
        hintText: hasSavedKey
            ? I18n.tr('ai.local.key_saved')
            : I18n.tr('ai.local.key_hint'),
        suffixIcon: IconButton(
          key: const ValueKey('local_ai_api_key_visibility'),
          tooltip: I18n.tr(
            _showApiKey ? 'ai.local.hide_key' : 'ai.local.show_key',
          ),
          onPressed: _busy
              ? null
              : () => setState(() => _showApiKey = !_showApiKey),
          icon: Icon(
            _showApiKey
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context, ColorScheme cs) {
    return Wrap(
      spacing: DesignTokens.spaceMd,
      runSpacing: DesignTokens.spaceSm,
      children: [
        FilledButton(
          key: const ValueKey('local_ai_save_button'),
          onPressed: _busy ? null : _save,
          style: appSecondaryFilledButtonStyle(context),
          child: _busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(I18n.tr('ai.local.save')),
        ),
        OutlinedButton(
          key: const ValueKey('local_ai_test_button'),
          onPressed: _busy ? null : _testConnection,
          child: Text(I18n.tr('ai.local.test')),
        ),
        TextButton(
          key: const ValueKey('local_ai_clear_button'),
          onPressed: _busy ? null : _clearConfiguration,
          style: TextButton.styleFrom(foregroundColor: cs.error),
          child: Text(I18n.tr('ai.local.clear')),
        ),
      ],
    );
  }

  List<Widget> _buildRemoteBody(
    BuildContext context,
    AiService ai,
    ColorScheme cs,
  ) {
    final theme = Theme.of(context);
    return [
      AppInfoBanner(
        key: const ValueKey('local_ai_remote_status'),
        icon: Icons.cloud_outlined,
        title: I18n.tr('ai.local.server_title'),
        message: I18n.tr('ai.local.server_description'),
        color: cs.primary,
      ),
      const SizedBox(height: DesignTokens.spaceMd),
      AppSurfaceCard(
        padding: const EdgeInsets.all(DesignTokens.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  ai.enabled ? Icons.check_circle_outline : Icons.info_outline,
                  size: 18,
                  color: ai.enabled
                      ? Colors.green
                      : cs.onSurface.withValues(alpha: 0.60),
                ),
                const SizedBox(width: DesignTokens.spaceSm),
                Expanded(
                  child: Text(
                    ai.enabled
                        ? I18n.tr('ai.local.server_enabled')
                        : I18n.tr('ai.local.server_disabled'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface,
                      fontWeight: DesignTokens.fontWeightStrong,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: DesignTokens.spaceXs),
            Text(
              ai.enabled && ai.model.trim().isNotEmpty
                  ? '${I18n.tr('ai.local.model')} · ${ai.model}'
                  : I18n.tr('ai.local.not_configured'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.62),
              ),
            ),
          ],
        ),
      ),
    ];
  }
}
