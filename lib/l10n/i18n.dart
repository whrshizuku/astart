import 'package:flutter/material.dart';

import '../channels/native.dart';
import '../data/store.dart';
import 'translations.dart';

/// 支持的界面语言。简体中文为开发母语，其余语言由 AI 翻译（设置页与说明书中均有声明）。
class Lang {
  /// 用户在设置中的选择：system 跟随系统，其余为 BCP-47 语言标记。
  static const prefKey = 'app_locale';
  static const system = 'system';
  static const zhCN = 'zh-CN';
  static const zhTW = 'zh-TW';
  static const en = 'en';
  static const ja = 'ja';

  /// 设置页选项（值, 母语自名）。自名用各语言自己的写法，用户一看便知。
  static const options = <(String, String)>[
    (system, '跟随系统'),
    (zhCN, '简体中文'),
    (zhTW, '繁體中文'),
    (en, 'English'),
    (ja, '日本語'),
  ];

  /// 当前实际生效的语言标记（已把 system 解析为具体语言）。
  static String current = zhCN;

  /// 把系统 Locale 归并到四种受支持语言之一，中文语境外一律英语兜底。
  static String resolveDevice(Locale? loc) {
    if (loc == null) return zhCN;
    if (loc.languageCode == 'zh') {
      final region = loc.scriptCode == 'Hant' ||
              loc.countryCode == 'TW' ||
              loc.countryCode == 'HK' ||
              loc.countryCode == 'MO'
          ? zhTW
          : zhCN;
      return region;
    }
    if (loc.languageCode == 'ja') return ja;
    if (loc.languageCode == 'en') return en;
    // 其他语种没有翻译，按用户要求统一落到英语界面。
    return en;
  }

  /// 读取用户偏好并解析出当前语言。
  static String resolve() {
    final pref = StartStore.I.prefStr(prefKey, system);
    if (pref == system) return resolveDevice(
        WidgetsBinding.instance.platformDispatcher.locale);
    return pref;
  }

  /// 保存选择、同步原生侧（桌面图标名等）。界面刷新由 StartStore 监听驱动。
  static Future<void> choose(String value) async {
    await StartStore.I.setPref(prefKey, value);
    final tag = value == system ? '' : value;
    await Native.setAppLocale(tag);
  }

  /// 桌标应用名：仅简体中文显示「启序」，其余语言统一 Start。
  static String appNameOf(String tag) => tag == zhCN ? '启序' : 'Start';
}

/// 翻译：以简体中文原文为 key，查当前语言词典；查不到就原样显示中文。
///
/// 占位符用 {0} {1}：tr('删了 {0} 条', [n])。
String tr(String zh, [List<Object?>? args]) {
  var out = zh;
  if (Lang.current != Lang.zhCN) {
    out = _translations[Lang.current]?[zh] ?? zh;
  }
  if (args != null) {
    for (var i = 0; i < args.length; i++) {
      out = out.replaceAll('{$i}', '${args[i]}');
    }
  }
  return out;
}

/// 各语言词典，key 一律为简体中文原文。见 translations.dart。
final Map<String, Map<String, String>> _translations = translations;
