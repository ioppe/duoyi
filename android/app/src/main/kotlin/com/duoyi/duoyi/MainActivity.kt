package com.duoyi.duoyi

import android.appwidget.AppWidgetManager
import android.app.Activity
import android.app.AppOpsManager
import android.app.PendingIntent
import android.content.ComponentName
import android.app.NotificationManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ApplicationInfo
import android.media.AudioManager
import android.net.Uri
import android.os.Bundle
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.Settings
import android.provider.OpenableColumns
import android.util.Log
import androidx.core.content.FileProvider
import com.duoyi.duoyi.services.FocusSoundForegroundService
import java.io.File
import java.io.IOException
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.Executors
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val platformInfoChannel = "duoyi/platform_info"
    private val updateChannel = "duoyi/update"
    private val notificationSettingsChannel = "duoyi/notification_settings"
    private val reminderRingtoneChannel = "duoyi/reminder_ringtone"
    private val focusSoundForegroundChannel = "duoyi/focus_sound_foreground"
    private val focusDndChannel = "duoyi/focus_dnd"
    private val focusDistractionChannel = "duoyi/focus_distraction"
    private val widgetsChannel = "duoyi/widgets"
    private val locationGeofenceChannel = "duoyi/location_geofence"
    private val noteAttachmentPickerChannel = "duoyi/note_attachment_picker"
    private val deepLinksChannel = "duoyi/deep_links"
    private val pickNoteAttachmentRequest = 7301
    private var pendingNoteAttachmentPick: MethodChannel.Result? = null
    private var deepLinksMethodChannel: MethodChannel? = null
    private var pendingInitialDeepLink: String? = null
    private var pendingInitialOAuthLink: String? = null
    private var pendingInitialSharedText: String? = null
    private var focusSoundForegroundMethodChannel: MethodChannel? = null
    private val widgetRestoreHandler = Handler(Looper.getMainLooper())
    private val widgetRestoreExecutor = Executors.newSingleThreadExecutor()
    private var widgetRestoreScheduled = false
    private var lastWidgetRestoreAtMillis = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        stopReminderRingtoneIfRequested(intent)
        pendingInitialDeepLink = duoyiDeepLinkFrom(intent)
        pendingInitialOAuthLink = oauthDeepLinkFrom(intent)
        pendingInitialSharedText = sharedTextFrom(intent)
    }

    override fun onResume() {
        super.onResume()
        scheduleWidgetRestoreAfterResume()
    }

    override fun onDestroy() {
        widgetRestoreHandler.removeCallbacksAndMessages(null)
        widgetRestoreExecutor.shutdownNow()
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        stopReminderRingtoneIfRequested(intent)
        val deepLink = duoyiDeepLinkFrom(intent)
        val link = oauthDeepLinkFrom(intent)
        val sharedText = sharedTextFrom(intent)
        val channel = deepLinksMethodChannel
        if (channel == null) {
            if (deepLink != null) pendingInitialDeepLink = deepLink
            if (link != null) pendingInitialOAuthLink = link
            if (sharedText != null) pendingInitialSharedText = sharedText
        } else {
            if (deepLink != null) channel.invokeMethod("onLink", deepLink)
            if (sharedText != null) channel.invokeMethod("onSharedText", sharedText)
        }
    }

    private fun scheduleWidgetRestoreAfterResume() {
        val now = System.currentTimeMillis()
        if (widgetRestoreScheduled || now - lastWidgetRestoreAtMillis < 60_000L) return
        widgetRestoreScheduled = true
        val appContext = applicationContext
        widgetRestoreHandler.postDelayed({
            widgetRestoreScheduled = false
            lastWidgetRestoreAtMillis = System.currentTimeMillis()
            widgetRestoreExecutor.execute {
                runCatching {
                    val restored =
                        DuoyiWidgetProviderRegistry.restoreEnabledProvidersForExistingWidgets(appContext)
                    DuoyiWidgetProviderRegistry.cleanupPendingVariantProviders(appContext)
                    if (restored > 0) {
                        DuoyiWidgetProviderRegistry.requestUpdateForAllWidgets(appContext)
                    }
                }.onFailure { error ->
                    Log.w("DuoyiWidgetPin", "resume widget provider restore failed", error)
                }
            }
        }, 4_500L)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, platformInfoChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAndroidDeviceInfo" -> {
                        result.success(
                            mapOf(
                                "manufacturer" to Build.MANUFACTURER,
                                "brand" to Build.BRAND,
                                "model" to Build.MODEL,
                                "sdkInt" to Build.VERSION.SDK_INT,
                            ),
                        )
                    }
                    "canUseFullScreenIntent" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                            result.success(manager.canUseFullScreenIntent())
                        } else {
                            result.success(true)
                        }
                    }
                    "getSystemTimeZoneId" -> {
                        result.success(TimeZone.getDefault().id)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstallPackages" -> {
                        val canInstall = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            packageManager.canRequestPackageInstalls()
                        } else {
                            true
                        }
                        result.success(canInstall)
                    }
                    "openInstallPermissionSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName"),
                            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                        }
                        result.success(null)
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("invalid_path", "APK 路径为空", null)
                            return@setMethodCallHandler
                        }
                        val source = File(path)
                        if (!source.exists()) {
                            result.error("missing_apk", "APK 文件不存在: $path", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val file = prepareApkForInstall(source)
                            val uri = FileProvider.getUriForFile(
                                this,
                                "$packageName.fileprovider",
                                file,
                            )
                            val intent = Intent(Intent.ACTION_VIEW)
                                .setDataAndType(uri, "application/vnd.android.package-archive")
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(null)
                        } catch (e: IllegalArgumentException) {
                            result.error("file_provider_root", "安装包路径无法授权: ${e.message}", null)
                        } catch (e: IOException) {
                            result.error("prepare_apk_failed", "准备安装包失败: ${e.message}", null)
                        } catch (e: Exception) {
                            result.error("install_failed", "打开安装器失败: ${e.message}", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notificationSettingsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openAppNotificationSettings" -> {
                        result.success(openAppNotificationSettings())
                    }
                    "openNotificationChannelSettings" -> {
                        val channelId = call.argument<String>("channelId")
                        result.success(openNotificationChannelSettings(channelId))
                    }
                    "notificationChannelStatuses" -> {
                        val channelIds = call.argument<List<String>>("channelIds") ?: emptyList()
                        result.success(notificationChannelStatuses(channelIds))
                    }
                    "systemAudioStatus" -> {
                        result.success(systemAudioStatus())
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, reminderRingtoneChannel)
            .setMethodCallHandler { call, result ->
                val arguments = call.arguments as? Map<*, *>
                val id = (arguments?.get("id") as? Number)?.toInt() ?: 0
                val title = call.argument<String>("title") ?: "多仪提醒"
                val body = call.argument<String>("body") ?: "提醒时间到了"
                val payload = call.argument<String>("payload")
                val fullScreen = call.argument<Boolean>("fullScreen") ?: false
                val vibrate = call.argument<Boolean>("vibrate") ?: true
                val snoozeMinutes = call.argument<Int>("snoozeMinutes") ?: 0
                val repeatCount = call.argument<Int>("repeatCount") ?: 0
                when (call.method) {
                    "showNow" -> {
                        val ok = ReminderRingtoneScheduler.showNow(this, id, title, body, payload, fullScreen, vibrate, snoozeMinutes, repeatCount)
                        if (ok) {
                            result.success(true)
                        } else {
                            result.error("ringtone_show_failed", "内置提醒铃声启动失败", null)
                        }
                    }
                    "scheduleOnce" -> {
                        val triggerAtMillis = call.argument<Long>("triggerAtMillis")
                            ?: call.argument<Int>("triggerAtMillis")?.toLong()
                            ?: 0L
                        val ok = ReminderRingtoneScheduler.scheduleOnce(
                            this,
                            id,
                            title,
                            body,
                            triggerAtMillis,
                            payload,
                            fullScreen,
                            vibrate,
                            snoozeMinutes,
                            repeatCount,
                        )
                        if (ok) {
                            result.success(true)
                        } else {
                            result.error("ringtone_schedule_failed", "内置提醒铃声注册失败", null)
                        }
                    }
                    "scheduleDaily" -> {
                        val hour = call.argument<Int>("hour") ?: 9
                        val minute = call.argument<Int>("minute") ?: 0
                        val weekdays = call.argument<List<Int>>("weekdays")
                            ?.toIntArray()
                            ?: intArrayOf()
                        val timezoneId = call.argument<String>("timezoneId")
                            ?: TimeZone.getDefault().id
                        val ok = ReminderRingtoneScheduler.scheduleDaily(
                            this,
                            id,
                            title,
                            body,
                            hour,
                            minute,
                            weekdays,
                            timezoneId,
                            payload,
                            fullScreen,
                            vibrate,
                            snoozeMinutes,
                            repeatCount,
                        )
                        if (ok) {
                            result.success(true)
                        } else {
                            result.error("ringtone_schedule_failed", "内置重复提醒铃声注册失败", null)
                        }
                    }
                    "cancel" -> {
                        ReminderRingtoneScheduler.cancel(this, id)
                        result.success(null)
                    }
                    "cancelAll" -> {
                        ReminderRingtoneScheduler.cancelAll(this)
                        result.success(null)
                    }
                    "pendingIds" -> {
                        result.success(ReminderRingtoneScheduler.pendingIds(this))
                    }
                    "lastDeliveryIssue" -> {
                        result.success(ReminderRingtoneScheduler.lastDeliveryIssue(this))
                    }
                    "clearLastDeliveryIssue" -> {
                        ReminderRingtoneScheduler.clearLastDeliveryIssue(this)
                        result.success(null)
                    }
                    "lastPlaybackStatus" -> {
                        result.success(ReminderRingtoneScheduler.lastPlaybackStatus(this))
                    }
                    "clearLastPlaybackStatus" -> {
                        ReminderRingtoneScheduler.clearLastPlaybackStatus(this)
                        result.success(null)
                    }
                    "stopActive" -> {
                        ReminderRingtoneScheduler.stopActiveRingtone(this)
                        ReminderRingtoneService.stopPreview()
                        result.success(null)
                    }
                    "previewCurrentSound" -> {
                        val durationMillis = call.argument<Long>("durationMillis")
                            ?: call.argument<Int>("durationMillis")?.toLong()
                            ?: 3000L
                        try {
                            result.success(ReminderRingtoneService.previewCurrentSound(this, durationMillis))
                        } catch (error: Exception) {
                            Log.e("MainActivity", "previewCurrentSound channel failed", error)
                            result.success(
                                mapOf(
                                    "started" to false,
                                    "reason" to "platform_channel_failed",
                                    "message" to "铃声试听启动失败，请重试。",
                                )
                            )
                        }
                    }
                    "stopPreview" -> {
                        ReminderRingtoneService.stopPreview()
                        result.success(null)
                    }
                    "setVolumePercent" -> {
                        val volume = call.argument<Int>("volumePercent") ?: 60
                        ReminderRingtoneService.setVolumePercent(this, volume)
                        result.success(null)
                    }
                    "setSoundName" -> {
                        val soundName = call.argument<String>("soundName") ?: "soft"
                        ReminderRingtoneService.setSoundName(this, soundName)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        val focusChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, focusSoundForegroundChannel)
        focusSoundForegroundMethodChannel = focusChannel
        FocusSoundForegroundService.stopRequestCallback = {
            focusSoundForegroundMethodChannel?.invokeMethod("stopRequested", null)
        }
        focusChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        FocusSoundForegroundService.start(this)
                        result.success(null)
                    }
                    "stop" -> {
                        FocusSoundForegroundService.stop(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, focusDndChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getStatus" -> result.success(focusDndStatus())
                    "openPolicyAccessSettings" -> {
                        result.success(openNotificationPolicyAccessSettings())
                    }
                    "enableDnd" -> {
                        val filter = call.argument<Int>("filter")
                            ?: NotificationManager.INTERRUPTION_FILTER_PRIORITY
                        result.success(enableFocusDnd(filter))
                    }
                    "restoreDnd" -> {
                        val previousFilter = call.argument<Int>("previousFilter")
                            ?: NotificationManager.INTERRUPTION_FILTER_ALL
                        result.success(restoreFocusDnd(previousFilter))
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, focusDistractionChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getStatus" -> {
                        result.success(
                            mapOf(
                                "supported" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP),
                                "accessGranted" to hasUsageStatsAccess(),
                                "accessibilityGranted" to hasFocusBlockerAccessibilityAccess(),
                                "blockerConfigured" to FocusBlockerStore.isConfigured(this),
                                "lastBlockedPackage" to FocusBlockerStore.lastBlockedPackage(this),
                                "lastBlockedAt" to FocusBlockerStore.lastBlockedAt(this),
                                "foregroundPackage" to foregroundPackageName(),
                            ),
                        )
                    }
                    "getForegroundApp" -> result.success(foregroundPackageName())
                    "openUsageAccessSettings" -> result.success(openUsageAccessSettings())
                    "openAccessibilitySettings" -> result.success(openAccessibilitySettings())
                    "getInstalledApps" -> result.success(installedLaunchableApps())
                    "setFocusBlocker" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        val packages = call.argument<List<String>>("packages")
                            ?.map { it.trim() }
                            ?.filter { it.isNotEmpty() }
                            ?.toSet()
                            ?: emptySet()
                        FocusBlockerStore.setConfig(this, enabled, packages)
                        result.success(FocusBlockerStore.isConfigured(this))
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, widgetsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canRequestPinWidget" -> result.success(canRequestPinWidget())
                    "canOpenWidgetSettings" -> result.success(canOpenWidgetSettings())
                    "openWidgetSettings" -> result.success(openWidgetSettings())
                    "requestPinWidget" -> {
                        val kind = call.argument<String>("kind") ?: "todo"
                        val style = call.argument<String>("style") ?: "standard"
                        result.success(requestPinWidget(kind, style))
                    }
                    "lastPinResult" -> {
                        val requestId = call.argument<String>("requestId") ?: ""
                        result.success(lastWidgetPinResult(requestId))
                    }
                    "clearPinResult" -> {
                        val requestId = call.argument<String>("requestId") ?: ""
                        clearWidgetPinResult(requestId)
                        result.success(null)
                    }
                    "cancelPinRequest" -> {
                        val requestId = call.argument<String>("requestId") ?: ""
                        DuoyiWidgetProviderRegistry.cleanupPendingVariantProvider(this, requestId)
                        DuoyiWidgetProviderRegistry.requestUpdateForAllWidgets(this)
                        result.success(null)
                    }
                    "applyWidgetDisplayMode" -> {
                        val style = call.argument<String>("style") ?: "standard"
                        result.success(DuoyiWidgetProviderRegistry.applyDisplayModeToExistingWidgets(this, style))
                    }
                    "refreshAllWidgets" -> {
                        DuoyiWidgetProviderRegistry.restoreEnabledProvidersForExistingWidgets(this)
                        result.success(DuoyiWidgetProviderRegistry.requestUpdateForAllWidgets(this))
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, locationGeofenceChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "syncReminders" -> {
                        val args = call.arguments as? Map<*, *>
                        val raw = args?.get("reminders") as? List<*> ?: emptyList<Any>()
                        val reminders = raw.mapNotNull {
                            LocationGeofenceScheduler.parseReminder(it as? Map<*, *> ?: return@mapNotNull null)
                        }
                        LocationGeofenceScheduler.syncReminders(
                            this,
                            reminders,
                            onResult = { result.success(it) },
                            onError = { code, message -> result.error(code, message, null) },
                        )
                    }
                    "clearReminders" -> {
                        LocationGeofenceScheduler.clearReminders(this) {
                            result.success(it)
                        }
                    }
                    "openLocationSettings" -> {
                        result.success(openLocationSettings())
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, noteAttachmentPickerChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickFile" -> pickNoteAttachment(result)
                    else -> result.notImplemented()
                }
            }
        deepLinksMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            deepLinksChannel,
        )
        deepLinksMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "takeInitialLink" -> {
                    val link = pendingInitialDeepLink
                    pendingInitialDeepLink = null
                    if (link != null && link == pendingInitialOAuthLink) {
                        pendingInitialOAuthLink = null
                    }
                    result.success(link)
                }
                "takeInitialOAuthLink" -> {
                    val link = pendingInitialOAuthLink
                    pendingInitialOAuthLink = null
                    result.success(link)
                }
                "takeInitialSharedText" -> {
                    val text = pendingInitialSharedText
                    pendingInitialSharedText = null
                    result.success(text)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Android framework, kept for FlutterActivity compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickNoteAttachmentRequest) return
        val pending = pendingNoteAttachmentPick ?: return
        pendingNoteAttachmentPick = null
        if (resultCode != Activity.RESULT_OK) {
            pending.success(null)
            return
        }
        val uri = data?.data
        if (uri == null) {
            pending.success(null)
            return
        }
        runCatching {
            val flags = data.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION
            if (flags != 0) {
                contentResolver.takePersistableUriPermission(uri, flags)
            }
        }
        pending.success(
            mapOf(
                "uri" to uri.toString(),
                "name" to displayNameFor(uri),
                "mimeType" to (contentResolver.getType(uri) ?: ""),
            ),
        )
    }

    private fun stopReminderRingtone() {
        runCatching {
            stopService(Intent(this, ReminderRingtoneService::class.java))
        }
    }

    private fun stopReminderRingtoneIfRequested(intent: Intent?) {
        val explicitStop = intent?.getBooleanExtra(ReminderRingtoneService.extraStopRingtone, false) == true
        if (explicitStop) {
            stopReminderRingtone()
        }
    }

    private fun duoyiDeepLinkFrom(intent: Intent?): String? {
        val uri = intent?.data ?: return null
        if (uri.scheme != "duoyi") return null
        return uri.toString()
    }

    private fun oauthDeepLinkFrom(intent: Intent?): String? {
        val raw = duoyiDeepLinkFrom(intent) ?: return null
        val uri = Uri.parse(raw)
        if (uri.host != "oauth") return null
        return uri.toString()
    }

    private fun sharedTextFrom(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_SEND) return null
        val type = intent.type ?: return null
        if (!type.startsWith("text/")) return null
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)
            ?.toString()
            ?.trim()
            ?: return null
        return text.ifEmpty { null }
    }

    private fun canRequestPinWidget(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val manager = getSystemService(AppWidgetManager::class.java)
        return manager?.isRequestPinAppWidgetSupported == true
    }

    private fun openWidgetSettings(): Boolean {
        val intent = appWidgetSettingsIntent() ?: return false
        return startSettingsActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun canOpenWidgetSettings(): Boolean {
        return appWidgetSettingsIntent() != null
    }

    private fun appWidgetSettingsIntent(): Intent? {
        val candidates = listOf(
            Intent("miui.intent.action.APP_PERM_EDITOR")
                .putExtra("extra_pkgname", packageName),
            Intent("miui.intent.action.APP_PERM_EDITOR")
                .setClassName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.permissions.PermissionsEditorActivity",
                )
                .putExtra("extra_pkgname", packageName),
            Intent("miui.intent.action.APP_PERM_EDITOR")
                .setClassName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.permissions.AppPermissionsEditorActivity",
                )
                .putExtra("extra_pkgname", packageName),
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:$packageName")),
        )
        return candidates.firstOrNull { it.resolveActivity(packageManager) != null }
    }

    private fun requestPinWidget(kind: String, styleId: String): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return "unsupported_platform"
        }
        val manager = getSystemService(AppWidgetManager::class.java)
            ?: run {
                return "unavailable"
            }
        if (!manager.isRequestPinAppWidgetSupported) {
            return "unsupported_launcher"
        }
        val pinStyle = DuoyiWidgetPinStyle.fromId(styleId)
        val provider = widgetProviderFor(kind, pinStyle.id)
            ?: run {
                return "invalid_kind"
            }
        val requestId = UUID.randomUUID().toString()
        return try {
            enableWidgetProvider(provider)
            DuoyiWidgetProviderRegistry.restoreEnabledProvidersForExistingWidgets(this)
            DuoyiWidgetProviderRegistry.requestUpdateForProvider(this, provider.className)
            val options = pinStyle.toOptions()
            Log.i(
                "DuoyiWidgetPin",
                "request requestId=$requestId kind=$kind style=${pinStyle.id} provider=${provider.className} min=${options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)}x${options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)} max=${options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH)}x${options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)}",
            )
            val callbackFlags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    PendingIntent.FLAG_MUTABLE
                } else {
                    0
                }
            val callback = PendingIntent.getBroadcast(
                this,
                requestId.hashCode(),
                Intent(this, DuoyiWidgetPinResultReceiver::class.java)
                    .putExtra(DuoyiWidgetPinResultReceiver.extraKind, kind)
                    .putExtra(DuoyiWidgetPinResultReceiver.extraStyle, pinStyle.id)
                    .putExtra(DuoyiWidgetPinResultReceiver.extraRequestId, requestId),
                callbackFlags,
            )
            if (manager.requestPinAppWidget(provider, options, callback)) {
                DuoyiWidgetProviderRegistry.rememberPendingVariantProvider(this, requestId, provider)
                "requested:$requestId"
            } else {
                Log.w("DuoyiWidgetPin", "request_blocked requestId=$requestId kind=$kind style=${pinStyle.id} provider=${provider.className}")
                DuoyiWidgetProviderRegistry.disableVariantProviderIfUnused(this, provider)
                DuoyiWidgetProviderRegistry.requestUpdateForProvider(this, provider.className)
                "confirmation_blocked"
            }
        } catch (e: SecurityException) {
            Log.w("DuoyiWidgetPin", "permission_denied requestId=$requestId kind=$kind style=${pinStyle.id} provider=${provider.className}", e)
            DuoyiWidgetProviderRegistry.disableVariantProviderIfUnused(this, provider)
            DuoyiWidgetProviderRegistry.requestUpdateForProvider(this, provider.className)
            "permission_denied"
        } catch (e: Exception) {
            Log.w("DuoyiWidgetPin", "unavailable requestId=$requestId kind=$kind style=${pinStyle.id} provider=${provider.className}", e)
            DuoyiWidgetProviderRegistry.disableVariantProviderIfUnused(this, provider)
            DuoyiWidgetProviderRegistry.requestUpdateForProvider(this, provider.className)
            "unavailable"
        }
    }

    private fun lastWidgetPinResult(requestId: String): Map<String, Any?>? {
        if (requestId.isBlank()) return null
        val prefs = getSharedPreferences(DuoyiWidgetPinResultReceiver.prefsName, Context.MODE_PRIVATE)
        if (prefs.getString(DuoyiWidgetPinResultReceiver.keyRequestId, "") != requestId) return null
        return mapOf(
            "requestId" to requestId,
            "kind" to prefs.getString(DuoyiWidgetPinResultReceiver.keyKind, ""),
            "style" to prefs.getString(DuoyiWidgetPinResultReceiver.keyStyle, ""),
            "widgetId" to prefs.getInt(DuoyiWidgetPinResultReceiver.keyWidgetId, AppWidgetManager.INVALID_APPWIDGET_ID),
            "status" to prefs.getString(DuoyiWidgetPinResultReceiver.keyStatus, ""),
            "confirmedAt" to prefs.getLong(DuoyiWidgetPinResultReceiver.keyConfirmedAt, 0L),
        )
    }

    private fun clearWidgetPinResult(requestId: String) {
        if (requestId.isBlank()) return
        val prefs = getSharedPreferences(DuoyiWidgetPinResultReceiver.prefsName, Context.MODE_PRIVATE)
        if (prefs.getString(DuoyiWidgetPinResultReceiver.keyRequestId, "") == requestId) {
            prefs.edit().clear().apply()
        }
    }

    private fun widgetProviderFor(kind: String, style: String): ComponentName? {
        return DuoyiWidgetProviderRegistry.componentFor(this, kind, style)
    }

    private fun enableWidgetProvider(provider: ComponentName) {
        packageManager.setComponentEnabledSetting(
            provider,
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )
    }

    private fun openLocationSettings(): Boolean {
        val intents = listOf(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:$packageName")),
            Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS),
        )
        return intents.any { startSettingsActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
    }

    private fun pickNoteAttachment(result: MethodChannel.Result) {
        if (pendingNoteAttachmentPick != null) {
            result.error("pick_in_progress", "已有文件选择器正在打开", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("*/*")
            .putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf("image/*", "application/pdf", "text/*", "application/*"),
            )
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            .addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        pendingNoteAttachmentPick = result
        try {
            startActivityForResult(intent, pickNoteAttachmentRequest)
        } catch (e: Exception) {
            pendingNoteAttachmentPick = null
            result.error("pick_failed", "无法打开系统文件选择器: ${e.message}", null)
        }
    }

    private fun displayNameFor(uri: Uri): String {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) {
                        val name = cursor.getString(index)
                        if (!name.isNullOrBlank()) return name
                    }
                }
            }
        return uri.lastPathSegment ?: "附件"
    }

    private fun openAppNotificationSettings(): Boolean {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:$packageName"))
        }.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return startSettingsActivity(intent)
    }

    private fun openNotificationChannelSettings(channelId: String?): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || channelId.isNullOrBlank()) {
            return openAppNotificationSettings()
        }
        val intent = Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            .putExtra(Settings.EXTRA_CHANNEL_ID, channelId)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return startSettingsActivity(intent)
    }

    private fun notificationChannelStatuses(channelIds: List<String>): Map<String, Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return emptyMap()
        val manager = notificationManager()
        return channelIds
            .filter { it.isNotBlank() }
            .associateWith { channelId ->
                val channel = manager.getNotificationChannel(channelId)
                mapOf(
                    "exists" to (channel != null),
                    "importance" to channel?.importance,
                    "hasSound" to (channel?.sound != null),
                    "canBypassDnd" to channel?.canBypassDnd(),
                )
            }
    }

    private fun systemAudioStatus(): Map<String, Any?> {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val manager = notificationManager()
        return mapOf(
            "alarmVolume" to audio.getStreamVolume(AudioManager.STREAM_ALARM),
            "alarmMaxVolume" to audio.getStreamMaxVolume(AudioManager.STREAM_ALARM),
            "notificationVolume" to audio.getStreamVolume(AudioManager.STREAM_NOTIFICATION),
            "notificationMaxVolume" to audio.getStreamMaxVolume(AudioManager.STREAM_NOTIFICATION),
            "ringVolume" to audio.getStreamVolume(AudioManager.STREAM_RING),
            "ringMaxVolume" to audio.getStreamMaxVolume(AudioManager.STREAM_RING),
            "dndSupported" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M),
            "interruptionFilter" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                manager.currentInterruptionFilter
            } else {
                null
            },
            "notificationPolicyAccessGranted" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                manager.isNotificationPolicyAccessGranted
            } else {
                false
            },
        )
    }

    private fun notificationManager(): NotificationManager {
        return getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    }

    private fun hasNotificationPolicyAccess(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        return notificationManager().isNotificationPolicyAccessGranted
    }

    private fun focusDndStatus(): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return mapOf(
                "supported" to false,
                "accessGranted" to false,
                "currentFilter" to null,
            )
        }
        val manager = notificationManager()
        return mapOf(
            "supported" to true,
            "accessGranted" to manager.isNotificationPolicyAccessGranted,
            "currentFilter" to manager.currentInterruptionFilter,
        )
    }

    private fun openNotificationPolicyAccessSettings(): Boolean {
        val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return startSettingsActivity(intent)
    }

    private fun enableFocusDnd(filter: Int): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return mapOf(
                "enabled" to false,
                "previousFilter" to null,
                "currentFilter" to null,
            )
        }
        val manager = notificationManager()
        if (!hasNotificationPolicyAccess()) {
            return mapOf(
                "enabled" to false,
                "previousFilter" to manager.currentInterruptionFilter,
                "currentFilter" to manager.currentInterruptionFilter,
            )
        }
        val previousFilter = manager.currentInterruptionFilter
        manager.setInterruptionFilter(filter)
        return mapOf(
            "enabled" to true,
            "previousFilter" to previousFilter,
            "currentFilter" to manager.currentInterruptionFilter,
        )
    }

    private fun restoreFocusDnd(previousFilter: Int): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        if (!hasNotificationPolicyAccess()) return false
        notificationManager().setInterruptionFilter(previousFilter)
        return true
    }

    private fun hasUsageStatsAccess(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return false
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName,
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName,
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun foregroundPackageName(): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return null
        if (!hasUsageStatsAccess()) return null
        val manager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val end = System.currentTimeMillis()
        val start = end - 10 * 60 * 1000L
        val stats = manager.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, start, end)
        return stats
            ?.filter { it.lastTimeUsed > 0 }
            ?.maxByOrNull { it.lastTimeUsed }
            ?.packageName
    }

    private fun openUsageAccessSettings(): Boolean {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return startSettingsActivity(intent)
    }

    private fun openAccessibilitySettings(): Boolean {
        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return startSettingsActivity(intent)
    }

    private fun installedLaunchableApps(): List<Map<String, Any?>> {
        val intent = Intent(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
        val resolved = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.queryIntentActivities(
                intent,
                PackageManager.ResolveInfoFlags.of(0L),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(intent, 0)
        }
        val seen = HashSet<String>()
        val apps = ArrayList<Map<String, Any?>>()
        for (info in resolved.orEmpty()) {
            val activityInfo = info.activityInfo ?: continue
            val appPackage = activityInfo.packageName ?: continue
            if (appPackage == packageName || !seen.add(appPackage)) continue
            val appInfo = activityInfo.applicationInfo
            val rawLabel = if (appInfo == null) {
                ""
            } else {
                runCatching {
                    appInfo.loadLabel(packageManager).toString().trim()
                }.getOrDefault("")
            }
            apps.add(
                mapOf(
                    "label" to rawLabel.ifEmpty { appPackage },
                    "packageName" to appPackage,
                    "isSystemApp" to (
                        appInfo != null &&
                            (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
                    ),
                ),
            )
        }
        return apps.sortedBy { it["label"].toString().lowercase() }
    }

    private fun hasFocusBlockerAccessibilityAccess(): Boolean {
        val expected = ComponentName(
            this,
            DuoyiFocusBlockerAccessibilityService::class.java,
        ).flattenToString()
        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        return enabledServices.split(':').any { it.equals(expected, ignoreCase = true) }
    }

    private fun startSettingsActivity(intent: Intent): Boolean {
        return try {
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    @Throws(IOException::class)
    private fun prepareApkForInstall(source: File): File {
        val updateDir = File(cacheDir, "updates")
        if (!updateDir.exists() && !updateDir.mkdirs()) {
            throw IOException("无法创建更新缓存目录")
        }

        val safeName = source.name.replace(Regex("[^A-Za-z0-9._-]"), "_")
            .ifBlank { "duoyi-update.apk" }
        val target = File(updateDir, safeName)
        val sourceCanonical = source.canonicalFile
        val targetCanonical = target.canonicalFile
        if (sourceCanonical.path == targetCanonical.path) {
            return targetCanonical
        }

        sourceCanonical.inputStream().use { input ->
            targetCanonical.outputStream().use { output ->
                input.copyTo(output)
            }
        }
        return targetCanonical
    }
}
