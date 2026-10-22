import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Shared visual timing. Real timers, request deadlines and reminder intervals
/// must stay independent of this accessibility-aware animation policy.
class AppMotion {
  AppMotion._();

  static const Curve enterCurve = Curves.easeOutCubic;
  static const Curve exitCurve = Curves.easeInCubic;
  static const double routeTravel = 12;
  static const Duration loadingCycle = Duration(milliseconds: 1200);

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static Duration duration(BuildContext context, Duration normal) =>
      reduced(context) ? Duration.zero : normal;

  static Duration feedback(BuildContext context) =>
      duration(context, DesignTokens.durationFast);

  static Duration transition(BuildContext context) =>
      duration(context, DesignTokens.durationBase);

  static AnimationStyle overlayStyle(BuildContext context) => AnimationStyle(
    duration: transition(context),
    reverseDuration: feedback(context),
    curve: enterCurve,
    reverseCurve: exitCurve,
  );

  static const AnimationStyle expansionStyle = AnimationStyle(
    duration: DesignTokens.durationBase,
    reverseDuration: DesignTokens.durationFast,
    curve: enterCurve,
    reverseCurve: exitCurve,
  );

  /// ExpansionTile does not read the platform's reduced-motion preference.
  static ThemeData themeFor(BuildContext context, ThemeData theme) =>
      reduced(context)
      ? theme.copyWith(
          expansionTileTheme: theme.expansionTileTheme.copyWith(
            expansionAnimationStyle: AnimationStyle.noAnimation,
          ),
        )
      : theme;

  static const PageTransitionsTheme pageTransitions = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: AppPageTransitionsBuilder(
        nativeBuilder: PredictiveBackPageTransitionsBuilder(),
      ),
      TargetPlatform.iOS: AppPageTransitionsBuilder(
        nativeBuilder: CupertinoPageTransitionsBuilder(),
      ),
      TargetPlatform.macOS: AppPageTransitionsBuilder(
        nativeBuilder: CupertinoPageTransitionsBuilder(),
      ),
      TargetPlatform.windows: AppPageTransitionsBuilder(),
      TargetPlatform.linux: AppPageTransitionsBuilder(),
      TargetPlatform.fuchsia: AppPageTransitionsBuilder(),
    },
  );
}

/// A restrained fade and short vertical travel on Web/desktop. Native mobile
/// builders keep their durations, interactive back gestures and delegation.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  final PageTransitionsBuilder? nativeBuilder;

  const AppPageTransitionsBuilder({this.nativeBuilder});

  @override
  Duration get transitionDuration => !kIsWeb && nativeBuilder != null
      ? nativeBuilder!.transitionDuration
      : DesignTokens.durationBase;

  @override
  Duration get reverseTransitionDuration => !kIsWeb && nativeBuilder != null
      ? nativeBuilder!.reverseTransitionDuration
      : DesignTokens.durationFast;

  @override
  DelegatedTransitionBuilder? get delegatedTransition {
    final delegate = kIsWeb ? null : nativeBuilder?.delegatedTransition;
    if (delegate == null) return null;
    return (context, animation, secondaryAnimation, allowSnapshotting, child) =>
        AppMotion.reduced(context)
        ? child
        : delegate(
            context,
            animation,
            secondaryAnimation,
            allowSnapshotting,
            child,
          );
  }

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final reduced = AppMotion.reduced(context);
    if (!kIsWeb && nativeBuilder != null) {
      if (reduced && nativeBuilder is! CupertinoPageTransitionsBuilder) {
        return child;
      }
      return nativeBuilder!.buildTransitions(
        route,
        context,
        reduced ? kAlwaysCompleteAnimation : animation,
        reduced ? kAlwaysDismissedAnimation : secondaryAnimation,
        child,
      );
    }
    if (reduced) return child;
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final curve = animation.status == AnimationStatus.reverse
            ? AppMotion.exitCurve
            : AppMotion.enterCurve;
        final progress = curve.transform(animation.value);
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, AppMotion.routeTravel * (1 - progress)),
            child: child,
          ),
        );
      },
    );
  }
}
