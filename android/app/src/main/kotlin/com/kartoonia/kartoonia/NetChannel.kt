package com.kartoonia.kartoonia

import io.flutter.plugin.common.MethodChannel
import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.zip.GZIPInputStream
import java.util.zip.InflaterInputStream
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

/**
 * A tiny native HTTP client that forces **TLS 1.2** on the handshake.
 *
 * WCOFlix's mirrors sit behind a Cloudflare "managed challenge" that 403s a
 * default TLS-1.3 client (which is what Dart's `dart:io` HttpClient negotiates,
 * with no API to change it). The WatchNixtoons2 Kodi addon gets through by
 * pinning its urllib3 pool to `PROTOCOL_TLSv1_2`; forcing TLS 1.2 here
 * reproduces that exact fingerprint, which Cloudflare lets through.
 *
 * Only the small catalog/search/embed/getvidlink requests need this — the media
 * CDN is not walled and is played directly by libmpv. So this handles short text
 * responses; bodies are returned as UTF-8 strings over the method channel.
 */
object NetChannel {
    private val io = Executors.newFixedThreadPool(4)

    /** An SSLSocketFactory whose sockets only offer TLS 1.2. */
    private val tls12Factory: SSLSocketFactory by lazy {
        val ctx = SSLContext.getInstance("TLSv1.2")
        ctx.init(null, null, null)
        ForcedTls12Factory(ctx.socketFactory)
    }

    fun handle(method: String, args: Map<String, Any?>, result: MethodChannel.Result) {
        when (method) {
            "get" -> request("GET", args, null, result)
            "post" -> {
                val body = args["body"] as? String ?: ""
                request("POST", args, body, result)
            }
            else -> result.notImplemented()
        }
    }

    private fun request(
        verb: String,
        args: Map<String, Any?>,
        body: String?,
        result: MethodChannel.Result,
    ) {
        val url = args["url"] as? String
        if (url == null) {
            result.error("no_url", "url is required", null); return
        }
        @Suppress("UNCHECKED_CAST")
        val headers = (args["headers"] as? Map<String, String>) ?: emptyMap()
        val timeoutMs = (args["timeoutMs"] as? Int) ?: 15000

        io.execute {
            var conn: HttpURLConnection? = null
            try {
                conn = (URL(url).openConnection() as HttpURLConnection).apply {
                    if (this is HttpsURLConnection) sslSocketFactory = tls12Factory
                    requestMethod = verb
                    connectTimeout = timeoutMs
                    readTimeout = timeoutMs
                    instanceFollowRedirects = true
                    setRequestProperty("Accept-Encoding", "gzip, deflate")
                    for ((k, v) in headers) setRequestProperty(k, v)
                    if (verb == "POST") {
                        doOutput = true
                        if (getRequestProperty("Content-Type") == null) {
                            setRequestProperty(
                                "Content-Type",
                                "application/x-www-form-urlencoded",
                            )
                        }
                        outputStream.use { it.write((body ?: "").toByteArray(Charsets.UTF_8)) }
                    }
                }
                val code = conn.responseCode
                val stream = if (code in 200..399) conn.inputStream else conn.errorStream
                val text = stream?.let { decodeBody(it, conn.contentEncoding) } ?: ""
                val payload = mapOf("status" to code, "body" to text)
                postSuccess(result, payload)
            } catch (e: Throwable) {
                postError(result, e)
            } finally {
                conn?.disconnect()
            }
        }
    }

    private fun decodeBody(raw: java.io.InputStream, encoding: String?): String {
        val decoded = when (encoding?.lowercase()) {
            "gzip" -> GZIPInputStream(raw)
            "deflate" -> InflaterInputStream(raw)
            else -> raw
        }
        BufferedInputStream(decoded).use { input ->
            val buf = ByteArrayOutputStream()
            val chunk = ByteArray(8192)
            while (true) {
                val n = input.read(chunk)
                if (n < 0) break
                buf.write(chunk, 0, n)
            }
            return buf.toString("UTF-8")
        }
    }

    private fun postSuccess(result: MethodChannel.Result, payload: Any?) {
        android.os.Handler(android.os.Looper.getMainLooper()).post { result.success(payload) }
    }

    private fun postError(result: MethodChannel.Result, e: Throwable) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            result.error("net_error", e.message ?: e.toString(), null)
        }
    }
}

/**
 * Wraps a delegate factory so every socket it produces has its enabled protocols
 * clamped to TLS 1.2 before the handshake begins.
 */
private class ForcedTls12Factory(private val delegate: SSLSocketFactory) : SSLSocketFactory() {
    private fun clamp(s: java.net.Socket): java.net.Socket {
        if (s is SSLSocket) s.enabledProtocols = arrayOf("TLSv1.2")
        return s
    }

    override fun getDefaultCipherSuites(): Array<String> = delegate.defaultCipherSuites
    override fun getSupportedCipherSuites(): Array<String> = delegate.supportedCipherSuites

    override fun createSocket(s: java.net.Socket, host: String, port: Int, autoClose: Boolean) =
        clamp(delegate.createSocket(s, host, port, autoClose))

    override fun createSocket(host: String, port: Int) =
        clamp(delegate.createSocket(host, port))

    override fun createSocket(host: String, port: Int, localHost: java.net.InetAddress, localPort: Int) =
        clamp(delegate.createSocket(host, port, localHost, localPort))

    override fun createSocket(host: java.net.InetAddress, port: Int) =
        clamp(delegate.createSocket(host, port))

    override fun createSocket(
        address: java.net.InetAddress,
        port: Int,
        localAddress: java.net.InetAddress,
        localPort: Int,
    ) = clamp(delegate.createSocket(address, port, localAddress, localPort))
}
