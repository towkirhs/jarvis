package com.towkirhs.jarcis

import android.Manifest
import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * Place triggers: tasks and alarms that go off when you arrive at or leave a place. The list comes from the app
 * ([set]) and is kept here so it can be put back after a reboot. Each entry:
 * {key, kind: "task" or "alarm", id, label, place, lat, lng, radius, when: "arrive" or "leave", sound, once}.
 */
object Geo {
    private const val PREFS = "jarcis_geo"

    fun all(context: Context): JSONArray =
        JSONArray(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("fences", "[]") ?: "[]")

    private fun save(context: Context, list: JSONArray) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("fences", list.toString()).commit()
    }

    fun set(context: Context, json: String) {
        save(context, JSONArray(json))
        register(context)
    }

    private fun has(context: Context, p: String) = context.checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED

    fun access(context: Context) = mapOf(
        "fine" to has(context, Manifest.permission.ACCESS_FINE_LOCATION),
        "background" to has(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION),
    )

    private fun pending(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context, 7700, Intent(context, GeofenceReceiver::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
    )

    /** Hands the current list to Android's geofencing (replacing what was there). */
    @SuppressLint("MissingPermission")
    fun register(context: Context) {
        val client = LocationServices.getGeofencingClient(context)
        client.removeGeofences(pending(context)).addOnCompleteListener {
            val list = all(context)
            if (list.length() == 0) return@addOnCompleteListener
            if (!has(context, Manifest.permission.ACCESS_FINE_LOCATION) ||
                !has(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION)
            ) {
                AlarmLog.add(context, "G|no location permission")
                return@addOnCompleteListener
            }
            val fences = (0 until list.length()).map { i ->
                val e = list.getJSONObject(i)
                Geofence.Builder()
                    .setRequestId(e.getString("key"))
                    .setCircularRegion(e.getDouble("lat"), e.getDouble("lng"), e.getDouble("radius").toFloat().coerceAtLeast(100f))
                    .setExpirationDuration(Geofence.NEVER_EXPIRE)
                    .setTransitionTypes(
                        if (e.optString("when") == "leave") Geofence.GEOFENCE_TRANSITION_EXIT else Geofence.GEOFENCE_TRANSITION_ENTER
                    )
                    .build()
            }
            // Initial trigger 0: setting "when I arrive home" while at home does not go off straight away.
            val request = GeofencingRequest.Builder().setInitialTrigger(0).addGeofences(fences).build()
            try {
                client.addGeofences(request, pending(context))
                    .addOnSuccessListener { AlarmLog.add(context, "G|${fences.size} places watched") }
                    .addOnFailureListener { e -> AlarmLog.add(context, "G|failed|${e.message}") }
            } catch (e: SecurityException) {
                AlarmLog.add(context, "G|failed|${e.message}")
            }
        }
    }

    /** Where the phone is now, for "use where I am". Answers null if it cannot tell. */
    @SuppressLint("MissingPermission")
    fun here(context: Context, result: MethodChannel.Result) {
        if (!has(context, Manifest.permission.ACCESS_FINE_LOCATION)) {
            result.success(null)
            return
        }
        LocationServices.getFusedLocationProviderClient(context)
            .getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, null)
            .addOnSuccessListener { l -> result.success(l?.let { mapOf("lat" to it.latitude, "lng" to it.longitude) }) }
            .addOnFailureListener { result.success(null) }
    }

    /** A place trigger went off. One-time ones are removed and reported to the app ([GeoQueue]). */
    fun fired(context: Context, keys: List<String>, entering: Boolean) {
        val list = all(context)
        val keep = JSONArray()
        var removed = false
        for (i in 0 until list.length()) {
            val e = list.getJSONObject(i)
            if (e.getString("key") !in keys || (e.optString("when") == "leave") == entering) {
                keep.put(e)
                continue
            }
            go(context, e)
            if (e.optBoolean("once")) {
                GeoQueue.add(context, e.getString("key"))
                removed = true
            } else {
                keep.put(e)
            }
        }
        if (removed) {
            save(context, keep)
            register(context)
            MainActivity.live?.invokeMethod("doneWaiting", null)
        }
    }

    private fun go(context: Context, e: JSONObject) {
        val place = e.optString("place", "the place")
        val where = if (e.optString("when") == "leave") "Leaving $place" else "At $place"
        val label = e.optString("label")
        val id = e.getInt("id")
        AlarmLog.add(context, "G|fired|${e.getString("key")}")
        if (e.optString("kind") == "alarm") {
            RingService.start(context, id, "$label · $where", e.optString("sound", "").ifEmpty { null })
            return
        }
        val nm = context.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel("place", "Place reminders", NotificationManager.IMPORTANCE_HIGH))
        val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val done = PendingIntent.getBroadcast(
            context, id * 2,
            Intent(context, ActionReceiver::class.java).setAction(ActionReceiver.ACTION_DONE)
                .putExtra("id", id).putExtra("kind", "notice").putExtra("label", label),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        nm.notify(
            id,
            Notification.Builder(context, "place")
                .setSmallIcon(android.R.drawable.ic_dialog_map)
                .setContentTitle(where)
                .setContentText(label)
                .setStyle(Notification.BigTextStyle().bigText(label))
                .setCategory(Notification.CATEGORY_REMINDER)
                .setContentIntent(open)
                .setAutoCancel(true)
                .addAction(Notification.Action.Builder(null, "Done", done).build())
                .build()
        )
    }
}

class GeofenceReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val event = GeofencingEvent.fromIntent(intent) ?: return
        if (event.hasError()) {
            AlarmLog.add(context, "G|error|${event.errorCode}")
            return
        }
        val keys = event.triggeringGeofences?.map { it.requestId } ?: return
        val t = event.geofenceTransition
        if (t != Geofence.GEOFENCE_TRANSITION_ENTER && t != Geofence.GEOFENCE_TRANSITION_EXIT) return
        Geo.fired(context, keys, t == Geofence.GEOFENCE_TRANSITION_ENTER)
    }
}

/** One-time place alarms that went off, waiting for the app to switch them off. */
object GeoQueue {
    private const val FILE = "jarcis_geo_fired"

    @Synchronized
    fun add(context: Context, key: String) {
        val p = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        p.edit().putString("q", JSONArray(p.getString("q", "[]")).put(key).toString()).apply()
    }

    @Synchronized
    fun take(context: Context): String {
        val p = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        val q = p.getString("q", "[]") ?: "[]"
        p.edit().putString("q", "[]").apply()
        return q
    }
}
