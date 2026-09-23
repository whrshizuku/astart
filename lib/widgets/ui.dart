// ── 工匠的骄傲与喜悦 · Artisan's Pride & Joy ──
// 致敬 Smartisan OS：
//   闪念胶囊 → 念头 · 大爆炸 → 捋一捋 · 一步 → 开始
// 把每一个细节较真到底，是这件小东西全部的骄傲与喜悦。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/store.dart';
import '../theme/tokens.dart';

/// 极简按压反馈：按压缩放 0.97 + 触感（可在设置关闭）。
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;
  final double scale;
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.scale = 0.97,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _haptic() {
    if (StartStore.I.prefBool('haptic', true)) HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap == null ? null : () { _haptic(); widget.onTap!(); },
      onDoubleTap: widget.onDoubleTap,
      onLongPress: widget.onLongPress == null ? null : () { _haptic(); widget.onLongPress!(); },
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 90),
        child: widget.child,
      ),
    );
  }
}

/// 主题色访问：以 InheritedWidget 方式下发 C。
class ThemeTokens extends InheritedWidget {
  final C c;
  const ThemeTokens({super.key, required this.c, required super.child});

  static C of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeTokens>()?.c ?? C.light;

  @override
  bool updateShouldNotify(ThemeTokens oldWidget) => oldWidget.c != c;
}

/// 统一卡片。
class StartCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  const StartCard({super.key, required this.child, this.padding = const EdgeInsets.all(S.md), this.color});

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? c.card,
        borderRadius: BorderRadius.circular(S.radius),
        border: Border.all(color: c.line),
      ),
      child: child,
    );
  }
}

/// 空态：极简图形 + 一句引导 + 可选行动按钮。
class EmptyView extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;
  const EmptyView({super.key, required this.icon, required this.text, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: c.inkSoft),
          const SizedBox(height: S.sm),
          Text(text, style: TextStyle(color: c.inkSoft, fontSize: S.textMd)),
          if (action != null) ...[
            const SizedBox(height: S.md),
            Pressable(
              onTap: onAction,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: S.lg, vertical: S.xs),
                decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(action!,
                    style: const TextStyle(color: Colors.white, fontSize: S.textMd, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 圆形勾选钮。
class CheckDot extends StatelessWidget {
  final bool done;
  final VoidCallback? onTap;
  const CheckDot({super.key, required this.done, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done ? c.accent : Colors.transparent,
          border: Border.all(color: done ? c.accent : c.inkSoft, width: 2),
        ),
        child: done ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
      ),
    );
  }
}

/// 6 秒撤销条：全局栈底浮出，到时静默生效。
class UndoHost extends StatefulWidget {
  const UndoHost({super.key});

  /// 显示撤销条。返回后 6 秒过期（过期不执行 onExpire 的删除，由调用方在删除时先快照）。
  static void show(BuildContext context, String text, VoidCallback onUndo) {
    final state = context.findAncestorStateOfType<_UndoHostState>();
    state?._show(text, onUndo);
  }

  @override
  State<UndoHost> createState() => _UndoHostState();
}

class _UndoHostState extends State<UndoHost> {
  String? _text;
  VoidCallback? _onUndo;

  void _show(String text, VoidCallback onUndo) {
    setState(() {
      _text = text;
      _onUndo = onUndo;
    });
  }

  void _dismiss() => setState(() {
        _text = null;
        _onUndo = null;
      });

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final visible = _text != null;
    return Positioned(
      left: S.md,
      right: S.md,
      bottom: 84,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 2),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.xs),
              decoration: BoxDecoration(
                color: c.ink,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(_text ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.paper, fontSize: S.textMd)),
                  ),
                  Pressable(
                    onTap: () {
                      _onUndo?.call();
                      _dismiss();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: S.xs, vertical: S.xs),
                      child: Text('撤销',
                          style: TextStyle(
                              color: c.accentLight, fontSize: S.textMd, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部弹层输入容器（统一圆角、纸色）。
Future<T?> showStartSheet<T>(BuildContext context, WidgetBuilder builder) {
  final c = ThemeTokens.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: c.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(S.lg)),
    ),
    builder: builder,
  );
}

/// 统一对话框。
Future<T?> showStartDialog<T>(BuildContext context, {required String title, String? content, List<Widget>? actions}) {
  final c = ThemeTokens.of(context);
  return showDialog<T>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(S.radius)),
      title: Text(title, style: TextStyle(color: c.ink, fontSize: S.textLg, fontWeight: FontWeight.bold)),
      content: content == null ? null : Text(content, style: TextStyle(color: c.ink, fontSize: S.textMd)),
      actions: actions,
    ),
  );
}

/// 图标小按钮（顶栏/卡片通用）。
class IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;
  final String? tip;
  const IconBtn(this.icon, {super.key, this.onTap, this.color, this.tip});

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(S.xs),
        child: Icon(icon, size: 24, color: color ?? c.ink),
      ),
    );
  }
}

/// 按行 + 句末标点拆成多条（动手吧 / 小步骤 / 念头通用，不按词拆）。
List<String> splitIntoLines(String raw) {
  final out = <String>[];
  for (final line in raw.split(RegExp(r'[\n\r]+'))) {
    final l = line.trim();
    if (l.isEmpty) continue;
    for (final p in l.split(RegExp(r'[。！？；!?;…]+'))) {
      final t = p.trim();
      if (t.isNotEmpty) out.add(t);
    }
  }
  return out;
}

/// 底部输入条（开始 / 捋一捋 / 念头 / 小步骤共用）：写一行存一条，回车换行多写几行。
/// 左⑂捋一捋拆词（有字拆内容，没字聚焦输入），右提交圆钮。
/// [showBang]=false 时隐藏拆词钮（开始页只负责倒进来）。
class QuickInputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onCommit;
  final VoidCallback onBang;
  final String hint;
  final bool showBang;
  final IconData submitIcon;
  final int maxLines;
  final bool autofocus;
  const QuickInputBar({
    super.key,
    required this.controller,
    required this.focus,
    required this.onCommit,
    required this.onBang,
    required this.hint,
    this.showBang = true,
    this.submitIcon = Icons.arrow_upward,
    this.maxLines = 4,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(S.md, 0, S.md, S.sm),
      padding: const EdgeInsets.fromLTRB(S.md, S.xs, S.xs, S.xs),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              autofocus: autofocus,
              minLines: 1,
              maxLines: maxLines,
              style: TextStyle(fontSize: S.textMd, color: c.ink),
              cursorColor: c.accent,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: c.inkSoft, fontSize: S.textSm),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, v, __) {
              final has = v.text.trim().isNotEmpty;
              return Row(
                children: [
                  if (showBang)
                    IconBtn(Icons.call_split, tip: '捋一捋拆词',
                        onTap: has ? onBang : focus.requestFocus),
                  Pressable(
                    onTap: has ? onCommit : null,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: has ? c.accent : c.cardAlt),
                      child: Icon(submitIcon,
                          size: 20, color: has ? Colors.white : c.inkSoft),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 统一页头：返回箭头（可选）+ 标题 + 计数（等宽数字）+ 右侧动作区。
class PageHead extends StatelessWidget {
  final String title;
  final int count; // -1 = 不显示
  final VoidCallback? onBack;
  final List<Widget> actions;
  const PageHead(this.title,
      {super.key, this.count = -1, this.onBack, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.md, S.sm, S.md, S.sm),
      child: Row(
        children: [
          if (onBack != null) ...[
            IconBtn(Icons.arrow_back, onTap: onBack, color: c.ink),
            const SizedBox(width: S.xs),
          ],
          Text(title,
              style: TextStyle(
                  fontSize: S.textXl, fontWeight: FontWeight.bold, color: c.ink)),
          if (count >= 0) ...[
            const SizedBox(width: S.xs),
            Text('$count',
                style: TextStyle(
                    fontSize: S.textSm,
                    color: c.inkSoft,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ],
          const Spacer(),
          ...actions,
        ],
      ),
    );
  }
}
