package com.start.notes

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONObject
import java.io.File

/**
 * 开机自启：扫描 start_items.json，把未完成、排期在未来的任务闹钟重新注册，
 * 防止重启后到点提醒丢失。字段与 lib/data/item.dart 的 toJson 完全一致
 * （kind==0 任务、done 未完成、due 毫秒时间戳）。全程静默，出错直接放弃。
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        try {
            val f = File(context.filesDir, "start_items.json")
            if (!f.exists()) return
            val arr = JSONObject(f.readText()).optJSONArray("items") ?: return
            val now = System.currentTimeMillis()
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                val due = o.optLong("due")
                if (o.optInt("kind") != 0 || o.optBoolean("done") || due <= now) continue
                val t = o.optString("title").trim()
                ReminderAlarm.schedule(context, o.optInt("id"),
                    if (t.isNotEmpty()) t else "Start", due)
            }
        } catch (_: Exception) {
        }
    }
}
