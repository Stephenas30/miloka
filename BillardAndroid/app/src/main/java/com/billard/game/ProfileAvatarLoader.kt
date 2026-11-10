package com.billard.game

import android.graphics.BitmapFactory
import android.util.Log
import android.widget.ImageView
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

object ProfileAvatarLoader {
    fun load(imageView: ImageView, avatarUrl: String?) {
        if (avatarUrl.isNullOrBlank()) return

        Thread {
            var connection: HttpURLConnection? = null
            try {
                val url = URL(avatarUrl)
                require(url.protocol == "https") { "Profile avatar must use HTTPS" }
                connection = url.openConnection() as HttpURLConnection
                connection.connectTimeout = 5000
                connection.readTimeout = 5000
                connection.instanceFollowRedirects = false
                val bitmap = connection.inputStream.use { BitmapFactory.decodeStream(it) }
                    ?: throw IOException("Profile avatar could not be decoded")
                imageView.post {
                    if (imageView.isAttachedToWindow) {
                        imageView.setPadding(0, 0, 0, 0)
                        imageView.setImageBitmap(bitmap)
                    }
                }
            } catch (error: IOException) {
                Log.w("BillardProfile", "Unable to load profile avatar", error)
            } catch (error: IllegalArgumentException) {
                Log.w("BillardProfile", "Unable to load profile avatar", error)
            } finally {
                connection?.disconnect()
            }
        }.start()
    }
}
