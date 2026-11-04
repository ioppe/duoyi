package com.duoyi.duoyi

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.accessibility.AccessibilityEvent

/**
 * 严格专注拦截：检测到配置的分心应用进入前台时，把用户拉回多仪的专注页。
 *
 * 只用显式 `MainActivity` + `duoyi://tab/focus` 深链，不做 `performGlobalAction`
 * 循环、不需要悬浮窗权限。失败必须留日志，且只重试一次（有界）。
 */
class DuoyiFocusBlockerAccessibilityService : AccessibilityService() {
    private val retryHandler = Handler(Looper.getMainLooper())
    private var lastBouncePackage: String? = null
    private var lastBounceAt: Long = 0L
    private var retryScheduledPackage: String? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        // 冷启动/系统重连时清理过期拦截配置：进程死后不得永久拦截。
        val cleared = FocusBlockerStore.clearIfExpired(this)
        Log.i(
            tag,
            "focus blocker service connected; cleared expired=${cleared}," +
                " enabled=${FocusBlockerStore.isConfigured(this)}",
        )
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val eventType = event?.eventType
        if (eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            eventType != AccessibilityEvent.TYPE_WINDOWS_CHANGED
        ) {
            return
        }
        val blockedPackage = event?.packageName?.toString() ?: return
        if (blockedPackage == packageName) return
        if (!FocusBlockerStore.isBlocked(this, blockedPackage)) return
        if (isDuplicateBounce(blockedPackage)) return
        FocusBlockerStore.recordBlockedPackage(this, blockedPackage)
        bounceToFocus(blockedPackage, attempt = 0)
    }

    override fun onInterrupt() = Unit

    override fun onDestroy() {
        retryHandler.removeCallbacksAndMessages(null)
        retryScheduledPackage = null
        super.onDestroy()
    }

    /** 拉回多仪并进入专注页；失败记录原因并最多重试一次。 */
    private fun bounceToFocus(blockedPackage: String, attempt: Int) {
        val intent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra("duoyi_focus_blocked_package", blockedPackage)
            .setData(
                Uri.Builder()
                    .scheme("duoyi")
                    .authority("tab")
                    .appendPath("focus")
                    .appendQueryParameter("blocked", blockedPackage)
                    .build(),
            )
        runCatching { startActivity(intent) }
            .onSuccess {
                retryScheduledPackage = null
                Log.i(tag, "focus blocker bounced $blockedPackage to focus tab")
            }
            .onFailure { error ->
                Log.w(tag, "focus blocker bounce failed for $blockedPackage", error)
                if (attempt < maxBounceAttempts - 1) scheduleBounceRetry(blockedPackage, attempt)
            }
    }

    private fun scheduleBounceRetry(blockedPackage: String, attempt: Int) {
        if (retryScheduledPackage == blockedPackage) return
        retryScheduledPackage = blockedPackage
        retryHandler.postDelayed(
            {
                retryScheduledPackage = null
                if (FocusBlockerStore.isBlocked(this, blockedPackage)) {
                    bounceToFocus(blockedPackage, attempt + 1)
                }
            },
            bounceRetryDelayMillis,
        )
    }

    private fun isDuplicateBounce(blockedPackage: String): Boolean {
        val now = SystemClock.elapsedRealtime()
        val duplicate = blockedPackage == lastBouncePackage &&
            now - lastBounceAt < bounceDebounceMillis
        lastBouncePackage = blockedPackage
        lastBounceAt = now
        return duplicate
    }

    companion object {
        private const val tag = "DuoyiFocusBlocker"
        private const val bounceDebounceMillis = 1500L
        private const val bounceRetryDelayMillis = 600L

        /** 首次 + 一次重试：不做无界重试。 */
        private const val maxBounceAttempts = 2
    }
}

/**
 * 原生拦截配置存储。
 *
 * 写入时同时保存有限失效时刻（[keyExpiresAt]）：进程被杀后拦截最迟在到期时
 * 自动失效，不会永久把用户挡在应用外。旧配置没有该值时视为“无过期”，
 * 由 Dart 首次同步时补写有限租约。
 */
object FocusBlockerStore {
    private const val prefsName = "duoyi_focus_blocker"
    private const val keyEnabled = "enabled"
    private const val keyPackages = "packages"
    private const val keyExpiresAt = "expires_at"
    private const val keyLastBlockedPackage = "last_blocked_package"
    private const val keyLastBlockedAt = "last_blocked_at"

    fun setConfig(context: Context, enabled: Boolean, packages: Set<String>, expiresAtMs: Long?) {
        val now = System.currentTimeMillis()
        val expiresAt = if (enabled) {
            FocusBlockerExpiry.normalizeRequested(expiresAtMs, now)
        } else {
            FocusBlockerExpiry.noExpiry
        }
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(keyEnabled, enabled)
            .putStringSet(keyPackages, packages)
            .putLong(keyExpiresAt, expiresAt)
            .apply()
    }

    fun expiresAt(context: Context): Long {
        return context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .getLong(keyExpiresAt, FocusBlockerExpiry.noExpiry)
    }

    fun isExpired(context: Context, nowMs: Long = System.currentTimeMillis()): Boolean {
        return FocusBlockerExpiry.isExpired(expiresAt(context), nowMs)
    }

    fun isConfigured(context: Context): Boolean {
        val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(keyEnabled, false)) return false
        if (prefs.getStringSet(keyPackages, emptySet()).isNullOrEmpty()) return false
        return FocusBlockerExpiry.isActive(
            prefs.getLong(keyExpiresAt, FocusBlockerExpiry.noExpiry),
            System.currentTimeMillis(),
        )
    }

    fun isBlocked(context: Context, packageName: String): Boolean {
        val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(keyEnabled, false)) return false
        if (!FocusBlockerExpiry.isActive(
                prefs.getLong(keyExpiresAt, FocusBlockerExpiry.noExpiry),
                System.currentTimeMillis(),
            )
        ) {
            return false
        }
        return prefs.getStringSet(keyPackages, emptySet())?.contains(packageName) == true
    }

    /** 冷启动清理：已过期的启用配置直接关闭并清空包集合。返回是否发生了清理。 */
    fun clearIfExpired(context: Context): Boolean {
        val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(keyEnabled, false)) return false
        val expiresAt = prefs.getLong(keyExpiresAt, FocusBlockerExpiry.noExpiry)
        if (!FocusBlockerExpiry.isExpired(expiresAt, System.currentTimeMillis())) return false
        prefs.edit()
            .putBoolean(keyEnabled, false)
            .remove(keyPackages)
            .putLong(keyExpiresAt, FocusBlockerExpiry.noExpiry)
            .apply()
        Log.i("DuoyiFocusBlocker", "expired focus blocker config cleared")
        return true
    }

    fun recordBlockedPackage(context: Context, packageName: String) {
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .edit()
            .putString(keyLastBlockedPackage, packageName)
            .putLong(keyLastBlockedAt, System.currentTimeMillis())
            .apply()
    }

    fun lastBlockedPackage(context: Context): String? {
        return context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .getString(keyLastBlockedPackage, null)
    }

    fun lastBlockedAt(context: Context): Long {
        return context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .getLong(keyLastBlockedAt, 0L)
    }
}
