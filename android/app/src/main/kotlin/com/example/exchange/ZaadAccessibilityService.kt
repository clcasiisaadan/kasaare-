package com.example.exchange

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.util.Log
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.content.Context

class ZaadAccessibilityService : AccessibilityService() {

    private var balanceCheckedAndConfirmed = false
    private var lastHandledText = ""
    private var isBusy = false
    private var isManualRun = false
    private var wakeLock: PowerManager.WakeLock? = null

    private val intervalHandler = Handler(Looper.getMainLooper())
    private var intervalRunnable: Runnable? = null
    private var currentIntervalMillis: Long = 20 * 1000L

    override fun onServiceConnected() {
        super.onServiceConnected()
        acquireWakeLock()
        startPeriodicCheckBalanceLoop()
    }

    private fun acquireWakeLock() {
        try {
            if (wakeLock == null) {
                val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                // Isticmaalka SCREEN_BRIGHT_WAKE_LOCK iyo ACQUIRE_CAUSES_WAKEUP waxay si khasab ah u shidayaan screen-ka
                wakeLock = powerManager.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                    PowerManager.ACQUIRE_CAUSES_WAKEUP or
                    PowerManager.ON_AFTER_RELEASE,
                    "ZaadAuto::BrightScreenWakeLock"
                )
            }
            if (wakeLock?.isHeld == false) {
                wakeLock?.acquire(6 * 60 * 60 * 1000L) // 6 Saacadood oo xidhiidh ah oo aanu screen-ku daminayn
            }
        } catch (e: Exception) {
            Log.e("ZaadAccessibility", "WakeLock error: ${e.message}")
        }
    }

    private fun isLicenseActive(): Boolean {
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val deviceId = prefs.getString("flutter.app_device_id", prefs.getString("app_device_id", "74EDF0753D14ADFE")) ?: ""
        val approvedDeviceId = prefs.getString("flutter.approved_device_id", prefs.getString("approved_device_id", "")) ?: ""
        val expiryMillis = prefs.getLong("flutter.license_expiry_millis", prefs.getLong("license_expiry_millis", 0L))
        val isApproved = prefs.getBoolean("flutter.is_admin_approved", prefs.getBoolean("is_admin_approved", false))

        if (!isApproved || expiryMillis == 0L || deviceId.isEmpty() || approvedDeviceId != deviceId) {
            return false
        }
        return System.currentTimeMillis() < expiryMillis
    }

    private fun startPeriodicCheckBalanceLoop() {
        intervalRunnable = object : Runnable {
            override fun run() {
                acquireWakeLock()
                val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                
                if (!isLicenseActive()) {
                    intervalHandler.postDelayed(this, currentIntervalMillis)
                    return
                }

                val isAccessibilityOn = prefs.getBoolean("flutter.accessibility_access_on", prefs.getBoolean("accessibility_access_on", true))
                if (!isAccessibilityOn) {
                    intervalHandler.postDelayed(this, currentIntervalMillis)
                    return
                }

                val isCheckBalanceOn = prefs.getBoolean("flutter.check_balance_on", false)
                val intervalValue = prefs.getInt("flutter.check_balance_interval_val", 20)
                currentIntervalMillis = intervalValue * 1000L

                val type = prefs.getString("flutter.type", "") ?: ""

                if (isCheckBalanceOn && !isBusy) {
                    val ussdCode = if (type.contains("SALAAM BANK", ignoreCase = true)) "*800#" else "*801#"
                    Log.d("ZaadAccessibility", "Periodic Check Balance Triggered ($ussdCode)")
                    triggerUssd(ussdCode)
                }

                intervalHandler.postDelayed(this, currentIntervalMillis)
            }
        }
        intervalHandler.postDelayed(intervalRunnable!!, currentIntervalMillis)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        acquireWakeLock()
        if (event == null) return
        
        if (!isLicenseActive()) return

        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        
        val isAccessibilityOn = prefs.getBoolean("flutter.accessibility_access_on", prefs.getBoolean("accessibility_access_on", true))
        if (!isAccessibilityOn) return

        val rootNode = rootInActiveWindow ?: return
        val fullScreenText = extractAllText(rootNode).lowercase()

        if (fullScreenText.isEmpty()) return

        Log.d("ZaadAccessibility", "Screen Text: $fullScreenText")

        val isCheckBalanceOn = prefs.getBoolean("flutter.check_balance_on", false)
        val isAutoTransferOn = prefs.getBoolean("flutter.auto_transfer_on", true) || prefs.getBoolean("flutter.auto_transfer", true)
        val isManualCheckTriggered = prefs.getBoolean("flutter.manual_check", false)
        val type = prefs.getString("flutter.type", "") ?: ""

        if (isManualCheckTriggered) {
            isManualRun = true
            prefs.edit().putBoolean("flutter.manual_check", false).apply()
        }

        if (!isCheckBalanceOn && !isAutoTransferOn && !isManualRun) return
        if (isBusy) return

        if (fullScreenText == lastHandledText && 
            !fullScreenText.contains("are you sure") && 
            !fullScreenText.contains("confirm") && 
            !fullScreenText.contains("ma hubtaa") &&
            !fullScreenText.contains("fadlan geli pin") &&
            !fullScreenText.contains("enter pin") &&
            !fullScreenText.contains("geli pin-kaaga")) {
            return
        }

        if (fullScreenText.contains("account-kan ma aha mid jira") ||
            fullScreenText.contains("ma aha mid jira") ||
            fullScreenText.contains("invalid pin format") ||
            fullScreenText.contains("insufficient balance") || 
            fullScreenText.contains("kuguma filna") || 
            fullScreenText.contains("invalid amount") || 
            fullScreenText.contains("invalid menu option") || 
            fullScreenText.contains("invalid option") || 
            fullScreenText.contains("internal service error") || 
            fullScreenText.contains("please try again") || 
            fullScreenText.contains("connection problem") || 
            fullScreenText.contains("invalid mmi code") || 
            fullScreenText.contains("tiriada lacagta") ||
            fullScreenText.contains("ka yartahay") ||
            fullScreenText.contains("error") || 
            fullScreenText.contains("failed") || 
            fullScreenText.contains("session") || 
            fullScreenText.contains("canceled") || 
            fullScreenText.contains("cancelled") ||
            fullScreenText.contains("input required")) {
            
            isBusy = true
            lastHandledText = fullScreenText
            Handler(Looper.getMainLooper()).postDelayed({
                clickSendOrOkButton(rootNode)
                Handler(Looper.getMainLooper()).postDelayed({
                    isBusy = false
                    balanceCheckedAndConfirmed = false
                    lastHandledText = ""
                    
                    val ussdCode = if (type.contains("SALAAM BANK", ignoreCase = true)) "*800#" else "*801#"
                    triggerUssd(ussdCode)
                }, 20)
            }, 10)
            return
        }

        var zaadPin = prefs.getString("flutter.zaadPin", "") ?: ""
        if (zaadPin.isEmpty()) zaadPin = prefs.getString("zaadPin", "") ?: ""
        if (zaadPin.isEmpty()) zaadPin = prefs.getString("flutter.zaad_pin", "") ?: ""
        if (zaadPin.isEmpty()) zaadPin = prefs.getString("zaad_pin", "") ?: ""
        
        zaadPin = zaadPin.replace(Regex("[^0-9]"), "").trim()

        val isPinScreen = fullScreenText.contains("fadlan geli pin") || 
                          fullScreenText.contains("fadlan gali pin") || 
                          fullScreenText.contains("enter pin") || 
                          fullScreenText.contains("pin-kaaga") ||
                          fullScreenText.contains("geli pin")

        if (isPinScreen) {
            if (zaadPin.isNotEmpty()) {
                isBusy = true
                lastHandledText = fullScreenText
                executeZaadPinInput(zaadPin)
                return
            }
        }

        if (isCheckBalanceOn || isAutoTransferOn || isManualRun) {
            val balanceQueryText = if (fullScreenText.contains("hadhaagaaga")) {
                fullScreenText.substringAfter("hadhaagaaga")
            } else if (fullScreenText.contains("hadhaaga")) {
                fullScreenText.substringAfter("hadhaaga")
            } else if (fullScreenText.contains("hadhaageedu waa")) {
                fullScreenText.substringAfter("hadhaageedu waa")
            } else {
                fullScreenText
            }

            if (!fullScreenText.contains("u dirtay") && !fullScreenText.contains("u dhiibtay")) {
                val matchResult = Regex("""\$\s*(\d+(\.\d+)?)""").find(balanceQueryText) 
                    ?: Regex("""\$\s*(\d+(\.\d+)?)""").findAll(fullScreenText).lastOrNull()

                if (matchResult != null && !balanceCheckedAndConfirmed) {
                    val rawAmount = matchResult.groupValues[1]
                    val amountDouble = rawAmount.toDoubleOrNull() ?: 0.0

                    if (amountDouble < 0.1) {
                        balanceCheckedAndConfirmed = true
                        isBusy = true
                        Handler(Looper.getMainLooper()).postDelayed({
                            clickSendOrOkButton(rootInActiveWindow)
                            isBusy = false
                            balanceCheckedAndConfirmed = false
                            lastHandledText = ""
                        }, 5)
                        return
                    }

                    if (amountDouble >= 0.1) {
                        val amountValue = rawAmount

                        balanceCheckedAndConfirmed = true
                        isBusy = true
                        lastHandledText = fullScreenText

                        prefs.edit().putString("flutter.pending_amount", amountValue).apply()

                        val ussdCode = if (type.contains("SALAAM BANK", ignoreCase = true)) {
                            "*800#"
                        } else {
                            var phone = prefs.getString("flutter.phone", "") ?: ""
                            if (phone.isEmpty()) phone = prefs.getString("phone", "") ?: ""
                            phone = phone.replace(Regex("[^0-9]"), "").trim()

                            var adminPin = prefs.getString("flutter.adminPin", "") ?: ""
                            if (adminPin.isEmpty()) adminPin = prefs.getString("adminPin", "") ?: ""
                            adminPin = adminPin.replace(Regex("[^0-9]"), "").trim()

                            if (phone.isNotEmpty() && adminPin.isNotEmpty()) {
                                "*806*$phone*$amountValue*$adminPin#"
                            } else {
                                "*801#"
                            }
                        }

                        Handler(Looper.getMainLooper()).postDelayed({
                            clickSendOrOkButton(rootInActiveWindow)
                            
                            Handler(Looper.getMainLooper()).postDelayed({
                                lastHandledText = ""
                                triggerUssd(ussdCode)
                                balanceCheckedAndConfirmed = false
                                isBusy = false
                            }, 10)
                        }, 5)
                        return
                    }
                }
            }
        }

        if (!type.contains("SALAAM BANK", ignoreCase = true) && !isPinScreen) {
            if (fullScreenText.contains("are you sure") || 
                fullScreenText.contains("confirm") || 
                fullScreenText.contains("ma hubtaa") || 
                fullScreenText.contains("ma rabtaa")) {
                isBusy = true
                executeFastInput("1")
                return
            }

            if (fullScreenText.contains("guul") || fullScreenText.contains("u dhiibtay") || fullScreenText.contains("u dirtay") || fullScreenText.contains("lagu shubay") || fullScreenText.contains("successful")) {
                isBusy = true
                lastHandledText = fullScreenText

                var remainingAmountDouble = 0.0
                var remainingRawAmount = ""

                if (fullScreenText.contains("hadhaagaaga")) {
                    val afterBalanceText = fullScreenText.substringAfter("hadhaagaaga")
                    val match = Regex("""\$\s*(\d+(\.\d+)?)""").find(afterBalanceText)
                    if (match != null) {
                        remainingRawAmount = match.groupValues[1]
                        remainingAmountDouble = remainingRawAmount.toDoubleOrNull() ?: 0.0
                    }
                }

                if (remainingAmountDouble >= 0.1) {
                    var phone = prefs.getString("flutter.phone", "") ?: ""
                    if (phone.isEmpty()) phone = prefs.getString("phone", "") ?: ""
                    phone = phone.replace(Regex("[^0-9]"), "").trim()

                    var adminPin = prefs.getString("flutter.adminPin", "") ?: ""
                    if (adminPin.isEmpty()) adminPin = prefs.getString("adminPin", "") ?: ""
                    adminPin = adminPin.replace(Regex("[^0-9]"), "").trim()

                    if (phone.isNotEmpty() && adminPin.isNotEmpty()) {
                        prefs.edit().putString("flutter.pending_amount", remainingRawAmount).apply()
                        val nextUssdCode = "*806*$phone*$remainingRawAmount*$adminPin#"

                        Handler(Looper.getMainLooper()).postDelayed({
                            clickSendOrOkButton(rootInActiveWindow)
                            Handler(Looper.getMainLooper()).postDelayed({
                                lastHandledText = ""
                                triggerUssd(nextUssdCode)
                                isBusy = false
                            }, 15)
                        }, 5)
                        return
                    }
                }

                Handler(Looper.getMainLooper()).postDelayed({
                    clickSendOrOkButton(rootInActiveWindow)
                    isBusy = false
                    balanceCheckedAndConfirmed = false
                    lastHandledText = ""
                    isManualRun = false
                }, 10)
                return
            }
        }

        if (type.contains("SALAAM BANK", ignoreCase = true)) {
            var registerPin = prefs.getString("flutter.registerPin", "") ?: ""
            if (registerPin.isEmpty()) registerPin = prefs.getString("registerPin", "") ?: ""
            registerPin = registerPin.replace(Regex("[^0-9]"), "").trim()

            val amount = prefs.getString("flutter.pending_amount", "") ?: "1"

            if (fullScreenText.contains("adeega sarifka") || fullScreenText.contains("dara-salaam bank")) {
                if (fullScreenText.contains("5. dara-salaam bank") || fullScreenText.contains("5.dara-salaam bank") || fullScreenText.contains("5.")) {
                    isBusy = true
                    executeFastInput("5")
                    return
                }
            }

            if (fullScreenText.contains("dara-salaam bank") && (fullScreenText.contains("lacag dhigasho") || fullScreenText.contains("2."))) {
                isBusy = true
                executeFastInput("2")
                return
            }

            if (fullScreenText.contains("fadlan geli lacagta") || fullScreenText.contains("fadlan gali lacagta") || fullScreenText.contains("geli lacagta")) {
                if (amount.isNotEmpty()) {
                    isBusy = true
                    executeFastInput(amount)
                    return
                }
            }

            if (fullScreenText.contains("fadlan geli macluumaad") || fullScreenText.contains("geli macluumaad")) {
                isBusy = true
                executeFastInput("1")
                return
            }

            if (fullScreenText.contains("sirta ee bangiga") || fullScreenText.contains("numberkaaga sirta") || fullScreenText.contains("pin-ka bangiga")) {
                if (registerPin.isNotEmpty()) {
                    isBusy = true
                    executeFastInput(registerPin)
                    return
                }
            }

            if (fullScreenText.contains("are you sure") || fullScreenText.contains("confirm this service") || fullScreenText.contains("ma hubtaa")) {
                isBusy = true
                executeFastInput("1")
                return
            }

            if (fullScreenText.contains("guul") || fullScreenText.contains("lagu shubay") || fullScreenText.contains("sucessful")) {
                isBusy = true
                
                Handler(Looper.getMainLooper()).postDelayed({
                    clickSendOrOkButton(rootInActiveWindow)
                    isBusy = false
                    balanceCheckedAndConfirmed = false
                    lastHandledText = ""
                    isManualRun = false
                }, 10)
                return
            }
        }
    }

    private fun executeZaadPinInput(pinToType: String) {
        Handler(Looper.getMainLooper()).postDelayed({
            val rootNode = rootInActiveWindow
            if (rootNode != null) {
                val editable = findEditableNode(rootNode)
                if (editable != null) {
                    editable.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    editable.performAction(AccessibilityNodeInfo.ACTION_FOCUS)

                    val cleanPin = pinToType.replace(Regex("[^0-9]"), "").trim()
                    val arguments = Bundle().apply {
                        putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, cleanPin)
                    }
                    editable.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)

                    Handler(Looper.getMainLooper()).postDelayed({
                        if (editable.text.isNull_or_empty()) {
                            editable.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)
                        }
                        
                        Handler(Looper.getMainLooper()).postDelayed({
                            clickSendOrOkButton(rootInActiveWindow)
                            isBusy = false
                        }, 25)
                    }, 25)
                } else {
                    isBusy = false
                }
            } else {
                isBusy = false
            }
        }, 5)
    }

    private fun CharSequence?.isNull_or_empty(): Boolean {
        return this == null || this.isEmpty()
    }

    private fun executeFastInput(textToType: String) {
        Handler(Looper.getMainLooper()).postDelayed({
            val rootNode = rootInActiveWindow
            if (rootNode != null) {
                val editable = findEditableNode(rootNode)
                if (editable != null) {
                    editable.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    editable.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
                    val arguments = Bundle().apply {
                        putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, textToType)
                    }
                    editable.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)

                    Handler(Looper.getMainLooper()).postDelayed({
                        clickSendOrOkButton(rootInActiveWindow)
                        isBusy = false
                    }, 10)
                } else {
                    isBusy = false
                }
            } else {
                isBusy = false
            }
        }, 5)
    }

    private fun extractAllText(node: AccessibilityNodeInfo?): String {
        if (node == null) return ""
        val sb = StringBuilder()
        if (node.text != null) {
            sb.append(node.text).append(" ")
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i)
            if (child != null) {
                sb.append(extractAllText(child))
            }
        }
        return sb.toString()
    }

    private fun findEditableNode(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null) return null
        if (node.isEditable || (node.className != null && node.className.toString().contains("EditText"))) {
            return node
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i)
            val found = findEditableNode(child)
            if (found != null) return found
        }
        return null
    }

    private fun triggerUssd(code: String) {
        lastHandledText = ""
        val encodedUssd = Uri.encode(code)
        val intent = Intent(Intent.ACTION_CALL, Uri.parse("tel:$encodedUssd")).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        try {
            startActivity(intent)
        } catch (e: Exception) {
            Log.e("ZaadAccessibility", "Khalad USSD: ${e.message}")
        }
    }

    private fun clickSendOrOkButton(nodeInfo: AccessibilityNodeInfo?) {
        var root = nodeInfo
        while (root?.parent != null) {
            root = root.parent
        }
        root?.let { findAndClickButton(it) } ?: run {
            rootInActiveWindow?.let { findAndClickButton(it) }
        }
    }

    private fun findAndClickButton(node: AccessibilityNodeInfo): Boolean {
        val text = node.text?.toString()?.uppercase() ?: ""
        val contentDesc = node.contentDescription?.toString()?.uppercase() ?: ""

        if (text == "SEND" || text == "OK" || text == "HAA" || text == "DIRO" || contentDesc.contains("SEND") || contentDesc.contains("OK")) {
            if (node.isClickable) {
                node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                return true
            }
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i)
            if (child != null) {
                if (findAndClickButton(child)) {
                    return true
                }
            }
        }
        return false
    }

    override fun onDestroy() {
        super.onDestroy()
        intervalRunnable?.let { intervalHandler.removeCallbacks(it) }
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (e: Exception) {
            Log.e("ZaadAccessibility", "WakeLock release error: ${e.message}")
        }
    }

    override fun onInterrupt() {
        balanceCheckedAndConfirmed = false
        isBusy = false
        isManualRun = false
        lastHandledText = ""
        Log.d("ZaadAccessibility", "Service Interrupted")
    }
}