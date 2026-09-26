import 'package:flutter/material.dart';

import '../channels/native.dart';
import '../data/item.dart';
import '../data/store.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';
import '../l10n/i18n.dart';

/// 捋一捋 · 大爆炸拆词浮层。
/// 词芯片默认全选（番茄红底），单击取消选择，双击删词，铅笔编辑，长按拖动换位。
class BigBangSheet extends StatefulWidget {
  final String text;
  final String? confirmLabel;
  final ValueChanged<List<String>> onDone;
  const BigBangSheet({super.key, required this.text, required this.onDone, this.confirmLabel});

  @override
  State<BigBangSheet> createState() => _BigBangSheetState();
}

class _BigBangSheetState extends State<BigBangSheet> {
  List<String> _words = [];
  Set<int> _picked = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _segment();
  }

  Future<void> _segment() async {
    final w = await Native.words(widget.text);
    if (!mounted) return;
    setState(() {
      _words = w;
      _picked = {for (var i = 0; i < w.length; i++) i};
      _loading = false;
    });
  }

  Future<void> _editWord(int i) async {
    final c = ThemeTokens.of(context);
    final ctl = TextEditingController(text: _words[i]);
    final v = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(S.radius)),
        title: Text(tr('改这个词'),
            style: TextStyle(color: c.ink, fontSize: S.textLg, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctl,
          autofocus: true,
          style: TextStyle(fontSize: S.textLg, color: c.ink),
          cursorColor: c.accent,
        ),
        actions: [
          // 必须用弹框自身的 dctx：浮层挂在 body 内嵌导航器、弹框挂在根导航器，
          // 用浮层 context 会误关拆词浮层、弹框反而卡住没反应。
          TextButton(onPressed: () => Navigator.pop(dctx), child: Text(tr('算了'), style: TextStyle(color: c.inkSoft))),
          TextButton(
            onPressed: () => Navigator.pop(dctx, ctl.text.trim()),
            child: Text(tr('好'), style: TextStyle(color: c.accent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (v == null || !mounted) return;
    setState(() {
      if (v.isEmpty) {
        _words.removeAt(i);
        _picked = _picked.map((e) => e > i ? e - 1 : e).toSet();
      } else {
        _words[i] = v;
      }
    });
  }

  /// 手动加一个词（拆不出词 / 短句场景直接补步骤）。
  Future<void> _addWord() async {
    final c = ThemeTokens.of(context);
    final ctl = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(S.radius)),
        title: Text(tr('加一步'),
            style: TextStyle(color: c.ink, fontSize: S.textLg, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctl,
          autofocus: true,
          style: TextStyle(fontSize: S.textLg, color: c.ink),
          cursorColor: c.accent,
          decoration: InputDecoration(hintText: tr('写清楚这一步做什么'), hintStyle: TextStyle(color: c.inkSoft)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx), child: Text(tr('算了'), style: TextStyle(color: c.inkSoft))),
          TextButton(
            onPressed: () => Navigator.pop(dctx, ctl.text.trim()),
            child: Text(tr('好'), style: TextStyle(color: c.accent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (v == null || v.isEmpty || !mounted) return;
    setState(() {
      _words.add(v);
      _picked.add(_words.length - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final pad = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(left: S.md, right: S.md, top: S.lg, bottom: pad + S.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Text(tr('捋一捋'),
                style: TextStyle(fontSize: S.textLg, fontWeight: FontWeight.bold, color: c.ink)),
          ),
          const SizedBox(height: S.xs),
          Center(
            child: Text(tr('点一下取消选中，双击删掉，长按改词，下面可手动补一步'),
                style: TextStyle(fontSize: S.textSm, color: c.inkSoft)),
          ),
          const SizedBox(height: S.md),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(S.lg),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_words.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: S.lg),
              child: Center(child: Text(tr('没拆出词，直接在下面手动加'), style: TextStyle(color: c.inkSoft))),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                child: _ChipWrap(
                  words: _words,
                  picked: _picked,
                  onTap: (i) => setState(() {
                    _picked.contains(i) ? _picked.remove(i) : _picked.add(i);
                  }),
                  onDoubleTap: (i) => setState(() {
                    _words.removeAt(i);
                    // 删除 i 后，其后的下标整体前移一位，选中集同步迁移。
                    _picked = _picked
                        .where((e) => e != i)
                        .map((e) => e > i ? e - 1 : e)
                        .toSet();
                  }),
                  onLongPress: _editWord,
                  onReorder: (from, to) => setState(() {
                    final w = _words.removeAt(from);
                    _words.insert(to.clamp(0, _words.length), w);
                    final np = <int>{};
                    for (final p in _picked) {
                      np.add(p == from
                          ? to
                          : (p >= to && p < from ? p + 1 : (p <= to && p > from ? p - 1 : p)));
                    }
                    _picked
                      ..clear()
                      ..addAll(np);
                  }),
                ),
              ),
            ),
          const SizedBox(height: S.md),
          if (!_loading)
            Pressable(
              onTap: _addWord,
              child: Container(
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.cardAlt,
                  borderRadius: BorderRadius.circular(S.radius),
                  border: Border.all(color: c.line),
                ),
                child: Text(tr('手动加一步'),
                    style: TextStyle(color: c.inkSoft, fontSize: S.textMd, fontWeight: FontWeight.bold)),
              ),
            ),
          const SizedBox(height: S.xs),
          if (!_loading && _words.isNotEmpty)
            Pressable(
              onTap: () {
                final kept = <String>[];
                final idx = _picked.toList()..sort();
                for (final i in idx) {
                  kept.add(_words[i]);
                }
                widget.onDone(kept);
                // 回调存完即关浮层，避免再点一次重复入库。
                Navigator.of(context).pop();
              },
              child: Container(
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(S.radius)),
                child: Text(tr('{0}（已选 {1}/{2}）',
                    [widget.confirmLabel ?? tr('就这样'), _picked.length, _words.length]),
                    style: const TextStyle(
                        color: Colors.white, fontSize: S.textMd, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }
}

/// 可拖动换位的词芯片流。
class _ChipWrap extends StatelessWidget {
  final List<String> words;
  final Set<int> picked;
  final void Function(int) onTap;
  final void Function(int) onDoubleTap;
  final void Function(int) onLongPress;
  final void Function(int from, int to) onReorder;

  const _ChipWrap({
    required this.words,
    required this.picked,
    required this.onTap,
    required this.onDoubleTap,
    required this.onLongPress,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Wrap(
      spacing: S.xs,
      runSpacing: S.xs,
      children: [
        for (var i = 0; i < words.length; i++)
          DragTarget<int>(
            onWillAcceptWithDetails: (d) => d.data != i,
            onAcceptWithDetails: (d) => onReorder(d.data, i),
            builder: (_, __, ___) => Draggable<int>(
              data: i,
              feedback: _chip(context, c, i, lifted: true),
              childWhenDragging: Opacity(opacity: 0.3, child: _chip(context, c, i)),
              child: _chip(context, c, i),
            ),
          ),
      ],
    );
  }

  Widget _chip(BuildContext context, C c, int i, {bool lifted = false}) {
    final on = picked.contains(i);
    return Pressable(
      onTap: () => onTap(i),
      onDoubleTap: () => onDoubleTap(i),
      onLongPress: () => onLongPress(i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: S.sm, vertical: S.xs),
        decoration: BoxDecoration(
          color: on ? c.accent : c.card,
          borderRadius: BorderRadius.circular(S.sm),
          border: Border.all(color: on ? c.accent : c.line),
          boxShadow: lifted
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8)]
              : null,
        ),
        child: Text(
          words[i],
          style: TextStyle(
            fontSize: S.textMd,
            fontWeight: FontWeight.bold,
            color: on ? Colors.white : c.ink,
          ),
        ),
      ),
    );
  }
}

/// 打开大爆炸浮层（供念头/步骤共用）。
Future<void> showBigBang(
  BuildContext context,
  String text, {
  required ValueChanged<List<String>> onDone,
  String? confirmLabel,
}) {
  return showStartSheet(
    context,
    (_) => BigBangSheet(text: text, onDone: onDone, confirmLabel: confirmLabel),
  );
}

/// 把拆出的词存成任务小步骤（首页焦点卡与步骤页共用）。
Future<void> saveKeptAsSteps(List<String> kept, Item task) async {
  if (kept.isEmpty) return;
  final now = DateTime.now().millisecondsSinceEpoch;
  for (var k = 0; k < kept.length; k++) {
    await StartStore.I.put(Item(
        kind: Item.kindTask,
        parentId: task.id,
        title: kept[k],
        rank: -1,
        created: now + k));
  }
}

/// 扇形菜单「捋一捋」入口：先输入一段话 → 大爆炸拆词 → 选中的词各存一条念头。
/// 体现「先动手（存）再捋一捋（拆）」：动手吧负责倾倒，捋一捋负责把一条念头炸开成多条。
Future<void> showBigBangFromInput(BuildContext context, {String initial = ''}) async {
  final ctl = TextEditingController(text: initial);
  final text = await showStartSheet<String>(
    context,
    (_) => Padding(
      padding: EdgeInsets.only(
        left: S.md,
        right: S.md,
        top: S.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + S.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr('捋一捋'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: S.textLg, fontWeight: FontWeight.bold, color: ThemeTokens.of(context).ink)),
          const SizedBox(height: S.xs),
          Text(tr('把一段话粘进来，拆成词，挑着留下'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: S.textSm, color: ThemeTokens.of(context).inkSoft)),
          const SizedBox(height: S.md),
          TextField(
            controller: ctl,
            autofocus: true,
            minLines: 2,
            maxLines: 6,
            style: TextStyle(fontSize: S.textLg, color: ThemeTokens.of(context).ink),
            decoration: InputDecoration(
              hintText: tr('想拆开的话…'),
              hintStyle: TextStyle(color: ThemeTokens.of(context).inkSoft),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(S.radius),
                borderSide: BorderSide(color: ThemeTokens.of(context).line),
              ),
            ),
          ),
          const SizedBox(height: S.md),
          Pressable(
            onTap: () => Navigator.pop(context, ctl.text.trim()),
            child: Container(
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: ThemeTokens.of(context).accent,
                  borderRadius: BorderRadius.circular(S.radius)),
              child: Text(tr('就这样'),
                  style: TextStyle(color: Colors.white, fontSize: S.textMd, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    ),
  );
  ctl.dispose();
  if (text == null || text.isEmpty || !context.mounted) return;
  await showBigBang(context, text, confirmLabel: tr('拆成念头'), onDone: (kept) async {
    if (kept.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final added = <int>[];
    for (var k = 0; k < kept.length; k++) {
      final it = Item(kind: Item.kindIdea, title: kept[k], rank: -1, created: now + k);
      await StartStore.I.put(it, touchRank: true);
      added.add(it.id);
    }
    if (context.mounted) {
      UndoHost.show(context, tr('拆成 {0} 条念头', [kept.length]), () async {
        for (final id in added) {
          StartStore.I.delete(id, cascade: false);
        }
      });
    }
  });
}
