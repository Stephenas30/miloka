package com.billard.game

import android.app.Activity
import android.os.Bundle
import android.util.Log
import android.view.View
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast

class MainActivity : Activity() {
    private var net: Net? = null
    private var isHost = false
    private var kadriOnline = false
    private lateinit var pool: PoolView

    companion object {
        private var activeInstance: MainActivity? = null

        @JvmStatic
        fun receivePoolMessage(message: String) {
            activeInstance?.runOnUiThread {
                activeInstance?.onLine(message)
            }
        }

        @JvmStatic
        fun showKadriMessage(message: String) {
            activeInstance?.let { activity ->
                activity.runOnUiThread {
                    Toast.makeText(activity, message, Toast.LENGTH_LONG).show()
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        activeInstance = this
        setContentView(R.layout.activity_main)
        applyImmersiveMode()
        pool = findViewById(R.id.pool)
        val p1 = findViewById<TextView>(R.id.player1)
        val p2 = findViewById<TextView>(R.id.player2)
        val msg = findViewById<TextView>(R.id.message)
        val stake = findViewById<TextView>(R.id.stake)
        val profileName = findViewById<TextView>(R.id.profile_name)
        val wallet = findViewById<TextView>(R.id.wallet_balance)
        val mode = intent.getIntExtra("mode", 1)
        val hostBet = intent.getIntExtra("host_bet", 0)
        val guestBet = intent.getIntExtra("guest_bet", 0)
        val userName = intent.getStringExtra("user_name") ?: "Profil"
        profileName.text = userName
        wallet.text = intent.getIntExtra("user_coins", 0).toString()
        ProfileAvatarLoader.load(
            findViewById<ImageView>(R.id.profile_avatar),
            intent.getStringExtra("avatar_url"),
        )
        if (mode == 2 && (hostBet > 0 || guestBet > 0)) {
            stake.text = "Mise $hostBet / $guestBet 🪙"
            stake.visibility = View.VISIBLE
        }
        pool.mode = mode
        pool.level = intent.getIntExtra("level", 1)
        pool.listener = object : PoolView.Listener {
            override fun onHud(p0: String, p1t: String, cur: Int, message: String) {
                p1.text = p0
                p2.text = p1t
                msg.text = message
                p1.setBackgroundResource(if (cur == 0) R.drawable.card_active else R.drawable.card_bg)
                p2.setBackgroundResource(if (cur == 1) R.drawable.card_active else R.drawable.card_bg)
            }

            override fun onGameOver(winner: Int) {
                if (!kadriOnline) return
                try {
                    Class.forName("com.example.miloka.MainActivity")
                        .getMethod("notifyPoolGameFinished", Integer.TYPE)
                        .invoke(null, winner)
                } catch (error: ReflectiveOperationException) {
                    Log.e("BillardOnline", "Could not notify Kadri that the game ended", error)
                }
            }
        }
        findViewById<Button>(R.id.btn_home).setOnClickListener { finish() }
        val replay: () -> Unit = {
            when {
                mode != 2 -> pool.newGame()
                isHost -> startOnlineGame()
                else -> Toast.makeText(this, R.string.only_host, Toast.LENGTH_SHORT).show()
            }
        }
        findViewById<Button>(R.id.restart).setOnClickListener { replay() }
        pool.onReplay = replay
        pool.onHome = { finish() }
        if (mode == 2 && intent.getBooleanExtra("kadri_online", false)) {
            startKadriOnline()
        } else if (mode == 2) {
            startOnline(intent.getStringExtra("role") == "host", intent.getStringExtra("ip") ?: "")
        }
        else pool.newGame()
    }

    private fun startKadriOnline() {
        kadriOnline = true
        isHost = intent.getIntExtra("player_index", 0) == 0
        val seed = intent.getLongExtra("seed", 0L)
        pool.myIdx = if (isHost) 0 else 1
        pool.ready = true
        pool.newGame(seed)
        pool.send = { message ->
            try {
                Class.forName("com.example.miloka.MainActivity")
                    .getMethod("sendPoolMessage", String::class.java)
                    .invoke(null, message)
            } catch (error: ReflectiveOperationException) {
                Log.e("BillardOnline", "Could not send game move to Kadri", error)
            }
        }
    }

    private fun startOnlineGame() {
        val seed = System.nanoTime()
        pool.ready = true
        pool.newGame(seed)
        pool.send?.invoke("START $seed")
    }

    private fun startOnline(host: Boolean, ip: String) {
        isHost = host
        pool.myIdx = if (host) 0 else 1
        pool.ready = false
        pool.newGame()
        val n = Net({ line -> onLine(line) }, { ev -> onEvent(ev) })
        net = n
        pool.send = { n.send(it) }
        if (host) { n.host(); pool.setMessage(getString(R.string.waiting) + " " + Net.localIp()) }
        else { n.join(ip); pool.setMessage(getString(R.string.connecting)) }
    }

    private fun onEvent(ev: String) {
        when (ev) {
            "connected" -> if (isHost) startOnlineGame()
            "error" -> pool.setMessage(getString(R.string.conn_error))
            "lost" -> { pool.ready = false; pool.setMessage(getString(R.string.conn_lost)) }
        }
    }

    private fun onLine(line: String) {
        val f = line.split(" ")
        when (f[0]) {
            "START" -> { pool.ready = true; pool.newGame(f[1].toLong()) }
            "SHOT" -> pool.remoteShot(f[1].toFloat(), f[2].toFloat())
            "PLACE" -> pool.remotePlace(f[1].toFloat(), f[2].toFloat())
            "STATE" -> pool.applySnapshot(line)
        }
    }

    override fun onDestroy() {
        net?.close()
        if (kadriOnline) {
            try {
                Class.forName("com.example.miloka.MainActivity")
                    .getMethod("notifyPoolGameClosed")
                    .invoke(null)
            } catch (error: ReflectiveOperationException) {
                Log.e("BillardOnline", "Could not notify Kadri that the game closed", error)
            }
        }
        if (activeInstance === this) activeInstance = null
        super.onDestroy()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) applyImmersiveMode()
    }

    private fun applyImmersiveMode() {
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_FULLSCREEN or
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE
    }
}
