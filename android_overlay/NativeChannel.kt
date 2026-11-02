package com.towkirhs.jarcis

import android.content.Context
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
            "getLog" -> result.success(AlarmLog.read(context))
            else -> return false
        }
        return true
    }
}
