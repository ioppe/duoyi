package com.duoyi.duoyi

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 系统启用列表的组件名匹配：全名与 `.Cls` 短名都必须命中。
 *
 * 复现真机（小米 Android 16）写入的短名条目，避免“设置里已开启”被判成未授权。
 */
class FocusBlockerComponentsTest {

    private val pkg = "com.duoyi.duoyi"
    private val cls = "com.duoyi.duoyi.DuoyiFocusBlockerAccessibilityService"

    @Test
    fun shortClassNameEntryMatches() {
        val raw = "com.duoyi.duoyi/.DuoyiFocusBlockerAccessibilityService"
        assertTrue(FocusBlockerComponents.matches(raw, pkg, cls))
    }

    @Test
    fun fullyQualifiedEntryMatches() {
        val raw = "com.duoyi.duoyi/com.duoyi.duoyi.DuoyiFocusBlockerAccessibilityService"
        assertTrue(FocusBlockerComponents.matches(raw, pkg, cls))
    }

    @Test
    fun colonSeparatedListMatchesAnyEntry() {
        val raw = "com.android.talkback/.TalkBackService:com.duoyi.duoyi/.DuoyiFocusBlockerAccessibilityService"
        assertTrue(FocusBlockerComponents.matches(raw, pkg, cls))
    }

    @Test
    fun entriesWithSurroundingSpacesStillMatch() {
        val raw = " com.duoyi.duoyi / .DuoyiFocusBlockerAccessibilityService "
        assertTrue(FocusBlockerComponents.matches(raw, pkg, cls))
    }

    @Test
    fun sameClassNameFromAnotherPackageDoesNotMatch() {
        val raw = "com.example.other/.DuoyiFocusBlockerAccessibilityService"
        assertFalse(FocusBlockerComponents.matches(raw, pkg, cls))
    }

    @Test
    fun missingOrEmptySettingDoesNotMatch() {
        assertFalse(FocusBlockerComponents.matches(null, pkg, cls))
        assertFalse(FocusBlockerComponents.matches("", pkg, cls))
        assertFalse(FocusBlockerComponents.matches(":", pkg, cls))
    }

    @Test
    fun malformedEntriesAreIgnoredWithoutThrowing() {
        val raw = "garbage-entry:com.duoyi.duoyi/:com.duoyi.duoyi/.DuoyiFocusBlockerAccessibilityService"
        assertTrue(FocusBlockerComponents.matches(raw, pkg, cls))
        assertNull(FocusBlockerComponents.splitEntry("no-slash"))
        assertNull(FocusBlockerComponents.splitEntry("pkg/"))
        assertNull(FocusBlockerComponents.splitEntry("/cls"))
        assertEquals("a" to "b", FocusBlockerComponents.splitEntry("a/b"))
    }

    @Test
    fun normalizeClassNameExpandsShortNameOnly() {
        assertEquals(
            "com.duoyi.duoyi.SomeService",
            FocusBlockerComponents.normalizeClassName(".SomeService", "com.duoyi.duoyi"),
        )
        assertEquals(
            "com.duoyi.duoyi.SomeService",
            FocusBlockerComponents.normalizeClassName("com.duoyi.duoyi.SomeService", pkg),
        )
        assertEquals("", FocusBlockerComponents.normalizeClassName("  ", pkg))
    }
}
