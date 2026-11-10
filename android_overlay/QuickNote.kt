package com.towkirhs.jarcis

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.view.Gravity
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

/**
 * "Type to Jarvis": a small card over whatever you are doing. Type, send, and Jarvis answers in the card;
 * the app itself never opens. Opened by Handy's Jarvis bubble (text) or the action com.towkirhs.jarcis.TYPE.
 * Tap outside the card to close it.
 */
class TypeActivity : Activity() {
    private lateinit var box: EditText
    private lateinit var answer: TextView
    private val main by lazy { Handler(Looper.getMainLooper()) }
    private val giveUp = Runnable { show("Saved. Jarvis will answer in a notification.") }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setShowWhenLocked(true)
        val dp = resources.displayMetrics.density
        answer = TextView(this).apply {
            textSize = 16f
            setTextColor(Color.WHITE)
            maxLines = 8
            visibility = TextView.GONE
            setPadding(0, 0, 0, (12 * dp).toInt())
        }
        box = EditText(this).apply {
            hint = "Tell Jarvis…"
            textSize = 17f
            setTextColor(Color.WHITE)
            setHintTextColor(0x99FFFFFF.toInt())
            background = null
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES or InputType.TYPE_TEXT_FLAG_AUTO_CORRECT
            imeOptions = EditorInfo.IME_ACTION_SEND
            setOnEditorActionListener { _, action, _ -> if (action == EditorInfo.IME_ACTION_SEND) send() else false }
        }
        fun link(label: String, tap: () -> Unit) = TextView(this).apply {
            text = label
            textSize = 14f
            setTextColor(0xFF9FD3D3.toInt())
            setPadding((20 * dp).toInt(), (12 * dp).toInt(), 0, 0)
            setOnClickListener { tap() }
        }
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val pad = (20 * dp).toInt()
            setPadding(pad, pad, pad, pad)
            background = GradientDrawable().apply {
                cornerRadius = 28 * dp
                setColor(0xF01E2A33.toInt())
            }
            addView(answer)
            addView(box, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            addView(LinearLayout(this@TypeActivity).apply {
                gravity = Gravity.END
                addView(link("Open Jarvis") {
                    startActivity(Intent(this@TypeActivity, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    finish()
                })
                addView(link("Send") { send() })
            })
            isClickable = true
        }
        val root = FrameLayout(this).apply {
            setOnClickListener { finish() }
            addView(card, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                gravity = Gravity.BOTTOM
                val m = (16 * dp).toInt()
                setMargins(m, m, m, m)
            })
            // Keep the card just above the keyboard.
            setOnApplyWindowInsetsListener { v, insets ->
                v.setPadding(0, 0, 0, insets.getInsets(WindowInsets.Type.ime() or WindowInsets.Type.systemBars()).bottom)
                insets
            }
        }
        window.setDecorFitsSystemWindows(false)
        setContentView(root)
        box.requestFocus()
        // Jarvis's answers come to this card while it is open, instead of a notification.
        Chat.card = { text -> show(text) }
    }

    private fun send(): Boolean {
        val text = box.text.toString().trim()
        if (text.isEmpty()) return true
        box.setText("")
        main.removeCallbacks(giveUp)
        if (Commands.parse(this, text) != null) {
            // A phone command ("flashlight on", "set a timer"): done at once, quietly.
            show(Assistant.handle(this, text, false))
        } else {
            show("…")
            NoteQueue.add(this, text, null, "typed")
            Chat.process(this, null)
            main.postDelayed(giveUp, 25_000)
        }
        return true
    }

    private fun show(text: String) {
        if (text != "…") main.removeCallbacks(giveUp)
        answer.text = text
        answer.visibility = TextView.VISIBLE
    }

    override fun onDestroy() {
        main.removeCallbacksAndMessages(null)
        Chat.card = null
        super.onDestroy()
    }
}
