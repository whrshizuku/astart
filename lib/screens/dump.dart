import 'package:flutter/material.dart';

import '../channels/native.dart';
import '../data/item.dart';
import '../data/store.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';
import 'segment_screen.dart';

/// 动手吧 = 纯速记页，只负责「丢」。
/// 底部输入条一股脑写下来，点倒进来按行和句末标点（。！？；…）拆成多条
/// kindInbox 暂存（与捋一捋 / 念头 / 小步骤共用 splitIntoLines），
/// 存完直接进捋一捋分拣。本页不展示也不管理暂存列表——那是捋一捋的职责。
class DumpScreen extends StatefulWidget {
  final String initial;
  const DumpScreen({super.key, this.initial = ''});

  @override
  State<DumpScreen> createState() => _DumpScreenState();
}

class _DumpScreenState extends State<DumpScreen> {
  final _ctl = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // 撤销条让开底部输入条。
    UndoHost.extraBottom.value = 72;
    _ctl.text = widget.initial;
    _loadShare();
  }

  Future<void> _loadShare() async {
    if (widget.initial.isEmpty) {
      final t = await Native.initialShare();
      if (t != null && t.trim().isNotEmpty && mounted && _ctl.text.isEmpty) {
        _ctl.text = t;
      }
    }
  }

  @override
  void dispose() {
    UndoHost.extraBottom.value = 0;
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// 倒进来：拆成多条暂存，存完切到捋一捋整理（先存再捋）。
  Future<void> _dump() async {
    final chunks = splitIntoLines(_ctl.text);
    if (chunks.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < chunks.length; i++) {
      await StartStore.I.put(
        Item(kind: Item.kindInbox, title: chunks[i], rank: -1, created: now + i),
        touchRank: true,
      );
    }
    if (!mounted) return;
    // 存完跳捋一捋整理。pushReplacement 替换本页，捋完返回回首页。
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => const SegmentScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHead('动手吧', onBack: () => Navigator.pop(context)),
            const Expanded(child: _DumpGuide()),
            QuickInputBar(
              controller: _ctl,
              focus: _focus,
              hint: '想到什么一股脑写下来',
              onCommit: _dump,
              onBang: _dump,
              showBang: false,
              submitIcon: Icons.south,
              maxLines: 6,
              autofocus: widget.initial.isEmpty,
            ),
          ],
        ),
      ),
    );
  }
}

/// 开始页中部引导：丢 → 捋 → 做三步。
class _DumpGuide extends StatelessWidget {
  const _DumpGuide();

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    const steps = [
      (Icons.edit_note, '丢', '想到什么全写下来，不用想分类'),
      (Icons.south, '倒进来', '按行和句末标点自动拆成几条'),
      (Icons.alt_route, '捋一捋', '逐条分到日程或随手做'),
    ];
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              if (i > 0) ...[
                Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: c.inkSoft),
                const SizedBox(height: S.xxs),
              ],
              StartCard(
                padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.sm),
                child: Row(
                  children: [
                    Icon(steps[i].$1, size: 22, color: c.accent),
                    const SizedBox(width: S.sm),
                    Text(steps[i].$2,
                        style: TextStyle(
                            fontSize: S.textMd, fontWeight: FontWeight.bold, color: c.ink)),
                    const SizedBox(width: S.sm),
                    Expanded(
                      child: Text(steps[i].$3,
                          style: TextStyle(fontSize: S.textSm, color: c.inkSoft, height: 1.4)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
