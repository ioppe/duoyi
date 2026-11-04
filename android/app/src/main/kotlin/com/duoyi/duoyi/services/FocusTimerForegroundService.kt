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
 * - 秒级显示交给系统 chronometer，倒计时到期由本服务清理通知并通知 Dart；
 *   Dart 只在状态变化时同步一次 payload。
 * - 通知权限被拒、前台服务启动被拒（Android 12+ 后台限制）都只记录日志，
 *   绝不反向打断计时。
 */
class FocusTimerForegroundService : Service() {

    private val handler = Handler(Looper.getMainLooper())
    private var expiryRunnable: Runnable? = null
    private var progressRunnable: Runnable? = null

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
        val startedAtElapsed = SystemClock.elapsedRealtime()
        val notification = buildNotification(model)
        val started = startForegroundSafely(notification)
        if (!started) {
            // 通知不可用时不留下后台服务；计时本身仍在 Dart 侧继续。
            stopEverything()
            return START_NOT_STICKY
        }
        scheduleExpiry(model)
        scheduleProgress(model, startedAtElapsed)
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        cancelExpiry()
        cancelProgress()
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
            .setContentText(textFor(model))
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
        return builder.build()
    }

    /** 暂停时补上冻结的剩余/累计时间，避免只显示“已暂停”而看不到停了多久。 */
    private fun textFor(model: FocusTimerNotificationModel): String {
        if (!model.paused) return model.text
        val frozen = formatDuration(model.remainingMillis)
        return listOf(model.text, frozen).filter { it.isNotEmpty() }.joinToString(" · ")
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

    private fun scheduleExpiry(model: FocusTimerNotificationModel) {
        cancelExpiry()
        val delay = model.expiryDelayMillis
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

    private fun scheduleProgress(model: FocusTimerNotificationModel, startedAtElapsed: Long) {
        cancelProgress()
        if (model.paused || !model.showsProgress || model.remainingMillis <= 0L) return
        val runnable = object : Runnable {
            override fun run() {
                val elapsed = (SystemClock.elapsedRealtime() - startedAtElapsed).coerceAtLeast(0L)
                val updated = model.afterElapsed(elapsed)
                if (updated.remainingMillis <= 0L) return
                runCatching {
                    val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    manager.notify(notificationId, buildNotification(updated))
                    handler.postDelayed(this, 15_000L.coerceAtMost(updated.remainingMillis))
                }.onFailure { error ->
                    Log.w(tag, "focus timer progress refresh failed", error)
                }
            }
        }
        progressRunnable = runnable
        handler.postDelayed(runnable, 15_000L.coerceAtMost(model.remainingMillis))
    }

    private fun cancelProgress() {
        progressRunnable?.let { handler.removeCallbacks(it) }
        progressRunnable = null
    }

    private fun stopEverything() {
        cancelExpiry()
        cancelProgress()
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

        private fun formatDuration(millis: Long): String {
            val totalSeconds = (millis.coerceAtLeast(0L) / 1000L)
            val hours = totalSeconds / 3600L
            val minutes = (totalSeconds % 3600L) / 60L
            val seconds = totalSeconds % 60L
            return if (hours > 0) {
                "%d:%02d:%02d".format(hours, minutes, seconds)
            } else {
                "%02d:%02d".format(minutes, seconds)
            }
        }
    }
}
