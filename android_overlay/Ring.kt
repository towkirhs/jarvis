package com.towkirhs.jarcis

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.Gravity
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** How alarms and reminders show, kept on the phone: your alarm sound for everything, and what opens on the full screen. */
object AlarmPrefs {
    private fun p(context: Context) = context.getSharedPreferences("jarcis_alarm", Context.MODE_PRIVATE)

    /** The music file used when an alarm has none of its own (null: the phone's alarm sound). */
    fun sound(context: Context): String? = p(context).getString("sound", null)?.takeIf { it.isNotEmpty() }
    fun soundName(context: Context): String? = p(context).getString("soundName", null)?.takeIf { it.isNotEmpty() }
    fun fullAlarm(context: Context) = p(context).getBoolean("fullAlarm", true)
    fun fullNotice(context: Context) = p(context).getBoolean("fullNotice", false)

    /** How every alarm without its own rings: {vol: 10-100 (% of the phone's alarm volume), rise, vib}, or null. */
    fun style(context: Context): String? = p(context).getString("style", null)?.takeIf { it.isNotEmpty() }

    fun set(context: Context, key: String, value: Any?) {
        val e = p(context).edit()
        when (value) {
            is Boolean -> e.putBoolean(key, value)
            null -> e.remove(key)
            else -> e.putString(key, value.toString())
        }
        e.apply()
    }

    /** Whether Android lets Jarvis put an alarm over the lock screen (a setting of its own since Android 14). */
    fun canFullScreen(context: Context): Boolean =
        android.os.Build.VERSION.SDK_INT < 34 || context.getSystemService(NotificationManager::class.java).canUseFullScreenIntent()
}

/**
 * A ringing alarm: plays your chosen music (or the phone's alarm sound) on a loop at alarm volume, vibrates,
 * and shows a full-screen card with Stop and Snooze, until you stop it or 10 minutes pass.
 */
class RingService : Service() {
    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private val main = Handler(Looper.getMainLooper())
    private var id = 0
    private var label = "Alarm"
    private var sound: String? = null
    private var style: String? = null

    /** The phone's alarm volume before this alarm changed it, put back when it stops. */
    private var oldVolume: Int? = null

    /** "clock" for an alarm from the Clock tab, "alarm" for one set on a task or event (it can be marked done). */
    private var kind = "clock"

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_DONE -> {
                // An alarm of a task or event: finishing it here marks the item done in Jarvis.
                DoneQueue.add(this, if (id >= ActionReceiver.SNOOZE_OFFSET) id - ActionReceiver.SNOOZE_OFFSET else id)
                MainActivity.live?.invokeMethod("doneWaiting", null)
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_SNOOZE -> {
                val base = if (id >= ActionReceiver.SNOOZE_OFFSET) id - ActionReceiver.SNOOZE_OFFSET else id
                AlarmScheduler.schedule(
                    this, base + ActionReceiver.SNOOZE_OFFSET, System.currentTimeMillis() + 10 * 60 * 1000L,
                    kind, label, false, 0, sound, style
                )
                stopSelf()
                return START_NOT_STICKY
            }
        }
        id = intent?.getIntExtra("id", 0) ?: 0
        label = intent?.getStringExtra("label") ?: "Alarm"
        sound = intent?.getStringExtra("sound") ?: AlarmPrefs.sound(this)
        kind = intent?.getStringExtra("kind") ?: "clock"
        style = intent?.getStringExtra("style") ?: AlarmPrefs.style(this)
        startForeground(NOTE_ID, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        ringing = true
        // Open the alarm's screen straight away. The notification's full-screen request only works while the
        // phone is locked; this also covers a phone that is in use (allowed because Jarvis may draw over apps).
        try { startActivity(screenIntent()) } catch (_: Exception) {}
        play()
        main.removeCallbacksAndMessages(null)
        main.postDelayed({ stopSelf() }, 10 * 60 * 1000L)
        return START_NOT_STICKY
    }

    private fun play() {
        player?.release()
        val chosen = sound?.let { File(it) }?.takeIf { it.exists() }?.let { Uri.fromFile(it) }
        val fallback = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build()
        fun playing(uri: Uri) = MediaPlayer().apply {
            setAudioAttributes(attrs)
            setDataSource(this@RingService, uri)
            isLooping = true
            prepare()
            start()
        }
        val st = try { JSONObject(style ?: "{}") } catch (_: Exception) { JSONObject() }
        // Loudness: the phone's alarm volume set to the chosen share while it rings, put back afterwards.
        if (st.has("vol")) {
            val audio = getSystemService(AudioManager::class.java)
            try {
                val max = audio.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                if (oldVolume == null) oldVolume = audio.getStreamVolume(AudioManager.STREAM_ALARM)
                val target = Math.round(max * st.optInt("vol", 100).coerceIn(10, 100) / 100f).coerceAtLeast(1)
                audio.setStreamVolume(AudioManager.STREAM_ALARM, target, 0)
            } catch (_: Exception) {
                // Do Not Disturb can refuse the change: it rings at the phone's own alarm volume.
            }
        }
        player = try {
            playing(chosen ?: fallback)
        } catch (e: Exception) {
            // The music file is gone or cannot be played: ring with the phone's own alarm sound.
            try { playing(fallback) } catch (_: Exception) { null }
        }
        // Gets louder slowly: from very soft to full over about a minute.
        if (st.optBoolean("rise", false)) {
            var level = 0.05f
            player?.setVolume(level, level)
            val step = object : Runnable {
                override fun run() {
                    level = (level + 0.05f).coerceAtMost(1f)
                    try { player?.setVolume(level, level) } catch (_: Exception) {}
                    if (level < 1f) main.postDelayed(this, 3000L)
                }
            }
            main.postDelayed(step, 3000L)
        }
        if (st.optBoolean("vib", true)) {
            vibrator = getSystemService(Vibrator::class.java)?.also {
                it.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 800, 800), 0), attrs)
            }
        }
    }

    private fun notification(): Notification {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, "Ringing alarms", NotificationManager.IMPORTANCE_HIGH).apply { setSound(null, null) }
        )
        val screen = PendingIntent.getActivity(
            this, 5, screenIntent(), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        fun act(action: String, code: Int) = PendingIntent.getService(
            this, code, Intent(this, RingService::class.java).setAction(action), PendingIntent.FLAG_IMMUTABLE
        )
        val b = Notification.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(label)
            .setContentText("Alarm")
            .setCategory(Notification.CATEGORY_ALARM)
            .setOngoing(true)
            .setContentIntent(screen)
            .setFullScreenIntent(screen, true)
            .addAction(Notification.Action.Builder(null, if (kind == "alarm") "Done" else "Stop", act(if (kind == "alarm") ACTION_DONE else ACTION_STOP, 6)).build())
            .addAction(Notification.Action.Builder(null, "Snooze 10 min", act(ACTION_SNOOZE, 7)).build())
        // Show it at once: Android may otherwise hold a service's notification back for ten seconds.
        if (android.os.Build.VERSION.SDK_INT >= 31) b.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        return b.build()
    }

    private fun screenIntent() = Intent(this, RingActivity::class.java)
        .putExtra("label", label).putExtra("mode", "ring").putExtra("kind", kind)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION)

    override fun onDestroy() {
        ringing = false
        main.removeCallbacksAndMessages(null)
        try { player?.stop() } catch (_: Exception) {}
        player?.release()
        player = null
        vibrator?.cancel()
        oldVolume?.let {
            try { getSystemService(AudioManager::class.java).setStreamVolume(AudioManager.STREAM_ALARM, it, 0) } catch (_: Exception) {}
        }
        oldVolume = null
        RingActivity.current?.finish()
        super.onDestroy()
    }

    companion object {
        const val CHANNEL = "ring"
        const val NOTE_ID = 2_100_000_002
        const val ACTION_STOP = "com.towkirhs.jarcis.RING_STOP"
        const val ACTION_SNOOZE = "com.towkirhs.jarcis.RING_SNOOZE"
        const val ACTION_DONE = "com.towkirhs.jarcis.RING_DONE"
        var ringing = false
            private set

        fun start(context: Context, id: Int, label: String, sound: String?, kind: String = "clock", style: String? = null) {
            context.startForegroundService(
                Intent(context, RingService::class.java).putExtra("id", id).putExtra("label", label)
                    .putExtra("sound", sound).putExtra("kind", kind).putExtra("style", style)
            )
        }
    }
}

/**
 * The full screen of a ringing alarm (mode "ring": Stop or Done, and Snooze) or of a reminder (mode "notice":
 * Done, Snooze, Close). It shows over the lock screen and over other apps, and Back does not close it:
 * you answer it with one of its buttons.
 */
class RingActivity : Activity() {
    private var mode = "ring"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        current = this
        setShowWhenLocked(true)
        setTurnScreenOn(true)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        show(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        show(intent)
    }

    private fun show(intent: Intent) {
        mode = intent.getStringExtra("mode") ?: "ring"
        val kind = intent.getStringExtra("kind") ?: "clock"
        val id = intent.getIntExtra("id", -1)
        val label = intent.getStringExtra("label") ?: "Alarm"
        val dp = resources.displayMetrics.density
        val teal = Color.rgb(11, 114, 133)
        fun text(s: String, size: Float, color: Int) = TextView(this).apply {
            this.text = s
            textSize = size
            setTextColor(color)
            gravity = Gravity.CENTER
        }
        fun button(s: String, filled: Boolean, onTap: () -> Unit) = TextView(this).apply {
            this.text = s
            textSize = 20f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            background = android.graphics.drawable.GradientDrawable().apply {
                cornerRadius = 20 * dp
                if (filled) setColor(teal) else {
                    setColor(Color.TRANSPARENT)
                    setStroke((1.5f * dp).toInt(), Color.rgb(140, 140, 150))
                }
            }
            isClickable = true
            setOnClickListener { onTap() }
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, (64 * dp).toInt()).apply {
                topMargin = (14 * dp).toInt()
            }
        }
        fun ring(action: String) {
            startService(Intent(this, RingService::class.java).setAction(action))
            finish()
        }
        fun notice(action: String) {
            sendBroadcast(
                Intent(this, ActionReceiver::class.java).setAction(action)
                    .putExtra("id", id).putExtra("kind", kind).putExtra("label", label)
            )
            finish()
        }
        setContentView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.rgb(18, 18, 24))
            val pad = (28 * dp).toInt()
            setPadding(pad, pad, pad, pad)
            addView(text(if (mode == "ring") "Alarm" else "Reminder", 16f, Color.rgb(150, 200, 210)))
            addView(text(SimpleDateFormat("h:mm a", Locale.getDefault()).format(Date()), 64f, Color.WHITE))
            addView(text(label, 24f, Color.rgb(220, 220, 228)).apply { setPadding(0, (12 * dp).toInt(), 0, (28 * dp).toInt()) })
            if (mode == "ring") {
                if (kind == "alarm") addView(button("Done", true) { ring(RingService.ACTION_DONE) })
                else addView(button("Stop", true) { ring(RingService.ACTION_STOP) })
                addView(button("Snooze 10 min", false) { ring(RingService.ACTION_SNOOZE) })
            } else {
                addView(button("Done", true) { notice(ActionReceiver.ACTION_DONE) })
                addView(button("Snooze 10 min", false) { notice(ActionReceiver.ACTION_SNOOZE) })
                addView(button("Close", false) { finish() })
            }
        })
        if (mode == "ring" && !RingService.ringing) finish()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        // Answer it with a button.
    }

    override fun onDestroy() {
        if (current === this) current = null
        super.onDestroy()
    }

    companion object {
        var current: RingActivity? = null

        /** A reminder's own full screen, opened next to its notification. */
        fun noticeIntent(context: Context, id: Int, kind: String, label: String) = Intent(context, RingActivity::class.java)
            .putExtra("mode", "notice").putExtra("id", id).putExtra("kind", kind).putExtra("label", label)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION)
    }
}
