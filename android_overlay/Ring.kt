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
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

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

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_SNOOZE -> {
                val base = if (id >= ActionReceiver.SNOOZE_OFFSET) id - ActionReceiver.SNOOZE_OFFSET else id
                AlarmScheduler.schedule(
                    this, base + ActionReceiver.SNOOZE_OFFSET, System.currentTimeMillis() + 10 * 60 * 1000L,
                    "clock", label, false, 0, sound
                )
                stopSelf()
                return START_NOT_STICKY
            }
        }
        id = intent?.getIntExtra("id", 0) ?: 0
        label = intent?.getStringExtra("label") ?: "Alarm"
        sound = intent?.getStringExtra("sound")
        startForeground(NOTE_ID, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        ringing = true
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
        player = try {
            playing(chosen ?: fallback)
        } catch (e: Exception) {
            // The music file is gone or cannot be played: ring with the phone's own alarm sound.
            try { playing(fallback) } catch (_: Exception) { null }
        }
        vibrator = getSystemService(Vibrator::class.java)?.also {
            it.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 800, 800), 0), attrs)
        }
    }

    private fun notification(): Notification {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, "Ringing alarms", NotificationManager.IMPORTANCE_HIGH).apply { setSound(null, null) }
        )
        val screen = PendingIntent.getActivity(
            this, 5, Intent(this, RingActivity::class.java).putExtra("label", label)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        fun act(action: String, code: Int) = PendingIntent.getService(
            this, code, Intent(this, RingService::class.java).setAction(action), PendingIntent.FLAG_IMMUTABLE
        )
        return Notification.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(label)
            .setContentText("Alarm")
            .setCategory(Notification.CATEGORY_ALARM)
            .setOngoing(true)
            .setContentIntent(screen)
            .setFullScreenIntent(screen, true)
            .addAction(Notification.Action.Builder(null, "Stop", act(ACTION_STOP, 6)).build())
            .addAction(Notification.Action.Builder(null, "Snooze 10 min", act(ACTION_SNOOZE, 7)).build())
            .build()
    }

    override fun onDestroy() {
        ringing = false
        main.removeCallbacksAndMessages(null)
        try { player?.stop() } catch (_: Exception) {}
        player?.release()
        player = null
        vibrator?.cancel()
        RingActivity.current?.finish()
        super.onDestroy()
    }

    companion object {
        const val CHANNEL = "ring"
        const val NOTE_ID = 2_100_000_002
        const val ACTION_STOP = "com.towkirhs.jarcis.RING_STOP"
        const val ACTION_SNOOZE = "com.towkirhs.jarcis.RING_SNOOZE"
        var ringing = false
            private set

        fun start(context: Context, id: Int, label: String, sound: String?) {
            context.startForegroundService(
                Intent(context, RingService::class.java).putExtra("id", id).putExtra("label", label).putExtra("sound", sound)
            )
        }
    }
}

/** The full-screen card of a ringing alarm, shown over the lock screen. */
class RingActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        current = this
        setShowWhenLocked(true)
        setTurnScreenOn(true)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val dp = resources.displayMetrics.density
        fun text(s: String, size: Float, color: Int) = TextView(this).apply {
            this.text = s
            textSize = size
            setTextColor(color)
            gravity = Gravity.CENTER
        }
        fun button(s: String, action: String) = Button(this).apply {
            this.text = s
            textSize = 20f
            setOnClickListener {
                startService(Intent(this@RingActivity, RingService::class.java).setAction(action))
                finish()
            }
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, (64 * dp).toInt()).apply {
                topMargin = (16 * dp).toInt()
            }
        }
        setContentView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.rgb(18, 18, 24))
            val pad = (32 * dp).toInt()
            setPadding(pad, pad, pad, pad)
            addView(text(SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date()), 72f, Color.WHITE))
            addView(text(intent.getStringExtra("label") ?: "Alarm", 24f, Color.rgb(200, 200, 210)))
            addView(button("Stop", RingService.ACTION_STOP))
            addView(button("Snooze 10 min", RingService.ACTION_SNOOZE))
        })
        if (!RingService.ringing) finish()
    }

    override fun onDestroy() {
        if (current === this) current = null
        super.onDestroy()
    }

    companion object {
        var current: RingActivity? = null
    }
}
