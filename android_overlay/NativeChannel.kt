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
            "command" -> {
                // A phone action ("open WhatsApp", "call Oishi on WhatsApp"), or null if it is an ordinary note.
                val text = call.argument<String>("text") ?: ""
                val cmd = Commands.parse(context, text)
                if (cmd == null) {
                    result.success(null)
                } else {
                    try {
                        result.success(Commands.run(context, cmd))
                    } catch (e: Exception) {
                        result.success("Couldn't: ${e.message}")
                    }
                }
            }
            "setShortcuts" -> {
                Commands.setShortcuts(context, call.argument<String>("json") ?: "{}")
                result.success(null)
            }
            "takeCommandLog" -> result.success(Commands.takeLog(context))
            "wake" -> {
                val on = call.argument<Boolean>("on") == true
                val key = call.argument<String>("key")
                if (key != null) {
                    context.getSharedPreferences("jarcis_cmds", Context.MODE_PRIVATE).edit().putString("picovoice", key).apply()
                }
                if (on) WakeService.start(context) else WakeService.stop(context)
                result.success(null)
            }
            "voiceAccess" -> {
                fun has(p: String) = context.checkSelfPermission(p) == android.content.pm.PackageManager.PERMISSION_GRANTED
                result.success(mapOf(
                    "mic" to has(android.Manifest.permission.RECORD_AUDIO),
                    "contacts" to has(android.Manifest.permission.READ_CONTACTS),
                    "call" to has(android.Manifest.permission.CALL_PHONE),
                    "overlay" to Overlay.allowed(context),
                    "wake" to WakeService.running,
                ))
            }
            "openOverlaySettings" -> {
                context.startActivity(
                    Intent(android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION, android.net.Uri.parse("package:${context.packageName}"))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                result.success(null)
            }
            "haptic" -> {
                // Android's named haptics: crisp, tuned per phone, and they follow the system touch-feedback setting.
                val view = (context as? android.app.Activity)?.window?.decorView
                val sdk = android.os.Build.VERSION.SDK_INT
                val effect = when (call.argument<String>("kind")) {
                    "confirm" -> if (sdk >= 30) android.view.HapticFeedbackConstants.CONFIRM else android.view.HapticFeedbackConstants.VIRTUAL_KEY
                    "reject" -> if (sdk >= 30) android.view.HapticFeedbackConstants.REJECT else android.view.HapticFeedbackConstants.LONG_PRESS
                    "toggleOn" -> if (sdk >= 34) android.view.HapticFeedbackConstants.TOGGLE_ON else android.view.HapticFeedbackConstants.CLOCK_TICK
                    "toggleOff" -> if (sdk >= 34) android.view.HapticFeedbackConstants.TOGGLE_OFF else android.view.HapticFeedbackConstants.CLOCK_TICK
                    "gestureStart" -> if (sdk >= 30) android.view.HapticFeedbackConstants.GESTURE_START else android.view.HapticFeedbackConstants.LONG_PRESS
                    "gestureEnd" -> if (sdk >= 30) android.view.HapticFeedbackConstants.GESTURE_END else android.view.HapticFeedbackConstants.CLOCK_TICK
                    "segment" -> if (sdk >= 34) android.view.HapticFeedbackConstants.SEGMENT_TICK else android.view.HapticFeedbackConstants.CLOCK_TICK
                    "longPress" -> android.view.HapticFeedbackConstants.LONG_PRESS
                    "key" -> android.view.HapticFeedbackConstants.VIRTUAL_KEY
                    else -> android.view.HapticFeedbackConstants.CLOCK_TICK
                }
                result.success(view?.performHapticFeedback(effect) ?: false)
            }
            "notify" -> {
                Chat.jarvisSays(context, call.argument<String>("text") ?: "")
                result.success(null)
            }
            else -> return false
        }
        return true
    }
}
