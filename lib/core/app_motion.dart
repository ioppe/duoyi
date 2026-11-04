import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PredictiveBackEvent;

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
      TargetPlatform.android: kIsWeb
          ? AppPageTransitionsBuilder()
          : _AndroidSlidePageTransitionsBuilder(),
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

/// Full-size horizontal navigation after Android confirms a back gesture.
/// The previous page stays still; no shared-element zoom or corner morph.
class _AndroidSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const _AndroidSlidePageTransitionsBuilder();

  @override
  Duration get transitionDuration => DesignTokens.durationBase;

  @override
  Duration get reverseTransitionDuration => DesignTokens.durationFast;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      _AndroidSlideTransition(route: route, animation: animation, child: child);
}

class _AndroidSlideTransition extends StatefulWidget {
  const _AndroidSlideTransition({
    required this.route,
    required this.animation,
    required this.child,
  });

  final PageRoute<dynamic> route;
  final Animation<double> animation;
  final Widget child;

  @override
  State<_AndroidSlideTransition> createState() =>
      _AndroidSlideTransitionState();
}

class _AndroidSlideTransitionState extends State<_AndroidSlideTransition>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent event) {
    final route = widget.route;
    if (event.isButtonEvent || !route.isCurrent || !route.popGestureEnabled) {
      return false;
    }
    // Let Android own the gesture, but keep the route fully visible until
    // the system commits it. Progress updates intentionally do not move it.
    route.handleStartBackGesture(progress: 1.0);
    return true;
  }

  @override
  void handleCancelBackGesture() => widget.route.handleCancelBackGesture();

  @override
  void handleCommitBackGesture() {
    final route = widget.route;
    if (route.isCurrent && route.popDisposition != RoutePopDisposition.pop) {
      route.handleCancelBackGesture();
      return;
    }
    route.handleCommitBackGesture();
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) return widget.child;
    final direction = Directionality.of(context);
    final animation = widget.animation;
    return AnimatedBuilder(
      animation: animation,
      child: widget.child,
      builder: (context, child) {
        final curve = animation.status == AnimationStatus.reverse
            ? AppMotion.exitCurve
            : AppMotion.enterCurve;
        final progress = curve.transform(animation.value);
        return FractionalTranslation(
          translation: Offset(
            (1 - progress) * (direction == TextDirection.ltr ? 1 : -1),
            0,
          ),
          child: child,
        );
      },
    );
  }
}

/// A restrained fade and short vertical travel on Web/desktop. Cupertino
/// platforms keep their native durations, interactive back and delegation.
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
