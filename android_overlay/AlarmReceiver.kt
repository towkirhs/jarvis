package com.towkirhs.jarcis

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build

object AlarmLog {
    private const val PREFS = "jarcis_alarm_log"

    fun add(context: Context, line: String) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val old = prefs.getString("log", "") ?: ""
        prefs.edit().putString("log", if (old.isEmpty()) line else "$old\n$line").commit()
    }

    fun read(context: Context): String =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("log", "") ?: ""
}

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("id", 0)
        val label = intent.getStringExtra("label") ?: "Alarm"
        AlarmLog.add(context, "F|$id|${System.currentTimeMillis()}")

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val sound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel("alarm", "Alarms", NotificationManager.IMPORTANCE_HIGH)
            channel.setSound(
                sound,
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            manager.createNotificationChannel(channel)
        }
        val open = PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, "alarm")
        else Notification.Builder(context).setSound(sound)
        val notification = builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("Alarm")
            .setContentText(label)
            .setCategory(Notification.CATEGORY_ALARM)
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        notification.flags = notification.flags or Notification.FLAG_INSISTENT
        manager.notify(id, notification)
    }
}
