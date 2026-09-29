import 'dart:async';
import 'dart:convert';

/// 平台文件 IO：隔离 dart:io，Web 端用 localStorage 替代。
class PlatformIO {
  static Future<String> filesDir() async => '';
  static Future<String?> readFile(String path) async => null;
  static Future<bool> fileExists(String path) async => false;
  static Future<void> writeFile(String path, String content) async {}
  static Future<void> deleteFile(String path) async {}
}

/// 原生偏好读写。
class Prefs {
  static Future<Map<String, Object?>> getAll([String name = 'start_prefs']) async => {};
  static Future<void> set(String key, Object? value, [String name = 'start_prefs']) async {}
}

/// 系统能力：路径 / 震动 / 屏幕常亮 / 分词 / 音效 / 任意门动作。
class Native {
  static Future<String> filesDir() async => '';
  static Future<String?> versionName() async => null;
  static Future<int> calendarInsert(String title, int ms) async => 0;
  static Future<void> calendarDelete(int eventId) async {}
  static Future<void> vibrate([int ms = 20]) async {}
  static Future<void> keepScreenOn(bool on) async {}
  static Future<String?> initialShare() async => null;
  static Future<void> dial(String number) async {}
  static Future<void> openUrl(String url) async {}
  static Future<void> addToCalendar(String title, int ms) async {}
  static Future<void> setAlarm(String title, int ms, {bool daily = false}) async {}
  static Future<void> dismissAlarm(String title) async {}
  static Future<void> scheduleNotify(int id, String label, int whenMs) async {}
  static Future<void> cancelNotify(int id) async {}
  static Future<void> setKeepAlive(bool on) async {}
  static Future<void> setAppLocale(String languageTag) async {}
  static Future<Map<String, Object?>> alarmDiag() async => {};
  static Future<void> restart() async {}
  static Future<void> factoryReset() async {}
  static Future<void> openChannelSettings() async {}
  static Future<bool> ensureReminderPerms() async => true;
  static Future<List<Map<String, Object?>>> calendarToday() async => [];
  static Future<List<String>> words(String text) async => _simpleWords(text);
  static Future<void> tick(int volume) async {}
  static Future<void> chime() async {}
  static Future<void> stopChime() async {}

  /// Web 降级分词：按字符拆分（无 ICU 词典，仅保证不崩溃）。
  static List<String> _simpleWords(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return [];
    return trimmed.split('');
  }
}

/// 系统语音引擎（Web 不可用）。
class SystemVoice {
  static Stream<Map<String, Object?>> events() => const Stream.empty();
  static Future<void> start({bool online = false}) async {}
  static Future<void> stop() async {}
  static Future<bool> ensureMic() async => false;
  static Future<Map<String, Object?>> testOnline() async =>
      {'engines': <String>[], 'available': false, 'onDevice': false};
}

/// 文件导入导出（Web 端用浏览器下载/上传）。
class FileApi {
  static Future<bool> export(String json, [String name = 'start_data.json']) async => false;
  static Future<String?> import() async => null;
}

/// Vosk 离线语音识别（Web 不可用）。
class Voice {
  static Stream<Map<String, Object?>> events() => const Stream.empty();
  static Future<void> start() async {}
  static Future<void> stop() async {}
}
