package com.towkirhs.jarcis

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONArray

/** Receives dictations from the Handy app, queues them, and gets them processed right away. */
class NoteReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val text = intent.getStringExtra("text")?.trim() ?: return
        if (text.isEmpty()) return
        NoteQueue.add(context, text)
        val app = MainActivity.live
        if (app != null) {
            app.invokeMethod("notesWaiting", null) // the open app processes it
        } else {
            BackgroundRunner.run(context, goAsync())
        }
    }
}

object NoteQueue {
    private const val FILE = "jarcis_notes"

    @Synchronized
    fun add(context: Context, text: String) {
        val p = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        val arr = JSONArray(p.getString("q", "[]"))
        arr.put(text)
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
