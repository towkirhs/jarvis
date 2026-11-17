package com.towkirhs.jarcis

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONArray
import org.json.JSONObject

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
            ACTION_CHECK -> {
                val answer = intent.getStringExtra("a") ?: "done"
                val text = RemoteInput.getResultsFromIntent(intent)?.getCharSequence(CheckNote.KEY_TEXT)?.toString()
                // "15 more minutes" asks again then, even if Jarvis is closed.
                if (answer == "more") {
                    AlarmScheduler.schedule(
                        context, id, System.currentTimeMillis() + 15 * 60 * 1000L, "checkin", intent.getStringExtra("label") ?: "", false
                    )
                }
                CheckQueue.add(context, id - CheckNote.BASE, answer, text)
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
        const val ACTION_CHECK = "com.towkirhs.jarcis.CHECK"
        const val SNOOZE_OFFSET = 1_000_000_000
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

/** "Finished Study?" at the end of a planned block: Done, 15 more min, or Skipped / what you did instead. */
object CheckNote {
    const val BASE = 1_400_000_000
    const val KEY_TEXT = "check_text"
    private const val CHANNEL = "checkin"

    fun show(context: Context, id: Int, title: String) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "Check-ins", NotificationManager.IMPORTANCE_DEFAULT))
        fun act(answer: String, k: Int, mutable: Boolean = false): PendingIntent = PendingIntent.getBroadcast(
            context,
            700_000_000 + (id - BASE) % 50_000_000 * 4 + k,
            Intent(context, ActionReceiver::class.java).setAction(ActionReceiver.ACTION_CHECK)
                .putExtra("id", id).putExtra("a", answer).putExtra("label", title),
            PendingIntent.FLAG_UPDATE_CURRENT or (if (mutable) PendingIntent.FLAG_MUTABLE else PendingIntent.FLAG_IMMUTABLE)
        )
        val input = RemoteInput.Builder(KEY_TEXT)
            .setLabel("Skipped, or what you did instead")
            .setChoices(arrayOf("Skipped"))
            .build()
        val open = PendingIntent.getActivity(context, 8, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val n = Notification.Builder(context, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("Finished $title?")
            .setContentText("Your planned time for it is up.")
            .setCategory(Notification.CATEGORY_REMINDER)
            .setContentIntent(open)
            .setAutoCancel(true)
            .addAction(Notification.Action.Builder(null, "Done", act("done", 0)).build())
            .addAction(Notification.Action.Builder(null, "15 more min", act("more", 1)).build())
            .addAction(Notification.Action.Builder(null, "Skipped / other", act("other", 2, true)).addRemoteInput(input).build())
            .build()
        manager.notify(id, n)
    }
}

/** Check-in answers waiting for the app: {nid, a, text, at}. */
object CheckQueue {
    private const val FILE = "jarcis_checks"

    @Synchronized
    fun add(context: Context, nid: Int, answer: String, text: String?) {
        val p = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        val arr = JSONArray(p.getString("q", "[]"))
        arr.put(JSONObject().put("nid", nid).put("a", answer).put("text", text ?: "").put("at", System.currentTimeMillis()))
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
