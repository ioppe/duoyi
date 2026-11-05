package com.duoyi.duoyi

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 系统下载完成广播入口。
 *
 * 只在 DownloadManager 报告的 id 与本应用持久化的 id 一致时才发通知；
 * 不发通知以外的动作，绝不从后台自动拉起安装器。
 *
 * 需要在 AndroidManifest.xml 中声明（由主会话统一 glue）：
 *
 * ```xml
 * <receiver
 *     android:name=".AndroidUpdateDownloadReceiver"
 *     android:exported="true">
 *     <intent-filter>
 *         <action android:name="android.intent.action.DOWNLOAD_COMPLETE" />
 *     </intent-filter>
 * </receiver>
 * ```
 */
class AndroidUpdateDownloadReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != DownloadManager.ACTION_DOWNLOAD_COMPLETE) return
        val downloadId = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, 0L)
        if (downloadId <= 0L) return
        runCatching {
            AndroidUpdateDownloads.onDownloadComplete(
                context.applicationContext,
                downloadId,
            )
        }.onFailure { error ->
            Log.w(tag, "handle download complete $downloadId failed", error)
        }
    }

    companion object {
        private const val tag = "DuoyiUpdateDownload"
    }
}
