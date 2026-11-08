package com.towkirhs.jarcis

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.widget.Toast
import java.io.File

/** Installs a newer Jarvis APK that the app downloaded, through Android's own installer screen. */
object Updater {
    /** The build number of the installed app (the release's build-N). */
    fun build(context: Context): Long =
        context.packageManager.getPackageInfo(context.packageName, 0).longVersionCode

    /** Android asks once whether Jarvis may install apps; false until you allow it. */
    fun canInstall(context: Context) = context.packageManager.canRequestPackageInstalls()

    fun openInstallAccess(context: Context) {
        context.startActivity(
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    /** Hands the APK at [path] to the installer; Android then shows "Update Jarvis?". [done] gets an error or null. */
    fun install(context: Context, path: String, done: (String?) -> Unit) {
        val app = context.applicationContext
        val main = Handler(Looper.getMainLooper())
        Thread {
            val error = try {
                val file = File(path)
                val installer = app.packageManager.packageInstaller
                val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
                params.setAppPackageName(app.packageName)
                val id = installer.createSession(params)
                installer.openSession(id).use { session ->
                    file.inputStream().use { input ->
                        session.openWrite("jarvis.apk", 0, file.length()).use { out ->
                            input.copyTo(out)
                            session.fsync(out)
                        }
                    }
                    val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                        (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
                    val pending = PendingIntent.getBroadcast(app, id, Intent(app, InstallReceiver::class.java), flags)
                    session.commit(pending.intentSender)
                }
                null
            } catch (e: Exception) {
                e.message ?: e.toString()
            }
            main.post { done(error) }
        }.start()
    }
}

/** What the installer reports: it needs you to confirm (shows its screen), or it failed. */
class InstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                @Suppress("DEPRECATION")
                val confirm = if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                confirm?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)?.let { context.startActivity(it) }
            }
            PackageInstaller.STATUS_SUCCESS -> {}
            else -> {
                val why = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "error $status"
                Toast.makeText(context, "Jarvis update didn't install: $why", Toast.LENGTH_LONG).show()
            }
        }
    }
}
