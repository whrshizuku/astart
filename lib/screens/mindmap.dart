import 'package:flutter/material.dart';

import '../data/item.dart';
import '../data/store.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

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
        body: const SafeArea(child: EmptyView(icon: Icons.account_tree_outlined, text: '这条已不在了')),
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
            PageHead('导图',
                count: total,
                onBack: () => Navigator.pop(context),
                actions: [
                  if (_delta.isNotEmpty)
                    IconBtn(Icons.restart_alt, tip: '重排', onTap: () => setState(() => _delta.clear())),
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
    final sel = _sel == n.id;
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
        child: Pressable(
          onTap: () => setState(() => _sel = n.id),
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
                n.title.trim().isEmpty ? '（空）' : n.title,
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

  /// 底部工具列：选中节点后给出 加子/加同级/编辑/删除。
  Widget _toolbar(C c) {
    final s = StartStore.I;
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
                  tip: '加子节点',
                  color: c.accent,
                  onTap: () => _addNode(_sel == 0 ? widget.rootId : _sel)),
              if (_sel != 0 && !isRootSel)
                IconBtn(Icons.playlist_add, tip: '加同级节点',
                    onTap: () {
                      final p = selItem?.parentId ?? widget.rootId;
                      _addNode(p);
                    }),
              if (_sel != 0 && selItem != null)
                IconBtn(Icons.edit_outlined, tip: '编辑', onTap: () => _editNode(selItem)),
              if (_sel != 0 && !isRootSel)
                IconBtn(Icons.delete_outline, tip: '删除（含子枝）',
                    onTap: () async {
                      final snap = s.exportJson();
                      s.delete(_sel, cascade: true);
                      setState(() => _sel = 0);
                      if (!mounted) return;
                      UndoHost.show(context, '剪掉一枝', () async => s.restoreJson(snap));
                    }),
              if (_sel != 0 && isRootSel)
                IconBtn(Icons.edit_outlined, tip: '编辑根', onTap: () => _editNode(s.byId(widget.rootId)!)),
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
                hintText: '写点什么',
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
