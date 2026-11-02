package com.towkirhs.jarcis

import android.content.BroadcastReceiver
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Runs the Dart code in backgroundMain() without opening the app, so a note from Handy is
 * understood (and its alarm set) right away. Only used when the app's screen isn't alive.
 */
object BackgroundRunner {
    private const val TIMEOUT_MS = 25_000L
    private var engine: FlutterEngine? = null
    private val pending = mutableListOf<BroadcastReceiver.PendingResult>()
    private val handler = Handler(Looper.getMainLooper())
    private val timeout = Runnable { stop() }

    /** Must be called on the main thread. */
    fun run(context: Context, result: BroadcastReceiver.PendingResult) {
        pending.add(result)
        if (engine != null) return // the running engine keeps draining until the queue is empty
        val app = context.applicationContext
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(app)
        loader.ensureInitializationComplete(app, null)
        val e = FlutterEngine(app)
        MethodChannel(e.dartExecutor.binaryMessenger, "jarcis/native").setMethodCallHandler { call, res ->
            if (call.method == "backgroundDone") {
                res.success(null)
                handler.post { stop() }
            } else if (!NativeChannel.handle(app, call, res)) {
                res.notImplemented()
            }
        }
        engine = e
        handler.postDelayed(timeout, TIMEOUT_MS)
        e.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "backgroundMain")
        )
    }

    private fun stop() {
        handler.removeCallbacks(timeout)
        engine?.destroy()
        engine = null
        pending.forEach { it.finish() }
        pending.clear()
    }
}
