import 'package:flutter/material.dart';

import '../channels/native.dart';
import '../data/store.dart';
import '../theme/tokens.dart';
import '../utils/update_checker.dart';
import '../widgets/ui.dart';
import 'ai_settings.dart';
import 'cloud_settings.dart';
import 'manual.dart';
import '../l10n/i18n.dart';

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
            // 返回钮居左、应用 logo 相对整行水平居中。
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
                    child: Image.asset('assets/app_icon.png',
                        width: 30, height: 30),
                  ),
                ],
              ),
            ),
            const SizedBox(height: S.sm),
            _Group(c, label: tr('界面语言')),
            _LangTile(),
            Padding(
              padding: const EdgeInsets.fromLTRB(S.xs, 0, S.xs, S.xs),
              child: Text(tr('除简体中文外，界面翻译由人工智能生成，仅供参考'),
                  style: TextStyle(fontSize: S.textSm, color: c.inkSoft)),
            ),
            _Group(c, label: tr('外观')),
            _DarkModeTile(),
            _FontTile(),
            _Group(c, label: tr('触感与音效')),
            _SwitchTile(
              title: tr('按压触感'),
              value: s.prefBool('haptic', true),
              onChanged: (v) => s.setPref('haptic', v),
            ),
            _SwitchTile(
              title: tr('专注滴答声'),
              value: s.prefBool('focus_tick', false),
              onChanged: (v) => s.setPref('focus_tick', v),
            ),
            _NotifyModeTile(),
            _VolumeTile(),
            _Group(c, label: tr('后台保活')),
            _SwitchTile(
              title: tr('常驻通知防误杀'),
              value: s.prefBool('keep_alive', true),
              onChanged: (v) {
                s.setPref('keep_alive', v);
                Native.setKeepAlive(v);
              },
            ),
            _SwitchTile(
              title: tr('到点悬浮提醒'),
              value: s.prefBool('notify_on', true),
              onChanged: (v) => s.setPref('notify_on', v),
            ),
            _Group(c, label: tr('数据（全在本机）')),
            _ExportTile(),
            _ImportTile(),
            _ClearTile(),
            _Group(c, label: tr('扩展（默认关闭，按需开启）')),
            _SwitchTile(
              title: tr('在线语音识别'),
              value: s.prefBool('voice_online', false),
              onChanged: (v) => s.setPref('voice_online', v),
            ),
            _NavTile(
              icon: Icons.auto_awesome,
              title: tr('AI 助手'),
              onTap: () => Navigator.of(context, rootNavigator: true)
                  .push(MaterialPageRoute(builder: (_) => const AiSettingsScreen())),
            ),
            _NavTile(
              icon: Icons.cloud_outlined,
              title: tr('云备份（WebDAV）'),
              onTap: () => Navigator.of(context, rootNavigator: true)
                  .push(MaterialPageRoute(builder: (_) => const CloudSettingsScreen())),
            ),
            _Group(c, label: tr('关于')),
            _UpdateTile(),
            _NavTile(
              icon: Icons.menu_book_outlined,
              title: tr('使用说明'),
              onTap: () => Navigator.of(context, rootNavigator: true)
                  .push(MaterialPageRoute(builder: (_) => const ManualScreen())),
            ),
            _NavTile(
              icon: Icons.description_outlined,
              title: tr('用户协议'),
              onTap: () => Navigator.of(context, rootNavigator: true)
                  .push(MaterialPageRoute(builder: (_) => const AgreeScreen(privacy: false))),
            ),
            _NavTile(
              icon: Icons.privacy_tip_outlined,
              title: tr('隐私政策'),
              onTap: () => Navigator.of(context, rootNavigator: true)
                  .push(MaterialPageRoute(builder: (_) => const AgreeScreen(privacy: true))),
            ),
            _NavTile(
              icon: Icons.gavel_outlined,
              title: tr('开源协议'),
              onTap: () => Navigator.of(context, rootNavigator: true)
                  .push(MaterialPageRoute(builder: (_) => const LicenseScreen())),
            ),
            _NavTile(
              icon: Icons.code,
              title: tr('项目源码'),
              onTap: () => Native.openUrl('https://gitee.com/dubwhr/astart'),
            ),
            _NavTile(
              icon: Icons.mail_outline,
              title: tr('联系作者'),
              onTap: () => Native.openUrl('mailto:3210819895@qq.com'),
            ),
            Padding(
              padding: const EdgeInsets.all(S.sm),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('Start',
                        style: TextStyle(
                            fontSize: S.textSm,
                            fontWeight: FontWeight.bold,
                            color: c.inkSoft,
                            height: 1.0)),
                    const SizedBox(width: S.xxs),
                    if (Lang.current == Lang.zhCN)
                      Text(tr('启序'),
                          style:
                              TextStyle(fontSize: S.textSm, color: c.inkSoft, height: 1.0)),
                    if (Lang.current == Lang.zhCN) const SizedBox(width: S.xxs),
                    Text(tr('© 2026 王浩然'),
                        style:
                            TextStyle(fontSize: S.textSm, color: c.inkSoft, height: 1.0)),
                  ],
                ),
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
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: S.textMd, color: c.ink)),
          ),
          Switch(value: value, activeThumbColor: c.accent, onChanged: onChanged),
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
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: S.textMd, color: c.ink)),
              ),
              const SizedBox(width: S.xs),
              Icon(Icons.chevron_right, size: 20, color: c.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- 具体设置项 ----------------

class _LangTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final s = StartStore.I;
    final cur = s.prefStr(Lang.prefKey, Lang.system);
    final curName =
        Lang.options.firstWhere((o) => o.$1 == cur, orElse: () => Lang.options.first).$2;
    return _Row(
      child: Pressable(
        onTap: () => _pick(context),
        child: Row(
          children: [
            Expanded(
              child: Text(tr('界面语言'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: S.textMd, color: c.ink)),
            ),
            Flexible(
              child: Text(curName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: S.textSm, color: c.inkSoft)),
            ),
            Icon(Icons.chevron_right, size: 20, color: c.inkSoft),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final s = StartStore.I;
    final c = ThemeTokens.of(context);
    final cur = s.prefStr(Lang.prefKey, Lang.system);
    await showStartDialog<void>(
      context,
      title: tr('界面语言'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in Lang.options)
            RadioListTile<String>(
              value: o.$1,
              groupValue: cur,
              activeColor: c.accent,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.trailing,
              title: Text(o.$2),
              onChanged: (v) async {
                Navigator.pop(context);
                if (v != null) await Lang.choose(v);
              },
            ),
        ],
      ),
      actions: (dctx) => [
        TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: Text(tr('取消'), style: TextStyle(color: c.inkSoft))),
      ],
    );
  }
}

class _DarkModeTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final s = StartStore.I;
    final opts = [(tr('跟随系统'), 0), (tr('开'), 1), (tr('关'), 2)];
    return _Row(
      child: Row(
        children: [
          Expanded(
            child: Text(tr('深色'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: S.textMd, color: c.ink)),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
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
    final opts = [(tr('小'), 0), (tr('中'), 1), (tr('大'), 2)];
    return _Row(
      child: Row(
        children: [
          Expanded(
            child: Text(tr('字号'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: S.textMd, color: c.ink)),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
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
    final opts = [(tr('声音'), 0), (tr('震动'), 1), (tr('静默'), 2)];
    return _Row(
      child: Row(
        children: [
          Expanded(
            child: Text(tr('做完提示'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: S.textMd, color: c.ink)),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
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
              Expanded(
                child: Text(tr('提示音量'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: S.textMd, color: c.ink)),
              ),
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
            UndoHost.show(context, ok ? tr('已导出到文件') : tr('取消了'), () {});
          }
        },
        child: Row(
          children: [
            Icon(Icons.file_upload_outlined, size: 20, color: c.ink),
            const SizedBox(width: S.sm),
            Expanded(
              child: Text(tr('导出数据'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: S.textMd, color: c.ink)),
            ),
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
            UndoHost.show(context, r ? tr('已导入') : tr('文件内容不对，没导入'),
                () async => StartStore.I.restoreJson(snap));
          }
        },
        child: Row(
          children: [
            Icon(Icons.file_download_outlined, size: 20, color: c.ink),
            const SizedBox(width: S.sm),
            Expanded(
              child: Text(tr('导入数据'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: S.textMd, color: c.ink)),
            ),
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
            Expanded(
              child: Text(_checking ? tr('检查中…') : tr('检查更新'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: S.textMd, color: c.ink)),
            ),
            const SizedBox(width: S.xs),
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
        SnackBar(content: Text(tr('已是最新版'))),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('发现新版本 v{0}', [r.version])),
          action: r.url.isNotEmpty
              ? SnackBarAction(
                  label: tr('下载'), onPressed: () => Native.openUrl(r.url))
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
            title: tr('清空全部？'),
            actions: (dctx) => [
              TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text(tr('再想想'))),
              TextButton(
                  onPressed: () => Navigator.pop(dctx, true),
                  child: Text(tr('清空'), style: TextStyle(color: c.accentDark))),
            ],
          );
          if (ok != true || !context.mounted) return;
          final snap = await StartStore.I.clearAll();
          if (context.mounted) {
            UndoHost.show(context, tr('已清空'), () async => StartStore.I.restoreJson(snap));
          }
        },
        child: Row(
          children: [
            Icon(Icons.delete_outline, size: 20, color: c.accentDark),
            const SizedBox(width: S.sm),
            Expanded(
              child: Text(tr('清空全部'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: S.textMd, color: c.accentDark)),
            ),
          ],
        ),
      ),
    );
  }
}

