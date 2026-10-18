package com.reptrack.app.reptrack

import java.util.Calendar
import java.util.TimeZone

/**
 * Pure next-trigger calculation (no Android APIs) so it can be unit tested on the JVM.
 *
 * Alarms are stored as local wall-clock times ("07:15" on given ISO weekdays, 1=Mon..7=Sun).
 * Calendar field arithmetic is used instead of adding 24h, so DST changes never shift the
 * wall-clock time, and passing a new [tz] after a timezone change recomputes correctly.
 */
object NextOccurrence {

    /** ISO weekday (1=Mon..7=Sun) of [cal]. */
    fun isoWeekday(cal: Calendar): Int = (cal.get(Calendar.DAY_OF_WEEK) + 5) % 7 + 1

    /**
     * Next trigger strictly after [nowMs] for the wall-clock time [hour]:[minute] on one of
     * [repeatDays] (ISO weekdays), moved earlier by [leadMinutes]. Returns null when
     * [repeatDays] is empty.
     */
    fun compute(
        nowMs: Long,
        hour: Int,
        minute: Int,
        repeatDays: Set<Int>,
        tz: TimeZone = TimeZone.getDefault(),
        leadMinutes: Int = 0
    ): Long? {
        if (repeatDays.isEmpty()) return null
        // Look 8 days ahead: covers "same weekday next week" when today's time has passed
        // and lead time can push today's candidate into the past.
        for (offset in 0..8) {
            val cal = Calendar.getInstance(tz)
            cal.timeInMillis = nowMs
            cal.add(Calendar.DAY_OF_YEAR, offset)
            cal.set(Calendar.HOUR_OF_DAY, hour)
            cal.set(Calendar.MINUTE, minute)
            cal.set(Calendar.SECOND, 0)
            cal.set(Calendar.MILLISECOND, 0)
            if (isoWeekday(cal) !in repeatDays) continue
            val candidate = cal.timeInMillis - leadMinutes * 60_000L
            if (candidate > nowMs) return candidate
        }
        return null
    }

    fun parseTime(time: String): Pair<Int, Int> {
        val parts = time.trim().split(":")
        val h = parts.getOrNull(0)?.toIntOrNull() ?: 0
        val m = parts.getOrNull(1)?.toIntOrNull() ?: 0
        return Pair(h.coerceIn(0, 23), m.coerceIn(0, 59))
    }
}
