package com.start.notes

import android.app.LocaleManager
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.os.LocaleList
import java.util.Locale

/**
 * 应用内语言。
 * API 33+：走系统每应用语言（Locales 持久化，桌面图标名随之切换）。
 * API 29-32：无系统级接口，用保存的标记包装 Resources Configuration，
 * 至少让进程内的原生文案跟随；Flutter 界面始终由 Dart 侧自行切换。
 */
object AppLocale {
    private const val PREF = "start_locale"
    private const val KEY = "tag"

    fun savedTag(ctx: Context): String =
        ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE).getString(KEY, "") ?: ""

    fun apply(ctx: Context, tag: String) {
        ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE).edit().putString(KEY, tag).apply()
        if (Build.VERSION.SDK_INT >= 33) {
            val lm = ctx.getSystemService(LocaleManager::class.java)
            lm.applicationLocales =
                if (tag.isEmpty()) LocaleList.getEmptyLocaleList()
                else LocaleList.forLanguageTags(tag)
        }
    }

    /** 用保存的语言包装 Context；空标记或 API 33+（系统自管）时原样返回。 */
    fun wrap(base: Context): Context {
        if (Build.VERSION.SDK_INT >= 33) return base
        val tag = savedTag(base)
        if (tag.isEmpty()) return base
        val cfg = Configuration(base.resources.configuration)
        cfg.setLocale(Locale.forLanguageTag(tag))
        return base.createConfigurationContext(cfg)
    }
}
