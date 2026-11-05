package com.towkirhs.jarcis

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import java.io.File

/**
 * "Send to Jarvis" in Android's share menu (from the copy pop-up, a screenshot, or any app).
 * Saves the text or image, gets it processed in the background, and closes straight away.
 */
class ShareActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim().orEmpty()
        val image = imageUri(intent)?.let { copyImage(it) }
        if (text.isEmpty() && image == null) {
            Toast.makeText(this, "Nothing to send", Toast.LENGTH_SHORT).show()
        } else {
            NoteQueue.add(this, text, image, "share")
            val app = MainActivity.live
            if (app != null) app.invokeMethod("notesWaiting", null) else BackgroundRunner.run(this, null)
            Toast.makeText(this, "Sent to Jarvis", Toast.LENGTH_SHORT).show()
        }
        finish()
    }

    private fun imageUri(intent: Intent): Uri? {
        if (intent.type?.startsWith("image/") != true) return null
        return if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }
    }

    /** Copies the shared image into the app's own storage, so it is still there when it gets processed. */
    private fun copyImage(uri: Uri): String? = try {
        val dir = File(filesDir, "shared").apply { mkdirs() }
        val ext = if (contentResolver.getType(uri) == "image/png") "png" else "jpg"
        val file = File(dir, "${System.currentTimeMillis()}.$ext")
        contentResolver.openInputStream(uri)?.use { input -> file.outputStream().use { input.copyTo(it) } }
        file.absolutePath
    } catch (e: Exception) {
        null
    }
}
