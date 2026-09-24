import 'package:flutter/material.dart';

import '../data/item.dart';
import '../data/store.dart';
import '../theme/tokens.dart';
import '../widgets/editor.dart';
import '../widgets/ui.dart';
import 'bigbang.dart';
import 'mindmap.dart';

/// 捋一捋 = 暂存条目的分类与拆词工坊，也支持「开始」的速记逻辑。
/// 底部常驻输入条：写下来直接按行 / 句末标点拆成多条暂存，⑂ 可先拆词再存。
/// 进来之后：
///   - 单条分类为 日程（设时间）/ 随手做
///   - 单条捋一捋（大爆炸拆词），选中词各成一条新暂存，再逐条分类
///   - 批量选择后整体分类或删除（带撤销）
/// 暂存一旦分类即离开本页（流入首页三块）。
class SegmentScreen extends StatefulWidget {
  const SegmentScreen({super.key});

  @override
  State<SegmentScreen> createState() => _SegmentScreenState();
}

class _SegmentScreenState extends State<SegmentScreen> {
  bool _selecting = false;
  final Set<int> _selected = {};
  final TextEditingController _ctl = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  @override
  void dispose() {
    _ctl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  /// 写的内容按行 / 句末标点拆成多条暂存（与「开始」同一规则）。
  Future<void> _commitInbox() async {
    final parts = splitIntoLines(_ctl.text);
    if (parts.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var k = 0; k < parts.length; k++) {
      await StartStore.I.put(
        Item(kind: Item.kindInbox, title: parts[k], rank: -1, created: now + k),
        touchRank: true,
      );
    }
    _ctl.clear();
    if (mounted) {
      setState(() {});
      _inputFocus.requestFocus();
    }
  }

  /// 写的内容先捋一捋拆词，挑中的词各成一条暂存。
  Future<void> _bangInbox() async {
    final raw = _ctl.text.trim();
    if (raw.isEmpty || !mounted) return;
    await showBigBang(
      context,
      raw,
      confirmLabel: '拆成几条',
      onDone: (kept) async {
        final now = DateTime.now().millisecondsSinceEpoch;
        for (var k = 0; k < kept.length; k++) {
          await StartStore.I.put(
            Item(kind: Item.kindInbox, title: kept[k], rank: -1, created: now + k),
            touchRank: true,
          );
        }
        if (mounted) {
          setState(() => _ctl.clear());
          _inputFocus.requestFocus();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: StartStore.I,
        builder: (context, _) => _build(context),
      );

  Widget _build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final s = StartStore.I;
    final list = s.inboxTasks();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            PageHead(
              '捋一捋',
              count: list.length,
              onBack: () => Navigator.pop(context),
              actions: _selecting
                  ? [
                      IconBtn(Icons.select_all_outlined, tip: '全选', onTap: () {
                        setState(() {
                          _selected.length == list.length
                              ? _selected.clear()
                              : _selected.addAll(list.map((e) => e.id));
                        });
                      }),
                      IconBtn(Icons.checklist_outlined, tip: '全变随手做',
                          onTap: () => _batchClassify(Item.kindTask, dueTime: 0)),
                      IconBtn(Icons.delete_outline, tip: '删除', onTap: _batchDelete),
                      IconBtn(Icons.close, tip: '退出选择', onTap: () {
                        setState(() {
                          _selecting = false;
                          _selected.clear();
                        });
                      }),
                    ]
                  : [
                      IconBtn(Icons.add, tip: '新建', onTap: _newOne),
                      IconBtn(Icons.playlist_add_check, tip: '批量整理', onTap: () {
                        if (list.isNotEmpty) setState(() => _selecting = true);
                      }),
                    ],
            ),
            Expanded(
              child: list.isEmpty
                  ? EmptyView(
                      icon: Icons.call_split,
                      text: '在下面写点什么，自动拆成几条再捋',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(S.md, 0, S.md, S.sm),
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final it = list[i];
                        final sel = _selected.contains(it.id);
                        return Padding(
                          key: ValueKey(it.id),
                          padding: const EdgeInsets.only(bottom: S.xs),
                          child: _InboxCard(
                            it: it,
                            selected: sel,
                            selecting: _selecting,
                            onToggle: () => setState(() {
                              sel ? _selected.remove(it.id) : _selected.add(it.id);
                            }),
                            onEnterSelect: () => setState(() {
                              _selecting = true;
                              _selected.add(it.id);
                            }),
                            onChange: () => setState(() {}),
                          ),
                        );
                      },
                    ),
            ),
            // 批量整理时收起输入条，避免边选边记误操作。
            if (!_selecting)
              QuickInputBar(
                controller: _ctl,
                focus: _inputFocus,
                hint: '直接写下来；回车换行多记几条',
                onCommit: _commitInbox,
                onBang: _bangInbox,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _batchClassify(int kind, {int? dueTime}) async {
    if (_selected.isEmpty) return;
    final s = StartStore.I;
    final snap = s.exportJson();
    for (final id in _selected) {
      final it = s.byId(id);
      if (it != null && it.isInbox) {
        it.kind = kind;
        if (dueTime != null) it.dueTime = dueTime;
        if (kind == Item.kindTask && dueTime == 0) it.alarm = false;
        await s.put(it);
      }
    }
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    if (!mounted) return;
    UndoHost.show(context, '已分类', () async => s.restoreJson(snap));
  }

  Future<void> _batchDelete() async {
    if (_selected.isEmpty) return;
    final s = StartStore.I;
    final snap = await s.deleteAll(_selected.toList());
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    if (!mounted) return;
    UndoHost.show(context, '已删除所选', () async => s.restoreJson(snap));
  }

  /// 新建一条暂存（根导航弹层，盖住底栏）。
  void _newOne() {
    showQuickAdd(Navigator.of(context, rootNavigator: true).context, inbox: true);
  }
}

/// 暂存卡片：文本 + 分类（日程/随手做）+ 捋一捋拆词 + 删除。
class _InboxCard extends StatelessWidget {
  final Item it;
  final bool selected;
  final bool selecting;
  final VoidCallback onToggle;
  final VoidCallback onEnterSelect;
  final VoidCallback onChange;
  const _InboxCard({
    required this.it,
    required this.selected,
    required this.selecting,
    required this.onToggle,
    required this.onEnterSelect,
    required this.onChange,
  });

  Future<void> _toAnytime() async {
    it.kind = Item.kindTask;
    it.dueTime = 0;
    it.alarm = false;
    await StartStore.I.put(it);
    onChange();
  }

  Future<void> _toSchedule(BuildContext context) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: it.dueTime > 0 ? DateTime.fromMillisecondsSinceEpoch(it.dueTime) : now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (d == null) return;
    if (!context.mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: it.dueTime > 0
          ? TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(it.dueTime))
          : TimeOfDay.now(),
    );
    if (t == null) return;
    it.kind = Item.kindTask;
    it.dueTime = DateTime(d.year, d.month, d.day, t.hour, t.minute).millisecondsSinceEpoch;
    it.alarm = true;
    await StartStore.I.put(it);
    onChange();
  }

  /// 捋一捋：大爆炸拆词，选中词各成一条新暂存，原条删除。
  Future<void> _split(BuildContext context) async {
    await showBigBang(context, it.title, confirmLabel: '拆成几条', onDone: (kept) async {
      if (kept.isEmpty) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var k = 0; k < kept.length; k++) {
        await StartStore.I.put(
          Item(kind: Item.kindInbox, title: kept[k], rank: -1, created: now + k),
          touchRank: true,
        );
      }
      final removed = StartStore.I.delete(it.id, cascade: false);
      onChange();
      if (context.mounted) {
        UndoHost.show(context, '拆成 ${kept.length} 条', () async {
          await StartStore.I.restore(removed);
        });
      }
    });
  }

  Future<void> _delete(BuildContext context) async {
    final removed = StartStore.I.delete(it.id, cascade: false);
    onChange();
    if (context.mounted) {
      UndoHost.show(context, '删了一条', () async => StartStore.I.restore(removed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Pressable(
      onTap: selecting ? onToggle : null,
      onLongPress: selecting ? null : onEnterSelect,
      child: StartCard(
        color: selected ? c.accentSoft : null,
        padding: const EdgeInsets.all(S.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.inbox_outlined, size: 16, color: c.inkSoft),
                const SizedBox(width: S.xs),
                Expanded(
                  child: Text(it.title,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: S.textMd, color: c.ink, height: 1.4)),
                ),
                if (selecting)
                  Icon(
                    selected ? Icons.check_circle : Icons.circle_outlined,
                    color: selected ? c.accent : c.inkSoft,
                    size: 22,
                  ),
              ],
            ),
            if (!selecting) ...[
              const SizedBox(height: S.sm),
              Row(
                children: [
                  _Act(icon: Icons.event_outlined, onTap: () => _toSchedule(context)),
                  const SizedBox(width: S.xs),
                  _Act(icon: Icons.checklist_outlined, onTap: () => _toAnytime()),
                  const Spacer(),
                  IconBtn(Icons.account_tree_outlined, tip: '导图', color: c.accent,
                      onTap: () {
                    Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute(builder: (_) => MindMapScreen(rootId: it.id)));
                  }),
                  IconBtn(Icons.call_split, tip: '捋一捋', color: c.accent,
                      onTap: () => _split(context)),
                  IconBtn(Icons.edit_outlined, tip: '编辑', color: c.inkSoft,
                      onTap: () => showTextEdit(context, it, onSaved: onChange)),
                  IconBtn(Icons.delete_outline, tip: '删除', color: c.inkSoft,
                      onTap: () => _delete(context)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 分类小圆钮（纯图标）。
class _Act extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _Act({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(shape: BoxShape.circle, color: c.cardAlt),
        child: Icon(icon, size: 16, color: c.ink),
      ),
    );
  }
}


