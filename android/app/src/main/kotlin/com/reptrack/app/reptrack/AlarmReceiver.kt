package com.reptrack.app.reptrack

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.PowerManager
import androidx.core.app.NotificationCompat

class AlarmReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_TRIGGER_ALARM = "com.reptrack.app.action.TRIGGER_ALARM"

        const val EXTRA_ROUTINE_ID = "extra_routine_id"
        const val EXTRA_TITLE = "extra_title"
        const val EXTRA_CATEGORY = "extra_category"
        const val EXTRA_TIME = "extra_time"
        const val EXTRA_IS_AUDIBLE = "extra_is_audible"
        const val EXTRA_VIBRATION = "extra_vibration"
        const val EXTRA_REPEAT_DAYS = "extra_repeat_days"

        const val NOTIFICATION_CHANNEL_ID = "reptrack_alarm_ring_channel"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val routineId = intent.getIntExtra(EXTRA_ROUTINE_ID, 0)
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "Routine Reminder"
        val category = intent.getStringExtra(EXTRA_CATEGORY) ?: "Routine"
        val time = intent.getStringExtra(EXTRA_TIME) ?: ""
        val isAudible = intent.getBooleanExtra(EXTRA_IS_AUDIBLE, true)
        val vibration = intent.getBooleanExtra(EXTRA_VIBRATION, true)

        // 1. Acquire temporary wake lock to ensure CPU remains active
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "reptrack:alarm_wake_lock"
        )
        wakeLock.acquire(45000) // 45 seconds safety window

        try {
            // 2. Start audible alarm service if audible is requested
            if (isAudible) {
                val serviceIntent = Intent(context, AlarmAudioService::class.java).apply {
                    action = AlarmAudioService.ACTION_START
                    putExtra(AlarmAudioService.EXTRA_TITLE, title)
                    putExtra(AlarmAudioService.EXTRA_ROUTINE_ID, routineId)
                    putExtra(AlarmAudioService.EXTRA_IS_AUDIBLE, true)
                    putExtra(AlarmAudioService.EXTRA_VIBRATION, vibration)
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
            }

            // 3. Launch MainActivity with Full-Screen intent so the ringing UI displays over lock screen
            val fullScreenIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("alarm_routine_id", routineId)
                putExtra("alarm_title", title)
                putExtra("alarm_category", category)
                putExtra("alarm_time", time)
                putExtra("alarm_is_ringing", true)
            }

            val pendingFullScreen = PendingIntent.getActivity(
                context,
                routineId + 10000,
                fullScreenIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Direct start activity if allowed
            try {
                context.startActivity(fullScreenIntent)
            } catch (e: Exception) {
                e.printStackTrace()
            }

            // 4. Post Heads-Up / Full-Screen Notification with Stop & Snooze actions
            showNotification(context, routineId, title, category, time, pendingFullScreen, isAudible)

        } catch (e: Exception) {
            e.printStackTrace()
        } finally {
            if (wakeLock.isHeld) {
                try {
                    wakeLock.release()
                } catch (e: Exception) {}
            }
        }
    }

    private fun showNotification(
        context: Context,
        routineId: Int,
        title: String,
        category: String,
        time: String,
        fullScreenPendingIntent: PendingIntent,
        isAudible: Boolean
    ) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val audioAttributes = AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(AudioAttributes.USAGE_ALARM)
                .build()

            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "RepTrack Routine Alarms",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "High-priority alarms for scheduled daily routines"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 300, 500)
                setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM), audioAttributes)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            manager.createNotificationChannel(channel)
        }

        // Action: Stop Alarm
        val stopIntent = Intent(context, AlarmAudioService::class.java).apply {
            action = AlarmAudioService.ACTION_STOP
        }
        val stopPending = PendingIntent.getService(
            context,
            routineId + 20000,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("Routine Alert: $title")
            .setContentText("Scheduled at $time • $category")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(fullScreenPendingIntent)
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .setAutoCancel(true)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPending)
            .build()

        manager.notify(routineId + 3000, notification)
    }
}
