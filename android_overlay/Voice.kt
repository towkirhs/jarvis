package com.towkirhs.jarcis

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.hardware.camera2.CameraManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.ContactsContract
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.app.SearchManager
import android.os.BatteryManager
import android.provider.MediaStore
import android.view.KeyEvent
import org.json.JSONObject
import java.util.Calendar

/**
 * Small phone actions by voice or text: open an app, open a WhatsApp chat, call someone (WhatsApp or phone,
 * after a 3 second countdown you can cancel), text, torch, YouTube, directions. Jarvis never sends a message
 * by itself: chats open with the text filled in, and you press send.
 */
object Commands {
    /** [quiet]: one of your own commands set not to speak its confirmation. */
    data class Cmd(val kind: String, val target: String, val text: String? = null, val quiet: Boolean = false)

    private const val PREFS = "jarcis_cmds"
    private val main = Handler(Looper.getMainLooper())
    private var pendingCall: Runnable? = null

    /** Your nicknames ("oishi" -> a contact name or number) and phrases ("gym music" -> an action). */
    fun setShortcuts(context: Context, json: String) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("shortcuts", json).apply()

    private fun shortcuts(context: Context): JSONObject =
        JSONObject(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("shortcuts", "{}") ?: "{}")

    private val timeWords = Regex(
        "\\b(at \\d|by \\d|tomorrow|tonight|today|next|later|remind|in \\d+ (min|minute|hour|day)s?|on (mon|tue|wed|thu|fri|sat|sun))"
    )

    fun isOwnPhrase(context: Context, text: String): Boolean =
        shortcuts(context).optJSONObject("phrases")?.has(text.trim().lowercase().replace(Regex("[.!?]+$"), "")) == true

    /** A command, or null if this is an ordinary note (a reminder like "call Ammu at 8" stays a note). */
    fun parse(context: Context, raw: String): Cmd? = parseText(raw, shortcuts(context).optJSONObject("phrases"))

    private val numberWords = mapOf(
        "a" to 1, "an" to 1, "one" to 1, "two" to 2, "three" to 3, "four" to 4, "five" to 5, "six" to 6, "seven" to 7,
        "eight" to 8, "nine" to 9, "ten" to 10, "fifteen" to 15, "twenty" to 20, "thirty" to 30, "forty" to 40,
        "forty five" to 45, "sixty" to 60, "ninety" to 90,
    )

    /** [parse] without the phone: [phrases] are your own commands ({phrase: {kind, target, text, speak}}). */
    fun parseText(raw: String, phrases: JSONObject?): Cmd? {
        var t = raw.trim().lowercase().replace(Regex("[.!?]+$"), "")
        t = t.replace(Regex("^(hey |ok |okay )?jarvis[,:]?\\s*"), "").replace(Regex("^please\\s+"), "").trim()
        if (t.isEmpty()) return null
        // Your own phrases first.
        if (phrases != null && phrases.has(t)) {
            val p = phrases.getJSONObject(t)
            return Cmd(p.getString("kind"), p.getString("target"), p.optString("text").ifEmpty { null }, !p.optBoolean("speak", true))
        }
        // Stop talking.
        if (t in setOf("stop", "stop talking", "be quiet", "quiet", "shut up", "enough", "thanks", "thank you")) return Cmd("hush", "")
        // Quick questions answered on the phone.
        if (Regex("^(what(?:'s| is) the time|what time is it|tell me the time|time)( now)?$").matches(t)) return Cmd("time", "")
        if (Regex("^(?:what(?:'s| is) (?:the |my )?)?battery(?: level| percentage| left)?$|^how much battery(?: is left| do i have| left)?$").matches(t)) {
            return Cmd("battery", "")
        }
        // Music and sound.
        if (Regex("^(?:pause|pause (?:the )?(?:music|song|video)|stop (?:the )?(?:music|song))$").matches(t)) return Cmd("media", "pause")
        if (Regex("^(?:resume|play|continue|(?:resume|play) (?:the )?music)$").matches(t)) return Cmd("media", "play")
        if (Regex("^(?:next|skip)(?: (?:song|track))?$|^skip (?:this )?(?:song|track)$|^next one$").matches(t)) return Cmd("media", "next")
        if (Regex("^(?:previous|last)(?: (?:song|track))?$|^go back a (?:song|track)$").matches(t)) return Cmd("media", "previous")
        if (Regex("^(?:volume up|turn (?:it|the volume) up|louder|increase (?:the )?volume)$").matches(t)) return Cmd("volume", "up")
        if (Regex("^(?:volume down|turn (?:it|the volume) down|quieter|softer|lower (?:the )?volume|decrease (?:the )?volume)$").matches(t)) {
            return Cmd("volume", "down")
        }
        if (Regex("^mute(?: (?:the )?(?:volume|sound|media|music))?$").matches(t)) return Cmd("volume", "mute")
        if (Regex("^unmute(?: (?:the )?(?:volume|sound|media|music))?$").matches(t)) return Cmd("volume", "unmute")
        if (Regex("^(?:max|full) volume$|^volume (?:to )?(?:max|full)$").matches(t)) return Cmd("volume", "100")
        Regex("^(?:set )?(?:the )?volume (?:to |at )?(\\d{1,3})(?: ?%| percent)?$").find(t)?.let {
            return Cmd("volume", it.groupValues[1].toInt().coerceIn(0, 100).toString())
        }
        Regex("^(?:play|put on) (.+?) on spotify$").find(t)?.let { return Cmd("play_in", SPOTIFY, it.groupValues[1]) }
        Regex("^(?:play|put on) (.+?) on youtube music$").find(t)?.let { return Cmd("play_in", YT_MUSIC, it.groupValues[1]) }
        // Ringer and Do Not Disturb.
        if (Regex("^(?:silent mode|silent|silence (?:my |the )?phone|put (?:my |the )?phone on silent)$").matches(t)) return Cmd("ringer", "silent")
        if (Regex("^(?:vibrate mode|vibrate|vibration mode|put (?:my |the )?phone on vibrate)$").matches(t)) return Cmd("ringer", "vibrate")
        if (Regex("^(?:ring mode|normal mode|sound mode|sound on|ringer on|turn (?:the )?sound (?:back )?on)$").matches(t)) return Cmd("ringer", "normal")
        Regex("^(?:turn |switch )?(on |off )?(?:do not disturb|dnd)(?: mode)?(?: (on|off))?$").find(t)?.let {
            return Cmd("dnd", it.groupValues[1].trim().ifEmpty { it.groupValues[2].ifEmpty { "on" } })
        }
        // Timers and alarms (before the time-word check below, which would make them notes).
        val num = "(\\d+|${numberWords.keys.sortedByDescending { it.length }.joinToString("|")})"
        val unit = "(seconds?|secs?|minutes?|mins?|hours?|hrs?)"
        (Regex("^(?:set |start )?(?:a |the )?timer (?:for )?$num ?$unit$").find(t)
            ?: Regex("^(?:set |start )?(?:a |an )?$num ?$unit timer$").find(t))?.let {
            val n = it.groupValues[1].toIntOrNull() ?: numberWords[it.groupValues[1]] ?: return null
            val secs = n * when (it.groupValues[2].first()) { 's' -> 1; 'm' -> 60; else -> 3600 }
            return Cmd("timer", secs.toString())
        }
        if (Regex("^(?:cancel|stop|delete) (?:the |my )?timer$").matches(t)) return Cmd("timer_cancel", "")
        Regex(
            "^(?:wake me(?: up)?|set (?:an |the |my )?alarm|alarm)(?: for| at)?(?: at)? (\\d{1,2})(?:[:. ](\\d{2}))? ?(a\\.? ?m|p\\.? ?m)?\\.?(?: tomorrow(?: morning)?)?$"
        ).find(t)?.let {
            val h = it.groupValues[1].toInt()
            val m = it.groupValues[2].ifEmpty { "0" }.toInt()
            if (h > 23 || m > 59) return null
            val half = when (it.groupValues[3].firstOrNull()) { 'a' -> "am"; 'p' -> "pm"; else -> null }
            return Cmd("alarm", "%02d:%02d".format(h, m), half)
        }
        if (Regex("^(?:take a (?:photo|picture|selfie)|open (?:the )?camera)$").matches(t)) return Cmd("camera", "")
        if (timeWords.containsMatchIn(t)) return null
        Regex("^video call (.+?) on whatsapp$").find(t)?.let { return Cmd("wa_video", it.groupValues[1]) }
        Regex("^(?:call|ring) (.+?) on whatsapp$").find(t)?.let { return Cmd("wa_call", it.groupValues[1]) }
        Regex("^whatsapp call (.+)$").find(t)?.let { return Cmd("wa_call", it.groupValues[1]) }
        Regex("^(?:message|text|msg|send a message to) (.+?) on whatsapp(?:\\s*(?:saying|that|:)\\s*(.+))?$").find(t)?.let {
            return Cmd("wa_chat", it.groupValues[1], it.groupValues[2].ifEmpty { null })
        }
        Regex("^whatsapp (.+?)(?:\\s*(?:saying|that|:)\\s*(.+))?$").find(t)?.let {
            return Cmd("wa_chat", it.groupValues[1], it.groupValues[2].ifEmpty { null })
        }
        Regex("^(?:call|phone|dial|ring) (.+)$").find(t)?.let { return Cmd("call", it.groupValues[1]) }
        Regex("^(?:sms|text) (.+?)(?:\\s*(?:saying|that|:)\\s*(.+))?$").find(t)?.let {
            return Cmd("sms", it.groupValues[1], it.groupValues[2].ifEmpty { null })
        }
        Regex("^(?:turn |switch )?(on|off) (?:the )?(?:flashlight|torch|flash)$").find(t)?.let { return Cmd("torch", it.groupValues[1]) }
        Regex("^(?:flashlight|torch|flash) (on|off)$").find(t)?.let { return Cmd("torch", it.groupValues[1]) }
        Regex("^play (.+?) on youtube$").find(t)?.let { return Cmd("youtube", it.groupValues[1]) }
        Regex("^(?:search )?youtube (?:for )?(.+)$").find(t)?.let { return Cmd("youtube", it.groupValues[1]) }
        Regex("^(?:navigate|directions|take me|go) to (.+)$").find(t)?.let { return Cmd("maps", it.groupValues[1]) }
        Regex("^(?:open|launch|start) (?:the )?(.+?)(?: app)?$").find(t)?.let { return Cmd("app", it.groupValues[1]) }
        return null
    }

    /** Runs [cmd]. Returns what happened, in a few words, or throws with what went wrong. */
    fun run(context: Context, cmd: Cmd): String {
        return when (cmd.kind) {
            "app" -> openApp(context, cmd.target)
            "link" -> {
                start(context, Intent(Intent.ACTION_VIEW, Uri.parse(cmd.target)))
                "Opened ${cmd.target}"
            }
            "wa_chat" -> {
                val (name, number) = person(context, cmd.target)
                val url = "https://api.whatsapp.com/send?phone=${waNumber(number)}" +
                    (cmd.text?.let { "&text=" + Uri.encode(it) } ?: "")
                start(context, Intent(Intent.ACTION_VIEW, Uri.parse(url)).setPackage("com.whatsapp"))
                "Opened WhatsApp chat with $name" + (if (cmd.text != null) ", message ready to send" else "")
            }
            "wa_call", "wa_video" -> {
                val (name, _) = person(context, cmd.target)
                val mime = if (cmd.kind == "wa_video") "vnd.android.cursor.item/vnd.com.whatsapp.video.call"
                else "vnd.android.cursor.item/vnd.com.whatsapp.voip.call"
                val id = whatsappRow(context, name, mime)
                    ?: throw Exception("$name has no WhatsApp ${if (cmd.kind == "wa_video") "video " else ""}call in your contacts")
                val intent = Intent(Intent.ACTION_VIEW).setDataAndType(
                    Uri.parse("content://com.android.contacts/data/$id"), mime
                ).setPackage("com.whatsapp")
                countdown(context, "${if (cmd.kind == "wa_video") "Video calling" else "Calling"} $name on WhatsApp") { start(context, intent) }
                "Calling $name on WhatsApp"
            }
            "call" -> {
                val (name, number) = person(context, cmd.target)
                val direct = context.checkSelfPermission(Manifest.permission.CALL_PHONE) == PackageManager.PERMISSION_GRANTED
                val intent = Intent(if (direct) Intent.ACTION_CALL else Intent.ACTION_DIAL, Uri.parse("tel:$number"))
                if (direct) countdown(context, "Calling $name") { start(context, intent) } else start(context, intent)
                if (direct) "Calling $name" else "Opened the dialer for $name"
            }
            "sms" -> {
                val (name, number) = person(context, cmd.target)
                val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:$number"))
                cmd.text?.let { intent.putExtra("sms_body", it) }
                start(context, intent)
                "Opened a text to $name"
            }
            "torch" -> {
                val cm = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
                val id = cm.cameraIdList.firstOrNull() ?: throw Exception("No flashlight")
                cm.setTorchMode(id, cmd.target == "on")
                "Flashlight ${cmd.target}"
            }
            "youtube" -> {
                start(context, Intent(Intent.ACTION_VIEW, Uri.parse("https://www.youtube.com/results?search_query=" + Uri.encode(cmd.target))))
                "Searching YouTube for ${cmd.target}"
            }
            "maps" -> {
                start(context, Intent(Intent.ACTION_VIEW, Uri.parse("google.navigation:q=" + Uri.encode(cmd.target))))
                "Directions to ${cmd.target}"
            }
            // One of your own commands that runs built-in commands: "silent mode then set an alarm for 6:30".
            "do" -> cmd.target.split(Regex("\\s+then\\s+|\\s*;\\s*")).filter { it.isNotBlank() }.joinToString(". ") { step ->
                val inner = parseText(step, null) ?: throw Exception("\"$step\" is not a command Jarvis knows")
                run(context, inner)
            }
            "hush" -> {
                Speaker.stop()
                ""
            }
            "time" -> "It's " + android.text.format.DateFormat.getTimeFormat(context).format(java.util.Date())
            "battery" -> {
                val bm = context.getSystemService(BatteryManager::class.java)
                val pct = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                "Battery is at $pct%" + if (bm.isCharging) ", charging" else ""
            }
            "media" -> {
                val am = context.getSystemService(AudioManager::class.java)
                val code = when (cmd.target) {
                    "pause" -> KeyEvent.KEYCODE_MEDIA_PAUSE
                    "play" -> KeyEvent.KEYCODE_MEDIA_PLAY
                    "next" -> KeyEvent.KEYCODE_MEDIA_NEXT
                    else -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
                }
                am.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, code))
                am.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, code))
                when (cmd.target) { "pause" -> "Paused"; "play" -> "Playing"; "next" -> "Next song"; else -> "Previous song" }
            }
            "volume" -> {
                val am = context.getSystemService(AudioManager::class.java)
                val s = AudioManager.STREAM_MUSIC
                val ui = AudioManager.FLAG_SHOW_UI
                when (cmd.target) {
                    "up" -> repeat(2) { am.adjustStreamVolume(s, AudioManager.ADJUST_RAISE, ui) }
                    "down" -> repeat(2) { am.adjustStreamVolume(s, AudioManager.ADJUST_LOWER, ui) }
                    "mute" -> am.adjustStreamVolume(s, AudioManager.ADJUST_MUTE, ui)
                    "unmute" -> am.adjustStreamVolume(s, AudioManager.ADJUST_UNMUTE, ui)
                    else -> am.setStreamVolume(s, am.getStreamMaxVolume(s) * cmd.target.toInt() / 100, ui)
                }
                when (cmd.target) {
                    "up" -> "Volume up"; "down" -> "Volume down"; "mute" -> "Muted"; "unmute" -> "Unmuted"
                    else -> "Volume at ${cmd.target}%"
                }
            }
            "play_in" -> {
                val app = if (cmd.target == SPOTIFY) "Spotify" else "YouTube Music"
                val intent = Intent(MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH)
                    .setPackage(cmd.target)
                    .putExtra(SearchManager.QUERY, cmd.text)
                    .putExtra(MediaStore.EXTRA_MEDIA_FOCUS, "vnd.android.cursor.item/*")
                try {
                    start(context, intent)
                } catch (e: Exception) {
                    throw Exception("$app is not installed")
                }
                "Playing ${cmd.text} on $app"
            }
            "ringer" -> {
                val am = context.getSystemService(AudioManager::class.java)
                needPolicyAccess(context)
                am.ringerMode = when (cmd.target) {
                    "silent" -> AudioManager.RINGER_MODE_SILENT
                    "vibrate" -> AudioManager.RINGER_MODE_VIBRATE
                    else -> AudioManager.RINGER_MODE_NORMAL
                }
                when (cmd.target) { "silent" -> "Phone on silent"; "vibrate" -> "Phone on vibrate"; else -> "Sound on" }
            }
            "dnd" -> {
                needPolicyAccess(context)
                context.getSystemService(NotificationManager::class.java).setInterruptionFilter(
                    if (cmd.target == "on") NotificationManager.INTERRUPTION_FILTER_PRIORITY else NotificationManager.INTERRUPTION_FILTER_ALL
                )
                "Do not disturb ${cmd.target}"
            }
            "timer" -> {
                val secs = cmd.target.toInt()
                val id = TIMER_ID
                val label = "Timer, ${span(secs)}"
                AlarmScheduler.schedule(context, id, System.currentTimeMillis() + secs * 1000L, "clock", label, false, 0, null)
                "Timer set for ${span(secs)}"
            }
            "timer_cancel" -> {
                AlarmScheduler.cancel(context, TIMER_ID)
                "Timer cancelled"
            }
            "alarm" -> {
                val (h, m) = cmd.target.split(":").map { it.toInt() }
                val at = nextAlarm(h, m, cmd.text, Calendar.getInstance())
                val id = ALARM_ID_BASE + ((at / 60000) % 1_000_000).toInt()
                AlarmScheduler.schedule(context, id, at, "clock", "Alarm", false, 0, null)
                NewClocks.add(context, id, at)
                val left = (at - System.currentTimeMillis()) / 60000 + 1
                "Alarm set for " + android.text.format.DateFormat.getTimeFormat(context).format(java.util.Date(at)) +
                    ", in ${span(left.toInt() * 60)}"
            }
            "camera" -> {
                start(context, Intent(MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA))
                "Opened the camera"
            }
            else -> throw Exception("I don't know how to do that yet")
        }
    }

    const val SPOTIFY = "com.spotify.music"
    const val YT_MUSIC = "com.google.android.apps.youtube.music"
    private const val TIMER_ID = 1_799_999_999
    const val ALARM_ID_BASE = 1_800_000_000

    /** "10 minutes", "1 hour 30 minutes", "45 seconds". */
    fun span(secs: Int): String {
        if (secs < 60) return "$secs second${if (secs == 1) "" else "s"}"
        val h = secs / 3600
        val m = (secs % 3600) / 60
        val parts = mutableListOf<String>()
        if (h > 0) parts.add("$h hour${if (h == 1) "" else "s"}")
        if (m > 0) parts.add("$m minute${if (m == 1) "" else "s"}")
        return parts.joinToString(" ")
    }

    /**
     * When "wake me at [h]:[m]" rings: the next time it comes. Without am or pm ([half] null), an hour of 1 to 12
     * means whichever of the morning or evening time comes first.
     */
    fun nextAlarm(h: Int, m: Int, half: String?, now: Calendar): Long {
        val hours = when {
            half == "am" -> listOf(if (h == 12) 0 else h)
            half == "pm" -> listOf(if (h == 12) 12 else h + 12)
            h in 1..12 -> listOf(h % 12, h % 12 + 12)
            else -> listOf(h)
        }
        return hours.map { hour ->
            (now.clone() as Calendar).apply {
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, m)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
                if (timeInMillis <= now.timeInMillis) add(Calendar.DAY_OF_MONTH, 1)
            }.timeInMillis
        }.min()
    }

    /** Silent mode and Do Not Disturb need Android's "Do Not Disturb access"; opens that screen if missing. */
    private fun needPolicyAccess(context: Context) {
        if (context.getSystemService(NotificationManager::class.java).isNotificationPolicyAccessGranted) return
        start(context, Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
        throw Exception("Allow Do Not Disturb access for Jarvis, then say it again")
    }

    private fun start(context: Context, intent: Intent) {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(intent)
        } catch (e: Exception) {
            throw Exception("No app on this phone can do that")
        }
    }

    private fun openApp(context: Context, name: String): String {
        val alias = shortcuts(context).optJSONObject("apps")?.optString(name)?.ifEmpty { null } ?: name
        val pm = context.packageManager
        val apps = pm.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), 0)
        val want = alias.lowercase()
        val labelled = apps.map { it to it.loadLabel(pm).toString() }
        val hit = labelled.firstOrNull { it.second.lowercase() == want }
            ?: labelled.firstOrNull { it.second.lowercase().startsWith(want) }
            ?: labelled.firstOrNull { it.second.lowercase().contains(want) }
            ?: throw Exception("No app called $name")
        val launch = pm.getLaunchIntentForPackage(hit.first.activityInfo.packageName) ?: throw Exception("Can't open ${hit.second}")
        start(context, launch)
        return "Opened ${hit.second}"
    }

    /** A person from your nicknames or contacts: (name, number). */
    private fun person(context: Context, said: String): Pair<String, String> {
        val nick = shortcuts(context).optJSONObject("people")?.optString(said.lowercase())?.ifEmpty { null }
        val query = nick ?: said
        if (query.replace(Regex("[^0-9+]"), "").length >= 7 && query.any { it.isDigit() } && !query.any { it.isLetter() }) {
            return said to query
        }
        if (context.checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) {
            throw Exception("Allow Jarvis to read contacts (Settings, Hey Jarvis)")
        }
        val c = context.contentResolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME, ContactsContract.CommonDataKinds.Phone.NUMBER),
            "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ?", arrayOf("%$query%"), null
        ) ?: throw Exception("Can't read contacts")
        val found = mutableListOf<Pair<String, String>>()
        c.use { while (it.moveToNext()) found.add(it.getString(0) to it.getString(1)) }
        val q = query.lowercase()
        return found.firstOrNull { it.first.lowercase() == q }
            ?: found.firstOrNull { it.first.lowercase().startsWith(q) }
            ?: found.firstOrNull()
            ?: throw Exception("No contact called $said. Add a nickname in Settings, Hey Jarvis")
    }

    /** Digits in international form for WhatsApp; Bangladeshi 01… numbers get 880. */
    private fun waNumber(number: String): String {
        var d = number.replace(Regex("[^0-9]"), "")
        if (d.startsWith("00")) d = d.substring(2)
        if (d.length == 11 && d.startsWith("01")) d = "88$d"
        return d
    }

    private fun whatsappRow(context: Context, name: String, mime: String): Long? {
        if (context.checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) return null
        val c = context.contentResolver.query(
            ContactsContract.Data.CONTENT_URI, arrayOf(ContactsContract.Data._ID),
            "${ContactsContract.Data.MIMETYPE} = ? AND ${ContactsContract.Data.DISPLAY_NAME} = ?", arrayOf(mime, name), null
        ) ?: return null
        return c.use { if (it.moveToFirst()) it.getLong(0) else null }
    }

    /** Waits 3 seconds with a Cancel button, then does [action]. */
    private fun countdown(context: Context, what: String, action: () -> Unit) {
        pendingCall?.let { main.removeCallbacks(it) }
        val go = Runnable {
            pendingCall = null
            Overlay.hide(context)
            try { action() } catch (e: Exception) { toast(context, e.message ?: "Could not call") }
        }
        pendingCall = go
        main.post {
            if (!Overlay.show(context, "$what in 3 seconds", "Cancel") { cancel(context) }) {
                toast(context, "$what in 3 seconds")
            }
        }
        main.postDelayed(go, 3000)
    }

    fun cancel(context: Context) {
        pendingCall?.let { main.removeCallbacks(it) }
        pendingCall = null
        Overlay.hide(context)
        toast(context, "Cancelled")
    }

    /** Commands done by voice, for the chat in the app to show next time it opens. */
    @Synchronized
    fun log(context: Context, said: String, did: String) {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val list = org.json.JSONArray(p.getString("log", "[]"))
        list.put(JSONObject().put("said", said).put("did", did).put("ts", System.currentTimeMillis()))
        p.edit().putString("log", list.toString()).apply()
    }

    @Synchronized
    fun takeLog(context: Context): String {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val s = p.getString("log", "[]") ?: "[]"
        p.edit().remove("log").apply()
        return s
    }

    fun toast(context: Context, text: String) = main.post { Toast.makeText(context.applicationContext, text, Toast.LENGTH_SHORT).show() }
}

/** A small card at the top of the screen (needs "Display over other apps"). Also what lets Jarvis open apps
 *  from the background on newer Android versions. */
object Overlay {
    private var view: View? = null

    fun allowed(context: Context) = Settings.canDrawOverlays(context)

    fun show(context: Context, text: String, button: String? = null, onButton: (() -> Unit)? = null): Boolean {
        if (!allowed(context)) return false
        hide(context)
        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val dp = context.resources.displayMetrics.density
        val box = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding((20 * dp).toInt(), (12 * dp).toInt(), (12 * dp).toInt(), (12 * dp).toInt())
            background = GradientDrawable().apply {
                cornerRadius = 28 * dp
                setColor(0xEE1E2A33.toInt())
            }
        }
        box.addView(TextView(context).apply {
            this.text = text
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 16f
        })
        if (button != null) {
            box.addView(Button(context).apply {
                this.text = button
                setOnClickListener { onButton?.invoke() }
            })
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE, PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = (48 * dp).toInt()
        }
        return try {
            wm.addView(box, params)
            view = box
            true
        } catch (e: Exception) {
            false
        }
    }

    fun hide(context: Context) {
        val v = view ?: return
        view = null
        try {
            (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(v)
        } catch (_: Exception) {
        }
    }
}

/**
 * Listens for "Hey Jarvis" (openWakeWord, on the phone, nothing recorded or sent), then hears one sentence
 * with the phone's speech recognizer: a command runs, anything else goes to Jarvis as a note and the answer
 * comes back as a notification. Runs as a foreground service with a notification while it listens.
 */
class WakeService : Service() {
    private var detector: WakeWord? = null
    @Volatile private var listening = false
    private var thread: Thread? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            // The listening card has the mic; wait, then go back to listening for the wake word.
            ACTION_PAUSE -> {
                stopListening()
                return START_STICKY
            }
            ACTION_RESUME -> {
                detector?.reset()
                listen()
                return START_STICKY
            }
        }
        startForegroundNotice()
        if (detector == null) startWake()
        return START_STICKY
    }

    private fun startForegroundNotice() {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "Hey Jarvis", NotificationManager.IMPORTANCE_MIN))
        val stop = PendingIntent.getService(
            this, 3, Intent(this, WakeService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE
        )
        val open = PendingIntent.getActivity(this, 4, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val n = Notification.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("Say \"Hey Jarvis\"")
            .setContentText("Listening for the wake word on this phone only")
            .setContentIntent(open)
            .addAction(Notification.Action.Builder(null, "Stop", stop).build())
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 30) {
            startForeground(ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(ID, n)
        }
    }

    private fun startWake() {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            Commands.toast(this, "Allow the microphone in Jarvis first")
            stopSelf()
            return
        }
        try {
            detector = WakeWord(this)
        } catch (e: Exception) {
            Commands.toast(this, "Wake word could not start: ${e.message}")
            stopSelf()
            return
        }
        listen()
    }

    /** Reads the mic in 80 ms chunks on its own thread until the wake word scores above the threshold. */
    private fun listen() {
        if (listening) return
        listening = true
        val threshold = getSharedPreferences("jarcis_cmds", Context.MODE_PRIVATE).getFloat("wake_threshold", 0.5f)
        thread = Thread {
            val chunk = ShortArray(WakeWord.CHUNK)
            var rec: AudioRecord? = null
            var failed = false
            try {
                val min = AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
                rec = AudioRecord(
                    MediaRecorder.AudioSource.VOICE_RECOGNITION, 16000, AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT, maxOf(min, WakeWord.CHUNK * 4)
                )
                rec.startRecording()
                while (listening) {
                    var n = 0
                    while (n < chunk.size && listening) {
                        val r = rec.read(chunk, n, chunk.size - n)
                        if (r <= 0) throw IllegalStateException("the microphone stopped")
                        n += r
                    }
                    if (!listening) break
                    if ((detector?.score(chunk) ?: 0f) >= threshold) {
                        listening = false
                        main.post { heard() }
                    }
                }
            } catch (e: Exception) {
                failed = listening
                listening = false
                if (failed) main.post {
                    Commands.toast(this, "Wake word stopped: ${e.message}")
                    stopSelf()
                }
            } finally {
                try { rec?.stop() } catch (_: Exception) {}
                rec?.release()
            }
        }.apply { start() }
    }

    private fun stopListening() {
        listening = false
        try { thread?.join(1000) } catch (_: InterruptedException) {}
        thread = null
    }

    /** "Hey Jarvis" was heard: let go of the mic and open the listening card, which hears one sentence. */
    private fun heard() {
        stopListening()
        ListenActivity.open(this)
    }

    override fun onDestroy() {
        stopListening()
        detector?.close()
        detector = null
        Overlay.hide(this)
        super.onDestroy()
    }

    companion object {
        const val CHANNEL = "wake"
        const val ID = 2_100_000_001
        const val ACTION_STOP = "com.towkirhs.jarcis.WAKE_STOP"
        const val ACTION_PAUSE = "com.towkirhs.jarcis.WAKE_PAUSE"
        const val ACTION_RESUME = "com.towkirhs.jarcis.WAKE_RESUME"
        var running = false
            private set

        fun start(context: Context) {
            running = true
            context.startForegroundService(Intent(context, WakeService::class.java))
        }

        fun stop(context: Context) {
            running = false
            context.stopService(Intent(context, WakeService::class.java))
        }

        fun pause(context: Context) {
            if (running) context.startService(Intent(context, WakeService::class.java).setAction(ACTION_PAUSE))
        }

        fun resume(context: Context) {
            if (running) context.startService(Intent(context, WakeService::class.java).setAction(ACTION_RESUME))
        }
    }
}
