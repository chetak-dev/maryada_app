package com.guardnest.kid

import android.Manifest
import android.app.Activity
import android.app.Dialog
import android.app.admin.DevicePolicyManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
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
import android.view.WindowInsets
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
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

    // Colors — "Royal & Warm" palette (mirrors the parent app). Follows the
    // in-app light/dark choice, falling back to the device's system setting.
    private val isDark: Boolean by lazy {
        when (ChildStore.themeMode(this)) {
            "dark" -> true
            "light" -> false
            else -> (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                Configuration.UI_MODE_NIGHT_YES
        }
    }

    /** Picks a light- or dark-mode colour. */
    private fun dk(light: String, dark: String): Int =
        Color.parseColor(if (isDark) dark else light)

    private val cPrimary by lazy { dk("#4338CA", "#818CF8") }
    private val cPrimaryDark by lazy { dk("#312E81", "#4338CA") }
    private val cAccent by lazy { dk("#16A34A", "#22C55E") }
    private val cBg by lazy { dk("#FBF9F6", "#141220") }
    private val cCard by lazy { dk("#FFFFFF", "#1E1B2E") }
    private val cInk by lazy { dk("#1C1917", "#F5F3F0") }
    private val cMuted by lazy { dk("#78716C", "#A8A29E") }
    private val cBorder by lazy { dk("#EAE6DF", "#383152") }
    private val cDanger by lazy { dk("#DC2626", "#F87171") }

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
    private var unlinking = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.decorView.setBackgroundColor(cBg)
        // The setup notice is silently dropped without this on Android 13+,
        // and Device Owner (which would pin it on) isn't set up yet.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 4)
        }
        render()
    }

    override fun onResume() {
        super.onResume()
        // Back in the app — stop any pending grant-return poll.
        awaitingGrant = null
        uiHandler.removeCallbacks(grantPoll)
        // Re-check after returning from any system settings/consent screen.
        render()
        // Clears the banking-mode notice the moment the last permission is back.
        TempAccessNotice.sync(this)
        // Posts (or clears) the "setup isn't finished" reminder.
        SetupNotice.sync(this)
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
                } else if (snap != null && snap.exists()) {
                    // Keep the family name fresh from this device's own child doc
                    // (the parent stamps it there — the child can't read the
                    // family root doc directly).
                    val name = snap.getString("familyName")?.trim()
                    if (!name.isNullOrEmpty() && name != ChildStore.familyName(this)) {
                        ChildStore.setFamilyName(this, name)
                        if (permissionsComplete()) refreshStatus()
                    }
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

    /** Header and footer stay put; only the cards between them scroll. */
    private fun buildUi(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(cBg)
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }

        root.addView(buildHeader())

        val body = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(16), dp(18), dp(16))
        }

        if (!permissionsComplete()) {
            // Mandatory setup gate — device can't be linked until all granted.
            body.addView(buildSetupGate())
        } else {
            body.addView(buildStatusCard())
            if (ChildStore.isPaired(this)) {
                buildUsageCard()?.let {
                    body.addView(gap(dp(14)))
                    body.addView(it)
                }
            }
            body.addView(gap(dp(14)))
            body.addView(buildPairingCard())
        }

        val scroller = ScrollView(this).apply {
            isFillViewport = true
            setBackgroundColor(cBg)
            clipToPadding = false
            addView(
                body,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                ),
            )
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f
            )
        }
        root.addView(scroller)
        root.addView(buildVersionFooter())

        return root
    }

    /** The installed app version, e.g. "v1.0.0(0)". */
    private fun versionLabel(): String = AppUpdater.versionLabel(this)

    /** Credit line pinned at the very bottom of the screen. */
    private fun buildVersionFooter(): View {
        return TextView(this).apply {
            text = "Made with \u2764\uFE0F by ISKCON Brahmapur"
            textSize = 12f
            setTextColor(cMuted)
            gravity = Gravity.CENTER
            typeface = Typeface.DEFAULT_BOLD
            setBackgroundColor(cBg)
            setPadding(dp(16), dp(8), dp(16), dp(12))
            // Sits above the gesture bar rather than behind it.
            setOnApplyWindowInsetsListener { v, insets ->
                val bottom = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    insets.getInsets(WindowInsets.Type.systemBars()).bottom
                } else {
                    @Suppress("DEPRECATION") insets.systemWindowInsetBottom
                }
                v.setPadding(dp(16), dp(8), dp(16), bottom + dp(10))
                insets
            }
            requestApplyInsets()
        }
    }

    private fun buildHeader(): View {
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            // targetSdk 35 draws under the status bar, so the top padding is
            // whatever the system actually reserves — not a guessed constant.
            setPadding(dp(20), dp(44), dp(20), dp(18))
            background = GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                intArrayOf(cPrimary, Color.parseColor("#7C3AED"))
            ).apply {
                val r = dp(26).toFloat()
                cornerRadii = floatArrayOf(0f, 0f, 0f, 0f, r, r, r, r)
            }
            elevation = dp(8).toFloat()
            setOnApplyWindowInsetsListener { v, insets ->
                val top = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    insets.getInsets(WindowInsets.Type.systemBars()).top
                } else {
                    @Suppress("DEPRECATION") insets.systemWindowInsetTop
                }
                v.setPadding(dp(20), top + dp(12), dp(20), dp(18))
                insets
            }
            requestApplyInsets()
        }

        // Brand mark — the transparent artwork as-is, no backing card.
        header.addView(ImageView(this).apply {
            setImageResource(R.drawable.maryada_logo)
            scaleType = ImageView.ScaleType.FIT_CENTER
            val size = dp(48)
            layoutParams = LinearLayout.LayoutParams(size, size)
        })

        header.addView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), 0, 0, 0)
            layoutParams = LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f
            )
            addView(TextView(this@MainActivity).apply {
                text = "Maryada"
                setTextColor(Color.WHITE)
                textSize = 21f
                typeface = Typeface.DEFAULT_BOLD
            })
            addView(TextView(this@MainActivity).apply {
                text = versionLabel()
                setTextColor(Color.parseColor("#E0E7FF"))
                textSize = 12f
            })
        })

        // Light/dark toggle — always available at the front.
        header.addView(TextView(this).apply {
            text = if (isDark) "\u2600\uFE0F" else "\uD83C\uDF19" // sun / moon
            textSize = 20f
            gravity = Gravity.CENTER
            val size = dp(44)
            background = rounded(Color.parseColor("#FFFFFF"), dp(14), Color.TRANSPARENT, 0)
                .apply { alpha = 60 }
            layoutParams = LinearLayout.LayoutParams(size, size)
            isClickable = true
            setOnClickListener {
                ChildStore.setThemeMode(
                    this@MainActivity, if (isDark) "light" else "dark"
                )
                recreate()
            }
        })

        // Everything the child rarely needs (uninstall) hides behind this.
        header.addView(TextView(this).apply {
            text = "\u22EE"
            textSize = 20f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            val size = dp(36)
            layoutParams = LinearLayout.LayoutParams(size, size).apply {
                leftMargin = dp(4)
            }
            isClickable = true
            setOnClickListener { showMoreMenu() }
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

    private fun hasNotificationAccess() = Permissions.hasNotificationAccess(this)

    private fun permissionsComplete(): Boolean = Permissions.allGranted(this)

    private fun buildSetupGate(): View {
        val col = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }

        col.addView(permissionRow(
            "\uD83D\uDCCA", "Usage access",
            hasUsageAccess()
        ) { grantUsage() })
        col.addView(gap(dp(10)))
        col.addView(permissionRow(
            "\uD83D\uDCDE", "Calls & messages",
            hasCallLog() && hasSms()
        ) { grantCallsAndMessages() })
        col.addView(gap(dp(10)))
        col.addView(permissionRow(
            "\uD83D\uDD0B", "Keep protection running",
            hasBatteryExemption()
        ) { grantBattery() })
        col.addView(gap(dp(10)))
        col.addView(permissionRow(
            "\uD83D\uDEAB", "App blocking",
            hasAccessibility()
        ) { grantAccessibility() })
        col.addView(gap(dp(10)))
        col.addView(permissionRow(
            "\uD83D\uDD12", "Lock when paused",
            hasOverlay()
        ) { grantOverlay() })
        col.addView(gap(dp(10)))
        col.addView(permissionRow(
            "\uD83D\uDEE1", "Prevent removal",
            hasDeviceAdmin()
        ) { grantDeviceAdmin() })
        col.addView(gap(dp(10)))
        col.addView(permissionRow(
            "\uD83D\uDD14", "Notification access",
            hasNotificationAccess()
        ) { grantNotificationAccess() })

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
            background = circle(if (granted) dk("#DCFCE7", "#173a25") else dk("#ECEBFB", "#2A2540"))
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
        row.addView(texts)

        if (granted) {
            row.addView(TextView(this).apply {
                text = "\u2713"
                textSize = 20f
                setTextColor(cAccent)
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
                val s = dp(32)
                background = circle(dk("#DCFCE7", "#173a25"))
                layoutParams = LinearLayout.LayoutParams(s, s)
            })
        } else {
            row.addView(tonalButton("Enable") { onGrant() })
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

    /** Opens the Notification access screen so the child can enable the YouTube
     *  media-session capture. Deep-links straight to our app on Android 11+. */
    private fun grantNotificationAccess() {
        val comp = android.content.ComponentName(
            this, GuardNestNotificationListener::class.java
        )
        try {
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
                    .putExtra(
                        Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
                        comp.flattenToString(),
                    )
            } else {
                Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            }
            startActivity(intent)
            armGrantWatch { hasNotificationAccess() }
        } catch (_: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                armGrantWatch { hasNotificationAccess() }
            } catch (_: Exception) {
            }
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
            textSize = 24f
            gravity = Gravity.CENTER
            val s = dp(56)
            layoutParams = LinearLayout.LayoutParams(s, s)
            background = circle(dk("#ECEBFB", "#2A2540"))
            setTextColor(cPrimary)
        }
        row.addView(statusBadge)

        val texts = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), 0, 0, 0)
        }
        statusTitle = TextView(this).apply {
            text = "Checking status…"
            textSize = 20f
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

    /**
     * Today's screen time for this device: a big total plus a short list of the
     * most-used apps with a proportional bar. Returns null when usage access
     * isn't granted or there's nothing to show yet.
     */
    private fun buildUsageCard(): View? {
        val (total, apps) = UsageReporter.today(this) ?: return null
        if (apps.isEmpty()) return null

        val c = card()
        c.addView(TextView(this).apply {
            text = "Screen time today"
            textSize = 16f
            setTextColor(cInk)
            typeface = Typeface.DEFAULT_BOLD
        })
        c.addView(TextView(this).apply {
            text = fmtDuration(total)
            textSize = 26f
            setTextColor(cPrimary)
            typeface = Typeface.DEFAULT_BOLD
            setPadding(0, dp(2), 0, dp(12))
        })

        val maxMin = (apps.maxOfOrNull { it.minutes } ?: 1).coerceAtLeast(1)
        for (app in apps) c.addView(buildUsageRow(app.label, app.minutes, maxMin))
        return c
    }

    /** One app row: name, its time, and a proportional progress bar. */
    private fun buildUsageRow(label: String, minutes: Int, maxMin: Int): View {
        val wrap = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, dp(7), 0, dp(7))
        }

        val top = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        top.addView(TextView(this).apply {
            text = label
            textSize = 14f
            setTextColor(cInk)
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        })
        top.addView(TextView(this).apply {
            text = fmtDuration(minutes)
            textSize = 13f
            setTextColor(cMuted)
            typeface = Typeface.DEFAULT_BOLD
            setPadding(dp(8), 0, 0, 0)
        })
        wrap.addView(top)

        val filled = minutes.coerceAtLeast(0)
        val rest = (maxMin - filled).coerceAtLeast(0)
        val bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            background = rounded(dk("#ECEBFB", "#2A2540"), dp(4), Color.TRANSPARENT, 0)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(6)
            ).apply { topMargin = dp(6) }
        }
        bar.addView(View(this).apply {
            background = rounded(cPrimary, dp(4), Color.TRANSPARENT, 0)
            layoutParams = LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.MATCH_PARENT,
                filled.toFloat().coerceAtLeast(0.001f)
            )
        })
        if (rest > 0) bar.addView(View(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.MATCH_PARENT, rest.toFloat()
            )
        })
        wrap.addView(bar)
        return wrap
    }

    /** "45m", "1h", "2h 15m". */
    private fun fmtDuration(minutes: Int): String {
        if (minutes < 60) return "${minutes}m"
        val h = minutes / 60
        val m = minutes % 60
        return if (m == 0) "${h}h" else "${h}h ${m}m"
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
            setHintTextColor(Color.parseColor("#A8A29E"))
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
            background = rounded(dk("#FAF8F4", "#2A2540"), dp(12), cBorder, dp(1))
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
     * Confirms, then turns off the accessibility service — the one protection
     * banking apps refuse to run alongside — while keeping device admin so the
     * app still can't be uninstalled. The device drops into banking mode
     * (lockbox): only the parent's allow-list stays usable. Turning
     * accessibility back on restores everything.
     */
    private fun onTemporaryAccess() {
        android.app.AlertDialog.Builder(
            this, android.R.style.Theme_DeviceDefault_Light_Dialog_Alert
        )
            .setTitle("Turn off monitoring?")
            .setMessage(
                "Temporary Access turns off Maryada’s accessibility service so " +
                    "a banking app will run.\n\nYour device stays locked to your " +
                    "parent’s allowed apps, and Maryada still can’t be " +
                    "uninstalled.\n\nTo restore full protection, turn Maryada’s " +
                    "Accessibility back on in Settings.\n\nAre you sure you want " +
                    "to continue?"
            )
            .setCancelable(false)
            .setPositiveButton("Yes, turn off") { _, _ ->
                // Remember this was intentional so the enforcement service can
                // restore protection once it returns.
                ChildStore.setTempAccess(this, true)
                TempAccessNotice.begin(this)
                // Accessibility is the only thing banking apps object to, so it
                // is the only protection this turns off — notification access
                // and call/SMS access stay exactly as the child granted them.
                WebFilterVpnService.stop(this)
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
     * The tucked-away options: Temporary Access (banking) and uninstalling —
     * neither belongs on the front screen.
     */
    private fun showMoreMenu() {
        if (!ChildStore.isPaired(this)) {
            toast("This device isn’t linked yet.")
            return
        }
        val dialog = Dialog(this)
        val sheet = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), dp(10), dp(12), dp(20))
            background = GradientDrawable().apply {
                setColor(cCard)
                val r = dp(26).toFloat()
                cornerRadii = floatArrayOf(r, r, r, r, 0f, 0f, 0f, 0f)
            }
        }
        // Drag handle, so the sheet reads as a sheet.
        sheet.addView(View(this).apply {
            background = rounded(cMuted, dp(3), Color.TRANSPARENT, 0)
            alpha = 0.35f
            layoutParams = LinearLayout.LayoutParams(dp(38), dp(4)).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                topMargin = dp(2)
                bottomMargin = dp(14)
            }
        })
        sheet.addView(
            sheetRow("\uD83C\uDFE6", "Request Temporary Access",
                "Turn monitoring off for a banking app") {
                dialog.dismiss()
                onTemporaryAccess()
            }
        )
        sheet.addView(
            sheetRow("\uD83D\uDDD1\uFE0F", "Uninstall this app",
                "Only after a parent removes this device") {
                dialog.dismiss()
                confirmUninstall()
            }
        )
        dialog.setContentView(sheet)
        dialog.window?.apply {
            setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            setLayout(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )
            setGravity(Gravity.BOTTOM)
        }
        dialog.show()
    }

    /** One tappable line of the bottom sheet. */
    private fun sheetRow(
        emoji: String,
        title: String,
        subtitle: String,
        onTap: () -> Unit,
    ): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(14), dp(14), dp(14), dp(14))
            background = ripple(
                rounded(Color.TRANSPARENT, dp(18), Color.TRANSPARENT, 0),
                0x22000000,
            )
            isClickable = true
            setOnClickListener { onTap() }
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )
        }
        row.addView(TextView(this).apply {
            text = emoji
            textSize = 19f
            gravity = Gravity.CENTER
            val s = dp(44)
            background = circle(dk("#ECEBFB", "#2A2540"))
            layoutParams = LinearLayout.LayoutParams(s, s)
        })
        row.addView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), 0, 0, 0)
            layoutParams = LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f
            )
            addView(TextView(this@MainActivity).apply {
                text = title
                textSize = 15f
                setTextColor(cInk)
                typeface = Typeface.DEFAULT_BOLD
            })
            addView(TextView(this@MainActivity).apply {
                text = subtitle
                textSize = 12f
                setTextColor(cMuted)
                setPadding(0, dp(2), 0, 0)
            })
        })
        return row
    }

    private fun confirmUninstall() {
        android.app.AlertDialog.Builder(
            this, android.R.style.Theme_DeviceDefault_Light_Dialog_Alert
        )
            .setTitle("Uninstall this app?")
            .setMessage(
                "Maryada can only be removed after your parent removes this " +
                    "device from the family. Tap Check to see whether that has " +
                    "been done."
            )
            .setPositiveButton("Check") { _, _ -> unlinkIfRemoved() }
            .setNegativeButton("Cancel", null)
            .show()
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
        toast("Checking…")
        FirebaseFirestore.getInstance()
            .collection("families").document(fid)
            .collection("children").document(cid)
            .get()
            .addOnSuccessListener { doc ->
                unlinking = false
                if (!doc.exists()) {
                    performLocalUnlink()
                } else {
                    toast("Hare Krishna, Kindly contact your Admin for this. Thanks")
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
        toast("Device disconnected. You can uninstall the app now.")
        render()
    }

    // ------------------------------------------------------------- state logic

    private fun refreshStatus() {
        val owner = DeviceLockdown.isDeviceOwner(this)
        val paired = ChildStore.isPaired(this)
        // The family's name adds nothing here and only dates the screen when a
        // parent renames it.
        val familyLine = "Connected to your family."

        when {
            paired && owner -> setStatus(
                "\u2713", cAccent, dk("#DCFCE7", "#173a25"),
                "Protected", familyLine
            )
            paired -> setStatus(
                "\u2713", cPrimary, dk("#ECEBFB", "#2A2540"),
                "Connected", familyLine
            )
            else -> setStatus(
                "!", Color.parseColor("#F59E0B"), dk("#FEF3C7", "#3a2f14"),
                "Not connected yet", "Enter a pairing code below to get started."
            )
        }

        // Hide the pairing card once linked.
        pairingCard.visibility = if (paired) View.GONE else View.VISIBLE
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
        background = rounded(cCard, dp(20), Color.TRANSPARENT, 0)
        elevation = dp(3).toFloat()
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        )
    }

    /** Material-style touch feedback over any shape. */
    private fun ripple(content: Drawable, tint: Int = 0x40FFFFFF): Drawable =
        RippleDrawable(ColorStateList.valueOf(tint), content, null)

    /** A filled, pill-shaped primary button with ripple feedback. */
    private fun filledButton(label: String, onClick: () -> Unit): TextView =
        TextView(this).apply {
            text = label
            textSize = 15f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            letterSpacing = 0.02f
            gravity = Gravity.CENTER
            setPadding(dp(20), dp(15), dp(20), dp(15))
            background = ripple(
                GradientDrawable(
                    GradientDrawable.Orientation.LEFT_RIGHT,
                    intArrayOf(cPrimary, cPrimaryDark)
                ).apply { cornerRadius = dp(100).toFloat() }
            )
            elevation = dp(2).toFloat()
            isClickable = true
            setOnClickListener { onClick() }
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }

    /** A compact tonal button — quiet next to the filled one. */
    private fun tonalButton(label: String, onClick: () -> Unit): TextView =
        TextView(this).apply {
            text = label
            textSize = 14f
            setTextColor(if (isDark) Color.WHITE else cPrimaryDark)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(dp(18), dp(10), dp(18), dp(10))
            background = ripple(
                rounded(dk("#ECEBFB", "#2A2540"), dp(100), Color.TRANSPARENT, 0),
                0x33000000,
            )
            isClickable = true
            setOnClickListener { onClick() }
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
