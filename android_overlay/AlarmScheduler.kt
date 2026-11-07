package com.towkirhs.jarcis

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import org.json.JSONObject
import java.util.Calendar

/** Short text log of scheduled (S) and fired (F) alarms, shown in Settings for debugging. */
object AlarmLog {
    private const val PREFS = "jarcis_alarm_log"

    fun add(context: Context, line: String) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val old = (prefs.getString("log", "") ?: "").split("\n").filter { it.isNotEmpty() }
        val lines = old.takeLast(199) + line
        prefs.edit().putString("log", lines.joinToString("\n")).commit()
    }

    fun read(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("log", "") ?: ""
}

/**
 * Keeps every pending alarm and notice in SharedPreferences so they can be re-armed after a reboot
 * or an app update. kind "alarm" rings as an alarm clock; kind "notice" is a quiet reminder; kind "clock" is an
 * alarm from the Clock page: it rings with RingService and repeats on its weekdays ([days], Monday = bit 0).
 */
object AlarmScheduler {
    private const val PREFS = "jarcis_alarms"
    private const val DAY = 24L * 60 * 60 * 1000

    private fun load(context: Context): JSONObject =
        JSONObject(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("alarms", "{}") ?: "{}")

    private fun save(context: Context, all: JSONObject) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("alarms", all.toString()).commit()
    }

    fun entry(context: Context, id: Int): JSONObject? = load(context).optJSONObject(id.toString())

    fun remove(context: Context, id: Int) {
        val all = load(context)
        all.remove(id.toString())
        save(context, all)
    }

    fun schedule(
        context: Context, id: Int, millis: Long, kind: String, label: String, repeatDaily: Boolean,
        days: Int = 0, sound: String? = null
    ) {
        val all = load(context)
        all.put(
            id.toString(),
            JSONObject().put("millis", millis).put("kind", kind).put("label", label).put("repeat", repeatDaily)
                .put("days", days).put("sound", sound ?: "")
        )
        save(context, all)
        arm(context, id, millis, kind)
        AlarmLog.add(context, "S|$id|$millis|$kind|${label.replace("\n", " ").replace("|", "/")}")
    }

    fun cancel(context: Context, id: Int) {
        remove(context, id)
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pending = PendingIntent.getBroadcast(
            context, id, Intent(context, AlarmReceiver::class.java),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        )
        if (pending != null) {
            manager.cancel(pending)
            pending.cancel()
        }
    }

    fun rearmAll(context: Context) {
        val all = load(context)
        val now = System.currentTimeMillis()
        for (key in all.keys().asSequence().toList()) {
            val e = all.getJSONObject(key)
            var millis = e.getLong("millis")
            if (millis <= now) {
                val days = e.optInt("days", 0)
                if (days != 0) {
                    millis = nextOnDays(millis, days)
                    e.put("millis", millis)
                    arm(context, key.toInt(), millis, e.getString("kind"))
                    continue
                }
                if (!e.getBoolean("repeat")) {
                    all.remove(key)
                    continue
                }
                while (millis <= now) millis += DAY
                e.put("millis", millis)
            }
            arm(context, key.toInt(), millis, e.getString("kind"))
        }
        save(context, all)
    }

    fun nextDaily(millis: Long): Long {
        var next = millis
        val now = System.currentTimeMillis()
        while (next <= now) next += DAY
        return next
    }

    /** The next time after now at the same clock time as [millis], on one of the weekdays in [mask]. */
    fun nextOnDays(millis: Long, mask: Int): Long {
        val now = Calendar.getInstance()
        val c = Calendar.getInstance().apply { timeInMillis = millis }
        c.set(now.get(Calendar.YEAR), now.get(Calendar.MONTH), now.get(Calendar.DAY_OF_MONTH))
        repeat(9) {
            val bit = (c.get(Calendar.DAY_OF_WEEK) + 5) % 7 // Monday = 0 … Sunday = 6
            if (c.timeInMillis > now.timeInMillis && (mask shr bit) and 1 == 1) return c.timeInMillis
            c.add(Calendar.DAY_OF_MONTH, 1)
        }
        return c.timeInMillis
    }

    private fun arm(context: Context, id: Int, millis: Long, kind: String) {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val fire = PendingIntent.getBroadcast(
            context, id, Intent(context, AlarmReceiver::class.java).putExtra("id", id),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        if (kind == "alarm" || kind == "clock") {
            val show = PendingIntent.getActivity(
                context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE
            )
            try {
                manager.setAlarmClock(AlarmManager.AlarmClockInfo(millis, show), fire)
            } catch (e: SecurityException) {
                manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, millis, fire)
            }
        } else {
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, millis, fire)
        }
    }
}
