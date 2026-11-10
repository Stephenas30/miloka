package com.billard.game

import android.os.Handler
import android.os.Looper
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.PrintWriter
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.Executors

/** Connexion directe entre deux téléphones (l’un héberge, l’autre rejoint par adresse IP). */
class Net(private val onLine: (String) -> Unit, private val onEvent: (String) -> Unit) {
    private val ui = Handler(Looper.getMainLooper())
    private val writer = Executors.newSingleThreadExecutor()
    private var socket: Socket? = null
    private var server: ServerSocket? = null
    private var out: PrintWriter? = null
    @Volatile private var closed = false

    companion object {
        const val PORT = 5050
        fun localIp(): String {
            try {
                for (i in NetworkInterface.getNetworkInterfaces().toList())
                    for (a in i.inetAddresses.toList())
                        if (!a.isLoopbackAddress && a is Inet4Address) return a.hostAddress ?: "?"
            } catch (e: Exception) { }
            return "?"
        }
    }

    fun host() {
        Thread {
            try { server = ServerSocket(PORT); attach(server!!.accept()) }
            catch (e: Exception) { if (!closed) post("error") }
        }.start()
    }

    fun join(ip: String) {
        Thread {
            try { val s = Socket(); s.connect(InetSocketAddress(ip, PORT), 8000); attach(s) }
            catch (e: Exception) { if (!closed) post("error") }
        }.start()
    }

    private fun attach(s: Socket) {
        socket = s
        out = PrintWriter(s.getOutputStream(), true)
        post("connected")
        try {
            val r = BufferedReader(InputStreamReader(s.getInputStream()))
            while (true) { val l = r.readLine() ?: break; ui.post { onLine(l) } }
        } catch (e: Exception) { }
        if (!closed) post("lost")
    }

    fun send(line: String) {
        try { writer.execute { try { out?.println(line) } catch (e: Exception) { } } } catch (e: Exception) { }
    }

    fun close() {
        closed = true
        try { socket?.close(); server?.close() } catch (e: Exception) { }
        writer.shutdown()
    }

    private fun post(e: String) { ui.post { onEvent(e) } }
}
