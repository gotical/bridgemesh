package io.bridgemesh.bridgemesh

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

/**
 * Foreground Service, который держит приложение живым
 * в фоне, пока работает mesh-сеть.
 *
 * Запускается из MainActivity.startMeshService() и останавливается
 * из MainActivity.stopMeshService().
 *
 * Уведомление в шторке показывает пользователю, что BridgeMesh
 * активен и работает в фоне (Android требует foreground-уведомления,
 * если приложение постоянно что-то делает).
 */
class MeshForegroundService : Service() {

    companion object {
        private const val CHANNEL_ID = "bridgemesh_mesh"
        private const val NOTIF_ID = 7311
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
        startForegroundWithNotification()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // START_STICKY — система попробует перезапустить сервис,
        // если он умрёт (например, из-за нехватки памяти).
        return START_STICKY
    }

    private fun ensureChannel() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val ch = NotificationChannel(
                    CHANNEL_ID,
                    "Mesh-сеть работает",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "BridgeMesh поддерживает связь в фоне"
                    setShowBadge(false)
                }
                nm.createNotificationChannel(ch)
            }
        }
    }

    private fun startForegroundWithNotification() {
        val openIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pi = openIntent?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        val notif = builder
            .setContentTitle("BridgeMesh работает")
            .setContentText("Ищу соседей и передаю сообщения")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setContentIntent(pi)
            .setPriority(
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O)
                    Notification.PRIORITY_LOW
                else
                    Notification.PRIORITY_LOW,
            )
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // Android 14+ требует указывать foregroundServiceType.
            startForeground(
                NOTIF_ID,
                notif,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE or
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIF_ID, notif)
        }
    }
}
