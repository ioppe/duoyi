package com.duoyi.duoyi

import android.app.Activity
import android.app.DownloadManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

/**
 * 应用更新包的系统后台下载。
 *
 * 设计约束：
 * - 只接受 http/https 地址，拒绝 file/content 等本地输入；
 * - 只下载 `.apk` 到应用私有 externalFiles 目录，不申请存储权限；
 * - 下载由系统 DownloadManager 的独立进程完成，Flutter/Activity 退出后继续；
 * - 本应用只查询/取消自己持久化的那一个 downloadId；
 * - 下载完成只发通知，不自动拉起安装器，安装由用户点击触发。
 */
object AndroidUpdateDownloads {
    const val actionInstallDownloadedUpdate = "com.duoyi.duoyi.action.INSTALL_DOWNLOADED_UPDATE"
    const val extraDownloadId = "duoyi_update_download_id"

    private const val tag = "DuoyiUpdateDownload"
    private const val prefsName = "duoyi_app_update_download"
    private const val downloadSubDir = "duoyi_updates"
    private const val defaultChannelId = "duoyi_app_update"
    private const val notificationId = 7307
    private const val apkMimeType = "application/vnd.android.package-archive"

    private const val keyDownloadId = "download_id"
    private const val keyUrl = "url"
    private const val keyVersionName = "version_name"
    private const val keyVersionCode = "version_code"
    private const val keyFileName = "file_name"
    private const val keyAccentColor = "accent_color"
    private const val keyTitle = "notification_title"
    private const val keyText = "notification_text"
    private const val keyActionLabel = "install_action_label"
    private const val keyChannelName = "channel_name"
    private const val keyChannelDescription = "channel_description"
    private const val keyPendingInstallId = "pending_install_id"

    private val allowedFileName = Regex("^[A-Za-z0-9._-]+$")

    /** 一个下载任务的快照，随 MethodChannel 返回给 Dart。 */
    private data class DownloadState(
        val downloadId: Long,
        val status: String,
        val receivedBytes: Long,
        val totalBytes: Long,
        val localPath: String?,
        val reason: String,
        val versionName: String,
        val fileName: String,
        val url: String,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "downloadId" to downloadId,
            "status" to status,
            "receivedBytes" to receivedBytes,
            "totalBytes" to if (totalBytes > 0) totalBytes else null,
            "localPath" to localPath,
            "reason" to reason,
            "versionName" to versionName,
            "fileName" to fileName,
            "url" to url,
        )
    }

    /**
     * 在 `duoyi/update` 通道里处理更新下载相关方法。
     *
     * 返回 false 表示不是本 helper 的方法，调用方应继续 `result.notImplemented()`。
     */
    fun handleMethod(
        activity: Activity,
        call: MethodCall,
        result: MethodChannel.Result,
    ): Boolean {
        return when (call.method) {
            "startBackgroundDownload" -> {
                startBackgroundDownload(activity, call, result)
                true
            }
            "queryBackgroundDownload" -> {
                result.success(queryDownload(activity)?.toMap())
                true
            }
            "cancelBackgroundDownload" -> {
                cancelDownload(activity)
                result.success(null)
                true
            }
            "installDownloadedUpdate" -> {
                result.success(installHeldDownload(activity))
                true
            }
            else -> false
        }
    }

    private fun startBackgroundDownload(
        activity: Activity,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val url = call.argument<String>("url")?.trim().orEmpty()
        val parsed = Uri.parse(url)
        val scheme = parsed.scheme?.lowercase()
        if (scheme != "http" && scheme != "https") {
            result.error("invalid_url", "只支持 http/https 下载地址", null)
            return
        }
        val active = queryDownload(activity)
        if (active != null && isActiveStatus(active.status)) {
            // 已有任务在跑：直接返回同一个任务，避免重复下载。
            result.success(active.toMap())
            return
        }
        val versionName = call.argument<String>("versionName")?.trim().orEmpty()
        val fileName = safeApkFileName(
            call.argument<String>("fileName").orEmpty(),
            versionName,
        )
        val title = call.argument<String>("notificationTitle")?.trim()
            ?.takeIf { it.isNotEmpty() } ?: "多仪"
        val text = call.argument<String>("notificationText")?.trim()
            ?.takeIf { it.isNotEmpty() } ?: "正在下载更新包"
        val actionLabel = call.argument<String>("installActionLabel")?.trim()
            ?.takeIf { it.isNotEmpty() } ?: "点击安装"
        val channelName = call.argument<String>("channelName")?.trim()
            ?.takeIf { it.isNotEmpty() } ?: defaultChannelId
        val channelDescription = call.argument<String>("channelDescription")?.trim()
            ?.takeIf { it.isNotEmpty() } ?: "应用更新包后台下载与安装提醒"
        val accentColor = when (val raw = call.argument<Any>("accentColor")) {
            is Number -> raw.toInt()
            is String -> raw.toIntOrNull() ?: 0
            else -> 0
        }
        try {
            ensureDownloadDirectory(activity)
            val request = DownloadManager.Request(parsed)
                .setTitle(title)
                .setDescription(text)
                .setMimeType(apkMimeType)
                .setNotificationVisibility(
                    DownloadManager.Request.VISIBILITY_VISIBLE,
                )
                .setAllowedOverMetered(true)
                .setAllowedOverRoaming(false)
                .setDestinationInExternalFilesDir(
                    activity,
                    Environment.DIRECTORY_DOWNLOADS,
                    "$downloadSubDir/$fileName",
                )
            val downloadId = downloadManager(activity)?.enqueue(request)
                ?: throw IllegalStateException("系统下载服务不可用")
            prefs(activity).edit()
                .putLong(keyDownloadId, downloadId)
                .putString(keyUrl, url)
                .putString(keyVersionName, versionName)
                .putInt(keyVersionCode, call.argument<Number>("versionCode")?.toInt() ?: 0)
                .putString(keyFileName, fileName)
                .putInt(keyAccentColor, accentColor)
                .putString(keyTitle, title)
                .putString(keyText, text)
                .putString(keyActionLabel, actionLabel)
                .putString(keyChannelName, channelName)
                .putString(keyChannelDescription, channelDescription)
                .apply()
            val snapshot = queryDownload(activity)
            result.success(
                snapshot?.toMap() ?: mapOf(
                    "downloadId" to downloadId,
                    "status" to "pending",
                    "receivedBytes" to 0L,
                    "totalBytes" to null,
                    "localPath" to null,
                    "reason" to "",
                    "versionName" to versionName,
                    "fileName" to fileName,
                    "url" to url,
                ),
            )
        } catch (error: IllegalArgumentException) {
            result.error("invalid_request", "下载参数无效: ${error.message}", null)
        } catch (error: SecurityException) {
            result.error("download_denied", "系统拒绝创建下载任务: ${error.message}", null)
        } catch (error: Exception) {
            Log.w(tag, "enqueue update download failed", error)
            result.error("download_failed", "创建下载任务失败: ${error.message}", null)
        }
    }

    /** 只查询本应用持久化的那一个任务；没有任务返回 null。 */
    private fun queryDownload(context: Context): DownloadState? {
        val prefs = prefs(context)
        val downloadId = prefs.getLong(keyDownloadId, 0L)
        if (downloadId <= 0L) return null
        val versionName = prefs.getString(keyVersionName, "").orEmpty()
        val fileName = prefs.getString(keyFileName, "").orEmpty()
        val url = prefs.getString(keyUrl, "").orEmpty()
        val manager = downloadManager(context) ?: return null
        val cursor = try {
            manager.query(DownloadManager.Query().setFilterById(downloadId))
        } catch (error: Exception) {
            Log.w(tag, "query download $downloadId failed", error)
            null
        }
        if (cursor != null) {
            cursor.use {
                if (it.moveToFirst()) {
                    val statusCode = it.getInt(
                        it.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS),
                    )
                    val received = it.getLong(
                        it.getColumnIndexOrThrow(
                            DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR,
                        ),
                    ).coerceAtLeast(0L)
                    val total = it.getLong(
                        it.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES),
                    )
                    val localUri = it.getString(
                        it.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI),
                    )
                    val reasonCode = it.getInt(
                        it.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON),
                    )
                    val status = statusName(statusCode)
                    val path = trustedLocalPath(context, localUri)
                    return DownloadState(
                        downloadId = downloadId,
                        status = status,
                        receivedBytes = received,
                        totalBytes = total,
                        localPath = path,
                        reason = if (statusCode == DownloadManager.STATUS_FAILED) {
                            "failed:$reasonCode"
                        } else {
                            ""
                        },
                        versionName = versionName,
                        fileName = fileName,
                        url = url,
                    )
                }
            }
        }
        // 没有系统成功状态便无法确认文件写完，残留的部分文件不算下载完成。
        return DownloadState(
            downloadId = downloadId,
            status = "failed",
            receivedBytes = 0L,
            totalBytes = 0L,
            localPath = null,
            reason = "missing",
            versionName = versionName,
            fileName = fileName,
            url = url,
        )
    }

    /** 只删除本应用当前持有的任务及其文件。 */
    fun cancelDownload(context: Context) {
        val prefs = prefs(context)
        val downloadId = prefs.getLong(keyDownloadId, 0L)
        if (downloadId <= 0L) return
        try {
            downloadManager(context)?.remove(downloadId)
        } catch (error: Exception) {
            Log.w(tag, "remove download $downloadId failed", error)
        }
        expectedFile(context, prefs.getString(keyFileName, "").orEmpty())
            ?.takeIf { it.isFile }
            ?.delete()
        NotificationManagerCompat.from(context).cancel(notificationId)
        prefs.edit()
            .remove(keyDownloadId)
            .remove(keyPendingInstallId)
            .apply()
    }

    /**
     * 下载完成后的 receiver 入口：只对属于自己的 id 生效，
     * 成功后发通知（不自动安装）。
     */
    fun onDownloadComplete(context: Context, downloadId: Long) {
        val prefs = prefs(context)
        if (prefs.getLong(keyDownloadId, 0L) != downloadId || downloadId <= 0L) return
        val state = queryDownload(context) ?: return
        if (state.status != "success") return
        notifyDownloadComplete(context, state)
    }

    /**
     * 处理点击「安装通知」进入的 Intent；返回 true 表示本 helper 已消费。
     */
    fun handleInstallIntent(activity: Activity, intent: Intent?): Boolean {
        if (intent?.action != actionInstallDownloadedUpdate) return false
        val downloadId = intent.getLongExtra(extraDownloadId, 0L)
        val prefs = prefs(activity)
        if (downloadId <= 0L || prefs.getLong(keyDownloadId, 0L) != downloadId) {
            return true
        }
        if (!canInstallPackages(activity)) {
            prefs.edit().putLong(keyPendingInstallId, downloadId).apply()
            openInstallPermissionSettings(activity)
            return true
        }
        installHeldDownload(activity)
        return true
    }

    /** 授权返回后调用：有挂起的安装任务且已获授权时才继续安装。 */
    fun resumePendingInstallIfAllowed(activity: Activity): Boolean {
        val prefs = prefs(activity)
        val pendingId = prefs.getLong(keyPendingInstallId, 0L)
        if (pendingId <= 0L) return false
        if (!canInstallPackages(activity)) return false
        return installHeldDownload(activity)
    }

    fun canInstallPackages(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        return context.packageManager.canRequestPackageInstalls()
    }

    fun openInstallPermissionSettings(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:${context.packageName}"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(intent)
        } catch (error: Exception) {
            Log.w(tag, "open install permission settings failed", error)
        }
    }

    /** 把已下载的 APK 交给系统安装器（复用 FileProvider）。 */
    fun installHeldDownload(activity: Activity): Boolean {
        val prefs = prefs(activity)
        val fileName = prefs.getString(keyFileName, "").orEmpty()
        val file = expectedFile(activity, fileName)?.takeIf { it.isFile } ?: return false
        if (!canInstallPackages(activity)) {
            prefs.edit()
                .putLong(keyPendingInstallId, prefs.getLong(keyDownloadId, 0L))
                .apply()
            openInstallPermissionSettings(activity)
            return false
        }
        return try {
            val prepared = prepareApkForInstall(activity, file)
            val uri = FileProvider.getUriForFile(
                activity,
                "${activity.packageName}.fileprovider",
                prepared,
            )
            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, apkMimeType)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
            prefs.edit().remove(keyPendingInstallId).apply()
            true
        } catch (error: IllegalArgumentException) {
            Log.w(tag, "file provider cannot expose apk", error)
            false
        } catch (error: IOException) {
            Log.w(tag, "prepare apk for install failed", error)
            false
        } catch (error: Exception) {
            Log.w(tag, "install downloaded apk failed", error)
            false
        }
    }

    private fun notifyDownloadComplete(context: Context, state: DownloadState) {
        val prefs = prefs(context)
        val channelName = prefs.getString(keyChannelName, "").orEmpty()
            .ifEmpty { defaultChannelId }
        val channelDescription = prefs.getString(keyChannelDescription, "").orEmpty()
        ensureNotificationChannel(context, channelName, channelDescription)
        val title = prefs.getString(keyTitle, "").orEmpty().ifEmpty { "多仪" }
        val actionLabel = prefs.getString(keyActionLabel, "").orEmpty()
            .ifEmpty { "点击安装" }
        val version = state.versionName.ifEmpty { "" }
        val detail = listOf(version, state.fileName)
            .filter { it.isNotBlank() }
            .joinToString(" · ")
        val body = if (detail.isBlank()) actionLabel else "$detail\n$actionLabel"
        val contentIntent = PendingIntent.getActivity(
            context,
            notificationId,
            Intent(context, MainActivity::class.java)
                .setAction(actionInstallDownloadedUpdate)
                .putExtra(extraDownloadId, state.downloadId)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = NotificationCompat.Builder(context, defaultChannelId)
            .setSmallIcon(R.drawable.ic_stat_duoyi)
            .setContentTitle(title)
            .setContentText(detail.ifBlank { actionLabel })
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
        val accent = prefs.getInt(keyAccentColor, 0)
        if (accent != 0) {
            builder.setColor(accent)
        }
        val notification = builder.build()
        val manager = NotificationManagerCompat.from(context)
        if (!manager.areNotificationsEnabled()) {
            // 通知被关闭不影响下载与安装；Dart 侧仍能查询到 success。
            return
        }
        try {
            manager.notify(notificationId, notification)
        } catch (error: SecurityException) {
            Log.w(tag, "post update notification denied", error)
        }
    }

    private fun ensureNotificationChannel(
        context: Context,
        name: String,
        description: String,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
            ?: return
        val channel = NotificationChannel(
            defaultChannelId,
            name,
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            this.description = description
            setShowBadge(false)
            enableVibration(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun downloadManager(context: Context): DownloadManager? =
        context.getSystemService(DownloadManager::class.java)

    private fun prefs(context: Context) =
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)

    private fun isActiveStatus(status: String): Boolean =
        status == "pending" || status == "running" || status == "paused"

    private fun statusName(code: Int): String = when (code) {
        DownloadManager.STATUS_PENDING -> "pending"
        DownloadManager.STATUS_RUNNING -> "running"
        DownloadManager.STATUS_PAUSED -> "paused"
        DownloadManager.STATUS_SUCCESSFUL -> "success"
        DownloadManager.STATUS_FAILED -> "failed"
        else -> "unknown"
    }

    private fun downloadDirectory(context: Context): File {
        val base = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: File(context.filesDir, "downloads")
        return File(base, downloadSubDir)
    }

    private fun ensureDownloadDirectory(context: Context): File {
        val dir = downloadDirectory(context)
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    private fun safeApkFileName(requested: String, versionName: String): String {
        val cleaned = requested.trim().replace(Regex("[^A-Za-z0-9._-]"), "_")
            .trimStart('.')
            .take(96)
        val base = when {
            cleaned.isEmpty() -> {
                val version = versionName.trim().replace(Regex("[^A-Za-z0-9._-]"), "_")
                if (version.isEmpty()) "duoyi-update.apk" else "duoyi-$version.apk"
            }
            cleaned.endsWith(".apk", ignoreCase = true) -> cleaned
            else -> "$cleaned.apk"
        }
        return if (allowedFileName.matches(base)) base else "duoyi-update.apk"
    }

    private fun expectedFile(context: Context, fileName: String): File? {
        if (fileName.isBlank() || !allowedFileName.matches(fileName)) return null
        val dir = downloadDirectory(context)
        return try {
            val file = File(dir, fileName).canonicalFile
            if (file.parentFile?.canonicalPath != dir.canonicalFile.path) return null
            file
        } catch (error: IOException) {
            Log.w(tag, "resolve update file failed", error)
            null
        }
    }

    /** 只信任落在本应用下载目录里的 local uri。 */
    private fun trustedLocalPath(context: Context, localUri: String?): String? {
        val raw = localUri?.trim().orEmpty()
        if (raw.isEmpty()) return null
        val uri = Uri.parse(raw)
        if (uri.scheme != "file") return null
        val path = uri.path ?: return null
        return try {
            val dir = downloadDirectory(context).canonicalFile
            val file = File(path).canonicalFile
            if (!file.isFile) return null
            if (file.parentFile?.canonicalPath != dir.path) return null
            file.absolutePath
        } catch (error: IOException) {
            null
        }
    }

    @Throws(IOException::class)
    private fun prepareApkForInstall(context: Context, source: File): File {
        val updateDir = File(context.cacheDir, "updates")
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
