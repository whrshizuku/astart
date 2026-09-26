import 'package:flutter/material.dart';
import '../data/item.dart';
import '../data/store.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';
import '../l10n/i18n.dart';

/// 导图索引页：列出所有根导图（kindInbox 且 parentId==0 的条目）。
/// 从捋一捋右上角进入，可新建、点进编辑、批量删除。
class MindMapIndexScreen extends StatefulWidget {
  const MindMapIndexScreen({super.key});

  @override
  State<MindMapIndexScreen> createState() => _MindMapIndexScreenState();
}

class _MindMapIndexScreenState extends State<MindMapIndexScreen> {
  List<Item> _roots() => StartStore.I.items
      .where((e) => e.isInbox && e.parentId == 0 && !e.done)
      .toList();

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final list = _roots();
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Column(
          children: [
            PageHead(tr('导图'),
                count: list.length,
                onBack: () => Navigator.pop(context),
                actions: [
                  IconBtn(Icons.add, tip: tr('新建导图'), onTap: () async {
                    final s = StartStore.I;
                    final n = Item(kind: Item.kindInbox, title: tr('新导图'), rank: -1);
                    await s.put(n);
                    if (!mounted) return;
                    Navigator.push(context, MaterialPageRoute(
                        builder: (_) => MindMapScreen(rootId: n.id)));
                  }),
                ]),
            Expanded(
              child: list.isEmpty
                  ? EmptyView(
                      icon: Icons.account_tree_outlined,
                      text: tr('还没有导图，点右上角新建一个'))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(S.md, 0, S.md, S.sm),
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final it = list[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: S.xs),
                          child: Pressable(
                            onTap: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => MindMapScreen(rootId: it.id))),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.sm),
                              decoration: BoxDecoration(
                                color: c.card,
                                borderRadius: BorderRadius.circular(S.radius),
                                border: Border.all(color: c.line),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      it.title.trim().isEmpty ? tr('（空）') : it.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: S.textMd, color: c.ink),
                                    ),
                                  ),
                                  Text(tr('{0} 节点', [StartStore.I.subtasksOf(it.id).length]),
                                      style: TextStyle(fontSize: S.textSm, color: c.inkSoft)),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 思维导图：以一条暂存为根、向右生长的树。
/// 数据即 kindInbox 子条目（parentId 挂树，与数据层完全兼容）。
/// 交互：点按选中，选中后底部工具列 加子节点/加同级/编辑/删除；
/// 按住拖动自由移动（连同子树），重排钮恢复自动布局。
class MindMapScreen extends StatefulWidget {
  final int rootId;
  const MindMapScreen({super.key, required this.rootId});

  @override
  State<MindMapScreen> createState() => _MindMapScreenState();
}

class _MindMapScreenState extends State<MindMapScreen> {
  static const _nodeW = 168.0, _nodeH = 48.0, _gapX = 36.0, _gapY = 10.0;

  int _sel = 0;
  bool _selecting = false;
  final Set<int> _selected = {};
  final Map<int, Offset> _delta = {}; // 拖动偏移（连同子树）

  Item? get _root => StartStore.I.byId(widget.rootId);
  List<Item> _children(int id) => StartStore.I
      .subtasksOf(id)
      .where((e) => e.isInbox)
      .toList();

  void _descIds(int id, List<int> out) {
    for (final k in _children(id)) {
      out.add(k.id);
      _descIds(k.id, out);
    }
  }

  double _heightOf(Item n) {
    final kids = _children(n.id);
    if (kids.isEmpty) return _nodeH;
    var h = 0.0;
    for (final k in kids) {
      h += _heightOf(k) + _gapY;
    }
    return h - _gapY;
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final root = _root;
    if (root == null) {
      return Scaffold(
        backgroundColor: c.paper,
        body: SafeArea(child: EmptyView(icon: Icons.account_tree_outlined, text: tr('这条已不在了'))),
      );
    }
    final ids = <int>[];
    _descIds(root.id, ids);
    final total = 1 + ids.length;

    // 自动布局 + 拖动偏移 → 位置与连线
    final nodes = <Item, Offset>{};
    final edges = <List<Offset>>[];
    void place(Item n, double x, double top) {
      final h = _heightOf(n);
      final base = Offset(x, top + h / 2 - _nodeH / 2);
      nodes[n] = base + (_delta[n.id] ?? Offset.zero);
      var ky = top;
      for (final k in _children(n.id)) {
        final kh = _heightOf(k);
        place(k, x + _nodeW + _gapX, ky);
        ky += kh + _gapY;
      }
    }

    place(root, 0, 0);
    for (final n in nodes.keys) {
      for (final k in _children(n.id)) {
        final p = nodes[n]!, q = nodes[k];
        if (q != null) edges.add([p + Offset(_nodeW, _nodeH / 2), q + Offset(0, _nodeH / 2)]);
      }
    }
    var maxX = _nodeW, maxY = _nodeH;
    for (final p in nodes.values) {
      if (p.dx + _nodeW > maxX) maxX = p.dx + _nodeW;
      if (p.dy + _nodeH > maxY) maxY = p.dy + _nodeH;
    }

    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Column(
          children: [
            PageHead(tr('导图'),
                count: total,
                onBack: () => Navigator.pop(context),
                actions: [
                  IconBtn(Icons.add, tip: tr('新建导图'), onTap: _newMap),
                  if (_delta.isNotEmpty)
                    IconBtn(Icons.restart_alt, tip: tr('重排'), onTap: () => setState(() => _delta.clear())),
                ]),
            Expanded(
              child: InteractiveViewer(
                constrained: false,
                minScale: 0.4,
                maxScale: 2.5,
                child: SizedBox(
                  width: maxX + S.lg,
                  height: maxY + S.lg,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _EdgePainter(
                              edges: edges, color: c.line, accent: c.accent),
                        ),
                      ),
                      for (final e in nodes.entries) _node(e.key, e.value, c),
                    ],
                  ),
                ),
              ),
            ),
            _toolbar(c),
          ],
        ),
      ),
    );
  }

  Widget _node(Item n, Offset pos, C c) {
    final isRoot = n.id == widget.rootId;
    final sel = _selecting ? _selected.contains(n.id) : _sel == n.id;
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      width: _nodeW,
      height: _nodeH,
      child: GestureDetector(
        // 按住拖动：连同子树一起移动。
        onPanUpdate: (d) {
          setState(() {
            final ids = [n.id];
            _descIds(n.id, ids);
            for (final id in ids) {
              _delta[id] = (_delta[id] ?? Offset.zero) + d.delta;
            }
          });
        },
        onLongPress: () => _nodeMenu(n),
        child: Pressable(
          onTap: () {
            if (_selecting) {
              setState(() {
                if (_selected.contains(n.id)) {
                  _selected.remove(n.id);
                } else {
                  _selected.add(n.id);
                }
              });
            } else {
              setState(() => _sel = n.id);
            }
          },
          onDoubleTap: () => _editNode(n),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: S.sm, vertical: S.xxs),
            decoration: BoxDecoration(
              color: isRoot || sel ? c.accentSoft : c.card,
              borderRadius: BorderRadius.circular(S.radius),
              border: Border.all(
                color: isRoot || sel ? c.accent : c.line,
                width: isRoot || sel ? 1.5 : 1,
              ),
            ),
            child: Center(
              child: Text(
                n.title.trim().isEmpty ? tr('（空）') : n.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: S.textSm,
                  fontWeight: isRoot ? FontWeight.bold : FontWeight.normal,
                  color: c.ink,
                  height: 1.25,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 底部工具列：选中节点后给出 加子/加同级/编辑/删除；批量态给 全选/删除/退出。
  Widget _toolbar(C c) {
    final s = StartStore.I;
    if (_selecting) {
      final allIds = <int>[];
      _descIds(widget.rootId, allIds);
      return Container(
        decoration: BoxDecoration(
          color: c.card,
          border: Border(top: BorderSide(color: c.line)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.xs),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconBtn(Icons.select_all, tip: tr('全选'), onTap: () {
                  setState(() {
                    _selected.length == allIds.length
                        ? _selected.clear()
                        : _selected.addAll(allIds);
                  });
                }),
                Text(tr('已选 {0}', [_selected.length]), style: TextStyle(color: c.inkSoft, fontSize: S.textSm)),
                IconBtn(Icons.delete_outline, tip: tr('删除所选'), color: c.accent,
                    onTap: _selected.isEmpty ? null : () {
                      final snap = s.exportJson();
                      for (final id in _selected) {
                        if (id != widget.rootId) s.delete(id, cascade: true);
                      }
                      setState(() {
                        _selected.clear();
                        _selecting = false;
                        _sel = 0;
                      });
                      UndoHost.show(context, tr('已删除所选'), () async => s.restoreJson(snap));
                    }),
                IconBtn(Icons.close, tip: tr('退出'), onTap: () {
                  setState(() {
                    _selecting = false;
                    _selected.clear();
                  });
                }),
              ],
            ),
          ),
        ),
      );
    }
    final selItem = _sel == 0 ? null : s.byId(_sel);
    final isRootSel = _sel == widget.rootId;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.xs),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconBtn(Icons.subdirectory_arrow_right,
                  tip: tr(tr('加子节点')),
                  color: c.accent,
                  onTap: () => _addNode(_sel == 0 ? widget.rootId : _sel)),
              IconBtn(Icons.download_outlined,
                  tip: tr('导入日程 / 随手做 / 步骤'),
                  onTap: () => _importItems(_sel == 0 ? widget.rootId : _sel)),
              if (_sel != 0 && !isRootSel)
                IconBtn(Icons.playlist_add, tip: tr('加同级节点'),
                    onTap: () {
                      final p = selItem?.parentId ?? widget.rootId;
                      _addNode(p);
                    }),
              if (_sel != 0 && selItem != null)
                IconBtn(Icons.edit_outlined, tip: tr('编辑'), onTap: () => _editNode(selItem)),
              if (_sel != 0 && !isRootSel)
                IconBtn(Icons.delete_outline, tip: tr('删除（含子枝）'),
                    onTap: () async {
                      final snap = s.exportJson();
                      s.delete(_sel, cascade: true);
                      setState(() => _sel = 0);
                      if (!mounted) return;
                      UndoHost.show(context, tr(tr('剪掉一枝')), () async => s.restoreJson(snap));
                    }),
              IconBtn(Icons.checklist_outlined, tip: tr('批量删除'),
                  onTap: () => setState(() {
                        _selecting = true;
                        _selected.clear();
                        if (_sel != 0 && _sel != widget.rootId) _selected.add(_sel);
                      })),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addNode(int parentId) async {
    final s = StartStore.I;
    final n = Item(kind: Item.kindInbox, title: '', parentId: parentId, rank: -1);
    await s.put(n);
    setState(() => _sel = n.id);
    if (!mounted) return;
    await _editNode(s.byId(n.id)!, removeIfEmpty: true);
  }

  /// 导入：把日程 / 随手做 / 小步骤复制进导图（选中节点的子枝），多选批量入。
  Future<void> _importItems(int parentId) async {
    final s = StartStore.I;
    final pool = s.items
        .where((it) => it.parentId != 0 ||
            (it.kind == Item.kindTask && it.title.trim().isNotEmpty))
        .where((it) => it.id != widget.rootId)
        .toList()
      ..sort((a, b) => b.id.compareTo(a.id));
    final picked = <int>{};
    await showStartSheet(context, (ctx) {
      final c = ThemeTokens.of(ctx);
      return StatefulBuilder(builder: (ctx, setSt) {
        String kindName(Item it) {
          if (it.parentId != 0) return tr('步骤');
          return it.dueTime > 0 ? tr('日程') : tr('随手做');
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(S.md, S.md, S.md, S.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(tr('导入条目'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: S.textLg,
                            fontWeight: FontWeight.bold,
                            color: c.ink)),
                  ),
                  const SizedBox(width: S.sm),
                  Flexible(
                    child: Text(tr('选好挂到当前枝上'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: S.textSm, color: c.inkSoft)),
                  ),
                ],
              ),
              const SizedBox(height: S.sm),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 380),
                  child: pool.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: S.xl),
                          child: Center(
                              child: Text(tr('还没有日程和随手做'),
                                  style: TextStyle(
                                      fontSize: S.textSm, color: c.inkSoft))),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: pool.length,
                          itemBuilder: (_, i) {
                            final it = pool[i];
                            final on = picked.contains(it.id);
                            return Pressable(
                              onTap: () => setSt(() {
                                on ? picked.remove(it.id) : picked.add(it.id);
                              }),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: S.xxs),
                                child: Row(
                                  children: [
                                    Icon(
                                      on
                                          ? Icons.check_circle
                                          : Icons.circle_outlined,
                                      size: 18,
                                      color:
                                          on ? c.accent : c.inkSoft,
                                    ),
                                    const SizedBox(width: S.sm),
                                    Expanded(
                                      child: Text(
                                        it.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: S.textMd, color: c.ink),
                                      ),
                                    ),
                                    Text(kindName(it),
                                        style: TextStyle(
                                            fontSize: S.textSm - 1,
                                            color: c.inkSoft)),
                                    if (it.parentId != 0) ...[
                                      const SizedBox(width: S.xs),
                                      Flexible(
                                        child: Text(
                                          tr('属于 {0}', [s.byId(it.parentId)?.title ?? tr('任务')]),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: S.textSm - 1,
                                              color: c.inkSoft),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(height: S.md),
              Pressable(
                onTap: picked.isEmpty
                    ? null
                    : () async {
                        final s2 = StartStore.I;
                        for (final id in picked) {
                          final it = s2.byId(id);
                          if (it == null) continue;
                          final name = it.parentId != 0
                              ? it.title
                              : it.title.trim();
                          if (name.isEmpty) continue;
                          await s2.put(Item(
                              kind: Item.kindInbox,
                              title: name,
                              parentId: parentId,
                              rank: -1));
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: picked.isEmpty ? c.line : c.accent,
                    borderRadius: BorderRadius.circular(S.radius),
                  ),
                  child: Text(
                    picked.isEmpty ? tr('点条目选中') : tr('导入（{0}）', [picked.length]),
                    style: TextStyle(
                        fontSize: S.textMd,
                        fontWeight: FontWeight.bold,
                        color: picked.isEmpty ? c.inkSoft : Colors.white),
                  ),
                ),
              ),
            ],
          ),
        );
      });
    });
    if (mounted) setState(() {});
  }

  /// 长按节点：快捷编辑菜单（编辑文字 / 加子节点 / 剪掉这枝）。
  Future<void> _nodeMenu(Item n) async {
    final s = StartStore.I;
    final c = ThemeTokens.of(context);
    final isRoot = n.id == widget.rootId;
    await showStartSheet(context, (ctx) {
      Widget row(IconData icon, String text, VoidCallback onTap,
              {Color? color}) =>
          Pressable(
            onTap: () {
              Navigator.pop(ctx);
              onTap();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: S.sm),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: color ?? c.ink),
                  const SizedBox(width: S.sm),
                  Flexible(
                    child: Text(text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: S.textMd,
                            fontWeight: FontWeight.bold,
                            color: color ?? c.ink)),
                  ),
                ],
              ),
            ),
          );
      return Padding(
        padding: const EdgeInsets.fromLTRB(S.md, S.md, S.md, S.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(n.title.trim().isEmpty ? tr('（空）') : n.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: S.textMd,
                    fontWeight: FontWeight.bold,
                    color: c.ink)),
            const SizedBox(height: S.xs),
            row(Icons.edit_outlined, tr('编辑文字'), () async => _editNode(n)),
            row(Icons.subdirectory_arrow_right, tr('加子节点'),
                () => _addNode(n.id), color: c.accent),
            if (!isRoot)
              row(Icons.delete_outline, tr('剪掉这枝'), () async {
                final snap = s.exportJson();
                s.delete(n.id, cascade: true);
                setState(() => _sel = 0);
                if (!mounted) return;
                UndoHost.show(
                    context, tr('剪掉一枝'), () async => s.restoreJson(snap));
              }, color: c.accent),
          ],
        ),
      );
    });
    if (mounted) setState(() {});
  }

  /// 编辑节点文本；新建时留空则删除该节点。
  Future<void> _editNode(Item n, {bool removeIfEmpty = false}) async {
    final ctl = TextEditingController(text: n.title);
    await showStartSheet(context, (ctx) {
      final c = ThemeTokens.of(ctx);
      final pad = MediaQuery.of(ctx).viewInsets.bottom;
      return Padding(
        padding: EdgeInsets.fromLTRB(S.md, S.md, S.md, pad + S.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: ctl,
              autofocus: true,
              maxLines: null,
              style: TextStyle(fontSize: S.textLg, color: c.ink, height: 1.4),
              decoration: InputDecoration(
                hintText: tr('写点什么'),
                hintStyle: TextStyle(color: c.inkSoft),
                border: InputBorder.none,
              ),
            ),
            const SizedBox(height: S.md),
            Pressable(
              onTap: () async {
                final t = ctl.text.trim();
                if (t.isEmpty) {
                  if (removeIfEmpty) StartStore.I.delete(n.id, cascade: true);
                } else if (t != n.title) {
                  n.title = t;
                  await StartStore.I.put(n);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Container(
                height: 48,
                alignment: Alignment.center,
                decoration:
                    BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(S.radius)),
                child: const Icon(Icons.check, size: 22, color: Colors.white),
              ),
            ),
          ],
        ),
      );
    });
    if (mounted) setState(() {});
  }

  /// 新建导图：从零起一个空根节点，进编辑态直接写标题。
  Future<void> _newMap() async {
    final root = Item()..kind = Item.kindInbox..title = '';
    await StartStore.I.put(root);
    if (!mounted) return;
    // 替换当前导图页为新根节点（旧页出栈）。
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => MindMapScreen(rootId: root.id)),
    );
  }
}

/// 连线画笔：父到子的平滑曲线。
class _EdgePainter extends CustomPainter {
  final List<List<Offset>> edges;
  final Color color;
  final Color accent;
  _EdgePainter({required this.edges, required this.color, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color;
    for (final e in edges) {
      final a = e[0], b = e[1];
      final dx = (b.dx - a.dx).abs() / 2;
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..cubicTo(a.dx + dx, a.dy, b.dx - dx, b.dy, b.dx, b.dy);
      canvas.drawPath(path, p);
      // 端点小圆点
      canvas.drawCircle(a, 2.5, Paint()..color = accent);
    }
  }

  @override
  bool shouldRepaint(_EdgePainter old) =>
      old.edges != edges || old.color != color || old.accent != accent;
}
