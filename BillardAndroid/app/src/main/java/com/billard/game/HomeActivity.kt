package com.billard.game

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Bundle
import android.util.Log
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import java.io.IOException

class HomeActivity : Activity() {
    private val userCoins: Int by lazy { intent.getIntExtra("user_coins", 0) }
    private val userName: String by lazy { intent.getStringExtra("user_name") ?: "Profil" }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_home)
        try {
            val background = assets.open("flutter_assets/assets/images/background.png").use {
                BitmapFactory.decodeStream(it)
            }
            findViewById<ImageView>(R.id.home_background).setImageBitmap(background)
        } catch (error: IOException) {
            Log.w("BillardHome", "Kadri background asset unavailable; using billard background", error)
        }
        applyImmersiveMode()
        findViewById<TextView>(R.id.profile_name).text = userName
        findViewById<TextView>(R.id.wallet_balance).text = userCoins.toString()
        ProfileAvatarLoader.load(
            findViewById(R.id.profile_avatar),
            intent.getStringExtra("avatar_url"),
        )
        findViewById<View>(R.id.btn_friends).setOnClickListener {
            if (intent.getBooleanExtra("from_kadri", false)) {
                startActivity(
                    Intent().setClassName(packageName, "com.example.miloka.MainActivity")
                        .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                        .putExtra("openPoolFriends", true),
                )
                finish()
            } else {
                Toast.makeText(
                    this,
                    "Ouvrez le billard depuis Kadri pour accéder à vos amis.",
                    Toast.LENGTH_SHORT,
                ).show()
            }
        }
        findViewById<View>(R.id.btn_solo).setOnClickListener { chooseLevel() }
        findViewById<View>(R.id.btn_two).setOnClickListener { play(1) }
        findViewById<View>(R.id.btn_online).setOnClickListener {
            if (intent.getBooleanExtra("from_kadri", false)) {
                startActivity(
                    Intent().setClassName(packageName, "com.example.miloka.MainActivity")
                        .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                        .putExtra("openPoolOnline", true),
                )
                finish()
            } else {
                online()
            }
        }
        findViewById<View>(R.id.btn_kadri).setOnClickListener { finish() }
    }

    private fun play(mode: Int, role: String = "", ip: String = "", level: Int = 1) {
        startActivity(Intent(this, MainActivity::class.java)
            .putExtra("mode", mode).putExtra("role", role).putExtra("ip", ip)
            .putExtra("level", level).putExtra("user_coins", userCoins)
            .putExtra("user_name", userName)
            .putExtra("avatar_url", intent.getStringExtra("avatar_url")))
    }

    private fun chooseLevel() {
        AlertDialog.Builder(this).setTitle(R.string.choose_level)
            .setItems(resources.getStringArray(R.array.levels)) { _, which -> play(0, level = which) }
            .show()
    }

    private fun online() {
        val v = layoutInflater.inflate(R.layout.dialog_online, null)
        val d = AlertDialog.Builder(this).setView(v).create()
        v.findViewById<TextView>(R.id.my_ip).text = getString(R.string.your_address) + " " + Net.localIp()
        v.findViewById<Button>(R.id.btn_host).setOnClickListener { d.dismiss(); play(2, "host") }
        v.findViewById<Button>(R.id.btn_join).setOnClickListener {
            val ip = v.findViewById<EditText>(R.id.ip).text.toString().trim()
            if (ip.isNotEmpty()) { d.dismiss(); play(2, "join", ip) }
        }
        d.show()
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
