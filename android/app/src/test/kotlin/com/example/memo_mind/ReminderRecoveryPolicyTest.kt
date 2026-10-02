package com.example.memo_mind

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class ReminderRecoveryPolicyTest {
    private val now = Instant.parse("2026-10-02T02:00:00Z").toEpochMilli()

    @Test fun rejectsMissedAndExactlyNowAlarms() {
        assertFalse(ReminderRecoveryPolicy.isFuture("2026-10-02T08:59:00", "Asia/Ho_Chi_Minh", now))
        assertFalse(ReminderRecoveryPolicy.isFuture("2026-10-02T09:00:00", "Asia/Ho_Chi_Minh", now))
    }

    @Test fun preservesFutureAlarmsInTheirStoredTimeZone() {
        assertTrue(ReminderRecoveryPolicy.isFuture("2026-10-02T09:01:00", "Asia/Ho_Chi_Minh", now))
        assertTrue(ReminderRecoveryPolicy.isFuture("2026-10-02T09:00:00", "America/New_York", now))
    }

    @Test fun invalidAlarmsFailClosed() {
        assertFalse(ReminderRecoveryPolicy.isFuture(null, "UTC", now))
        assertFalse(ReminderRecoveryPolicy.isFuture("broken", "UTC", now))
        assertFalse(ReminderRecoveryPolicy.isFuture("2026-10-02T09:00:00", "invalid/zone", now))
    }

    @Test fun respectsDstWhenRestoring() {
        val dstNow = Instant.parse("2026-11-01T13:59:00Z").toEpochMilli()
        assertTrue(ReminderRecoveryPolicy.isFuture("2026-11-01T09:00:00", "America/New_York", dstNow))
        assertFalse(ReminderRecoveryPolicy.isFuture("2026-11-01T09:00:00", "America/New_York", dstNow + 60000))
    }
}
