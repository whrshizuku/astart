import 'package:flutter/material.dart';

import '../ai/assist.dart';
import '../channels/native.dart';
import '../data/store.dart';
import '../l10n/i18n.dart';
import '../services/webdav.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

/// 隐藏功能页：设置→扩展开启「开发者模式」后，底部版权行五击进入。
/// 包含 AI / 在线语音 / 离线语音 / 云端 连通性测试与常用调试工具。
class LabScreen extends StatefulWidget {
  const LabScreen({super.key});

  @override
  State<LabScreen> createState() => _LabScreenState();
}

class _LabScreenState extends State<LabScreen> {
  bool _busy = false;

  Future<void> _run(String name, Future<void> Function() fn) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e) {
      _toast('失败: $e');
    }
    setState(() => _busy = false);
  }

  void _toast(String s) {
    LogSink.append(s);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _testAi() => _run('AI 测试', () async {
    _toast('开关: ${AiConfig.on}');
    _toast('端点: ${AiConfig.base}');
    _toast('模型: ${AiConfig.model}');
    _toast('密钥: ${AiConfig.key.isEmpty ? '(空)' : '***'}');
    if (!AiConfig.ready) {
      _toast('未就绪，请先在设置→扩展中开启并填写配置');
    } else {
      final r = await AiClient.ping();
      _toast('连通成功: ${r.length > 60 ? '${r.substring(0, 60)}...' : r}');
    }
  });

  Future<void> _testVoice() => _run('在线语音测试', () async {
    final r = await SystemVoice.testOnline();
    _toast('识别可用: ${r['available']}');
    _toast('设备端识别: ${r['onDevice']}');
    final engines = (r['engines'] as List?) ?? [];
    _toast('引擎列表 (${engines.length}): ${engines.isEmpty ? '(无)' : engines.join(', ')}');
  });

  Future<void> _testVosk() => _run('离线语音检测', () async {
    final r = await SystemVoice.testOnline();
    _toast('识别可用: ${r['available']}');
    _toast('设备端识别支持: ${r['onDevice']}');
  });

  Future<void> _testCloud() => _run('云端测试', () async {
    _toast('开关: ${WebDav.on}');
    _toast('地址: ${WebDav.url}');
    _toast('账号: ${WebDav.user.isEmpty ? '(空)' : '***'}');
    if (!WebDav.ready) {
      _toast('未就绪，请先在设置→扩展中开启并填写配置');
    } else {
      await WebDav.ping();
      _toast('连通成功');
      final list = await WebDav.list();
      _toast('备份文件 (${list.length}): ${list.isEmpty ? '(无)' : list.join(', ')}');
    }
  });

  Future<void> _showInfo() => _run('设备信息', () async {
    final v = await Native.versionName();
    final dir = await Native.filesDir();
    final prefs = await Prefs.getAll();
    _toast('版本: $v\n目录: $dir\n偏好键数: ${prefs.length}');
  });

  Future<void> _exportData() => _run('数据导出', () async {
    final json = StartStore.I.exportJson();
    final ok = await FileApi.export(json, 'start_debug_export.json');
    _toast(ok ? '导出成功' : '用户取消或失败');
  });

  Future<void> _testNotify() => _run('通知测试', () async {
    final now = DateTime.now().millisecondsSinceEpoch + 5000;
    await Native.scheduleNotify(999999, '测试通知', now);
    _toast('已设 5 秒后测试通知');
  });

  Future<void> _testCalendar() => _run('日历读取', () async {
    final list = await Native.calendarToday();
    _toast('今日事件 (${list.length}): ${list.isEmpty ? '(无)' : list.take(5).map((e) => e['title']).join(', ')}');
  });

  Future<void> _alarmNow() => _run('立即闹钟', () async {
    await Native.scheduleNotify(999997, '闹钟测试-立即', DateTime.now().millisecondsSinceEpoch + 1500);
    _toast('1.5 秒后触发（锁屏查看）');
  });

  Future<void> _alarm10s() => _run('10 秒闹钟', () async {
    await Native.scheduleNotify(999998, '闹钟测试-10秒', DateTime.now().millisecondsSinceEpoch + 10000);
    _toast('10 秒后触发（锁屏查看）');
  });

  Future<void> _alarmDiag() => _run('闹钟诊断', () async {
    final d = await Native.alarmDiag();
    String fmt(Object? ms) {
      final v = (ms as num?)?.toInt() ?? 0;
      return v > 0 ? DateTime.fromMillisecondsSinceEpoch(v).toString() : '(无)';
    }
    _toast(
      '通知权限: ${d['notifPermission']}\n'
      '通知总开关: ${d['notificationsEnabled']}\n'
      '渠道存在: ${d['channelExists']}，重要度: ${d['channelImportance']}（≥4 才会响铃震动）\n'
      '到点提醒偏好: ${d['notifyOn']}，常驻偏好: ${d['keepAlive']}\n'
      '下一个闹钟: ${fmt(d['nextAlarmAt'])}\n'
      '上次触发: ${fmt(d['lastFire'])}「${d['lastLabel']}」\n'
      '上次被权限拦下: ${fmt(d['lastBlocked'])}',
    );
  });

  Future<void> _channelSettings() => _run('渠道设置', () async {
    await Native.openChannelSettings();
  });

  Future<void> _calWrite() => _run('日历写入', () async {
    final ms = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch;
    final id = await Native.calendarInsert('测试事件', ms);
    _toast(id > 0 ? '写入成功 id=$id' : '写入失败（无权限或无可写日历）');
  });

  Future<void> _segment() => _run('分词测试', () async {
    final words = await Native.words('明天下午三点开会别忘了带文件');
    _toast('分词 (${words.length}): ${words.join(' / ')}');
  });

  Future<void> _restart() => _run('强制重启', () async {
    await Native.restart();
  });

  Future<void> _factoryReset() async {
    final ok = await showStartDialog<bool>(
      context,
      title: tr('恢复出厂？'),
      actions: (dctx) => [
        TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text(tr('取消'))),
        TextButton(
          onPressed: () => Navigator.pop(dctx, true),
          child: Text(tr('确认'), style: TextStyle(color: ThemeTokens.of(context).accentDark)),
        ),
      ],
    );
    if (ok != true || !context.mounted) return;
    await StartStore.I.factoryReset();
    await Native.factoryReset();
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(S.md),
          children: [
            // 返回钮居左、标题居中（与设置页同款标题栏）。
            SizedBox(
              height: 32,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconBtn(Icons.arrow_back,
                        onTap: () => Navigator.pop(context)),
                  ),
                  Center(
                    child: Text(tr('测试'),
                        style: TextStyle(
                            fontSize: S.textLg,
                            fontWeight: FontWeight.bold,
                            color: c.ink)),
                  ),
                ],
              ),
            ),
            _group(c, tr('接口测试')),
            _tile(c, Icons.psychology_outlined, tr('AI 测试'), _testAi),
            _tile(c, Icons.mic_outlined, tr('在线语音'), _testVoice),
            _tile(c, Icons.wifi_off_outlined, tr('离线语音'), _testVosk),
            _tile(c, Icons.cloud_outlined, tr('云端测试'), _testCloud),
            _group(c, tr('闹钟测试')),
            _tile(c, Icons.alarm_outlined, tr('立即闹钟'), _alarmNow),
            _tile(c, Icons.timer_outlined, tr('10 秒后闹钟'), _alarm10s),
            _tile(c, Icons.build_outlined, tr('闹钟诊断'), _alarmDiag),
            _tile(c, Icons.settings_outlined, tr('通知渠道设置'), _channelSettings),
            _group(c, tr('日程测试')),
            _tile(c, Icons.event_outlined, tr('写入测试事件'), _calWrite),
            _tile(c, Icons.calendar_month_outlined, tr('读取今日日历'), _testCalendar),
            _group(c, tr('调试工具')),
            _tile(c, Icons.info_outlined, tr('设备信息'), _showInfo),
            _tile(c, Icons.file_download_outlined, tr('导出数据'), _exportData),
            _tile(c, Icons.notifications_outlined, tr('通知测试'), _testNotify),
            _tile(c, Icons.content_cut_outlined, tr('分词测试'), _segment),
            _tile(c, Icons.refresh_outlined, tr('强制重启'), _restart),
            _tile(c, Icons.delete_forever_outlined, tr('恢复出厂'), _factoryReset),
            _group(c, tr('运行日志')),
            _tile(c, Icons.terminal_outlined, tr('打开日志'), () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const LogScreen()))),
          ],
        ),
      ),
    );
  }

  /// 分组小标题（与设置页 _Group 同款）。
  Widget _group(C c, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.xxs, S.md, 0, S.xs),
      child: Text(label,
          style: TextStyle(
              fontSize: S.textSm,
              color: c.inkSoft,
              fontWeight: FontWeight.bold)),
    );
  }

  /// 单条目独立卡片（与设置页 _NavTile 同款）。
  Widget _tile(C c, IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: S.xs),
      child: Pressable(
        onTap: _busy ? null : onTap,
        child: StartCard(
          padding: const EdgeInsets.symmetric(
              horizontal: S.md, vertical: S.sm),
          child: Row(
            children: [
              Icon(icon, size: 20, color: c.ink),
              const SizedBox(width: S.sm),
              Expanded(
                child: Text(label,
                    style: TextStyle(fontSize: S.textMd, color: c.ink)),
              ),
              if (_busy)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: c.accent),
                )
              else
                Icon(Icons.chevron_right, size: 20, color: c.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}

/// 日志子页面：开发者模式里「打开日志」后进入。
class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  String _log = '';

  @override
  void initState() {
    super.initState();
    _log = LogSink.buffer;
  }

  void _clear() => setState(() {
    LogSink.clear();
    _log = '';
  });

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Column(
          children: [
            // 标题栏
            SizedBox(
              height: 32,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconBtn(Icons.arrow_back,
                        onTap: () => Navigator.pop(context)),
                  ),
                  Center(
                    child: Text(tr('运行日志'),
                        style: TextStyle(
                            fontSize: S.textLg,
                            fontWeight: FontWeight.bold,
                            color: c.ink)),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconBtn(Icons.delete_outline,
                        onTap: _clear, color: c.inkSoft),
                  ),
                ],
              ),
            ),
            const SizedBox(height: S.sm),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: S.md),
                child: StartCard(
                  color: c.cardAlt,
                  padding: const EdgeInsets.all(S.md),
                  child: SingleChildScrollView(
                    reverse: true,
                    child: SelectableText(
                      _log.isEmpty ? tr('暂无日志') : _log,
                      style: TextStyle(
                          fontSize: S.textSm, color: c.ink, height: 1.6),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 内存日志收集器：供各处 append，LogScreen 可读取。
class LogSink {
  static final _buf = StringBuffer();
  static String get buffer => _buf.toString();

  static void clear() => _buf.clear();

  static void append(String s) {
    final now = DateTime.now();
    final t = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    _buf.writeln('[$t] $s');
    // 只保留最近 1000 行
    final lines = _buf.toString().split('\n');
    if (lines.length > 1000) {
      _buf.clear();
      _buf.writeAll(lines.skip(lines.length - 1000), '\n');
      _buf.write('\n');
    }
  }
}
