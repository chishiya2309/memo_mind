package com.example.memo_mind

import java.time.LocalDateTime
import java.time.ZoneId

/** One-shot reminders must never be replayed at/before now after a reboot. */
object ReminderRecoveryPolicy {
    fun isFuture(date: String?, zone: String?, nowMillis: Long): Boolean = try {
        LocalDateTime.parse(date).atZone(ZoneId.of(zone)).toInstant().toEpochMilli() > nowMillis
    } catch (_: Exception) { false }
}
