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
            "clock" -> {
                AlarmScheduler.schedule(
                    context,
                    call.argument<Number>("id")!!.toInt(),
                    call.argument<Number>("millis")!!.toLong(),
                    "clock",
                    call.argument<String>("label") ?: "Alarm",
                    false,
                    call.argument<Number>("days")?.toInt() ?: 0,
                    call.argument<String>("sound")
                )
                result.success(null)
            }
            "ringNow" -> {
                RingService.start(context, 0, call.argument<String>("label") ?: "Test alarm", call.argument<String>("sound"))
                result.success(null)
            }
            "geofences" -> {
                Geo.set(context, call.argument<String>("json") ?: "[]")
                result.success(null)
            }
            "takeGeoFired" -> result.success(GeoQueue.take(context))
            "calendarAccess" -> result.success(PhoneCalendar.allowed(context))
            "calendars", "calendarInstances", "calendarInsert", "calendarUpdate", "calendarDelete", "calendarEvent", "calendarOpen" -> {
                if (!PhoneCalendar.allowed(context)) {
                    result.success(null)
                } else {
                    try {
                        when (call.method) {
                            "calendars" -> result.success(PhoneCalendar.calendars(context))
                            "calendarInstances" -> result.success(
                                PhoneCalendar.instances(
                                    context,
                                    call.argument<Number>("from")!!.toLong(),
                                    call.argument<Number>("to")!!.toLong(),
                                    call.argument<List<Number>>("ids")!!.map { it.toLong() }
                                )
                            )
                            "calendarInsert" -> result.success(
                                PhoneCalendar.insert(context, call.argument<Number>("cal")!!.toLong(), call.argument<String>("json")!!)
                            )
                            "calendarUpdate" -> result.success(
                                PhoneCalendar.update(context, call.argument<Number>("ev")!!.toLong(), call.argument<String>("json")!!)
                            )
                            "calendarDelete" -> result.success(PhoneCalendar.delete(context, call.argument<Number>("ev")!!.toLong()))
                            "calendarEvent" -> result.success(PhoneCalendar.event(context, call.argument<Number>("ev")!!.toLong()))
                            else -> {
                                PhoneCalendar.open(context, call.argument<Number>("ev")!!.toLong())
                                result.success(null)
                            }
                        }
                    } catch (e: Exception) {
                        result.error("calendar", e.message, null)
                    }
                }
            }
            "locationAccess" -> result.success(Geo.access(context))
            "here" -> Geo.here(context, result)
            "openUrl" -> {
                try {
                    context.startActivity(
                        Intent(Intent.ACTION_VIEW, android.net.Uri.parse(call.argument<String>("url")))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                } catch (_: Exception) {
                    // No browser to open it.
                }
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
                        val did = Commands.run(context, cmd)
                        if (!cmd.quiet) Speaker.say(context, did, if (cmd.kind in setOf("time", "battery")) "answer" else "confirm", false)
                        result.success(did)
                    } catch (e: Exception) {
                        Speaker.say(context, e.message ?: "", "problem", false)
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
                val threshold = call.argument<Number>("threshold")
                if (threshold != null) {
                    context.getSharedPreferences("jarcis_cmds", Context.MODE_PRIVATE).edit()
                        .putFloat("wake_threshold", threshold.toFloat()).apply()
                }
                if (on) WakeService.start(context) else WakeService.stop(context)
                result.success(null)
            }
            "speechLang" -> {
                context.getSharedPreferences("jarcis_cmds", Context.MODE_PRIVATE).edit()
                    .putString("speech_lang", call.argument<String>("lang") ?: "").apply()
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
                val text = call.argument<String>("text") ?: ""
                val spoken = call.argument<Boolean>("spoken") == true
                Chat.jarvisSays(context, text)
                // Said aloud if your Voice replies allow it; then, if you like, it listens for a follow-up.
                Speaker.say(context, text, "answer", spoken) {
                    if (spoken && Speaker.settings(context).optBoolean("followUp", true)) ListenActivity.open(context, true)
                }
                result.success(null)
            }
            "speak" -> {
                Speaker.say(
                    context, call.argument<String>("text") ?: "", call.argument<String>("kind") ?: "answer",
                    call.argument<Boolean>("spoken") == true
                )
                result.success(null)
            }
            "speakTest" -> {
                Speaker.speak(context, call.argument<String>("text") ?: "Hello, I'm Jarvis.")
                result.success(null)
            }
            "setSpeech" -> {
                Speaker.setSettings(context, call.argument<String>("json") ?: "{}")
                result.success(null)
            }
            "voices" -> result.success(Speaker.voices(context))
            "takeNewClocks" -> result.success(NewClocks.take(context))
            "appBuild" -> result.success(Updater.build(context))
            "canInstall" -> result.success(Updater.canInstall(context))
            "openInstallAccess" -> {
                Updater.openInstallAccess(context)
                result.success(null)
            }
            "installApk" -> Updater.install(context, call.argument<String>("path")!!) { result.success(it) }
            else -> return false
        }
        return true
    }
}
