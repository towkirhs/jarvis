package com.towkirhs.jarcis

import android.Manifest
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.CalendarContract
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** Reads and writes the phone's calendars: the ones Google Calendar and any other account on the phone fill. */
object PhoneCalendar {
    fun allowed(context: Context) =
        context.checkSelfPermission(Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED &&
            context.checkSelfPermission(Manifest.permission.WRITE_CALENDAR) == PackageManager.PERMISSION_GRANTED

    /** The repeat rule for one of Jarvis' repeats, or null for no repeat. */
    fun rrule(repeat: String?): String? = when (repeat) {
        "daily" -> "FREQ=DAILY"
        "weekly" -> "FREQ=WEEKLY"
        "monthly" -> "FREQ=MONTHLY"
        "yearly" -> "FREQ=YEARLY"
        else -> null
    }

    /** A length in the form Android keeps for repeating events: whole days for all-day, seconds otherwise. */
    fun duration(ms: Long, allDay: Boolean): String =
        if (allDay) "P${maxOf(1L, ms / 86_400_000L)}D" else "P${maxOf(60L, ms / 1000L)}S"

    /** The length in milliseconds of an RFC 5545 duration such as P3600S, PT1H30M or P2D; 0 if it cannot be read. */
    fun durationMillis(text: String?): Long {
        val m = Regex("^P(?:(\\d+)W)?(?:(\\d+)D)?(?:T(?:(\\d+)H)?(?:(\\d+)M)?)?(?:(\\d+)S)?$").find(text ?: "") ?: return 0
        fun n(i: Int) = m.groupValues[i].toLongOrNull() ?: 0L
        return ((n(1) * 7 + n(2)) * 86_400L + n(3) * 3_600L + n(4) * 60L + n(5)) * 1000L
    }

    /** Dates to leave out of a repeat, in the form Android keeps them (UTC, comma separated). */
    fun exdates(millis: List<Long>): String? {
        if (millis.isEmpty()) return null
        val f = SimpleDateFormat("yyyyMMdd'T'HHmmss'Z'", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }
        return millis.joinToString(",") { f.format(Date(it)) }
    }

    fun calendars(context: Context): String {
        val out = JSONArray()
        val cols = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
            CalendarContract.Calendars.ACCOUNT_NAME,
            CalendarContract.Calendars.CALENDAR_COLOR,
            CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL,
        )
        context.contentResolver.query(CalendarContract.Calendars.CONTENT_URI, cols, null, null, null)?.use { c ->
            while (c.moveToNext()) {
                out.put(
                    JSONObject()
                        .put("id", c.getLong(0))
                        .put("name", c.getString(1) ?: "")
                        .put("account", c.getString(2) ?: "")
                        .put("color", c.getInt(3))
                        .put("writable", c.getInt(4) >= CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR)
                )
            }
        }
        return out.toString()
    }

    /** Every occurrence between [from] and [to] in the calendars [ids], repeats already expanded by Android. */
    fun instances(context: Context, from: Long, to: Long, ids: List<Long>): String {
        val out = JSONArray()
        if (ids.isEmpty()) return out.toString()
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().also {
            ContentUris.appendId(it, from)
            ContentUris.appendId(it, to)
        }.build()
        val cols = arrayOf(
            CalendarContract.Instances.EVENT_ID,
            CalendarContract.Instances.CALENDAR_ID,
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.ALL_DAY,
            CalendarContract.Instances.EVENT_LOCATION,
            CalendarContract.Instances.DESCRIPTION,
            CalendarContract.Instances.CALENDAR_COLOR,
        )
        val where = "${CalendarContract.Instances.CALENDAR_ID} IN (${ids.joinToString(",")}) AND " +
            "(${CalendarContract.Instances.STATUS} IS NULL OR ${CalendarContract.Instances.STATUS} != ${CalendarContract.Events.STATUS_CANCELED})"
        context.contentResolver.query(uri, cols, where, null, "${CalendarContract.Instances.BEGIN} ASC")?.use { c ->
            while (c.moveToNext() && out.length() < 4000) {
                out.put(
                    JSONObject()
                        .put("ev", c.getLong(0))
                        .put("cal", c.getLong(1))
                        .put("title", c.getString(2) ?: "")
                        .put("start", c.getLong(3))
                        .put("end", c.getLong(4))
                        .put("allDay", c.getInt(5) == 1)
                        .put("location", c.getString(6) ?: JSONObject.NULL)
                        .put("desc", c.getString(7) ?: JSONObject.NULL)
                        .put("color", c.getInt(8))
                )
            }
        }
        return out.toString()
    }

    private fun values(j: JSONObject): ContentValues {
        val v = ContentValues()
        val allDay = j.optBoolean("allDay")
        val start = j.getLong("start")
        val end = j.getLong("end")
        v.put(CalendarContract.Events.TITLE, j.optString("title"))
        v.put(CalendarContract.Events.EVENT_LOCATION, if (j.isNull("location")) null else j.getString("location"))
        v.put(CalendarContract.Events.DESCRIPTION, if (j.isNull("desc")) null else j.getString("desc"))
        v.put(CalendarContract.Events.ALL_DAY, if (allDay) 1 else 0)
        v.put(CalendarContract.Events.EVENT_TIMEZONE, if (allDay) "UTC" else TimeZone.getDefault().id)
        v.put(CalendarContract.Events.DTSTART, start)
        val rule = rrule(if (j.isNull("repeat")) null else j.getString("repeat"))
        if (rule == null) {
            v.put(CalendarContract.Events.DTEND, end)
            v.putNull(CalendarContract.Events.DURATION)
            v.putNull(CalendarContract.Events.RRULE)
            v.putNull(CalendarContract.Events.EXDATE)
        } else {
            v.put(CalendarContract.Events.RRULE, rule)
            v.put(CalendarContract.Events.DURATION, duration(end - start, allDay))
            v.putNull(CalendarContract.Events.DTEND)
            val skip = j.optJSONArray("skip")
            val list = (0 until (skip?.length() ?: 0)).map { skip!!.getLong(it) }
            if (allDay || list.isEmpty()) v.putNull(CalendarContract.Events.EXDATE)
            else v.put(CalendarContract.Events.EXDATE, exdates(list))
        }
        return v
    }

    /** Adds an event to the calendar [cal]; returns its id, or -1. */
    fun insert(context: Context, cal: Long, json: String): Long {
        val v = values(JSONObject(json))
        v.put(CalendarContract.Events.CALENDAR_ID, cal)
        val uri = context.contentResolver.insert(CalendarContract.Events.CONTENT_URI, v) ?: return -1
        return ContentUris.parseId(uri)
    }

    fun update(context: Context, ev: Long, json: String): Boolean =
        context.contentResolver.update(
            ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, ev), values(JSONObject(json)), null, null
        ) > 0

    fun delete(context: Context, ev: Long): Boolean =
        context.contentResolver.delete(ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, ev), null, null) > 0

    /** One event as it is now, or null if it is gone. */
    fun event(context: Context, ev: Long): String? {
        val cols = arrayOf(
            CalendarContract.Events.TITLE,
            CalendarContract.Events.DTSTART,
            CalendarContract.Events.DTEND,
            CalendarContract.Events.DURATION,
            CalendarContract.Events.ALL_DAY,
            CalendarContract.Events.EVENT_LOCATION,
            CalendarContract.Events.DESCRIPTION,
            CalendarContract.Events.DELETED,
        )
        context.contentResolver.query(
            ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, ev), cols, null, null, null
        )?.use { c ->
            if (!c.moveToFirst() || c.getInt(7) == 1) return null
            val start = c.getLong(1)
            val end = if (c.isNull(2)) start + durationMillis(c.getString(3)) else c.getLong(2)
            return JSONObject()
                .put("ev", ev)
                .put("title", c.getString(0) ?: "")
                .put("start", start)
                .put("end", end)
                .put("allDay", c.getInt(4) == 1)
                .put("location", c.getString(5) ?: JSONObject.NULL)
                .put("desc", c.getString(6) ?: JSONObject.NULL)
                .toString()
        }
        return null
    }

    /** Opens an event in the phone's Calendar app. */
    fun open(context: Context, ev: Long) {
        try {
            context.startActivity(
                Intent(Intent.ACTION_VIEW, ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, ev))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        } catch (_: Exception) {
            // No calendar app.
        }
    }
}
