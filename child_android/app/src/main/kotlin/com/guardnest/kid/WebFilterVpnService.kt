package com.guardnest.kid

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.Inet4Address
import java.net.InetAddress
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * A lightweight, transparent web filter. It stands up a local VPN that routes
 * ONLY DNS to itself, inspects each DNS query, and answers blocked domains with
 * NXDOMAIN while forwarding everything else to a real resolver. All other
 * traffic uses the normal network untouched.
 *
 * This is intentionally opt-in: Android shows a consent dialog before any VPN
 * starts, and the child can see the persistent VPN key. Note: DNS-over-HTTPS
 * (e.g. some browsers / "Private DNS") can bypass this — a known limitation.
 */
class WebFilterVpnService : VpnService() {

    @Volatile private var running = false
    private var tunnel: ParcelFileDescriptor? = null
    private var worker: Thread? = null
    private var pool: ExecutorService? = null
    private val writeLock = Any()
    private var rulesListener: ListenerRegistration? = null

    @Volatile private var blockedDomains: Set<String> = emptySet()
    @Volatile private var enabledCategories: Set<String> = emptySet()
    @Volatile private var upstreams: List<InetAddress> = emptyList()

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopFilter()
            return START_NOT_STICKY
        }
        if (!running) startFilter()
        return START_STICKY
    }

    override fun onDestroy() {
        stopFilter()
        super.onDestroy()
    }

    private fun startFilter() {
        resolveUpstreams()
        // Load cached category lists off the main thread — they can be several
        // MB, and parsing them on the main thread would ANR the app.
        Thread { runCatching { CategoryFeed.loadCache(applicationContext) } }
            .apply { isDaemon = true }.start()
        attachRules()
        val builder = Builder()
            .setSession("Maryada web filter")
            .addAddress("10.111.222.1", 24)
            .addDnsServer(VIRTUAL_DNS)
            .addRoute(VIRTUAL_DNS, 32)
        builder.setBlocking(true)
        val tun = try {
            builder.establish()
        } catch (_: Exception) {
            null
        } ?: return
        tunnel = tun
        running = true
        worker = Thread { runLoop(tun) }.apply { isDaemon = true; start() }
    }

    private fun stopFilter() {
        running = false
        rulesListener?.remove()
        rulesListener = null
        try {
            pool?.shutdownNow()
        } catch (_: Exception) {
        }
        pool = null
        try {
            worker?.interrupt()
        } catch (_: Exception) {
        }
        worker = null
        try {
            tunnel?.close()
        } catch (_: Exception) {
        }
        tunnel = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    /** Keeps [blockedDomains] in sync with the family's web-filter rule. */
    private fun attachRules() {
        val familyId = ChildStore.familyId(this) ?: return
        rulesListener = FirebaseFirestore.getInstance()
            .collection("families").document(familyId)
            .collection("rules").document("webFilter")
            .addSnapshotListener { snap, _ ->
                if (snap == null || !snap.exists()) return@addSnapshotListener
                // The protective categories always block; the family rule can
                // only ADD sites/categories on top, never switch them off.
                if (snap.getBoolean("enabled") == false) {
                    blockedDomains = WebFilter.PROTECTIVE_CATEGORIES
                        .flatMap { WebFilter.CATEGORY_SEEDS[it] ?: emptyList() }
                        .toSet()
                    enabledCategories = WebFilter.PROTECTIVE_CATEGORIES
                    CategoryFeed.ensure(applicationContext, enabledCategories)
                    return@addSnapshotListener
                }
                val sites = (snap.get("blockedSites") as? List<*>)
                    ?.mapNotNull { (it as? String)?.lowercase()?.removePrefix("www.") }
                    ?: emptyList()
                val cats = ((snap.get("blockedCategories") as? List<*>)
                    ?.mapNotNull { it as? String }
                    ?: emptyList()) + WebFilter.PROTECTIVE_CATEGORIES
                val fromCats = cats.flatMap { WebFilter.CATEGORY_SEEDS[it] ?: emptyList() }
                blockedDomains = (sites + fromCats).toSet()
                enabledCategories = cats.toSet()
                // Fetch/refresh the live per-category blocklists for runtime
                // domain categorisation.
                CategoryFeed.ensure(applicationContext, enabledCategories)
                Log.i(TAG, "web filter rules updated: ${blockedDomains.size} seed domain(s), " +
                    "categories=${enabledCategories}")
            }
    }

    private fun runLoop(tun: ParcelFileDescriptor) {
        val input = FileInputStream(tun.fileDescriptor)
        val output = FileOutputStream(tun.fileDescriptor)
        val executor = Executors.newFixedThreadPool(8)
        pool = executor
        val packet = ByteArray(32767)

        while (running && !Thread.interrupted()) {
            val length = try {
                input.read(packet)
            } catch (_: Exception) {
                break
            }
            if (length <= 0) continue
            // Copy the packet: the buffer is reused for the next read while the
            // worker handles this one.
            val copy = packet.copyOf(length)
            try {
                executor.execute { handleQuery(copy, output) }
            } catch (_: Exception) {
                break
            }
        }
    }

    /**
     * Captures the phone's real DNS servers (before the VPN overrides them) and
     * appends public fallbacks, so forwarding is reliable. Only IPv4 servers are
     * kept since the tunnel is IPv4.
     */
    private fun resolveUpstreams() {
        val list = ArrayList<InetAddress>()
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val lp = cm.getLinkProperties(cm.activeNetwork)
            lp?.dnsServers?.forEach { if (it is Inet4Address) list.add(it) }
        } catch (_: Exception) {
        }
        for (ip in listOf("1.1.1.1", "8.8.8.8", "9.9.9.9")) {
            try {
                val a = InetAddress.getByName(ip)
                if (list.none { it.hostAddress == a.hostAddress }) list.add(a)
            } catch (_: Exception) {
            }
        }
        upstreams = list
    }

    /** Forwards a DNS query to each upstream in turn until one answers. */
    private fun forward(query: ByteArray): ByteArray? {
        for (server in upstreams) {
            val socket = DatagramSocket()
            try {
                protect(socket)
                socket.soTimeout = 1500
                socket.send(DatagramPacket(query, query.size, server, 53))
                val buf = ByteArray(4096)
                val resp = DatagramPacket(buf, buf.size)
                socket.receive(resp)
                return buf.copyOfRange(0, resp.length)
            } catch (_: Exception) {
                // Try the next upstream.
            } finally {
                try {
                    socket.close()
                } catch (_: Exception) {
                }
            }
        }
        return null
    }

    /**
     * Handles one captured DNS query on a worker thread: blocked domains get an
     * NXDOMAIN reply; everything else is forwarded to a real resolver (so a slow
     * lookup never stalls the others).
     */
    private fun handleQuery(packet: ByteArray, output: FileOutputStream) {
        try {
            val length = packet.size
            if (length < 28 || (packet[0].toInt() ushr 4 and 0xF) != 4) return
            val ihl = (packet[0].toInt() and 0x0F) * 4
            if (packet[9].toInt() and 0xFF != 17) return // UDP only
            val udp = ihl
            val dstPort =
                ((packet[udp + 2].toInt() and 0xFF) shl 8) or (packet[udp + 3].toInt() and 0xFF)
            if (dstPort != 53) return
            val dnsStart = udp + 8
            if (dnsStart >= length) return

            val dns = packet.copyOfRange(dnsStart, length)
            val domain = parseDomain(dns) ?: return

            val blocked = isBlocked(domain)
            // Only log a block as "blocked website" when the child is actually
            // in a browser — otherwise background app/ad traffic that happens to
            // match a category would show as sites they never tried to visit.
            if (blocked && ForegroundApp.isBrowserForeground()) {
                WebHistoryStore.recordBlocked(domain, reasonFor(domain))
                AlertLog.log(
                    this, "blockedWebsite", "Blocked $domain",
                    throttleKey = "site:$domain",
                )
            }
            val reply = if (blocked) {
                buildNxdomain(dns)
            } else {
                forward(dns) ?: return
            }
            writeReply(packet, ihl, reply, output)
        } catch (_: Exception) {
            // Drop malformed/failed queries; the resolver will retry.
        }
    }

    /** True if [domain] equals or is a subdomain of any blocked domain. */
    private fun isBlocked(domain: String): Boolean {
        val d = domain.lowercase().removePrefix("www.")
        // Manual sites + curated category seeds (instant, offline).
        if (blockedDomains.any { d == it || d.endsWith(".$it") }) return true
        // Runtime category decision from the live per-category feed.
        return CategoryFeed.isBlocked(d, enabledCategories)
    }

    /** Which category blocked [domain], for the parent's activity tag. */
    private fun reasonFor(domain: String): String {
        val d = domain.lowercase().removePrefix("www.")
        return CategoryFeed.categoryOf(d, enabledCategories)
            ?: WebFilter.categoryHint(d)
            ?: WebFilter.REASON_BLOCKLIST
    }

    private fun parseDomain(dns: ByteArray): String? {
        if (dns.size < 13) return null
        var pos = 12
        val sb = StringBuilder()
        while (pos < dns.size) {
            val len = dns[pos].toInt() and 0xFF
            if (len == 0) break
            if (len > 63 || pos + len + 1 > dns.size) return null
            if (sb.isNotEmpty()) sb.append('.')
            for (i in 1..len) sb.append((dns[pos + i].toInt() and 0xFF).toChar())
            pos += len + 1
        }
        return if (sb.isEmpty()) null else sb.toString()
    }

    /** Turns a DNS query into an NXDOMAIN response (same id + question). */
    private fun buildNxdomain(query: ByteArray): ByteArray {
        val out = query.copyOf()
        out[2] = 0x81.toByte() // QR=1, Opcode=0, RD copied bit set below
        out[3] = 0x83.toByte() // RA=1, RCODE=3 (NXDOMAIN)
        // ANCOUNT / NSCOUNT / ARCOUNT = 0
        out[6] = 0; out[7] = 0
        out[8] = 0; out[9] = 0
        out[10] = 0; out[11] = 0
        return out
    }

    /** Wraps a DNS payload back into an IP/UDP packet aimed at the requester. */
    private fun writeReply(
        request: ByteArray,
        ihl: Int,
        dns: ByteArray,
        output: FileOutputStream,
    ) {
        val total = ihl + 8 + dns.size
        val out = ByteArray(total)
        // Copy IP header, swap src/dst.
        System.arraycopy(request, 0, out, 0, ihl)
        for (i in 0 until 4) {
            out[12 + i] = request[16 + i]
            out[16 + i] = request[12 + i]
        }
        // IP total length.
        out[2] = (total ushr 8).toByte()
        out[3] = (total and 0xFF).toByte()
        // Zero IP checksum, recompute.
        out[10] = 0; out[11] = 0
        val ipSum = checksum(out, 0, ihl)
        out[10] = (ipSum ushr 8).toByte()
        out[11] = (ipSum and 0xFF).toByte()
        // UDP header: swap ports, set length, checksum 0.
        val u = ihl
        out[u] = request[u + 2]; out[u + 1] = request[u + 3]     // src port = req dst
        out[u + 2] = request[u]; out[u + 3] = request[u + 1]     // dst port = req src
        val udpLen = 8 + dns.size
        out[u + 4] = (udpLen ushr 8).toByte()
        out[u + 5] = (udpLen and 0xFF).toByte()
        out[u + 6] = 0; out[u + 7] = 0
        System.arraycopy(dns, 0, out, u + 8, dns.size)
        synchronized(writeLock) {
            output.write(out, 0, total)
        }
    }

    private fun checksum(data: ByteArray, offset: Int, len: Int): Int {
        var sum = 0
        var i = offset
        val end = offset + len
        while (i + 1 < end) {
            sum += ((data[i].toInt() and 0xFF) shl 8) or (data[i + 1].toInt() and 0xFF)
            i += 2
        }
        if (i < end) sum += (data[i].toInt() and 0xFF) shl 8
        while (sum shr 16 != 0) sum = (sum and 0xFFFF) + (sum shr 16)
        return sum.inv() and 0xFFFF
    }

    companion object {
        const val ACTION_STOP = "com.guardnest.kid.STOP_WEB_FILTER"
        private const val TAG = "GuardNestWebFilter"
        private const val VIRTUAL_DNS = "10.111.222.2"

        /**
         * Starts the filter (requires one-time VPN consent to have been granted).
         * Called by the enforcement service when the parent enables web filtering.
         */
        fun start(ctx: Context) {
            ctx.startService(Intent(ctx, WebFilterVpnService::class.java))
        }

        /** Stops the filter (parent disabled it, or nothing left to block). */
        fun stop(ctx: Context) {
            ctx.startService(
                Intent(ctx, WebFilterVpnService::class.java).setAction(ACTION_STOP)
            )
        }
    }
}
