import 'package:flutter/material.dart';

import '../core/design_tokens.dart';

class PomodoroTimerRing extends StatelessWidget {
  final double progress;
  final String timeText;
  final Color color;
  final double size;
  final bool countUp;
  final String? statusLabel;

  const PomodoroTimerRing({
    super.key,
    required this.progress,
    required this.timeText,
    required this.color,
    this.size = 220,
    this.countUp = false,
    this.statusLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (statusLabel != null) return _buildMinimal(context);
    final compact = size < 150;
    final timeFontSize = size >= 200
        ? 48.0
        : compact
        ? 32.0
        : 40.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.15),
            blurRadius: 30,
            spreadRadius: 10,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size - 18,
            height: size - 18,
            child: CircularProgressIndicator(
              value: countUp ? 1.0 : progress,
              strokeWidth: 6,
              strokeCap: StrokeCap.round,
              backgroundColor: Colors.grey.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(DesignTokens.spaceMd),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    timeText,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: timeFontSize,
                      fontWeight: DesignTokens.fontWeightStrong,
                      fontFamily: DesignTokens.fontFamily,
                      letterSpacing: 0,
                      color: Theme.of(context).textTheme.headlineSmall?.color,
                    ),
                  ),
                  if (!compact) const SizedBox(height: 8),
                  if (!countUp && progress > 0 && !compact)
                    Text(
                      '${(progress.clamp(0.0, 1.0) * 100).round()}%',
                      style: TextStyle(
                        fontSize: progress >= 1.0 ? 14 : 16,
                        color: Colors.grey.shade500,
                        fontWeight: DesignTokens.fontWeightStrong,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMinimal(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final timeStyle = theme.textTheme.displaySmall?.copyWith(
      fontSize: DesignTokens.focusRestTimerFontSize,
      fontWeight: DesignTokens.fontWeightStrong,
      letterSpacing: -1.5,
    );
    final painter = TextPainter(
      text: TextSpan(text: timeText, style: timeStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final readableSize = painter.width + DesignTokens.space3xl;
    painter.dispose();
    return LayoutBuilder(
      builder: (context, constraints) {
        final preferred = readableSize > size ? readableSize : size;
        final diameter = preferred.clamp(0.0, constraints.maxWidth);
        return SizedBox(
          width: diameter,
          height: diameter,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(DesignTokens.spaceXs),
                  child: CircularProgressIndicator(
                    value: countUp ? 1 : progress.clamp(0.0, 1.0),
                    strokeWidth: DesignTokens.focusRestRingStrokeWidth,
                    strokeCap: StrokeCap.round,
                    backgroundColor: color.withValues(alpha: 0.13),
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(DesignTokens.spaceLg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeText,
                      maxLines: 1,
                      softWrap: false,
                      style: timeStyle,
                    ),
                    const SizedBox(height: DesignTokens.spaceXxs),
                    Text(
                      statusLabel!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
