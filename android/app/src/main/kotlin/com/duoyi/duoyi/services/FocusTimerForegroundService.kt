package com.duoyi.duoyi.services

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import com.duoyi.duoyi.MainActivity
import com.duoyi.duoyi.R

/**
 * 专注计时持续通知（独立前台服务，`specialUse` 类型）。
 *
 * 职责边界：
 * - 只服务番茄钟通知：不写入普通提醒历史、不复用 `local_notifications` 渠道，
 *   因此不与提醒的渠道和历史共用，也不依赖音频播放。
 * - 正文时间由本服务每秒按 `SystemClock.elapsedRealtime` 推进（倒计时与正计时都
 *   一样），不依赖 Dart 秒级 timer；系统 chronometer/进度条仍作为附加展示。
 * - 到期时刻只由首次同步的 canonical 锚点决定，秒级 `notify` 与主题/语言重推
 *   都不会延长它。
 * - 通知按钮是标准 `NotificationCompat` actions，点击直接回到本包 `MainActivity`
 *   的 `duoyi://focus-timer/...` 深链，再交给既有 `duoyi/deep_links` 统一分发。
 * - 通知权限被拒、前台服务启动被拒（Android 12+ 后台限制）都只记录日志，
 *   绝不反向打断计时。
 */
class FocusTimerForegroundService : Service() {

    private val handler = Handler(Looper.getMainLooper())
    private var expiryRunnable: Runnable? = null
    private var tickRunnable: Runnable? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            actionStop -> {
                stopEverything()
                return START_NOT_STICKY
            }
        }
        val payload = payloadFrom(intent)
        val model = FocusTimerNotificationModel.fromMap(payload)
        if (model == null) {
            Log.w(tag, "focus timer sync without usable payload; stopping notification")
            stopEverything()
            return START_NOT_STICKY
        }
        // 按 canonical 锚点折算“此刻”，之后只用单调时钟推进。
        val nowWallClock = System.currentTimeMillis()
        val base = model.rebasedAt(nowWallClock)
        if (!base.paused && !base.isCountUp && base.remainingMillis <= 0L) {
            // Dart 已经走到 0（即将结算）：不展示 00:00 的僵尸通知，也不伪造到期回调。
            Log.i(tag, "focus timer synced at zero; clearing notification")
            stopEverything()
            return START_NOT_STICKY
        }
        val notification = buildNotification(base)
        val started = startForegroundSafely(notification)
        if (!started) {
            // 通知不可用时不留下后台服务；计时本身仍在 Dart 侧继续。
            stopEverything()
            return START_NOT_STICKY
        }
        scheduleExpiry(base, nowWallClock)
        scheduleTicker(base, SystemClock.elapsedRealtime())
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        cancelExpiry()
        cancelTicker()
        // 无论走 stopEverything 还是外部 stopService，都保证通知被移除。
        runCatching {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.cancel(notificationId)
        }.onFailure { error -> Log.w(tag, "focus timer notification cleanup failed", error) }
        super.onDestroy()
    }

    private fun startForegroundSafely(notification: Notification): Boolean {
        return runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    notificationId,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                )
            } else {
                startForeground(notificationId, notification)
            }
            true
        }.getOrElse { error ->
            Log.w(tag, "focus timer foreground start failed", error)
            false
        }
    }

    private fun buildNotification(model: FocusTimerNotificationModel): Notification {
        ensureChannel(model.channelName)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val openIntent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .setData(Uri.parse(model.returnUri))
        val contentIntent = PendingIntent.getActivity(this, notificationId, openIntent, flags)
        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.drawable.ic_stat_duoyi)
            .setContentTitle(model.title)
            // 折叠态优先显示这一行：以本地化“剩余/已计时 + 时间”开头。
            .setContentText(model.contentText)
            .setStyle(NotificationCompat.BigTextStyle().bigText(model.detailText))
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(model.usesChronometer)
            .setCategory(NotificationCompat.CATEGORY_STOPWATCH)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
        if (model.accentColorArgb != 0) {
            // 主题主色由 Dart 注入；NotificationCompat 无 color getter，必须用 setter 方法。
            builder.setColor(model.accentColorArgb)
        }
        if (model.usesChronometer) {
            builder
                .setWhen(model.notificationWhen(System.currentTimeMillis()))
                .setUsesChronometer(true)
                .setChronometerCountDown(model.chronometerCountDown)
        }
        if (model.showsProgress) {
            builder.setProgress(progressMax, model.progressPermille, false)
        } else {
            builder.setProgress(0, 0, false)
        }
        addControlActions(builder, model)
        return builder.build()
    }

    /**
     * 运行态=暂停/重置，暂停态=开始/重置。每个动作都用独立的 requestCode 与 data URI，
     * 避免 `FLAG_UPDATE_CURRENT` 被别的动作覆盖；没有有效绑定时不添加任何按钮。
     */
    private fun addControlActions(
        builder: NotificationCompat.Builder,
        model: FocusTimerNotificationModel,
    ) {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        for (action in model.controlActions) {
            val label = model.actionLabel(action)
            if (label.isEmpty()) continue
            val intent = Intent(this, MainActivity::class.java)
                .setAction(Intent.ACTION_VIEW)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .setData(Uri.parse(model.controlUri(action)))
            val pending = PendingIntent.getActivity(
                this,
                actionRequestCode(action),
                intent,
                flags,
            )
            builder.addAction(actionIcon(action), label, pending)
        }
    }

    private fun actionRequestCode(action: FocusTimerControlAction): Int =
        notificationId + actionRequestCodeOffset + action.ordinal

    private fun actionIcon(action: FocusTimerControlAction): Int = when (action) {
        FocusTimerControlAction.start -> android.R.drawable.ic_media_play
        FocusTimerControlAction.pause -> android.R.drawable.ic_media_pause
        FocusTimerControlAction.reset -> android.R.drawable.ic_menu_close_clear_cancel
    }

    private fun ensureChannel(channelName: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val name = channelName.ifEmpty { defaultChannelName }
        val channel = NotificationChannel(
            channelId,
            name,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = name
            setSound(null, null)
            enableVibration(false)
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    /** 到期只由首次同步的锚点决定：秒级刷新与主题/语言重推都不会延长它。 */
    private fun scheduleExpiry(model: FocusTimerNotificationModel, nowWallClock: Long) {
        cancelExpiry()
        val delay = model.expiryDelayMillisAt(nowWallClock)
        if (delay <= 0L) return
        val runnable = Runnable {
            Log.i(tag, "focus timer reached zero; clearing notification")
            expiryCallback?.invoke()
            stopEverything()
        }
        expiryRunnable = runnable
        handler.postDelayed(runnable, delay)
    }

    private fun cancelExpiry() {
        expiryRunnable?.let { handler.removeCallbacks(it) }
        expiryRunnable = null
    }

    /**
     * 每秒一次的时间推进：正文时间、进度与 chronometer 基准一起刷新。
     * 暂停不调度；倒计时归零后停止自身刷新，交给到期调度做一次性清理。
     */
    private fun scheduleTicker(
        model: FocusTimerNotificationModel,
        startedAtElapsed: Long,
    ) {
        cancelTicker()
        if (model.paused) return
        val runnable = object : Runnable {
            override fun run() {
                val elapsed = (SystemClock.elapsedRealtime() - startedAtElapsed).coerceAtLeast(0L)
                val updated = model.afterElapsed(elapsed)
                if (!model.isCountUp && updated.remainingMillis <= 0L) return
                runCatching {
                    val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    manager.notify(notificationId, buildNotification(updated))
                }.onFailure { error ->
                    Log.w(tag, "focus timer tick refresh failed", error)
                }
                handler.postDelayed(this, tickMillis)
            }
        }
        tickRunnable = runnable
        handler.postDelayed(runnable, tickMillis)
    }

    private fun cancelTicker() {
        tickRunnable?.let { handler.removeCallbacks(it) }
        tickRunnable = null
    }

    private fun stopEverything() {
        cancelExpiry()
        cancelTicker()
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        runCatching { manager.cancel(notificationId) }
            .onFailure { error -> Log.w(tag, "focus timer notification cancel failed", error) }
        stopForegroundCompat()
        stopSelf()
    }

    private fun stopForegroundCompat() {
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(Service.STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        }.onFailure { error -> Log.w(tag, "focus timer stopForeground failed", error) }
    }

    companion object {
        private const val tag = "DuoyiFocusTimer"
        const val channelId = "duoyi_focus_timer_v1"
        const val notificationId = 951_101
        private const val progressMax = 1000
        private const val tickMillis = 1_000L
        private const val actionRequestCodeOffset = 10
        private const val defaultChannelName = "Focus timer"
        private const val actionSync = "com.duoyi.duoyi.FOCUS_TIMER_SYNC"
        private const val actionStop = "com.duoyi.duoyi.FOCUS_TIMER_STOP"
        private const val extraPayloadPrefix = "duoyi_focus_timer_"

        /** 原生到期回调（MainActivity 转发给 Dart）。 */
        var expiryCallback: (() -> Unit)? = null

        fun sync(context: Context, payload: Map<*, *>?) {
            val intent = Intent(context, FocusTimerForegroundService::class.java)
                .setAction(actionSync)
            payload?.forEach { entry ->
                val key = entry.key?.toString() ?: return@forEach
                val value = entry.value
                when (value) {
                    null -> Unit
                    is Boolean -> intent.putExtra(extraPayloadPrefix + key, value)
                    is Int -> intent.putExtra(extraPayloadPrefix + key, value)
                    is Long -> intent.putExtra(extraPayloadPrefix + key, value)
                    else -> intent.putExtra(extraPayloadPrefix + key, value.toString())
                }
            }
            startServiceCompat(context, intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, FocusTimerForegroundService::class.java)
                .setAction(actionStop)
            runCatching { context.startService(intent) }
                .onFailure { error ->
                    Log.w(tag, "focus timer stop request failed", error)
                    context.stopService(Intent(context, FocusTimerForegroundService::class.java))
                }
        }

        private fun startServiceCompat(context: Context, intent: Intent) {
            runCatching {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            }.onFailure { error ->
                Log.w(tag, "focus timer service start failed", error)
            }
        }

        private fun payloadFrom(intent: Intent?): Map<String, Any?>? {
            val extras = intent?.extras ?: return null
            if (extras.isEmpty) return null
            val payload = HashMap<String, Any?>()
            for (key in extras.keySet()) {
                if (!key.startsWith(extraPayloadPrefix)) continue
                payload[key.removePrefix(extraPayloadPrefix)] = extras.get(key)
            }
            return payload.ifEmpty { null }
        }
    }
}
