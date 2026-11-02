import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_motion.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/web_target.dart';

/// Web（含窄屏 Web）与 native macOS 把 `showAppModalSheet` 的内容渲染成居中的
/// 通用对话框；native Android / iOS 继续使用底部半屏面板（初始半屏、可展开
/// 收起、拖动手柄、安全区与键盘避让全部保持不变）。
///
/// 判定用 [defaultTargetPlatform]，不用 `kIsWeb` 也不用 `dart:io` 的 host 检查：
/// - `kIsWeb` 在 `flutter test` 的 VM 上恒为 false，macOS 宿主无法用测试覆盖；
/// - `Platform.isMacOS` 会让所有跑在 mac 宿主上的 widget test 误入桌面分支。
/// 测试只需要 override [debugDefaultTargetPlatformOverride]（或
/// [WebTarget.debugWebBuild]）即可切到目标分支。
bool useAppModalCenteredPresentation() =>
    WebTarget.isWebBuild || defaultTargetPlatform == TargetPlatform.macOS;

/// 一次 modal 的呈现方式：是否居中、是否可关闭。
///
/// 由 [showAppModalCenteredDialog] 通过 [AppModalPresentationScope] 传给
/// builder 内部（可能是嵌套多层）的 `AppModalSheet`，因此调用点不需要任何
/// 参数改动，也不需要逐屏判断平台。
@immutable
class AppModalPresentation {
  /// true：居中对话框；false：底部半屏面板。
  final bool centered;

  /// false 时不渲染关闭按钮，遮罩点击、Escape 与系统返回都不关闭。
  final bool dismissible;

  const AppModalPresentation({required this.centered, this.dismissible = true});

  /// 底部面板（native Android / iOS）以及未挂 scope 的独立使用场景。
  static const AppModalPresentation bottomSheet = AppModalPresentation(
    centered: false,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppModalPresentation &&
          other.centered == centered &&
          other.dismissible == dismissible;

  @override
  int get hashCode => Object.hash(centered, dismissible);
}

class AppModalPresentationScope extends InheritedWidget {
  final AppModalPresentation presentation;

  const AppModalPresentationScope({
    super.key,
    required this.presentation,
    required super.child,
  });

  /// 未挂 scope 时回落到底部面板，保持共享组件单独使用时的既有行为。
  static AppModalPresentation of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AppModalPresentationScope>()
          ?.presentation ??
      AppModalPresentation.bottomSheet;

  static bool isCentered(BuildContext context) => of(context).centered;

  @override
  bool updateShouldNotify(AppModalPresentationScope oldWidget) =>
      oldWidget.presentation != presentation;
}

/// 桌面 / Web 的居中 modal 路由。
///
/// 与 `showModalBottomSheet` 对齐的语义：`Navigator.pop` 的返回值、嵌套
/// 子弹层、`useRootNavigator`、调用点捕获的 InheritedTheme 以及
/// `barrierDismissible`。位置、视口和键盘余高由本函数负责，卡片表面
/// （唯一一层 Material）由 `AppModalSheet` 负责，不叠加第二层 surface/handle。
Future<T?> showAppModalCenteredDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool useRootNavigator = false,
  bool shiftForKeyboard = true,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  // 与 showModalBottomSheet 一致地捕获调用点的 InheritedTheme（主题、品牌、
  // 语言等），使对话框内的文案与底色跟随发起页面。
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  final theme = Theme.of(context);
  final barrierColor =
      theme.dialogTheme.barrierColor ??
      theme.bottomSheetTheme.modalBarrierColor ??
      theme.colorScheme.scrim.withValues(alpha: 0.32);
  final reducedMotion = AppMotion.reduced(context);

  return navigator.push<T>(
    PageRouteBuilder<T>(
      settings: const RouteSettings(name: 'app-modal-centered-dialog'),
      opaque: false,
      barrierDismissible: isDismissible,
      barrierColor: barrierColor,
      barrierLabel: I18n.tr('action.close'),
      // 约 200ms 的轻淡入 + 0.96→1 缩放；系统开启减少动画时 duration 为
      // 零并在 transitionsBuilder 里直接返回 child（单帧到位，无百分比）。
      transitionDuration: AppMotion.transition(context),
      reverseTransitionDuration: AppMotion.feedback(context),
      pageBuilder: (routeContext, animation, secondaryAnimation) => themes.wrap(
        AppModalPresentationScope(
          presentation: AppModalPresentation(
            centered: true,
            dismissible: isDismissible,
          ),
          child: AppModalCenteredLayout(
            dismissible: isDismissible,
            shiftForKeyboard: shiftForKeyboard,
            child: Builder(builder: builder),
          ),
        ),
      ),
      transitionsBuilder: (routeContext, animation, secondaryAnimation, child) {
        if (reducedMotion) return child;
        final curved = animation.drive(CurveTween(curve: AppMotion.enterCurve));
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(
              begin: DesignTokens.appModalCenteredScaleBegin,
              end: 1,
            ).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

/// 居中弹层的位置 / 视口约束 / 键盘余高 / 焦点闭环。
///
/// 只做「把内容放到可用的居中区域」，不画背景、不画阴影、不再叠一层
/// Material：视觉表面由 `AppModalSheet` 的卡片负责。
class AppModalCenteredLayout extends StatefulWidget {
  final Widget child;
  final bool dismissible;
  final bool shiftForKeyboard;

  const AppModalCenteredLayout({
    super.key,
    required this.child,
    this.dismissible = true,
    this.shiftForKeyboard = true,
  });

  @override
  State<AppModalCenteredLayout> createState() => _AppModalCenteredLayoutState();
}

class _AppModalCenteredLayoutState extends State<AppModalCenteredLayout> {
  final FocusScopeNode _focusScopeNode = FocusScopeNode(
    debugLabel: 'AppModalCenteredDialog',
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  );

  @override
  void initState() {
    super.initState();
    // 默认 requestFocus：打开后键盘焦点进入对话框，Tab 在卡片内部闭环，
    // 不会跑到面板后面的页面上。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusScopeNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusScopeNode.dispose();
    super.dispose();
  }

  void _handleDismissIntent() {
    if (!widget.dismissible) return;
    // maybePop 而不是 pop：尊重内容自带的 PopScope（例如未保存草稿确认）。
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // 键盘余高只在这里扣一次；卡片内部通过 removeViewInsets 看到 0，
    // 不会出现「弹层和 route 各扣一遍键盘」的双重上移。
    final bottomInset = widget.shiftForKeyboard ? media.viewInsets.bottom : 0.0;
    final margin =
        media.size.width < DesignTokens.appModalCenteredNarrowBreakpoint
        ? DesignTokens.appModalCenteredNarrowMargin
        : DesignTokens.appModalCenteredMargin;
    final safeHeight = media.size.height - bottomInset - media.padding.top;
    final heightLimit = safeHeight.isFinite && safeHeight > 0
        ? safeHeight
        : 0.0;
    final availableHeight = (safeHeight - margin * 2)
        .clamp(0.0, heightLimit)
        .toDouble();
    final maxHeight =
        availableHeight * DesignTokens.appModalCenteredMaxHeightFactor;
    final maxWidth = (media.size.width - margin * 2)
        .clamp(0.0, media.size.width)
        .toDouble();
    return AnimatedPadding(
      duration: AppMotion.feedback(context),
      curve: AppMotion.enterCurve,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: margin, vertical: margin),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: maxHeight,
            ),
            child: PopScope(
              canPop: widget.dismissible,
              child: Shortcuts(
                shortcuts: const <ShortcutActivator, Intent>{
                  SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
                },
                child: Actions(
                  actions: <Type, Action<Intent>>{
                    DismissIntent: CallbackAction<DismissIntent>(
                      onInvoke: (_) {
                        _handleDismissIntent();
                        return null;
                      },
                    ),
                  },
                  child: FocusScope(
                    node: _focusScopeNode,
                    autofocus: true,
                    child: MediaQuery.removeViewInsets(
                      context: context,
                      removeBottom: true,
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
