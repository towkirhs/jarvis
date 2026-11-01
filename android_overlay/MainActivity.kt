package com.towkirhs.jarcis

import android.Manifest
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
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
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jarcis/spike")
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
                    val id = call.argument<Number>("id")!!.toInt()
                    val millis = call.argument<Number>("millis")!!.toLong()
                    val label = call.argument<String>("label") ?: "Alarm"
                    AlarmLog.add(this, "S|$id|$millis|${label.replace("\n", " ").replace("|", "/")}")
                    val alarms = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                    val fire = PendingIntent.getBroadcast(
                        this, id,
                        Intent(this, AlarmReceiver::class.java).putExtra("id", id).putExtra("label", label),
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    val show = PendingIntent.getActivity(
                        this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE
                    )
                    alarms.setAlarmClock(AlarmManager.AlarmClockInfo(millis, show), fire)
                    result.success(null)
                }
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
