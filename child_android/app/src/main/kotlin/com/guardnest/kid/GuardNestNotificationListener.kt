package com.guardnest.kid

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Notification access is granted during setup, but chat capture no longer reads
 * notifications: WhatsApp messages are captured only from the on-screen
 * conversation (via the accessibility service) when the child actually opens a
 * chat. This listener is therefore intentionally a no-op.
 */
class GuardNestNotificationListener : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        // Intentionally does nothing — chats are captured only when opened.
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {}
}

