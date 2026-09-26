import 'package:flutter/material.dart';

import '../ai/assist.dart';
import '../data/store.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';
import '../l10n/i18n.dart';

/// 扩展 · AI 助手配置。默认关闭；开启后可选用预设免费模型或自填任意
/// OpenAI 兼容端点。仅在你主动点「AI 整理」时联网，发送内容只有那一段语音/文字。
class AiSettingsScreen extends StatelessWidget {
  const AiSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StartStore.I,
      builder: (context, _) {
        final c = ThemeTokens.of(context);
        final s = StartStore.I;
        final on = s.prefBool('ai_on', false);
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
                    Flexible(
                      child: Text(tr('AI 助手'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: S.textXl,
                              fontWeight: FontWeight.bold,
                              color: c.ink)),
                    ),
                  ],
                ),
                const SizedBox(height: S.sm),
                _Card(
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 20, color: c.ink),
                      const SizedBox(width: S.sm),
                      Expanded(
                        child: Text(tr('启用 AI 助手'),
                            style:
                                TextStyle(fontSize: S.textMd, color: c.ink)),
                      ),
                      Switch(
                        value: on,
                        activeThumbColor: c.accent,
                        onChanged: AiConfig.setOn,
                      ),
                    ],
                  ),
                ),
                if (on) ...[
                  _Label(c, tr('选择服务')),
                  _Presets(),
                  _Label(c, tr('接口配置')),
                  _Field(
                    icon: Icons.link,
                    value: AiConfig.base,
                    hint: 'https://example.com/v1',
                    onSave: AiConfig.setBase,
                  ),
                  _Field(
                    icon: Icons.memory,
                    value: AiConfig.model,
                    hint: tr('模型名，如 glm-4-flash'),
                    onSave: AiConfig.setModel,
                  ),
                  _Field(
                    icon: Icons.key,
                    value: AiConfig.key,
                    hint: 'API Key',
                    obscure: true,
                    onSave: AiConfig.setKey,
                  ),
                  const SizedBox(height: S.sm),
                  _TestButton(),
                ],
                const SizedBox(height: S.md),
                _Note(c,
                    tr('AI 只在你主动点「AI 整理」时工作：把一段话拆成「日程 / 随手做 / 念头」并自动归类。发送的仅为当时那段文字，配置与数据都只存在本机，开发者不收集任何信息。')),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Presets extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final base = AiConfig.base;
    final presetBases = AiConfig.presets.map((e) => e.$2).toList();
    final selectedCustom =
        base.isNotEmpty && !presetBases.contains(base);
    return Padding(
      padding: const EdgeInsets.only(bottom: S.xs),
      child: Wrap(
        spacing: S.xs,
        runSpacing: S.xs,
        children: [
          for (final p in AiConfig.presets)
            Pressable(
              onTap: () {
                AiConfig.setBase(p.$2);
                AiConfig.setModel(p.$3);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: S.sm, vertical: S.xs),
                decoration: BoxDecoration(
                  color: base == p.$2 &&
                          (p.$2.isNotEmpty || (!selectedCustom && p.$2.isEmpty))
                      ? c.accent
                      : c.cardAlt,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: p.$2.isEmpty && selectedCustom
                          ? c.accent
                          : Colors.transparent),
                ),
                child: Text(p.$1,
                    style: TextStyle(
                        fontSize: S.textSm,
                        fontWeight: FontWeight.bold,
                        color: base == p.$2 &&
                                (p.$2.isNotEmpty ||
                                    (!selectedCustom && p.$2.isEmpty))
                            ? Colors.white
                            : c.ink)),
              ),
            ),
        ],
      ),
    );
  }
}

class _TestButton extends StatefulWidget {
  @override
  State<_TestButton> createState() => _TestButtonState();
}

class _TestButtonState extends State<_TestButton> {
  bool _busy = false;
  String? _ok; // null=未测；true/false 文案

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Pressable(
      onTap: _busy || !AiConfig.ready
          ? null
          : () async {
              setState(() {
                _busy = true;
                _ok = null;
              });
              try {
                await AiClient.ping();
                if (mounted) setState(() => _ok = tr('连接正常'));
              } catch (e) {
                if (mounted) setState(() => _ok = tr('连不上：{0}', [e]));
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
      child: _Card(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_busy)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: c.accent),
              )
            else
              Icon(Icons.wifi_tethering, size: 20, color: c.ink),
            const SizedBox(width: S.sm),
            Flexible(
              child: Text(_busy ? tr('正在测试…') : (_ok ?? tr('测试连接')),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: S.textMd,
                      color: !AiConfig.ready && !_busy ? c.inkSoft : c.ink)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 行内可编辑字段：点一下弹底部输入框保存（密钥默认遮蔽）。
class _Field extends StatelessWidget {
  final IconData icon;
  final String value;
  final String hint;
  final bool obscure;
  final Future<void> Function(String) onSave;
  const _Field({
    required this.icon,
    required this.value,
    required this.hint,
    required this.onSave,
    this.obscure = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final display = obscure && value.isNotEmpty
        ? '•' * 8
        : (value.isEmpty ? hint : value);
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
                    borderSide:
                        BorderSide(color: ThemeTokens.of(ctx).line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(S.radius),
                    borderSide: BorderSide(
                        color: ThemeTokens.of(ctx).accent, width: 1.5),
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
                  child: Text(tr('保存'),
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

class _Label extends StatelessWidget {
  final C c;
  final String text;
  const _Label(this.c, this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(S.xxs, S.md, 0, S.xs),
        child: Text(text,
            style: TextStyle(
                fontSize: S.textSm,
                color: c.inkSoft,
                fontWeight: FontWeight.bold)),
      );
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
