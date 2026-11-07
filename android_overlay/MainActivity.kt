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
    private var pendingLaunch: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingShared = sharedTextFrom(intent)
        pendingLaunch = intent?.getStringExtra("jarvis_capture")
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jarcis/native")
        channel = ch
        live = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "takeLaunchAction" -> {
                    result.success(pendingLaunch)
                    pendingLaunch = null
                }
                "takeSharedText" -> {
                    result.success(pendingShared)
                    pendingShared = null
                }
                "requestVoicePermissions" -> {
                    requestPermissions(
                        arrayOf(Manifest.permission.RECORD_AUDIO, Manifest.permission.READ_CONTACTS, Manifest.permission.CALL_PHONE), 3
                    )
                    result.success(null)
                }
                "requestSmsPermission" -> {
                    requestPermissions(arrayOf(Manifest.permission.RECEIVE_SMS), 2)
                    result.success(null)
                }
                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= 33) {
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
                    }
                    result.success(null)
                }
                else -> if (!NativeChannel.handle(this, call, result)) result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        if (live === channel) live = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        sharedTextFrom(intent)?.let { channel?.invokeMethod("sharedText", it) }
        intent.getStringExtra("jarvis_capture")?.let { channel?.invokeMethod("launchAction", it) }
    }

    private fun sharedTextFrom(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_SEND) return null
        if (intent.type?.startsWith("text/") != true) return null
        return intent.getStringExtra(Intent.EXTRA_TEXT)
    }

    companion object {
        /** The open app's channel, or null when the app's screen isn't alive. */
        var live: MethodChannel? = null
    }
}
