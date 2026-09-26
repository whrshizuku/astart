// ── 工匠的骄傲与喜悦 · Artisan's Pride & Joy ──
// 致敬 Smartisan OS
// 把每一个细节较真到底，是这件小东西全部的骄傲与喜悦。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/store.dart';
import '../theme/tokens.dart';
import '../l10n/i18n.dart';

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

/// 全局拖拽总线：任何条目被长按拖起时置 true，松手/取消/落下时归位。
/// DragDock（挂在 main.dart 顶层）监听它浮出「垃圾桶 / 思维导图」两个落点。
class DragDockBus {
  DragDockBus._();
  static final ValueNotifier<bool> active = ValueNotifier<bool>(false);

  /// 整批拖拽暂存：多选拖起时由页面写入整组 id，垃圾桶落点读取后清空。
  static List<int>? pendingIds;
}

/// 全局统一长按拖拽行：拖起唤出底部落点底座，反馈样式全局一致
/// （番茄浅底圆角卡，跟随手指）。[enabled]=false 时（如批量选择态）禁用拖拽。
class DraggableLine extends StatelessWidget {
  final int id;
  final String title;
  final bool enabled;
  final Widget child;

  /// 多选整批拖拽时的整组 id（含自身）；单条拖拽留空。
  final List<int>? dragIds;

  /// 整组拖拽时本条也在选中集里：原位同样变半透明。
  final bool selected;

  /// 拖起回调（页面用来退出选择态等）。
  final VoidCallback? onDragStarted;
  const DraggableLine({
    super.key,
    required this.id,
    required this.title,
    required this.child,
    this.enabled = true,
    this.dragIds,
    this.selected = false,
    this.onDragStarted,
  });

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final batch = (dragIds != null && dragIds!.length > 1) ? dragIds!.length : 0;
    return LongPressDraggable<int>(
      data: id,
      maxSimultaneousDrags: enabled ? 1 : 0,
      delay: const Duration(milliseconds: 120),
      // 浮影升到根 Overlay：高于底部红区与输入条，拖到桶上时标签仍在最上层。
      rootOverlay: true,
      onDragStarted: () {
        DragDockBus.active.value = true;
        DragDockBus.pendingIds = batch > 1 ? List.of(dragIds!) : null;
        onDragStarted?.call();
      },
      onDragEnd: (_) {
        DragDockBus.active.value = false;
        DragDockBus.pendingIds = null;
      },
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width - S.md * 2,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 浮影就是整个标签本身，不再另做小字卡。
              child,
              // 多选整批：右上角叠一个番茄红数量标，一眼看出拖的是一组。
              if (batch > 1)
                Positioned(
                  top: -8,
                  right: -8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(tr('{0} 条', [batch]),
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ),
                ),
            ],
          ),
        ),
      ),
      // 整组拖拽时，所有选中条目原位一起变半透明（拖拽进行中才降透明度，
      // 平时选择态保持高亮）。
      child: ValueListenableBuilder<bool>(
        valueListenable: DragDockBus.active,
        builder: (_, dragging, c2) => Opacity(
          opacity: dragging && selected ? 0.45 : 1.0,
          child: c2!,
        ),
        child: child,
      ),
      // 被拖起的那一条：原位恒半透明。
      childWhenDragging: Opacity(opacity: 0.45, child: child),
    );
  }
}

/// 6 秒撤销条：全局栈底浮出，到时静默生效。
class UndoHost extends StatefulWidget {
  const UndoHost({super.key});

  /// 已挂载的实例（全局唯一，挂在 MaterialApp.builder 顶层）。
  static _UndoHostState? _state;

  /// 有底部输入条的页面（念头/捋一捋/小步骤）登记额外避让，撤销条让到输入条上方；
  /// 页面 dispose 时归零。
  static final ValueNotifier<double> extraBottom = ValueNotifier(0);

  /// 显示撤销条。返回后 6 秒过期（过期不执行 onExpire 的删除，由调用方在删除时先快照）。
  static void show(BuildContext context, String text, VoidCallback onUndo) {
    final state = _state ?? context.findAncestorStateOfType<_UndoHostState>();
    state?._show(text, onUndo);
  }

  @override
  State<UndoHost> createState() => _UndoHostState();
}

class _UndoHostState extends State<UndoHost> {
  String? _text;
  VoidCallback? _onUndo;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    UndoHost._state = this;
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (UndoHost._state == this) UndoHost._state = null;
    super.dispose();
  }

  void _show(String text, VoidCallback onUndo) {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 6), _dismiss);
    setState(() {
      _text = text;
      _onUndo = onUndo;
    });
  }

  void _dismiss() {
    _timer?.cancel();
    _timer = null;
    if (!mounted) return;
    setState(() {
      _text = null;
      _onUndo = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    // 拖拽激活时让位给落点底座（两处浮层同一位置，同显会叠字），计时照常走。
    return ValueListenableBuilder<bool>(
      valueListenable: DragDockBus.active,
      builder: (_, dragging, __) {
        final visible = _text != null && !dragging;
        return ValueListenableBuilder<double>(
          valueListenable: UndoHost.extraBottom,
          builder: (_, extra, __) {
            // 底栏胶囊 64 + 手势条 + 间距；有底部输入条的页面再让开输入条。
            final bottom = 64 +
                MediaQuery.viewPaddingOf(context).bottom +
                S.md +
                extra;
            return Positioned(
      left: S.md,
      right: S.md,
      bottom: bottom,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 2),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: Material(
              color: Colors.transparent,
              child: Container(
              padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.xs),
              decoration: BoxDecoration(
                // 白卡 + 番茄红描边，与全局卡片统一（不再用黑底）
                color: c.card,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: c.accent, width: 1.5),
                boxShadow: [
                  BoxShadow(
                      color: c.ink.withValues(alpha: 0.10),
                      blurRadius: 10)
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(_text ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.ink, fontSize: S.textMd)),
                  ),
                  Pressable(
                    onTap: () {
                      _onUndo?.call();
                      _dismiss();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: S.xs, vertical: S.xs),
                      child: Text(tr('撤销'),
                          style: TextStyle(
                              color: c.accent, fontSize: S.textMd, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
            ),
          ),
        ),
      ),
          );
          },
        );
      },
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
/// 按钮必须用 actions 回调给出的 dctx（弹框自身 context）来 pop：
/// 页面在 body 内嵌导航器内、弹框默认挂根导航器，用页面 context 会误关页面、弹框卡住。
Future<T?> showStartDialog<T>(BuildContext context,
    {required String title, Widget? content, required List<Widget> Function(BuildContext dctx) actions}) {
  final c = ThemeTokens.of(context);
  return showDialog<T>(
    context: context,
    builder: (dctx) => AlertDialog(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(S.radius)),
      title: Text(title, style: TextStyle(color: c.ink, fontSize: S.textLg, fontWeight: FontWeight.bold)),
      content: content,
      actions: actions(dctx),
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
  final VoidCallback? onBang;
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
    this.onBang,
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
                    IconBtn(Icons.new_releases_outlined, tip: tr('捋一捋拆词'),
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

/// 全局拖拽删除底座：任何条目长按拖起时，底部升起一条番茄红区域，
/// 中央一个垃圾桶——把条目扔进去即删（6 秒可撤销）。
/// 挂在 MaterialApp.builder 顶层，监听 [DragDockBus.active]。
class DragDock extends StatelessWidget {
  final Future<void> Function(int id)? onTrash;
  const DragDock({super.key, this.onTrash});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: DragDockBus.active,
      builder: (_, on, __) => Positioned(
        left: 0,
        right: 0,
        // 全面屏：红区贴屏幕最底，左右全覆盖。
        bottom: 0,
        child: IgnorePointer(
          ignoring: !on,
          child: AnimatedSlide(
            offset: on ? Offset.zero : const Offset(0, 0.6),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: AnimatedOpacity(
              opacity: on ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              child: DragTarget<int>(
                onAcceptWithDetails: (d) =>
                    (onTrash ?? (_) async {})(d.data),
                builder: (ctx, cand, _) {
                  final hov = cand.isNotEmpty;
                  final navPad = MediaQuery.viewPaddingOf(ctx).bottom;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOut,
                    height: (hov ? 80 : 72) + navPad,
                    padding: EdgeInsets.only(bottom: navPad),
                    decoration: BoxDecoration(
                      // 实心番茄红：悬停时加深一档，扔进去有明确反馈
                      color: hov
                          ? const Color(0xFFE04A2E)
                          : ThemeTokens.of(ctx).accent,
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black
                                .withValues(alpha: hov ? 0.25 : 0.12),
                            blurRadius: hov ? 18 : 10,
                            spreadRadius: hov ? 1 : 0)
                      ],
                    ),
                    child: Center(
                      child: Icon(Icons.delete_outline,
                          size: hov ? 34 : 30, color: Colors.white),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
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
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: S.textXl,
                          fontWeight: FontWeight.bold,
                          color: c.ink)),
                ),
                if (count >= 0) ...[
                  const SizedBox(width: S.xs),
                  Text('$count',
                      style: TextStyle(
                          fontSize: S.textSm,
                          color: c.inkSoft,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ],
              ],
            ),
          ),
          const Spacer(),
          ...actions,
        ],
      ),
    );
  }
}

/// 自定义时间选择面板：替代原生 showTimePicker。
/// 上滑选小时/分钟，下两个大按钮确认/取消，风格统一番茄红。
Future<TimeOfDay?> showStartTimePicker(BuildContext context,
    {TimeOfDay? initial}) async {
  return showStartSheet<TimeOfDay>(context, (ctx) => _TimePickerSheet(initial: initial));
}

class _TimePickerSheet extends StatefulWidget {
  final TimeOfDay? initial;
  const _TimePickerSheet({this.initial});
  @override
  State<_TimePickerSheet> createState() => _TimePickerSheetState();
}

class _TimePickerSheetState extends State<_TimePickerSheet> {
  late int _h;
  late int _m;
  final _hc = FixedExtentScrollController();
  final _mc = FixedExtentScrollController();

  @override
  void initState() {
    super.initState();
    final now = widget.initial ?? TimeOfDay.now();
    _h = now.hour;
    _m = now.minute;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hc.jumpToItem(_h);
      _mc.jumpToItem(_m);
    });
  }

  @override
  void dispose() {
    _hc.dispose();
    _mc.dispose();
    super.dispose();
  }

  Widget _wheel(FixedExtentScrollController ctl, int count, int cur,
      ValueChanged<int> onSel) {
    final c = ThemeTokens.of(context);
    return SizedBox(
      height: 160,
      child: ListWheelScrollView.useDelegate(
        controller: ctl,
        itemExtent: 40,
        perspective: 0.005,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: onSel,
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: count,
          builder: (_, i) {
            final on = i == cur;
            return Center(
              child: Text(
                i.toString().padLeft(2, '0'),
                style: TextStyle(
                  fontSize: on ? 22 : S.textMd,
                  fontWeight: on ? FontWeight.bold : FontWeight.normal,
                  color: on ? c.accent : c.inkSoft,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(S.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(child: _wheel(_hc, 24, _h, (v) => setState(() => _h = v))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: S.sm),
                  child: Text(':',
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold, color: c.ink)),
                ),
                Expanded(child: _wheel(_mc, 60, _m, (v) => setState(() => _m = v))),
              ],
            ),
            const SizedBox(height: S.md),
            Row(
              children: [
                Expanded(
                  child: Pressable(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: S.sm),
                      decoration: BoxDecoration(
                          color: c.cardAlt,
                          borderRadius: BorderRadius.circular(999)),
                      child: Center(
                          child: Text(tr('取消'),
                              style: TextStyle(
                                  fontSize: S.textMd, color: c.ink))),
                    ),
                  ),
                ),
                const SizedBox(width: S.sm),
                Expanded(
                  child: Pressable(
                    onTap: () =>
                        Navigator.pop(context, TimeOfDay(hour: _h, minute: _m)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: S.sm),
                      decoration: BoxDecoration(
                          color: c.accent,
                          borderRadius: BorderRadius.circular(999)),
                      child: Center(
                          child: Text(tr('确认'),
                              style: TextStyle(
                                  fontSize: S.textMd,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white))),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 自定义日期选择面板：替代原生 showDatePicker。
/// 年/月/日三列滚轮，随年月联动当月天数，风格统一番茄红。
Future<DateTime?> showStartDatePicker(BuildContext context,
    {DateTime? initial}) async {
  return showStartSheet<DateTime>(context, (ctx) => _DatePickerSheet(initial: initial));
}

class _DatePickerSheet extends StatefulWidget {
  final DateTime? initial;
  const _DatePickerSheet({this.initial});
  @override
  State<_DatePickerSheet> createState() => _DatePickerSheetState();
}

class _DatePickerSheetState extends State<_DatePickerSheet> {
  // 未来的事最多选一年后的：年份只列今年与明年，选到明年时月/日不超今天。
  late final int _yearBase = DateTime.now().year;
  static const _yearCount = 2;
  late final int _nowMonth = DateTime.now().month;
  late final int _nowDay = DateTime.now().day;
  late int _y, _mo, _d;
  final _yc = FixedExtentScrollController();
  final _mc = FixedExtentScrollController();
  final _dc = FixedExtentScrollController();

  int get _monthCount => _y >= _yearBase + 1 ? _nowMonth : 12;

  int get _daysInMonth {
    final max = DateUtils.getDaysInMonth(_y, _mo);
    if (_y >= _yearBase + 1 && _mo >= _nowMonth) return _nowDay;
    return max;
  }

  @override
  void initState() {
    super.initState();
    final now = widget.initial ?? DateTime.now();
    _y = now.year.clamp(_yearBase, _yearBase + _yearCount - 1);
    _mo = now.month;
    _d = now.day;
    _clampFields();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _yc.jumpToItem(_y - _yearBase);
      _mc.jumpToItem(_mo - 1);
      _dc.jumpToItem((_d - 1).clamp(0, _daysInMonth - 1));
    });
  }

  @override
  void dispose() {
    _yc.dispose();
    _mc.dispose();
    _dc.dispose();
    super.dispose();
  }

  /// 纯字段钳制（初始化用，不碰滚轮控制器）。
  void _clampFields() {
    if (_y >= _yearBase + 1) {
      if (_mo > _nowMonth) _mo = _nowMonth;
      if (_mo == _nowMonth && _d > _nowDay) _d = _nowDay;
    }
    final maxD = _daysInMonth;
    if (_d > maxD) _d = maxD;
  }

  void _clampDay() {
    if (_y >= _yearBase + 1 && _mo > _nowMonth) {
      _mo = _nowMonth;
      _mc.jumpToItem(_mo - 1);
    }
    final max = _daysInMonth;
    if (_d > max) {
      _d = max;
      _dc.jumpToItem(_d - 1);
    }
  }

  Widget _wheel(FixedExtentScrollController ctl, int count, int cur,
      ValueChanged<int> onSel, String Function(int) label) {
    final c = ThemeTokens.of(context);
    return SizedBox(
      height: 160,
      child: ListWheelScrollView.useDelegate(
        controller: ctl,
        itemExtent: 40,
        perspective: 0.005,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: onSel,
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: count,
          builder: (_, i) {
            final on = i == cur;
            return Center(
              child: Text(
                label(i),
                style: TextStyle(
                  fontSize: on ? 22 : S.textMd,
                  fontWeight: on ? FontWeight.bold : FontWeight.normal,
                  color: on ? c.accent : c.inkSoft,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(S.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(child: _wheel(_yc, _yearCount, _y - _yearBase,
                    (v) => setState(() { _y = _yearBase + v; _clampDay(); }),
                    (i) => tr('{0} 年', [_yearBase + i]))),
                const SizedBox(width: S.xs),
                Expanded(child: _wheel(_mc, _monthCount, _mo - 1,
                    (v) => setState(() { _mo = v + 1; _clampDay(); }),
                    (i) => tr('{0} 月', [i + 1]))),
                const SizedBox(width: S.xs),
                Expanded(child: _wheel(_dc, _daysInMonth, _d - 1,
                    (v) => setState(() => _d = v + 1),
                    (i) => tr('{0} 日', [i + 1]))),
              ],
            ),
            const SizedBox(height: S.md),
            Row(
              children: [
                Expanded(
                  child: Pressable(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: S.sm),
                      decoration: BoxDecoration(
                          color: c.cardAlt,
                          borderRadius: BorderRadius.circular(999)),
                      child: Center(
                          child: Text(tr('取消'),
                              style: TextStyle(
                                  fontSize: S.textMd, color: c.ink))),
                    ),
                  ),
                ),
                const SizedBox(width: S.sm),
                Expanded(
                  child: Pressable(
                    onTap: () => Navigator.pop(context, DateTime(_y, _mo, _d)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: S.sm),
                      decoration: BoxDecoration(
                          color: c.accent,
                          borderRadius: BorderRadius.circular(999)),
                      child: Center(
                          child: Text(tr('确认'),
                              style: TextStyle(
                                  fontSize: S.textMd,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white))),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
