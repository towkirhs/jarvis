package com.towkirhs.jarcis

import android.app.AppOpsManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.Process
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/** Time in apps, read from Android's usage history (needs "Usage access" for Jarvis). */
object AppUsage {
    private val names = HashMap<String, String>()

    fun allowed(context: Context): Boolean {
        val ops = context.getSystemService(AppOpsManager::class.java)
        return ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName) ==
            AppOpsManager.MODE_ALLOWED
    }

    fun label(context: Context, pkg: String): String = names.getOrPut(pkg) {
        try {
            context.packageManager.getApplicationLabel(context.packageManager.getApplicationInfo(pkg, 0)).toString()
        } catch (_: Exception) {
            pkg
        }
    }

    /** Home screens and the system bars: time there is not time "in an app". */
    private fun skipped(context: Context): Set<String> {
        val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        return context.packageManager.queryIntentActivities(home, 0).map { it.activityInfo.packageName }.toSet() +
            "com.android.systemui"
    }

    /** Stretches of time with an app on screen between [from] and [to]: {pkg, name, start, end}. */
    fun sessions(context: Context, from: Long, to: Long): List<Map<String, Any>> {
        if (!allowed(context)) return emptyList()
        val usm = context.getSystemService(UsageStatsManager::class.java)
        val skip = skipped(context)
        val events = usm.queryEvents(from - 6 * 3600_000L, to)
        val e = UsageEvents.Event()
        val out = mutableListOf<Map<String, Any>>()
        var cur: String? = null
        var since = 0L
        fun close(t: Long) {
            val c = cur ?: return
            val s = maxOf(since, from)
            val end = minOf(t, to)
            if (end > s && c !in skip) out.add(mapOf("pkg" to c, "name" to label(context, c), "start" to s, "end" to end))
            cur = null
        }
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            when (e.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> if (cur != e.packageName) {
                    close(e.timeStamp)
                    cur = e.packageName
                    since = e.timeStamp
                }
                UsageEvents.Event.ACTIVITY_PAUSED, UsageEvents.Event.ACTIVITY_STOPPED -> if (cur == e.packageName) close(e.timeStamp)
                UsageEvents.Event.SCREEN_NON_INTERACTIVE, UsageEvents.Event.DEVICE_SHUTDOWN -> close(e.timeStamp)
            }
        }
        close(minOf(to, System.currentTimeMillis()))
        return out
    }

    /** Milliseconds per app since midnight. */
    fun today(context: Context): Map<String, Long> {
        val c = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        val totals = HashMap<String, Long>()
        for (s in sessions(context, c.timeInMillis, System.currentTimeMillis())) {
            val pkg = s["pkg"] as String
            totals[pkg] = (totals[pkg] ?: 0L) + (s["end"] as Long) - (s["start"] as Long)
        }
        return totals
    }

    /** Apps with an icon on the home screen: {pkg, name}, by name. */
    fun apps(context: Context): List<Map<String, String>> {
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return context.packageManager.queryIntentActivities(launcher, 0)
            .map { it.activityInfo.packageName }
            .distinct()
            .filter { it != context.packageName }
            .map { mapOf("pkg" to it, "name" to label(context, it)) }
            .sortedBy { it["name"]!!.lowercase() }
    }
}

/** Your app alarms, as set in Jarvis: [{id, pkg, when: open|today|sitting, min, ring, text}]. */
object AppAlarms {
    private fun prefs(context: Context) = context.getSharedPreferences("jarcis_apps", Context.MODE_PRIVATE)

    fun list(context: Context): JSONArray = JSONArray(prefs(context).getString("alarms", "[]"))

    fun set(context: Context, json: String) {
        prefs(context).edit().putString("alarms", json).apply()
        sync(context)
    }

    /** Runs the watcher while there is an app alarm and usage access; stops it otherwise. */
    fun sync(context: Context) {
        val want = list(context).length() > 0 && AppUsage.allowed(context)
        val intent = Intent(context, AppWatchService::class.java)
        try {
            if (want) context.startForegroundService(intent) else context.stopService(intent)
        } catch (_: Exception) {
            // Android may refuse to start it from the background; it starts the next time Jarvis opens.
        }
    }

    /** Fired today (once-a-day alarms) or for this stretch in the app (one-go alarms). */
    fun firedKey(context: Context, id: Int): String = prefs(context).getString("fired_$id", "") ?: ""

    fun markFired(context: Context, id: Int, key: String) {
        prefs(context).edit().putString("fired_$id", key).apply()
    }
}

/** Looks at which app is on screen every few seconds (only while the screen is on) and rings your app alarms. */
class AppWatchService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var running = false
    private var fg: String? = null
    private var fgSince = 0L
    private var lastQuery = 0L
    private var lastTotals = 0L
    private val lastOpen = HashMap<Int, Long>()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(QUIET, "App alarms running", NotificationManager.IMPORTANCE_MIN))
        val open = PendingIntent.getActivity(this, 9, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val note = Notification.Builder(this, QUIET)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("App alarms are on")
            .setContentText("Jarvis watches app time for the app alarms you set.")
            .setContentIntent(open)
            .build()
        startForeground(NOTE_ID, note, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        if (!running) {
            running = true
            handler.post(tick)
        }
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        handler.removeCallbacks(tick)
        super.onDestroy()
    }

    private val tick = object : Runnable {
        override fun run() {
            val on = getSystemService(PowerManager::class.java).isInteractive
            try {
                if (on) check() else fg = null
            } catch (_: Exception) {
            }
            if (running) handler.postDelayed(this, if (on) 3000L else 30_000L)
        }
    }

    private fun check() {
        val alarms = AppAlarms.list(this)
        if (alarms.length() == 0 || !AppUsage.allowed(this)) {
            stopSelf()
            return
        }
        val now = System.currentTimeMillis()
        val usm = getSystemService(UsageStatsManager::class.java)
        val events = usm.queryEvents(if (lastQuery == 0L) now - 60_000L else lastQuery - 1000L, now)
        lastQuery = now
        val e = UsageEvents.Event()
        var latest: String? = null
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            if (e.eventType == UsageEvents.Event.ACTIVITY_RESUMED) latest = e.packageName
        }
        // Jarvis's own screens (an alarm ringing) do not count as leaving the app.
        if (latest != null && latest != packageName && latest != fg) {
            fg = latest
            fgSince = now
            for (i in 0 until alarms.length()) {
                val a = alarms.getJSONObject(i)
                val id = a.optInt("id")
                if (a.optString("when") == "open" && a.optString("pkg") == latest && now - (lastOpen[id] ?: 0L) > 60_000L) {
                    lastOpen[id] = now
                    fire(a)
                }
            }
        }
        for (i in 0 until alarms.length()) {
            val a = alarms.getJSONObject(i)
            val id = a.optInt("id")
            val min = a.optInt("min", 60) * 60_000L
            if (a.optString("when") == "sitting" && a.optString("pkg") == fg && now - fgSince >= min &&
                AppAlarms.firedKey(this, id) != "$fgSince"
            ) {
                AppAlarms.markFired(this, id, "$fgSince")
                fire(a)
            }
        }
        if (now - lastTotals >= 60_000L) {
            lastTotals = now
            val today = String.format("%tF", now)
            val due = (0 until alarms.length()).map { alarms.getJSONObject(it) }
                .filter { it.optString("when") == "today" && AppAlarms.firedKey(this, it.optInt("id")) != today }
            if (due.isNotEmpty()) {
                val totals = AppUsage.today(this)
                for (a in due) {
                    if ((totals[a.optString("pkg")] ?: 0L) >= a.optInt("min", 60) * 60_000L) {
                        AppAlarms.markFired(this, a.optInt("id"), today)
                        fire(a)
                    }
                }
            }
        }
    }

    private fun fire(a: JSONObject) {
        val text = a.optString("text").ifEmpty { "App alarm" }
        if (a.optBoolean("ring")) {
            RingService.start(this, 0, text, null, "clock")
            return
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(LOUD, "App alarms", NotificationManager.IMPORTANCE_HIGH))
        val n = Notification.Builder(this, LOUD)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("Jarvis")
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setCategory(Notification.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .build()
        manager.notify(1_500_000_000 + Math.floorMod(a.optInt("id"), 100_000_000), n)
    }

    companion object {
        private const val NOTE_ID = 4471
        private const val QUIET = "appwatch"
        private const val LOUD = "appalarm"
    }
}
