import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:vosk_flutter/vosk_flutter.dart';

/// 原生偏好读写：直接操作同名 SharedPreferences，保证与老版数据兼容。
/// 注意：不能用 shared_preferences 插件（它会给键加 "flutter." 前缀）。
class Prefs {
  static const _ch = MethodChannel('start/prefs');

  static Future<Map<String, Object?>> getAll([String name = 'start_prefs']) async {
    final r = await _ch.invokeMethod<dynamic>('getAll', {'name': name});
    return (r as Map<Object?, Object?>? ?? {}).cast<String, Object?>();
  }

  static Future<void> set(String key, Object? value, [String name = 'start_prefs']) =>
      _ch.invokeMethod('set', {'name': name, 'key': key, 'value': value});
}

/// 系统能力：路径 / 震动 / 屏幕常亮 / 分享接收 / 分词 / 音效 / 任意门动作（拨号、打开链接）。
class Native {
  static const _sys = MethodChannel('start/system');
  static const _seg = MethodChannel('start/segment');
  static const _snd = MethodChannel('start/sound');

  static Future<String> filesDir() async =>
      (await _sys.invokeMethod<String>('filesDir')) ?? '';

  /// 包版本名（PackageManager 实时读，自动跟随 build.gradle）。
  static Future<String?> versionName() => _sys.invokeMethod<String?>('versionName');

  /// 把日程写入手机日历，返回 eventId（0=失败/无权限，调用方可退回系统日历新建页）。
  static Future<int> calendarInsert(String title, int ms) async =>
      (await _sys.invokeMethod<int>('calendarInsert', {'title': title, 'ms': ms})) ?? 0;

  /// 删除此前写入的日历事件（编辑/删除服药计划时回收旧事件，防重复堆积）。
  static Future<void> calendarDelete(int eventId) =>
      _sys.invokeMethod('calendarDelete', {'id': eventId});

  static Future<void> vibrate([int ms = 20]) => _sys.invokeMethod('vibrate', {'ms': ms});

  static Future<void> keepScreenOn(bool on) => _sys.invokeMethod('keepScreenOn', {'on': on});

  static Future<String?> initialShare() => _sys.invokeMethod<String?>('initialShare');

  /// 任意门：拨号 / 打开链接（走系统 Intent，不联网）。
  static Future<void> dial(String number) =>
      _sys.invokeMethod('openAction', {'kind': 'dial', 'data': number});
  static Future<void> openUrl(String url) =>
      _sys.invokeMethod('openAction', {'kind': 'url', 'data': url});

  /// 绑定手机日历与系统闹钟：用系统 Intent，不申请额外权限、不联网。
  /// daily=true 时系统闹钟按每日重复（服药计划用）。
  static Future<void> addToCalendar(String title, int ms) =>
      _sys.invokeMethod('calendar', {'title': title, 'ms': ms});
  static Future<void> setAlarm(String title, int ms, {bool daily = false}) =>
      _sys.invokeMethod('alarm', {'title': title, 'ms': ms, 'daily': daily});

  /// 按标签撤掉系统闹钟（服药计划改名/删除时防残留）。
  static Future<void> dismissAlarm(String title) =>
      _sys.invokeMethod('dismissAlarm', {'title': title});

  /// 本地到点提醒：AlarmManager 精确闹钟 + 悬浮通知，无需第三方推送。
  static Future<void> scheduleNotify(int id, String label, int whenMs) =>
      _sys.invokeMethod('notifySchedule', {'id': id, 'label': label, 'when': whenMs});
  static Future<void> cancelNotify(int id) =>
      _sys.invokeMethod('notifyCancel', {'id': id});

  /// 后台保活常驻通知开关（true=显示"今日待办守护中"，false=移除）。
  static Future<void> setKeepAlive(bool on) =>
      _sys.invokeMethod('setKeepAlive', {'on': on});

  /// 应用内语言覆盖（Android 13+ 同步系统每应用语言与桌面图标名；空串恢复跟随系统）。
  static Future<void> setAppLocale(String languageTag) =>
      _sys.invokeMethod('setAppLocale', {'tag': languageTag});

  /// 闹钟链路诊断：{notifPermission, notificationsEnabled, channelExists,
  /// channelImportance, notifyOn, keepAlive, nextAlarmAt}。
  static Future<Map<String, Object?>> alarmDiag() async {
    final r = await _sys.invokeMethod<Map<Object?, Object?>>('alarmDiag');
    return (r ?? {}).cast<String, Object?>();
  }

  /// 强制重启：杀进程后由系统闹钟 400ms 内拉回启动页。
  static Future<void> restart() => _sys.invokeMethod('restart');

  /// 恢复出厂：撤通知、删数据与偏好后重启回到首启协议页。
  static Future<void> factoryReset() => _sys.invokeMethod('factoryReset');

  /// 打开系统通知渠道设置页（检查提醒渠道是否被静音/降级）。
  static Future<void> openChannelSettings() =>
      _sys.invokeMethod('openChannelSettings');

  /// 确保提醒相关权限（通知+日历）：服药计划保存前调用。
  /// 已全授予返回 true，否则弹系统申请框并返回 false。
  static Future<bool> ensureReminderPerms() async =>
      await _sys.invokeMethod<bool>('ensureReminderPerms') ?? true;

  /// 读取今日手机日历事件（移植自老版 Cal.today）。
  /// 返回 [{id,title,begin,end,calName}]。无权限时返回空并触发系统授权弹窗。
  static Future<List<Map<String, Object?>>> calendarToday() async {
    final r = await _sys.invokeMethod<List<Object?>>('calendarToday');
    return (r ?? []).map((e) {
      final m = (e as Map<Object?, Object?>).cast<String, Object?>();
      return {
        'id': (m['id'] as num?)?.toInt() ?? 0,
        'title': (m['title'] as String?) ?? '',
        'begin': (m['begin'] as num?)?.toInt() ?? 0,
        'end': (m['end'] as num?)?.toInt() ?? 0,
        'calName': (m['calName'] as String?) ?? '',
      };
    }).toList();
  }

  /// 词级分词（ICU 词典，BreakIterator Locale.CHINA），返回去掉首尾标点的词列表。
  static Future<List<String>> words(String text) async {
    final r = await _seg.invokeMethod<List<Object?>>('words', {'text': text});
    return (r ?? []).map((e) => e.toString()).toList();
  }

  static Future<void> tick(int volume) => _snd.invokeMethod('tick', {'volume': volume});

  static Future<void> chime() => _snd.invokeMethod('chime');

  static Future<void> stopChime() => _snd.invokeMethod('stopChime');
}

/// 系统语音引擎（厂商自研离线优先）。事件：{type: ready|partial|final|end|error|rms, text}。
class SystemVoice {
  static const _ch = MethodChannel('start/voice');
  static const _evt = EventChannel('start/voice/evt');
  static Stream<Map<String, Object?>>? _events;

  static Stream<Map<String, Object?>> events() {
    return _events ??= _evt.receiveBroadcastStream().map((e) {
      final m = (e as Map<Object?, Object?>).cast<String, Object?>();
      return m;
    });
  }

  /// [online]=true 时允许系统在线识别（更准但走网络）；默认 false 强制离线优先。
  static Future<void> start({bool online = false}) =>
      _ch.invokeMethod('start', {'online': online});
  static Future<void> stop() => _ch.invokeMethod('stop');

  /// 确保麦克风权限（Vosk 离线引擎走插件侧，权限需在原生侧单独申请）。
  static Future<bool> ensureMic() async =>
      (await _ch.invokeMethod<bool>('ensureMic')) ?? false;

  /// 在线语音测试：返回 {engines: List<String>, available: bool, onDevice: bool}。
  static Future<Map<String, Object?>> testOnline() async {
    final r = await _ch.invokeMethod<Map<Object?, Object?>>('testOnline');
    return (r ?? {}).cast<String, Object?>();
  }
}

/// 文件导入导出：走系统 SAF（ACTION_CREATE_DOCUMENT / ACTION_OPEN_DOCUMENT），
/// 用户选择保存位置或文件，不联网、不需存储权限。
class FileApi {
  static const _ch = MethodChannel('start/file');

  static Future<bool> export(String json, [String name = 'start_data.json']) async {
    final r = await _ch.invokeMethod<bool>('export', {'json': json, 'name': name});
    return r ?? false;
  }

  static Future<String?> import() => _ch.invokeMethod<String?>('import');
}

/// 语音识别：Vosk 离线引擎（开源，中文模型，首次联网下载模型后离线识别）。
/// 不绑谷歌、不依赖手机系统语音服务。事件流：{type: loading|ready|partial|final|end|error, text}
/// loading=首次下载模型中（text=百分比 0-100）；模型常驻内存，之后启动即听。
class Voice {
  static const _modelName = 'vosk-model-small-cn-0.22';

  static final _plugin = VoskFlutterPlugin.instance();
  static Model? _model;
  static Recognizer? _recognizer;
  static SpeechService? _service;
  static StreamSubscription? _resultSub;
  static StreamSubscription? _partialSub;
  static StreamController<Map<String, Object?>>? _ctl;
  static Future<void>? _starting;

  static Stream<Map<String, Object?>> events() {
    _ctl ??= StreamController<Map<String, Object?>>.broadcast();
    return _ctl!.stream;
  }

  /// 幂等：并发/重复调用共用同一次启动，避免重复下载与重复建引擎。
  static Future<void> start() =>
      _starting ??= _doStart().whenComplete(() => _starting = null);

  static Future<void> _doStart() async {
    _ctl ??= StreamController<Map<String, Object?>>.broadcast();
    try {
      if (_service == null) {
        _ctl!.add({'type': 'loading', 'text': ''});
        final dir = await Native.filesDir();
        final modelPath = await _ensureModel('$dir/models');
        _model ??= await _plugin.createModel(modelPath);
        _recognizer ??=
            await _plugin.createRecognizer(model: _model!, sampleRate: 16000);
        _service = await _plugin.initSpeechService(_recognizer!);

        _resultSub = _service!.onResult().listen((s) {
          try {
            final t = jsonDecode(s)['text'] as String? ?? '';
            if (t.isNotEmpty) _ctl!.add({'type': 'final', 'text': t});
          } catch (_) {}
        });
        _partialSub = _service!.onPartial().listen((s) {
          try {
            final t = jsonDecode(s)['partial'] as String? ?? '';
            if (t.isNotEmpty) _ctl!.add({'type': 'partial', 'text': t});
          } catch (_) {}
        });
      }
      _ctl!.add({'type': 'ready', 'text': ''});
      await _service!.start();
    } catch (e) {
      await _resetService();
      _ctl!.add({'type': 'error', 'text': '$e'});
    }
  }

  static Future<void> _resetService() async {
    await _resultSub?.cancel();
    _resultSub = null;
    await _partialSub?.cancel();
    _partialSub = null;
    try { await _service?.dispose(); } catch (_) {}
    _service = null;
    _recognizer = null;
  }

  static Future<void> stop() async {
    try { await _service?.stop(); } catch (_) {}
    _ctl?.add({'type': 'end'});
  }

  /// 从 APK assets 解压模型到本地（首次启动），之后复用缓存。
  static Future<String> _ensureModel(String storageDir) async {
    final modelDir = Directory(p.join(storageDir, _modelName));
    final doneFile = File(p.join(storageDir, '.model_ready'));
    if (doneFile.existsSync()) return modelDir.path; // 已解压过

    _ctl?.add({'type': 'loading', 'text': ''});
    await Directory(storageDir).create(recursive: true);
    final zipBytes = await rootBundle.load('assets/models/vosk-model-small-cn-0.22.zip');
    final archive = ZipDecoder().decodeBytes(zipBytes.buffer.asUint8List());
    for (final f in archive) {
      if (f.isFile) {
        final out = File(p.join(storageDir, f.name))..createSync(recursive: true);
        out.writeAsBytesSync(f.content);
      }
    }
    doneFile.writeAsStringSync('ok');
    return modelDir.path;
  }
}

