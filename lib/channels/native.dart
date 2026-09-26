import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
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

  static Future<void> vibrate([int ms = 20]) => _sys.invokeMethod('vibrate', {'ms': ms});

  static Future<void> keepScreenOn(bool on) => _sys.invokeMethod('keepScreenOn', {'on': on});

  static Future<String?> initialShare() => _sys.invokeMethod<String?>('initialShare');

  /// 任意门：拨号 / 打开链接（走系统 Intent，不联网）。
  static Future<void> dial(String number) =>
      _sys.invokeMethod('openAction', {'kind': 'dial', 'data': number});
  static Future<void> openUrl(String url) =>
      _sys.invokeMethod('openAction', {'kind': 'url', 'data': url});

  /// 绑定手机日历与系统闹钟：用系统 Intent，不申请额外权限、不联网。
  static Future<void> addToCalendar(String title, int ms) =>
      _sys.invokeMethod('calendar', {'title': title, 'ms': ms});
  static Future<void> setAlarm(String title, int ms) =>
      _sys.invokeMethod('alarm', {'title': title, 'ms': ms});

  /// 本地到点提醒：AlarmManager 精确闹钟 + 悬浮通知，无需第三方推送。
  static Future<void> scheduleNotify(int id, String label, int whenMs) =>
      _sys.invokeMethod('notifySchedule', {'id': id, 'label': label, 'when': whenMs});
  static Future<void> cancelNotify(int id) =>
      _sys.invokeMethod('notifyCancel', {'id': id});

  /// 后台保活常驻通知开关（true=显示"今日待办守护中"，false=移除）。
  static Future<void> setKeepAlive(bool on) =>
      _sys.invokeMethod('setKeepAlive', {'on': on});

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

  /// 开机铃声：原生侧按 start_prefs 里的开关与音量自行决定是否播放。
  static Future<void> bootSound() => _snd.invokeMethod('playBoot');
  static Future<void> previewBoot(int volume) =>
      _snd.invokeMethod('previewBoot', {'volume': volume});
  static Future<void> stopBoot() => _snd.invokeMethod('stopBoot');
}

/// 系统语音引擎（厂商自研离线优先），与 Vosk 互为备选。事件同 {type,text}。
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

  /// 选择音频文件复制进应用私有目录作为开机铃声，返回是否成功。
  static Future<bool> pickBootSound() async =>
      (await _ch.invokeMethod<bool>('pickBootSound')) ?? false;
}

/// 语音识别：Vosk 离线引擎（开源，中文模型，首次联网下载模型后离线识别）。
/// 不绑谷歌、不依赖手机系统语音服务。事件流：{type: ready|partial|final|end|error, text}
class Voice {
  static const _modelUrl =
      'https://alphacephei.com/vosk/models/vosk-model-small-cn-0.22.zip';

  static final _plugin = VoskFlutterPlugin.instance();
  static ModelLoader? _loader;
  static Model? _model;
  static Recognizer? _recognizer;
  static SpeechService? _service;
  static StreamSubscription? _resultSub;
  static StreamSubscription? _partialSub;
  static StreamController<Map<String, Object?>>? _ctl;
  static bool _loading = false;

  static Stream<Map<String, Object?>> events() {
    _ctl ??= StreamController<Map<String, Object?>>.broadcast();
    return _ctl!.stream;
  }

  static Future<void> start() async {
    if (_loading) return;
    _loading = true;
    _ctl ??= StreamController<Map<String, Object?>>.broadcast();
    _ctl!.add({'type': 'ready', 'text': ''});

    try {
      if (_service == null) {
        final dir = await Native.filesDir();
        _loader ??= ModelLoader(modelStorage: '$dir/models');
        final modelPath = await _loader!.loadFromNetwork(_modelUrl);
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
      await _service!.start();
      _loading = false;
    } catch (e) {
      _loading = false;
      _ctl!.add({'type': 'error', 'text': '$e'});
    }
  }

  static Future<void> stop() async {
    try { await _service?.stop(); } catch (_) {}
    _ctl?.add({'type': 'end'});
  }
}
