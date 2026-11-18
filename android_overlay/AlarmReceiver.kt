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

        if (kind == "clock") {
            val days = entry.optInt("days", 0)
            val sound = entry.optString("sound", "").ifEmpty { null }
            val style = entry.optString("style", "").ifEmpty { null }
            if (days != 0) {
                AlarmScheduler.schedule(
                    context, id, AlarmScheduler.nextOnDays(entry.getLong("millis"), days), kind, label, false, days, sound, style
                )
            } else {
                AlarmScheduler.remove(context, id)
            }
            RingService.start(context, id, label, sound, "clock", style)
            return
        }

        // The nightly background test: proves Android still lets Jarvis's reminders fire while the phone sleeps.
        if (kind == "beat") {
            Health.beat(context, entry.getLong("millis"))
            AlarmScheduler.schedule(context, id, AlarmScheduler.nextDaily(entry.getLong("millis")), kind, label, true)
            return
        }

        if (kind == "checkin") {
            AlarmScheduler.remove(context, id)
            CheckNote.show(context, id, label)
            return
        }

        if (entry.getBoolean("repeat")) {
            AlarmScheduler.schedule(context, id, AlarmScheduler.nextDaily(entry.getLong("millis")), kind, label, true)
        } else {
            AlarmScheduler.remove(context, id)
        }

        val isAlarm = kind == "alarm"
        // An alarm of a task or event rings like a clock alarm, on the full screen, unless you turned that off.
        if (isAlarm && AlarmPrefs.fullAlarm(context)) {
            RingService.start(context, id, label, null, "alarm")
            return
        }
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
        // Reminders on the full screen: the notification asks for it (for a locked phone) and it is opened directly too.
        val full = !isAlarm && AlarmPrefs.fullNotice(context)
        if (full) {
            val screen = RingActivity.noticeIntent(context, id, kind, label)
            builder.setFullScreenIntent(
                PendingIntent.getActivity(context, id, screen, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE), true
            )
            try { context.startActivity(screen) } catch (_: Exception) {}
        }
        val notification = builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(if (isAlarm) "Alarm" else "Jarvis")
            .setContentText(label)
            .setStyle(Notification.BigTextStyle().bigText(label))
            .setCategory(if (isAlarm) Notification.CATEGORY_ALARM else Notification.CATEGORY_REMINDER)
            .setContentIntent(open)
            .setAutoCancel(true)
            .addAction(0, "Done", action(context, ActionReceiver.ACTION_DONE, id, kind, label))
            .addAction(0, "Snooze 10 min", action(context, ActionReceiver.ACTION_SNOOZE, id, kind, label))
            .addAction(Chat.replyAction(context, if (id >= ActionReceiver.SNOOZE_OFFSET) id - ActionReceiver.SNOOZE_OFFSET else id, id))
            .build()
        if (isAlarm) notification.flags = notification.flags or Notification.FLAG_INSISTENT
        manager.notify(id, notification)
    }

    private fun action(context: Context, action: String, id: Int, kind: String, label: String): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            id * 2 + (if (action == ActionReceiver.ACTION_DONE) 0 else 1),
            Intent(context, ActionReceiver::class.java)
                .setAction(action)
                .putExtra("id", id)
                .putExtra("kind", kind)
                .putExtra("label", label),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
}
