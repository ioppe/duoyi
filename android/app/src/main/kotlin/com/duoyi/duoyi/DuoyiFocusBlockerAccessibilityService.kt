package com.duoyi.duoyi

import android.accessibilityservice.AccessibilityService
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import androidx.core.content.ContextCompat
import java.util.concurrent.Executors

/**
 * 严格专注拦截：检测到配置的分心应用进入前台时，把用户拉回多仪的专注页。
 *
 * 只用显式 `MainActivity` + `duoyi://tab/focus` 深链，不做 `performGlobalAction`
 * 循环、不需要悬浮窗权限。`startActivity` 成功只代表“已请求返回”，真实返回以
 * [FocusBlockerForegroundState] 记录的前台观察为准：每轮请求最多再验证一次并补发
 * 一次，失败留日志，不做无界重试。
 *
 * 有 window 事件时行为完全由无障碍事件决定；某些页面（如登录页）实机不产生
 * TYPE_WINDOW_STATE_CHANGED/TYPE_WINDOWS_CHANGED，此时仅在“已授予使用情况访问 +
 * 设备可交互”时用 [FocusBlockerUsageAccess] 读取 `UsageEvents` 的 type/package/time
 * 补漏，“已请求返回”与“确认返回”的判定与 AA 路径完全一致。
 */
class DuoyiFocusBlockerAccessibilityService : AccessibilityService() {
    private val workHandler = Handler(Looper.getMainLooper())
    private val bounceGate = FocusBlockerBounceGate(bounceDebounceMillis)

    /** generation / pending / deferred 的唯一权威（服务不保留镜像字段）。 */
    private val workState = FocusBlockerPendingWorkState()

    /** 最近一次 [isDuplicateBounce] 计算的剩余冷却（0 表示该事件已被接受）。 */
    private var lastBounceDelayMillis = 0L

    /** 当前待验证请求的序号（0 起）；目标与 generation 由 [workState] 提供。 */
    private var pendingVerificationAttempt = 0

    /** Usage 监控生命周期权威（generation / inflight / 会话起点）。 */
    private val usageMonitor = FocusBlockerUsageMonitorState()
    private val usageReducer = FocusBlockerUsageEventsReducer()
    private val usageExecutor = Executors.newSingleThreadExecutor()

    private var configReceiver: BroadcastReceiver? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        // 冷启动/系统重连时清理过期拦截配置：进程死后不得永久拦截。
        val cleared = FocusBlockerStore.clearIfExpired(this)
        Log.i(
            tag,
            "focus blocker service connected; cleared expired=${cleared}," +
                " enabled=${FocusBlockerStore.isConfigured(this)}",
        )
        // 配置启停不能依赖外部 AA 事件：先注册内部配置广播，再按当前配置启停 Usage 监控。
        registerConfigReceiver()
        syncUsageMonitor(reason = "service-connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val safeEvent = event ?: return
        val eventType = safeEvent.eventType
        if (eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            eventType != AccessibilityEvent.TYPE_WINDOWS_CHANGED
        ) {
            return
        }
        val observedPackage = safeEvent.packageName?.toString() ?: return
        val now = SystemClock.uptimeMillis()
        // AccessibilityEvent.eventTime 与 SystemClock.uptimeMillis 同基准；更旧的窗口
        // 观察不得覆盖更新的前台结论（Splash 结束后补发的旧事件是典型来源）。
        val observedAt = FocusBlockerWindowTracker.normalizeObservedAt(safeEvent.eventTime.toLong(), now)
        if (!FocusBlockerForegroundState.observeForeground(observedPackage, observedAt, now)) {
            return
        }
        if (observedPackage == packageName) {
            // 只有本应用真的成为前台才算确认返回；AA 或 MainActivity 的观察都走这里。
            confirmPendingReturn()
            return
        }
        if (!FocusBlockerStore.isBlocked(this, observedPackage)) {
            // 用户切到白名单应用（微信/QQ 等）或配置已停用/过期：完整取消旧的拉回等待，
            // 并留下“被哪个窗口、因何取消”的诊断信息，已发出的 requested 不会无声消失。
            cancelAllWork(reason = "nonblocked-window", observedPackage = observedPackage)
            return
        }
        if (isDuplicateBounce(observedPackage, now)) {
            // 冷却期内重复事件只排队一次固定截止时刻的复查：不推进冷却、不重复记拦截事件。
            scheduleDeferredCheck(observedPackage, now + lastBounceDelayMillis)
            return
        }
        startBounceCycle(observedPackage, recordDetection = true)
    }

    override fun onInterrupt() {
        Log.i(tag, "focus blocker service interrupted")
    }

    override fun onDestroy() {
        stopUsageMonitor(reason = "service-destroyed")
        unregisterConfigReceiver()
        usageExecutor.shutdownNow()
        super.onDestroy()
    }

    /** 本应用确认为前台：日志只在这里出现 confirmed，并完整取消待执行工作。 */
    private fun confirmPendingReturn() {
        val blockedPackage = workState.pendingTargetPackage() ?: workState.deferredTargetPackage()
        if (blockedPackage != null) {
            Log.i(tag, "focus blocker confirmed return to duoyi from $blockedPackage")
        }
        cancelAllWork(reason = "own-foreground", observedPackage = packageName)
    }

    /** 新的一轮拉回：作废旧回调、按需记录一次真实拦截事件，然后发出第一个请求。 */
    private fun startBounceCycle(
        blockedPackage: String,
        recordDetection: Boolean,
        maxAttempts: Int = maxBounceAttempts,
    ) {
        workHandler.removeCallbacks(verificationCheck)
        workHandler.removeCallbacks(deferredCheck)
        pendingVerificationAttempt = 0
        val shouldRecord = workState.beginCycle(blockedPackage, recordDetection, maxAttempts)
        // 同一轮内重复检测、补发请求与 deferred 复查都不重复记账；换目标或换轮才记一次。
        if (shouldRecord) FocusBlockerStore.recordBlockedPackage(this, blockedPackage)
        requestBounce(blockedPackage, workState.generation(), attempt = 0)
    }

    /**
     * 发起一次拉回请求。
     *
     * 请求前必须重新确认配置仍有效、请求仍属于当前轮、设备确实可交互。
     */
    private fun requestBounce(blockedPackage: String, requestId: Long, attempt: Int) {
        if (!workState.isCurrent(requestId, blockedPackage)) return
        if (!FocusBlockerStore.isBlocked(this, blockedPackage)) {
            cancelAllWork(reason = "config-inactive", observedPackage = blockedPackage)
            return
        }
        // 息屏/锁屏时绝不拉起：设备不可用时完整取消，绝不唤醒或绕过锁屏。
        if (!FocusBlockerUsageAccess.isDeviceAwakeAndUnlocked(this)) {
            cancelAllWork(reason = "device-unavailable", observedPackage = blockedPackage)
            return
        }
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
                // 成功只代表请求已交给系统，绝不等于用户已回到专注页。
                Log.i(
                    tag,
                    "focus blocker requested $blockedPackage to focus tab" +
                        " (attempt ${attempt + 1}/${workState.attemptLimit()}), awaiting confirmation",
                )
                scheduleReturnVerification(blockedPackage, requestId, attempt)
            }
            .onFailure { error ->
                Log.w(tag, "focus blocker bounce failed for $blockedPackage", error)
                scheduleReturnVerification(blockedPackage, requestId, attempt)
            }
    }

    /** 有界验证排程：最多一次，目标是“请求后真的回到本应用或被拦截应用仍在”。 */
    private fun scheduleReturnVerification(blockedPackage: String, requestId: Long, attempt: Int) {
        if (!workState.isCurrent(requestId, blockedPackage)) return
        pendingVerificationAttempt = attempt
        workHandler.removeCallbacks(verificationCheck)
        workHandler.postDelayed(verificationCheck, bounceRetryDelayMillis)
    }

    /**
     * 验证回调：确认返回、补发一次或收敛本轮。
     *
     * 每次都重新读取配置与进程内前台观察：切到允许应用/本应用时绝不抢占；
     * 补发受本轮 attempt limit（AA 默认 2、Usage 来源 1）约束，不进行无限验证或无限重试。
     */
    private val verificationCheck = Runnable {
        val blockedPackage = workState.pendingTargetPackage() ?: return@Runnable
        val requestId = workState.generation()
        if (!workState.isCurrent(requestId, blockedPackage)) return@Runnable
        val attempt = pendingVerificationAttempt
        val foreground = FocusBlockerForegroundState.foregroundPackageName()
        val blockingActive = FocusBlockerStore.isBlocked(this, blockedPackage)
        when {
            foreground == packageName -> {
                Log.i(tag, "focus blocker confirmed return to duoyi from $blockedPackage")
                cancelAllWork(reason = "own-foreground", observedPackage = packageName)
            }
            FocusBlockerForegroundState.shouldRetryReturn(
                targetPackage = blockedPackage,
                foregroundPackage = foreground,
                blockingActive = blockingActive,
                attempt = attempt,
                maxAttempts = workState.attemptLimit(),
            ) -> requestBounce(blockedPackage, requestId, attempt + 1)
            !blockingActive -> cancelAllWork(reason = "config-inactive", observedPackage = blockedPackage)
            else -> {
                Log.w(
                    tag,
                    "focus blocker return unconfirmed for $blockedPackage" +
                        " (foreground=${foreground ?: "unknown"}, attempts=${attempt + 1})",
                )
                finishVerificationCycle(reason = "unconfirmed")
            }
        }
    }

    /**
     * 只结束本轮验证：移除验证回调、作废本轮 generation，但**保留**事件触发的 deferred。
     *
     * 这里不能做整体清理，否则 T1200 的 unconfirmed 会删掉 T200 排队的 T1500 复查。
     */
    private fun finishVerificationCycle(reason: String) {
        workHandler.removeCallbacks(verificationCheck)
        pendingVerificationAttempt = 0
        workState.finishVerificationCycle()
        Log.i(
            tag,
            "focus blocker verification finished: reason=$reason," +
                " deferred=${workState.deferredTargetPackage() ?: "none"}",
        )
    }

    /**
     * 冷却期内重复 AA 事件排队一次固定截止时刻的复查。
     *
     * 同一截止时刻只更换目标、不改期：armDeferred 返回 false 时说明已经排程，
     * 再次 post 会把期限推后并饿死复查。Usage 来源不排这种基于缓存包的复查。
     */
    private fun scheduleDeferredCheck(blockedPackage: String, deadlineUptimeMillis: Long) {
        if (!workState.armDeferred(blockedPackage, deadlineUptimeMillis)) return
        workHandler.removeCallbacks(deferredCheck)
        val delay = (deadlineUptimeMillis - SystemClock.uptimeMillis()).coerceAtLeast(0L)
        workHandler.postDelayed(deferredCheck, delay)
    }

    /**
     * 复查：只有“当前前台仍是该被拦截应用且仍处于拦截期”才重新拉回。
     *
     * 只有冷却期内的重复 AA 事件才会排它；启动期只有一个快速事件时没有重复事件、也就没有
     * 这次复查，它的第二次机会来自 [bounceRetryDelayMillis] 的有界验证。本回调绝不重排自己。
     */
    private val deferredCheck = Runnable {
        val blockedPackage = workState.consumeDeferred() ?: return@Runnable
        if (FocusBlockerForegroundState.foregroundPackageName() == blockedPackage &&
            FocusBlockerStore.isBlocked(this, blockedPackage) &&
            bounceGate.delayUntilAllowed(blockedPackage, SystemClock.uptimeMillis()) == 0L
        ) {
            startBounceCycle(blockedPackage, recordDetection = true)
        }
    }

    /**
     * 完整取消：本应用确认返回、允许应用在前台、配置失效或服务销毁。
     *
     * 诊断日志带上触发窗口与原因：已经发出的 requested 不能无声消失。
     */
    private fun cancelAllWork(reason: String, observedPackage: String?) {
        val pending = workState.pendingTargetPackage()
        val deferred = workState.deferredTargetPackage()
        workHandler.removeCallbacks(verificationCheck)
        workHandler.removeCallbacks(deferredCheck)
        pendingVerificationAttempt = 0
        workState.cancelAll()
        if (pending != null || deferred != null) {
            Log.i(
                tag,
                "focus blocker cancelled pending work: reason=$reason" +
                    " window=${observedPackage ?: "unknown"}" +
                    " pending=${pending ?: "none"} deferred=${deferred ?: "none"}",
            )
        }
    }

    /**
     * 保留旧包装名：内部走纯 Kotlin 固定冷却门控。
     *
     * 冷却全局生效且被拒事件**不推进**已接受时刻、不改变已接受包名，因此连续重复事件
     * 与冷却期内出现的另一个被拦截应用都不会饿死下一次真正的拉回。
     */
    private fun isDuplicateBounce(blockedPackage: String, nowUptimeMillis: Long): Boolean {
        lastBounceDelayMillis = bounceGate.delayUntilAllowed(blockedPackage, nowUptimeMillis)
        return lastBounceDelayMillis > 0L
    }

    // ---------------------------------------------------------------------------------
    // UsageEvents 前台补漏（仅在已授权“使用情况访问”且设备可交互时启用）
    // ---------------------------------------------------------------------------------

    /**
     * 500ms 一次的前台补漏轮询。
     *
     * 主 looper 每次最多一个 inflight 查询，查询本身在单线程 executor 上执行；回到主线程
     * 后再次校验 generation / 配置 / 设备状态，迟到结果不能恢复旧会话。
     */
    private val usagePoll = object : Runnable {
        override fun run() {
            if (!usageMonitor.isActive()) return
            val service = this@DuoyiFocusBlockerAccessibilityService
            if (!FocusBlockerStore.isConfigured(service)) {
                stopUsageMonitor(reason = "config-inactive")
                return
            }
            scheduleNextUsagePoll()
            // 息屏/锁屏不查询：不拉起、不改系统设置，也不会把一个不可见的读当成证据。
            if (!FocusBlockerUsageAccess.isDeviceAwakeAndUnlocked(service)) return
            if (!usageMonitor.beginQuery()) return
            val generation = usageMonitor.generation()
            val sessionStart = usageMonitor.sessionStartedAtWallMillis()
            val nowWall = System.currentTimeMillis()
            val appContext = applicationContext
            usageExecutor.execute {
                val events = runCatching {
                    FocusBlockerUsageAccess.readRecentEvents(
                        context = appContext,
                        sessionStartedAtWallMillis = sessionStart,
                        nowWallMillis = nowWall,
                    )
                }.getOrElse { error ->
                    Log.w(tag, "focus blocker usage read failed", error)
                    emptyList()
                }
                workHandler.post {
                    if (!usageMonitor.completeQuery(generation)) return@post
                    handleUsageEvents(events, generation)
                }
            }
        }
    }

    private fun scheduleNextUsagePoll() {
        workHandler.removeCallbacks(usagePoll)
        if (usageMonitor.isActive()) {
            workHandler.postDelayed(usagePoll, usagePollIntervalMillis)
        }
    }

    /**
     * 按当前配置启停 Usage 监控。
     *
     * 配置有效时重启 generation 并立即开始轮询；配置关闭/过期则停止。这里只检查是否已授予
     * 使用情况访问，不依赖 Provider 缓存，因此用户稍后在系统设置里授权后下一轮即可查询。
     */
    private fun syncUsageMonitor(reason: String) {
        if (!FocusBlockerStore.isConfigured(this)) {
            stopUsageMonitor(reason = "config-inactive:$reason")
            return
        }
        workHandler.removeCallbacks(usagePoll)
        usageReducer.reset()
        usageMonitor.start(System.currentTimeMillis())
        Log.i(
            tag,
            "focus blocker usage monitor started: reason=$reason," +
                " usageAccess=${FocusBlockerUsageAccess.hasUsageAccess(this)}",
        )
        workHandler.post(usagePoll)
    }

    /** 停止监控：移除轮询、作废 generation、丢弃去重记录，并取消待执行拉回。 */
    private fun stopUsageMonitor(reason: String) {
        workHandler.removeCallbacks(usagePoll)
        val wasActive = usageMonitor.isActive()
        usageMonitor.stop()
        usageReducer.reset()
        if (wasActive) {
            Log.i(tag, "focus blocker usage monitor stopped: reason=$reason")
        }
        cancelAllWork(reason = reason, observedPackage = null)
    }

    /**
     * 处理一批 UsageEvents 元数据。
     *
     * 只在仍属于当前会话、配置有效、已授权且设备可交互时才下判断；无新证据即返回。
     */
    private fun handleUsageEvents(
        events: List<FocusBlockerUsageObservation>,
        generation: Long,
    ) {
        if (!usageMonitor.isCurrent(generation)) return
        if (!FocusBlockerStore.isConfigured(this)) {
            stopUsageMonitor(reason = "config-inactive")
            return
        }
        if (!FocusBlockerUsageAccess.isDeviceAwakeAndUnlocked(this)) return
        if (!FocusBlockerUsageAccess.hasUsageAccess(this)) return
        // 成对采样处理时刻，worker 的耗时不能把旧事件映射成更新的前台。
        val nowWall = System.currentTimeMillis()
        val nowUptime = SystemClock.uptimeMillis()
        val verdict = usageReducer.resolve(
            events = events,
            nowWallMillis = nowWall,
            nowUptimeMillis = nowUptime,
            sessionStartedAtWallMillis = usageMonitor.sessionStartedAtWallMillis(),
        )
        when (verdict) {
            is FocusBlockerUsageVerdict.Foreground -> onUsageForeground(verdict, nowUptime)
            is FocusBlockerUsageVerdict.Loss -> onUsageLoss(verdict, nowUptime)
            FocusBlockerUsageVerdict.None -> Unit
        }
    }

    /**
     * Usage 观察到的前台包：走与 AA 完全相同的判定（tracker 先去旧、允许包立即取消、
     * 全局冷却门控、显式 MainActivity 深链）。
     *
     * Usage 来源一轮只发 1 次请求；冷却中被拒绝时**不消费**该事件，让下一次 fresh 查询
     * 在冷却结束后决定是否接受。
     */
    private fun onUsageForeground(
        verdict: FocusBlockerUsageVerdict.Foreground,
        nowUptimeMillis: Long,
    ) {
        val observedPackage = verdict.packageName
        val accepted = FocusBlockerForegroundState.observeForeground(
            observedPackage,
            verdict.observedAtUptimeMillis,
            nowUptimeMillis,
        )
        if (!accepted) {
            // 比 AA/MainActivity 已记录的观察更旧：消费掉，绝不覆盖更新的前台结论。
            usageReducer.consume(verdict)
            return
        }
        if (observedPackage == packageName) {
            confirmPendingReturn()
            usageReducer.consume(verdict)
            return
        }
        if (!FocusBlockerStore.isBlocked(this, observedPackage)) {
            cancelAllWork(reason = "nonblocked-window", observedPackage = observedPackage)
            usageReducer.consume(verdict)
            return
        }
        if (bounceGate.delayUntilAllowed(observedPackage, nowUptimeMillis) > 0L) {
            // 全局冷却中：不消费、不排 deferred；下一次 fresh 查询会重新读当前切换。
            return
        }
        usageReducer.consume(verdict)
        Log.i(
            tag,
            "focus blocker usage foreground detected: package=$observedPackage" +
                " eventAt=${verdict.decisiveAtWallMillis}",
        )
        startBounceCycle(
            blockedPackage = observedPackage,
            recordDetection = true,
            maxAttempts = usageCycleAttempts,
        )
    }

    /** Usage 观察到的明确 loss：只在 tracker 仍是该包且不旧时生效，并完整取消待执行拉回。 */
    private fun onUsageLoss(verdict: FocusBlockerUsageVerdict.Loss, nowUptimeMillis: Long) {
        val accepted = FocusBlockerForegroundState.observeForegroundLoss(
            verdict.packageName,
            verdict.observedAtUptimeMillis,
            nowUptimeMillis,
        )
        if (accepted) {
            cancelAllWork(reason = "usage-loss", observedPackage = verdict.packageName)
        }
        usageReducer.consume(verdict)
    }

    /**
     * 注册内部配置变化广播接收器（动态、不导出）。
     *
     * 广播不携带任何负载，接收器只重读本地状态；旧版本同样通过 AndroidX 的签名权限
     * 实现非导出，外部应用不能触发配置重启。
     */
    private fun registerConfigReceiver() {
        if (configReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action != FocusBlockerStore.actionConfigChanged) return
                onBlockerConfigChanged()
            }
        }
        val filter = IntentFilter(FocusBlockerStore.actionConfigChanged)
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                ContextCompat.registerReceiver(
                    this,
                    receiver,
                    filter,
                    ContextCompat.RECEIVER_NOT_EXPORTED,
                )
            }
        }.onSuccess {
            configReceiver = receiver
        }.onFailure { error ->
            Log.w(tag, "focus blocker config receiver registration failed", error)
        }
    }

    private fun unregisterConfigReceiver() {
        val receiver = configReceiver ?: return
        configReceiver = null
        runCatching { unregisterReceiver(receiver) }
            .onFailure { error ->
                Log.w(tag, "focus blocker config receiver unregister failed", error)
            }
    }

    /** 配置变化：清理过期配置、作废旧监控结果与旧拉回，再按新配置启停轮询。 */
    private fun onBlockerConfigChanged() {
        FocusBlockerStore.clearIfExpired(this)
        cancelAllWork(reason = "config-changed", observedPackage = null)
        syncUsageMonitor(reason = "config-changed")
    }

    companion object {
        private const val tag = "DuoyiFocusBlocker"
        private const val bounceDebounceMillis = 1500L
        private const val bounceRetryDelayMillis = 600L

        /** Usage 前台补漏轮询间隔；单次读取固定 5s 窗口。 */
        private const val usagePollIntervalMillis = 500L

        /** Usage 来源一轮只发 1 次请求（仍用 600ms 验证确认/记 unconfirmed）。 */
        private const val usageCycleAttempts = 1

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
    /** 内部配置变化广播：仅 setPackage 本应用，接收器不导出且不携带负载。 */
    const val actionConfigChanged = "com.duoyi.duoyi.action.FOCUS_BLOCKER_CONFIG_CHANGED"

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
        val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        // 恢复前台会重复同步同一配置；相同值不能取消返回或移动监控起点。
        if (prefs.getBoolean(keyEnabled, false) == enabled &&
            prefs.getStringSet(keyPackages, emptySet()).orEmpty() == packages &&
            prefs.getLong(keyExpiresAt, FocusBlockerExpiry.noExpiry) == expiresAt
        ) return
        prefs.edit()
            .putBoolean(keyEnabled, enabled)
            .putStringSet(keyPackages, packages)
            .putLong(keyExpiresAt, expiresAt)
            .apply()
        notifyConfigChanged(context)
    }

    /**
     * 配置写入后通知同进程的服务：启停不能依赖外部无障碍事件。
     *
     * 广播限定本应用包名且不携带负载；失败只留日志，不影响已写入的配置。
     */
    private fun notifyConfigChanged(context: Context) {
        runCatching {
            context.sendBroadcast(Intent(actionConfigChanged).setPackage(context.packageName))
        }.onFailure { error ->
            Log.w("DuoyiFocusBlocker", "focus blocker config broadcast failed", error)
        }
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
