import 'package:flutter/material.dart';

import '../data/item.dart';
import '../data/store.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

/// 数据管理：浏览、搜索、删除全部条目（含小步骤）。
/// 从设置页进入，误删可撤销；所有数据仍只存在本机。
class DataManageScreen extends StatefulWidget {
  const DataManageScreen({super.key});

  @override
  State<DataManageScreen> createState() => _DataManageScreenState();
}

class _DataManageScreenState extends State<DataManageScreen> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  String _kindName(Item it) {
    if (it.parentId != 0) return '步骤';
    return switch (it.kind) {
      Item.kindIdea => '念头',
      Item.kindInbox => '暂存',
      _ => it.dueTime > 0 ? '日程' : '任务',
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return ListenableBuilder(
      listenable: StartStore.I,
      builder: (context, _) {
        final q = _ctl.text.trim();
        var items = StartStore.I.items.toList()
          ..sort((a, b) => b.id.compareTo(a.id));
        if (q.isNotEmpty) {
          items = items.where((e) => e.title.contains(q)).toList();
        }
        final total = StartStore.I.items.length;
        return Scaffold(
          backgroundColor: c.paper,
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(S.sm),
                  child: Row(
                    children: [
                      IconBtn(Icons.arrow_back,
                          onTap: () => Navigator.pop(context)),
                      const SizedBox(width: S.xs),
                      Text('数据管理',
                          style: TextStyle(
                              fontSize: S.textXl,
                              fontWeight: FontWeight.bold,
                              color: c.ink)),
                      const Spacer(),
                      Text('$total 条',
                          style: TextStyle(
                              fontSize: S.textSm,
                              color: c.inkSoft,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ])),
                    ],
                  ),
                ),
                // 搜索框：按标题过滤，输入即刷。
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(S.md, 0, S.md, S.sm),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: S.md, vertical: S.xxs),
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(S.radius),
                      border: Border.all(color: c.line),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search_outlined,
                            size: 18, color: c.inkSoft),
                        const SizedBox(width: S.xs),
                        Expanded(
                          child: TextField(
                            controller: _ctl,
                            onChanged: (_) => setState(() {}),
                            style:
                                TextStyle(fontSize: S.textSm, color: c.ink),
                            decoration: const InputDecoration(
                              hintText: '搜标题',
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                        if (_ctl.text.isNotEmpty)
                          IconBtn(Icons.close, tip: '清空', onTap: () {
                            _ctl.clear();
                            setState(() {});
                          }),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Text(q.isEmpty ? '还没有数据' : '没有匹配的条目',
                              style: TextStyle(
                                  fontSize: S.textSm, color: c.inkSoft)),
                        )
                      : ListView.builder(
                          padding:
                              const EdgeInsets.fromLTRB(S.md, 0, S.md, S.lg),
                          itemCount: items.length,
                          itemBuilder: (_, i) {
                            final it = items[i];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: S.xxs),
                              child: Pressable(
                                onTap: () {
                                  final snap = StartStore.I.exportJson();
                                  StartStore.I.delete(it.id, cascade: true);
                                  UndoHost.show(
                                      context, '已删除「${it.title}」',
                                      () async =>
                                          StartStore.I.restoreJson(snap));
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: S.sm, vertical: S.xs),
                                  decoration: BoxDecoration(
                                    color: c.card,
                                    borderRadius:
                                        BorderRadius.circular(S.sm),
                                    border: Border.all(color: c.line),
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 44,
                                        child: Text('#${it.id}',
                                            style: TextStyle(
                                                fontSize: S.textSm,
                                                color: c.inkSoft,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures()
                                                ])),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: c.cardAlt,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(_kindName(it),
                                            style: TextStyle(
                                                fontSize: S.textSm - 1,
                                                color: c.inkSoft)),
                                      ),
                                      const SizedBox(width: S.xs),
                                      Expanded(
                                        child: Text(
                                          it.title.isEmpty
                                              ? '(无标题)'
                                              : it.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: S.textSm,
                                              color: it.done
                                                  ? c.done
                                                  : c.ink,
                                              decoration: it.done
                                                  ? TextDecoration
                                                      .lineThrough
                                                  : null),
                                        ),
                                      ),
                                      if (it.parentId != 0)
                                        Text('↳${it.parentId}',
                                            style: TextStyle(
                                                fontSize: S.textSm - 1,
                                                color: c.inkSoft)),
                                      Icon(Icons.close,
                                          size: 16, color: c.inkSoft),
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
      },
    );
  }
}
