package com.duoyi.duoyi

import android.Manifest
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.TimeZone
import com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver

object ReminderRingtoneScheduler {
    private const val tag = "DuoyiReminderRingtone"
    private const val actionRing = "com.duoyi.duoyi.REMINDER_RING"
    private const val prefsName = "duoyi_native_reminder_ringtone"
    private val flutterScheduledPrefsNames = arrayOf(
        "scheduled_notifications",
        "notification_plugin_cache",
    )
    private const val flutterScheduledPrefsKey = "scheduled_notifications"
    private const val idsKey = "ids"
    private const val entryPrefix = "entry_"
    private const val lastIssueKey = "last_delivery_issue"
    private const val lastPlaybackStatusKey = "last_playback_status"
    private const val recentDeliveryPrefix = "recent_delivery_"
    private const val recentDeliveryTokensPrefix = "recent_delivery_tokens_"
    private const val recentDeliveryWindowMillis = 45_000L
    private const val recentDeliveryTokenMaxAgeMillis = 24 * 60 * 60 * 1000L
    private const val deliveryTokenExtra = "deliveryToken"
    const val FOLLOW_UP_SNOOZE = "snooze"
    const val FOLLOW_UP_AUTO_REPEAT = "auto_repeat"
    private const val followUpSnoozeNamespace = 0x20000000
    private const val followUpAutoRepeatNamespace = 0x30000000
    private val reservedFollowUpIds = setOf(
        880016,
        919001,
        919002,
        919003,
        919004,
    )

    fun showNow(
        context: Context,
        id: Int,
        title: String,
        body: String,
        payload: String?,
        fullScreen: Boolean = false,
        vibrate: Boolean = true,
        snoozeMinutes: Int = 0,
        repeatCount: Int = 0,
    ): Boolean {
        cancelScheduledOnly(context, id)
        prepareDeliveryInfrastructure(context)
        val intent = ReminderRingtoneService.intent(
            context,
            id,
            title,
            body,
            payload,
            fullScreen,
            vibrate,
            snoozeMinutes,
            repeatCount,
            id,
        )
        // `showNow` is user/test initiated. The scheduled receiver keeps its
        // own duplicate-delivery guard, but applying the same 45s guard here
        // makes rapid strong-reminder retries report success without actually
        // starting playback.
        recordNotificationPermissionIssueIfDenied(context, id)
        if (startRingtoneService(context, intent)) return true
        return ReminderRingtoneReceiver.showFallbackNotification(
            context,
            id,
            title,
            body,
            payload,
            fullScreen,
        )
    }

    fun scheduleOnce(
        context: Context,
        id: Int,
        title: String,
        body: String,
        triggerAtMillis: Long,
        payload: String?,
        fullScreen: Boolean = false,
        vibrate: Boolean = true,
        snoozeMinutes: Int = 0,
        repeatCount: Int = 0,
    ): Boolean {
        if (triggerAtMillis <= System.currentTimeMillis()) {
            cancelScheduledOnly(context, id)
            return false
        }
        cancelScheduledOnly(context, id)
        prepareDeliveryInfrastructure(context)
        val intent = baseIntent(
            context,
            id,
            title,
            body,
            payload,
            fullScreen,
            vibrate,
            snoozeMinutes,
            repeatCount,
            deliveryToken = buildDeliveryToken(id, id, triggerAtMillis, "once"),
        )
        if (!schedule(context, id, triggerAtMillis, intent)) return false
        rememberSchedule(context, id, triggerAtMillis, intent)
        return true
    }

    fun scheduleFollowUpOnce(
        context: Context,
        rootId: Int,
        followUpKind: String,
        title: String,
        body: String,
        triggerAtMillis: Long,
        payload: String?,
        fullScreen: Boolean = false,
        vibrate: Boolean = true,
        snoozeMinutes: Int = 0,
        repeatCount: Int = 0,
    ): Boolean {
        if (rootId == 0) return false
        val id = followUpId(rootId, followUpKind)
        cancelFollowUpSiblings(context, rootId, id)
        if (triggerAtMillis <= System.currentTimeMillis()) {
            cancelScheduledOnly(context, id)
            return false
        }
        cancelScheduledOnly(context, id)
        prepareDeliveryInfrastructure(context)
        val intent = baseIntent(
            context,
            id,
            title,
            body,
            payload,
            fullScreen,
            vibrate,
            snoozeMinutes,
            repeatCount,
            rootId,
            buildDeliveryToken(rootId, id, triggerAtMillis, followUpKind),
        ).putExtra("followUpKind", followUpKind)
        if (!schedule(context, id, triggerAtMillis, intent)) return false
        rememberSchedule(context, id, triggerAtMillis, intent)
        return true
    }

    fun reserveDelivery(
        context: Context,
        id: Int,
        rootId: Int = id,
        deliveryToken: String? = null,
    ): Boolean {
        if (id == 0) return true
        val deliveryRootId = if (rootId == 0) id else rootId
        val now = System.currentTimeMillis()
        val store = prefs(context)
        val key = "$recentDeliveryPrefix$deliveryRootId"
        val last = store.getLong(key, 0L)
        if (last > 0L && now >= last && now - last < recentDeliveryWindowMillis) {
            Log.w(tag, "duplicate delivery skipped: id=$id rootId=$deliveryRootId")
            return false
        }
        val normalizedToken = deliveryToken?.takeIf { it.isNotBlank() }
        if (normalizedToken != null) {
            val tokenKey = "$recentDeliveryTokensPrefix$deliveryRootId"
            val recentTokens = recentDeliveryTokens(store.getString(tokenKey, null), now)
            if (recentTokens.containsKey(normalizedToken)) {
                Log.w(tag, "duplicate delivery skipped: id=$id rootId=$deliveryRootId token=$normalizedToken")
                return false
            }
            recentTokens[normalizedToken] = now
            store.edit()
                .putString(tokenKey, encodeRecentDeliveryTokens(recentTokens, now))
                .putLong("$recentDeliveryPrefix$deliveryRootId", now)
                .apply()
            return true
        }
        store.edit().putLong(key, now).apply()
        return true
    }

    fun deliveryTokenFrom(intent: Intent): String? {
        return intent.getStringExtra(deliveryTokenExtra)?.takeIf { it.isNotBlank() }
    }

    fun scheduleDaily(
        context: Context,
        id: Int,
        title: String,
        body: String,
        hour: Int,
        minute: Int,
        weekdays: IntArray,
        timezoneId: String?,
        payload: String?,
        fullScreen: Boolean = false,
        vibrate: Boolean = true,
        snoozeMinutes: Int = 0,
        repeatCount: Int = 0,
    ): Boolean {
        val normalized = weekdays.filter { it in 1..7 }.distinct().toIntArray()
        val zoneId = normalizeTimeZone(timezoneId)
        val triggerAtMillis = nextWallClockMillis(hour, minute, normalized, zoneId)
        cancelScheduledOnly(context, id)
        prepareDeliveryInfrastructure(context)
        val intent = baseIntent(
            context,
            id,
            title,
            body,
            payload,
            fullScreen,
            vibrate,
            snoozeMinutes,
            repeatCount,
            deliveryToken = buildDeliveryToken(id, id, triggerAtMillis, "daily"),
        )
            .putExtra("repeat", true)
            .putExtra("hour", hour)
            .putExtra("minute", minute)
            .putExtra("weekdays", normalized)
            .putExtra("timezoneId", zoneId)
        if (!schedule(context, id, triggerAtMillis, intent)) return false
        rememberSchedule(context, id, triggerAtMillis, intent)
        return true
    }

    fun rescheduleFromReceiver(context: Context, source: Intent) {
        val id = source.getIntExtra("id", 0)
        if (id == 0) return
        scheduleDaily(
            context = context,
            id = id,
            title = source.getStringExtra("title") ?: "多仪提醒",
            body = source.getStringExtra("body") ?: "提醒时间到了",
            hour = source.getIntExtra("hour", 9),
            minute = source.getIntExtra("minute", 0),
            weekdays = source.getIntArrayExtra("weekdays") ?: intArrayOf(),
            timezoneId = source.getStringExtra("timezoneId"),
            payload = source.getStringExtra("payload"),
            fullScreen = source.getBooleanExtra("fullScreen", false),
            vibrate = source.getBooleanExtra("vibrate", true),
            snoozeMinutes = source.getIntExtra("snoozeMinutes", 0),
            repeatCount = source.getIntExtra("repeatCount", 0),
        )
    }

    fun cancel(context: Context, id: Int) {
        cancelScheduledOnly(context, id)
        ReminderRingtoneService.stopIfActive(context, id)
        ReminderRingtoneService.cancelNotification(context, id)
        for (childId in followUpIds(id)) {
            ReminderRingtoneService.stopIfActive(context, childId)
            ReminderRingtoneService.cancelNotification(context, childId)
        }
    }

    private fun cancelScheduledOnly(context: Context, id: Int) {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        cancelFlutterPluginScheduled(context, id)
        cancelPendingIntent(manager, context, id, baseIntent(context, id, "", "", null))
        forgetId(context, id)
        for (childId in followUpIds(id)) {
            cancelFlutterPluginScheduled(context, childId)
            cancelPendingIntent(
                manager,
                context,
                childId,
                baseIntent(context, childId, "", "", null, rootId = id),
            )
            forgetId(context, childId)
        }
    }

    private fun cancelFollowUpSiblings(context: Context, rootId: Int, keepId: Int) {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (childId in followUpIds(rootId)) {
            if (childId == keepId) continue
            cancelFlutterPluginScheduled(context, childId)
            cancelPendingIntent(
                manager,
                context,
                childId,
                baseIntent(context, childId, "", "", null, rootId = rootId),
            )
            forgetId(context, childId)
            ReminderRingtoneService.stopIfActive(context, childId)
            ReminderRingtoneService.cancelNotification(context, childId)
        }
    }

    fun cancelAll(context: Context) {
        val ids = prefs(context).getStringSet(idsKey, emptySet()).orEmpty()
        ids.mapNotNull { it.toIntOrNull() }.forEach { cancel(context, it) }
        prefs(context).edit().remove(idsKey).apply()
        ReminderRingtoneService.stopActive(context)
        ids.mapNotNull { it.toIntOrNull() }.forEach { id ->
            ReminderRingtoneService.cancelNotification(context, id)
            followUpIds(id).forEach { childId ->
                ReminderRingtoneService.cancelNotification(context, childId)
            }
        }
    }

    fun stopActiveRingtone(context: Context) {
        ReminderRingtoneService.stopActive(context)
    }

    fun cancelFollowUps(context: Context, rootId: Int) {
        if (rootId == 0) return
        cancelFollowUpSiblings(context, rootId, 0)
    }

    fun cancelFlutterPluginOwner(context: Context, id: Int) {
        if (id == 0) return
        cancelFlutterPluginScheduled(context, id)
    }

    fun cleanupFlutterPluginOwners(context: Context) {
        val ids = prefs(context).getStringSet(idsKey, emptySet()).orEmpty()
        ids.mapNotNull { it.toIntOrNull() }.forEach { id ->
            cancelFlutterPluginScheduled(context, id)
        }
    }

    fun markDelivered(context: Context, id: Int, rootId: Int = id) {
        if (id == 0) return
        cancelFlutterPluginScheduled(context, id)
        forgetId(context, id)
        if (rootId != 0 && rootId != id) {
            cancelFollowUpSiblings(context, rootId, id)
        }
    }

    fun pendingIds(context: Context): List<Int> {
        val store = prefs(context)
        val ids = store.getStringSet(idsKey, emptySet()).orEmpty()
        val now = System.currentTimeMillis()
        val active = mutableListOf<Int>()
        val stale = mutableSetOf<String>()
        ids.forEach { rawId ->
            val id = rawId.toIntOrNull()
            val rawEntry = store.getString("${entryPrefix}$rawId", null)
            val json = rawEntry?.let { runCatching { JSONObject(it) }.getOrNull() }
            if (id == null || json == null) {
                stale.add(rawId)
                return@forEach
            }
            val repeat = json.optBoolean("repeat", false)
            val triggerAtMillis = json.optLong("triggerAtMillis", 0L)
            if (!repeat &&
                triggerAtMillis <= now &&
                !scheduledPendingIntentExists(context, id, json)
            ) {
                stale.add(rawId)
                return@forEach
            }
            active.add(id)
        }
        if (stale.isNotEmpty()) {
            val nextIds = ids.toMutableSet().also { it.removeAll(stale) }
            val edit = store.edit().putStringSet(idsKey, nextIds)
            stale.forEach { edit.remove("${entryPrefix}$it") }
            edit.apply()
        }
        return active.distinct().sorted()
    }

    fun recordDeliveryIssue(
        context: Context,
        id: Int,
        reason: String,
        message: String,
    ) {
        val payload = JSONObject()
            .put("id", id)
            .put("reason", reason)
            .put("message", message)
            .put("timestamp", System.currentTimeMillis())
        prefs(context).edit().putString(lastIssueKey, payload.toString()).apply()
    }

    fun lastDeliveryIssue(context: Context): Map<String, Any?>? {
        val raw = prefs(context).getString(lastIssueKey, null) ?: return null
        val json = runCatching { JSONObject(raw) }.getOrNull() ?: return null
        return mapOf(
            "id" to json.optInt("id", 0),
            "reason" to json.optString("reason", ""),
            "message" to json.optString("message", ""),
            "timestamp" to json.optLong("timestamp", 0L),
        )
    }

    fun clearLastDeliveryIssue(context: Context) {
        prefs(context).edit().remove(lastIssueKey).apply()
    }

    fun recordNotificationPermissionIssueIfDenied(context: Context, id: Int): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return false
        if (ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        recordDeliveryIssue(
            context,
            id,
            "notification_permission_denied",
            "系统通知权限关闭，内置铃声会继续尝试播放，但停止、稍后提醒或兜底通知可能无法显示；请开启通知权限后重新保存提醒。",
        )
        return true
    }

    fun recordPlaybackStarted(
        context: Context,
        id: Int,
        source: String,
    ) {
        if (id == 0) return
        val payload = JSONObject()
            .put("id", id)
            .put("status", "started")
            .put("source", source)
            .put("timestamp", System.currentTimeMillis())
        prefs(context).edit().putString(lastPlaybackStatusKey, payload.toString()).apply()
    }

    fun lastPlaybackStatus(context: Context): Map<String, Any?>? {
        val raw = prefs(context).getString(lastPlaybackStatusKey, null) ?: return null
        val json = runCatching { JSONObject(raw) }.getOrNull() ?: return null
        return mapOf(
            "id" to json.optInt("id", 0),
            "status" to json.optString("status", ""),
            "source" to json.optString("source", ""),
            "timestamp" to json.optLong("timestamp", 0L),
        )
    }

    fun clearLastPlaybackStatus(context: Context) {
        prefs(context).edit().remove(lastPlaybackStatusKey).apply()
    }

    fun restoreAll(context: Context, deliverExpired: Boolean = true) {
        val ids = prefs(context).getStringSet(idsKey, emptySet()).orEmpty()
        ids.mapNotNull { it.toIntOrNull() }.forEach { id ->
            cancelFlutterPluginScheduled(context, id)
            restoreOne(context, id, deliverExpired)
        }
    }

    private fun schedule(context: Context, id: Int, triggerAtMillis: Long, intent: Intent): Boolean {
        return runCatching {
            val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val operation = pendingIntent(context, id, intent)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !manager.canScheduleExactAlarms()) {
                    manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, operation)
                } else {
                    manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, operation)
                }
            } else {
                manager.setExact(AlarmManager.RTC_WAKEUP, triggerAtMillis, operation)
            }
            true
        }.getOrElse { error ->
            Log.w(tag, "schedule failed: id=$id triggerAtMillis=$triggerAtMillis", error)
            false
        }
    }

    private fun prepareDeliveryInfrastructure(context: Context) {
        runCatching {
            ReminderRingtoneService.ensureStatusNotificationChannel(context)
            ReminderRingtoneReceiver.ensureFallbackNotificationChannel(context)
        }.onFailure { error ->
            Log.w(tag, "prepare delivery notification channels failed", error)
        }
    }

    private fun startRingtoneService(context: Context, intent: Intent): Boolean {
        return runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            true
        }.getOrElse { error ->
            recordDeliveryIssue(
                context,
                id = intent.getIntExtra("id", 0),
                reason = "service_start_failed",
                message = "系统拒绝启动内置提醒铃声服务：${error.message ?: error.javaClass.simpleName}",
            )
            false
        }
    }

    private fun pendingIntent(context: Context, id: Int, intent: Intent): PendingIntent {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(context, id, intent, flags)
    }

    private fun existingPendingIntent(context: Context, id: Int, intent: Intent): PendingIntent? {
        val flags = PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(context, id, intent, flags)
    }

    private fun cancelPendingIntent(
        manager: AlarmManager,
        context: Context,
        id: Int,
        intent: Intent,
    ) {
        existingPendingIntent(context, id, intent)?.let { manager.cancel(it) }
    }

    private fun scheduledPendingIntentExists(context: Context, id: Int, json: JSONObject): Boolean {
        val rootId = json.optInt("rootId", id)
        val intent = baseIntent(context, id, "", "", null, rootId = rootId)
        return existingPendingIntent(context, id, intent) != null
    }

    private fun cancelFlutterPluginScheduled(context: Context, id: Int) {
        val ids = pluginAlarmQueueIds(id)
        runCatching {
            val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            ids.forEach { pluginId ->
                val intent = Intent(context, ScheduledNotificationReceiver::class.java)
                cancelPendingIntent(manager, context, pluginId, intent)
                NotificationManagerCompat.from(context).cancel(pluginId)
            }
        }.onFailure { error ->
            Log.w(tag, "flutter scheduled alarm cleanup failed: id=$id", error)
        }
        removeFlutterPluginCacheIds(context, ids)
    }

    private fun removeFlutterPluginCacheIds(context: Context, ids: Set<Int>) {
        for (prefsName in flutterScheduledPrefsNames) {
            runCatching {
                val store = context.getSharedPreferences(
                    prefsName,
                    Context.MODE_PRIVATE,
                )
                val raw = store.getString(flutterScheduledPrefsKey, null)
                    ?: return@runCatching
                val source = JSONArray(raw)
                val kept = JSONArray()
                for (index in 0 until source.length()) {
                    val item = source.optJSONObject(index)
                    if (item == null || item.optInt("id", 0) !in ids) {
                        kept.put(source.get(index))
                    }
                }
                store.edit().putString(flutterScheduledPrefsKey, kept.toString()).commit()
            }.onFailure { error ->
                Log.w(
                    tag,
                    "flutter scheduled cache cleanup failed: prefs=$prefsName ids=${ids.joinToString(",")}",
                    error,
                )
            }
        }
    }

    private fun pluginAlarmQueueIds(id: Int): Set<Int> {
        val ids = mutableSetOf(id)
        for (weekday in 1..7) {
            ids.add(subId(id, weekday))
            ids.add(legacySubId(id, weekday))
        }
        return ids
    }

    private fun followUpIds(rootId: Int): List<Int> {
        return listOf(
            followUpId(rootId, FOLLOW_UP_SNOOZE),
            followUpId(rootId, FOLLOW_UP_AUTO_REPEAT),
        ).distinct()
    }

    private fun followUpId(rootId: Int, kind: String): Int {
        val namespace = when (kind) {
            FOLLOW_UP_SNOOZE -> followUpSnoozeNamespace
            FOLLOW_UP_AUTO_REPEAT -> followUpAutoRepeatNamespace
            else -> 0x40000000
        }
        var hash = 0x811c9dc5.toInt()
        val key = "$rootId:$kind"
        key.forEach { ch ->
            hash = hash xor ch.code
            hash *= 0x01000193
        }
        val lowBits = hash and 0x0fffffff
        var candidate = namespace or lowBits
        var salt = 0
        while (candidate == 0 ||
            candidate == rootId ||
            candidate in reservedFollowUpIds
        ) {
            salt += 1
            candidate = namespace or ((lowBits + salt) and 0x0fffffff)
        }
        return candidate
    }

    private fun subId(base: Int, weekday: Int): Int {
        var hash = 0x811c9dc5.toInt()
        val key = "$base:$weekday"
        key.forEach { ch ->
            hash = hash xor ch.code
            hash = (hash * 0x01000193) and 0x7fffffff
        }
        return if (hash == 0) weekday else hash
    }

    private fun legacySubId(base: Int, weekday: Int): Int {
        return (base.toLong() * 10L + weekday.toLong()).toInt()
    }

    private fun baseIntent(
        context: Context,
        id: Int,
        title: String,
        body: String,
        payload: String?,
        fullScreen: Boolean = false,
        vibrate: Boolean = true,
        snoozeMinutes: Int = 0,
        repeatCount: Int = 0,
        rootId: Int = id,
        deliveryToken: String = buildDeliveryToken(rootId, id, System.currentTimeMillis(), "manual"),
    ): Intent {
        return Intent(context, ReminderRingtoneReceiver::class.java)
            .setAction(actionRing)
            .putExtra("id", id)
            .putExtra("rootId", rootId)
            .putExtra("title", title)
            .putExtra("body", body)
            .putExtra("payload", payload)
            .putExtra("fullScreen", fullScreen)
            .putExtra("vibrate", vibrate)
            .putExtra("snoozeMinutes", snoozeMinutes.coerceIn(0, 120))
            .putExtra("repeatCount", repeatCount.coerceIn(0, 10))
            .putExtra("repeatRemaining", repeatCount.coerceIn(0, 10))
            .putExtra(deliveryTokenExtra, deliveryToken)
    }

    private fun buildDeliveryToken(
        rootId: Int,
        id: Int,
        triggerAtMillis: Long,
        kind: String,
    ): String {
        val normalizedRootId = if (rootId == 0) id else rootId
        return "$normalizedRootId:$id:$triggerAtMillis:$kind"
    }

    private fun recentDeliveryTokens(raw: String?, now: Long): MutableMap<String, Long> {
        val result = linkedMapOf<String, Long>()
        if (raw.isNullOrBlank()) return result
        val json = runCatching { JSONObject(raw) }.getOrNull() ?: return result
        val keys = json.keys()
        while (keys.hasNext()) {
            val token = keys.next()
            val timestamp = json.optLong(token, 0L)
            if (timestamp > 0L &&
                (now < timestamp || now - timestamp <= recentDeliveryTokenMaxAgeMillis)
            ) {
                result[token] = timestamp
            }
        }
        return result
    }

    private fun encodeRecentDeliveryTokens(tokens: Map<String, Long>, now: Long): String {
        val json = JSONObject()
        tokens.entries
            .filter { it.value > 0L && (now < it.value || now - it.value <= recentDeliveryTokenMaxAgeMillis) }
            .sortedByDescending { it.value }
            .take(32)
            .forEach { (token, timestamp) -> json.put(token, timestamp) }
        return json.toString()
    }

    private fun nextWallClockMillis(
        hour: Int,
        minute: Int,
        weekdays: IntArray,
        timezoneId: String,
    ): Long {
        val zone = TimeZone.getTimeZone(timezoneId)
        val now = Calendar.getInstance(zone)
        var best: Long? = null
        for (offset in 0..7) {
            val candidate = Calendar.getInstance(zone).apply {
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
                set(Calendar.HOUR_OF_DAY, hour.coerceIn(0, 23))
                set(Calendar.MINUTE, minute.coerceIn(0, 59))
                add(Calendar.DAY_OF_YEAR, offset)
            }
            val dartWeekday = when (candidate.get(Calendar.DAY_OF_WEEK)) {
                Calendar.MONDAY -> 1
                Calendar.TUESDAY -> 2
                Calendar.WEDNESDAY -> 3
                Calendar.THURSDAY -> 4
                Calendar.FRIDAY -> 5
                Calendar.SATURDAY -> 6
                else -> 7
            }
            val weekdayAllowed = weekdays.isEmpty() || weekdays.contains(dartWeekday)
            if (weekdayAllowed && candidate.after(now)) {
                val millis = candidate.timeInMillis
                if (best == null || millis < best!!) best = millis
            }
        }
        return best ?: now.timeInMillis + 60_000L
    }

    private fun normalizeTimeZone(timezoneId: String?): String {
        val systemDefault = TimeZone.getDefault().id
        val normalized = timezoneId?.trim().orEmpty()
        if (normalized.isBlank()) {
            return systemDefault
        }
        val resolved = TimeZone.getTimeZone(normalized)
        if (resolved.id == "GMT" && normalized != "GMT" && normalized != "Etc/GMT") {
            return systemDefault
        }
        return normalized
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)

    private fun rememberSchedule(
        context: Context,
        id: Int,
        triggerAtMillis: Long,
        intent: Intent,
    ) {
        val store = prefs(context)
        val next = store.getStringSet(idsKey, emptySet()).orEmpty().toMutableSet()
        next.add(id.toString())
        store.edit()
            .putStringSet(idsKey, next)
            .putString("${entryPrefix}$id", encodeEntry(triggerAtMillis, intent))
            .apply()
    }

    private fun forgetId(context: Context, id: Int) {
        val store = prefs(context)
        val next = store.getStringSet(idsKey, emptySet()).orEmpty().toMutableSet()
        next.remove(id.toString())
        store.edit()
            .putStringSet(idsKey, next)
            .remove("${entryPrefix}$id")
            .apply()
    }

    private fun restoreOne(context: Context, id: Int, deliverExpired: Boolean) {
        val raw = prefs(context).getString("${entryPrefix}$id", null) ?: return
        val json = runCatching { JSONObject(raw) }.getOrNull() ?: return
        val title = json.optString("title", "多仪提醒")
        val body = json.optString("body", "提醒时间到了")
        val payload = json.optString("payload").ifBlank { null }
        val rootId = json.optInt("rootId", id)
        val followUpKind = json.optString("followUpKind").ifBlank { null }
        val vibrate = json.optBoolean("vibrate", true)
        val fullScreen = json.optBoolean("fullScreen", false)
        val snoozeMinutes = json.optInt("snoozeMinutes", 0)
        val repeatCount = json.optInt("repeatCount", 0)
        val repeat = json.optBoolean("repeat", false)
        val storedDeliveryToken = json.optString("deliveryToken").ifBlank {
            buildDeliveryToken(rootId, id, json.optLong("triggerAtMillis", 0L), followUpKind ?: "once")
        }
        if (repeat) {
            val weekdays = json.optJSONArray("weekdays")?.let { array ->
                IntArray(array.length()) { index -> array.optInt(index) }
            } ?: intArrayOf()
            scheduleDaily(
                context = context,
                id = id,
                title = title,
                body = body,
                hour = json.optInt("hour", 9),
                minute = json.optInt("minute", 0),
                weekdays = weekdays,
                timezoneId = json.optString("timezoneId").ifBlank { null },
                payload = payload,
                fullScreen = fullScreen,
                vibrate = vibrate,
                snoozeMinutes = snoozeMinutes,
                repeatCount = repeatCount,
            )
            return
        }

        val triggerAtMillis = json.optLong("triggerAtMillis", 0L)
        if (triggerAtMillis > System.currentTimeMillis()) {
            if (followUpKind != null && rootId != id) {
                scheduleFollowUpOnce(
                    context,
                    rootId,
                    followUpKind,
                    title,
                    body,
                    triggerAtMillis,
                    payload,
                    fullScreen,
                    vibrate,
                    snoozeMinutes,
                    repeatCount,
                )
            } else {
                scheduleOnce(context, id, title, body, triggerAtMillis, payload, fullScreen, vibrate, snoozeMinutes, repeatCount)
            }
        } else {
            val intent = ReminderRingtoneService.intent(
                context,
                id,
                title,
                body,
                payload,
                fullScreen,
                vibrate,
                snoozeMinutes,
                repeatCount,
                rootId,
            )
            cancelScheduledOnly(context, id)
            if (rootId != id) {
                cancelFollowUpSiblings(context, rootId, id)
            }
            if (!deliverExpired) {
                Log.i(tag, "expired restore delivery skipped after app update: id=$id")
                return
            }
            if (reserveDelivery(context, id, rootId, storedDeliveryToken)) {
                recordNotificationPermissionIssueIfDenied(context, id)
                prepareDeliveryInfrastructure(context)
                if (!startRingtoneService(context, intent)) {
                    ReminderRingtoneReceiver.showFallbackNotification(
                        context,
                        id,
                        title,
                        body,
                        payload,
                        fullScreen,
                        rootId,
                    )
                }
            }
        }
    }

    private fun encodeEntry(triggerAtMillis: Long, intent: Intent): String {
        val weekdays = intent.getIntArrayExtra("weekdays") ?: intArrayOf()
        val id = intent.getIntExtra("id", 0)
        val rootId = intent.getIntExtra("rootId", id)
        val followUpKind = intent.getStringExtra("followUpKind") ?: ""
        return JSONObject()
            .put("title", intent.getStringExtra("title") ?: "多仪提醒")
            .put("body", intent.getStringExtra("body") ?: "提醒时间到了")
            .put("payload", intent.getStringExtra("payload") ?: "")
            .put("rootId", rootId)
            .put("followUpKind", followUpKind)
            .put(
                "deliveryToken",
                intent.getStringExtra(deliveryTokenExtra)
                    ?: buildDeliveryToken(rootId, id, triggerAtMillis, followUpKind.ifBlank { "once" }),
            )
            .put("fullScreen", intent.getBooleanExtra("fullScreen", false))
            .put("vibrate", intent.getBooleanExtra("vibrate", true))
            .put("snoozeMinutes", intent.getIntExtra("snoozeMinutes", 0))
            .put("repeatCount", intent.getIntExtra("repeatCount", 0))
            .put("triggerAtMillis", triggerAtMillis)
            .put("repeat", intent.getBooleanExtra("repeat", false))
            .put("hour", intent.getIntExtra("hour", 9))
            .put("minute", intent.getIntExtra("minute", 0))
            .put("weekdays", JSONArray(weekdays.toList()))
            .put("timezoneId", intent.getStringExtra("timezoneId") ?: "")
            .toString()
    }
}
