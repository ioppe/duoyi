import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_text_scale.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../providers/preferences_provider.dart';
import '../widgets/surface_components.dart';

String textScaleLabel(double scale) => switch (AppTextScale.normalize(scale)) {
  AppTextScale.small => I18n.tr('preferences.text_scale.small'),
  AppTextScale.standard => I18n.tr('preferences.text_scale.standard'),
  AppTextScale.large => I18n.tr('preferences.text_scale.large'),
  final value => I18n.tr(
    'preferences.text_scale.percent',
  ).replaceAll('{percent}', '${AppTextScale.percentOf(value)}'),
};

/// A local draft previews the chosen size. Only Done persists it.
class TextSizeSettingsScreen extends StatefulWidget {
  const TextSizeSettingsScreen({super.key});

  @override
  State<TextSizeSettingsScreen> createState() => _TextSizeSettingsScreenState();
}

class _TextSizeSettingsScreenState extends State<TextSizeSettingsScreen> {
  late final PreferencesProvider _preferences;
  late double _draft;
  String? _owner;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _preferences = context.read<PreferencesProvider>();
    _draft = _preferences.textScale;
    _owner = _preferences.textScaleOwner;
    _preferences.addListener(_onPreferencesChanged);
  }

  @override
  void dispose() {
    _preferences.removeListener(_onPreferencesChanged);
    super.dispose();
  }

  void _onPreferencesChanged() {
    if (_owner == _preferences.textScaleOwner) return;
    setState(() {
      _owner = _preferences.textScaleOwner;
      _draft = _preferences.textScale;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final owner = _owner;
    if (owner != _preferences.textScaleOwner) {
      _onPreferencesChanged();
      return;
    }
    setState(() => _saving = true);
    try {
      await _preferences.setTextScale(_draft);
      if (!mounted) return;
      setState(() => _saving = false);
      if (owner == _preferences.textScaleOwner) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(I18n.tr('preferences.text_scale.save_failed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LocaleProvider>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final previewBackground = Color.alphaBlend(
      cs.onSurface.withValues(alpha: 0.05),
      cs.surface,
    );
    final media = MediaQuery.of(context);
    final platformScaler = AppTextScale.systemScalerOf(media.textScaler);
    final previewScaler = AppTextScale.resolve(
      system: platformScaler,
      appScale: _draft,
    );
    final percent = AppTextScale.percentOf(_draft);
    final percentLabel = I18n.tr(
      'preferences.text_scale.percent',
    ).replaceAll('{percent}', '$percent');

    // Controls use the platform scaler so the full preview range stays usable.
    return MediaQuery(
      data: media.copyWith(textScaler: platformScaler),
      child: PopScope(
        canPop: !_saving,
        child: RepaintBoundary(
          key: const ValueKey('text_size_page'),
          child: Scaffold(
            backgroundColor: previewBackground,
            appBar: AppBar(
              backgroundColor: previewBackground,
              surfaceTintColor: Colors.transparent,
              centerTitle: true,
              leading: BackButton(
                key: const ValueKey('text_size_back_button'),
                onPressed: _saving
                    ? () {}
                    : () => Navigator.of(context).maybePop(),
              ),
              title: Text(I18n.tr('preferences.menu.text_scale')),
              titleTextStyle: appSecondaryRouteTitleTextStyle(context),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: DesignTokens.spaceMd),
                  child: FilledButton(
                    key: const ValueKey('text_size_done_button'),
                    onPressed: _saving ? null : _save,
                    child: Text(I18n.tr('preferences.text_scale.done')),
                  ),
                ),
              ],
            ),
            body: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    key: const ValueKey('text_size_preview_scroll'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.spaceLg,
                      vertical: DesignTokens.space3xl,
                    ),
                    child: MediaQuery(
                      data: media.copyWith(textScaler: previewScaler),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _PreviewBubble(
                            key: const ValueKey('text_size_preview_title'),
                            outgoing: true,
                            text: I18n.tr(
                              'preferences.text_scale.preview_title',
                            ),
                          ),
                          const SizedBox(height: DesignTokens.spaceXxl),
                          _PreviewBubble(
                            text: I18n.tr(
                              'preferences.text_scale.preview_hint',
                            ),
                          ),
                          const SizedBox(height: DesignTokens.spaceXxl),
                          _PreviewBubble(
                            text: I18n.tr(
                              'preferences.text_scale.preview_note',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _buildControls(context, percentLabel),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context, String percentLabel) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: cs.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            DesignTokens.spaceLg,
            DesignTokens.spaceLg,
            DesignTokens.spaceLg,
            DesignTokens.spaceMd,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('A', style: textTheme.bodyMedium),
                  Expanded(
                    child: Text(
                      percentLabel,
                      key: const ValueKey('text_size_percent_label'),
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium,
                    ),
                  ),
                  Text('A', style: textTheme.headlineMedium),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: DesignTokens.spaceXxs,
                  activeTrackColor: cs.outline,
                  inactiveTrackColor: cs.outline,
                  activeTickMarkColor: cs.outline,
                  inactiveTickMarkColor: cs.outline,
                  thumbColor: cs.primary,
                  tickMarkShape: const _TextSizeTickShape(),
                  showValueIndicator: ShowValueIndicator.never,
                ),
                child: Slider(
                  key: const ValueKey('text_size_slider'),
                  value: AppTextScale.indexOf(_draft).toDouble(),
                  min: 0,
                  max: (AppTextScale.options.length - 1).toDouble(),
                  divisions: AppTextScale.options.length - 1,
                  label: percentLabel,
                  semanticFormatterCallback: (index) => textScaleLabel(
                    AppTextScale.options[index.round().clamp(
                      0,
                      AppTextScale.options.length - 1,
                    )],
                  ),
                  onChanged: _saving
                      ? null
                      : (index) {
                          setState(
                            () => _draft = AppTextScale.options[index.round()],
                          );
                        },
                ),
              ),
              Align(
                alignment: const Alignment(-5 / 7, 0),
                child: Text(
                  I18n.tr('preferences.text_scale.standard_marker'),
                  key: const ValueKey('text_size_standard_marker'),
                  style: textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewBubble extends StatelessWidget {
  const _PreviewBubble({super.key, required this.text, this.outgoing = false});

  final String text;
  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final avatar = Container(
      width: DesignTokens.space4xl,
      height: DesignTokens.space4xl,
      decoration: BoxDecoration(
        color: outgoing ? cs.secondaryContainer : cs.primary,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
      ),
      child: Icon(
        outgoing ? Icons.person_outline : Icons.checklist_rounded,
        color: outgoing ? cs.onSecondaryContainer : cs.onPrimary,
        size: DesignTokens.controlIconSize,
      ),
    );
    final bubble = Flexible(
      child: Container(
        padding: const EdgeInsets.all(DesignTokens.spaceLg),
        decoration: BoxDecoration(
          color: outgoing ? cs.primaryContainer : cs.surface,
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: outgoing ? cs.onPrimaryContainer : cs.onSurface,
          ),
        ),
      ),
    );
    return Row(
      mainAxisAlignment: outgoing
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: outgoing
          ? [bubble, const SizedBox(width: DesignTokens.spaceMd), avatar]
          : [avatar, const SizedBox(width: DesignTokens.spaceMd), bubble],
    );
  }
}

class _TextSizeTickShape extends SliderTickMarkShape {
  const _TextSizeTickShape();

  @override
  Size getPreferredSize({
    required SliderThemeData sliderTheme,
    required bool isEnabled,
  }) => const Size(1, DesignTokens.spaceMd);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    required bool isEnabled,
    required TextDirection textDirection,
  }) {
    context.canvas.drawLine(
      center - const Offset(0, DesignTokens.spaceXs),
      center + const Offset(0, DesignTokens.spaceXs),
      Paint()
        ..color = sliderTheme.inactiveTickMarkColor ?? Colors.grey
        ..strokeWidth = 1,
    );
  }
}
