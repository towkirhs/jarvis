package com.towkirhs.jarcis

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Re-arms every saved alarm after a reboot or an app update. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            AlarmScheduler.rearmAll(context)
            Geo.register(context) // Android forgets geofences on reboot
        }
    }
}
