package com.towkirhs.jarcis

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar

class CommandsTest {
    private fun p(text: String, phrases: JSONObject? = null) = Commands.parseText(text, phrases)
    private fun cmd(kind: String, target: String, text: String? = null) = Commands.Cmd(kind, target, text)

    @Test
    fun oldCommandsStillWork() {
        assertEquals(cmd("app", "youtube"), p("Hey Jarvis, open YouTube"))
        assertEquals(cmd("wa_chat", "oishi", "i'm on my way"), p("message Oishi on WhatsApp saying I'm on my way"))
        assertEquals(cmd("wa_call", "oishi"), p("call Oishi on WhatsApp"))
        assertEquals(cmd("call", "ammu"), p("call Ammu"))
        assertEquals(cmd("torch", "on"), p("turn on the flashlight"))
        assertEquals(cmd("youtube", "lofi"), p("play lofi on YouTube"))
        assertNull(p("call Ammu at 8 pm")) // a reminder, so a note
        assertNull(p("buy milk"))
    }

    @Test
    fun musicAndSound() {
        assertEquals(cmd("media", "pause"), p("pause"))
        assertEquals(cmd("media", "pause"), p("stop the music"))
        assertEquals(cmd("media", "play"), p("play"))
        assertEquals(cmd("media", "next"), p("next song")) // "next" is also a time word; must not become a note
        assertEquals(cmd("media", "previous"), p("previous track"))
        assertEquals(cmd("volume", "up"), p("volume up"))
        assertEquals(cmd("volume", "down"), p("turn it down"))
        assertEquals(cmd("volume", "mute"), p("mute"))
        assertEquals(cmd("volume", "40"), p("set volume to 40%"))
        assertEquals(cmd("volume", "100"), p("max volume"))
        assertEquals(cmd("play_in", Commands.SPOTIFY, "arijit singh"), p("play Arijit Singh on Spotify"))
        assertEquals(cmd("play_in", Commands.YT_MUSIC, "lofi"), p("play lofi on YouTube Music"))
    }

    @Test
    fun phoneModes() {
        assertEquals(cmd("ringer", "silent"), p("silent mode"))
        assertEquals(cmd("ringer", "vibrate"), p("put my phone on vibrate"))
        assertEquals(cmd("ringer", "normal"), p("sound on"))
        assertEquals(cmd("dnd", "on"), p("turn on do not disturb"))
        assertEquals(cmd("dnd", "off"), p("do not disturb off"))
        assertEquals(cmd("dnd", "on"), p("DND"))
    }

    @Test
    fun timersAlarmsAndQuestions() {
        assertEquals(cmd("timer", "600"), p("set a timer for 10 minutes"))
        assertEquals(cmd("timer", "300"), p("five minute timer"))
        assertEquals(cmd("timer", "3600"), p("timer for an hour"))
        assertEquals(cmd("timer", "30"), p("timer 30 seconds"))
        assertEquals(cmd("timer_cancel", ""), p("cancel the timer"))
        assertEquals(cmd("alarm", "06:30", "am"), p("wake me up at 6:30 a.m."))
        assertEquals(cmd("alarm", "07:00", null), p("set an alarm for 7"))
        assertEquals(cmd("alarm", "21:15", null), p("alarm at 21:15"))
        assertEquals(cmd("alarm", "05:00", "pm"), p("set alarm for 5 pm tomorrow"))
        assertEquals(cmd("time", ""), p("what time is it"))
        assertEquals(cmd("battery", ""), p("how much battery is left"))
        assertEquals(cmd("hush", ""), p("stop"))
        assertEquals(cmd("camera", ""), p("take a selfie"))
    }

    @Test
    fun yourOwnCommandsComeFirstAndCanStayQuiet() {
        val phrases = JSONObject().put("good night", JSONObject().put("kind", "app").put("target", "Sleep").put("speak", false))
        val c = p("Good night!", phrases)!!
        assertEquals("app", c.kind)
        assertTrue(c.quiet)
        assertFalse(p("open camera")!!.quiet)
    }

    @Test
    fun stepsOfYourOwnCommandAreBuiltInCommands() {
        // What "do" runs, step by step (own phrases are not looked up, so a phrase cannot run itself forever).
        val steps = "silent mode then set an alarm for 6:30 am; pause".split(Regex("\\s+then\\s+|\\s*;\\s*"))
        assertEquals(listOf(cmd("ringer", "silent"), cmd("alarm", "06:30", "am"), cmd("media", "pause")), steps.map { p(it) })
    }

    @Test
    fun alarmTimeIsTheNextOneToCome() {
        fun at(h: Int, m: Int) = Calendar.getInstance().apply {
            set(2026, Calendar.NOVEMBER, 8, h, m, 0)
            set(Calendar.MILLISECOND, 0)
        }
        fun hourOf(ms: Long) = Calendar.getInstance().apply { timeInMillis = ms }.let {
            "${it.get(Calendar.DAY_OF_MONTH)} ${it.get(Calendar.HOUR_OF_DAY)}:${it.get(Calendar.MINUTE)}"
        }
        // 10 pm: "6:30" without am/pm means tomorrow morning.
        assertEquals("9 6:30", hourOf(Commands.nextAlarm(6, 30, null, at(22, 0))))
        // 2 pm: "6" means this evening.
        assertEquals("8 18:0", hourOf(Commands.nextAlarm(6, 0, null, at(14, 0))))
        assertEquals("9 6:0", hourOf(Commands.nextAlarm(6, 0, "am", at(14, 0))))
        assertEquals("9 0:0", hourOf(Commands.nextAlarm(12, 0, "am", at(14, 0))))
        assertEquals("8 21:15", hourOf(Commands.nextAlarm(21, 15, null, at(14, 0))))
    }

    @Test
    fun spans() {
        assertEquals("10 minutes", Commands.span(600))
        assertEquals("1 hour 30 minutes", Commands.span(5400))
        assertEquals("45 seconds", Commands.span(45))
    }

    @Test
    fun quietHoursAndShortAnswers() {
        fun t(h: Int, m: Int) = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, h)
            set(Calendar.MINUTE, m)
        }
        assertTrue(Speaker.inQuietHours("23:00", "07:00", t(23, 30)))
        assertTrue(Speaker.inQuietHours("23:00", "07:00", t(6, 59)))
        assertFalse(Speaker.inQuietHours("23:00", "07:00", t(7, 0)))
        assertTrue(Speaker.inQuietHours("13:00", "14:00", t(13, 30)))
        assertFalse(Speaker.inQuietHours("", "", t(13, 30)))
        assertEquals("It will rain.", Speaker.shorten("It will **rain**. Take an umbrella.", true))
        assertEquals("It will rain. Take an umbrella.", Speaker.shorten("It will rain. Take an umbrella.", false))
    }
}
