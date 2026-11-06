package com.towkirhs.jarcis

import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Channel methods that work without a screen, shared by the app and the background runner. */
object NativeChannel {
    /** Returns false if the method isn't one of these. */
    fun handle(context: Context, call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "schedule" -> {
                AlarmScheduler.schedule(
                    context,
                    call.argument<Number>("id")!!.toInt(),
                    call.argument<Number>("millis")!!.toLong(),
                    call.argument<String>("kind") ?: "notice",
                    call.argument<String>("label") ?: "Reminder",
                    call.argument<Boolean>("repeatDaily") ?: false
                )
                result.success(null)
            }
            "cancel" -> {
                AlarmScheduler.cancel(context, call.argument<Number>("id")!!.toInt())
                result.success(null)
            }
            "takeNotes" -> result.success(NoteQueue.take(context))
            "takeDone" -> result.success(DoneQueue.take(context))
            "takeMoney" -> result.success(MoneyQueue.take(context))
            "moneyAccess" -> result.success(
                mapOf(
                    "sms" to (context.checkSelfPermission(android.Manifest.permission.RECEIVE_SMS) ==
                        android.content.pm.PackageManager.PERMISSION_GRANTED),
                    "notifications" to (android.provider.Settings.Secure.getString(
                        context.contentResolver, "enabled_notification_listeners"
                    )?.contains(context.packageName) == true)
                )
            )
            "openNotificationAccess" -> {
                context.startActivity(
                    Intent(android.provider.Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                result.success(null)
            }
            "getLog" -> result.success(AlarmLog.read(context))
            "notify" -> {
                Replies.show(context, call.argument<String>("title") ?: "Jarvis", call.argument<String>("text") ?: "")
                result.success(null)
            }
            else -> return false
        }
        return true
    }
}

/** Jarvis's answer to a note sent from outside the app (the bubble, share, a screenshot). */
object Replies {
    private const val CHANNEL = "replies"
    private const val ID = 2_100_000_000

    fun show(context: Context, title: String, text: String) {
        if (text.isBlank()) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        if (android.os.Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                android.app.NotificationChannel(CHANNEL, "Jarvis replies", android.app.NotificationManager.IMPORTANCE_DEFAULT)
            )
        }
        val open = android.app.PendingIntent.getActivity(
            context, 7, Intent(context, MainActivity::class.java), android.app.PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (android.os.Build.VERSION.SDK_INT >= 26) android.app.Notification.Builder(context, CHANNEL)
        else android.app.Notification.Builder(context)
        manager.notify(
            ID,
            builder.setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(android.app.Notification.BigTextStyle().bigText(text))
                .setContentIntent(open)
                .setAutoCancel(true)
                .build()
        )
    }
}
