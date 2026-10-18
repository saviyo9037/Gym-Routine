package com.reptrack.app.reptrack

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** Everything the native side needs to (re)schedule a routine alarm without Flutter running. */
data class AlarmDef(
    val routineId: Int,
    val title: String,
    val category: String,
    val time: String,            // "HH:mm" local
    val repeatDays: List<Int>,   // ISO weekdays, 1=Mon..7=Sun
    val alarmEnabled: Boolean,   // fire the main alarm/notification at [time]
    val audible: Boolean,
    val vibration: Boolean,
    val soundName: String,
    val leadMinutes: Int,        // minutes before start for the heads-up reminder (0 = at start)
    val reminderEnabled: Boolean // post a silent heads-up notification at start - leadMinutes
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("routineId", routineId)
        put("title", title)
        put("category", category)
        put("time", time)
        put("repeatDays", JSONArray(repeatDays))
        put("alarmEnabled", alarmEnabled)
        put("audible", audible)
        put("vibration", vibration)
        put("soundName", soundName)
        put("leadMinutes", leadMinutes)
        put("reminderEnabled", reminderEnabled)
    }

    companion object {
        fun fromJson(o: JSONObject): AlarmDef {
            val days = ArrayList<Int>()
            val arr = o.optJSONArray("repeatDays") ?: JSONArray()
            for (i in 0 until arr.length()) days.add(arr.optInt(i))
            return AlarmDef(
                routineId = o.optInt("routineId"),
                title = o.optString("title", "Routine"),
                category = o.optString("category", "Routine"),
                time = o.optString("time", "00:00"),
                repeatDays = days,
                alarmEnabled = o.optBoolean("alarmEnabled", true),
                audible = o.optBoolean("audible", false),
                vibration = o.optBoolean("vibration", true),
                soundName = o.optString("soundName", ""),
                leadMinutes = o.optInt("leadMinutes", 0),
                reminderEnabled = o.optBoolean("reminderEnabled", false)
            )
        }
    }
}

/** SharedPreferences-backed list of scheduled routine alarms. */
object AlarmStore {
    private const val PREFS = "reptrack_alarm_defs"
    private const val KEY = "defs"

    @Synchronized
    fun all(context: Context): List<AlarmDef> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
            ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { AlarmDef.fromJson(arr.getJSONObject(it)) }
        } catch (e: Exception) {
            emptyList()
        }
    }

    @Synchronized
    fun get(context: Context, routineId: Int): AlarmDef? = all(context).firstOrNull { it.routineId == routineId }

    @Synchronized
    fun put(context: Context, def: AlarmDef) {
        val next = all(context).filter { it.routineId != def.routineId } + def
        save(context, next)
    }

    @Synchronized
    fun remove(context: Context, routineId: Int) {
        save(context, all(context).filter { it.routineId != routineId })
    }

    private fun save(context: Context, defs: List<AlarmDef>) {
        val arr = JSONArray()
        defs.forEach { arr.put(it.toJson()) }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, arr.toString()).apply()
    }
}
