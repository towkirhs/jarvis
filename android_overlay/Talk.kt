package com.towkirhs.jarcis

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.view.Gravity
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * Jarvis talking back, the way you set it in Hey Jarvis, Voice replies:
 * {mode: "voice" | "always" | "headphones" | "never", confirm, answer, problem, short, quietFrom, quietTo,
 *  rate, pitch, voice, followUp}.
 */
object Speaker {
    private const val PREFS = "jarcis_cmds"
    private var tts: TextToSpeech? = null
    private var ready = false
    private var waiting: (() -> Unit)? = null
    private var focus: AudioFocusRequest? = null
    private val main by lazy { Handler(Looper.getMainLooper()) }
    private val afterDone = mutableMapOf<String, () -> Unit>()

    fun settings(context: Context): JSONObject =
        JSONObject(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("speech", "{}") ?: "{}")

    fun setSettings(context: Context, json: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("speech", json).apply()
    }

    private fun headphones(am: AudioManager) = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any {
        it.type in setOf(
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLE_HEADSET, AudioDeviceInfo.TYPE_USB_HEADSET,
        )
    }

    /**
     * Whether Jarvis may speak now. [kind]: "confirm", "answer" or "problem". [spoken]: you used your voice or the
     * button (not typing). On silent or vibrate it stays quiet unless headphones are in; quiet hours always win.
     */
    fun allowed(context: Context, s: JSONObject, kind: String, spoken: Boolean): Boolean {
        val mode = s.optString("mode", "voice")
        if (mode == "never" || !s.optBoolean(kind, true)) return false
        val am = context.getSystemService(AudioManager::class.java)
        val inEars = headphones(am)
        if (mode == "voice" && !spoken) return false
        if (mode == "headphones" && !inEars) return false
        if (am.ringerMode != AudioManager.RINGER_MODE_NORMAL && !inEars) return false
        return !inQuietHours(s.optString("quietFrom"), s.optString("quietTo"), Calendar.getInstance())
    }

    /** Quiet hours like 23:00 to 07:00 (across midnight) or 13:00 to 14:00. Empty means none. */
    fun inQuietHours(from: String, to: String, now: Calendar): Boolean {
        if (from.isEmpty() || to.isEmpty()) return false
        fun min(t: String) = t.split(":").let { it[0].toInt() * 60 + it[1].toInt() }
        val n = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        val a = min(from)
        val b = min(to)
        return if (a <= b) n in a until b else n >= a || n < b
    }

    /** The first sentence when "short answers" is on; never more than about 400 letters. */
    fun shorten(text: String, short: Boolean): String {
        var t = text.replace(Regex("[*_#`]"), "").trim()
        if (short) t = t.split(Regex("(?<=[.!?])\\s+")).first()
        return if (t.length > 400) t.substring(0, 400) else t
    }

    /** Speaks [text] if your settings allow it. [then] runs when it has finished speaking. */
    fun say(context: Context, text: String, kind: String, spoken: Boolean, then: (() -> Unit)? = null): Boolean {
        if (text.isBlank()) return false
        val s = settings(context)
        if (!allowed(context, s, kind, spoken)) return false
        speak(context, shorten(text, s.optBoolean("short", true)), s, then)
        return true
    }

    /** Speaks with your voice settings, whatever the rules (for Test voice). */
    fun speak(context: Context, text: String, s: JSONObject = settings(context), then: (() -> Unit)? = null) {
        val app = context.applicationContext
        val go: () -> Unit = {
            val t = tts!!
            t.setSpeechRate(s.optDouble("rate", 1.0).toFloat())
            t.setPitch(s.optDouble("pitch", 1.0).toFloat())
            val name = s.optString("voice")
            if (name.isNotEmpty()) t.voices?.firstOrNull { it.name == name }?.let { t.voice = it }
            val am = app.getSystemService(AudioManager::class.java)
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANT)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
            t.setAudioAttributes(attrs)
            // Music gets quieter while Jarvis talks, then comes back.
            focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK).setAudioAttributes(attrs).build()
            am.requestAudioFocus(focus!!)
            val id = "j${System.nanoTime()}"
            if (then != null) afterDone[id] = then
            Overlay.show(app, text, "Stop") { stop() }
            t.speak(text, TextToSpeech.QUEUE_FLUSH, null, id)
        }
        if (ready) {
            go()
            return
        }
        waiting = go
        start(app)
    }

    /** Starts the phone's speech engine (once); what is waiting is spoken when it is ready. */
    private fun start(app: Context) {
        if (tts != null) return
        tts = TextToSpeech(app) { status ->
            ready = status == TextToSpeech.SUCCESS
            if (ready) {
                tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) {}
                    override fun onDone(utteranceId: String?) {
                        finished(app, utteranceId, true)
                    }
                    @Deprecated("Deprecated in Java")
                    override fun onError(utteranceId: String?) {
                        finished(app, utteranceId, false)
                    }
                    override fun onStop(utteranceId: String?, interrupted: Boolean) {
                        finished(app, utteranceId, false)
                    }
                })
                main.post {
                    waiting?.invoke()
                    waiting = null
                }
            } else {
                tts = null
            }
        }
    }

    private fun finished(context: Context, id: String?, done: Boolean) {
        main.post {
            focus?.let { context.getSystemService(AudioManager::class.java).abandonAudioFocusRequest(it) }
            focus = null
            Overlay.hide(context)
            val then = afterDone.remove(id)
            if (done) then?.invoke()
        }
    }

    fun stop() {
        waiting = null
        afterDone.clear()
        tts?.stop()
    }

    /** The voices this phone has: [{name, locale}]. Empty until the speech engine has started once. */
    fun voices(context: Context): List<Map<String, String>> {
        if (!ready) {
            start(context.applicationContext)
            return emptyList()
        }
        return (tts?.voices ?: emptySet())
            .filter { !it.isNetworkConnectionRequired && it.features?.contains("notInstalled") != true }
            .sortedBy { it.locale.toLanguageTag() + it.name }
            .map { mapOf("name" to it.name, "locale" to it.locale.displayName) }
    }
}

/** What happens with one sentence you said (by "Hey Jarvis", the button, or a follow-up). */
object Assistant {
    /** Does a command or hands the sentence to Jarvis as a note. Returns a line to show. */
    fun handle(context: Context, text: String, spoken: Boolean): String {
        val cmd = Commands.parse(context, text)
        if (cmd == null) {
            NoteQueue.add(context, text, null, "voice")
            Chat.process(context, null)
            return "“$text”"
        }
        return try {
            val did = Commands.run(context, cmd)
            if (did.isNotEmpty()) Commands.log(context, text, did)
            if (!cmd.quiet) Speaker.say(context, did, if (cmd.kind in setOf("time", "battery")) "answer" else "confirm", spoken)
            did
        } catch (e: Exception) {
            val why = e.message ?: "Could not do that"
            Speaker.say(context, why, "problem", spoken)
            why
        }
    }
}

/** Alarms set by voice ("wake me at 6:30"), waiting for the app to add them to the Clock page. */
object NewClocks {
    private const val FILE = "jarcis_new_clocks"

    @Synchronized
    fun add(context: Context, id: Int, at: Long) {
        val p = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        val q = JSONArray(p.getString("q", "[]")).put(JSONObject().put("id", id).put("at", at))
        p.edit().putString("q", q.toString()).apply()
    }

    @Synchronized
    fun take(context: Context): String {
        val p = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        val q = p.getString("q", "[]") ?: "[]"
        p.edit().putString("q", "[]").apply()
        return q
    }
}

/**
 * "Talk to Jarvis": listens for one sentence straight away, no wake word. Opened by its own icon (which a button
 * remapper like the Essential Key can launch), by "Hey Jarvis", or after an answer for a follow-up.
 * Actions for button apps: com.towkirhs.jarcis.TALK (listen), .SNAP (photo to Jarvis), .DO with extra "text".
 */
class ListenActivity : Activity() {
    private var recognizer: SpeechRecognizer? = null
    private var retried = false
    private lateinit var line: TextView
    private val main by lazy { Handler(Looper.getMainLooper()) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        openCards++
        setShowWhenLocked(true)
        Speaker.stop()
        WakeService.pause(this)
        when (intent.action) {
            ACTION_SNAP -> {
                startActivity(Intent(this, MainActivity::class.java).putExtra("jarvis_capture", "photo")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                finish()
                return
            }
            ACTION_DO -> {
                // Other apps can send this, so it only runs one of your own commands, nothing else.
                val text = intent.getStringExtra("text")
                if (!text.isNullOrBlank() && Commands.isOwnPhrase(this, text)) {
                    Assistant.handle(this, text, true)
                } else {
                    Commands.toast(this, "A button can only run one of your own commands")
                }
                finish()
                return
            }
        }
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            Commands.toast(this, "Allow the microphone in Jarvis, Hey Jarvis")
            startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            finish()
            return
        }
        card()
        listen()
    }

    /** A small card at the bottom; tap outside it to cancel. */
    private fun card() {
        val dp = resources.displayMetrics.density
        line = TextView(this).apply {
            text = if (intent.getBooleanExtra("followUp", false)) "Anything else?" else "Listening…"
            textSize = 18f
            setTextColor(Color.WHITE)
        }
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val pad = (20 * dp).toInt()
            setPadding(pad, pad, pad, pad)
            background = GradientDrawable().apply {
                cornerRadius = 28 * dp
                setColor(0xF01E2A33.toInt())
            }
            addView(line)
            // The way into the chat: opening Jarvis by package (a button app) lands here instead.
            addView(TextView(this@ListenActivity).apply {
                text = "Open Jarvis"
                textSize = 14f
                setTextColor(0xFF9FD3D3.toInt())
                gravity = Gravity.END
                setPadding(0, (14 * dp).toInt(), 0, 0)
                setOnClickListener {
                    startActivity(Intent(this@ListenActivity, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    finish()
                }
            })
            isClickable = true
        }
        setContentView(FrameLayout(this).apply {
            setOnClickListener { finish() }
            addView(box, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                gravity = Gravity.BOTTOM
                val m = (16 * dp).toInt()
                setMargins(m, m, m, (32 * dp).toInt())
            })
        })
    }

    private fun listen() {
        val r = SpeechRecognizer.createSpeechRecognizer(this)
        recognizer = r
        r.setRecognitionListener(object : RecognitionListener {
            override fun onResults(results: Bundle?) {
                val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
                if (text.isNullOrBlank()) return finish()
                line.text = "“$text”"
                val shown = Assistant.handle(this@ListenActivity, text, true)
                line.text = shown
                main.postDelayed({ finish() }, 1200)
            }
            override fun onPartialResults(partialResults: Bundle?) {
                partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
                    ?.takeIf { it.isNotBlank() }?.let { line.text = it }
            }
            override fun onError(error: Int) {
                // The mic may still be with the wake word, or nothing was heard yet: try once more before giving up.
                if (retried || isFinishing) return finish()
                retried = true
                line.text = "Listening…"
                r.destroy()
                main.postDelayed({ if (!isFinishing) listen() }, 400)
            }
            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onEvent(eventType: Int, params: Bundle?) {}
        })
        r.startListening(speechIntent(this).putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true))
    }

    override fun onDestroy() {
        main.removeCallbacksAndMessages(null)
        recognizer?.destroy()
        recognizer = null
        openCards--
        WakeService.resume(this)
        super.onDestroy()
    }

    companion object {
        const val ACTION_TALK = "com.towkirhs.jarcis.TALK"
        const val ACTION_SNAP = "com.towkirhs.jarcis.SNAP"
        const val ACTION_DO = "com.towkirhs.jarcis.DO"

        /**
         * How Jarvis asks the phone to listen: in the language chosen in Settings, Voice ("" = the phone's own),
         * and waiting through a short pause so a sentence is not cut in half.
         */
        fun speechIntent(context: Context): Intent {
            val i = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                .putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 1800L)
                .putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 1800L)
            val lang = context.getSharedPreferences("jarcis_cmds", Context.MODE_PRIVATE).getString("speech_lang", "en-IN")
            if (!lang.isNullOrEmpty()) i.putExtra(RecognizerIntent.EXTRA_LANGUAGE, lang)
            // Your own words (names and the like) as hints, so the phone hears them right more often.
            // Android 13+; recognisers that do not support hints ignore them.
            val hints = context.getSharedPreferences("jarcis_cmds", Context.MODE_PRIVATE).getString("speech_hints", "")
                ?.split('\n')?.map { it.trim() }?.filter { it.isNotEmpty() }.orEmpty()
            if (hints.isNotEmpty() && Build.VERSION.SDK_INT >= 33) {
                i.putStringArrayListExtra(RecognizerIntent.EXTRA_BIASING_STRINGS, ArrayList(hints))
            }
            return i
        }

        /** Listening cards open now (a follow-up card can open before the last one closes). Main thread only. */
        private var openCards = 0
        val showing get() = openCards > 0

        /** Opens the listening card (from the background too: "Display over other apps" allows that). */
        fun open(context: Context, followUp: Boolean = false) {
            context.startActivity(
                Intent(context, ListenActivity::class.java).setAction(ACTION_TALK).putExtra("followUp", followUp)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION)
            )
        }
    }
}
