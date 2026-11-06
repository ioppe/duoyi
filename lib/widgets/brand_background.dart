import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_brand.dart';
import '../core/i18n.dart';
import '../providers/theme_provider.dart';
import 'app_pull_to_sync.dart';
import 'surface_components.dart';

/// Wraps any child with the active theme's background image and overlay.
/// Default brand has no asset, so we just render the child on top of the
/// scaffold's normal background.
class BrandBackground extends StatelessWidget {
  final Widget child;
  final double? overlayOpacity;

  const BrandBackground({super.key, required this.child, this.overlayOpacity});

  @override
  Widget build(BuildContext context) {
    final brand = context.watch<ThemeProvider>().brand;
    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.sizeOf(context);
        final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
        final logicalWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : media.width;
        final logicalHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : media.height;
        final cacheWidth = (logicalWidth * dpr).ceil().clamp(1, 4096);
        final cacheHeight = (logicalHeight * dpr).ceil().clamp(1, 4096);
        return Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: brand.backgroundAsset != null
                  ? Image.asset(
                      brand.backgroundAsset!,
                      fit: BoxFit.cover,
                      cacheWidth: cacheWidth,
                      cacheHeight: cacheHeight,
                      filterQuality: FilterQuality.low,
                      gaplessPlayback: true,
                      errorBuilder: (context, error, stack) =>
                          Container(color: brand.backgroundOverlay),
                    )
                  : Container(color: brand.backgroundOverlay),
            ),
            RepaintBoundary(
              child: Container(
                color: brand.backgroundOverlay.withValues(
                  alpha: (overlayOpacity ?? brand.backgroundOverlayOpacity)
                      .clamp(0.0, 1.0),
                ),
              ),
            ),
            child,
          ],
        );
      },
    );
  }
}

/// Keeps route-pushed transparent pages from falling through to the Navigator's
/// black backing surface.
class BrandRouteSurface extends StatelessWidget {
  final Widget child;
  const BrandRouteSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // 路由页常以 `const BrandRouteSurface(child: XxxScreen())` 推入 Navigator：
    // 语言热切换时父级不下发新实例，子树不会重建。这里监听 I18n.localeListenable
    //（挂在 I18n 静态层，不依赖 Provider 作用域），并以 locale 作 KeyedSubtree
    // 键强制子树重新挂载，const 子页内的 I18n/品牌文案才能即时跟随新语言。
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final routeBackground = theme.brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        return Material(
          color: routeBackground,
          child: BrandBackground(
            child: AppSecondaryControlTheme(
              child: KeyedSubtree(
                key: ValueKey<AppLocale>(locale),
                child: AppPullToSync(child: child),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A scaffold that shows transparent surfaces on top of the brand background.
/// Use this in screens so they don't paint a solid scaffold color over the
/// brand image.
class BrandScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool extendBodyBehindAppBar;
  final bool paintBackground;

  const BrandScaffold({
    super.key,
    this.appBar,
    this.body,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.extendBodyBehindAppBar = false,
    this.paintBackground = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final routeBackground = theme.brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final scaffold = Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      appBar: appBar,
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
    );
    return ColoredBox(
      color: paintBackground ? routeBackground : Colors.transparent,
      child: paintBackground ? BrandBackground(child: scaffold) : scaffold,
    );
  }
}

/// 主题卡片的背景图缩略图（纯预览，不触发任何解锁/网络操作）。
///
/// 有 [AppBrand.backgroundAsset] 时渲染圆角裁剪的图片，加载失败或
/// 无图（默认主题）时回退到 [fallback]——复用 [BrandBackground] 的
/// errorBuilder 方案，缺图不会崩溃。
class BrandBackgroundThumbnail extends StatelessWidget {
  final AppBrand brand;
  final double size;
  final Widget fallback;

  const BrandBackgroundThumbnail({
    super.key,
    required this.brand,
    this.size = 52,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final asset = brand.backgroundAsset;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: brand.theme.colorScheme.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: asset == null
          ? fallback
          : Image.asset(
              asset,
              fit: BoxFit.cover,
              width: size,
              height: size,
              filterQuality: FilterQuality.low,
              gaplessPlayback: true,
              errorBuilder: (context, error, stack) => fallback,
            ),
    );
  }
}
