package com.towkirhs.jarcis

/**
 * "Type to Jarvis": the same card as Talk to Jarvis (ListenActivity), opening with the keyboard instead of the mic.
 * Opened by Handy's Jarvis bubble (text) or the action com.towkirhs.jarcis.TYPE. The app itself never opens.
 */
class TypeActivity : ListenActivity() {
    override val listenFirst = false
}
