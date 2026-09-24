package com.start.notes

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build

/**
 * 到点提醒：AlarmManager 触发后弹出悬浮通知（大文本、点击回主界面、autoCancel）。
 * 整体 try/catch 静默，绝不影响主流程。
 */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            if (Build.VERSION.SDK_INT >= 33 &&
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                    != PackageManager.PERMISSION_GRANTED) return
            val id = intent.getIntExtra("id", 0)
            val label = intent.getStringExtra("label") ?: ""
            val pi = PendingIntent.getActivity(context, id,
                context.packageManager.getLaunchIntentForPackage(context.packageName),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val n = Notification.Builder(context, ReminderAlarm.CHANNEL_NOTIFY)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(label)
                .setContentText("到点了")
                .setStyle(Notification.BigTextStyle().bigText("到点了"))
                .setCategory(Notification.CATEGORY_REMINDER)
                .setAutoCancel(true)
                .setContentIntent(pi)
                .build()
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .notify(id, n)
        } catch (_: Exception) {
        }
    }
}

/**
 * 闹钟/渠道公共逻辑：MainActivity（notifySchedule、notifyCancel、常驻通知）与
 * BootReceiver（开机重排）共用，保证 PendingIntent 构造完全一致，cancel 才能命中。
 */
object ReminderAlarm {
    const val CHANNEL_NOTIFY = "start_notify"
    const val CHANNEL_ONGOING = "start_ongoing"
    const val ONGOING_ID = 1001

    fun pendingIntent(context: Context, id: Int, label: String): PendingIntent {
        val i = Intent(context, ReminderReceiver::class.java).apply {
            putExtra("id", id)
            putExtra("label", label)
        }
        return PendingIntent.getBroadcast(context, id, i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    fun ensureChannel(context: Context) {
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .createNotificationChannel(
                NotificationChannel(CHANNEL_NOTIFY, "提醒", NotificationManager.IMPORTANCE_HIGH))
    }

    /** 注册到点闹钟；SDK>=31 无精确闹钟权限时降级为非精确 set。 */
    fun schedule(context: Context, id: Int, label: String, whenMs: Long) {
        ensureChannel(context)
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = pendingIntent(context, id, label)
        if (Build.VERSION.SDK_INT >= 31 && !am.canScheduleExactAlarms()) {
            am.set(AlarmManager.RTC_WAKEUP, whenMs, pi)
        } else {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, whenMs, pi)
        }
    }

    fun cancel(context: Context, id: Int) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(pendingIntent(context, id, ""))
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(id)
    }
}
