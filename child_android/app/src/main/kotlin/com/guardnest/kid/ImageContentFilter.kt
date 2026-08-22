package com.guardnest.kid

import android.graphics.Bitmap

/**
 * Computes a cheap perceptual signature of a captured browser frame. It's used
 * purely as a change detector: when two consecutive screenshots hash to the
 * same value the page is static, so the caller can skip the expensive OCR pass
 * and save battery. It does no content analysis of its own.
 */
object ImageContentFilter {

    /**
     * A cheap 64-bit average-hash of the frame, used to tell whether the screen
     * changed since the last capture. Identical signatures mean a static page,
     * so the caller can skip the expensive OCR pass and save battery. Returns 0
     * on failure (treated as "changed", so nothing is ever wrongly skipped).
     */
    fun signature(bitmap: Bitmap): Long {
        return try {
            val small = Bitmap.createScaledBitmap(bitmap, 8, 8, false)
            val px = IntArray(64)
            small.getPixels(px, 0, 8, 0, 0, 8, 8)
            if (small !== bitmap) small.recycle()
            val lum = IntArray(64)
            var sum = 0L
            for (i in 0 until 64) {
                val p = px[i]
                val r = (p shr 16) and 0xFF
                val g = (p shr 8) and 0xFF
                val b = p and 0xFF
                val l = (r * 30 + g * 59 + b * 11) / 100
                lum[i] = l
                sum += l
            }
            val avg = (sum / 64).toInt()
            var bits = 0L
            for (i in 0 until 64) {
                if (lum[i] >= avg) bits = bits or (1L shl i)
            }
            bits
        } catch (_: Throwable) {
            0L
        }
    }
}
