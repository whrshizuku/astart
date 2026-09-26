import 'package:flutter/material.dart';

import '../data/store.dart';
import '../services/webdav.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

/// 扩展 · 云备份（WebDAV）。默认关闭；仅在用户手动点备份/恢复时联网，
/// 兼容坚果云、群晖、Nextcloud 等任意 WebDAV 服务。
class CloudSettingsScreen extends StatelessWidget {
  const CloudSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StartStore.I,
      builder: (context, _) {
        final c = ThemeTokens.of(context);
        final s = StartStore.I;
        final on = s.prefBool('wd_on', false);
        return Scaffold(
          backgroundColor: c.paper,
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(S.md),
              children: [
                Row(
                  children: [
                    IconBtn(Icons.arrow_back,
                        onTap: () => Navigator.pop(context)),
                    const SizedBox(width: S.xs),
                    Text('云备份',
                        style: TextStyle(
                            fontSize: S.textXl,
                            fontWeight: FontWeight.bold,
                            color: c.ink)),
                  ],
                ),
                const SizedBox(height: S.sm),
                _Card(
                  child: Row(
                    children: [
                      Icon(Icons.cloud_outlined, size: 20, color: c.ink),
                      const SizedBox(width: S.sm),
                      Expanded(
                        child: Text('启用 WebDAV 云备份',
                            style:
                                TextStyle(fontSize: S.textMd, color: c.ink)),
                      ),
                      Switch(
                        value: on,
                        activeThumbColor: c.accent,
                        onChanged: WebDav.setOn,
                      ),
                    ],
                  ),
                ),
                if (on) ...[
                  const SizedBox(height: S.sm),
                  _CloudField(
                    icon: Icons.language,
                    value: WebDav.url,
                    hint: '服务器地址，如 https://dav.jianguoyun.com/dav/backup',
                    onSave: WebDav.setUrl,
                  ),
                  _CloudField(
                    icon: Icons.person_outline,
                    value: WebDav.user,
                    hint: '账号',
                    onSave: WebDav.setUser,
                  ),
                  _CloudField(
                    icon: Icons.key,
                    value: WebDav.pass,
                    hint: '密码 / 应用专用密码',
                    obscure: true,
                    onSave: WebDav.setPass,
                  ),
                  const SizedBox(height: S.sm),
                  _ActionRow(
                    icon: Icons.wifi_tethering,
                    title: '测试连接',
                    onTap: () => _test(context),
                  ),
                  _ActionRow(
                    icon: Icons.cloud_upload_outlined,
                    title: '立即备份',
                    onTap: () => _backup(context),
                  ),
                  _ActionRow(
                    icon: Icons.cloud_download_outlined,
                    title: '从云端恢复最新一份',
                    danger: true,
                    onTap: () => _restore(context),
                  ),
                ],
                const SizedBox(height: S.md),
                _Note(c,
                    '备份内容为全量数据 JSON，文件名带时间戳，只上传到你自己填的服务器。'
                    '恢复会覆盖本机全部内容，恢复后可在 6 秒内撤销。不开启、不点按钮就不会联网。'),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _test(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!WebDav.ready) {
      messenger.showSnackBar(const SnackBar(content: Text('先把地址账号密码填全')));
      return;
    }
    try {
      await WebDav.ping();
      messenger.showSnackBar(const SnackBar(content: Text('连接正常')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('连不上：$e')));
    }
  }

  Future<void> _backup(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!WebDav.ready) {
      messenger.showSnackBar(const SnackBar(content: Text('先把地址账号密码填全')));
      return;
    }
    try {
      final name = await WebDav.backup();
      messenger.showSnackBar(SnackBar(content: Text('已备份：$name')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('备份失败：$e')));
    }
  }

  Future<void> _restore(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!WebDav.ready) {
      messenger.showSnackBar(const SnackBar(content: Text('先把地址账号密码填全')));
      return;
    }
    final c = ThemeTokens.of(context);
    final ok = await showStartDialog<bool>(
      context,
      title: '用云端备份覆盖本机？',
      actions: (dctx) => [
        TextButton(
            onPressed: () => Navigator.pop(dctx, false), child: const Text('取消')),
        TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: Text('覆盖', style: TextStyle(color: c.accentDark))),
      ],
    );
    if (ok != true || !context.mounted) return;
    try {
      final json = await WebDav.fetchLatest();
      final snap = StartStore.I.exportJson();
      final r = await StartStore.I.restoreJson(json);
      if (!context.mounted) return;
      if (r) {
        UndoHost.show(context, '已从云端恢复',
            () async => StartStore.I.restoreJson(snap));
      } else {
        messenger.showSnackBar(const SnackBar(content: Text('备份文件内容不对，没恢复')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('恢复失败：$e')));
    }
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool danger;
  const _ActionRow(
      {required this.icon, required this.title, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: S.xs),
      child: Pressable(
        onTap: onTap,
        child: _Card(
          child: Row(
            children: [
              Icon(icon, size: 20, color: danger ? c.accentDark : c.ink),
              const SizedBox(width: S.sm),
              Text(title,
                  style: TextStyle(
                      fontSize: S.textMd,
                      color: danger ? c.accentDark : c.ink)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CloudField extends StatelessWidget {
  final IconData icon;
  final String value;
  final String hint;
  final bool obscure;
  final Future<void> Function(String) onSave;
  const _CloudField({
    required this.icon,
    required this.value,
    required this.hint,
    required this.onSave,
    this.obscure = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final display = obscure && value.isNotEmpty ? '•' * 8 : (value.isEmpty ? hint : value);
    return Padding(
      padding: const EdgeInsets.only(bottom: S.xs),
      child: Pressable(
        onTap: () => _edit(context),
        child: _Card(
          child: Row(
            children: [
              Icon(icon, size: 20, color: c.ink),
              const SizedBox(width: S.sm),
              Expanded(
                child: Text(display,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: S.textMd,
                        color: value.isEmpty ? c.inkSoft : c.ink)),
              ),
              Icon(Icons.edit_note, size: 20, color: c.inkSoft),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final ctl = TextEditingController(text: value);
    await showStartSheet<void>(
      context,
      (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(S.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(hint,
                  style: TextStyle(
                      fontSize: S.textMd,
                      fontWeight: FontWeight.bold,
                      color: ThemeTokens.of(ctx).ink)),
              const SizedBox(height: S.sm),
              TextField(
                controller: ctl,
                autofocus: true,
                obscureText: obscure,
                style: TextStyle(
                    fontSize: S.textMd, color: ThemeTokens.of(ctx).ink),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: ThemeTokens.of(ctx).ringWell,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(S.radius),
                    borderSide: BorderSide(color: ThemeTokens.of(ctx).line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(S.radius),
                    borderSide:
                        BorderSide(color: ThemeTokens.of(ctx).accent, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: S.md),
              Pressable(
                onTap: () async {
                  await onSave(ctl.text);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: ThemeTokens.of(ctx).accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text('保存',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: S.textMd)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    ctl.dispose();
  }
}

class _Note extends StatelessWidget {
  final C c;
  final String text;
  const _Note(this.c, this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(fontSize: S.textSm, color: c.inkSoft, height: 1.6));
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => StartCard(
        padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.sm),
        child: child,
      );
}
