import 'package:flutter/material.dart';

import '../data/item.dart';
import '../data/store.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';
import 'bigbang.dart';

/// 捋一捋：把一件事拆成小步骤。支持输入拆词，或手动逐条添加。
class StepsScreen extends StatefulWidget {
  final int taskId;
  const StepsScreen({super.key, required this.taskId});

  @override
  State<StepsScreen> createState() => _StepsScreenState();
}

class _StepsScreenState extends State<StepsScreen> {
  bool _selecting = false;
  final Set<int> _selected = {};
  final TextEditingController _ctl = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  Item? get _task => StartStore.I.byId(widget.taskId);

  @override
  void initState() {
    super.initState();
    // 没有步骤时进来直接弹键盘写。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (StartStore.I.subtasksOf(widget.taskId).isEmpty) _inputFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  /// 写的内容直接存为小步骤（多行/句末标点各存一条）。
  Future<void> _commitInput() async {
    final task = _task;
    final raw = _ctl.text.trim();
    if (task == null || raw.isEmpty) return;
    final parts = splitIntoLines(raw);
    if (parts.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var k = 0; k < parts.length; k++) {
      await StartStore.I.put(Item(
          kind: Item.kindTask,
          parentId: task.id,
          title: parts[k],
          rank: -1,
          created: now + k));
    }
    _ctl.clear();
    if (mounted) {
      setState(() {});
      // 连续写：提交后键盘不收。
      _inputFocus.requestFocus();
    }
  }

  /// 写的内容先大爆炸拆词，挑中的词各存一条步骤。
  Future<void> _bangInput() async {
    final task = _task;
    final raw = _ctl.text.trim();
    if (task == null || raw.isEmpty || !mounted) return;
    await showBigBang(
      context,
      raw,
      confirmLabel: '存为小步骤',
      onDone: (kept) async {
        await saveKeptAsSteps(kept, task);
        if (mounted) {
          _ctl.clear();
          setState(() {});
        }
      },
    );
  }

  /// 手动加一条步骤。
  Future<void> _addStep() async {
    final c = ThemeTokens.of(context);
    final ctl = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(S.radius)),
        title: Text('加一步',
            style: TextStyle(color: c.ink, fontSize: S.textLg, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctl,
          autofocus: true,
          style: TextStyle(fontSize: S.textLg, color: c.ink),
          cursorColor: c.accent,
          decoration: InputDecoration(hintText: '写清楚这一步做什么', hintStyle: TextStyle(color: c.inkSoft)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('算了', style: TextStyle(color: c.inkSoft))),
          TextButton(
            onPressed: () => Navigator.pop(context, ctl.text.trim()),
            child: Text('好', style: TextStyle(color: c.accent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    ctl.dispose();
    final task = _task;
    if (v == null || v.isEmpty || task == null || !mounted) return;
    final it = Item(kind: Item.kindTask, parentId: task.id, title: v);
    await StartStore.I.put(it);
    setState(() {});
  }

  /// 编辑步骤文字。
  Future<void> _editStep(Item it) async {
    final c = ThemeTokens.of(context);
    final ctl = TextEditingController(text: it.title);
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(S.radius)),
        title: Text('改这一步',
            style: TextStyle(color: c.ink, fontSize: S.textLg, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctl,
          autofocus: true,
          style: TextStyle(fontSize: S.textLg, color: c.ink),
          cursorColor: c.accent,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('算了', style: TextStyle(color: c.inkSoft))),
          TextButton(
            onPressed: () => Navigator.pop(context, ctl.text.trim()),
            child: Text('好', style: TextStyle(color: c.accent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (v == null || v.isEmpty || !mounted) return;
    it.title = v;
    await StartStore.I.put(it);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: StartStore.I,
        builder: (context, _) => _build(context),
      );

  Widget _build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final s = StartStore.I;
    final task = _task;
    if (task == null) {
      return Scaffold(
        backgroundColor: c.paper,
        body: const Center(child: Text('这件事不存在了')),
      );
    }
    final steps = s.subtasksOf(task.id);

    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(S.md, S.sm, S.md, S.sm),
              child: Row(
                children: [
                  IconBtn(Icons.arrow_back, onTap: () => Navigator.pop(context)),
                  const Spacer(),
                  if (_selecting) ...[
                    IconBtn(Icons.delete_outline, tip: '删除所选', onTap: () => _deleteBatch()),
                    IconBtn(Icons.close, tip: '退出选择', onTap: () {
                      setState(() {
                        _selecting = false;
                        _selected.clear();
                      });
                    }),
                  ] else ...[
                    IconBtn(Icons.add, tip: '加一步', onTap: _addStep),
                    IconBtn(Icons.delete_outline, tip: '批量整理', onTap: () {
                      if (steps.isNotEmpty) setState(() => _selecting = true);
                    }),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.md),
              child: StartCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.title,
                        style: TextStyle(
                            fontSize: S.textLg, fontWeight: FontWeight.bold, color: c.ink)),
                    if (steps.isNotEmpty) ...[
                      const SizedBox(height: S.xs),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: steps.every((e) => e.done)
                                    ? 1
                                    : steps.where((e) => e.done).length / steps.length,
                                minHeight: 6,
                                backgroundColor: c.cardAlt,
                                color: c.accent,
                              ),
                            ),
                          ),
                          const SizedBox(width: S.sm),
                          Text(
                            '${steps.where((e) => e.done).length}/${steps.length}',
                            style: TextStyle(
                                fontSize: S.textSm,
                                color: c.inkSoft,
                                fontFeatures: const [FontFeature.tabularFigures()]),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: S.sm),
            Expanded(
              child: steps.isEmpty
                  ? EmptyView(
                      icon: Icons.playlist_add,
                      text: '在下面写一步，一步一步来',
                    )
                  : _StepList(steps: steps, task: task, selecting: _selecting, selected: _selected,
                      onToggleSelect: (id) => setState(() {
                        _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
                      }),
                      onEdit: _editStep,
                      onReorder: _reorderSteps),
            ),
            QuickInputBar(
              controller: _ctl,
              focus: _inputFocus,
              hint: '写一步；回车换行多写几步',
              onCommit: _commitInput,
              onBang: _bangInput,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteBatch() async {
    final s = StartStore.I;
    final snap = await s.deleteAll(_selected.toList());
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    if (!mounted) return;
    UndoHost.show(context, '已删除所选', () async => s.restoreJson(snap));
  }

  /// 长按拖动排序：重写 created（subtasksOf 按 created 升序）。
  Future<void> _reorderSteps(int o, int n) async {
    final s = StartStore.I;
    final task = _task;
    if (task == null) return;
    final steps = s.subtasksOf(task.id);
    if (n > o) n--;
    if (o == n) return;
    final ids = steps.map((e) => e.id).toList();
    final id = ids.removeAt(o);
    ids.insert(n, id);
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var k = 0; k < ids.length; k++) {
      final it = s.byId(ids[k]);
      if (it != null) {
        it.created = now + k;
        await s.put(it);
      }
    }
  }
}

class _StepList extends StatelessWidget {
  final List<Item> steps;
  final Item task;
  final bool selecting;
  final Set<int> selected;
  final ValueChanged<int> onToggleSelect;
  final ValueChanged<Item> onEdit;
  final void Function(int oldIndex, int newIndex) onReorder;

  const _StepList({
    required this.steps,
    required this.task,
    required this.selecting,
    required this.selected,
    required this.onToggleSelect,
    required this.onEdit,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final s = StartStore.I;
    // 当前该做的那张：第一个未完成的步骤
    final currentId = steps.firstWhere((e) => !e.done, orElse: () => steps.last).id;

    return ReorderableListView.builder(
      buildDefaultDragHandles: !selecting,
      proxyDecorator: (child, i, a) => ScaleTransition(scale: a, child: child),
      padding: const EdgeInsets.fromLTRB(S.md, 0, S.md, S.lg),
      itemCount: steps.length,
      onReorder: onReorder,
      itemBuilder: (_, i) {
        final it = steps[i];
        final sel = selected.contains(it.id);
        final isCurrent = it.id == currentId && !it.done;
        return Padding(
          key: ValueKey(it.id),
          padding: const EdgeInsets.only(bottom: S.xs),
          child: Pressable(
            onTap: selecting
                ? () => onToggleSelect(it.id)
                : () async {
                    it.done = !it.done;
                    await s.put(it);
                    // 子步骤全部完成 → 父任务自动勾上
                    final all = s.subtasksOf(task.id);
                    if (all.isNotEmpty && all.every((e) => e.done) && !task.done) {
                      task.done = true;
                      await s.put(task);
                    }
                    if (!it.done) {
                      if (s.prefBool('haptic', true)) {
                        // 完成反馈
                      }
                    }
                  },
            onDoubleTap: () async {
              final removed = s.delete(it.id, cascade: false);
              UndoHost.show(context, '已删除步骤', () async => s.restore(removed));
            },
            child: StartCard(
              color: sel
                  ? c.accentSoft
                  : isCurrent
                      ? c.accentSoft
                      : null,
              padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.sm),
              child: Row(
                children: [
                  if (selecting)
                    Icon(sel ? Icons.check_circle : Icons.circle_outlined,
                        color: sel ? c.accent : c.inkSoft, size: 22)
                  else
                    CheckDot(done: it.done),
                  const SizedBox(width: S.sm),
                  Expanded(
                    child: Text(
                      it.title,
                      style: TextStyle(
                        fontSize: S.textMd,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                        color: it.done ? c.done : c.ink,
                        decoration: it.done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                  if (!selecting)
                    IconBtn(Icons.edit_outlined, tip: '改这一步', color: c.inkSoft,
                        onTap: () => onEdit(it)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
