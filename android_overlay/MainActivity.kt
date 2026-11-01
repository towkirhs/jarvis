package com.towkirhs.jarcis

import android.Manifest
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingShared: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingShared = sharedTextFrom(intent)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jarcis/native")
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "takeSharedText" -> {
                    result.success(pendingShared)
                    pendingShared = null
                }
                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= 33) {
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
                    }
                    result.success(null)
                }
                "schedule" -> {
                    AlarmScheduler.schedule(
                        this,
                        call.argument<Number>("id")!!.toInt(),
                        call.argument<Number>("millis")!!.toLong(),
                        call.argument<String>("kind") ?: "notice",
                        call.argument<String>("label") ?: "Reminder",
                        call.argument<Boolean>("repeatDaily") ?: false
                    )
                    result.success(null)
                }
                "cancel" -> {
                    AlarmScheduler.cancel(this, call.argument<Number>("id")!!.toInt())
                    result.success(null)
                }
                "takeNotes" -> result.success(NoteQueue.take(this))
                "getLog" -> result.success(AlarmLog.read(this))
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        sharedTextFrom(intent)?.let { channel?.invokeMethod("sharedText", it) }
    }

    private fun sharedTextFrom(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_SEND) return null
        if (intent.type?.startsWith("text/") != true) return null
        return intent.getStringExtra(Intent.EXTRA_TEXT)
    }
}
