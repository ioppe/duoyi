package com.duoyi.duoyi

import android.app.AppOpsManager
import android.app.KeyguardManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.os.Process

/**
 * 已授权“使用情况访问”时的前台补漏读取（窄接口）。
 *
 * 只读 `UsageEvents` 的 **type / packageName / timeStamp**：不读 text、className、窗口或
 * 节点内容，不授予任何权限、不写系统设置、不使用 wakelock/前台服务，也不拿
 * `queryUsageStats.lastTimeUsed` 去猜前台。未授权、息屏/锁屏或读取异常一律返回“无新证据”。
 */
object FocusBlockerUsageAccess {
    /** 只回看最近 5s，避免把很久以前的前台当成现在。 */
    const val defaultLookbackMillis = 5_000L

    /** 单次查询最多消费的事件数，避免异常数据拖慢 worker。 */
    private const val maxEventsPerQuery = 256

    // UsageEvents.Event 的公开数值：MOVE_TO_FOREGROUND == ACTIVITY_RESUMED == 1，
    // MOVE_TO_BACKGROUND == ACTIVITY_PAUSED == 2，ACTIVITY_STOPPED == 23。
    // 这里用 min-SDK 安全的名字/常量，不依赖 API 29 才新增的别名。
    private const val eventTypeResumed = UsageEvents.Event.MOVE_TO_FOREGROUND
    private const val eventTypePaused = UsageEvents.Event.MOVE_TO_BACKGROUND
    private const val eventTypeStopped = 23

    /**
     * 是否已授予“使用情况访问”。
     *
     * 复用 min 21 兼容的 AppOps 只读检查（Q 及以上用 unsafeCheckOpNoThrow）。
     */
    fun hasUsageAccess(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return false
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager
            ?: return false
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName,
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName,
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /** 设备是否可交互：息屏或锁屏时既不查询也不拉起。 */
    fun isDeviceAwakeAndUnlocked(context: Context): Boolean {
        val power = context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return false
        if (!power.isInteractive) return false
        val keyguard = context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            ?: return true
        return !keyguard.isKeyguardLocked
    }

    /**
     * 读取最近的元数据事件（调用方保证在工作线程上调用）。
     *
     * 未授权 / 设备不可交互 / 窗口非法 / 读取异常一律返回空列表，调用方因此只得到
     * “无新证据”，不会据此猜前台。
     */
    fun readRecentEvents(
        context: Context,
        sessionStartedAtWallMillis: Long,
        nowWallMillis: Long,
        lookbackMillis: Long = defaultLookbackMillis,
    ): List<FocusBlockerUsageObservation> {
        if (!isDeviceAwakeAndUnlocked(context)) return emptyList()
        if (!hasUsageAccess(context)) return emptyList()
        if (nowWallMillis <= 0L) return emptyList()
        val manager = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
            ?: return emptyList()
        val beginWall = maxOf(sessionStartedAtWallMillis, nowWallMillis - lookbackMillis)
        if (beginWall >= nowWallMillis) return emptyList()
        return runCatching { collectRecentEvents(manager, beginWall, nowWallMillis) }
            .getOrElse { emptyList() }
    }

    /** 只遍历 type/package/timeStamp，忽略其余字段与无关事件类型。 */
    private fun collectRecentEvents(
        manager: UsageStatsManager,
        beginWallMillis: Long,
        endWallMillis: Long,
    ): List<FocusBlockerUsageObservation> {
        val events = manager.queryEvents(beginWallMillis, endWallMillis) ?: return emptyList()
        val event = UsageEvents.Event()
        val observations = ArrayList<FocusBlockerUsageObservation>()
        var scanned = 0
        while (scanned < maxEventsPerQuery && events.hasNextEvent()) {
            if (!events.getNextEvent(event)) break
            scanned += 1
            val kind = when (event.eventType) {
                eventTypeResumed -> FocusBlockerUsageKind.RESUMED
                eventTypePaused -> FocusBlockerUsageKind.PAUSED
                eventTypeStopped -> FocusBlockerUsageKind.STOPPED
                else -> continue
            }
            val packageName = event.packageName ?: continue
            observations.add(
                FocusBlockerUsageObservation(
                    packageName = packageName,
                    eventAtWallMillis = event.timeStamp,
                    kind = kind,
                ),
            )
        }
        // 批次不完整时不能用前半段猜前台：后面的事件可能已经切到 QQ/微信。
        if (events.hasNextEvent()) return emptyList()
        return observations
    }
}
