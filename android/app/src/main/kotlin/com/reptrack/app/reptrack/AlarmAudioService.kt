package com.reptrack.app.reptrack

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat

class AlarmAudioService : Service() {

    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null

    companion object {
        const val CHANNEL_ID = "reptrack_alarm_ring_channel"
        const val NOTIFICATION_ID = 9901

        const val ACTION_START = "com.reptrack.app.action.START_ALARM"
        const val ACTION_STOP = "com.reptrack.app.action.STOP_ALARM"

        const val EXTRA_TITLE = "extra_title"
        const val EXTRA_ROUTINE_ID = "extra_routine_id"
        const val EXTRA_IS_AUDIBLE = "extra_is_audible"
        const val EXTRA_VIBRATION = "extra_vibration"

        var isCurrentlyRinging = false
            private set
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START

        if (action == ACTION_STOP) {
            stopAlarmPlayback()
            stopForeground(true)
            stopSelf()
            return START_NOT_STICKY
        }

        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "RepTrack Routine"
        val routineId = intent?.getIntExtra(EXTRA_ROUTINE_ID, 0) ?: 0
        val isAudible = intent?.getBooleanExtra(EXTRA_IS_AUDIBLE, true) ?: true
        val useVibration = intent?.getBooleanExtra(EXTRA_VIBRATION, true) ?: true

        // Create foreground notification to guarantee service continuity
        val notification = buildForegroundNotification(title, routineId)
        startForeground(NOTIFICATION_ID, notification)

        isCurrentlyRinging = true

        if (isAudible) {
            startAudioPlayback()
        }

        if (useVibration) {
            startVibration()
        }

        return START_STICKY
    }

    private fun startAudioPlayback() {
        try {
            mediaPlayer?.release()
            mediaPlayer = null

            // Use default alarm tone or fallback to notification tone
            var alertUri: Uri? = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            if (alertUri == null) {
                alertUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            }
            if (alertUri == null) {
                alertUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            }

            mediaPlayer = MediaPlayer().apply {
                setDataSource(applicationContext, alertUri!!)
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                isLooping = true
                prepare()
                start()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun startVibration() {
        try {
            vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vibratorManager.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }

            val pattern = longArrayOf(0, 600, 400, 600, 400)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(pattern, 0)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopAlarmPlayback() {
        isCurrentlyRinging = false
        try {
            mediaPlayer?.stop()
            mediaPlayer?.release()
            mediaPlayer = null
        } catch (e: Exception) {
            e.printStackTrace()
        }

        try {
            vibrator?.cancel()
            vibrator = null
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun buildForegroundNotification(title: String, routineId: Int): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("alarm_routine_id", routineId)
            putExtra("alarm_title", title)
            putExtra("alarm_is_ringing", true)
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            routineId,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Action: Stop
        val stopIntent = Intent(this, AlarmAudioService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPending = PendingIntent.getService(
            this,
            routineId + 50000,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("RepTrack Routine Alarm: $title")
            .setContentText("Activity time! Tap to open alarm controls or stop.")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(pendingIntent)
            .setFullScreenIntent(pendingIntent, true)
            .setOngoing(true)
            .setAutoCancel(false)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop Alarm", stopPending)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val audioAttributes = AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(AudioAttributes.USAGE_ALARM)
                .build()

            val channel = NotificationChannel(
                CHANNEL_ID,
                "RepTrack Routine Alarms",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "High-priority alarms for scheduled daily routines"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 600, 400, 600, 400)
                setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM), audioAttributes)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }

            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    override fun onDestroy() {
        stopAlarmPlayback()
        super.onDestroy()
    }
}
