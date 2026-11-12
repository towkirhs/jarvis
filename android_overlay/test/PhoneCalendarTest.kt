package com.towkirhs.jarcis

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PhoneCalendarTest {
    @Test fun repeatsBecomeRules() {
        assertEquals("FREQ=WEEKLY", PhoneCalendar.rrule("weekly"))
        assertEquals("FREQ=DAILY", PhoneCalendar.rrule("daily"))
        assertNull(PhoneCalendar.rrule(null))
        assertNull(PhoneCalendar.rrule("fortnightly"))
    }

    @Test fun durationsAreWrittenForAndroid() {
        assertEquals("P3600S", PhoneCalendar.duration(3_600_000L, false))
        assertEquals("P1D", PhoneCalendar.duration(86_400_000L, true))
        assertEquals("P3D", PhoneCalendar.duration(3 * 86_400_000L, true))
        assertEquals("P60S", PhoneCalendar.duration(1_000L, false)) // never under a minute
    }

    @Test fun durationsAreRead() {
        assertEquals(3_600_000L, PhoneCalendar.durationMillis("P3600S"))
        assertEquals(5_400_000L, PhoneCalendar.durationMillis("PT1H30M"))
        assertEquals(2 * 86_400_000L, PhoneCalendar.durationMillis("P2D"))
        assertEquals(7 * 86_400_000L, PhoneCalendar.durationMillis("P1W"))
        assertEquals(0L, PhoneCalendar.durationMillis(null))
        assertEquals(0L, PhoneCalendar.durationMillis("soon"))
    }

    @Test fun skippedDatesAreWrittenInUtc() {
        assertNull(PhoneCalendar.exdates(emptyList()))
        // 2026-11-20 09:00:00 UTC
        assertEquals("20261120T090000Z", PhoneCalendar.exdates(listOf(1_795_165_200_000L)))
    }
}
