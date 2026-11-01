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

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("id", -1)
        val entry = AlarmScheduler.entry(context, id) ?: return
        val kind = entry.getString("kind")
        val label = entry.getString("label")
        AlarmLog.add(context, "F|$id|${System.currentTimeMillis()}")

        if (entry.getBoolean("repeat")) {
            AlarmScheduler.schedule(context, id, AlarmScheduler.nextDaily(entry.getLong("millis")), kind, label, true)
        } else {
            AlarmScheduler.remove(context, id)
        }

        val isAlarm = kind == "alarm"
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val sound = RingtoneManager.getDefaultUri(
            if (isAlarm) RingtoneManager.TYPE_ALARM else RingtoneManager.TYPE_NOTIFICATION
        )
        val channelId = if (isAlarm) "alarm" else "notice"
        if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel(
                channelId,
                if (isAlarm) "Alarms" else "Reminders",
                if (isAlarm) NotificationManager.IMPORTANCE_HIGH else NotificationManager.IMPORTANCE_DEFAULT
            )
            channel.setSound(
                sound,
                AudioAttributes.Builder()
                    .setUsage(if (isAlarm) AudioAttributes.USAGE_ALARM else AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            manager.createNotificationChannel(channel)
        }
        val open = PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, channelId)
        else Notification.Builder(context).setSound(sound)
        val notification = builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(if (isAlarm) "Alarm" else "Jarvis")
            .setContentText(label)
            .setStyle(Notification.BigTextStyle().bigText(label))
            .setCategory(if (isAlarm) Notification.CATEGORY_ALARM else Notification.CATEGORY_REMINDER)
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        if (isAlarm) notification.flags = notification.flags or Notification.FLAG_INSISTENT
        manager.notify(id, notification)
    }
}
