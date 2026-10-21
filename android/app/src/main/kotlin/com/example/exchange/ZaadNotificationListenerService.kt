package com.example.exchange

import android.app.Notification
import android.content.Intent
import android.net.Uri
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

class ZaadNotificationListenerService : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return

        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        
        val isAutoTransferOn = prefs.getBoolean("flutter.auto_transfer_on", true)
        if (!isAutoTransferOn) {
            Log.d("ZaadListener", "Auto Transfer waa OFF, Notification-ka waa la iska indhatiray.")
            return
        }

        val extras = sbn.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val fullContent = "$title $text".lowercase()

        Log.d("ZaadListener", "Notification helay: $fullContent")

        if (fullContent.contains("heshay") || 
            fullContent.contains("ka helay") || 
            fullContent.contains("zaad") || 
            fullContent.contains("u sariftay") || 
            fullContent.contains("adeega sarifka")) {
            
            val amount = extractAmount(fullContent)
            if (amount != null && amount.isNotEmpty()) {
                Log.d("ZaadListener", "Lacag la helay/sarifay: $amount")

                prefs.edit().putString("flutter.pending_amount", amount).apply()

                val type = prefs.getString("flutter.type", "") ?: ""
                val ussdCode: String

                if (type.contains("SALAAM BANK", ignoreCase = true)) {
                    ussdCode = "*888#"
                    Log.d("ZaadListener", "Koodka Salaam Bank: *888#")
                } else {
                    val phone = prefs.getString("flutter.phone", "") ?: ""
                    val adminPin = prefs.getString("flutter.adminPin", "") ?: ""
                    ussdCode = "*806*$phone*$amount*$adminPin#"
                    Log.d("ZaadListener", "Koodka ZAAD: $ussdCode")
                }

                triggerUssd(ussdCode)
            }
        }
    }

    private fun triggerUssd(code: String) {
        val encodedUssd = Uri.encode(code)
        val intent = Intent(Intent.ACTION_CALL, Uri.parse("tel:$encodedUssd")).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        try {
            startActivity(intent)
        } catch (e: Exception) {
            Log.e("ZaadListener", "Khalad USSD: ${e.message}")
        }
    }

    private fun extractAmount(text: String): String? {
        val regex = Regex("""\$([0-9]+(?:\.[0-9]+)?)""")
        val matchResult = regex.find(text)
        return matchResult?.groupValues?.get(1)
    }
}