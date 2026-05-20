package com.linkguard.app.engine

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder

// =====================================================
//  LinkGuardForegroundService
//  低重要度前景服務：防止系統在任務切換時中斷連線
//  依附 MainActivity 生命週期，在 onResume/onPause 啟停
// =====================================================

class LinkGuardForegroundService : Service() {

    companion object {
        private const val CHANNEL_ID   = "linkguard_fg_service"
        private const val NOTIF_ID     = 9001

        fun start(context: Context) {
            val intent = Intent(context, LinkGuardForegroundService::class.java)
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, LinkGuardForegroundService::class.java))
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIF_ID, buildNotification())
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "LinkGuard 連線保持",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "維持前線設備連線狀態"
            setShowBadge(false)
        }
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("LinkGuard 運行中")
            .setContentText("前線連線保持中")
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setOngoing(true)
            .build()
    }
}
