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
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build

/**
 * 到点提醒：AlarmManager 触发后弹出悬浮通知（大文本、点击回主界面、autoCancel）。
 * 渠道带闹钟铃声 + 震动 + 全屏意图：到点真的"响"起来，不跳转其他应用。
 * 整体 try/catch 静默，绝不影响主流程。
 */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // 先落触发记录：哪怕通知发不出去，开发者模式也能确认闹钟本体是否到点。
        val sp = context.getSharedPreferences("start_prefs", Context.MODE_PRIVATE)
        try {
            sp.edit()
                .putLong("last_alarm_fire", System.currentTimeMillis())
                .putString("last_alarm_label", intent.getStringExtra("label") ?: "")
                .apply()
        } catch (_: Exception) {
        }
        try {
            // 渠道可能因升级换 id 而未建过：先确保存在，通知才不会被系统静默丢弃。
            ReminderAlarm.ensureChannel(context)
            if (Build.VERSION.SDK_INT >= 33 &&
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                    != PackageManager.PERMISSION_GRANTED) {
                // 权限被拒：记下被拦时间，诊断页能直接看到「到点了但没权限」。
                sp.edit().putLong("last_alarm_blocked", System.currentTimeMillis()).apply()
                return
            }
            val id = intent.getIntExtra("id", 0)
            val label = intent.getStringExtra("label") ?: ""
            val lctx = AppLocale.wrap(context)
            val due = lctx.getString(R.string.reminder_due)
            val pi = PendingIntent.getActivity(context, id,
                context.packageManager.getLaunchIntentForPackage(context.packageName),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val n = Notification.Builder(context, ReminderAlarm.CHANNEL_NOTIFY)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(label)
                .setContentText(due)
                .setStyle(Notification.BigTextStyle().bigText(due))
                .setCategory(Notification.CATEGORY_ALARM)
                .setAutoCancel(true)
                .setFullScreenIntent(pi, true)
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
    // v2：换渠道 id 强制重建——渠道配置一经创建不可修改，老渠道没有闹钟铃声。
    const val CHANNEL_NOTIFY = "start_notify_v2"
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
        val lctx = AppLocale.wrap(context)
        val ch = NotificationChannel(CHANNEL_NOTIFY,
            lctx.getString(R.string.channel_notify),
            NotificationManager.IMPORTANCE_HIGH)
        // 闹钟铃声 + 震动：到点像系统闹钟一样响，不依赖系统通知音。
        val alarm = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        ch.setSound(alarm, AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build())
        ch.enableVibration(true)
        ch.vibrationPattern = longArrayOf(0, 500, 400, 500)
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .createNotificationChannel(ch)
    }

    /** 服药计划提醒 id：1500000000 + 计划id*1000 + 天序*10 + 时段序（与 Dart 侧 store.dart 完全一致）。 */
    fun medNotifyId(planId: Int, day: Int, slot: Int) =
        1_500_000_000 + planId * 1000 + day * 10 + slot

    /**
     * 注册到点闹钟：setAlarmClock 永远精确且无需 SCHEDULE_EXACT_ALARM 权限
     * （Android 14+ 对 targetSdk 34 默认不授予该权限，setExact 会降级非精确被
     * Doze 拖延到不准点），状态栏显示闹钟图标，语义就是应用内闹钟。
     */
    fun schedule(context: Context, id: Int, label: String, whenMs: Long) {
        ensureChannel(context)
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = pendingIntent(context, id, label)
        val show = PendingIntent.getActivity(context, id,
            context.packageManager.getLaunchIntentForPackage(context.packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        am.setAlarmClock(AlarmManager.AlarmClockInfo(whenMs, show), pi)
    }

    fun cancel(context: Context, id: Int) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(pendingIntent(context, id, ""))
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(id)
    }
}
