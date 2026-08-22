package com.guardnest.kid

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

/**
 * A full-screen lock screen shown while the device is paused or in bedtime, and
 * over any app the parent has blocked. It covers everything and swallows
 * touches, so the child can't use the app underneath — only the "Go home"
 * button leads anywhere.
 *
 * Deliberately a native copy of the browser's block page
 * ([assets/blocked.html]): the child meets the same screen whether a website or
 * an app is blocked. It's rebuilt in views rather than a WebView so it appears
 * instantly, with no blank frame while a page loads.
 *
 * Uses a system overlay window (needs the "Display over other apps" permission).
 */
object LockOverlay {

    private var view: View? = null
    private var currentKey: String? = null
    private var shownAt = 0L

    /// Set when the child taps "Go home": the watchers are still reporting the
    /// blocked app as foreground for a moment, and without this they put the
    /// screen straight back up before the launcher appears.
    private var suppressUntil = 0L

    /** Two watchers (accessibility events and the UsageStats poller) both drive
     *  this overlay and briefly disagree around app switches; ignoring a
     *  non-forced hide right after a show is what stops the visible flicker. */
    private const val HIDE_DEBOUNCE_MS = 1_200L

    fun isShowing(): Boolean = view != null

    fun canShow(ctx: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(ctx)

    /** [detail] is the small line under the message — the blocked app's name,
     *  mirroring the host shown on the website block page. */
    fun show(
        ctx: Context,
        title: String,
        subtitle: String,
        detail: String = "",
        emergency: Boolean = false,
    ) {
        if (!canShow(ctx)) return
        if (System.currentTimeMillis() < suppressUntil) return
        val key = "$title\u0000$subtitle\u0000$detail"
        if (view != null) {
            // Same lock screen already up — keep it. If the message changed
            // (e.g. pause → bedtime, or a different blocked app), rebuild it.
            if (currentKey == key) return
            hide(ctx, force = true)
        }
        val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_INSET_DECOR or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED,
            PixelFormat.OPAQUE,
        )
        params.gravity = Gravity.CENTER

        val v = buildView(ctx, title, subtitle, detail)
        // Swallow all touches so nothing beneath can be interacted with.
        v.setOnTouchListener { _, _ -> true }
        try {
            wm.addView(v, params)
            view = v
            currentKey = key
            // Stamped on the real show only: refreshing it on every repeat call
            // kept the debounce permanently open, so a genuine hide (child back
            // on the home screen) could never get through.
            shownAt = System.currentTimeMillis()
        } catch (_: Exception) {
        }
    }

    /** [force] bypasses the debounce — for real unlock events (parent lifted
     *  the rule, unpair, teardown) rather than foreground-signal noise. */
    fun hide(ctx: Context, force: Boolean = false) {
        val v = view ?: return
        if (!force && System.currentTimeMillis() - shownAt < HIDE_DEBOUNCE_MS) return
        val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        try {
            wm.removeView(v)
        } catch (_: Exception) {
        }
        view = null
        currentKey = null
    }

    private fun buildView(
        ctx: Context,
        title: String,
        subtitle: String,
        detail: String,
    ): View {
        val density = ctx.resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()

        val root = FrameLayout(ctx).apply {
            background = GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                intArrayOf(
                    Color.parseColor("#4338CA"),
                    Color.parseColor("#6D28D9"),
                    Color.parseColor("#7C3AED"),
                )
            )
            isClickable = true
            isFocusable = true
        }

        val content = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(26), dp(40), dp(26), dp(96))
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ).apply { gravity = Gravity.CENTER }
        }

        content.addView(TextView(ctx).apply {
            text = "\uD83D\uDEE1\uFE0F"
            textSize = 56f
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(40).toFloat()
                setColor(Color.argb(36, 255, 255, 255))
            }
            layoutParams = LinearLayout.LayoutParams(dp(132), dp(132)).apply {
                bottomMargin = dp(30)
            }
        })
        content.addView(TextView(ctx).apply {
            text = title
            setTextColor(Color.WHITE)
            textSize = 27f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
        })
        content.addView(TextView(ctx).apply {
            text = subtitle
            setTextColor(Color.parseColor("#E9E7FD"))
            textSize = 17f
            gravity = Gravity.CENTER
            setLineSpacing(0f, 1.35f)
            setPadding(0, dp(14), 0, 0)
        })
        if (detail.isNotBlank()) {
            content.addView(TextView(ctx).apply {
                text = detail
                setTextColor(Color.parseColor("#CBBEF9"))
                textSize = 13f
                gravity = Gravity.CENTER
                setPadding(0, dp(10), 0, 0)
            })
        }
        content.addView(TextView(ctx).apply {
            text = "Go home"
            setTextColor(Color.parseColor("#4C1D95"))
            textSize = 17f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(16).toFloat()
                setColor(Color.WHITE)
            }
            setPadding(dp(46), dp(16), dp(46), dp(16))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(34) }
            // The overlay swallows touches, so the button needs its own listener
            // ahead of that — set on the child, which is hit first.
            setOnClickListener { goHome(ctx) }
        })

        root.addView(content)
        root.addView(TextView(ctx).apply {
            text = "An Initiative by ISKCON Brahmapur"
            setTextColor(Color.parseColor("#CBBEF9"))
            textSize = 12f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
                bottomMargin = dp(22)
            }
        })
        return root
    }

    /** The home screen is the one place the lock screen lets the child go. */
    private fun goHome(ctx: Context) {
        // Drop the screen first: waiting for a watcher to notice the launcher
        // left it sitting over the home screen for up to a second after the tap.
        suppressUntil = System.currentTimeMillis() + GO_HOME_GRACE_MS
        hide(ctx, force = true)
        try {
            ctx.startActivity(
                Intent(Intent.ACTION_MAIN)
                    .addCategory(Intent.CATEGORY_HOME)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        } catch (_: Exception) {
        }
    }

    private const val GO_HOME_GRACE_MS = 1_500L

    // Shared by the two watchers that raise this screen: the text is part of the
    // overlay's identity, so a difference between them would rebuild it (and
    // flicker) on every hand-off.
    const val APP_BLOCKED_TITLE = "App Blocked"
    const val APP_BLOCKED_MESSAGE = "Hare Krishna, this app is blocked by your parent."
}
