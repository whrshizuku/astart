import 'package:flutter/material.dart';

import '../data/item.dart';
import '../data/store.dart';
import '../main.dart';
import '../theme/tokens.dart';
import '../widgets/editor.dart';
import '../widgets/ui.dart';
import 'bigbang.dart';

/// 念头 = 独立页（底栏第一键）。
/// 老版 IdeaActivity 交互：单击捋一捋拆词 / 双击删除（撤销）/ 长按进选择态 / 铅笔编辑。
/// 顶栏：返回 + 标题 + 计数 + 一股脑(记一件) + 批量整理(进选择态)。
class IdeaScreen extends StatefulWidget {
  const IdeaScreen({super.key});

  @override
  State<IdeaScreen> createState() => _IdeaScreenState();
}

class _IdeaScreenState extends State<IdeaScreen> {
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

  void _quickAdd() {
    final ctx = StartApp.navigatorKey.currentContext ?? context;
    showQuickAdd(ctx, idea: true);
  }

  /// 写的内容按行/句末标点拆成多条念头。
  Future<void> _commitIdea() async {
    final raw = _ctl.text.trim();
    if (raw.isEmpty) return;
    final parts = splitIntoLines(raw);
    if (parts.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var k = 0; k < parts.length; k++) {
      await StartStore.I.put(
        Item(kind: Item.kindIdea, title: parts[k], rank: -1, created: now + k),
        touchRank: true,
      );
    }
    _ctl.clear();
    if (mounted) {
      setState(() {});
      _inputFocus.requestFocus();
    }
  }

  /// 写的内容先捋一捋拆词，挑中的词各成一条念头。
  Future<void> _bangIdea() async {
    final raw = _ctl.text.trim();
    if (raw.isEmpty || !mounted) return;
    await showBigBang(
      context,
      raw,
      confirmLabel: '拆成念头',
      onDone: (kept) async {
        final now = DateTime.now().millisecondsSinceEpoch;
        for (var k = 0; k < kept.length; k++) {
          await StartStore.I.put(
            Item(kind: Item.kindIdea, title: kept[k], rank: -1, created: now + k),
            touchRank: true,
          );
        }
        if (mounted) setState(() => _ctl.clear());
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
    final ideas = s.ideas();

    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(S.md, S.sm, S.md, S.sm),
              child: Row(
                children: [
                  IconBtn(Icons.arrow_back, onTap: () => Navigator.pop(context), color: c.ink),
                  const SizedBox(width: S.sm),
                  Text('念头',
                      style: TextStyle(
                          fontSize: S.textXl, fontWeight: FontWeight.bold, color: c.ink)),
                  const SizedBox(width: S.xs),
                  Text('${ideas.length}',
                      style: TextStyle(fontSize: S.textSm, color: c.inkSoft)),
                  const Spacer(),
                  if (_selecting) ...[
                    IconBtn(Icons.select_all_outlined, tip: '全选', onTap: () {
                      setState(() {
                        _selected.length == ideas.length
                            ? _selected.clear()
                            : _selected.addAll(ideas.map((e) => e.id));
                      });
                    }),
                    IconBtn(Icons.delete_outline, tip: '删除', onTap: _batchDelete),
                    IconBtn(Icons.close, tip: '完成', onTap: () {
                      setState(() {
                        _selecting = false;
                        _selected.clear();
                      });
                    }),
                  ] else ...[
                    IconBtn(Icons.add, tip: '记一件', onTap: _quickAdd),
                    IconBtn(Icons.delete_outline, tip: '批量整理', onTap: () {
                      if (ideas.isNotEmpty) setState(() => _selecting = true);
                    }),
                  ],
                ],
              ),
            ),
            Expanded(
              child: ideas.isEmpty
                  ? EmptyView(icon: Icons.lightbulb_outline, text: '念头空，在下面写下来')
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(S.md, 0, S.md, S.lg + 16),
                      itemCount: ideas.length,
                      itemBuilder: (_, i) => _IdeaCard(
                        it: ideas[i],
                        selecting: _selecting,
                        selected: _selected,
                        onChange: () => setState(() {}),
                        onEnterSelect: () => setState(() {
                          _selecting = true;
                          _selected.add(ideas[i].id);
                        }),
                      ),
                    ),
            ),
            QuickInputBar(
              controller: _ctl,
              focus: _inputFocus,
              hint: '念头写下来；回车换行多记几条',
              onCommit: _commitIdea,
              onBang: _bangIdea,
            ),
          ],
        ),
      ),
    );
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
    UndoHost.show(context, '已删除', () async => s.restoreJson(snap));
  }
}

/// 念头卡：单击捋一捋拆词，双击删除（撤销），长按进选择态，铅笔编辑。
class _IdeaCard extends StatelessWidget {
  final Item it;
  final bool selecting;
  final Set<int> selected;
  final VoidCallback onChange;
  final VoidCallback onEnterSelect;
  const _IdeaCard({
    required this.it,
    required this.selecting,
    required this.selected,
    required this.onChange,
    required this.onEnterSelect,
  });

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final s = StartStore.I;
    final sel = selected.contains(it.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: S.xs),
      child: Pressable(
        onTap: selecting
            ? () {
                sel ? selected.remove(it.id) : selected.add(it.id);
                onChange();
              }
            : () => showBigBang(context, it.title, confirmLabel: '拆成念头',
                onDone: (kept) async {
                  if (kept.length <= 1) return;
                  final now = DateTime.now().millisecondsSinceEpoch;
                  for (var k = 0; k < kept.length; k++) {
                    await s.put(
                      Item(kind: Item.kindIdea, title: kept[k], rank: -1, created: now + k),
                      touchRank: true,
                    );
                  }
                  final removed = s.delete(it.id, cascade: false);
                  onChange();
                  if (context.mounted) {
                    UndoHost.show(context, '拆成了 ${kept.length} 条', () async {
                      await s.restore(removed);
                    });
                  }
                }),
        onDoubleTap: selecting
            ? null
            : () async {
                final removed = s.delete(it.id, cascade: false);
                onChange();
                if (context.mounted) {
                  UndoHost.show(context, '已删除念头', () async => s.restore(removed));
                }
              },
        onLongPress: selecting ? null : onEnterSelect,
        child: StartCard(
          color: sel ? c.accentSoft : null,
          padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.sm),
          child: Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 16, color: c.inkSoft),
              const SizedBox(width: S.xs),
              Expanded(
                child: Text(it.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: S.textMd,
                        fontWeight: FontWeight.bold,
                        color: c.ink)),
              ),
              if (selecting)
                Icon(
                  sel ? Icons.check_circle : Icons.circle_outlined,
                  color: sel ? c.accent : c.inkSoft,
                  size: 22,
                )
              else ...[
                Pressable(
                  onTap: () => showItemEditor(context, it, onDeleted: onChange),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: S.xs, vertical: S.xxs),
                    child: Icon(Icons.edit_outlined, size: 16, color: c.inkSoft),
                  ),
                ),
                Icon(Icons.call_split, size: 16, color: c.accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
