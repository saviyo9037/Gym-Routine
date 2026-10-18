package com.reptrack.app.reptrack

import java.util.Calendar
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NextOccurrenceTest {
    private fun ms(tz: TimeZone, y: Int, mo: Int, d: Int, h: Int, mi: Int): Long {
        val c = Calendar.getInstance(tz)
        c.clear()
        c.set(y, mo - 1, d, h, mi, 0)
        return c.timeInMillis
    }

    private val utc = TimeZone.getTimeZone("UTC")
    private val all = setOf(1, 2, 3, 4, 5, 6, 7)

    @Test fun laterToday() {
        // 2026-10-20 is a Tuesday
        val now = ms(utc, 2026, 10, 20, 6, 0)
        assertEquals(ms(utc, 2026, 10, 20, 7, 0), NextOccurrence.compute(now, 7, 0, all, utc))
    }

    @Test fun passedTodayGoesToTomorrow_andIsStrictlyAfterNow() {
        val now = ms(utc, 2026, 10, 20, 7, 0)
        assertEquals(ms(utc, 2026, 10, 21, 7, 0), NextOccurrence.compute(now, 7, 0, all, utc))
    }

    @Test fun onlyMondaysFromTuesday() {
        val now = ms(utc, 2026, 10, 20, 6, 0)
        assertEquals(ms(utc, 2026, 10, 26, 7, 0), NextOccurrence.compute(now, 7, 0, setOf(1), utc))
    }

    @Test fun sameWeekdayPassedGoesNextWeek() {
        val now = ms(utc, 2026, 10, 20, 9, 0)
        assertEquals(ms(utc, 2026, 10, 27, 7, 0), NextOccurrence.compute(now, 7, 0, setOf(2), utc))
    }

    @Test fun emptyDaysIsNull() {
        assertNull(NextOccurrence.compute(ms(utc, 2026, 10, 20, 6, 0), 7, 0, emptySet(), utc))
    }

    @Test fun leadCanCrossMidnight() {
        val now = ms(utc, 2026, 10, 20, 23, 0)
        // Wednesday 00:05 minus 10 minutes = Tuesday 23:55
        assertEquals(
            ms(utc, 2026, 10, 20, 23, 55),
            NextOccurrence.compute(now, 0, 5, setOf(3), utc, leadMinutes = 10)
        )
    }

    @Test fun wallClockStableAcrossDst() {
        // Europe/Berlin DST starts 2026-03-29, ends 2026-10-25; New York 2026-03-08 / 2026-11-01.
        val cases = listOf(
            Triple("Europe/Berlin", ms(TimeZone.getTimeZone("Europe/Berlin"), 2026, 3, 28, 23, 0), 7),
            Triple("Europe/Berlin", ms(TimeZone.getTimeZone("Europe/Berlin"), 2026, 10, 24, 23, 0), 7),
            Triple("America/New_York", ms(TimeZone.getTimeZone("America/New_York"), 2026, 3, 7, 23, 0), 7),
            Triple("America/New_York", ms(TimeZone.getTimeZone("America/New_York"), 2026, 10, 31, 23, 0), 7)
        )
        for ((zone, now, hour) in cases) {
            val tz = TimeZone.getTimeZone(zone)
            val next = NextOccurrence.compute(now, hour, 0, all, tz)!!
            val c = Calendar.getInstance(tz)
            c.timeInMillis = next
            assertEquals("$zone wall clock hour", hour, c.get(Calendar.HOUR_OF_DAY))
            assertEquals(0, c.get(Calendar.MINUTE))
        }
    }

    @Test fun timezoneChangeRecomputesInTheNewZone() {
        val now = ms(utc, 2026, 10, 20, 6, 0)
        val kolkata = TimeZone.getTimeZone("Asia/Kolkata")
        val a = NextOccurrence.compute(now, 7, 0, all, utc)!!
        val b = NextOccurrence.compute(now, 7, 0, all, kolkata)!!
        assertEquals(ms(kolkata, 2026, 10, 21, 7, 0), b) // 06:00 UTC is already 11:30 in Kolkata
        assertEquals(true, a != b)
    }

    @Test fun parseTimeIsDefensive() {
        assertEquals(Pair(7, 5), NextOccurrence.parseTime("07:05"))
        assertEquals(Pair(0, 0), NextOccurrence.parseTime("garbage"))
        assertEquals(Pair(23, 59), NextOccurrence.parseTime("99:99"))
    }
}
