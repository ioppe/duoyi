import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';

/// 专注时长快捷选项（分钟）：手机 chips 与桌面下拉共用同一组预设。
const List<int> kFocusDurationPresets = <int>[15, 25, 30, 45, 60, 90];

/// 原生桌面（macOS / Windows / Linux）改用单一、可鼠标与键盘操作的下拉时长
/// 选择；选项完整展示，不需要横向拖动。
///
/// 用 [defaultTargetPlatform] 而不是 `io.Platform`，测试可用
/// `TargetPlatformVariant` 覆盖；Web（含手机 Web）与移动端继续使用原有 chips。
bool usesDesktopFocusDurationPicker() {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;
}

/// 时长选项文案：`25 分钟` / `25 min`，复用 focus.rest 已有的分钟单位。
String focusDurationOptionLabel(int minutes) =>
    '$minutes ${I18n.tr('focus.rest.unit_minutes')}';

/// 桌面专注时长选择：下拉分钟数 + 独立的「正向计时」开关。
///
/// 当前自定义时长（不在预设内）会作为唯一一项保留在下拉里，因此 Provider
/// 重建、换账号都不会把已选时长重置回预设。
class FocusDurationPicker extends StatelessWidget {
  /// 当前专注时长（分钟）：取自 `provider.config.focusDuration`。
  final int focusMinutes;

  /// 是否正向计时（自由计时）。
  final bool isCountUp;

  /// 运行中 / 暂停中 / 跨端只读时为 false，两个控件一起禁用。
  final bool enabled;

  final ValueChanged<int> onMinutesSelected;
  final ValueChanged<bool> onCountUpChanged;

  /// 预设分钟数；测试可覆盖。
  final List<int> presets;

  const FocusDurationPicker({
    super.key,
    required this.focusMinutes,
    required this.isCountUp,
    required this.enabled,
    required this.onMinutesSelected,
    required this.onCountUpChanged,
    this.presets = kFocusDurationPresets,
  });

  static const Key dropdownKey = ValueKey('focus_duration_dropdown');
  static const Key countUpKey = ValueKey('focus_countup_toggle');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // 预设 ∪ 当前值：自定义时长始终是下拉里的一项。
    final options = <int>{...presets, focusMinutes}.toList()..sort();
    final value = options.contains(focusMinutes) ? focusMinutes : options.first;
    final labelStyle = (theme.textTheme.bodySmall ?? const TextStyle())
        .copyWith(
          fontWeight: DesignTokens.fontWeightMedium,
          color: enabled ? cs.onSurface : cs.onSurface.withValues(alpha: 0.38),
        );

    return Wrap(
      spacing: DesignTokens.spaceSm,
      runSpacing: DesignTokens.spaceSm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 172,
          child: InputDecorator(
            decoration: InputDecoration(
              isDense: true,
              enabled: enabled,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spaceMd,
                vertical: 10,
              ),
              prefixIcon: const Icon(Icons.timer_outlined, size: 16),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 34,
                minHeight: 0,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                key: dropdownKey,
                value: value,
                isDense: true,
                isExpanded: true,
                borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
                icon: const Icon(
                  Icons.expand_more,
                  size: DesignTokens.controlIconSize,
                ),
                style: labelStyle,
                items: [
                  for (final minutes in options)
                    DropdownMenuItem<int>(
                      value: minutes,
                      child: Text(
                        focusDurationOptionLabel(minutes),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: enabled
                    ? (selected) {
                        if (selected == null) return;
                        onMinutesSelected(selected);
                      }
                    : null,
              ),
            ),
          ),
        ),
        ChoiceChip(
          key: countUpKey,
          visualDensity: VisualDensity.standard,
          avatar: const Icon(Icons.all_inclusive, size: 16),
          label: Text(I18n.tr('focus.rest.timer_countup')),
          labelStyle: labelStyle,
          selected: isCountUp,
          onSelected: enabled ? (_) => onCountUpChanged(!isCountUp) : null,
        ),
      ],
    );
  }
}
