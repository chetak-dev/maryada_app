package com.guardnest.kid

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.WebView

/**
 * Full-screen "website blocked" page shown when the child's browser reaches an
 * unsafe site. It renders a styled HTML page ([assets/blocked.html]) in a
 * WebView — a real designed page rather than a floating overlay — with a
 * "Go back" button. The accessibility service has already sent the browser back
 * off the unsafe page before launching this, so closing this returns the child
 * to the previous, safe page.
 */
class BlockActivity : Activity() {

    @SuppressLint("SetJavaScriptEnabled", "AddJavascriptInterface")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val host = intent.getStringExtra(EXTRA_HOST).orEmpty()
        val message = intent.getStringExtra(EXTRA_MESSAGE).orEmpty()
        val title = intent.getStringExtra(EXTRA_TITLE).orEmpty()

        val web = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = false
            isVerticalScrollBarEnabled = false
            addJavascriptInterface(Bridge(), "Android")
            val params = buildList {
                if (host.isNotEmpty()) add("site=" + Uri.encode(host))
                if (message.isNotEmpty()) add("msg=" + Uri.encode(message))
                if (title.isNotEmpty()) add("title=" + Uri.encode(title))
            }
            val query = if (params.isEmpty()) "" else "?" + params.joinToString("&")
            loadUrl("file:///android_asset/blocked.html$query")
        }
        setContentView(
            web,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        finish()
    }

    private inner class Bridge {
        @JavascriptInterface
        fun goBack() {
            runOnUiThread { finish() }
        }

        @JavascriptInterface
        fun goHome() {
            runOnUiThread {
                try {
                    startActivity(
                        Intent(Intent.ACTION_MAIN)
                            .addCategory(Intent.CATEGORY_HOME)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                } catch (_: Exception) {
                }
                finish()
            }
        }
    }

    companion object {
        const val EXTRA_HOST = "host"
        const val EXTRA_MESSAGE = "message"
        const val EXTRA_TITLE = "title"
    }
}
