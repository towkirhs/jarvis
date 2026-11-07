package com.towkirhs.jarcis

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.hardware.camera2.CameraManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.ContactsContract
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import org.json.JSONObject

/**
 * Small phone actions by voice or text: open an app, open a WhatsApp chat, call someone (WhatsApp or phone,
 * after a 3 second countdown you can cancel), text, torch, YouTube, directions. Jarvis never sends a message
 * by itself: chats open with the text filled in, and you press send.
 */
object Commands {
    data class Cmd(val kind: String, val target: String, val text: String? = null)

    private const val PREFS = "jarcis_cmds"
    private val main = Handler(Looper.getMainLooper())
    private var pendingCall: Runnable? = null

    /** Your nicknames ("oishi" -> a contact name or number) and phrases ("gym music" -> an action). */
    fun setShortcuts(context: Context, json: String) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("shortcuts", json).apply()

    private fun shortcuts(context: Context): JSONObject =
        JSONObject(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("shortcuts", "{}") ?: "{}")

    private val timeWords = Regex(
        "\\b(at \\d|by \\d|tomorrow|tonight|today|next|later|remind|in \\d+ (min|minute|hour|day)s?|on (mon|tue|wed|thu|fri|sat|sun))"
    )

    /** A command, or null if this is an ordinary note (a reminder like "call Ammu at 8" stays a note). */
    fun parse(context: Context, raw: String): Cmd? {
        var t = raw.trim().lowercase().replace(Regex("[.!?]+$"), "")
        t = t.replace(Regex("^(hey |ok |okay )?jarvis[,:]?\\s*"), "").replace(Regex("^please\\s+"), "").trim()
        if (t.isEmpty()) return null
        // Your own phrases first.
        val phrases = shortcuts(context).optJSONObject("phrases")
        if (phrases != null && phrases.has(t)) {
            val p = phrases.getJSONObject(t)
            return Cmd(p.getString("kind"), p.getString("target"), p.optString("text").ifEmpty { null })
        }
        if (timeWords.containsMatchIn(t)) return null
        Regex("^video call (.+?) on whatsapp$").find(t)?.let { return Cmd("wa_video", it.groupValues[1]) }
        Regex("^(?:call|ring) (.+?) on whatsapp$").find(t)?.let { return Cmd("wa_call", it.groupValues[1]) }
        Regex("^whatsapp call (.+)$").find(t)?.let { return Cmd("wa_call", it.groupValues[1]) }
        Regex("^(?:message|text|msg|send a message to) (.+?) on whatsapp(?:\\s*(?:saying|that|:)\\s*(.+))?$").find(t)?.let {
            return Cmd("wa_chat", it.groupValues[1], it.groupValues[2].ifEmpty { null })
        }
        Regex("^whatsapp (.+?)(?:\\s*(?:saying|that|:)\\s*(.+))?$").find(t)?.let {
            return Cmd("wa_chat", it.groupValues[1], it.groupValues[2].ifEmpty { null })
        }
        Regex("^(?:call|phone|dial|ring) (.+)$").find(t)?.let { return Cmd("call", it.groupValues[1]) }
        Regex("^(?:sms|text) (.+?)(?:\\s*(?:saying|that|:)\\s*(.+))?$").find(t)?.let {
            return Cmd("sms", it.groupValues[1], it.groupValues[2].ifEmpty { null })
        }
        Regex("^(?:turn |switch )?(on|off) (?:the )?(?:flashlight|torch|flash)$").find(t)?.let { return Cmd("torch", it.groupValues[1]) }
        Regex("^(?:flashlight|torch|flash) (on|off)$").find(t)?.let { return Cmd("torch", it.groupValues[1]) }
        Regex("^play (.+?) on youtube$").find(t)?.let { return Cmd("youtube", it.groupValues[1]) }
        Regex("^(?:search )?youtube (?:for )?(.+)$").find(t)?.let { return Cmd("youtube", it.groupValues[1]) }
        Regex("^(?:navigate|directions|take me|go) to (.+)$").find(t)?.let { return Cmd("maps", it.groupValues[1]) }
        Regex("^(?:open|launch|start) (?:the )?(.+?)(?: app)?$").find(t)?.let { return Cmd("app", it.groupValues[1]) }
        return null
    }

    /** Runs [cmd]. Returns what happened, in a few words, or throws with what went wrong. */
    fun run(context: Context, cmd: Cmd): String {
        return when (cmd.kind) {
            "app" -> openApp(context, cmd.target)
            "link" -> {
                start(context, Intent(Intent.ACTION_VIEW, Uri.parse(cmd.target)))
                "Opened ${cmd.target}"
            }
            "wa_chat" -> {
                val (name, number) = person(context, cmd.target)
                val url = "https://api.whatsapp.com/send?phone=${waNumber(number)}" +
                    (cmd.text?.let { "&text=" + Uri.encode(it) } ?: "")
                start(context, Intent(Intent.ACTION_VIEW, Uri.parse(url)).setPackage("com.whatsapp"))
                "Opened WhatsApp chat with $name" + (if (cmd.text != null) ", message ready to send" else "")
            }
            "wa_call", "wa_video" -> {
                val (name, _) = person(context, cmd.target)
                val mime = if (cmd.kind == "wa_video") "vnd.android.cursor.item/vnd.com.whatsapp.video.call"
                else "vnd.android.cursor.item/vnd.com.whatsapp.voip.call"
                val id = whatsappRow(context, name, mime)
                    ?: throw Exception("$name has no WhatsApp ${if (cmd.kind == "wa_video") "video " else ""}call in your contacts")
                val intent = Intent(Intent.ACTION_VIEW).setDataAndType(
                    Uri.parse("content://com.android.contacts/data/$id"), mime
                ).setPackage("com.whatsapp")
                countdown(context, "${if (cmd.kind == "wa_video") "Video calling" else "Calling"} $name on WhatsApp") { start(context, intent) }
                "Calling $name on WhatsApp"
            }
            "call" -> {
                val (name, number) = person(context, cmd.target)
                val direct = context.checkSelfPermission(Manifest.permission.CALL_PHONE) == PackageManager.PERMISSION_GRANTED
                val intent = Intent(if (direct) Intent.ACTION_CALL else Intent.ACTION_DIAL, Uri.parse("tel:$number"))
                if (direct) countdown(context, "Calling $name") { start(context, intent) } else start(context, intent)
                if (direct) "Calling $name" else "Opened the dialer for $name"
            }
            "sms" -> {
                val (name, number) = person(context, cmd.target)
                val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:$number"))
                cmd.text?.let { intent.putExtra("sms_body", it) }
                start(context, intent)
                "Opened a text to $name"
            }
            "torch" -> {
                val cm = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
                val id = cm.cameraIdList.firstOrNull() ?: throw Exception("No flashlight")
                cm.setTorchMode(id, cmd.target == "on")
                "Flashlight ${cmd.target}"
            }
            "youtube" -> {
                start(context, Intent(Intent.ACTION_VIEW, Uri.parse("https://www.youtube.com/results?search_query=" + Uri.encode(cmd.target))))
                "Searching YouTube for ${cmd.target}"
            }
            "maps" -> {
                start(context, Intent(Intent.ACTION_VIEW, Uri.parse("google.navigation:q=" + Uri.encode(cmd.target))))
                "Directions to ${cmd.target}"
            }
            else -> throw Exception("I don't know how to do that yet")
        }
    }

    private fun start(context: Context, intent: Intent) {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(intent)
        } catch (e: Exception) {
            throw Exception("No app on this phone can do that")
        }
    }

    private fun openApp(context: Context, name: String): String {
        val alias = shortcuts(context).optJSONObject("apps")?.optString(name)?.ifEmpty { null } ?: name
        val pm = context.packageManager
        val apps = pm.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), 0)
        val want = alias.lowercase()
        val labelled = apps.map { it to it.loadLabel(pm).toString() }
        val hit = labelled.firstOrNull { it.second.lowercase() == want }
            ?: labelled.firstOrNull { it.second.lowercase().startsWith(want) }
            ?: labelled.firstOrNull { it.second.lowercase().contains(want) }
            ?: throw Exception("No app called $name")
        val launch = pm.getLaunchIntentForPackage(hit.first.activityInfo.packageName) ?: throw Exception("Can't open ${hit.second}")
        start(context, launch)
        return "Opened ${hit.second}"
    }

    /** A person from your nicknames or contacts: (name, number). */
    private fun person(context: Context, said: String): Pair<String, String> {
        val nick = shortcuts(context).optJSONObject("people")?.optString(said.lowercase())?.ifEmpty { null }
        val query = nick ?: said
        if (query.replace(Regex("[^0-9+]"), "").length >= 7 && query.any { it.isDigit() } && !query.any { it.isLetter() }) {
            return said to query
        }
        if (context.checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) {
            throw Exception("Allow Jarvis to read contacts (Settings, Hey Jarvis)")
        }
        val c = context.contentResolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME, ContactsContract.CommonDataKinds.Phone.NUMBER),
            "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ?", arrayOf("%$query%"), null
        ) ?: throw Exception("Can't read contacts")
        val found = mutableListOf<Pair<String, String>>()
        c.use { while (it.moveToNext()) found.add(it.getString(0) to it.getString(1)) }
        val q = query.lowercase()
        return found.firstOrNull { it.first.lowercase() == q }
            ?: found.firstOrNull { it.first.lowercase().startsWith(q) }
            ?: found.firstOrNull()
            ?: throw Exception("No contact called $said. Add a nickname in Settings, Hey Jarvis")
    }

    /** Digits in international form for WhatsApp; Bangladeshi 01… numbers get 880. */
    private fun waNumber(number: String): String {
        var d = number.replace(Regex("[^0-9]"), "")
        if (d.startsWith("00")) d = d.substring(2)
        if (d.length == 11 && d.startsWith("01")) d = "88$d"
        return d
    }

    private fun whatsappRow(context: Context, name: String, mime: String): Long? {
        if (context.checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) return null
        val c = context.contentResolver.query(
            ContactsContract.Data.CONTENT_URI, arrayOf(ContactsContract.Data._ID),
            "${ContactsContract.Data.MIMETYPE} = ? AND ${ContactsContract.Data.DISPLAY_NAME} = ?", arrayOf(mime, name), null
        ) ?: return null
        return c.use { if (it.moveToFirst()) it.getLong(0) else null }
    }

    /** Waits 3 seconds with a Cancel button, then does [action]. */
    private fun countdown(context: Context, what: String, action: () -> Unit) {
        pendingCall?.let { main.removeCallbacks(it) }
        val go = Runnable {
            pendingCall = null
            Overlay.hide(context)
            try { action() } catch (e: Exception) { toast(context, e.message ?: "Could not call") }
        }
        pendingCall = go
        main.post {
            if (!Overlay.show(context, "$what in 3 seconds", "Cancel") { cancel(context) }) {
                toast(context, "$what in 3 seconds")
            }
        }
        main.postDelayed(go, 3000)
    }

    fun cancel(context: Context) {
        pendingCall?.let { main.removeCallbacks(it) }
        pendingCall = null
        Overlay.hide(context)
        toast(context, "Cancelled")
    }

    /** Commands done by voice, for the chat in the app to show next time it opens. */
    @Synchronized
    fun log(context: Context, said: String, did: String) {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val list = org.json.JSONArray(p.getString("log", "[]"))
        list.put(JSONObject().put("said", said).put("did", did).put("ts", System.currentTimeMillis()))
        p.edit().putString("log", list.toString()).apply()
    }

    @Synchronized
    fun takeLog(context: Context): String {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val s = p.getString("log", "[]") ?: "[]"
        p.edit().remove("log").apply()
        return s
    }

    fun toast(context: Context, text: String) = main.post { Toast.makeText(context.applicationContext, text, Toast.LENGTH_SHORT).show() }
}

/** A small card at the top of the screen (needs "Display over other apps"). Also what lets Jarvis open apps
 *  from the background on newer Android versions. */
object Overlay {
    private var view: View? = null

    fun allowed(context: Context) = Settings.canDrawOverlays(context)

    fun show(context: Context, text: String, button: String? = null, onButton: (() -> Unit)? = null): Boolean {
        if (!allowed(context)) return false
        hide(context)
        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val dp = context.resources.displayMetrics.density
        val box = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding((20 * dp).toInt(), (12 * dp).toInt(), (12 * dp).toInt(), (12 * dp).toInt())
            background = GradientDrawable().apply {
                cornerRadius = 28 * dp
                setColor(0xEE1E2A33.toInt())
            }
        }
        box.addView(TextView(context).apply {
            this.text = text
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 16f
        })
        if (button != null) {
            box.addView(Button(context).apply {
                this.text = button
                setOnClickListener { onButton?.invoke() }
            })
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE, PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = (48 * dp).toInt()
        }
        return try {
            wm.addView(box, params)
            view = box
            true
        } catch (e: Exception) {
            false
        }
    }

    fun hide(context: Context) {
        val v = view ?: return
        view = null
        try {
            (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(v)
        } catch (_: Exception) {
        }
    }
}

/**
 * Listens for "Hey Jarvis" (openWakeWord, on the phone, nothing recorded or sent), then hears one sentence
 * with the phone's speech recognizer: a command runs, anything else goes to Jarvis as a note and the answer
 * comes back as a notification. Runs as a foreground service with a notification while it listens.
 */
class WakeService : Service() {
    private var detector: WakeWord? = null
    @Volatile private var listening = false
    private var thread: Thread? = null
    private var recognizer: SpeechRecognizer? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        startForegroundNotice()
        if (detector == null) startWake()
        return START_STICKY
    }

    private fun startForegroundNotice() {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "Hey Jarvis", NotificationManager.IMPORTANCE_MIN))
        val stop = PendingIntent.getService(
            this, 3, Intent(this, WakeService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE
        )
        val open = PendingIntent.getActivity(this, 4, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val n = Notification.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("Say \"Hey Jarvis\"")
            .setContentText("Listening for the wake word on this phone only")
            .setContentIntent(open)
            .addAction(Notification.Action.Builder(null, "Stop", stop).build())
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 30) {
            startForeground(ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(ID, n)
        }
    }

    private fun startWake() {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            Commands.toast(this, "Allow the microphone in Jarvis first")
            stopSelf()
            return
        }
        try {
            detector = WakeWord(this)
        } catch (e: Exception) {
            Commands.toast(this, "Wake word could not start: ${e.message}")
            stopSelf()
            return
        }
        listen()
    }

    /** Reads the mic in 80 ms chunks on its own thread until the wake word scores above the threshold. */
    private fun listen() {
        if (listening) return
        listening = true
        val threshold = getSharedPreferences("jarcis_cmds", Context.MODE_PRIVATE).getFloat("wake_threshold", 0.5f)
        thread = Thread {
            val chunk = ShortArray(WakeWord.CHUNK)
            var rec: AudioRecord? = null
            var failed = false
            try {
                val min = AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
                rec = AudioRecord(
                    MediaRecorder.AudioSource.VOICE_RECOGNITION, 16000, AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT, maxOf(min, WakeWord.CHUNK * 4)
                )
                rec.startRecording()
                while (listening) {
                    var n = 0
                    while (n < chunk.size && listening) {
                        val r = rec.read(chunk, n, chunk.size - n)
                        if (r <= 0) throw IllegalStateException("the microphone stopped")
                        n += r
                    }
                    if (!listening) break
                    if ((detector?.score(chunk) ?: 0f) >= threshold) {
                        listening = false
                        main.post { heard() }
                    }
                }
            } catch (e: Exception) {
                failed = listening
                listening = false
                if (failed) main.post {
                    Commands.toast(this, "Wake word stopped: ${e.message}")
                    stopSelf()
                }
            } finally {
                try { rec?.stop() } catch (_: Exception) {}
                rec?.release()
            }
        }.apply { start() }
    }

    private fun stopListening() {
        listening = false
        try { thread?.join(1000) } catch (_: InterruptedException) {}
        thread = null
    }

    /** "Hey Jarvis" was heard: let go of the mic, listen for one sentence, then go back to waiting. */
    private fun heard() {
        stopListening()
        Overlay.show(this, "Listening…")
        val r = SpeechRecognizer.createSpeechRecognizer(this)
        recognizer = r
        r.setRecognitionListener(object : RecognitionListener {
            override fun onResults(results: Bundle?) {
                val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
                if (!text.isNullOrBlank()) handle(text) else Overlay.hide(this@WakeService)
                resume()
            }
            override fun onError(error: Int) {
                Overlay.hide(this@WakeService)
                resume()
            }
            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onPartialResults(partialResults: Bundle?) {}
            override fun onEvent(eventType: Int, params: Bundle?) {}
        })
        r.startListening(
            Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        )
    }

    private fun handle(text: String) {
        val cmd = Commands.parse(this, text)
        if (cmd == null) {
            Overlay.show(this, "“$text”")
            main.postDelayed({ Overlay.hide(this) }, 2000)
            NoteQueue.add(this, text, null, "voice")
            Chat.process(this, null)
            return
        }
        try {
            val did = Commands.run(this, cmd)
            if (!did.startsWith("Calling")) {
                Overlay.show(this, did)
                main.postDelayed({ Overlay.hide(this) }, 1500)
            }
            Commands.log(this, text, did)
        } catch (e: Exception) {
            Overlay.show(this, e.message ?: "Could not do that")
            main.postDelayed({ Overlay.hide(this) }, 2500)
        }
    }

    private fun resume() {
        main.postDelayed({
            recognizer?.destroy()
            recognizer = null
            detector?.reset()
            listen()
        }, 300)
    }

    override fun onDestroy() {
        recognizer?.destroy()
        stopListening()
        detector?.close()
        detector = null
        Overlay.hide(this)
        super.onDestroy()
    }

    companion object {
        const val CHANNEL = "wake"
        const val ID = 2_100_000_001
        const val ACTION_STOP = "com.towkirhs.jarcis.WAKE_STOP"
        var running = false
            private set

        fun start(context: Context) {
            running = true
            context.startForegroundService(Intent(context, WakeService::class.java))
        }

        fun stop(context: Context) {
            running = false
            context.stopService(Intent(context, WakeService::class.java))
        }
    }
}
