package com.towkirhs.jarcis

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.app.RemoteInput
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.speech.RecognizerIntent
import android.widget.Toast
import org.json.JSONArray
import org.json.JSONObject

/**
 * Talking to Jarvis from notifications. Jarvis's replies show as a little chat; you answer with Reply
 * (type, or the keyboard's mic) or Speak (voice straight away). Answers go through the same pipeline as the
 * bubble, and Jarvis's next reply lands in the same chat.
 */
object Chat {
    private const val CHANNEL = "replies"
    const val ID = 2_100_000_000
    private const val FILE = "jarcis_chat"
    private const val KEY_TEXT = "reply_text"
    private const val FRESH_MS = 30 * 60 * 1000L // a chat older than this starts over

    /** Jarvis says something: add it to the chat and show it. */
    fun jarvisSays(context: Context, text: String) {
        if (text.isBlank()) return
        add(context, "jarvis", text)
        show(context, thinking = false)
    }

    /** The person answered from a notification: show it at once (so the reply spinner stops), then queue it. */
    fun personSays(context: Context, text: String, about: Int, notificationId: Int) {
        add(context, "me", text)
        if (notificationId != ID) {
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(notificationId)
        }
        show(context, thinking = true, about = about)
        NoteQueue.add(context, text, null, if (about >= 0) "reply:$about" else "reply")
    }

    @Synchronized
    private fun add(context: Context, who: String, text: String) {
        val p = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        val old = JSONArray(p.getString("h", "[]"))
        val kept = JSONArray()
        for (i in 0 until old.length()) {
            val m = old.getJSONObject(i)
            if (now - m.getLong("ts") < FRESH_MS) kept.put(m)
        }
        kept.put(JSONObject().put("who", who).put("text", text).put("ts", now))
        while (kept.length() > 8) kept.remove(0)
        p.edit().putString("h", kept.toString()).apply()
    }

    private fun history(context: Context): JSONArray =
        JSONArray(context.getSharedPreferences(FILE, Context.MODE_PRIVATE).getString("h", "[]"))

    private fun flags(mutable: Boolean): Int = PendingIntent.FLAG_UPDATE_CURRENT or when {
        mutable && Build.VERSION.SDK_INT >= 31 -> PendingIntent.FLAG_MUTABLE
        !mutable -> PendingIntent.FLAG_IMMUTABLE
        else -> 0
    }

    /** "Reply" with a text box (the keyboard's mic works there too). [about] is the item it is about, or -1. */
    fun replyAction(context: Context, about: Int, notificationId: Int): Notification.Action {
        val intent = Intent(context, ReplyReceiver::class.java)
            .putExtra("about", about)
            .putExtra("nid", notificationId)
        val pending = PendingIntent.getBroadcast(context, 40_000 + (notificationId % 1_000_000), intent, flags(true))
        val input = RemoteInput.Builder(KEY_TEXT)
            .setLabel(if (about >= 0) "Done, later, at 8 pm, cancel…" else "Answer Jarvis")
            .build()
        return Notification.Action.Builder(null, "Reply", pending).addRemoteInput(input).build()
    }

    /** "Speak": opens the phone's voice typing and sends what you say. */
    private fun speakAction(context: Context, about: Int, notificationId: Int): Notification.Action {
        val intent = Intent(context, VoiceActivity::class.java)
            .putExtra("about", about)
            .putExtra("nid", notificationId)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val pending = PendingIntent.getActivity(context, 50_000 + (notificationId % 1_000_000), intent, flags(false))
        return Notification.Action.Builder(null, "Speak", pending).build()
    }

    fun show(context: Context, thinking: Boolean, about: Int = -1) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Jarvis replies", NotificationManager.IMPORTANCE_DEFAULT)
            )
        }
        val open = PendingIntent.getActivity(
            context, 7, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL)
        else Notification.Builder(context)
        val h = history(context)
        val last = if (h.length() > 0) h.getJSONObject(h.length() - 1).getString("text") else ""
        if (Build.VERSION.SDK_INT >= 28) {
            val me = Person.Builder().setName("You").build()
            val jarvis = Person.Builder().setName("Jarvis").build()
            val style = Notification.MessagingStyle(me)
            for (i in 0 until h.length()) {
                val m = h.getJSONObject(i)
                style.addMessage(m.getString("text"), m.getLong("ts"), if (m.getString("who") == "me") me else jarvis)
            }
            if (thinking) style.addMessage("…", System.currentTimeMillis(), jarvis)
            builder.setStyle(style)
        } else {
            val text = if (thinking) "Thinking about: $last" else last
            builder.setContentTitle("Jarvis").setContentText(text).setStyle(Notification.BigTextStyle().bigText(text))
        }
        manager.notify(
            ID,
            builder.setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentIntent(open)
                .setAutoCancel(true)
                .setOnlyAlertOnce(thinking) // your own answer should not buzz; Jarvis's reply should
                .addAction(replyAction(context, about, ID))
                .addAction(speakAction(context, about, ID))
                .build()
        )
    }

    /** Hands the queued answer to Jarvis: the open app if there is one, otherwise a background run. */
    fun process(context: Context, result: BroadcastReceiver.PendingResult?) {
        val app = MainActivity.live
        if (app != null) {
            app.invokeMethod("notesWaiting", null)
            result?.finish()
        } else {
            BackgroundRunner.run(context, result)
        }
    }
}

/** A typed answer from a notification's Reply box. */
class ReplyReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val text = RemoteInput.getResultsFromIntent(intent)?.getCharSequence("reply_text")?.toString()?.trim()
        if (text.isNullOrEmpty()) return
        Chat.personSays(context, text, intent.getIntExtra("about", -1), intent.getIntExtra("nid", Chat.ID))
        Chat.process(context, goAsync())
    }
}

/** Opens the phone's voice typing, sends what was said to Jarvis, and closes. Nothing of its own is shown. */
class VoiceActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState != null) return
        val listen = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            .putExtra(RecognizerIntent.EXTRA_PROMPT, "Tell Jarvis")
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(listen, 1)
        } catch (e: Exception) {
            Toast.makeText(this, "This phone has no voice typing. Use Reply instead.", Toast.LENGTH_LONG).show()
            finish()
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        val text = data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()?.trim()
        if (resultCode == RESULT_OK && !text.isNullOrEmpty()) {
            Chat.personSays(this, text, intent.getIntExtra("about", -1), intent.getIntExtra("nid", Chat.ID))
            Chat.process(applicationContext, null)
        }
        finish()
    }
}
