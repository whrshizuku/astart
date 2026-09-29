import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;

/// Web 端文件 IO：用 localStorage 模拟简单文件系统。
class PlatformIO {
  static const _prefix = '_file_';

  static Future<String> filesDir() async => 'web';

  static Future<String?> readFile(String path) async =>
      html.window.localStorage[_prefix + path];

  static Future<bool> fileExists(String path) async =>
      html.window.localStorage.containsKey(_prefix + path);

  static Future<void> writeFile(String path, String content) async =>
      html.window.localStorage[_prefix + path] = content;

  static Future<void> deleteFile(String path) async =>
      html.window.localStorage.remove(_prefix + path);
}

/// Web 端偏好：用 localStorage。
class Prefs {
  static const _prefix = '_prefs_';

  static Future<Map<String, Object?>> getAll([String name = 'start_prefs']) async {
    final p = '$name/';
    final r = <String, Object?>{};
    html.window.localStorage.forEach((k, v) {
      if (k.startsWith(p)) {
        final key = k.substring(p.length);
        try {
          r[key] = jsonDecode(v);
        } catch (_) {
          r[key] = v;
        }
      }
    });
    return r;
  }

  static Future<void> set(String key, Object? value, [String name = 'start_prefs']) async {
    final k = '$name/$key';
    if (value == null) {
      html.window.localStorage.remove(k);
    } else {
      html.window.localStorage[k] = jsonEncode(value);
    }
  }
}

/// 一次性注入 Web 端 JS 辅助函数（震动 / 屏幕常亮 / 音效 / 分词）。
/// 全部挂在 globalThis 上，Dart 侧用 [js.context.callMethod] 调用。
bool _webHelpersInited = false;
void _initWebHelpers() {
  if (_webHelpersInited) return;
  _webHelpersInited = true;
  final code = '''
globalThis._startVibrate = function(ms) {
  try { return navigator.vibrate ? navigator.vibrate(ms) : false; } catch(e) { return false; }
};
globalThis._startWakeLock = async function(on) {
  try {
    if (!on) {
      if (globalThis._startWakeSentinel) { globalThis._startWakeSentinel.release(); globalThis._startWakeSentinel = null; }
      return;
    }
    if (!navigator.wakeLock) return;
    globalThis._startWakeSentinel = await navigator.wakeLock.request('screen');
  } catch(e) {}
};
globalThis._startBeep = function(freq, durMs, vol) {
  try {
    var ctx = globalThis._startAudioCtx = globalThis._startAudioCtx || new (window.AudioContext || window.webkitAudioContext)();
    if (ctx.state === 'suspended') ctx.resume();
    var osc = ctx.createOscillator();
    var gain = ctx.createGain();
    osc.type = 'sine';
    osc.frequency.value = freq;
    gain.gain.value = vol;
    osc.connect(gain); gain.connect(ctx.destination);
    var now = ctx.currentTime;
    osc.start(now); osc.stop(now + durMs / 1000);
  } catch(e) {}
};
globalThis._startSeg = function(text) {
  try {
    if (typeof Intl === 'undefined' || !Intl.Segmenter) return null;
    var seg = new Intl.Segmenter('zh', {granularity: 'word'});
    var out = [];
    for (var s of seg.segment(text)) {
      if (s.isWordLike && s.segment.trim()) out.push(s.segment);
    }
    return JSON.stringify(out);
  } catch(e) { return null; }
};
''';
  try {
    html.document.body!.append(html.ScriptElement()..text = code);
  } catch (_) {}
}

/// Web 端系统能力：用浏览器 API 替代 Android 原生能力。
/// 通知 → Web Notifications；震动 → navigator.vibrate；屏幕常亮 → Wake Lock；
/// 音效 → Web Audio；分词 → Intl.Segmenter（zh）；系统闹钟 → 到点通知（页面开着时有效）。
class Native {
  static Future<String> filesDir() async => 'web';

  /// 写死版本号（Web 端读不到 build.gradle；改版本时同步更新这里）。
  static Future<String?> versionName() async => '2.3.2';

  // 日历：Web 无系统日历，全部空实现。
  static Future<int> calendarInsert(String title, int ms) async => 0;
  static Future<void> calendarDelete(int eventId) async {}
  static Future<void> addToCalendar(String title, int ms) async {}
  static Future<List<Map<String, Object?>>> calendarToday() async => [];

  static Future<void> vibrate([int ms = 20]) async {
    _initWebHelpers();
    try {
      js.context.callMethod('_startVibrate', [ms]);
    } catch (_) {}
  }

  static Future<void> keepScreenOn(bool on) async {
    _initWebHelpers();
    try {
      await js.context.callMethod('_startWakeLock', [on]);
    } catch (_) {}
  }

  static Future<String?> initialShare() async => null;
  static Future<void> dial(String number) async {}

  static Future<void> openUrl(String url) async {
    html.window.open(url, '_blank');
  }

  // ---------------- 系统闹钟（服药）/ 到点提醒 ----------------
  // Web 上没有系统闹钟，用 Notification + setTimeout 替代：页面开着时到点弹通知。
  // daily 模式仅当天有效（页面刷新后 rearmAll 会重挂）。
  static final Map<int, Timer> _notifyTimers = {};
  static final Map<String, Timer> _alarmTimers = {};

  static Future<void> setAlarm(String title, int ms, {bool daily = false}) async {
    await dismissAlarm(title);
    final delay = ms - DateTime.now().millisecondsSinceEpoch;
    if (delay <= 0) return;
    _alarmTimers[title] =
        Timer(Duration(milliseconds: delay), () => _showNotif(title, '服药提醒'));
  }

  static Future<void> dismissAlarm(String title) async {
    _alarmTimers[title]?.cancel();
    _alarmTimers.remove(title);
  }

  static Future<void> scheduleNotify(int id, String label, int whenMs) async {
    await cancelNotify(id);
    final delay = whenMs - DateTime.now().millisecondsSinceEpoch;
    if (delay <= 0) {
      _showNotif(label, '启序 Start');
      return;
    }
    _notifyTimers[id] =
        Timer(Duration(milliseconds: delay), () => _showNotif(label, '启序 Start'));
  }

  static Future<void> cancelNotify(int id) async {
    _notifyTimers[id]?.cancel();
    _notifyTimers.remove(id);
  }

  /// 弹通知：权限未授予则先请求；denied 静默跳过。
  static void _showNotif(String title, String body) {
    try {
      if (html.Notification.supported != true) return;
      if (html.Notification.permission == 'granted') {
        html.Notification(title, body: body, icon: 'favicon.png');
      } else if (html.Notification.permission == 'default') {
        html.Notification.requestPermission().then((p) {
          if (p == 'granted') html.Notification(title, body: body, icon: 'favicon.png');
        });
      }
    } catch (_) {}
  }

  // ---------------- 偏好 / 诊断 / 重启 ----------------
  static Future<void> setKeepAlive(bool on) async {} // Web 无常驻通知
  static Future<void> setAppLocale(String languageTag) async {}

  static Future<Map<String, Object?>> alarmDiag() async => {
        'notifPermission': html.Notification.supported == true
            ? html.Notification.permission
            : 'unsupported',
        'notificationsEnabled':
            html.Notification.supported == true && html.Notification.permission == 'granted',
        'channelExists': true,
        'channelImportance': 4,
        'notifyOn': true,
        'keepAlive': false,
        'nextAlarmAt': 0,
      };

  static Future<void> restart() async {
    html.window.location.reload();
  }

  /// 恢复出厂：清 localStorage 后刷新回首屏。
  static Future<void> factoryReset() async {
    try {
      html.window.localStorage.clear();
    } catch (_) {}
    html.window.location.reload();
  }

  static Future<void> openChannelSettings() async {}

  /// 确保提醒权限：请求 Web 通知授权（granted=true / denied=false / default 弹框）。
  static Future<bool> ensureReminderPerms() async {
    try {
      if (html.Notification.supported != true) return false;
      final p = html.Notification.permission;
      if (p == 'granted') return true;
      if (p == 'denied') return false;
      final r = await html.Notification.requestPermission();
      return r == 'granted';
    } catch (_) {
      return false;
    }
  }

  // ---------------- 分词（Intl.Segmenter 中文词级） ----------------
  static Future<List<String>> words(String text) async {
    final t = text.trim();
    if (t.isEmpty) return [];
    _initWebHelpers();
    try {
      final r = js.context.callMethod('_startSeg', [t]);
      if (r is String) {
        final list = jsonDecode(r) as List;
        return list.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return _simpleWords(t);
  }

  /// 降级分词：按字符拆分（浏览器不支持 Intl.Segmenter 时兜底）。
  static List<String> _simpleWords(String text) => text.split('');

  // ---------------- 音效（Web Audio） ----------------
  static Future<void> tick(int volume) async {
    _initWebHelpers();
    final v = ((volume ?? 70) / 100).clamp(0.0, 1.0) * 0.25;
    try {
      js.context.callMethod('_startBeep', [1000, 28, v]);
    } catch (_) {}
  }

  static Future<void> chime() async {
    _initWebHelpers();
    try {
      js.context.callMethod('_startBeep', [880, 200, 0.2]);
      await Future.delayed(const Duration(milliseconds: 160));
      js.context.callMethod('_startBeep', [1175, 320, 0.2]);
    } catch (_) {}
  }

  static Future<void> stopChime() async {}
}

/// Web 端系统语音：浏览器 SpeechRecognition（保留接口，语音速记已从主功能移除）。
class SystemVoice {
  static Stream<Map<String, Object?>> events() => const Stream.empty();
  static Future<void> start({bool online = false}) async {}
  static Future<void> stop() async {}
  static Future<bool> ensureMic() async => false;
  static Future<Map<String, Object?>> testOnline() async =>
      {'engines': <String>[], 'available': false, 'onDevice': false};
}

/// Web 端文件导入导出：浏览器下载 / 文件上传。
class FileApi {
  static Future<bool> export(String json, [String name = 'start_data.json']) async {
    try {
      final blob = html.Blob([json], 'application/json');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement()
        ..href = url
        ..download = name
        ..style.display = 'none';
      html.document.body!.append(anchor);
      anchor.click();
      anchor.remove();
      html.Url.revokeObjectUrl(url);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> import() async {
    final completer = Completer<String?>();
    final input = html.FileUploadInputElement()..accept = '.json';
    input.onChange.listen((_) {
      final files = input.files;
      if (files == null || files.isEmpty) {
        if (!completer.isCompleted) completer.complete(null);
        return;
      }
      final reader = html.FileReader();
      reader.onLoadEnd.listen((_) {
        if (!completer.isCompleted) completer.complete(reader.result as String?);
      });
      reader.onError.listen((_) {
        if (!completer.isCompleted) completer.complete(null);
      });
      reader.readAsText(files.first);
    });
    input.click();
    return completer.future;
  }
}

/// Web 端 Vosk 语音识别：不可用（语音速记已移至开发者模式，Web 上不启用）。
class Voice {
  static Stream<Map<String, Object?>> events() => const Stream.empty();
  static Future<void> start() async {}
  static Future<void> stop() async {}
}
