import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../ai/assist.dart';
import '../channels/native.dart';
import '../data/item.dart';
import '../data/store.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

/// 开发者选项：设置页顶部图标连点五次进入。调试开关、语音/大模型试验台、
/// 数据浏览与测试数据工具都在这里；全部配置仅存本机。
class LabScreen extends StatelessWidget {
  const LabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StartStore.I,
      builder: (context, _) {
        final c = ThemeTokens.of(context);
        final s = StartStore.I;
        return Scaffold(
          backgroundColor: c.paper,
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(S.md),
              children: [
                Row(
                  children: [
                    IconBtn(Icons.arrow_back, onTap: () => Navigator.pop(context)),
                    const SizedBox(width: S.xs),
                    Text('开发者选项',
                        style: TextStyle(
                            fontSize: S.textXl,
                            fontWeight: FontWeight.bold,
                            color: c.ink)),
                    const Spacer(),
                    Icon(Icons.bug_report_outlined, color: c.inkSoft),
                  ],
                ),
                const SizedBox(height: S.sm),
                _Group(c, label: '启动与开机动画'),
                _SplashMsTile(),
                _SwitchTile(
                  title: '开机铃声',
                  value: s.prefBool('boot_sound_on', false),
                  onChanged: (v) => s.setPref('boot_sound_on', v),
                ),
                _BootSoundTile(),
                _Group(c, label: '音效与通知（即时测试）'),
                _ActionTile(
                    icon: Icons.timer_outlined,
                    title: '播放滴答声',
                    onTap: () =>
                        Native.tick(s.prefInt('sound_volume', 70))),
                _ActionTile(
                    icon: Icons.notifications_active_outlined,
                    title: '播放结束提示音',
                    onTap: Native.chime),
                _ActionTile(
                    icon: Icons.vibration,
                    title: '震动一下',
                    onTap: () => Native.vibrate(40)),
                _ActionTile(
                  icon: Icons.alarm,
                  title: '5 秒后来一条测试通知',
                  onTap: () => Native.scheduleNotify(
                      999001,
                      '测试提醒',
                      DateTime.now().millisecondsSinceEpoch + 5000),
                ),
                _Group(c, label: '大模型助手（2.0 预研接口）'),
                _AiSection(),
                _Group(c, label: '语音交互'),
                _VoiceBench(),
                _Group(c, label: '云存储备份（WebDAV）'),
                _WdSection(),
                _Group(c, label: '数据工具'),
                _ActionTile(
                  icon: Icons.science_outlined,
                  title: '生成一批测试数据',
                  onTap: () => _seedData(context),
                ),
                _ActionTile(
                  icon: Icons.refresh,
                  title: '重置协议（下次启动重新同意）',
                  onTap: () async {
                    await s.setPref('eula_accepted_version', 0);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已重置，重启后生效')));
                    }
                  },
                ),
                _ActionTile(
                  icon: Icons.delete_sweep_outlined,
                  title: '清空全部条目',
                  danger: true,
                  onTap: () => _wipe(context),
                ),
                _ActionTile(
                  icon: Icons.restart_alt,
                  title: '恢复全部开发者选项为默认',
                  danger: true,
                  onTap: () => _resetLab(context),
                ),
                const SizedBox(height: S.lg),
                Center(
                  child: Text('Start · lab',
                      style: TextStyle(fontSize: S.textSm, color: c.inkSoft)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _seedData(BuildContext context) async {
    final s = StartStore.I;
    final now = DateTime.now().millisecondsSinceEpoch;
    final samples = [
      Item(kind: Item.kindTask, title: '测试随手做一', rank: -1, created: now),
      Item(kind: Item.kindTask, title: '测试随手做二', rank: -1, created: now + 1),
      Item(
          kind: Item.kindTask,
          title: '测试日程',
          dueTime: DateTime.now()
              .add(const Duration(hours: 3))
              .millisecondsSinceEpoch,
          alarm: true,
          created: now + 2),
      Item(kind: Item.kindIdea, title: '测试念头：也许可以做个彩蛋', rank: -1, created: now + 3),
      Item(kind: Item.kindInbox, title: '测试暂存：等分类的一条', rank: -1, created: now + 4),
    ];
    for (final it in samples) {
      await s.put(it, touchRank: true);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已生成 5 条测试数据')));
    }
  }

  Future<void> _wipe(BuildContext context) async {
    final ok = await showStartDialog<bool>(
      context,
      title: '清空全部条目？',
      actions: (dctx) => [
        TextButton(
            onPressed: () => Navigator.pop(dctx, false), child: const Text('取消')),
        TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: Text('清空',
                style: TextStyle(
                    color: ThemeTokens.of(context).accentDark))),
      ],
    );
    if (ok != true) return;
    final snap = await StartStore.I.clearAll();
    if (!context.mounted) return;
    UndoHost.show(context, '已清空', () async => StartStore.I.restoreJson(snap));
  }

  Future<void> _resetLab(BuildContext context) async {
    const keys = [
      'dev_splash_ms',
      'boot_sound_on',
      'ai_on',
      'ai_base',
      'ai_key',
      'ai_model',
      'voice_engine',
      'voice_ai_auto',
      'wd_url',
      'wd_user',
      'wd_pass',
    ];
    for (final k in keys) {
      await Prefs.set(k, null);
      StartStore.I.prefs.remove(k);
    }
    StartStore.I.refresh();
  }
}

// ---------------- 通用件 ----------------

class _Group extends StatelessWidget {
  final C c;
  final String label;
  const _Group(this.c, {required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.xxs, S.md, 0, S.xs),
      child: Text(label,
          style:
              TextStyle(fontSize: S.textSm, color: c.inkSoft, fontWeight: FontWeight.bold)),
    );
  }
}

class _Row extends StatelessWidget {
  final Widget child;
  const _Row({required this.child});

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: S.xs),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.sm),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(S.radius),
          border: Border.all(color: c.line),
        ),
        child: child,
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchTile({required this.title, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return _Row(
      child: Row(
        children: [
          Text(title, style: TextStyle(fontSize: S.textMd, color: c.ink)),
          const Spacer(),
          Switch(value: value, activeColor: c.accent, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool danger;
  const _ActionTile(
      {required this.icon, required this.title, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final color = danger ? c.accentDark : c.ink;
    return Padding(
      padding: const EdgeInsets.only(bottom: S.xs),
      child: Pressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.sm),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(S.radius),
            border: Border.all(color: c.line),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: S.sm),
              Text(title, style: TextStyle(fontSize: S.textMd, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- 启动相关 ----------------

class _SplashMsTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final s = StartStore.I;
    final ms = s.prefInt('dev_splash_ms', 2600).toDouble().clamp(1400.0, 6000.0);
    return _Row(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('开机动画时长', style: TextStyle(fontSize: S.textMd, color: c.ink)),
              const Spacer(),
              Text('${(ms / 1000).toStringAsFixed(1)} 秒',
                  style: TextStyle(
                      fontSize: S.textSm,
                      color: c.inkSoft,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: c.accent,
              inactiveTrackColor: c.cardAlt,
              thumbColor: c.accent,
              overlayColor: c.accentRipple,
            ),
            child: Slider(
              min: 1400,
              max: 6000,
              divisions: 46,
              value: ms,
              onChanged: (v) {
                s.prefs['dev_splash_ms'] = v.round();
                s.refresh();
              },
              onChangeEnd: (v) => s.setPref('dev_splash_ms', v.round()),
            ),
          ),
        ],
      ),
    );
  }
}

class _BootSoundTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final s = StartStore.I;
    return _Row(
      child: Row(
        children: [
          Expanded(
            child: Text('开机铃声文件（boot_sound.mp3，未选则用内置音）',
                style: TextStyle(fontSize: S.textSm, color: c.inkSoft)),
          ),
          TextButton(
            onPressed: () => Native.previewBoot(s.prefInt('sound_volume', 70)),
            child: Text('试听', style: TextStyle(color: c.accent)),
          ),
          TextButton(
            onPressed: () async {
              final ok = await FileApi.pickBootSound();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ok ? '铃声已选好，重启生效' : '没有选到文件')));
              }
            },
            child: Text('选择', style: TextStyle(color: c.accent)),
          ),
        ],
      ),
    );
  }
}

// ---------------- 大模型 ----------------

class _AiSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final s = StartStore.I;
    return Column(
      children: [
        _SwitchTile(
          title: '启用大模型助手',
          value: s.prefBool('ai_on', false),
          onChanged: (v) => s.setPref('ai_on', v),
        ),
        _Row(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('免费模型预设', style: TextStyle(fontSize: S.textMd, color: c.ink)),
              const SizedBox(height: S.xs),
              Wrap(
                spacing: S.xs,
                runSpacing: S.xs,
                children: [
                  for (final p in AiConfig.presets)
                    Pressable(
                      onTap: () async {
                        if (p.$2.isNotEmpty) await AiConfig.setBase(p.$2);
                        if (p.$3.isNotEmpty) await AiConfig.setModel(p.$3);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: S.sm, vertical: S.xxs),
                        decoration: BoxDecoration(
                          color: AiConfig.base == p.$2 && p.$2.isNotEmpty
                              ? c.accent
                              : c.cardAlt,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(p.$1,
                            style: TextStyle(
                                fontSize: S.textSm,
                                fontWeight: FontWeight.bold,
                                color: AiConfig.base == p.$2 && p.$2.isNotEmpty
                                    ? Colors.white
                                    : c.ink)),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        _PrefField(
          label: '接口地址（OpenAI 兼容）',
          value: s.prefStr('ai_base'),
          hint: 'https://.../v1',
          onSave: AiConfig.setBase,
        ),
        _PrefField(
          label: '模型名',
          value: s.prefStr('ai_model'),
          hint: 'glm-4-flash',
          onSave: AiConfig.setModel,
        ),
        _PrefField(
          label: 'API Key',
          value: s.prefStr('ai_key'),
          hint: 'sk-...',
          obscure: true,
          onSave: AiConfig.setKey,
        ),
        _ActionTile(
          icon: Icons.wifi_tethering,
          title: '连通性测试',
          onTap: () => _ping(context),
        ),
      ],
    );
  }

  Future<void> _ping(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!AiConfig.ready) {
      messenger.showSnackBar(
          const SnackBar(content: Text('先启用并填好地址、模型、Key')));
      return;
    }
    messenger.showSnackBar(const SnackBar(content: Text('请求中…')));
    try {
      final r = await AiClient.ping();
      messenger.showSnackBar(SnackBar(content: Text('连通正常：${r.trim()}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('失败：$e')));
    }
  }
}

class _PrefField extends StatefulWidget {
  final String label;
  final String value;
  final String hint;
  final bool obscure;
  final Future<void> Function(String) onSave;
  const _PrefField({
    required this.label,
    required this.value,
    required this.hint,
    required this.onSave,
    this.obscure = false,
  });

  @override
  State<_PrefField> createState() => _PrefFieldState();
}

class _PrefFieldState extends State<_PrefField> {
  late final TextEditingController _ctl =
      TextEditingController(text: widget.value);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: S.xs),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.xs),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(S.radius),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctl,
                obscureText: widget.obscure,
                style: TextStyle(fontSize: S.textSm, color: c.ink),
                decoration: InputDecoration(
                  labelText: widget.label,
                  hintText: widget.hint,
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            TextButton(
              onPressed: () => widget.onSave(_ctl.text),
              child: Text('保存', style: TextStyle(color: c.accent)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- 语音交互台 ----------------

class _VoiceBench extends StatefulWidget {
  @override
  State<_VoiceBench> createState() => _VoiceBenchState();
}

class _VoiceBenchState extends State<_VoiceBench> {
  StreamSubscription<Map<String, Object?>>? _sub;
  bool _listening = false;
  String _partial = '';
  final List<String> _finals = [];
  String _busy = '';

  bool get _useSystem => StartStore.I.prefInt('voice_engine', 0) == 0;

  @override
  void dispose() {
    _sub?.cancel();
    try {
      Voice.stop();
      SystemVoice.stop();
    } catch (_) {}
    super.dispose();
  }

  void _bindStream(Stream<Map<String, Object?>> stream) {
    _sub?.cancel();
    _sub = stream.listen((e) {
      final type = e['type'] as String? ?? '';
      final text = (e['text'] as String? ?? '').trim();
      if (!mounted) return;
      switch (type) {
        case 'partial':
          setState(() => _partial = text);
          break;
        case 'final':
          if (text.isEmpty) break;
          setState(() {
            _partial = '';
            _finals.insert(0, text);
          });
          if (StartStore.I.prefBool('voice_ai_auto', false)) _runAi(text);
          break;
        case 'end':
          setState(() => _listening = false);
          break;
        case 'error':
          setState(() {
            _listening = false;
            _busy = text.isEmpty ? '识别出错' : text;
          });
          break;
      }
    });
  }

  Future<void> _toggle() async {
    if (_listening) {
      _useSystem ? SystemVoice.stop() : Voice.stop();
      setState(() => _listening = false);
      return;
    }
    setState(() {
      _listening = true;
      _partial = '';
      _busy = '';
    });
    _bindStream(_useSystem ? SystemVoice.events() : Voice.events());
    if (_useSystem) {
      await SystemVoice.start();
    } else {
      await Voice.start();
    }
  }

  Future<void> _runAi(String text) async {
    if (!AiConfig.ready) {
      setState(() => _busy = 'AI 未配置好，已只保留转写文字');
      return;
    }
    setState(() => _busy = 'AI 解析中：$text');
    try {
      final item = await Assistant.handle(text);
      if (!mounted) return;
      if (item == null) {
        setState(() => _busy = '模型认为无需建条目');
        return;
      }
      final label = item.isIdea
          ? '念头'
          : (item.dueTime > 0 ? '日程' : '随手做');
      setState(() => _busy = '已建成$label：${item.title}');
      UndoHost.show(context, '撤销「${item.title}」',
          () => StartStore.I.delete(item.id, cascade: true));
    } catch (e) {
      if (mounted) setState(() => _busy = 'AI 失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final s = StartStore.I;
    final engine = s.prefInt('voice_engine', 0);
    return Column(
      children: [
        _Row(
          child: Row(
            children: [
              Text('识别引擎', style: TextStyle(fontSize: S.textMd, color: c.ink)),
              const Spacer(),
              for (final o in const [('系统离线', 0), ('Vosk', 1)])
                Padding(
                  padding: const EdgeInsets.only(left: S.xxs),
                  child: Pressable(
                    onTap: () {
                      if (_listening) return;
                      s.setPref('voice_engine', o.$2);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: S.sm, vertical: S.xxs),
                      decoration: BoxDecoration(
                        color: engine == o.$2 ? c.accent : c.cardAlt,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(o.$1,
                          style: TextStyle(
                              fontSize: S.textSm,
                              fontWeight: FontWeight.bold,
                              color:
                                  engine == o.$2 ? Colors.white : c.ink)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        _SwitchTile(
          title: '识别结果自动交 AI 建条目',
          value: s.prefBool('voice_ai_auto', false),
          onChanged: (v) => s.setPref('voice_ai_auto', v),
        ),
        _Row(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Pressable(
                    onTap: _toggle,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _listening ? c.accent : c.cardAlt,
                        border: Border.all(color: c.line),
                      ),
                      child: Icon(
                          _listening ? Icons.stop : Icons.mic_none,
                          color: _listening ? Colors.white : c.ink),
                    ),
                  ),
                  const SizedBox(width: S.sm),
                  Expanded(
                    child: Text(
                      _listening ? '正在听…（说一句待办试试）' : '点麦克风开始，再点停止',
                      style: TextStyle(fontSize: S.textSm, color: c.inkSoft),
                    ),
                  ),
                ],
              ),
              if (_partial.isNotEmpty) ...[
                const SizedBox(height: S.xs),
                Text('听到：$_partial',
                    style: TextStyle(fontSize: S.textSm, color: c.accent)),
              ],
              if (_busy.isNotEmpty) ...[
                const SizedBox(height: S.xs),
                Text(_busy, style: TextStyle(fontSize: S.textSm, color: c.inkSoft)),
              ],
              if (_finals.isNotEmpty) ...[
                const SizedBox(height: S.xs),
                for (final f in _finals.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        Icon(Icons.subject, size: 14, color: c.inkSoft),
                        const SizedBox(width: S.xs),
                        Expanded(
                          child: Text(f,
                              style: TextStyle(fontSize: S.textSm, color: c.ink)),
                        ),
                        TextButton(
                          onPressed: () => _runAi(f),
                          child: Text('交 AI',
                              style: TextStyle(fontSize: S.textSm, color: c.accent)),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        _TextAiBench(onResult: (msg) => setState(() => _busy = msg)),
      ],
    );
  }
}

/// 不走语音时直接打字测 AI 解析。
class _TextAiBench extends StatefulWidget {
  final ValueChanged<String> onResult;
  const _TextAiBench({required this.onResult});

  @override
  State<_TextAiBench> createState() => _TextAiBenchState();
}

class _TextAiBenchState extends State<_TextAiBench> {
  final _ctl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final text = _ctl.text.trim();
    if (text.isEmpty || !AiConfig.ready) {
      widget.onResult('先启用并配好大模型');
      return;
    }
    setState(() => _busy = true);
    try {
      final item = await Assistant.handle(text);
      widget.onResult(item == null ? '模型认为无需建条目' : '已建条目：${item.title}');
      _ctl.clear();
    } catch (e) {
      widget.onResult('AI 失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return _Row(
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ctl,
              style: TextStyle(fontSize: S.textSm, color: c.ink),
              decoration: const InputDecoration(
                hintText: '打字测解析，如：明天下午三点给妈打电话',
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : TextButton(
                  onPressed: _run,
                  child: Text('解析', style: TextStyle(color: c.accent)),
                ),
        ],
      ),
    );
  }
}

// ---------------- 云存储备份（WebDAV） ----------------

/// WebDAV 云备份：任意支持 WebDAV 的网盘（坚果云等）都能当备份盘。
/// 地址填目录，备份文件固定为 start-backup.json；Basic 认证，配置只存本机。
class _WdSection extends StatelessWidget {
  bool get _ready =>
      StartStore.I.prefStr('wd_url').trim().isNotEmpty &&
      StartStore.I.prefStr('wd_user').trim().isNotEmpty &&
      StartStore.I.prefStr('wd_pass').trim().isNotEmpty;

  Uri _base() {
    var u = StartStore.I.prefStr('wd_url').trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return Uri.parse(u);
  }

  Map<String, String> get _headers {
    final auth = base64Encode(utf8.encode(
        '${StartStore.I.prefStr('wd_user')}:${StartStore.I.prefStr('wd_pass')}'));
    return {'Authorization': 'Basic $auth'};
  }

  @override
  Widget build(BuildContext context) {
    final s = StartStore.I;
    return Column(
      children: [
        _PrefField(
          label: '服务器地址（目录）',
          value: s.prefStr('wd_url'),
          hint: 'https://dav.jianguoyun.com/dav/',
          onSave: (v) => s.setPref('wd_url', v.trim()),
        ),
        _PrefField(
          label: '账号',
          value: s.prefStr('wd_user'),
          hint: 'user@example.com',
          onSave: (v) => s.setPref('wd_user', v.trim()),
        ),
        _PrefField(
          label: '应用密码',
          value: s.prefStr('wd_pass'),
          hint: '应用密码，不是登录密码',
          obscure: true,
          onSave: (v) => s.setPref('wd_pass', v.trim()),
        ),
        _ActionTile(
          icon: Icons.wifi_tethering,
          title: '连接测试',
          onTap: () => _test(context),
        ),
        _ActionTile(
          icon: Icons.cloud_upload_outlined,
          title: '备份到云端',
          onTap: () => _push(context),
        ),
        _ActionTile(
          icon: Icons.cloud_download_outlined,
          title: '从云端恢复',
          onTap: () => _pull(context),
        ),
      ],
    );
  }

  Future<void> _test(BuildContext context) async {
    final m = ScaffoldMessenger.of(context);
    if (!_ready) {
      m.showSnackBar(const SnackBar(content: Text('先把地址、账号、密码填好')));
      return;
    }
    m.showSnackBar(const SnackBar(content: Text('连接中…')));
    try {
      final req = http.Request('PROPFIND', _base())
        ..headers.addAll({..._headers, 'Depth': '0'});
      final resp = await req.send().timeout(const Duration(seconds: 20));
      if (resp.statusCode == 207 || resp.statusCode == 200) {
        m.showSnackBar(const SnackBar(content: Text('连接正常，可以备份了')));
      } else if (resp.statusCode == 401) {
        m.showSnackBar(const SnackBar(content: Text('账号或应用密码不对')));
      } else {
        m.showSnackBar(
            SnackBar(content: Text('连接失败（状态 ${resp.statusCode}）')));
      }
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text('连不上：$e')));
    }
  }

  Future<void> _push(BuildContext context) async {
    final m = ScaffoldMessenger.of(context);
    if (!_ready) {
      m.showSnackBar(const SnackBar(content: Text('先把地址、账号、密码填好')));
      return;
    }
    m.showSnackBar(const SnackBar(content: Text('备份中…')));
    try {
      final uri = Uri.parse('${_base()}/start-backup.json');
      final resp = await http
          .put(uri,
              headers: {..._headers, 'Content-Type': 'application/json'},
              body: StartStore.I.exportJson())
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        m.showSnackBar(const SnackBar(content: Text('已备份到云端')));
      } else if (resp.statusCode == 401) {
        m.showSnackBar(const SnackBar(content: Text('账号或应用密码不对')));
      } else {
        m.showSnackBar(
            SnackBar(content: Text('备份失败（状态 ${resp.statusCode}）')));
      }
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text('备份失败：$e')));
    }
  }

  Future<void> _pull(BuildContext context) async {
    final m = ScaffoldMessenger.of(context);
    if (!_ready) {
      m.showSnackBar(const SnackBar(content: Text('先把地址、账号、密码填好')));
      return;
    }
    m.showSnackBar(const SnackBar(content: Text('获取云端备份…')));
    try {
      final uri = Uri.parse('${_base()}/start-backup.json');
      final resp = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode == 404) {
        m.showSnackBar(const SnackBar(content: Text('云端还没有备份，先备份一次')));
        return;
      }
      if (resp.statusCode != 200) {
        m.showSnackBar(
            SnackBar(content: Text('恢复失败（状态 ${resp.statusCode}）')));
        return;
      }
      if (!context.mounted) return;
      final ok = await showStartDialog<bool>(
        context,
        title: '用云端数据覆盖本机？',
        actions: (dctx) => [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('再想想')),
          TextButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: Text('恢复',
                  style:
                      TextStyle(color: ThemeTokens.of(context).accentDark))),
        ],
      );
      if (ok != true || !context.mounted) return;
      final snap = StartStore.I.exportJson();
      final r = await StartStore.I.restoreJson(resp.body);
      if (!context.mounted) return;
      UndoHost.show(context, r ? '已从云端恢复' : '云端文件不对，没导入',
          () async => StartStore.I.restoreJson(snap));
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text('恢复失败：$e')));
    }
  }
}
