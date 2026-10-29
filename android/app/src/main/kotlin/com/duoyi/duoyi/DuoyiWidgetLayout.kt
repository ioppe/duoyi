package com.duoyi.duoyi

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.res.Configuration
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.text.StaticLayout
import android.text.TextPaint
import android.util.SizeF
import android.widget.RemoteViews
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * 核心 4 组件（待办 / 习惯 / 日历 / 专注）的只读几何预算。
 *
 * 背景：3x2 实例高度随启动器网格变化，旧 XML 把内容区写成 `0dp + weight=1`，
 * 被 header(24) / 主按钮(32) / 摘要行 / nav(30) / padding(24) 挤压后，统计的
 * 单位行、星期行被裁掉。这里把"实际可用高度"算成 dp，交给 provider 用整行
 * 预算决定显示多少内容，再由 RemoteViews 渲染完整行，而不是让 TextView 去裁。
 *
 * 尺寸取向（按当前方向成对取值，修正竖屏误用横屏高度）：
 * - `MIN_WIDTH` 是竖屏宽度、`MAX_WIDTH` 是横屏宽度；`MAX_HEIGHT` 是竖屏高度、
 *   `MIN_HEIGHT` 是横屏高度。所以按 `resources.configuration.orientation` 配对：
 *   竖屏 = (MIN_WIDTH, MAX_HEIGHT)，横屏 = (MAX_WIDTH, MIN_HEIGHT)。
 *   两个方向的值绝不混进同一根轴的候选列表——旧实现每轴取最小值，会让竖屏 3x2
 *   按横屏高度预算，只剩数字/单位/底栏、中间大片空白。
 * - 仅当某轴主 key 非正时才退回该轴另一个 key；仍缺失才用 API 31
 *   `OPTION_APPWIDGET_SIZES` 的有效正数候选兜底（只补缺轴）；最后回落 180x110。
 * - `OPTION_APPWIDGET_SIZES` 是当前宿主可能的多方向尺寸，不是所有 resize 档位，
 *   因此不参与常规预算，只做缺失轴兜底。
 * - 字体用系统真实 fontScale，不强制 1.0；用 StaticLayout 测量包含中文回退字体的
 *   完整行高，关闭字体外边距，与 XML 的 includeFontPadding=false 一致。
 *
 * 只读：不读写 SharedPreferences，不做迁移，不改变主题 / 展示模式 / 导航语义。
 */
object DuoyiWidgetLayout {
    /** 标准 3x2 资源声明，没有任何有效选项时的回落值。 */
    const val FALLBACK_WIDTH_DP = 180f
    const val FALLBACK_HEIGHT_DP = 110f
    /** 大尺寸卡片内边距；高度/字体紧张时降到 COMPACT_PADDING_DP。 */
    const val PADDING_DP = 8f
    const val COMPACT_PADDING_DP = 6f
    /** 低于该高度或超过该 fontScale 视为紧凑，使用较小内边距/字号档位。 */
    const val TIGHT_HEIGHT_DP = 130f
    const val TIGHT_FONT_SCALE = 1.2f
    const val NARROW_WIDTH_DP = 200f
    /** 底部四项导航：可点的最小高度，文字仍按字体度量自适应。 */
    const val NAV_MIN_HEIGHT_DP = 28f
    /** 底栏标签上下各 2dp 内边距，navDp 必须把它算进整行预算。 */
    const val NAV_LABEL_PADDING_DP = 2f
    const val NAV_LABEL_SP = 10f
    /** 内容区与底栏之间的统一上边距（XML marginTop=6dp）。 */
    const val NAV_MARGIN_DP = 6f
    /** 品牌 logo 的紧凑高度（只改 XML 尺寸，不改资源图）。 */
    const val HEADER_LOGO_DP = 18f
    /** 核心 4 组件的模块名：13sp 中强字重，取代旧的品牌 TextView（仍 GONE）。 */
    const val MODULE_TITLE_SP = 13f
    /** Apple 风外框：24dp 圆角、无厚阴影。 */
    const val APPLE_CORNER_RADIUS_DP = 24
    /** 4 核心组件常规内边距 14dp；短实例/大字体降到 10dp，更挤时 8dp。 */
    const val APPLE_PADDING_DP = 14f
    const val APPLE_COMPACT_PADDING_DP = 10f
    const val APPLE_TIGHT_PADDING_DP = 8f
    /** 日历信息密度最高，内边距上限 12dp，紧凑时 8dp。 */
    const val CALENDAR_PADDING_DP = 12f
    const val CALENDAR_COMPACT_PADDING_DP = 8f
    /** 整行预算的舍入容差，避免实测误差把刚好放得下的一行判掉。 */
    const val EPSILON_DP = 0.5f
    private const val FALLBACK_LINE_RATIO = 1.17f

    fun resolve(
        context: Context,
        manager: AppWidgetManager,
        appWidgetId: Int,
    ): DuoyiWidgetProfile {
        val options = if (appWidgetId > 0) {
            runCatching { manager.getAppWidgetOptions(appWidgetId) }.getOrNull()
        } else {
            null
        }
        if (options == null) {
            return profileOf(context, FALLBACK_WIDTH_DP, FALLBACK_HEIGHT_DP)
        }
        val landscape = context.resources.configuration.orientation ==
            Configuration.ORIENTATION_LANDSCAPE
        val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        val maxWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 0)
        val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
        val maxHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
        // 同一方向成对取值：竖屏 (MIN_WIDTH, MAX_HEIGHT)，横屏 (MAX_WIDTH, MIN_HEIGHT)。
        // 两个方向的值绝不混进同一根轴，否则竖屏会按横屏高度预算而失去内容。
        var width = if (landscape) {
            positiveOr(maxWidth, minWidth)
        } else {
            positiveOr(minWidth, maxWidth)
        }
        var height = if (landscape) {
            positiveOr(minHeight, maxHeight)
        } else {
            positiveOr(maxHeight, minHeight)
        }
        // 只有缺轴时才用 API 31 sizes 兜底（sizes 是宿主多方向尺寸，非全部 resize 档位）。
        if (width <= 0f || height <= 0f) {
            val sizes = sizesBounds(options)
            if (width <= 0f) width = sizes.first
            if (height <= 0f) height = sizes.second
        }
        return profileOf(
            context,
            if (width > 0f) width else FALLBACK_WIDTH_DP,
            if (height > 0f) height else FALLBACK_HEIGHT_DP,
        )
    }

    /** 缺失轴的兜底：取 API 31 sizes 中该轴最小的有效正数。 */
    private fun sizesBounds(options: Bundle): Pair<Float, Float> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return 0f to 0f
        val sizes = options.getParcelableArrayList<SizeF>(
            AppWidgetManager.OPTION_APPWIDGET_SIZES
        ) ?: return 0f to 0f
        var width = 0f
        var height = 0f
        sizes.forEach { size ->
            if (size == null) return@forEach
            val candidateWidth = size.width.roundToInt().toFloat()
            val candidateHeight = size.height.roundToInt().toFloat()
            if (candidateWidth > 0f && (width == 0f || candidateWidth < width)) {
                width = candidateWidth
            }
            if (candidateHeight > 0f && (height == 0f || candidateHeight < height)) {
                height = candidateHeight
            }
        }
        return width to height
    }

    /**
     * 生成同时携带横屏 / 竖屏两套 RemoteViews 的容器（构造参数顺序 landscape, portrait）。
     *
     * 宿主旋转后会直接选用对应方向的那一套，不会继续用旋转前的预算绘制；全程只读，
     * 不写偏好、不注册 receiver / 权限、不新增 IPC，也不会触发 App 启动。
     * [render] 收到的 Context 只改过 orientation，因此 resolve / 主题 / 底栏 /
     * PendingIntent 全部基于同一方向配置生成。
     */
    fun forOrientations(context: Context, render: (Context) -> RemoteViews): RemoteViews {
        val base = context.resources.configuration
        val landscapeContext = context.createConfigurationContext(
            Configuration(base).apply { orientation = Configuration.ORIENTATION_LANDSCAPE }
        )
        val portraitContext = context.createConfigurationContext(
            Configuration(base).apply { orientation = Configuration.ORIENTATION_PORTRAIT }
        )
        return RemoteViews(render(landscapeContext), render(portraitContext))
    }

    /** 纯几何入口：便于父级在无 AppWidgetManager 的场景（含边界用例）复用。 */
    fun profileOf(context: Context, widthDp: Float, heightDp: Float): DuoyiWidgetProfile {
        val rawFontScale = context.resources.configuration?.fontScale ?: 1f
        val fontScale = if (rawFontScale.isFinite() && rawFontScale > 0f) rawFontScale else 1f
        val rawDensity = context.resources.displayMetrics?.density ?: 1f
        val density = if (rawDensity.isFinite() && rawDensity > 0f) rawDensity else 1f
        val safeWidth = if (widthDp.isFinite() && widthDp > 0f) widthDp else FALLBACK_WIDTH_DP
        val safeHeight = if (heightDp.isFinite() && heightDp > 0f) heightDp else FALLBACK_HEIGHT_DP
        return DuoyiWidgetProfile(safeWidth, safeHeight, fontScale, density)
    }

    /** 主 key 非正时退回该轴另一个 key；都非正返回 0，交给后续兜底。 */
    private fun positiveOr(primary: Int, secondary: Int): Float = when {
        primary > 0 -> primary.toFloat()
        secondary > 0 -> secondary.toFloat()
        else -> 0f
    }

    internal fun fallbackLineDp(sp: Float, fontScale: Float): Float =
        sp * fontScale * FALLBACK_LINE_RATIO
}

/**
 * 单个实例的只读几何档案。字段全部来自 AppWidgetManager 选项 + 系统资源配置，
 * 不含偏好，可安全地在每次 onUpdate 重新计算。
 */
class DuoyiWidgetProfile(
    val widthDp: Float,
    val heightDp: Float,
    val fontScale: Float,
    private val density: Float,
    /** 只读的内边距覆盖（不改变 host 尺寸/缩放/密度），null 表示沿用旧皮肤档位。 */
    private val paddingOverrideDp: Float? = null,
) {
    private val lineCache = HashMap<Float, Float>()
    private val paint = TextPaint()

    val isNarrow: Boolean get() = widthDp < DuoyiWidgetLayout.NARROW_WIDTH_DP
    val isShort: Boolean get() = heightDp < DuoyiWidgetLayout.TIGHT_HEIGHT_DP

    val paddingDp: Float
        get() = paddingOverrideDp ?: if (isShort || fontScale > DuoyiWidgetLayout.TIGHT_FONT_SCALE) {
            DuoyiWidgetLayout.COMPACT_PADDING_DP
        } else {
            DuoyiWidgetLayout.PADDING_DP
        }

    /** 4 核心组件的 Apple 风内边距：14dp，短实例/大字体 10dp，更挤 8dp。 */
    val applePaddingDp: Float
        get() = when {
            fontScale > DuoyiWidgetLayout.TIGHT_FONT_SCALE * 1.15f ->
                DuoyiWidgetLayout.APPLE_TIGHT_PADDING_DP
            isShort || fontScale > DuoyiWidgetLayout.TIGHT_FONT_SCALE ->
                DuoyiWidgetLayout.APPLE_COMPACT_PADDING_DP
            else -> DuoyiWidgetLayout.APPLE_PADDING_DP
        }

    /** 日历内边距上限 12dp（紧凑 8dp），日期格优先。 */
    val calendarPaddingDp: Float
        get() = if (isShort || fontScale > DuoyiWidgetLayout.TIGHT_FONT_SCALE) {
            DuoyiWidgetLayout.CALENDAR_COMPACT_PADDING_DP
        } else {
            DuoyiWidgetLayout.CALENDAR_PADDING_DP
        }

    /** 底栏标签字号；短实例微降，navDp 与它保持同一预算。 */
    val navLabelSp: Float
        get() = if (isShort) 9.5f else DuoyiWidgetLayout.NAV_LABEL_SP

    /** 只读派生：同 wide/height/fontScale/density，仅换内边距。 */
    fun withPadding(dp: Float): DuoyiWidgetProfile =
        DuoyiWidgetProfile(widthDp, heightDp, fontScale, density, dp.coerceAtLeast(0f))

    val contentHeightDp: Float get() = (heightDp - 2f * paddingDp).coerceAtLeast(0f)
    val contentWidthDp: Float get() = (widthDp - 2f * paddingDp).coerceAtLeast(0f)

    fun px(dp: Float): Int = (dp * density).roundToInt()

    /** 用实际中英文排版测量行高，包含系统 CJK 回退字体，匹配无字体外边距的 TextView。 */
    fun lineDp(sp: Float): Float {
        if (sp <= 0f) return 0f
        lineCache[sp]?.let { return it }
        paint.typeface = Typeface.DEFAULT
        paint.textSize = sp * fontScale * density
        val sample = "多仪 Ag0"
        val builder = StaticLayout.Builder.obtain(sample, 0, sample.length, paint, 100000)
            .setIncludePad(false)
            .setMaxLines(1)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            builder.setUseLineSpacingFromFallbacks(true)
        }
        val linePx = builder.build().height.toFloat()
        val value = if (linePx > 0f && linePx.isFinite()) {
            linePx / density
        } else {
            DuoyiWidgetLayout.fallbackLineDp(sp, fontScale)
        }
        lineCache[sp] = value
        return value
    }

    /** 实测文字宽度（dp）：日历据此判断一行 7 天是否整行放得下。 */
    fun textWidthDp(text: String, sp: Float, monospace: Boolean = false): Float {
        if (text.isEmpty() || sp <= 0f) return 0f
        paint.typeface = if (monospace) Typeface.MONOSPACE else Typeface.DEFAULT
        paint.textSize = sp * fontScale * density
        val widthPx = paint.measureText(text)
        return if (widthPx > 0f && widthPx.isFinite()) widthPx / density else 0f
    }

    /** 顶栏高度：logo 固定高度与文字行高中的较大者。 */
    fun headerDp(textSp: Float): Float = max(DuoyiWidgetLayout.HEADER_LOGO_DP, lineDp(textSp))

    /** 底部四项导航高度：最小可点高度与\"文字行高 + 标签上下 2dp\"中的较大者。 */
    fun navDp(textSp: Float = DuoyiWidgetLayout.NAV_LABEL_SP): Float = max(
        DuoyiWidgetLayout.NAV_MIN_HEIGHT_DP,
        lineDp(textSp) + 2f * DuoyiWidgetLayout.NAV_LABEL_PADDING_DP,
    )

    fun budget(fixedDp: Float): DuoyiWidgetBudget = DuoyiWidgetBudget(contentHeightDp - fixedDp)
}

/**
 * 整行预算账本：只有"整行"放得下才扣减，保证渲染内容永远不超出可用高度，
 * 也不会为 GONE 的控件预留空隙。
 */
class DuoyiWidgetBudget(availableDp: Float) {
    var remainingDp: Float = if (availableDp.isFinite()) availableDp.coerceAtLeast(0f) else 0f
        private set

    fun fits(dp: Float): Boolean = dp <= remainingDp + DuoyiWidgetLayout.EPSILON_DP

    /** 放得下才占用并返回 true；放不下不扣减，调用方应隐藏该块。 */
    fun reserve(dp: Float): Boolean {
        if (!fits(dp)) return false
        remainingDp = (remainingDp - dp).coerceAtLeast(0f)
        return true
    }
}
