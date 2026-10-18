package com.reptrack.app.reptrack

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Schedules/cancels routine alarms from the persisted [AlarmStore]. Works without Flutter, so
 * it can run from [AlarmReceiver] (chain the next occurrence) and [BootReceiver] (restore after
 * reboot, app update, clock or timezone change).
 *
 * PendingIntent request codes (kept disjoint from the other codes used in the app):
 *   main alarm   = routineId            (unchanged, so alarms scheduled by older builds still cancel)
 *   snooze       = routineId + 60000
 *   reminder     = routineId + 70000
 */
object AlarmScheduler {
    const val SNOOZE_OFFSET = 60000
    const val REMINDER_OFFSET = 70000

    private fun alarmManager(context: Context) =
        context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    private fun flags() = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

    private fun mainPending(context: Context, def: AlarmDef): PendingIntent {
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            action = AlarmReceiver.ACTION_TRIGGER_ALARM
            putExtra(AlarmReceiver.EXTRA_ROUTINE_ID, def.routineId)
            putExtra(AlarmReceiver.EXTRA_TITLE, def.title)
            putExtra(AlarmReceiver.EXTRA_CATEGORY, def.category)
            putExtra(AlarmReceiver.EXTRA_TIME, def.time)
            putExtra(AlarmReceiver.EXTRA_IS_AUDIBLE, def.audible)
            putExtra(AlarmReceiver.EXTRA_VIBRATION, def.vibration)
        }
        return PendingIntent.getBroadcast(context, def.routineId, intent, flags())
    }

    private fun reminderPending(context: Context, def: AlarmDef): PendingIntent {
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            action = AlarmReceiver.ACTION_REMINDER
            putExtra(AlarmReceiver.EXTRA_ROUTINE_ID, def.routineId)
            putExtra(AlarmReceiver.EXTRA_TITLE, def.title)
            putExtra(AlarmReceiver.EXTRA_CATEGORY, def.category)
            putExtra(AlarmReceiver.EXTRA_TIME, def.time)
            putExtra(AlarmReceiver.EXTRA_LEAD_MINUTES, def.leadMinutes)
        }
        return PendingIntent.getBroadcast(context, def.routineId + REMINDER_OFFSET, intent, flags())
    }

    /** Next start-time trigger for [def] after [nowMs], or null (disabled / no repeat days). */
    fun nextMainTrigger(def: AlarmDef, nowMs: Long = System.currentTimeMillis()): Long? {
        if (!def.alarmEnabled) return null
        val (h, m) = NextOccurrence.parseTime(def.time)
        return NextOccurrence.compute(nowMs, h, m, def.repeatDays.toSet())
    }

    fun nextReminderTrigger(def: AlarmDef, nowMs: Long = System.currentTimeMillis()): Long? {
        if (!def.reminderEnabled) return null
        val (h, m) = NextOccurrence.parseTime(def.time)
        return NextOccurrence.compute(nowMs, h, m, def.repeatDays.toSet(), leadMinutes = def.leadMinutes.coerceAtLeast(0))
    }

    /** (Re)schedules main alarm and reminder for [def]; cancels whichever no longer applies. */
    fun schedule(context: Context, def: AlarmDef, nowMs: Long = System.currentTimeMillis()) {
        val am = alarmManager(context)

        val mainAt = nextMainTrigger(def, nowMs)
        val mainPi = mainPending(context, def)
        if (mainAt != null) {
            val showIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("alarm_routine_id", def.routineId)
                putExtra("alarm_title", def.title)
            }
            val pendingShow = PendingIntent.getActivity(context, def.routineId + 40000, showIntent, flags())
            // setAlarmClock keeps firing in Doze and does not need the exact-alarm permission.
            am.setAlarmClock(AlarmManager.AlarmClockInfo(mainAt, pendingShow), mainPi)
        } else {
            am.cancel(mainPi)
        }

        val remAt = nextReminderTrigger(def, nowMs)
        val remPi = reminderPending(context, def)
        if (remAt != null) {
            scheduleReminderAt(am, remAt, remPi)
        } else {
            am.cancel(remPi)
        }
    }

    private fun scheduleReminderAt(am: AlarmManager, at: Long, pi: PendingIntent) {
        try {
            val canExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()
            if (canExact) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            } else {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            }
        } catch (e: SecurityException) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        }
    }

    fun cancel(context: Context, routineId: Int) {
        val am = alarmManager(context)
        val stub = AlarmDef(routineId, "", "", "00:00", emptyList(), false, false, false, "", 0, false)
        am.cancel(mainPending(context, stub))
        am.cancel(reminderPending(context, stub))
        val snooze = Intent(context, AlarmReceiver::class.java).apply {
            action = AlarmReceiver.ACTION_TRIGGER_ALARM
        }
        am.cancel(PendingIntent.getBroadcast(context, routineId + SNOOZE_OFFSET, snooze, flags()))
    }

    /** Restores every stored alarm (boot, app update, clock/timezone change, Flutter start). */
    fun scheduleAll(context: Context) {
        for (def in AlarmStore.all(context)) {
            try {
                schedule(context, def)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    /** Called when a main alarm or reminder fired: chain the next occurrence. */
    fun onFired(context: Context, routineId: Int) {
        val def = AlarmStore.get(context, routineId) ?: return
        try {
            // +60s guard: an alarm delivered a few ms early must not re-arm the same minute.
            schedule(context, def, System.currentTimeMillis() + 60_000L)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
