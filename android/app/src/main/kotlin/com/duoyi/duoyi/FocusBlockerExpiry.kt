package com.duoyi.duoyi

/**
 * 原生拦截配置的有效期判定（纯 Kotlin，无 Android 依赖，便于 JVM 单测）。
 *
 * 语义：
 * - `expiresAtMs <= 0` 表示“无过期”，仅用于兼容升级前写入的旧配置。
 * - 到期后配置必须视为关闭，进程被杀后不会永久拦截。
 */
object FocusBlockerExpiry {

    /** 无过期标记。 */
    const val noExpiry = 0L

    /** 已过期：有明确失效时刻且当前时间不早于它。 */
    fun isExpired(expiresAtMs: Long, nowMs: Long): Boolean =
        expiresAtMs > noExpiry && nowMs >= expiresAtMs

    /** 仍然有效：无过期标记或尚未到期。 */
    fun isActive(expiresAtMs: Long, nowMs: Long): Boolean = !isExpired(expiresAtMs, nowMs)

    /**
     * 归一化 Dart 传来的失效时刻：负数/非法值按“已失效”处理（返回 [noExpiry]
     * 之外哨兵由调用方判定），避免异常值把配置变成永久有效。
     */
    fun normalizeRequested(expiresAtMs: Long?, nowMs: Long): Long {
        if (expiresAtMs == null || expiresAtMs <= noExpiry) return noExpiry
        if (nowMs >= expiresAtMs) return nowMs
        return expiresAtMs
    }
}
