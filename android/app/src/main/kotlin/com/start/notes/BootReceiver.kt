package com.start.notes

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONObject
import java.io.File
import java.util.Calendar

/**
 * 开机自启：扫描 start_items.json 重排到点闹钟，防止重启后提醒丢失。
 *  - 任务（kind==0）：未完成、due 在未来 → 按 due 重挂；
 *  - 服药计划（kind==3 且 parent==0）：解析 note JSON，逐日逐时段重挂（30 天滚动窗口）。
 * 字段与 lib/data/item.dart 的 toJson 完全一致。全程静默，出错直接放弃。
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        try {
            val f = File(context.filesDir, "start_items.json")
            if (!f.exists()) return
            val arr = JSONObject(f.readText()).optJSONArray("items") ?: return
            val now = System.currentTimeMillis()
            val notifyOn = context.getSharedPreferences("start_prefs", Context.MODE_PRIVATE)
                .getBoolean("notify_on", true)
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i) ?: continue
                val kind = o.optInt("kind")
                if (kind == 3 && o.optInt("parent") == 0) {
                    if (notifyOn) armMedPlan(context, o, now)
                    continue
                }
                val due = o.optLong("due")
                if (kind != 0 || o.optBoolean("done") || due <= now) continue
                val t = o.optString("title").trim()
                ReminderAlarm.schedule(context, o.optInt("id"),
                    if (t.isNotEmpty()) t else "Start", due)
            }
        } catch (_: Exception) {
        }
    }

    /** 服药计划重挂：逐日逐时段独立 id（公式与 Dart store.dart 的 medNotifyId 一致）。 */
    private fun armMedPlan(context: Context, o: JSONObject, now: Long) {
        val meta = JSONObject(o.optString("note"))
        val times = meta.optJSONArray("times") ?: return
        val start = meta.optLong("start")
        val end = meta.optLong("end")
        val title = o.optString("title").trim().ifEmpty { "Start" }
        val dose = meta.optString("dose").trim()
        val label = if (dose.isEmpty()) title else "$title · $dose"
        val base = Calendar.getInstance().apply {
            timeInMillis = now
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        for (d in 0 until 30) {
            val day = (base.clone() as Calendar).apply {
                add(Calendar.DAY_OF_MONTH, d)
            }
            val dayMs = day.timeInMillis
            if (start > 0 && dayMs < start) continue
            if (end > 0 && dayMs > end) continue
            for (i in 0 until times.length()) {
                val parts = times.optString(i).split(":")
                val h = parts.getOrNull(0)?.trim()?.toIntOrNull() ?: 8
                val m = parts.getOrNull(1)?.trim()?.toIntOrNull() ?: 0
                val at = (day.clone() as Calendar).apply {
                    set(Calendar.HOUR_OF_DAY, h)
                    set(Calendar.MINUTE, m)
                    set(Calendar.SECOND, 0)
                    set(Calendar.MILLISECOND, 0)
                }
                val whenMs = at.timeInMillis
                if (whenMs <= now) continue
                ReminderAlarm.schedule(context,
                    ReminderAlarm.medNotifyId(o.optInt("id"), d, i), label, whenMs)
            }
        }
    }
}
