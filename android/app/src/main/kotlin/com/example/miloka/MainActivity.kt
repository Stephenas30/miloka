package com.example.miloka

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
companion object {
    private var billardChannel: MethodChannel? = null

    @JvmStatic
    fun sendPoolMessage(message: String) {
        billardChannel?.invokeMethod("poolMessage", message)
    }

    @JvmStatic
    fun notifyPoolGameClosed() {
        billardChannel?.invokeMethod("poolGameClosed", null)
    }

    @JvmStatic
    fun notifyPoolGameFinished(winner: Int) {
        billardChannel?.invokeMethod("poolGameFinished", winner)
    }
}

override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    billardChannel =
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "miloka/billard")
    billardChannel?.setMethodCallHandler { call, result ->
        when (call.method) {
            "open" -> {
                startActivity(
                    Intent(this, com.billard.game.HomeActivity::class.java)
                        .putExtra("from_kadri", true)
                        .putExtra("user_coins", call.argument<Int>("userCoins") ?: 0)
                        .putExtra("user_name", call.argument<String>("userName") ?: "Profil")
                        .putExtra("avatar_url", call.argument<String>("avatarUrl") ?: "")
                )
                result.success(null)
            }
            "startOnlineGame" -> {
                val playerIndex = call.argument<Int>("playerIndex")
                val seed = call.argument<Long>("seed")
                if (playerIndex == null || seed == null) {
                    result.error("invalid_arguments", "Missing playerIndex or seed", null)
                } else {
                    startActivity(
                        Intent().setClassName(
                            packageName,
                            "com.billard.game.MainActivity",
                        )
                            .putExtra("mode", 2)
                            .putExtra("kadri_online", true)
                            .putExtra("player_index", playerIndex)
                            .putExtra("seed", seed)
                            .putExtra("host_bet", call.argument<Int>("hostBet") ?: 0)
                            .putExtra("guest_bet", call.argument<Int>("guestBet") ?: 0)
                            .putExtra("user_coins", call.argument<Int>("userCoins") ?: 0)
                            .putExtra("user_name", call.argument<String>("userName") ?: "Profil")
                            .putExtra("avatar_url", call.argument<String>("avatarUrl") ?: "")
                    )
                    result.success(null)
                }
            }
            "remotePoolMessage" -> {
                val message = call.arguments as? String
                if (message == null) {
                    result.error("invalid_arguments", "Missing game message", null)
                } else {
                    com.billard.game.MainActivity.receivePoolMessage(message)
                    result.success(null)
                }
            }
            "poolResultError" -> {
                val message = call.arguments as? String
                if (message == null) {
                    result.error("invalid_arguments", "Missing result error message", null)
                } else {
                    com.billard.game.MainActivity.showKadriMessage(message)
                    result.success(null)
                }
            }
            else -> result.notImplemented()
        }
    }
}

override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    if (intent.getBooleanExtra("openPoolOnline", false)) {
        intent.removeExtra("openPoolOnline")
        billardChannel?.invokeMethod("openPoolOnline", null)
    }
    if (intent.getBooleanExtra("openPoolFriends", false)) {
        intent.removeExtra("openPoolFriends")
        billardChannel?.invokeMethod("openPoolFriends", null)
    }
}
}