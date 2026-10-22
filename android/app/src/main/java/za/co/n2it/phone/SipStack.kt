package za.co.n2it.phone

import android.os.Handler
import android.os.Looper
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.concurrent.TimeUnit

/*
 * N2IT's own SIP client over a secure WebSocket (RFC 7118), the same way the desktop app (JsSIP) talks to FusionPBX:
 * wss://<company>.voip.n2it.co.za/wss on port 443, which nginx passes to FreeSWITCH's WSS listener. Audio is WebRTC
 * (CallMedia.kt). It only does what the app needs: register, calls in and out, hold, transfer, voicemail lamp.
 * Replaces the Linphone SDK (AGPLv3, closed-source licence not affordable; owner 2026-10-22).
 */

/** One SIP request or response. Header names keep their case; lookups ignore case and know the compact forms. */
class SipMsg(val startLine: String, val headers: MutableList<Pair<String, String>> = mutableListOf(), var body: String = "") {
    val isRequest get() = !startLine.startsWith("SIP/2.0")
    val method: String get() = if (isRequest) startLine.substringBefore(' ') else cseqMethod
    val uri: String get() = startLine.split(' ').getOrElse(1) { "" }
    val status: Int get() = if (isRequest) 0 else startLine.split(' ').getOrNull(1)?.toIntOrNull() ?: 0
    val reason: String get() = if (isRequest) "" else startLine.split(' ', limit = 3).getOrElse(2) { "" }
    val cseq: Int get() = h("CSeq")?.trim()?.substringBefore(' ')?.toIntOrNull() ?: 0
    val cseqMethod: String get() = h("CSeq")?.trim()?.substringAfter(' ')?.trim() ?: ""
    val callId: String get() = h("Call-ID") ?: ""
    val fromTag: String? get() = tagOf(h("From"))
    val toTag: String? get() = tagOf(h("To"))
    val branch: String? get() = h("Via")?.let { Regex(";\\s*branch=([^;,\\s]+)", RegexOption.IGNORE_CASE).find(it)?.groupValues?.get(1) }
    val hasSdp get() = body.isNotBlank() && (h("Content-Type") ?: "").contains("sdp", true)

    fun h(name: String): String? = all(name).firstOrNull()
    fun all(name: String): List<String> {
        val n = full(name)
        return headers.filter { full(it.first).equals(n, true) }.map { it.second }
    }
    fun add(name: String, value: String) = apply { headers += name to value }
    fun set(name: String, value: String) = apply { remove(name); headers += name to value }
    fun remove(name: String) = apply { val n = full(name); headers.removeAll { full(it.first).equals(n, true) } }

    fun encode(): String {
        val sb = StringBuilder(startLine).append("\r\n")
        headers.filterNot { full(it.first).equals("Content-Length", true) }.forEach { (k, v) -> sb.append(k).append(": ").append(v).append("\r\n") }
        sb.append("Content-Length: ").append(body.toByteArray().size).append("\r\n\r\n").append(body)
        return sb.toString()
    }

    companion object {
        private val compact = mapOf("v" to "Via", "f" to "From", "t" to "To", "i" to "Call-ID", "m" to "Contact",
            "l" to "Content-Length", "c" to "Content-Type", "k" to "Supported", "o" to "Event", "r" to "Refer-To",
            "x" to "Session-Expires", "u" to "Allow-Events", "b" to "Referred-By", "e" to "Content-Encoding", "s" to "Subject")
        private fun full(n: String) = compact[n.lowercase()] ?: n

        fun tagOf(v: String?): String? = v?.let { Regex(";\\s*tag=([^;>\\s,]+)", RegexOption.IGNORE_CASE).find(it)?.groupValues?.get(1) }
        /** "Nasr" <sip:1002@n2test.voip.n2it.co.za>;tag=x -> sip:1002@n2test.voip.n2it.co.za */
        fun uriOf(v: String?): String = v?.let { s -> Regex("<([^>]*)>").find(s)?.groupValues?.get(1) ?: s.substringBefore(';').trim() } ?: ""
        fun userOf(uri: String): String = uri.substringAfter(':').substringBefore('@').substringBefore(';')
        fun nameOf(v: String?): String? = v?.let { s ->
            if (!s.contains('<')) return null
            s.substringBefore('<').trim().trim('"').trim().takeIf { it.isNotEmpty() }
        }

        fun parse(text: String): SipMsg? {
            val sep = text.indexOf("\r\n\r\n").takeIf { it >= 0 } ?: return null
            val lines = text.substring(0, sep).split("\r\n")
            val msg = SipMsg(lines.firstOrNull()?.trim() ?: return null)
            for (line in lines.drop(1)) {
                if (line.isEmpty()) continue
                if ((line[0] == ' ' || line[0] == '\t') && msg.headers.isNotEmpty()) {   // folded line
                    val (k, v) = msg.headers.removeAt(msg.headers.size - 1); msg.headers += k to "$v ${line.trim()}"; continue
                }
                val i = line.indexOf(':').takeIf { it > 0 } ?: continue
                msg.headers += line.substring(0, i).trim() to line.substring(i + 1).trim()
            }
            msg.body = text.substring(sep + 4)
            return msg
        }
    }
}

/** A SIP dialog (a call, or a REFER's subscription inside it): what requests inside the call need. */
class Dialog(val callId: String, val localTag: String, var remoteTag: String, val localUri: String, val remoteUri: String,
             var remoteTarget: String, var routes: List<String>, var localCseq: Int, var remoteName: String? = null)

/**
 * The SIP client: one WebSocket, the registration, and sending/receiving messages. Everything runs on the main thread
 * (the socket's and timers' callbacks are posted there), so the call logic in SipManager needs no locks.
 */
class SipUa(private val events: Events) {
    interface Events {
        fun onRegistration(state: RegState, code: Int, reason: String)
        /** A request from the PBX (INVITE, BYE, CANCEL, NOTIFY…); answer it with [SipUa.reply]. */
        fun onRequest(req: SipMsg)
        fun onTransportDown()
    }
    enum class RegState { None, Progress, Ok, Failed }

    private val main = Handler(Looper.getMainLooper())
    private val rnd = SecureRandom()
    private val http = OkHttpClient.Builder()
        .pingInterval(25, TimeUnit.SECONDS)   // keeps mobile networks and NAT from dropping an idle connection
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .build()

    var user = ""; private set
    var domain = ""; private set
    private var password = ""
    var userAgent = "N2IT Phone Android"
    private var ws: WebSocket? = null
    private var wsGen = 0   // callbacks from an old socket are ignored
    var connected = false; private set
    private var wanted = false   // keep connected and registered (false after stop())
    private var backoff = 2_000L

    /** Made-up host for our Via and Contact: over a WebSocket the PBX answers on the socket, not to an address. */
    private val viaHost = token(12).lowercase() + ".invalid"
    private val contactUser = token(8).lowercase()
    val contact get() = "<sip:$contactUser@$viaHost;transport=ws>"
    val aor get() = "sip:$user@$domain"

    // ---- Registration ----
    private val regCallId = token(22)
    private var regCseq = 0
    var regState = RegState.None; private set
    private val expires = 600   // re-register every 10 min; a mobile network forgets an idle connection after a few
    private val refresh = Runnable { register() }

    fun start(user: String, password: String, domain: String) {
        stop(unregister = regState == RegState.Ok)
        this.user = user.trim(); this.password = password; this.domain = domain
        wanted = true; backoff = 2_000L
        connect()
    }

    /** Disconnect and stay disconnected; [unregister] first so the PBX stops sending calls here. */
    fun stop(unregister: Boolean = true) {
        wanted = false
        main.removeCallbacks(refresh); main.removeCallbacks(reconnect)
        val old = ws
        val close = {
            if (ws === old) {
                ws = null; wsGen++; connected = false
                pending.values.forEach { main.removeCallbacks(it.timeout) }; pending.clear()
            }
            old?.close(1000, null)
        }
        if (unregister && connected && regState == RegState.Ok) {
            var done = false
            val finish = { if (!done) { done = true; close() } }
            request(registerRequest(0)) { if (it.status >= 200) finish() }
            main.postDelayed({ finish() }, 2000)
        } else close()
        setReg(RegState.None, 0, "")
    }

    /** Re-register now (app back on screen, network changed); reconnects first if the socket is gone. */
    fun refreshNow() {
        if (!wanted) return
        if (connected) register() else { main.removeCallbacks(reconnect); connect() }
    }

    /** The network changed (Wi-Fi <-> mobile): the old socket is dead even if it does not know it yet. */
    fun reconnectNow() {
        if (!wanted) return
        ws?.cancel(); ws = null; wsGen++; connected = false
        main.removeCallbacks(reconnect); connect()
    }

    private val reconnect = Runnable { connect() }

    private fun connect() {
        if (!wanted || domain.isEmpty()) return
        ws?.cancel()
        val gen = ++wsGen
        setReg(RegState.Progress, 0, "Connecting…")
        val req = Request.Builder().url("wss://$domain/wss").header("Sec-WebSocket-Protocol", "sip").header("User-Agent", userAgent).build()
        ws = http.newWebSocket(req, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                main.post { if (gen == wsGen) { connected = true; backoff = 2_000L; register() } }
            }
            override fun onMessage(webSocket: WebSocket, text: String) { main.post { if (gen == wsGen) receive(text) } }
            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) { main.post { if (gen == wsGen) lost("closed") } }
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                main.post { if (gen == wsGen) lost(t.message ?: "no connection") }
            }
        })
    }

    private fun lost(why: String) {
        connected = false; ws = null
        main.removeCallbacks(refresh)
        pending.values.toList().forEach { tx -> main.removeCallbacks(tx.timeout); pending.remove(tx.branch); tx.onResponse(synthetic(tx.req, 503, "Connection lost")) }
        events.onTransportDown()
        if (!wanted) return
        setReg(RegState.Progress, 0, "Cannot reach $domain (retrying)")
        main.postDelayed(reconnect, backoff)
        backoff = (backoff * 2).coerceAtMost(30_000L)
    }

    private fun setReg(s: RegState, code: Int, reason: String) { regState = s; events.onRegistration(s, code, reason) }

    private fun registerRequest(exp: Int) = SipMsg("REGISTER sip:$domain SIP/2.0")
        .add("Via", via()).add("Max-Forwards", "70")
        .add("To", "<$aor>").add("From", "<$aor>;tag=${token(10)}")
        .add("Call-ID", regCallId).add("CSeq", "${++regCseq} REGISTER")
        .add("Contact", "$contact;expires=$exp").add("Expires", "$exp")
        .add("Allow", ALLOW).add("Supported", "path, outbound").add("User-Agent", userAgent)

    private fun register() {
        main.removeCallbacks(refresh)
        if (!connected) return
        if (regState != RegState.Ok) setReg(RegState.Progress, 0, "Registering…")
        request(registerRequest(expires)) { res ->
            if (!wanted) return@request
            when {
                res.status in 200..299 -> {
                    // The PBX may shorten the time: re-register at 90% of what it granted
                    val granted = res.all("Contact").firstNotNullOfOrNull { c -> if (c.contains(contactUser)) Regex("expires=(\\d+)").find(c)?.groupValues?.get(1)?.toIntOrNull() else null }
                        ?: res.h("Expires")?.trim()?.toIntOrNull() ?: expires
                    setReg(RegState.Ok, res.status, res.reason)
                    main.postDelayed(refresh, (granted.coerceIn(60, expires) * 900L))
                }
                res.status >= 300 -> {
                    setReg(RegState.Failed, res.status, res.reason)
                    // A wrong password is not retried (the PBX bans the whole network after a few: fail2ban);
                    // anything else (PBX busy, connection lost) tries again in a minute
                    if (res.status != 401 && res.status != 403 && res.status != 407 && res.status != 404 && wanted)
                        main.postDelayed(refresh, 60_000L)
                }
            }
        }
    }

    // ---- Sending and receiving ----
    private class ClientTx(val branch: String, val req: SipMsg, val onResponse: (SipMsg) -> Unit, val timeout: Runnable,
                           val onRetry: ((SipMsg) -> Unit)?, val authTried: Boolean = false)
    private val pending = mutableMapOf<String, ClientTx>()

    fun via() = "SIP/2.0/WSS $viaHost;branch=z9hG4bK${token(16)}"

    fun send(msg: SipMsg): Boolean {
        val w = ws ?: return false
        if (!connected) return false
        return w.send(msg.encode())
    }

    /**
     * Send a request and get every response to it (provisional too). A 401/407 is answered once with the password;
     * the retry gets a new CSeq ([onRetry] lets a call keep its dialog's CSeq in step). No answer in 32 s = 408.
     */
    fun request(req: SipMsg, onRetry: ((SipMsg) -> Unit)? = null, onResponse: (SipMsg) -> Unit) {
        val branch = req.branch ?: return
        track(ClientTx(branch, req, onResponse, timeoutFor(branch, req, onResponse), onRetry))
    }
    private fun timeoutFor(branch: String, req: SipMsg, onResponse: (SipMsg) -> Unit) =
        Runnable { pending.remove(branch)?.let { onResponse(synthetic(req, 408, "Request Timeout")) } }
    private fun track(tx: ClientTx) {
        pending[tx.branch] = tx
        main.postDelayed(tx.timeout, if (tx.req.method == "INVITE") 180_000L else 32_000L)
        if (!send(tx.req)) { pending.remove(tx.branch); main.removeCallbacks(tx.timeout); tx.onResponse(synthetic(tx.req, 503, "Not connected")) }
    }

    /** Answer an INVITE that is still in progress with CANCEL (same branch, as RFC 3261 wants). */
    fun cancel(invite: SipMsg) {
        val c = SipMsg("CANCEL ${invite.uri} SIP/2.0")
        listOf("Via", "To", "From", "Call-ID").forEach { n -> invite.h(n)?.let { c.add(n, it) } }
        invite.all("Route").forEach { c.add("Route", it) }
        c.add("CSeq", "${invite.cseq} CANCEL").add("Max-Forwards", "70").add("User-Agent", userAgent)
        send(c)
    }

    private fun receive(text: String) {
        val msg = SipMsg.parse(text) ?: return
        if (msg.isRequest) { events.onRequest(msg); return }
        val tx = pending[msg.branch ?: return] ?: return
        if (msg.status == 401 || msg.status == 407) {
            if (msg.cseqMethod == "INVITE") ackFailure(tx.req, msg)
            val retry = if (tx.authTried || password.isEmpty()) null else authorised(tx.req, msg)
            if (retry == null) { finish(tx, msg); return }
            pending.remove(tx.branch); main.removeCallbacks(tx.timeout)
            tx.onRetry?.invoke(retry)
            val b = retry.branch ?: return
            track(ClientTx(b, retry, tx.onResponse, timeoutFor(b, retry, tx.onResponse), tx.onRetry, authTried = true))
            return
        }
        if (msg.status >= 200) {
            // A failed INVITE is acknowledged here (same branch); a 2xx is acknowledged by the call (new branch)
            if (msg.cseqMethod == "INVITE" && msg.status >= 300) ackFailure(tx.req, msg)
            finish(tx, msg)
        } else tx.onResponse(msg)
    }

    private fun finish(tx: ClientTx, res: SipMsg) {
        pending.remove(tx.branch); main.removeCallbacks(tx.timeout)
        tx.onResponse(res)
    }

    private fun ackFailure(invite: SipMsg, res: SipMsg) {
        val ack = SipMsg("ACK ${invite.uri} SIP/2.0")
        invite.h("Via")?.let { ack.add("Via", it) }
        ack.add("Max-Forwards", "70").add("To", res.h("To") ?: "").add("From", invite.h("From") ?: "")
            .add("Call-ID", invite.callId).add("CSeq", "${invite.cseq} ACK")
        invite.all("Route").forEach { ack.add("Route", it) }
        send(ack)
    }

    /** Copy of [req] with the answer to the PBX's password challenge (digest, MD5). */
    private fun authorised(req: SipMsg, challenge: SipMsg): SipMsg? {
        val proxy = challenge.status == 407
        val ch = challenge.h(if (proxy) "Proxy-Authenticate" else "WWW-Authenticate") ?: return null
        fun p(n: String) = Regex("$n=\"?([^\",]*)\"?", RegexOption.IGNORE_CASE).find(ch)?.groupValues?.get(1)
        val realm = p("realm") ?: domain
        val nonce = p("nonce") ?: return null
        val qop = p("qop")?.split(',')?.map { it.trim() }?.firstOrNull { it.equals("auth", true) }
        val algorithm = p("algorithm") ?: "MD5"
        if (!algorithm.equals("MD5", true)) return null
        val uri = req.uri
        val ha1 = md5("$user:$realm:$password")
        val ha2 = md5("${req.method}:$uri")
        val cnonce = token(16).lowercase()
        val nc = "00000001"
        val response = if (qop != null) md5("$ha1:$nonce:$nc:$cnonce:$qop:$ha2") else md5("$ha1:$nonce:$ha2")
        var value = "Digest username=\"$user\", realm=\"$realm\", nonce=\"$nonce\", uri=\"$uri\", response=\"$response\", algorithm=MD5"
        p("opaque")?.let { value += ", opaque=\"$it\"" }
        if (qop != null) value += ", qop=$qop, nc=$nc, cnonce=\"$cnonce\""
        val copy = SipMsg(req.startLine, req.headers.toMutableList(), req.body)
        copy.remove("Authorization").remove("Proxy-Authorization")
        copy.set("Via", via())
        copy.set("CSeq", "${req.cseq + 1} ${req.method}")
        copy.add(if (proxy) "Proxy-Authorization" else "Authorization", value)
        if (req.method == "REGISTER") regCseq = req.cseq + 1
        return copy
    }

    /** A response to the PBX's request [req]: Via, From, To (with our [toTag]), Call-ID and CSeq copied over. */
    fun reply(req: SipMsg, code: Int, reason: String, toTag: String? = null, extra: List<Pair<String, String>> = emptyList(), body: String = "") {
        val res = SipMsg("SIP/2.0 $code $reason")
        req.all("Via").forEach { res.add("Via", it) }
        req.all("Record-Route").forEach { res.add("Record-Route", it) }
        val to = req.h("To") ?: ""
        res.add("From", req.h("From") ?: "")
        res.add("To", if (toTag != null && SipMsg.tagOf(to) == null && code > 100) "$to;tag=$toTag" else to)
        res.add("Call-ID", req.callId).add("CSeq", req.h("CSeq") ?: "")
        res.add("User-Agent", userAgent)
        extra.forEach { (k, v) -> res.add(k, v) }
        if (body.isNotEmpty()) res.add("Content-Type", "application/sdp")
        res.body = body
        send(res)
    }

    /** A request inside [d] (BYE, re-INVITE, REFER, ACK…). */
    fun inDialog(d: Dialog, method: String, cseq: Int = ++d.localCseq): SipMsg {
        val m = SipMsg("$method ${d.remoteTarget} SIP/2.0")
            .add("Via", via()).add("Max-Forwards", "70")
            .add("To", "<${d.remoteUri}>;tag=${d.remoteTag}").add("From", "<${d.localUri}>;tag=${d.localTag}")
            .add("Call-ID", d.callId).add("CSeq", "$cseq $method")
        d.routes.forEach { m.add("Route", it) }
        if (method != "ACK" && method != "BYE") m.add("Contact", contact)
        m.add("User-Agent", userAgent)
        return m
    }

    private fun synthetic(req: SipMsg, code: Int, reason: String) =
        SipMsg("SIP/2.0 $code $reason").add("Call-ID", req.callId).add("CSeq", "${req.cseq} ${req.method}")

    fun token(n: Int): String {
        val chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        return (1..n).map { chars[rnd.nextInt(chars.length)] }.joinToString("")
    }

    companion object {
        const val ALLOW = "INVITE, ACK, CANCEL, BYE, UPDATE, OPTIONS, REFER, NOTIFY, INFO, MESSAGE"
        fun md5(s: String) = MessageDigest.getInstance("MD5").digest(s.toByteArray()).joinToString("") { "%02x".format(it) }
    }
}
