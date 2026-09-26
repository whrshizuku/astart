import 'package:flutter/material.dart';

import '../data/item.dart';
import '../data/store.dart';
import '../theme/tokens.dart';
import '../widgets/editor.dart';
import '../widgets/ui.dart';

/// 搜索 = 全局任务管理器：找全部条目（日程、随手做、小步骤），标题与备注包含即命中。
/// 顶部分类胶囊筛选（全部 / 日程 / 随手做 / 步骤）；右上角进批量态，全选、批量删除（可撤销）；
/// 点一条直达编辑（小步骤进所属任务的步骤页），非批量态行尾叉号单删。
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctl = TextEditingController();
  List<Item> _hits = [];
  int _filter = 0; // 0 全部 1 日程 2 随手做 3 步骤
  bool _selecting = false;
  final Set<int> _selected = {};

  static const _filterNames = ['全部', '日程', '随手做', '步骤'];

  @override
  void initState() {
    super.initState();
    _ctl.addListener(_search);
    StartStore.I.addListener(_search);
  }

  void _search() {
    final q = _ctl.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _hits = [];
      } else {
        _hits = StartStore.I.items
            .where((it) =>
                it.title.toLowerCase().contains(q) ||
                it.note.toLowerCase().contains(q) ||
                it.alarmLabel.toLowerCase().contains(q))
            .toList()
          ..sort((a, b) => b.id.compareTo(a.id));
      }
      if (_selecting && _hits.isEmpty) _exitSelect();
    });
  }

  void _exitSelect() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  /// 分类归属：0 全部 / 1 日程（有时间的任务）/ 2 随手做（无时间，含旧念头暂存）/ 3 小步骤。
  int _groupOf(Item it) {
    if (it.parentId != 0) return 3;
    if (it.kind == Item.kindTask && it.dueTime > 0) return 1;
    return 2;
  }

  List<Item> get _shown => _filter == 0
      ? _hits
      : _hits.where((it) => _groupOf(it) == _filter).toList();

  @override
  void dispose() {
    StartStore.I.removeListener(_search);
    _ctl.dispose();
    super.dispose();
  }

  String _kindName(Item it) {
    if (it.parentId != 0) return '步骤';
    return switch (it.kind) {
      Item.kindIdea => '随手做',
      Item.kindInbox => '随手做',
      _ => it.dueTime > 0 ? '日程' : '随手做',
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final shown = _shown;
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.xs),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: S.md, vertical: S.xxs),
                          decoration: BoxDecoration(
                            color: c.cardAlt,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.search_outlined,
                                  color: c.inkSoft, size: 20),
                              const SizedBox(width: S.xs),
                              Expanded(
                                child: TextField(
                                  controller: _ctl,
                                  autofocus: true,
                                  style: TextStyle(
                                      fontSize: S.textMd, color: c.ink),
                                  decoration: InputDecoration(
                                    hintText: '找事或念头',
                                    hintStyle: TextStyle(color: c.inkSoft),
                                    border: InputBorder.none,
                                    isDense: true,
                                  ),
                                ),
                              ),
                              if (_ctl.text.isNotEmpty)
                                IconBtn(Icons.close, tip: '清空', onTap: () {
                                  _ctl.clear();
                                }),
                            ],
                          ),
                        ),
                      ),
                      // 批量入口：有结果时显示；批量态变退出。
                      if (_hits.isNotEmpty)
                        _selecting
                            ? IconBtn(Icons.close,
                                tip: '退出选择', onTap: _exitSelect)
                            : IconBtn(Icons.playlist_add_check,
                                tip: '批量整理', onTap: () {
                                setState(() => _selecting = true);
                              }),
                    ],
                  ),
                ),
                // 分类胶囊筛选：批量态收起，专注选择。
                if (!_selecting && _hits.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(S.lg, 0, S.lg, S.xxs),
                    child: Wrap(
                      spacing: S.xs,
                      children: [
                        for (var i = 0; i < _filterNames.length; i++)
                          Pressable(
                            onTap: () => setState(() => _filter = i),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: S.sm, vertical: 3),
                              decoration: BoxDecoration(
                                color:
                                    _filter == i ? c.accent : Colors.transparent,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                    color:
                                        _filter == i ? c.accent : c.inkSoft),
                              ),
                              child: Text(_filterNames[i],
                                  style: TextStyle(
                                      fontSize: S.textSm - 1,
                                      color: _filter == i
                                          ? Colors.white
                                          : c.inkSoft)),
                            ),
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: shown.isEmpty
                      ? EmptyView(
                          icon: Icons.search_outlined,
                          text: _ctl.text.isEmpty
                              ? '输入几个字，找找看'
                              : _filter == 0
                                  ? '没找到'
                                  : '这个分类里没找到',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(
                              S.lg, S.xs, S.lg, S.xl + S.lg),
                          itemCount: shown.length,
                          itemBuilder: (_, i) {
                            final it = shown[i];
                            final sel = _selected.contains(it.id);
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: S.xs),
                              child: DraggableLine(
                                id: it.id,
                                title: it.title.isEmpty ? it.note : it.title,
                                // 选择态：已选条目可整组拖删，未选条目禁拖。
                                enabled: !_selecting || sel,
                                dragIds: _selecting && sel && _selected.length > 1
                                    ? _selected.toList()
                                    : null,
                                selected: sel,
                                onDragStarted: () => setState(() {
                                  _selecting = false;
                                  _selected.clear();
                                }),
                                child: Row(
                                children: [
                                  Expanded(
                                    child: Pressable(
                                      onTap: () {
                                        if (_selecting) {
                                          setState(() {
                                            sel
                                                ? _selected.remove(it.id)
                                                : _selected.add(it.id);
                                          });
                                          return;
                                        }
                                        if (it.parentId != 0) {
                                          Navigator.of(context,
                                                  rootNavigator: true)
                                              .pushNamed('/steps',
                                                  arguments: it.parentId);
                                        } else {
                                          showItemEditor(context, it);
                                        }
                                      },
                                      child: Row(
                                        children: [
                                          Icon(
                                            _selecting
                                                ? (sel
                                                    ? Icons.check_circle
                                                    : Icons.circle_outlined)
                                                : it.kind == Item.kindIdea
                                                    ? Icons.lightbulb_outline
                                                    : it.done
                                                        ? Icons.check_circle
                                                        : Icons
                                                            .radio_button_unchecked,
                                            size: 18,
                                            color: _selecting
                                                ? (sel
                                                    ? c.accent
                                                    : c.inkSoft)
                                                : it.kind == Item.kindIdea
                                                    ? c.inkSoft
                                                    : (it.done
                                                        ? c.done
                                                        : c.accent),
                                          ),
                                          const SizedBox(width: S.sm),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  it.title.isEmpty
                                                      ? it.note
                                                      : it.title,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                      fontSize: S.textMd,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: it.done
                                                          ? c.done
                                                          : c.ink,
                                                      decoration: it.done
                                                          ? TextDecoration
                                                              .lineThrough
                                                          : null),
                                                ),
                                                const SizedBox(width: 0),
                                                if (it.parentId != 0)
                                                  Text(
                                                    '属于 ${StartStore.I.byId(it.parentId)?.title ?? '任务'}',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                        fontSize: S.textSm - 1,
                                                        color: c.inkSoft),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: S.sm),
                                          Text(_kindName(it),
                                              style: TextStyle(
                                                  fontSize: S.textSm - 1,
                                                  color: c.inkSoft)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
            // 批量态吸底操作胶囊：全选 + 已选计数 + 删除。
            if (_selecting && _hits.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: S.lg,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: S.md, vertical: S.xs),
                    decoration: BoxDecoration(
                      color: c.ink,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 12,
                            offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconBtn(
                          _selected.length == shown.length && shown.isNotEmpty
                              ? Icons.check_circle
                              : Icons.select_all,
                          tip: '全选 / 取消',
                          color: Colors.white,
                          onTap: () => setState(() {
                            _selected.length == shown.length
                                ? _selected.clear()
                                : _selected.addAll(shown.map((e) => e.id));
                          }),
                        ),
                        Text('已选 ${_selected.length}',
                            style: const TextStyle(
                                fontSize: S.textSm, color: Colors.white70)),
                        // 删除统一走拖拽：长按任一已选条目，整组拖到底部桶。
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
