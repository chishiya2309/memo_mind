package com.example.memo_mind

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver
import com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver
import org.json.JSONArray

/** Plugin 22.3.1 restores one-shot alarms in the past, causing a burst on boot.
 * Prune only FR16's reserved IDs before delegating to the plugin. Keep this
 * cache contract covered by the Android reboot check when upgrading the plugin.
 */
class SafeReminderBootReceiver : ScheduledNotificationBootReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in setOf(Intent.ACTION_BOOT_COMPLETED,
                Intent.ACTION_MY_PACKAGE_REPLACED, "android.intent.action.QUICKBOOT_POWERON",
                "com.htc.intent.action.QUICKBOOT_POWERON")) return
        try {
            val key = "scheduled_notifications"
            val cache = context.getSharedPreferences(key, Context.MODE_PRIVATE)
            val stored = JSONArray(cache.getString(key, "[]") ?: "[]")
            val retained = JSONArray()
            val now = System.currentTimeMillis()
            for (index in 0 until stored.length()) {
                val entry = stored.getJSONObject(index)
                val id = entry.optInt("id", -1)
                val managed = id >= 160000000 && id < 260000000
                val future = !managed || ReminderRecoveryPolicy.isFuture(
                    entry.optString("scheduledDateTime"), entry.optString("timeZoneName"), now)
                if (future) {
                    retained.put(entry)
                } else {
                    val alarm = PendingIntent.getBroadcast(context, id,
                        Intent(context, ScheduledNotificationReceiver::class.java),
                        PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)
                    if (alarm != null) {
                        (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(alarm)
                        alarm.cancel()
                    }
                }
            }
            if (cache.edit().putString(key, retained.toString()).commit()) {
                super.onReceive(context, intent)
            }
        } catch (error: Exception) {
            // Fail closed: reopening the app repairs future alarms from SQLite.
            Log.e("MemoMindReminders", "Reminder recovery deferred until app launch", error)
        }
    }
}
