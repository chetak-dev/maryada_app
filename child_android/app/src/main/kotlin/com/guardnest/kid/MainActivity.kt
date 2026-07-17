package com.guardnest.kid

import android.Manifest
import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * GuardNest Kid — the on-device companion. A calm, branded status screen that
 * shows whether the device is linked and protected, with a simple pairing flow.
 * Technical setup controls live under "Advanced" so the everyday view stays clean.
 *
 * Enroll Device Owner for testing (device must be factory-reset with NO accounts):
 *   adb shell dpm set-device-owner com.guardnest.kid/.GuardNestAdminReceiver
 */
class MainActivity : Activity() {

    private val scope = CoroutineScope(Dispatchers.Main)
    private val uiHandler = Handler(Looper.getMainLooper())
    private var wasPaired: Boolean? = null
    private var removalWatch: ListenerRegistration? = null
    // Location is optional (not a setup gate); we ask once per session so the
    // parent can see it if the child allows it.
    private var locationAsked = false

    /** Re-renders if the pairing state flips (e.g. parent removed the device). */
    private val pairingWatch = object : Runnable {
        override fun run() {
            val paired = ChildStore.isPaired(this@MainActivity)
            if (wasPaired != null && wasPaired != paired) render()
            wasPaired = paired
            uiHandler.postDelayed(this, 1000)
        }
    }

    // Set while a system settings screen is open for a permission; when that
    // permission is granted we pull the app back to the setup gate.
    private var awaitingGrant: (() -> Boolean)? = null
    private val grantPoll = object : Runnable {
        override fun run() {
            val check = awaitingGrant
            if (check == null) return
            if (check()) {
                awaitingGrant = null
                bringToFront()
                render()
            } else {
                uiHandler.postDelayed(this, 700)
            }
        }
    }

    // Colors
    private val cPrimary = Color.parseColor("#4F46E5")
    private val cPrimaryDark = Color.parseColor("#4338CA")
    private val cAccent = Color.parseColor("#10B981")
    private val cBg = Color.parseColor("#F5F6FB")
    private val cCard = Color.parseColor("#FFFFFF")
    private val cInk = Color.parseColor("#0F172A")
    private val cMuted = Color.parseColor("#64748B")
    private val cBorder = Color.parseColor("#E2E8F0")
    private val cDanger = Color.parseColor("#EF4444")

    // Status card views
    private lateinit var statusBadge: TextView
    private lateinit var statusTitle: TextView
    private lateinit var statusSubtitle: TextView
    private lateinit var statusCard: LinearLayout

    // Pairing
    private lateinit var codeInput: EditText
    private lateinit var pairingCard: LinearLayout
    private lateinit var linkButton: LinearLayout
    private lateinit var linkLabel: TextView
    private lateinit var linkProgress: ProgressBar
    private var linking = false
    private lateinit var unlinkButton: TextView
    private var unlinking = false
    private var tempAccessBtn: TextView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.decorView.setBackgroundColor(cBg)
        render()
    }

    override fun onResume() {
        super.onResume()
        // Back in the app — stop any pending grant-return poll.
        awaitingGrant = null
        uiHandler.removeCallbacks(grantPoll)
        // Re-check after returning from any system settings/consent screen.
        render()
        wasPaired = ChildStore.isPaired(this)
        uiHandler.removeCallbacks(pairingWatch)
        uiHandler.postDelayed(pairingWatch, 1000)
        attachRemovalWatch()
        maybeRequestLocation()
    }

    override fun onPause() {
        super.onPause()
        uiHandler.removeCallbacks(pairingWatch)
        removalWatch?.remove()
        removalWatch = null
    }

    /**
     * While linked, watches this device's own child doc. If the parent removes
     * the device (doc deleted), the local pairing is cleared immediately so the
     * screen stops showing “Linked” — even if the background service missed it.
     */
    private fun attachRemovalWatch() {
        removalWatch?.remove()
        removalWatch = null
        val fid = ChildStore.familyId(this) ?: return
        val cid = ChildStore.childId(this) ?: return
        removalWatch = FirebaseFirestore.getInstance()
            .collection("families").document(fid)
            .collection("children").document(cid)
            .addSnapshotListener { snap, _ ->
                if (snap != null && !snap.exists() && !snap.metadata.isFromCache) {
                    ChildStore.clear(this)
                    DeviceLockdown.releaseForRemoval(this)
                    WebFilterVpnService.stop(this)
                    removalWatch?.remove()
                    removalWatch = null
                    render()
                }
            }
    }

    /** Asks once for the optional location permission when paired. Location is
     *  never a setup gate — if the child allows it, the parent sees it. */
    private fun maybeRequestLocation() {
        if (locationAsked || !ChildStore.isPaired(this)) return
        val granted = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) return
        locationAsked = true
        requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION), LOCATION_REQ)
    }

    /** Rebuilds the screen: the permission gate until everything is granted,
     *  then the normal status + pairing view. */
    private fun render() {
        setContentView(buildUi())
        if (permissionsComplete()) refreshStatus()
        // Keep protection running whenever the device is paired, even mid-setup
        // (each feature no-ops until its own permission is granted).
        if (ChildStore.isPaired(this)) EnforcementService.start(this)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        // Location is optional — never push the child to settings for it.
        if (requestCode == LOCATION_REQ) {
            render()
            return
        }
        // If a permission was permanently denied, guide the user to app settings.
        for (i in permissions.indices) {
            val denied = grantResults.getOrNull(i) != PackageManager.PERMISSION_GRANTED
            if (denied && !shouldShowRequestPermissionRationale(permissions[i])) {
                openAppSettings()
                break
            }
        }
        render()
    }

    override fun onDestroy() {
        scope.cancel()
        removalWatch?.remove()
        removalWatch = null
        super.onDestroy()
    }

    // ---------------------------------------------------------------- UI build

    private fun buildUi(): ScrollView {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(cBg)
        }

        root.addView(buildHeader())

        val body = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(20), dp(20), dp(28))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f
            )
        }

        if (!permissionsComplete()) {
            // Mandatory setup gate — device can't be linked until all granted.
            body.addView(buildSetupGate())
        } else {
            body.addView(buildStatusCard())
            body.addView(gap(dp(16)))
            body.addView(buildPairingCard())
            if (ChildStore.isPaired(this)) {
                body.addView(gap(dp(12)))
                body.addView(buildTemporaryAccessButton())
            }
            // Flexible spacer pushes the unlink button to the very bottom.
            body.addView(View(this).apply {
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f
                )
            })
            body.addView(gap(dp(12)))
            body.addView(buildUnlinkButton())
        }

        root.addView(body)

        return ScrollView(this).apply {
            isFillViewport = true
            setBackgroundColor(cBg)
            addView(root)
        }
    }

    private fun buildHeader(): View {
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(20), dp(48), dp(20), dp(28))
            background = GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                intArrayOf(cPrimary, Color.parseColor("#7C3AED"))
            )
        }

        // Shield mark
        header.addView(TextView(this).apply {
            text = "\uD83D\uDEE1"
            textSize = 26f
            gravity = Gravity.CENTER
            val size = dp(52)
            background = circle(Color.parseColor("#FFFFFF")).apply { alpha = 60 }
            layoutParams = LinearLayout.LayoutParams(size, size)
            setPadding(0, dp(6), 0, 0)
        })

        header.addView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), 0, 0, 0)
            addView(TextView(this@MainActivity).apply {
                text = "Maryada"
                setTextColor(Color.WHITE)
                textSize = 22f
                typeface = Typeface.DEFAULT_BOLD
            })
            addView(TextView(this@MainActivity).apply {
                text = "Family protection"
                setTextColor(Color.parseColor("#E0E7FF"))
                textSize = 13f
            })
        })

        return header
    }

    // ------------------------------------------------------- permission gate

    private fun hasUsageAccess() = UsageReporter.hasAccess(this)

    private fun hasCallLog() =
        checkSelfPermission(Manifest.permission.READ_CALL_LOG) ==
            PackageManager.PERMISSION_GRANTED

    private fun hasSms() =
        checkSelfPermission(Manifest.permission.READ_SMS) ==
            PackageManager.PERMISSION_GRANTED

    private fun hasVpnConsent() = VpnService.prepare(this) == null

    private fun hasBatteryExemption(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun hasDeviceAdmin() = DeviceLockdown.isAdminActive(this)

    private fun hasOverlay() = Settings.canDrawOverlays(this)

    private fun hasAccessibility(): Boolean {
        val cn = android.content.ComponentName(
            this, GuardNestAccessibilityService::class.java
        ).flattenToString()
        val enabled = Settings.Secure.getString(
            contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return enabled.split(':').any { it.equals(cn, ignoreCase = true) }
    }

    private fun permissionsComplete(): Boolean = Permissions.allGranted(this)

    private fun buildSetupGate(): View {
        val col = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }

        col.addView(permissionRow(
            "\uD83D\uDCCA", "Usage access",
            "Lets your family see screen time and app usage.",
            hasUsageAccess()
        ) { grantUsage() })
        col.addView(gap(dp(10)))
        col.addView(permissionRow(
            "\uD83D\uDCDE", "Calls & messages",
            "Lets your family review recent calls and SMS messages.",
            hasCallLog() && hasSms()
        ) { grantCallsAndMessages() })
        col.addView(gap(dp(10)))
        col.addView(permissionRow(
            "\uD83D\uDD0B", "Keep protection running",
            "Allow the app to run in the background so it can’t be turned off.",
            hasBatteryExemption()
        ) { grantBattery() })
        col.addView(gap(dp(10)))
        col.addView(permissionRow(
            "\uD83D\uDEAB", "App blocking",
            "Turn on Maryada in Accessibility so blocked apps can be stopped.",
            hasAccessibility()
        ) { grantAccessibility() })
        col.addView(gap(dp(10)))
        col.addView(permissionRow(
            "\uD83D\uDD12", "Lock when paused",
            "Allow display over other apps so the device can be fully paused.",
            hasOverlay()
        ) { grantOverlay() })
        col.addView(gap(dp(10)))
        col.addView(permissionRow(
            "\uD83D\uDEE1", "Prevent removal",
            "Activate device admin so Maryada can’t be removed without a parent.",
            hasDeviceAdmin()
        ) { grantDeviceAdmin() })

        col.addView(gap(dp(16)))
        col.addView(TextView(this).apply {
            text = "Required items must be on before you can continue."
            textSize = 12f
            setTextColor(Color.parseColor("#B45309"))
            gravity = Gravity.CENTER
        })
        col.addView(gap(dp(10)))
        col.addView(filledButton("Re-check") { render() })
        return col
    }

    private fun permissionRow(
        emoji: String,
        title: String,
        desc: String,
        granted: Boolean,
        onGrant: () -> Unit,
    ): View {
        val c = card()
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        row.addView(TextView(this).apply {
            text = emoji
            textSize = 20f
            gravity = Gravity.CENTER
            val s = dp(44)
            layoutParams = LinearLayout.LayoutParams(s, s)
            background = circle(if (granted) Color.parseColor("#DCFCE7") else Color.parseColor("#EEF2FF"))
        })
        val texts = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            setPadding(dp(12), 0, dp(8), 0)
        }
        texts.addView(TextView(this).apply {
            text = title
            textSize = 15f
            setTextColor(cInk)
            typeface = Typeface.DEFAULT_BOLD
        })
        texts.addView(TextView(this).apply {
            text = desc
            textSize = 12f
            setTextColor(cMuted)
            setPadding(0, dp(2), 0, 0)
        })
        row.addView(texts)

        if (granted) {
            row.addView(TextView(this).apply {
                text = "\u2713"
                textSize = 22f
                setTextColor(cAccent)
                typeface = Typeface.DEFAULT_BOLD
            })
        } else {
            row.addView(TextView(this).apply {
                text = "Enable"
                textSize = 14f
                setTextColor(Color.WHITE)
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
                setPadding(dp(16), dp(9), dp(16), dp(9))
                background = GradientDrawable(
                    GradientDrawable.Orientation.LEFT_RIGHT,
                    intArrayOf(cPrimary, cPrimaryDark)
                ).apply { cornerRadius = dp(10).toFloat() }
                isClickable = true
                setOnClickListener { onGrant() }
            })
        }
        c.addView(row)
        return c
    }

    /** Requests call log and SMS together in a single system prompt. */
    private fun grantCallsAndMessages() {
        val needed = mutableListOf<String>()
        if (!hasCallLog()) needed.add(Manifest.permission.READ_CALL_LOG)
        if (!hasSms()) needed.add(Manifest.permission.READ_SMS)
        if (needed.isNotEmpty()) {
            requestPermissions(needed.toTypedArray(), 3)
        }
    }

    private fun grantUsage() {
        UsageReporter.openSettings(this)
        armGrantWatch { hasUsageAccess() }
    }

    private fun grantBattery() {
        try {
            startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                    .setData(Uri.parse("package:$packageName"))
            )
        } catch (_: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            } catch (_: Exception) {
            }
        }
        armGrantWatch { hasBatteryExemption() }
    }

    private fun grantAccessibility() {
        try {
            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
            armGrantWatch { hasAccessibility() }
        } catch (_: Exception) {
        }
    }

    private fun grantOverlay() {
        try {
            startActivity(
                Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION)
                    .setData(Uri.parse("package:$packageName"))
            )
            armGrantWatch { hasOverlay() }
        } catch (_: Exception) {
        }
    }

    private fun grantDeviceAdmin() {
        val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
            .putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, DeviceLockdown.admin(this))
            .putExtra(
                DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                "Activate so Maryada can’t be removed without a parent.",
            )
        try {
            startActivity(intent)
            armGrantWatch { hasDeviceAdmin() }
        } catch (_: Exception) {
        }
    }

    /**
     * Watches for a settings-based permission to be granted while its system
     * screen is open, then pulls the app back to the setup gate.
     */
    private fun armGrantWatch(check: () -> Boolean) {
        awaitingGrant = check
        uiHandler.removeCallbacks(grantPoll)
        uiHandler.postDelayed(grantPoll, 800)
    }

    private fun bringToFront() {
        try {
            startActivity(
                Intent(this, MainActivity::class.java)
                    .addFlags(
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                            Intent.FLAG_ACTIVITY_NEW_TASK
                    )
            )
        } catch (_: Exception) {
        }
    }

    private fun openAppSettings() {
        try {
            startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    .setData(Uri.parse("package:$packageName"))
            )
        } catch (_: Exception) {
        }
    }

    private fun buildStatusCard(): View {
        statusCard = card()

        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        statusBadge = TextView(this).apply {
            text = "•"
            textSize = 22f
            gravity = Gravity.CENTER
            val s = dp(48)
            layoutParams = LinearLayout.LayoutParams(s, s)
            background = circle(Color.parseColor("#EEF2FF"))
            setTextColor(cPrimary)
        }
        row.addView(statusBadge)

        val texts = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), 0, 0, 0)
        }
        statusTitle = TextView(this).apply {
            text = "Checking status…"
            textSize = 18f
            setTextColor(cInk)
            typeface = Typeface.DEFAULT_BOLD
        }
        statusSubtitle = TextView(this).apply {
            text = ""
            textSize = 13f
            setTextColor(cMuted)
            setPadding(0, dp(2), 0, 0)
        }
        texts.addView(statusTitle)
        texts.addView(statusSubtitle)
        row.addView(texts)

        statusCard.addView(row)
        return statusCard
    }

    private fun buildPairingCard(): View {
        pairingCard = card()

        pairingCard.addView(TextView(this).apply {
            text = "Link this device"
            textSize = 16f
            setTextColor(cInk)
            typeface = Typeface.DEFAULT_BOLD
        })
        pairingCard.addView(TextView(this).apply {
            text = "Enter the pairing code from the parent app."
            textSize = 13f
            setTextColor(cMuted)
            setPadding(0, dp(4), 0, dp(14))
        })

        codeInput = EditText(this).apply {
            // Smaller hint so "Enter pairing code" fits the box, while the typed
            // code still shows large.
            hint = android.text.SpannableString("Enter pairing code").apply {
                setSpan(
                    android.text.style.RelativeSizeSpan(0.8f),
                    0, length,
                    android.text.Spanned.SPAN_INCLUSIVE_INCLUSIVE
                )
            }
            setHintTextColor(Color.parseColor("#94A3B8"))
            setTextColor(cInk)
            textSize = 22f
            gravity = Gravity.CENTER
            letterSpacing = 0.2f
            typeface = Typeface.MONOSPACE
            inputType = InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS or
                InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
            filters = arrayOf(
                android.text.InputFilter.LengthFilter(6),
                android.text.InputFilter.AllCaps(),
            )
            setPadding(dp(16), dp(18), dp(16), dp(18))
            background = rounded(Color.parseColor("#F8FAFC"), dp(12), cBorder, dp(1))
        }
        pairingCard.addView(codeInput)
        pairingCard.addView(gap(dp(12)))
        pairingCard.addView(buildLinkButton())

        return pairingCard
    }

    /** The “Link device” button, which shows an inline spinner while pairing. */
    private fun buildLinkButton(): View {
        linking = false
        val progress = ProgressBar(this, null, android.R.attr.progressBarStyleSmall).apply {
            val s = dp(20)
            layoutParams = LinearLayout.LayoutParams(s, s).apply { marginEnd = dp(10) }
            indeterminateTintList = ColorStateList.valueOf(Color.WHITE)
            visibility = View.GONE
        }
        val label = TextView(this).apply {
            text = "Link device"
            textSize = 16f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
        }
        val button = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(dp(16), dp(15), dp(16), dp(15))
            background = GradientDrawable(
                GradientDrawable.Orientation.LEFT_RIGHT,
                intArrayOf(cPrimary, cPrimaryDark)
            ).apply { cornerRadius = dp(14).toFloat() }
            isClickable = true
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
            addView(progress)
            addView(label)
            setOnClickListener { linkDevice() }
        }
        linkButton = button
        linkLabel = label
        linkProgress = progress
        return button
    }

    /** Greys out the Link button and shows/hides its inline spinner. */
    private fun setLinking(loading: Boolean) {
        linking = loading
        linkButton.isEnabled = !loading
        linkButton.isClickable = !loading
        linkButton.alpha = if (loading) 0.6f else 1f
        linkProgress.visibility = if (loading) View.VISIBLE else View.GONE
        linkLabel.text = if (loading) "Linking\u2026" else "Link device"
    }

    /**
     * A prominent "Temporary Access" button. Turns off ONLY the accessibility
     * permission so a strict banking app can run; the lockbox then keeps every
     * other app locked until the child turns Accessibility back on.
     */
    private fun buildTemporaryAccessButton(): View {
        val col = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val btn = TextView(this).apply {
            text = "Request Temporary Access"
            textSize = 16f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(dp(16), dp(15), dp(16), dp(15))
            background = GradientDrawable(
                GradientDrawable.Orientation.LEFT_RIGHT,
                intArrayOf(Color.parseColor("#F59E0B"), Color.parseColor("#D97706"))
            ).apply { cornerRadius = dp(14).toFloat() }
            isClickable = true
            setOnClickListener { onTemporaryAccess() }
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }
        tempAccessBtn = btn
        col.addView(btn)
        col.addView(TextView(this).apply {
            text = "Use a banking app for a while. All other apps stay locked " +
                "until protection is turned back on."
            textSize = 12f
            setTextColor(cMuted)
            gravity = Gravity.CENTER
            setPadding(dp(8), dp(8), dp(8), 0)
        })
        return col
    }

    /**
     * Confirms, then turns off the accessibility service. The device drops into
     * banking mode (lockbox) — only the parent's allow-list stays usable.
     */
    private fun onTemporaryAccess() {
        android.app.AlertDialog.Builder(
            this, android.R.style.Theme_DeviceDefault_Light_Dialog_Alert
        )
            .setTitle("Turn off monitoring?")
            .setMessage(
                "Temporary Access turns off app monitoring so you can use a " +
                    "banking app.\n\nEvery other app will be locked until you " +
                    "turn Maryada’s Accessibility back on in Settings.\n\n" +
                    "Are you sure you want to continue?"
            )
            .setCancelable(false)
            .setPositiveButton("Yes, turn off") { _, _ ->
                // Prevent a second tap.
                tempAccessBtn?.apply {
                    isClickable = false
                    isEnabled = false
                    alpha = 0.6f
                    text = "Temporary access on…"
                }
                // Turn off accessibility in the background.
                if (!AccessibilityController.disable()) {
                    // Fallback: open the accessibility screen to toggle it off.
                    try {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    } catch (_: Exception) {
                    }
                }
                // Take the child to the permission screen once the change
                // propagates (accessibility now shows as missing).
                uiHandler.postDelayed({ render() }, 500)
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    /**
     * The "Unlink this device" button. Unlinking is only allowed once the parent
     * has removed this device from their family — otherwise it stays protected.
     */
    private fun buildUnlinkButton(): View {
        unlinking = false
        val btn = TextView(this).apply {
            text = "Unlink this device"
            textSize = 14f
            setTextColor(cDanger)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(dp(16), dp(14), dp(16), dp(14))
            background = rounded(Color.parseColor("#FEF2F2"), dp(12), cDanger, dp(1))
            isClickable = true
            setOnClickListener { unlinkIfRemoved() }
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
            visibility = if (ChildStore.isPaired(this@MainActivity)) View.VISIBLE else View.GONE
        }
        unlinkButton = btn
        return btn
    }

    /**
     * Checks with the server whether this device was removed from the family.
     * Only if it was removed do we clear the local pairing and release device
     * admin so the child can unlink / uninstall; otherwise it stays protected.
     */
    private fun unlinkIfRemoved() {
        if (unlinking) return
        val fid = ChildStore.familyId(this)
        val cid = ChildStore.childId(this)
        if (fid == null || cid == null) {
            render()
            return
        }
        unlinking = true
        unlinkButton.isEnabled = false
        unlinkButton.alpha = 0.6f
        unlinkButton.text = "Checking\u2026"
        FirebaseFirestore.getInstance()
            .collection("families").document(fid)
            .collection("children").document(cid)
            .get()
            .addOnSuccessListener { doc ->
                unlinking = false
                if (!doc.exists()) {
                    performLocalUnlink()
                } else {
                    unlinkButton.isEnabled = true
                    unlinkButton.alpha = 1f
                    unlinkButton.text = "Unlink this device"
                    toast("This device is still linked. Ask your parent to remove it from their family first.")
                }
            }
            .addOnFailureListener {
                // A denied read usually means the record is gone — allow unlink.
                unlinking = false
                performLocalUnlink()
            }
    }

    private fun performLocalUnlink() {
        ChildStore.clear(this)
        DeviceLockdown.releaseForRemoval(this)
        WebFilterVpnService.stop(this)
        try {
            stopService(Intent(this, EnforcementService::class.java))
        } catch (_: Exception) {
        }
        removalWatch?.remove()
        removalWatch = null
        toast("Device unlinked. You can uninstall the app now.")
        render()
    }

    // ------------------------------------------------------------- state logic

    private fun refreshStatus() {
        val owner = DeviceLockdown.isDeviceOwner(this)
        val paired = ChildStore.isPaired(this)

        when {
            paired && owner -> setStatus(
                "\u2713", cAccent, Color.parseColor("#DCFCE7"),
                "Protected", "This device is linked and safeguarded."
            )
            paired -> setStatus(
                "\u2713", cPrimary, Color.parseColor("#EEF2FF"),
                "Linked", "Connected to your family. Protection pending setup."
            )
            else -> setStatus(
                "!", Color.parseColor("#F59E0B"), Color.parseColor("#FEF3C7"),
                "Not linked yet", "Enter a pairing code below to get started."
            )
        }

        // Hide the pairing card once linked.
        pairingCard.visibility = if (paired) View.GONE else View.VISIBLE
        // The unlink option only shows while linked.
        if (::unlinkButton.isInitialized) {
            unlinkButton.visibility = if (paired) View.VISIBLE else View.GONE
        }
    }

    private fun setStatus(badge: String, tint: Int, bg: Int, title: String, sub: String) {
        statusBadge.text = badge
        statusBadge.setTextColor(tint)
        statusBadge.background = circle(bg)
        statusTitle.text = title
        statusSubtitle.text = sub
    }

    /**
     * Grants the one-time VPN consent needed for web filtering. After this, the
     * guardian turns filtering on/off from the parent app and the enforcement
     * service starts/stops the filter automatically.
     */
    private fun startWebFilter() {
        val consent = VpnService.prepare(this)
        if (consent != null) {
            startActivityForResult(consent, REQ_VPN)
        } else {
            onVpnConsented()
        }
    }

    private fun onVpnConsented() {
        // Nudge the enforcement service to (re)evaluate the parent's web-filter
        // rule now that permission exists.
        EnforcementService.start(this)
        render()
    }

    @Deprecated("Simple VPN consent callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_VPN && resultCode == Activity.RESULT_OK) {
            onVpnConsented()
        }
    }

    private fun linkDevice() {
        if (linking) return
        val code = codeInput.text?.toString()?.trim().orEmpty()
        if (code.isEmpty()) {
            toast("Enter the pairing code first.")
            return
        }
        setLinking(true)
        scope.launch {
            try {
                val msg = Pairing.redeem(this@MainActivity, code)
                toast(msg)
                codeInput.setText("")
                EnforcementService.start(this@MainActivity)
                refreshStatus()
                attachRemovalWatch()
            } catch (e: Exception) {
                toast(e.message ?: "Couldn't link device.")
                setLinking(false)
            }
        }
    }

    // -------------------------------------------------------------- UI helpers

    private fun card(): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(18), dp(18), dp(18), dp(18))
        background = rounded(cCard, dp(18), cBorder, dp(1))
        elevation = dp(1).toFloat()
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        )
    }

    private fun filledButton(label: String, onClick: () -> Unit): TextView =
        TextView(this).apply {
            text = label
            textSize = 16f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(dp(16), dp(15), dp(16), dp(15))
            background = GradientDrawable(
                GradientDrawable.Orientation.LEFT_RIGHT,
                intArrayOf(cPrimary, cPrimaryDark)
            ).apply { cornerRadius = dp(14).toFloat() }
            isClickable = true
            setOnClickListener { onClick() }
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }

    private fun rounded(fill: Int, radius: Int, stroke: Int, strokeW: Int): GradientDrawable =
        GradientDrawable().apply {
            setColor(fill)
            cornerRadius = radius.toFloat()
            setStroke(strokeW, stroke)
        }

    private fun circle(fill: Int): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(fill)
        }

    private fun gap(h: Int): View = View(this).apply {
        layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, h)
    }

    private fun toast(msg: String) {
        Toast.makeText(this, msg, Toast.LENGTH_LONG).show()
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    private companion object {
        const val REQ_VPN = 0x7A
        const val LOCATION_REQ = 7
    }
}
