package com.reptrack.app.reptrack

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.reptrack.app/alarm"
    private var triggeredAlarmData: Map<String, Any?>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Enable display on top of lock screen and screen wake-up for alarms
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }

        handleAlarmIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleAlarmIntent(intent)
    }

    private fun handleAlarmIntent(intent: Intent?) {
        if (intent == null) return
        val isRinging = intent.getBooleanExtra("alarm_is_ringing", false)
        if (isRinging) {
            triggeredAlarmData = mapOf(
                "routineId" to intent.getIntExtra("alarm_routine_id", 0),
                "title" to (intent.getStringExtra("alarm_title") ?: ""),
                "category" to (intent.getStringExtra("alarm_category") ?: ""),
                "time" to (intent.getStringExtra("alarm_time") ?: ""),
                "isRinging" to true
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            when (call.method) {
                "scheduleAlarm" -> {
                    try {
                        val routineId = call.argument<Int>("routineId") ?: 0
                        val repeatDays = (call.argument<List<Int>>("repeatDays") ?: emptyList())
                            .filter { it in 1..7 }
                        val def = AlarmDef(
                            routineId = routineId,
                            title = call.argument<String>("title") ?: "Routine",
                            category = call.argument<String>("category") ?: "Routine",
                            time = call.argument<String>("time") ?: "00:00",
                            repeatDays = repeatDays,
                            alarmEnabled = call.argument<Boolean>("alarmEnabled") ?: true,
                            audible = call.argument<Boolean>("isAudible") ?: true,
                            vibration = call.argument<Boolean>("vibration") ?: true,
                            soundName = call.argument<String>("soundName") ?: "",
                            leadMinutes = call.argument<Int>("leadMinutes") ?: 0,
                            reminderEnabled = call.argument<Boolean>("reminderEnabled") ?: false
                        )
                        if (repeatDays.isEmpty()) {
                            // Nothing to repeat on: make sure no stale alarm survives.
                            AlarmStore.remove(this, routineId)
                            AlarmScheduler.cancel(this, routineId)
                            result.success(false)
                        } else {
                            AlarmStore.put(this, def)
                            AlarmScheduler.schedule(this, def)
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("ALARM_ERROR", e.message, null)
                    }
                }

                "cancelAlarm" -> {
                    try {
                        val routineId = call.argument<Int>("routineId") ?: 0
                        AlarmStore.remove(this, routineId)
                        AlarmScheduler.cancel(this, routineId)

                        // Also ensure audio service is stopped for this routine
                        val stopIntent = Intent(this, AlarmAudioService::class.java).apply {
                            action = AlarmAudioService.ACTION_STOP
                        }
                        startService(stopIntent)

                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CANCEL_ERROR", e.message, null)
                    }
                }

                "testAlarm" -> {
                    try {
                        val title = call.argument<String>("title") ?: "Test Routine Alarm"
                        val category = call.argument<String>("category") ?: "Gym"
                        val delaySeconds = call.argument<Int>("delaySeconds") ?: 2
                        val isAudible = call.argument<Boolean>("isAudible") ?: true

                        val triggerMs = System.currentTimeMillis() + (delaySeconds * 1000L)
                        val testId = 99999

                        val intent = Intent(this, AlarmReceiver::class.java).apply {
                            action = AlarmReceiver.ACTION_TRIGGER_ALARM
                            putExtra(AlarmReceiver.EXTRA_ROUTINE_ID, testId)
                            putExtra(AlarmReceiver.EXTRA_TITLE, title)
                            putExtra(AlarmReceiver.EXTRA_CATEGORY, category)
                            putExtra(AlarmReceiver.EXTRA_TIME, "Now")
                            putExtra(AlarmReceiver.EXTRA_IS_AUDIBLE, isAudible)
                            putExtra(AlarmReceiver.EXTRA_VIBRATION, true)
                        }

                        val pendingIntent = PendingIntent.getBroadcast(
                            this,
                            testId,
                            intent,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )

                        val clockInfo = AlarmManager.AlarmClockInfo(triggerMs, pendingIntent)
                        alarmManager.setAlarmClock(clockInfo, pendingIntent)

                        result.success(true)
                    } catch (e: Exception) {
                        result.error("TEST_ALARM_ERROR", e.message, null)
                    }
                }

                "stopAlarm" -> {
                    try {
                        val stopIntent = Intent(this, AlarmAudioService::class.java).apply {
                            action = AlarmAudioService.ACTION_STOP
                        }
                        startService(stopIntent)
                        triggeredAlarmData = null
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("STOP_ERROR", e.message, null)
                    }
                }

                "snoozeAlarm" -> {
                    try {
                        val routineId = call.argument<Int>("routineId") ?: 0
                        val snoozeMinutes = call.argument<Int>("snoozeMinutes") ?: 10
                        val title = call.argument<String>("title") ?: "Snoozed Routine"

                        // 1. Stop current audio
                        val stopIntent = Intent(this, AlarmAudioService::class.java).apply {
                            action = AlarmAudioService.ACTION_STOP
                        }
                        startService(stopIntent)
                        triggeredAlarmData = null

                        // 2. Schedule new alarm for now + snoozeMinutes
                        val triggerMs = System.currentTimeMillis() + (snoozeMinutes * 60 * 1000L)
                        val intent = Intent(this, AlarmReceiver::class.java).apply {
                            action = AlarmReceiver.ACTION_TRIGGER_ALARM
                            putExtra(AlarmReceiver.EXTRA_ROUTINE_ID, routineId)
                            putExtra(AlarmReceiver.EXTRA_TITLE, "$title (Snoozed)")
                            putExtra(AlarmReceiver.EXTRA_TIME, "+${snoozeMinutes}m")
                            putExtra(AlarmReceiver.EXTRA_IS_AUDIBLE, true)
                            putExtra(AlarmReceiver.EXTRA_VIBRATION, true)
                            putExtra(AlarmReceiver.EXTRA_IS_SNOOZE, true)
                        }
                        // Own request code: replaces only an earlier snooze, never the routine's
                        // regular repeating alarm.
                        val pendingIntent = PendingIntent.getBroadcast(
                            this,
                            routineId + AlarmScheduler.SNOOZE_OFFSET,
                            intent,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )
                        val clockInfo = AlarmManager.AlarmClockInfo(triggerMs, pendingIntent)
                        alarmManager.setAlarmClock(clockInfo, pendingIntent)

                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SNOOZE_ERROR", e.message, null)
                    }
                }

                "checkPermissions" -> {
                    val canExactAlarm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        alarmManager.canScheduleExactAlarms()
                    } else {
                        true
                    }

                    val notifGranted = NotificationManagerCompat.from(this).areNotificationsEnabled()

                    val batteryIgnored = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        powerManager.isIgnoringBatteryOptimizations(packageName)
                    } else {
                        true
                    }

                    val dndGranted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        notificationManager.isNotificationPolicyAccessGranted
                    } else {
                        true
                    }

                    val canFullScreen = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        notificationManager.canUseFullScreenIntent()
                    } else {
                        true
                    }

                    result.success(mapOf(
                        "canScheduleExactAlarms" to canExactAlarm,
                        "notificationsEnabled" to notifGranted,
                        "isBatteryOptimizationIgnored" to batteryIgnored,
                        "isDndAccessGranted" to dndGranted,
                        "canUseFullScreenIntent" to canFullScreen,
                        "manufacturer" to (Build.MANUFACTURER ?: ""),
                        "sdkInt" to Build.VERSION.SDK_INT
                    ))
                }

                "requestExactAlarmPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                            data = Uri.parse("package:$packageName")
                        }
                        startActivity(intent)
                    }
                    result.success(true)
                }

                "requestBatteryOptimizationExemption" -> {
                    // Opens the system "battery optimisation" list. We deliberately do not use
                    // ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS (restricted by Play policy).
                    try {
                        startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                    } catch (e: Exception) {
                        openAppDetails()
                    }
                    result.success(true)
                }

                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            7001
                        )
                    }
                    result.success(true)
                }

                "openNotificationSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        }
                        startActivity(intent)
                    } catch (e: Exception) {
                        openAppDetails()
                    }
                    result.success(true)
                }

                "openFullScreenIntentSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                        } else {
                            openAppDetails()
                        }
                    } catch (e: Exception) {
                        openAppDetails()
                    }
                    result.success(true)
                }

                "openAppSettings" -> {
                    openAppDetails()
                    result.success(true)
                }

                "getScheduledAlarms" -> {
                    val now = System.currentTimeMillis()
                    result.success(AlarmStore.all(this).map {
                        mapOf(
                            "routineId" to it.routineId,
                            "title" to it.title,
                            "nextAlarmEpochMs" to AlarmScheduler.nextMainTrigger(it, now),
                            "nextReminderEpochMs" to AlarmScheduler.nextReminderTrigger(it, now)
                        )
                    })
                }

                "rescheduleAll" -> {
                    AlarmScheduler.scheduleAll(this)
                    result.success(true)
                }

                "openDndSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                        startActivity(intent)
                    }
                    result.success(true)
                }

                "getTriggeredAlarmData" -> {
                    result.success(triggeredAlarmData)
                }

                "clearTriggeredAlarmData" -> {
                    triggeredAlarmData = null
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun openAppDetails() {
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
