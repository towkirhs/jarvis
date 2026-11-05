package com.towkirhs.jarcis

import android.app.Notification
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject

/** Money messages (SMS or app notifications) waiting for Jarvis to read them. */
object MoneyQueue {
    private const val FILE = "jarcis_money"
    private val looksLikeMoney = Regex("(Tk|BDT|৳)\\.?\\s*[\\d,]+", RegexOption.IGNORE_CASE)

    @Synchronized
    fun add(context: Context, from: String, text: String) {
        if (!looksLikeMoney.containsMatchIn(text)) return
        val p = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        val arr = JSONArray(p.getString("q", "[]"))
        arr.put(JSONObject().put("from", from).put("text", text).put("ts", System.currentTimeMillis()))
        p.edit().putString("q", arr.toString()).apply()
        MainActivity.live?.invokeMethod("moneyWaiting", null)
    }

    @Synchronized
    fun take(context: Context): String {
        val p = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        val q = p.getString("q", "[]") ?: "[]"
        p.edit().putString("q", "[]").apply()
        return q
    }
}

/** Incoming SMS. Only works after the person allows SMS in Jarvis's money settings. */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        // A long SMS arrives in parts; join them per sender.
        parts.groupBy { it.originatingAddress ?: "" }.forEach { (from, msgs) ->
            MoneyQueue.add(context, from, msgs.joinToString("") { it.messageBody ?: "" })
        }
    }
}

/** Notifications from wallet and bank apps. Only runs after the person turns on notification access. */
class MoneyNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName == packageName) return
        val extras = sbn.notification.extras
        val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString() ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        MoneyQueue.add(this, "${sbn.packageName} $title", text)
    }
}
