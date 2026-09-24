import 'package:flutter/material.dart';

import '../channels/native.dart';
import '../data/store.dart';
import '../theme/tokens.dart';
import '../utils/update_checker.dart';
import '../widgets/ui.dart';
import 'manual.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 监听 store：任何设置项变化立即重建，选中态/开关/滑块实时刷新。
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
                const Spacer(),
                Icon(Icons.settings_outlined, color: c.inkSoft),
              ],
            ),
            const SizedBox(height: S.sm),
            _Group(c, label: '外观'),
            _DarkModeTile(),
            _FontTile(),
            _Group(c, label: '触感与音效'),
            _SwitchTile(
              title: '按压触感',
              value: s.prefBool('haptic', true),
              onChanged: (v) => s.setPref('haptic', v),
            ),
            _SwitchTile(
              title: '专注滴答声',
              value: s.prefBool('focus_tick', false),
              onChanged: (v) => s.setPref('focus_tick', v),
            ),
            _NotifyModeTile(),
            _VolumeTile(),
            _Group(c, label: '后台保活'),
            _SwitchTile(
              title: '常驻通知防误杀',
              value: s.prefBool('keep_alive', true),
              onChanged: (v) {
                s.setPref('keep_alive', v);
                Native.setKeepAlive(v);
              },
            ),
            _SwitchTile(
              title: '到点悬浮提醒',
              value: s.prefBool('notify_on', true),
              onChanged: (v) => s.setPref('notify_on', v),
            ),
            _Group(c, label: '数据（全在本机）'),
            _ExportTile(),
            _ImportTile(),
            _ClearTile(),
            _Group(c, label: '关于'),
            _UpdateTile(),
            _NavTile(
              icon: Icons.menu_book_outlined,
              title: '使用说明',
              onTap: () => Navigator.of(context, rootNavigator: true)
                  .push(MaterialPageRoute(builder: (_) => const ManualScreen())),
            ),
            _NavTile(
              icon: Icons.description_outlined,
              title: '用户协议',
              onTap: () => Navigator.of(context, rootNavigator: true)
                  .push(MaterialPageRoute(builder: (_) => const AgreeScreen(privacy: false))),
            ),
            _NavTile(
              icon: Icons.privacy_tip_outlined,
              title: '隐私政策',
              onTap: () => Navigator.of(context, rootNavigator: true)
                  .push(MaterialPageRoute(builder: (_) => const AgreeScreen(privacy: true))),
            ),
            _NavTile(
              icon: Icons.gavel_outlined,
              title: '开源协议',
              onTap: () => Navigator.of(context, rootNavigator: true)
                  .push(MaterialPageRoute(builder: (_) => const LicenseScreen())),
            ),
            _NavTile(
              icon: Icons.code,
              title: '项目源码',
              onTap: () => Native.openUrl('https://gitee.com/dubwhr/astart'),
            ),
            _NavTile(
              icon: Icons.mail_outline,
              title: '联系作者',
              onTap: () => Native.openUrl('mailto:3210819895@qq.com'),
            ),
            Padding(
              padding: const EdgeInsets.all(S.sm),
              child: Center(
                child: Text('Start',
                    style: TextStyle(fontSize: S.textSm, color: c.inkSoft)),
              ),
            ),
          ],
        ),
      ),
    );
      },
    );
  }
}

// ---------------- 基础件 ----------------

class _Group extends StatelessWidget {
  final C c;
  final String label;
  const _Group(this.c, {required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.xxs, S.md, 0, S.xs),
      child: Text(label,
          style: TextStyle(fontSize: S.textSm, color: c.inkSoft, fontWeight: FontWeight.bold)),
    );
  }
}

class _Row extends StatelessWidget {
  final Widget child;
  const _Row({required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: S.xs),
      child: StartCard(
        padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.sm),
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

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const _NavTile({required this.icon, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: S.xs),
      child: Pressable(
        onTap: onTap,
        child: StartCard(
          padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.sm),
          child: Row(
            children: [
              Icon(icon, size: 20, color: c.ink),
              const SizedBox(width: S.sm),
              Text(title, style: TextStyle(fontSize: S.textMd, color: c.ink)),
              const Spacer(),
              Icon(Icons.chevron_right, size: 20, color: c.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- 具体设置项 ----------------

class _DarkModeTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final s = StartStore.I;
    const opts = [('跟随系统', 0), ('开', 1), ('关', 2)];
    return _Row(
      child: Row(
        children: [
          Text('深色', style: TextStyle(fontSize: S.textMd, color: c.ink)),
          const Spacer(),
          Row(
            children: opts
                .map((o) => Padding(
                      padding: const EdgeInsets.only(left: S.xxs),
                      child: Pressable(
                        onTap: () => s.setPref('dark_mode', o.$2),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: S.sm, vertical: S.xxs),
                          decoration: BoxDecoration(
                            color: s.prefInt('dark_mode', 0) == o.$2 ? c.accent : c.cardAlt,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(o.$1,
                              style: TextStyle(
                                  fontSize: S.textSm,
                                  fontWeight: FontWeight.bold,
                                  color: s.prefInt('dark_mode', 0) == o.$2 ? Colors.white : c.ink)),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _FontTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final s = StartStore.I;
    const opts = [('小', 0), ('中', 1), ('大', 2)];
    return _Row(
      child: Row(
        children: [
          Text('字号', style: TextStyle(fontSize: S.textMd, color: c.ink)),
          const Spacer(),
          Row(
            children: opts
                .map((o) => Padding(
                      padding: const EdgeInsets.only(left: S.xxs),
                      child: Pressable(
                        onTap: () => s.setPref('font_scale', AppThemes.fontScales[o.$2]),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: S.sm, vertical: S.xxs),
                          decoration: BoxDecoration(
                            color: (s.prefDouble('font_scale', 1.0) - AppThemes.fontScales[o.$2]).abs() < 0.01
                                ? c.accent
                                : c.cardAlt,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            o.$1,
                            style: TextStyle(
                              fontSize: S.textSm,
                              fontWeight: FontWeight.bold,
                              color: (s.prefDouble('font_scale', 1.0) - AppThemes.fontScales[o.$2]).abs() < 0.01
                                  ? Colors.white
                                  : c.ink,
                            ),
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _NotifyModeTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final s = StartStore.I;
    const opts = [('声音', 0), ('震动', 1), ('静默', 2)];
    return _Row(
      child: Row(
        children: [
          Text('做完提示', style: TextStyle(fontSize: S.textMd, color: c.ink)),
          const Spacer(),
          Row(
            children: opts
                .map((o) => Padding(
                      padding: const EdgeInsets.only(left: S.xxs),
                      child: Pressable(
                        onTap: () => s.setPref('focus_notify', o.$2),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: S.sm, vertical: S.xxs),
                          decoration: BoxDecoration(
                            color: s.prefInt('focus_notify', 0) == o.$2 ? c.accent : c.cardAlt,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(o.$1,
                              style: TextStyle(
                                  fontSize: S.textSm,
                                  fontWeight: FontWeight.bold,
                                  color: s.prefInt('focus_notify', 0) == o.$2 ? Colors.white : c.ink)),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _VolumeTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final s = StartStore.I;
    return _Row(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('提示音量', style: TextStyle(fontSize: S.textMd, color: c.ink)),
              const Spacer(),
              Text('${s.prefInt('sound_volume', 70)}',
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
              min: 0,
              max: 100,
              divisions: 20,
              value: s.prefInt('sound_volume', 70).toDouble(),
              onChanged: (v) {
                s.prefs['sound_volume'] = v.round();
                s.refresh();
              },
              onChangeEnd: (v) => s.setPref('sound_volume', v.round()),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return _Row(
      child: Pressable(
        onTap: () async {
          final ok = await FileApi.export(StartStore.I.exportJson());
          if (context.mounted) {
            UndoHost.show(context, ok ? '已导出到文件' : '取消了', () {});
          }
        },
        child: Row(
          children: [
            Icon(Icons.file_upload_outlined, size: 20, color: c.ink),
            const SizedBox(width: S.sm),
            Text('导出数据', style: TextStyle(fontSize: S.textMd, color: c.ink)),
          ],
        ),
      ),
    );
  }
}

class _ImportTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return _Row(
      child: Pressable(
        onTap: () async {
          final text = await FileApi.import();
          if (text == null || text.isEmpty) return;
          final snap = StartStore.I.exportJson();
          final r = await StartStore.I.restoreJson(text);
          if (context.mounted) {
            UndoHost.show(context, r ? '已导入' : '文件内容不对，没导入',
                () async => StartStore.I.restoreJson(snap));
          }
        },
        child: Row(
          children: [
            Icon(Icons.file_download_outlined, size: 20, color: c.ink),
            const SizedBox(width: S.sm),
            Text('导入数据', style: TextStyle(fontSize: S.textMd, color: c.ink)),
          ],
        ),
      ),
    );
  }
}

class _UpdateTile extends StatefulWidget {
  @override
  State<_UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends State<_UpdateTile> {
  bool _checking = false;

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return _Row(
      child: Pressable(
        onTap: _checking ? null : _check,
        child: Row(
          children: [
            Icon(_checking ? Icons.sync_outlined : Icons.system_update_outlined,
                size: 20, color: c.ink),
            const SizedBox(width: S.sm),
            Text(_checking ? '检查中…' : '检查更新',
                style: TextStyle(fontSize: S.textMd, color: c.ink)),
            const Spacer(),
            FutureBuilder<String>(
              future: UpdateChecker.current(),
              builder: (_, snap) => Text('v${snap.data ?? ''}',
                  style: TextStyle(
                      fontSize: S.textSm,
                      color: c.inkSoft,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final r = await UpdateChecker.check();
    if (!mounted) return;
    setState(() => _checking = false);
    if (r == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已是最新版')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('发现新版本 v${r.version}'),
          action: r.url.isNotEmpty
              ? SnackBarAction(
                  label: '下载', onPressed: () => Native.openUrl(r.url))
              : null,
        ),
      );
    }
  }
}

class _ClearTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return _Row(
      child: Pressable(
        onTap: () async {
          final ok = await showStartDialog<bool>(
            context,
            title: '清空全部？',
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text('再想想')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text('清空', style: TextStyle(color: c.accentDark))),
            ],
          );
          if (ok != true || !context.mounted) return;
          final snap = await StartStore.I.clearAll();
          if (context.mounted) {
            UndoHost.show(context, '已清空', () async => StartStore.I.restoreJson(snap));
          }
        },
        child: Row(
          children: [
            Icon(Icons.delete_outline, size: 20, color: c.accentDark),
            const SizedBox(width: S.sm),
            Text('清空全部', style: TextStyle(fontSize: S.textMd, color: c.accentDark)),
          ],
        ),
      ),
    );
  }
}
