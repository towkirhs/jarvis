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
    private var hearing: MethodChannel.Result? = null
    private var started = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingShared = sharedTextFrom(intent)
        pendingLaunch = intent?.getStringExtra("jarvis_capture").takeIf { it != "text" }
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
                "keepAwake" -> {
                    // The screen stays on while a focus timer runs, if you asked for that.
                    if (call.argument<Boolean>("on") == true) {
                        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                "requestLocation" -> {
                    // Android asks for "all the time" separately, after "while using the app" is given.
                    val fine = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
                        android.content.pm.PackageManager.PERMISSION_GRANTED
                    requestPermissions(
                        if (fine) arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
                        else arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
                        4
                    )
                    result.success(null)
                }
                "hear" -> {
                    // The mic in the chat bar: the phone's own speech screen, its text comes back to the box.
                    hearing?.success(null)
                    hearing = result
                    try {
                        startActivityForResult(ListenActivity.speechIntent(this), HEAR)
                    } catch (e: Exception) {
                        hearing = null
                        result.success(null)
                    }
                }
                "requestCalendar" -> {
                    requestPermissions(arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR), 5)
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

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != HEAR) return
        val text = data?.getStringArrayListExtra(android.speech.RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()?.trim()
        hearing?.success(if (resultCode == RESULT_OK) text else null)
        hearing = null
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        if (live === channel) live = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /** The bubble's "text" opens the small typing card over what you are doing, not the whole app. */
    private fun typingCard(intent: Intent?): Boolean {
        if (intent?.getStringExtra("jarvis_capture") != "text") return false
        startActivity(Intent(this, TypeActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        return true
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null && typingCard(intent)) finish()
    }

    override fun onStart() {
        super.onStart()
        started = true
    }

    override fun onStop() {
        started = false
        super.onStop()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (typingCard(intent)) {
            // Jarvis was in the background: put it back there, so only the card shows.
            if (!started) moveTaskToBack(true)
            return
        }
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
        private const val HEAR = 7
    }
}
