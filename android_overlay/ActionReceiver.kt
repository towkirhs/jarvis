package com.towkirhs.jarcis

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONArray

/** Handles the Done and Snooze buttons on Jarvis notifications. */
class ActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("id", -1)
        if (id < 0) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(id)
        when (intent.action) {
            ACTION_DONE -> {
                DoneQueue.add(context, if (id >= SNOOZE_OFFSET) id - SNOOZE_OFFSET else id)
                MainActivity.live?.invokeMethod("doneWaiting", null)
            }
            ACTION_SNOOZE -> {
                // A separate id, so a daily reminder's own schedule is left alone.
                val snoozeId = if (id >= SNOOZE_OFFSET) id else id + SNOOZE_OFFSET
                AlarmScheduler.schedule(
                    context,
                    snoozeId,
                    System.currentTimeMillis() + 10 * 60 * 1000L,
                    intent.getStringExtra("kind") ?: "notice",
                    intent.getStringExtra("label") ?: "Reminder",
                    false
                )
            }
        }
    }

    companion object {
        const val ACTION_DONE = "com.towkirhs.jarcis.DONE"
        const val ACTION_SNOOZE = "com.towkirhs.jarcis.SNOOZE"
        const val SNOOZE_OFFSET = 1_000_000
    }
}

/** Notification ids the person marked Done, waiting for the app to apply them. */
object DoneQueue {
    private const val FILE = "jarcis_done"

    @Synchronized
    fun add(context: Context, id: Int) {
        val p = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        val arr = JSONArray(p.getString("q", "[]"))
        arr.put(id)
        p.edit().putString("q", arr.toString()).apply()
    }

    @Synchronized
    fun take(context: Context): String {
        val p = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        val q = p.getString("q", "[]") ?: "[]"
        p.edit().putString("q", "[]").apply()
        return q
    }
}
