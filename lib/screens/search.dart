import 'package:flutter/material.dart';

import '../data/item.dart';
import '../data/store.dart';
import '../theme/tokens.dart';
import '../widgets/editor.dart';
import '../widgets/ui.dart';

/// 搜索：任务 + 念头，标题与备注包含即命中。
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctl = TextEditingController();
  List<Item> _hits = [];

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
            .toList();
      }
    });
  }

  @override
  void dispose() {
    StartStore.I.removeListener(_search);
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(S.md, S.sm, S.md, S.xs),
            child: StartCard(
              padding: const EdgeInsets.symmetric(horizontal: S.md),
              child: Row(
                children: [
                  Icon(Icons.search_outlined, color: c.inkSoft, size: 20),
                  const SizedBox(width: S.xs),
                  Expanded(
                    child: TextField(
                      controller: _ctl,
                      autofocus: false,
                      style: TextStyle(fontSize: S.textMd, color: c.ink),
                      decoration: InputDecoration(
                        hintText: '找事或念头',
                        hintStyle: TextStyle(color: c.inkSoft),
                        border: InputBorder.none,
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
          Expanded(
            child: _hits.isEmpty
                ? EmptyView(
                    icon: Icons.search_outlined,
                    text: _ctl.text.isEmpty ? '输入几个字，找找看' : '没找到',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(S.md, S.xs, S.md, S.md),
                    itemCount: _hits.length,
                    itemBuilder: (_, i) {
                      final it = _hits[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: S.xs),
                        child: Pressable(
                          onTap: () => showItemEditor(context, it),
                          child: StartCard(
                            padding:
                                const EdgeInsets.symmetric(horizontal: S.md, vertical: S.sm),
                            child: Row(
                              children: [
                                Icon(
                                  it.isIdea
                                      ? Icons.lightbulb_outline
                                      : it.done
                                          ? Icons.check_circle
                                          : Icons.radio_button_unchecked,
                                  size: 18,
                                  color: it.isIdea ? c.inkSoft : (it.done ? c.done : c.accent),
                                ),
                                const SizedBox(width: S.sm),
                                Expanded(
                                  child: Text(
                                    it.title.isEmpty ? it.note : it.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: S.textMd, color: c.ink),
                                  ),
                                ),
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
    );
  }
}
