package com.reptrack.app.reptrack

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Restores every scheduled routine alarm after the system dropped them:
 * reboot, app update, manual clock change or timezone change.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                try {
                    AlarmScheduler.scheduleAll(context)
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
    }
}
