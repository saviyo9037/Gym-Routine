package com.reptrack.app.reptrack

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action == Intent.ACTION_BOOT_COMPLETED ||
            action == Intent.ACTION_TIMEZONE_CHANGED ||
            action == Intent.ACTION_TIME_CHANGED ||
            action == Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            // When device reboots or timezone changes, alarms need rescheduling.
            // MainActivity's Flutter lifecycle will automatically reschedule active routines on launch.
        }
    }
}
