package com.reptrack.app.reptrack

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
                        val title = call.argument<String>("title") ?: "Routine"
                        val category = call.argument<String>("category") ?: "Routine"
                        val time = call.argument<String>("time") ?: ""
                        val triggerEpochMs = call.argument<Long>("triggerEpochMs") ?: 0L
                        val isAudible = call.argument<Boolean>("isAudible") ?: true
                        val vibration = call.argument<Boolean>("vibration") ?: true

                        if (triggerEpochMs <= System.currentTimeMillis()) {
                            result.error("INVALID_TIME", "Trigger time must be in the future", null)
                            return@setMethodCallHandler
                        }

                        val intent = Intent(this, AlarmReceiver::class.java).apply {
                            action = AlarmReceiver.ACTION_TRIGGER_ALARM
                            putExtra(AlarmReceiver.EXTRA_ROUTINE_ID, routineId)
                            putExtra(AlarmReceiver.EXTRA_TITLE, title)
                            putExtra(AlarmReceiver.EXTRA_CATEGORY, category)
                            putExtra(AlarmReceiver.EXTRA_TIME, time)
                            putExtra(AlarmReceiver.EXTRA_IS_AUDIBLE, isAudible)
                            putExtra(AlarmReceiver.EXTRA_VIBRATION, vibration)
                        }

                        val pendingIntent = PendingIntent.getBroadcast(
                            this,
                            routineId,
                            intent,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )

                        val showIntent = Intent(this, MainActivity::class.java).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                            putExtra("alarm_routine_id", routineId)
                            putExtra("alarm_title", title)
                        }
                        val pendingShow = PendingIntent.getActivity(
                            this,
                            routineId + 40000,
                            showIntent,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )

                        // setAlarmClock guarantees reliable wakeup in Doze mode and shows alarm icon in status bar
                        val clockInfo = AlarmManager.AlarmClockInfo(triggerEpochMs, pendingShow)
                        alarmManager.setAlarmClock(clockInfo, pendingIntent)

                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ALARM_ERROR", e.message, null)
                    }
                }

                "cancelAlarm" -> {
                    try {
                        val routineId = call.argument<Int>("routineId") ?: 0
                        val intent = Intent(this, AlarmReceiver::class.java).apply {
                            action = AlarmReceiver.ACTION_TRIGGER_ALARM
                        }
                        val pendingIntent = PendingIntent.getBroadcast(
                            this,
                            routineId,
                            intent,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )
                        alarmManager.cancel(pendingIntent)
                        pendingIntent.cancel()

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
                        }
                        val pendingIntent = PendingIntent.getBroadcast(
                            this,
                            routineId,
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

                    result.success(mapOf(
                        "canScheduleExactAlarms" to canExactAlarm,
                        "notificationsEnabled" to notifGranted,
                        "isBatteryOptimizationIgnored" to batteryIgnored,
                        "isDndAccessGranted" to dndGranted
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
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                            data = Uri.parse("package:$packageName")
                        }
                        startActivity(intent)
                    }
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
}
