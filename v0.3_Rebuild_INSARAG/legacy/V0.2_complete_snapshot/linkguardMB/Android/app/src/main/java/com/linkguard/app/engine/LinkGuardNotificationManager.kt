package com.linkguard.app.engine

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.linkguard.app.R
import com.linkguard.app.model.CommandOrder

class LinkGuardNotificationManager(private val context: Context) {

    companion object {
        private const val CHANNEL_SOS     = "linkguard_sos"
        private const val CHANNEL_DEVICE  = "linkguard_device"
        private const val CHANNEL_COMMAND = "linkguard_command"
    }

    init {
        createChannels()
    }

    private fun createChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val sosCh = NotificationChannel(CHANNEL_SOS, "SOS 警報", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "緊急 SOS 求救警報"
                enableLights(true)
                enableVibration(true)
                setBypassDnd(true)
            }
            mgr.createNotificationChannel(sosCh)
            mgr.createNotificationChannel(
                NotificationChannel(CHANNEL_DEVICE, "裝置通知", NotificationManager.IMPORTANCE_DEFAULT)
            )
            val cmdCh = NotificationChannel(CHANNEL_COMMAND, "指揮命令", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "指揮中心命令通知"
                enableLights(true)
                enableVibration(true)
            }
            mgr.createNotificationChannel(cmdCh)
        }
    }

    fun sendSOSNotification(victimID: String, heartRate: Int, distance: String) {
        val hr = if (heartRate > 0) "$heartRate bpm" else "-- bpm"
        send(
            CHANNEL_SOS,
            "SOS 求救警報",
            "$victimID · 心率: $hr · 距離: ~$distance",
            "sos-$victimID".hashCode()
        )
    }

    fun sendOfflineNotification(victimID: String) {
        send(
            CHANNEL_DEVICE,
            "裝置離線",
            "$victimID 已失去訊號連線",
            "offline-$victimID".hashCode()
        )
    }

    fun sendLowBatteryNotification(victimID: String, battery: Int) {
        send(
            CHANNEL_DEVICE,
            "低電量警告",
            "$victimID 電量僅剩 ${battery}%",
            "battery-$victimID".hashCode()
        )
    }

    fun sendCommandNotification(order: CommandOrder) {
        send(
            CHANNEL_COMMAND,
            "指揮中心：${order.priority.label}",
            "${order.title} — ${order.detail}",
            "cmd-${order.id}".hashCode()
        )
    }

    private fun send(channel: String, title: String, text: String, id: Int) {
        try {
            val notification = NotificationCompat.Builder(context, channel)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(title)
                .setContentText(text)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .build()
            NotificationManagerCompat.from(context).notify(id, notification)
        } catch (_: SecurityException) {
            // 使用者尚未授權通知
        }
    }
}
