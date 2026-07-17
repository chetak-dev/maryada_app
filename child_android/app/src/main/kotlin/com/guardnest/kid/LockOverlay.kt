package com.guardnest.kid

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView

/**
 * A full-screen lock overlay shown while the device is paused or in bedtime.
 * It covers everything and swallows touches, so the child can't use the phone —
 * they only see a "Paused" message until the parent lifts the restriction.
 *
 * Uses a system overlay window (needs the "Display over other apps" permission).
 */
object LockOverlay {

    private var view: View? = null

    fun isShowing(): Boolean = view != null

    fun canShow(ctx: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(ctx)

    fun show(ctx: Context, title: String, subtitle: String) {
        if (view != null) return
        if (!canShow(ctx)) return
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

        val v = buildView(ctx, title, subtitle)
        // Swallow all touches so nothing beneath can be interacted with.
        v.setOnTouchListener { _, _ -> true }
        try {
            wm.addView(v, params)
            view = v
        } catch (_: Exception) {
        }
    }

    fun hide(ctx: Context) {
        val v = view ?: return
        val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        try {
            wm.removeView(v)
        } catch (_: Exception) {
        }
        view = null
    }

    private fun buildView(ctx: Context, title: String, subtitle: String): View {
        val density = ctx.resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()

        val root = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            background = GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                intArrayOf(Color.parseColor("#4338CA"), Color.parseColor("#7C3AED"))
            )
            setPadding(dp(32), dp(32), dp(32), dp(32))
            isClickable = true
            isFocusable = true
        }

        root.addView(TextView(ctx).apply {
            text = "\uD83D\uDEE1"
            textSize = 64f
            gravity = Gravity.CENTER
        })
        root.addView(TextView(ctx).apply {
            text = title
            setTextColor(Color.WHITE)
            textSize = 28f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(0, dp(20), 0, 0)
        })
        root.addView(TextView(ctx).apply {
            text = subtitle
            setTextColor(Color.parseColor("#E0E7FF"))
            textSize = 16f
            gravity = Gravity.CENTER
            setPadding(dp(16), dp(10), dp(16), 0)
        })
        return root
    }
}
