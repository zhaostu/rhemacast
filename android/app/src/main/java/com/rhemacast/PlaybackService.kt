package com.rhemacast

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Foreground service keeping the WebRTC PeerConnection alive during
 * background playback. UI observes [status] / [stats] StateFlows.
 */
class PlaybackService : Service() {

    companion object {
        const val ACTION_START = "com.rhemacast.ACTION_START"
        const val ACTION_STOP = "com.rhemacast.ACTION_STOP"
        const val EXTRA_IP = "extra_ip"
        private const val CHANNEL_ID = "rhemacast_playback"
        private const val NOTIF_ID = 1

        private val _status = MutableStateFlow("Idle")
        val status = _status.asStateFlow()
        private val _stats = MutableStateFlow("")
        val stats = _stats.asStateFlow()

        fun start(context: Context, ip: String) {
            val i = Intent(context, PlaybackService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_IP, ip)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(i)
            } else {
                context.startService(i)
            }
        }

        fun stop(context: Context) {
            context.startService(
                Intent(context, PlaybackService::class.java).setAction(ACTION_STOP)
            )
        }
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var client: WebRTCClient? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                scope.launch {
                    client?.disconnect()
                    client?.release()
                    client = null
                    _status.value = "Disconnected"
                    _stats.value = ""
                }
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START -> {
                val ip = intent.getStringExtra(EXTRA_IP).orEmpty()
                startForegroundWithType()
                if (client == null) {
                    client = WebRTCClient(applicationContext, object : WebRTCClient.Listener {
                        override fun onStatus(s: String) { _status.value = s }
                        override fun onStats(s: String) { _stats.value = s }
                    })
                }
                scope.launch(Dispatchers.Default) { client?.connect(ip) }
                return START_STICKY
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        scope.launch {
            client?.disconnect()
            client?.release()
            client = null
        }
        scope.cancel()
        super.onDestroy()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_ID, "Playback", NotificationManager.IMPORTANCE_LOW
                    )
                )
            }
        }
    }

    private fun startForegroundWithType() {
        // Tap notification -> back to the app UI (singleTop: no duplicate screens).
        val openApp = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java)
                .setAction(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_LAUNCHER)
                .setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stop = PendingIntent.getService(
            this, 1,
            Intent(this, PlaybackService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification: Notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("Rhemacast")
                .setContentText("Receiving audio…")
                .setSmallIcon(android.R.drawable.ic_media_play)
                .setContentIntent(openApp)
                .addAction(android.R.drawable.ic_media_pause, "Stop", stop)
                .setOngoing(true)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("Rhemacast")
                .setContentText("Receiving audio…")
                .setSmallIcon(android.R.drawable.ic_media_play)
                .setContentIntent(openApp)
                .addAction(android.R.drawable.ic_media_pause, "Stop", stop)
                .setOngoing(true)
                .build()
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIF_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(NOTIF_ID, notification)
        }
    }
}
