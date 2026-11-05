package com.duoyi.duoyi

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 原生拦截配置的有效期判定：进程被杀后不得永久拦截，
 * 但升级前的旧配置（无过期值）仍按原有语义保持。
 */
class FocusBlockerExpiryTest {

    private val now = 1_700_000_000_000L

    @Test
    fun futureExpiryIsActive() {
        assertTrue(FocusBlockerExpiry.isActive(now + 60_000L, now))
        assertFalse(FocusBlockerExpiry.isExpired(now + 60_000L, now))
    }

    @Test
    fun pastExpiryIsExpired() {
        assertTrue(FocusBlockerExpiry.isExpired(now - 1L, now))
        assertFalse(FocusBlockerExpiry.isActive(now - 1L, now))
    }

    @Test
    fun boundaryAtExpiryCountsAsExpired() {
        assertTrue(FocusBlockerExpiry.isExpired(now, now))
        assertFalse(FocusBlockerExpiry.isActive(now, now))
    }

    @Test
    fun noExpiryMarkerKeepsLegacyBehaviour() {
        assertTrue(FocusBlockerExpiry.isActive(FocusBlockerExpiry.noExpiry, now))
        assertFalse(FocusBlockerExpiry.isExpired(FocusBlockerExpiry.noExpiry, now))
    }

    @Test
    fun requestedExpiryIsNormalized() {
        assertEquals(now + 1_000L, FocusBlockerExpiry.normalizeRequested(now + 1_000L, now))
        assertEquals(FocusBlockerExpiry.noExpiry, FocusBlockerExpiry.normalizeRequested(null, now))
        assertEquals(FocusBlockerExpiry.noExpiry, FocusBlockerExpiry.normalizeRequested(-5L, now))
        // 已过期请求归一化到“当下即过期”，不会变成永久有效。
        val normalized = FocusBlockerExpiry.normalizeRequested(now - 10L, now)
        assertEquals(now, normalized)
        assertTrue(FocusBlockerExpiry.isExpired(normalized, now))
    }
}
