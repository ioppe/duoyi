package com.duoyi.duoyi

import android.content.Context
import android.content.SharedPreferences
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.os.Build
import android.util.Log
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import kotlin.math.roundToInt

data class DuoyiWidgetThemePalette(
    val brandId: String,
    val cardSkinId: String,
    val dark: Boolean,
    val primary: Int,
    val background: Int,
    val surface: Int,
    val navBackground: Int,
    val border: Int,
    val text: Int,
    val mutedText: Int,
    val onPrimary: Int,
    val accentStart: Int,
    val accentEnd: Int,
    val backgroundAssetKey: String,
    val cornerRadiusDp: Int,
    val controlRadiusDp: Int,
    val borderWidthDp: Int,
)

/**
 * 只读派生的 Apple 风色板：从用户已有主题 prefs 推导，绝不回写 prefs。
 *
 * - 浅色：雾白容器 F7F8FA / 白 surface / 主 label 1C1C1E / secondary 6E6E73 / 轨道 E9EBEF
 * - 深色：容器 1C1C1E / surface 2C2C2E / label F5F5F7 / secondary B1B1B7 / 轨道 303034
 * - accent 沿用主题 primary；深色在 primary 上混少量白提升对比。
 */
data class DuoyiApplePalette(
    val container: Int,
    val surface: Int,
    val label: Int,
    val secondary: Int,
    val track: Int,
    val selection: Int,
    val accent: Int,
    val dark: Boolean,
)

object DuoyiWidgetTheme {
    private const val defaultPrimary = "#FFFF6B6B"
    private const val defaultBackground = "#FFFFFFFF"
    private const val defaultSurface = "#FFFFFFFF"
    private const val defaultNavBackground = "#FFFFF6F2"
    private const val defaultBorder = "#22FF6B6B"
    private const val defaultText = "#FF333333"
    private const val defaultMutedText = "#FF666666"
    private const val defaultOnPrimary = "#FFFFFFFF"
    private const val defaultAccentStart = "#FFFF6B6B"
    private const val defaultAccentEnd = "#FFFFB088"
    // Apple 风派生的固定色板（只读，不写入 prefs）。
    private const val appleLightContainer = "#F7F8FA"
    private const val appleLightSurface = "#FFFFFF"
    private const val appleLightLabel = "#1C1C1E"
    private const val appleLightSecondary = "#6E6E73"
    private const val appleLightTrack = "#E9EBEF"
    private const val appleDarkContainer = "#1C1C1E"
    private const val appleDarkSurface = "#2C2C2E"
    private const val appleDarkLabel = "#F5F5F7"
    private const val appleDarkSecondary = "#B1B1B7"
    private const val appleDarkTrack = "#303034"
    private const val appleDarkSelection = "#48484D"
    /** 深色强调色：在主题 primary 上混 22% 白。 */
    private const val APPLE_DARK_ACCENT_WHITE = 0.22f
    /** 纯色 root 混入原色的比例：浅色 6%，深色 10%。 */
    private const val APPLE_LIGHT_ROOT_MIX = 0.06f
    private const val APPLE_DARK_ROOT_MIX = 0.10f
    /** 淡 accent CTA 背景透明度。 */
    private const val APPLE_CTA_ALPHA = 0.12f
    private const val maxBackgroundBitmapCacheEntries = 8
    private val backgroundBitmapCache =
        object : LinkedHashMap<BackgroundBitmapCacheKey, Bitmap>(
            maxBackgroundBitmapCacheEntries,
            0.75f,
            true,
        ) {
            override fun removeEldestEntry(
                eldest: MutableMap.MutableEntry<BackgroundBitmapCacheKey, Bitmap>?,
            ): Boolean = size > maxBackgroundBitmapCacheEntries
        }

    fun read(prefs: SharedPreferences): DuoyiWidgetThemePalette {
        return DuoyiWidgetThemePalette(
            brandId = prefs.getString("widget_theme_brand_id", "defaultBrand") ?: "defaultBrand",
            cardSkinId = prefs.getString("widget_theme_card_skin_id", "plain_card") ?: "plain_card",
            dark = prefs.getBoolean("widget_theme_dark", false),
            primary = readColor(prefs, "widget_theme_primary", defaultPrimary),
            background = readColor(prefs, "widget_theme_background", defaultBackground),
            surface = readColor(prefs, "widget_theme_surface", defaultSurface),
            navBackground = readColor(prefs, "widget_theme_nav_background", defaultNavBackground),
            border = readColor(prefs, "widget_theme_border", defaultBorder),
            text = readColor(prefs, "widget_theme_text", defaultText),
            mutedText = readColor(prefs, "widget_theme_muted_text", defaultMutedText),
            onPrimary = readColor(prefs, "widget_theme_on_primary", defaultOnPrimary),
            accentStart = readColor(prefs, "widget_theme_accent_start", defaultAccentStart),
            accentEnd = readColor(prefs, "widget_theme_accent_end", defaultAccentEnd),
            backgroundAssetKey = prefs.getString("widget_theme_background_asset_key", "") ?: "",
            cornerRadiusDp = readInt(prefs, "widget_theme_corner_radius_dp", 13),
            controlRadiusDp = readInt(prefs, "widget_theme_control_radius_dp", 8),
            borderWidthDp = readInt(prefs, "widget_theme_border_width_dp", 0),
        )
    }

    fun applyContainer(
        context: Context,
        views: RemoteViews,
        prefs: SharedPreferences,
        rootId: Int,
        navId: Int = 0,
        appWidgetId: Int? = null,
        appleStyle: Boolean = false,
    ) {
        val theme = read(prefs)
        if (appleStyle) {
            applyAppleContainer(
                context = context,
                views = views,
                prefs = prefs,
                theme = theme,
                rootId = rootId,
                navId = navId,
                appWidgetId = appWidgetId,
            )
            return
        }
        val imageResource = backgroundImageResource(theme.backgroundAssetKey)
        if (imageResource != 0) {
            applyImageBackedSurface(
                context = context,
                views,
                prefs = prefs,
                rootId = rootId,
                imageResource = imageResource,
                overlayColor = imageOverlayColor(theme),
                radiusDp = theme.cornerRadiusDp,
                appWidgetId = appWidgetId,
            )
        } else {
            views.setViewVisibility(R.id.widget_theme_background, View.GONE)
            views.setViewVisibility(R.id.widget_theme_overlay, View.GONE)
            applyRoundedSurface(
                views,
                rootId,
                fill = theme.background,
                stroke = theme.border,
                radiusDp = theme.cornerRadiusDp,
                strokeWidthDp = theme.borderWidthDp,
            )
        }
        if (navId != 0) {
            applyRoundedSurface(
                views,
                navId,
                fill = theme.navBackground,
                stroke = blend(theme.border, theme.navBackground, 0.45f),
                radiusDp = theme.controlRadiusDp,
                strokeWidthDp = if (theme.borderWidthDp > 0) 1 else 0,
            )
        }
    }

    /**
     * Apple 风外框：24dp 圆角、轻边界、无厚阴影。
     *
     * 纯色 root 用近乎不透明的 soft surface 混少量主题原色；深色按 theme.dark。
     * 主题图片背景继续复用已有的圆角裁切位图（radius=24），不新增模糊/动画。
     */
    private fun applyAppleContainer(
        context: Context,
        views: RemoteViews,
        prefs: SharedPreferences,
        theme: DuoyiWidgetThemePalette,
        rootId: Int,
        navId: Int,
        appWidgetId: Int?,
    ) {
        val palette = applePalette(theme)
        val imageResource = backgroundImageResource(theme.backgroundAssetKey)
        if (imageResource != 0) {
            applyImageBackedSurface(
                context = context,
                views = views,
                prefs = prefs,
                rootId = rootId,
                imageResource = imageResource,
                overlayColor = imageOverlayColor(theme),
                radiusDp = DuoyiWidgetLayout.APPLE_CORNER_RADIUS_DP,
                appWidgetId = appWidgetId,
            )
        } else {
            views.setViewVisibility(R.id.widget_theme_background, View.GONE)
            views.setViewVisibility(R.id.widget_theme_overlay, View.GONE)
            applyAppleSurface(
                views = views,
                viewId = rootId,
                fill = appleRootFill(palette),
                drawableResource = appleRootDrawable(theme.dark),
            )
        }
        if (navId != 0) {
            applyAppleSurface(
                views = views,
                viewId = navId,
                fill = palette.track,
                drawableResource = appleTrackDrawable(theme.dark),
            )
        }
    }

    private fun applyImageBackedSurface(
        context: Context,
        views: RemoteViews,
        prefs: SharedPreferences,
        rootId: Int,
        imageResource: Int,
        overlayColor: Int,
        radiusDp: Int,
        appWidgetId: Int?,
    ) {
        views.setInt(
            rootId,
            "setBackgroundResource",
            widgetBackgroundResource(radiusDp, 0),
        )
        val bitmap = roundedBackgroundBitmap(
            context = context,
            imageResource = imageResource,
            radiusDp = radiusDp,
            overlayColor = overlayColor,
            renderSpec = backgroundRenderSpec(prefs, appWidgetId),
        )
        if (bitmap == null) {
            views.setImageViewResource(R.id.widget_theme_background, imageResource)
            views.setInt(R.id.widget_theme_overlay, "setBackgroundColor", overlayColor)
            views.setViewVisibility(R.id.widget_theme_overlay, View.VISIBLE)
        } else {
            views.setImageViewBitmap(R.id.widget_theme_background, bitmap)
            views.setViewVisibility(R.id.widget_theme_overlay, View.GONE)
        }
        views.setViewVisibility(R.id.widget_theme_background, View.VISIBLE)
    }

    fun applyButtonSurfaces(
        views: RemoteViews,
        prefs: SharedPreferences,
        primaryIds: IntArray = intArrayOf(),
        secondaryIds: IntArray = intArrayOf(),
        appleStyle: Boolean = false,
    ) {
        val theme = read(prefs)
        val palette = if (appleStyle) applePalette(theme) else null
        if (palette != null) {
            primaryIds.forEach {
                applyAppleSurface(
                    views = views,
                    viewId = it,
                    fill = withAlpha(palette.accent, APPLE_CTA_ALPHA),
                    drawableResource = appleCtaDrawable(palette.dark),
                )
            }
            secondaryIds.forEach {
                applyAppleSurface(
                    views = views,
                    viewId = it,
                    fill = palette.track,
                    drawableResource = appleTrackDrawable(palette.dark),
                )
            }
            return
        }
        primaryIds.forEach {
            applyRoundedSurface(
                views,
                it,
                fill = theme.primary,
                stroke = theme.primary,
                radiusDp = theme.controlRadiusDp,
                strokeWidthDp = 0,
            )
        }
        secondaryIds.forEach {
            applyRoundedSurface(
                views,
                it,
                fill = theme.navBackground,
                stroke = blend(theme.border, theme.navBackground, 0.35f),
                radiusDp = theme.controlRadiusDp,
                strokeWidthDp = if (theme.borderWidthDp > 0) 1 else 0,
            )
        }
    }

    fun applyTextColors(
        views: RemoteViews,
        prefs: SharedPreferences,
        primaryIds: IntArray = intArrayOf(),
        bodyIds: IntArray = intArrayOf(),
        mutedIds: IntArray = intArrayOf(),
        onPrimaryIds: IntArray = intArrayOf(),
        appleStyle: Boolean = false,
    ) {
        val theme = read(prefs)
        if (appleStyle) {
            val palette = applePalette(theme)
            primaryIds.forEach { views.setTextColor(it, palette.accent) }
            bodyIds.forEach { views.setTextColor(it, palette.label) }
            mutedIds.forEach { views.setTextColor(it, palette.secondary) }
            onPrimaryIds.forEach { views.setTextColor(it, theme.onPrimary) }
            return
        }
        primaryIds.forEach { views.setTextColor(it, theme.primary) }
        bodyIds.forEach { views.setTextColor(it, theme.text) }
        mutedIds.forEach { views.setTextColor(it, theme.mutedText) }
        onPrimaryIds.forEach { views.setTextColor(it, theme.onPrimary) }
    }

    // ------------------------------------------------------------ Apple 风派生色板

    /** 只读派生：不做 blur / 动画 / bitmap 装饰，只换配色与圆角资源。 */
    fun applePalette(theme: DuoyiWidgetThemePalette): DuoyiApplePalette {
        // 深色把主题 primary 混少量白，提升在 1C1C1E 上的对比度。
        val accent = if (theme.dark) blend(Color.WHITE, theme.primary, APPLE_DARK_ACCENT_WHITE) else theme.primary
        return if (theme.dark) {
            DuoyiApplePalette(
                container = parseAppleColor(appleDarkContainer),
                surface = parseAppleColor(appleDarkSurface),
                label = parseAppleColor(appleDarkLabel),
                secondary = parseAppleColor(appleDarkSecondary),
                track = parseAppleColor(appleDarkTrack),
                selection = parseAppleColor(appleDarkSelection),
                accent = accent,
                dark = true,
            )
        } else {
            DuoyiApplePalette(
                container = parseAppleColor(appleLightContainer),
                surface = parseAppleColor(appleLightSurface),
                label = parseAppleColor(appleLightLabel),
                secondary = parseAppleColor(appleLightSecondary),
                track = parseAppleColor(appleLightTrack),
                selection = parseAppleColor(appleLightSurface),
                accent = accent,
                dark = false,
            )
        }
    }

    /** 供 provider 直接取派生色板；与 apply* 内部读到的 prefs 完全一致。 */
    fun applePaletteOf(prefs: SharedPreferences): DuoyiApplePalette = applePalette(read(prefs))

    /** 纯色 root：近乎不透明的 soft surface 混少量原色（深色按 theme.dark 有更强混合）。 */
    private fun appleRootFill(palette: DuoyiApplePalette): Int {
        val mix = if (palette.dark) APPLE_DARK_ROOT_MIX else APPLE_LIGHT_ROOT_MIX
        return blend(palette.accent, palette.container, mix)
    }

    /**
     * 底栏分段控件：选中 segment 用白/深灰小圆角，文字 accent；未选清背景 + secondary。
     *
     * 每次 reapply 都先清掉未选标签的背景，避免 RemoteViews 复用时残留上一次的
     * 选中色块。Android S+ 用 setBackgroundTintList 上色，pre-S 用静态 light/dark
     * 圆角 drawable 保持形状与对比（不用 setBackgroundColor 破坏圆角）。
     */
    @Suppress("UNUSED_PARAMETER")
    fun applySegmentedNavigation(
        context: Context,
        views: RemoteViews,
        prefs: SharedPreferences,
        tabViewIds: IntArray,
        selectedId: Int,
        profile: DuoyiWidgetProfile,
    ) {
        val palette = applePaletteOf(prefs)
        val labelSp = profile.navLabelSp
        val segmentDrawable = appleSegmentDrawable(palette.dark)
        tabViewIds.forEach { viewId ->
            views.setTextViewTextSize(viewId, TypedValue.COMPLEX_UNIT_SP, labelSp)
            if (viewId == selectedId) {
                applyAppleSurface(
                    views = views,
                    viewId = viewId,
                    fill = palette.selection,
                    drawableResource = segmentDrawable,
                )
                views.setTextColor(viewId, palette.accent)
            } else {
                views.setInt(viewId, "setBackgroundResource", 0)
                views.setTextColor(viewId, palette.secondary)
            }
        }
    }

    private fun applyAppleSurface(
        views: RemoteViews,
        viewId: Int,
        fill: Int,
        drawableResource: Int,
    ) {
        views.setInt(viewId, "setBackgroundResource", drawableResource)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            views.setColorStateList(
                viewId,
                "setBackgroundTintList",
                ColorStateList.valueOf(fill),
            )
        }
    }

    private fun appleRootDrawable(dark: Boolean): Int =
        if (dark) R.drawable.widget_apple_bg_dark else R.drawable.widget_apple_bg_light

    private fun appleTrackDrawable(dark: Boolean): Int =
        if (dark) R.drawable.widget_apple_track_dark else R.drawable.widget_apple_track_light

    private fun appleSegmentDrawable(dark: Boolean): Int =
        if (dark) R.drawable.widget_apple_segment_dark else R.drawable.widget_apple_segment_light

    private fun appleCtaDrawable(dark: Boolean): Int =
        if (dark) R.drawable.widget_apple_cta_dark else R.drawable.widget_apple_cta_light

    private fun parseAppleColor(hex: String): Int = Color.parseColor(hex)

    private fun withAlpha(color: Int, alpha: Float): Int =
        Color.argb(
            (alpha.coerceIn(0f, 1f) * 255f).roundToInt(),
            Color.red(color),
            Color.green(color),
            Color.blue(color),
        )

    private fun readColor(
        prefs: SharedPreferences,
        key: String,
        fallback: String,
    ): Int {
        val raw = prefs.getString(key, null)?.trim()
        return try {
            Color.parseColor(if (raw.isNullOrEmpty()) fallback else raw)
        } catch (_: IllegalArgumentException) {
            Color.parseColor(fallback)
        }
    }

    private fun readInt(prefs: SharedPreferences, key: String, fallback: Int): Int {
        return try {
            prefs.getInt(key, fallback)
        } catch (_: ClassCastException) {
            prefs.getString(key, null)?.toIntOrNull() ?: fallback
        }
    }

    private fun applyRoundedSurface(
        views: RemoteViews,
        viewId: Int,
        fill: Int,
        stroke: Int,
        radiusDp: Int,
        strokeWidthDp: Int,
    ) {
        views.setInt(
            viewId,
            "setBackgroundResource",
            widgetBackgroundResource(radiusDp, strokeWidthDp),
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            views.setColorStateList(viewId, "setBackgroundTintList", ColorStateList.valueOf(fill))
        } else {
            // RemoteViews on pre-S cannot tint a drawable reliably. Keeping the rounded
            // drawable is preferable to replacing it with a square setBackgroundColor.
            Log.d(
                "DuoyiWidgetTheme",
                "pre-S rounded widget surface uses bundled rounded drawable without runtime tint",
            )
        }
    }

    private fun widgetBackgroundResource(radiusDp: Int, strokeWidthDp: Int): Int {
        // 24dp 的 Apple 外框必须真正返回新资源，不能被 >=16 分支映射回 16dp。
        if (radiusDp >= DuoyiWidgetLayout.APPLE_CORNER_RADIUS_DP) {
            return R.drawable.widget_apple_bg_light
        }
        if (radiusDp >= 16) return R.drawable.widget_bg_round_16
        if (radiusDp >= 15) return R.drawable.widget_bg_round_15
        if (radiusDp >= 14) return R.drawable.widget_bg_round_14
        if (strokeWidthDp <= 0) return R.drawable.widget_bg_plain
        return R.drawable.widget_bg
    }

    private fun roundedBackgroundBitmap(
        context: Context,
        imageResource: Int,
        radiusDp: Int,
        overlayColor: Int,
        renderSpec: BackgroundRenderSpec,
    ): Bitmap? {
        val key = BackgroundBitmapCacheKey(
            imageResource = imageResource,
            radiusDp = radiusDp,
            overlayColor = overlayColor,
            renderSpec = renderSpec,
        )
        synchronized(backgroundBitmapCache) {
            val cached = backgroundBitmapCache[key]
            if (cached != null && !cached.isRecycled) return cached
        }
        val output = renderRoundedBackgroundBitmap(
            context = context,
            imageResource = imageResource,
            radiusDp = radiusDp,
            overlayColor = overlayColor,
            renderSpec = renderSpec,
        ) ?: return null
        synchronized(backgroundBitmapCache) {
            backgroundBitmapCache[key] = output
        }
        return output
    }

    private fun renderRoundedBackgroundBitmap(
        context: Context,
        imageResource: Int,
        radiusDp: Int,
        overlayColor: Int,
        renderSpec: BackgroundRenderSpec,
    ): Bitmap? {
        val source = BitmapFactory.decodeResource(context.resources, imageResource) ?: return null
        return try {
            val width = renderSpec.bitmapWidth
            val height = renderSpec.bitmapHeight
            val output = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(output)
            val bounds = RectF(0f, 0f, width.toFloat(), height.toFloat())
            val radius = (radiusDp * renderSpec.radiusScale).toFloat()
            val path = Path().apply {
                addRoundRect(bounds, radius, radius, Path.Direction.CW)
            }
            val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.DITHER_FLAG or Paint.FILTER_BITMAP_FLAG)
            canvas.clipPath(path)
            canvas.drawBitmap(source, centerCropRect(source, width, height), bounds, paint)
            paint.color = overlayColor
            paint.style = Paint.Style.FILL
            canvas.drawRect(bounds, paint)
            output
        } finally {
            source.recycle()
        }
    }

    private fun centerCropRect(source: Bitmap, targetWidth: Int, targetHeight: Int): Rect {
        val sourceAspect = source.width.toFloat() / source.height.toFloat()
        val targetAspect = targetWidth.toFloat() / targetHeight.toFloat()
        return if (sourceAspect > targetAspect) {
            val cropWidth = (source.height * targetAspect).roundToInt().coerceAtMost(source.width)
            val left = ((source.width - cropWidth) / 2).coerceAtLeast(0)
            Rect(left, 0, left + cropWidth, source.height)
        } else {
            val cropHeight = (source.width / targetAspect).roundToInt().coerceAtMost(source.height)
            val top = ((source.height - cropHeight) / 2).coerceAtLeast(0)
            Rect(0, top, source.width, top + cropHeight)
        }
    }

    private fun backgroundRenderSpec(
        prefs: SharedPreferences,
        appWidgetId: Int?,
    ): BackgroundRenderSpec {
        return when {
            DuoyiWidgetDisplayMode.isCompact(prefs, appWidgetId) -> BackgroundRenderSpec(
                bitmapWidth = 240,
                bitmapHeight = 240,
                logicalWidthDp = 110,
                logicalHeightDp = 110,
            )
            DuoyiWidgetDisplayMode.isDetailed(prefs, appWidgetId) -> BackgroundRenderSpec(
                bitmapWidth = 400,
                bitmapHeight = 288,
                logicalWidthDp = 250,
                logicalHeightDp = 180,
            )
            else -> BackgroundRenderSpec(
                bitmapWidth = 360,
                bitmapHeight = 220,
                logicalWidthDp = 180,
                logicalHeightDp = 110,
            )
        }
    }

    private data class BackgroundRenderSpec(
        val bitmapWidth: Int,
        val bitmapHeight: Int,
        val logicalWidthDp: Int,
        val logicalHeightDp: Int,
    ) {
        val radiusScale: Float
            get() = minOf(
                bitmapWidth.toFloat() / logicalWidthDp.toFloat(),
                bitmapHeight.toFloat() / logicalHeightDp.toFloat(),
            )
    }

    private data class BackgroundBitmapCacheKey(
        val imageResource: Int,
        val radiusDp: Int,
        val overlayColor: Int,
        val renderSpec: BackgroundRenderSpec,
    )

    private fun backgroundImageResource(key: String): Int {
        return when (key.trim().lowercase()) {
            "re0",
            "assets/backgrounds/re0.png" -> R.drawable.widget_theme_re0
            "genshin",
            "assets/backgrounds/genshin.png" -> R.drawable.widget_theme_genshin
            "starrail",
            "star_rail",
            "assets/backgrounds/star_rail.png" -> R.drawable.widget_theme_star_rail
            "wuthering",
            "wutheringwaves",
            "assets/backgrounds/wuthering.png" -> R.drawable.widget_theme_wuthering
            "zzz",
            "assets/backgrounds/zzz.png" -> R.drawable.widget_theme_zzz
            "yanyun",
            "assets/backgrounds/yanyun.png" -> R.drawable.widget_theme_yanyun
            "botw",
            "assets/backgrounds/botw.png" -> R.drawable.widget_theme_botw
            else -> 0
        }
    }

    private fun imageOverlayColor(theme: DuoyiWidgetThemePalette): Int {
        return if (theme.dark) {
            Color.argb(92, 0, 0, 0)
        } else {
            Color.argb(78, 255, 255, 255)
        }
    }

    private fun blend(foreground: Int, background: Int, alpha: Float): Int {
        val a = alpha.coerceIn(0f, 1f)
        val inv = 1f - a
        return Color.argb(
            255,
            (Color.red(foreground) * a + Color.red(background) * inv).toInt(),
            (Color.green(foreground) * a + Color.green(background) * inv).toInt(),
            (Color.blue(foreground) * a + Color.blue(background) * inv).toInt(),
        )
    }
}
