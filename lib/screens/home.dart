import 'dart:async';

import 'package:flutter/material.dart';

import '../channels/native.dart';
import '../data/item.dart';
import '../data/store.dart';
import '../main.dart';
import '../theme/tokens.dart';
import '../widgets/editor.dart';
import '../widgets/ui.dart';
import 'settings.dart';

/// 首页 = 今日（复刻老版 TodayScreen 的极简布局）。
/// 顶栏：Start 字标 + 搜索 + 设置。
/// 今日焦点 hero 占首屏最上方：无焦点=大标语+选一件胶囊+不选直接专注；
/// 有焦点=大字标题+主胶囊「只做它」+次操作图标。日程卡长按可拖上来设焦点。
/// 其下大时钟 + 日期 + 一句鼓励。今天 = 已排期（含过期未完成，不责备）+ 手机日历，
/// 纯文字列表；随手做 = 无时间任务，可拖动排序，长按进选择态。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _selecting = false;
  final Set<int> _selected = {};
  Timer? _clock;
  String _hhmm = '';
  String _dateLabel = '';
  int _nowMs = 0;
  List<Map<String, Object?>> _events = [];
  bool _overSchedule = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tickClock();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) => _tickClock());
    _loadCalendar();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadCalendar();
  }

  Future<void> _loadCalendar() async {
    final ev = await Native.calendarToday();
    if (mounted) setState(() => _events = ev);
  }

  void _tickClock() {
    if (!mounted) return;
    final now = DateTime.now();
    setState(() {
      _hhmm = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      _dateLabel = _fullDate(now);
      _nowMs = now.millisecondsSinceEpoch;
    });
  }

  static String _fullDate(DateTime n) {
    const wk = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    return '${n.month}月${n.day}日 ${wk[n.weekday - 1]}';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    super.dispose();
  }

  /// 随手做右上角加号：多行速记弹层，回车换行多写几件，
  /// 保存时按行与句末标点自动拆成多条，直接成为随手做任务。
  void _quickAdd() {
    final ctx = StartApp.navigatorKey.currentContext ?? context;
    showQuickAdd(ctx);
  }

  /// 「选一件事」面板：今日未完成任务里挑一件设为焦点（ADHD：一次只做一件，降低决策负荷）。
  Future<void> _pickFocus() async {
    final s = StartStore.I;
    final list = s.openTasks().where((e) => !e.done).toList();
    if (list.isEmpty) {
      _quickAdd();
      return;
    }
    await showStartSheet(context, (ctx) {
      final c = ThemeTokens.of(ctx);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(S.md, S.md, S.md, S.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('今天只盯一件事',
                  style: TextStyle(
                      fontSize: S.textLg, fontWeight: FontWeight.bold, color: c.ink)),
              const SizedBox(height: S.xxs),
              Text('选一个，其他的先放一放',
                  style: TextStyle(fontSize: S.textSm, color: c.inkSoft)),
              const SizedBox(height: S.sm),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final it = list[i];
                    final timed = it.dueTime > 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: S.xs),
                      child: Pressable(
                        onTap: () async {
                          await s.setFocus(it.id);
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        child: StartCard(
                          color: s.todayFocus()?.id == it.id ? c.accentSoft : null,
                          padding: const EdgeInsets.symmetric(
                              horizontal: S.md, vertical: S.sm),
                          child: Row(
                            children: [
                              Icon(
                                timed ? Icons.schedule_outlined : Icons.checklist_outlined,
                                size: 16,
                                color: c.inkSoft,
                              ),
                              const SizedBox(width: S.sm),
                              Expanded(
                                child: Text(
                                  it.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: S.textMd,
                                      fontWeight: FontWeight.bold,
                                      color: c.ink),
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
        ),
      );
    });
  }

  /// 今天：今天到期 + 过期未完成（未来的日子还没到，先不来添乱）。
  List<Item> _todaySchedule() {
    final now = DateTime.now();
    final dayEnd =
        DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final fid = StartStore.I.todayFocus()?.id;
    final list = StartStore.I
        .openTasks()
        .where((it) => it.dueTime > 0 && it.dueTime < dayEnd.millisecondsSinceEpoch && it.id != fid)
        .toList()
      ..sort((a, b) => a.dueTime.compareTo(b.dueTime));
    return list;
  }

  /// 合并今日任务与手机日历事件，按 begin 升序。被任务 eventId 消费的事件跳过。
  List<Map<String, Object?>> _mergeToday(List<Item> schedule) {
    final consumed = schedule.map((e) => e.eventId).where((e) => e > 0).toSet();
    final entries = <Map<String, Object?>>[];
    for (final it in schedule) {
      entries.add({'kind': 'task', 'item': it, 'time': it.dueTime});
    }
    for (final ev in _events) {
      final id = (ev['id'] as num?)?.toInt() ?? 0;
      if (consumed.contains(id)) continue;
      entries.add({'kind': 'event', 'event': ev, 'time': ev['begin'] as int? ?? 0});
    }
    entries.sort((a, b) => (a['time'] as int).compareTo(b['time'] as int));
    return entries;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: StartStore.I,
        builder: (context, _) => _build(context),
      );

  Widget _build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final s = StartStore.I;
    final focus = s.todayFocus();
    final fid = focus?.id;
    // 焦点任务不在下方列表重复出现：一次只做一件事，避免两套按钮。
    final today = _todaySchedule();
    final anytime = s.anytimeTasks().where((it) => it.id != fid).toList();
    final entries = _mergeToday(today);
    final remaining = today.length + anytime.length;
    final encourage =
        remaining == 0 ? '今天的事都做完了，了不起' : '还有 $remaining 件，一件件来';

    return SafeArea(
      child: Column(
        children: [
          if (_selecting) _selectBar(c, [...today, ...anytime]) else const _TopBar(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.md, 0, S.md, S.xl + 16),
              children: [
                // 今日焦点在最上方：看完一眼就知道今天只盯哪一件。
                DragTarget<int>(
                  onWillAcceptWithDetails: (d) => d.data != fid,
                  onAcceptWithDetails: (d) async {
                    await s.setFocus(d.data);
                    if (mounted) setState(() {});
                  },
                  builder: (ctx, cand, _) {
                    final hovering = cand.isNotEmpty;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      decoration: BoxDecoration(
                        color: hovering ? c.accentSoft : Colors.transparent,
                        borderRadius: BorderRadius.circular(S.radius),
                      ),
                      child: _FocusHero(
                        focus: focus,
                        hovering: hovering,
                        onPick: _pickFocus,
                      ),
                    );
                  },
                ),
                _ClockHead(hhmm: _hhmm, date: _dateLabel, encourage: encourage),
                // 日程：今天到期 + 过期未完成 + 手机日历，纯文字行；可把随手做拖进来转日程。
                DragTarget<int>(
                  onWillAcceptWithDetails: (d) => !_selecting,
                  onAcceptWithDetails: (d) => _dragToSchedule(d.data),
                  builder: (ctx, cand, _) {
                    final hov = cand.isNotEmpty;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      decoration: BoxDecoration(
                        color: hov ? c.accentSoft : Colors.transparent,
                        borderRadius: BorderRadius.circular(S.radius),
                      ),
                      child: Column(
                        children: [
                          _SectionLabel('日程', onAdd: _newSchedule),
                          if (entries.isNotEmpty)
                            for (var i = 0; i < entries.length; i++) ...[
                              if (i > 0) const SizedBox(height: S.xxs),
                              _todayEntry(entries[i]),
                            ]
                          else
                            const _ListEmpty(msg: '还没有日程'),
                        ],
                      ),
                    );
                  },
                ),
                // 随手做：没定时间的都待在这，可拖动排序；长按整行拖进上面「日程」区转日程。
                GestureDetector(
                  onLongPress: () => setState(() => _selecting = true),
                  child: _SectionLabel('随手做', onAdd: _quickAdd),
                ),
                if (anytime.isNotEmpty)
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: true,
                    proxyDecorator: (child, i, a) => ScaleTransition(scale: a, child: child),
                    itemCount: anytime.length,
                    onReorder: (o, n) async {
                      final ids = anytime.map((e) => e.id).toList();
                      if (n > o) n--;
                      ids.insert(n, ids.removeAt(o));
                      await s.reorder(ids);
                    },
                    itemBuilder: (_, i) {
                      final it = anytime[i];
                      return LongPressDraggable<int>(
                        key: ValueKey(it.id),
                        data: it.id,
                        delay: const Duration(milliseconds: 120),
                        axis: Axis.vertical,
                        feedback: Material(
                          color: Colors.transparent,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                                maxWidth: MediaQuery.sizeOf(context).width - 96),
                            child: StartCard(
                              color: ThemeTokens.of(context).accentSoft,
                              child: Text(
                                it.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: S.textMd,
                                    fontWeight: FontWeight.bold,
                                    color: ThemeTokens.of(context).ink),
                              ),
                            ),
                          ),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.45,
                          child: _TaskLine(
                            it: it,
                            nowMs: _nowMs,
                            selecting: _selecting,
                            selected: _selected,
                            onChange: () => setState(() {}),
                          ),
                        ),
                        child: _TaskLine(
                          it: it,
                          nowMs: _nowMs,
                          selecting: _selecting,
                          selected: _selected,
                          onChange: () => setState(() {}),
                        ),
                      );
                    },
                  )
                else
                  const _ListEmpty(msg: '随手做的事，会排在这里'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 「今天」列表里的一行：任务可拖动设焦点，日历事件点击直达系统日历。
  Widget _todayEntry(Map<String, Object?> e) {
    if (e['kind'] == 'event') {
      final ev = e['event'] as Map<String, Object?>;
      return _EventLine(event: ev, nowMs: _nowMs);
    }
    final it = e['item'] as Item;
    return LongPressDraggable<int>(
      data: it.id,
      delay: const Duration(milliseconds: 120),
      axis: Axis.vertical,
      feedback: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width - 96),
          child: StartCard(
            color: ThemeTokens.of(context).accentSoft,
            child: Text(
              it.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: S.textMd,
                  fontWeight: FontWeight.bold,
                  color: ThemeTokens.of(context).ink),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.45,
        child: _TaskLine(
          it: it,
          nowMs: _nowMs,
          selecting: _selecting,
          selected: _selected,
          onChange: () => setState(() {}),
        ),
      ),
      child: _TaskLine(
        it: it,
        nowMs: _nowMs,
        selecting: _selecting,
        selected: _selected,
        onChange: () => setState(() {}),
      ),
    );
  }

  /// 随手做拖进「日程」区：删原条目（可撤销）并打开编辑器选时间，存好即成日程。
  Future<void> _dragToSchedule(int id) async {
    final s = StartStore.I;
    final it = s.items.firstWhere((e) => e.id == id, orElse: () => Item());
    if (it.id == 0) return;
    final snap = s.exportJson();
    await s.delete(id, cascade: true);
    if (!mounted) return;
    UndoHost.show(context, '已移入日程，选个时间', () async => s.restoreJson(snap));
    final ctx = StartApp.navigatorKey.currentContext ?? context;
    await showItemEditor(ctx, Item()..title = it.title, asSchedule: true);
  }

  /// 日程区右上角加号：新建日程（打开即选日期时间，无标题或无时间不会保存）。
  Future<void> _newSchedule() async {
    final ctx = StartApp.navigatorKey.currentContext ?? context;
    await showItemEditor(ctx, Item(), asSchedule: true);
  }

  /// 选择态顶栏：关闭 + 计数 + 全选 + 完成 + 删除（老版 buildAnytimeSelectBar）。
  Widget _selectBar(C c, List<Item> list) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.md, S.sm, S.md, S.sm),
      child: Row(
        children: [
          IconBtn(Icons.close, tip: '退出选择', onTap: () {
            setState(() {
              _selecting = false;
              _selected.clear();
            });
          }),
          const SizedBox(width: S.sm),
          Text('已选 ${_selected.length}',
              style: TextStyle(
                  fontSize: S.textMd,
                  fontWeight: FontWeight.bold,
                  color: c.ink,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          const Spacer(),
          IconBtn(Icons.select_all_outlined, tip: '全选', onTap: () {
            setState(() {
              _selected.length == list.length
                  ? _selected.clear()
                  : _selected.addAll(list.map((e) => e.id));
            });
          }),
          IconBtn(Icons.check_circle_outline, tip: '完成', onTap: _batchComplete),
          IconBtn(Icons.delete_outline, tip: '删除', onTap: _batchDelete),
        ],
      ),
    );
  }

  Future<void> _batchComplete() async {
    if (_selected.isEmpty) return;
    final s = StartStore.I;
    final snap = await s.deleteAll(_selected.toList(), complete: true);
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    if (!mounted) return;
    UndoHost.show(context, '完成了', () async => s.restoreJson(snap));
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

/// 顶栏：Start 字标 + 设置（搜索在底栏）。
class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.md, S.sm, S.md, S.sm),
      child: Row(
        children: [
          Text('Start',
              style: TextStyle(
                  fontSize: S.textLg, fontWeight: FontWeight.bold, color: c.ink)),
          const Spacer(),
          IconBtn(Icons.settings_outlined, tip: '设置', onTap: () {
            Navigator.of(context, rootNavigator: true)
                .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
          }),
        ],
      ),
    );
  }
}

/// 今日焦点 hero：无卡片、大留白，是整页最大的视觉锚点。
/// 无焦点 = 超大标语 + 选一件胶囊 + 不选直接专注；有焦点 = 大字标题 + 主胶囊 + 次操作。
class _FocusHero extends StatelessWidget {
  final Item? focus;
  final bool hovering;
  final VoidCallback onPick;
  const _FocusHero({required this.focus, required this.hovering, required this.onPick});

  Future<void> _complete(BuildContext context) async {
    final s = StartStore.I;
    final it = focus!;
    final snap = s.exportJson();
    it.done = true;
    await s.put(it);
    if (!context.mounted) return;
    UndoHost.show(context, '完成一件，漂亮', () async => s.restoreJson(snap));
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final s = StartStore.I;
    final it = focus;

    return Padding(
      padding: const EdgeInsets.fromLTRB(S.xs, S.lg, S.xs, S.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (it == null) ...[
            // 空态：一句大标语把决策压到最小。
            Text('今天只做\n一件就好',
                style: TextStyle(
                    fontSize: 32,
                    height: 1.25,
                    fontWeight: FontWeight.bold,
                    color: c.ink)),
            const SizedBox(height: S.xs),
            Text('选好后，打开 Start 就能直接开始',
                style: TextStyle(fontSize: S.textSm, color: c.inkSoft)),
            const SizedBox(height: S.md),
            // 主胶囊：选一件事（也可以把日程卡直接拖到这里）。
            Pressable(
              onTap: onPick,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 30, vertical: 13),
                decoration: BoxDecoration(
                    color: c.accent, borderRadius: BorderRadius.circular(999)),
                child: Text('选一件',
                    style: TextStyle(
                        fontSize: S.textLg,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ),
            ),
            const SizedBox(height: S.xxs),
            Pressable(
              onTap: () => Navigator.of(context, rootNavigator: true)
                  .pushNamed('/focus'),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: S.xxs, vertical: S.xxs),
                child: Text('不选，直接专注',
                    style: TextStyle(
                        fontSize: S.textSm,
                        fontWeight: FontWeight.bold,
                        color: c.accent)),
              ),
            ),
          ] else ...[
            if (it.done)
              Padding(
                padding: const EdgeInsets.only(bottom: S.xxs),
                child: Row(
                  children: [
                    const Icon(Icons.verified_outlined,
                        size: 16, color: Colors.grey),
                    const SizedBox(width: S.xxs),
                    Text('主线完成，漂亮',
                        style: TextStyle(
                            fontSize: S.textSm,
                            fontWeight: FontWeight.bold,
                            color: c.inkSoft)),
                  ],
                ),
              ),
            Text(
              it.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 30,
                  height: 1.25,
                  fontWeight: FontWeight.bold,
                  color: it.done ? c.done : c.ink,
                  decoration:
                      it.done ? TextDecoration.lineThrough : null),
            ),
            if (!it.done) ...[
              ..._progress(context, s, it),
              const SizedBox(height: S.md),
              Row(
                children: [
                  // 主胶囊：只做它（进专注）。
                  Pressable(
                    onTap: () => Navigator.of(context, rootNavigator: true)
                        .pushNamed('/focus', arguments: it.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                          color: c.accent,
                          borderRadius: BorderRadius.circular(999)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.play_arrow,
                              size: 20, color: Colors.white),
                          const SizedBox(width: S.xxs),
                          Text('只做它',
                              style: TextStyle(
                                  fontSize: S.textMd,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  // 次操作：完成 / 拆步骤 / 编辑 / 换一件，纯图标不抢戏。
                  IconBtn(Icons.check, tip: '完成', onTap: () => _complete(context)),
                  IconBtn(Icons.call_split, tip: '拆成小步骤', onTap: () {
                    Navigator.of(context, rootNavigator: true)
                        .pushNamed('/steps', arguments: it.id);
                  }),
                  IconBtn(Icons.edit_outlined, tip: '编辑',
                      onTap: () => showItemEditor(context, it)),
                  // 换一件：降低承诺压力，随时可以重新选。
                  IconBtn(Icons.swap_horiz, tip: '换一件', onTap: onPick),
                ],
              ),
            ] else
              // 完成态：给下一件事一个明确的起点。
              Padding(
                padding: const EdgeInsets.only(top: S.sm),
                child: Pressable(
                  onTap: onPick,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                        color: c.accent,
                        borderRadius: BorderRadius.circular(999)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.arrow_forward,
                            size: 20, color: Colors.white),
                        const SizedBox(width: S.xxs),
                        Text('下一件',
                            style: TextStyle(
                                fontSize: S.textMd,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  List<Widget> _progress(BuildContext context, StartStore s, Item it) {
    final c = ThemeTokens.of(context);
    final progress = s.subtaskProgress(it.id);
    if (progress[1] == 0) return const [];
    return [
      const SizedBox(height: S.sm),
      ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          value: progress[0] / progress[1],
          minHeight: 6,
          backgroundColor: c.accentSoft,
          valueColor: AlwaysStoppedAnimation(c.accent),
        ),
      ),
      const SizedBox(height: S.xxs),
      Text('小步骤 ${progress[0]}/${progress[1]}',
          style: TextStyle(
              fontSize: S.textSm,
              color: c.inkSoft,
              fontFeatures: const [FontFeature.tabularFigures()])),
    ];
  }
}

/// 大时钟 + 日期 + 一句鼓励（红字），节奏像老版一样安静。
class _ClockHead extends StatelessWidget {
  final String hhmm;
  final String date;
  final String encourage;
  const _ClockHead({required this.hhmm, required this.date, required this.encourage});

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.xs, S.md, S.xs, S.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(hhmm,
                  style: TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.bold,
                    color: c.ink,
                    fontFamily: 'monospace',
                    fontFeatures: const [FontFeature.tabularFigures()],
                    height: 1.0,
                    letterSpacing: -1,
                  )),
              const SizedBox(height: S.xxs),
              Text(date, style: TextStyle(fontSize: S.textSm, color: c.inkSoft)),
            ],
          ),
          const Spacer(),
          // 鼓励语：低阻力措辞，永远不催。
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(top: S.xs),
              child: Text(encourage,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                      fontSize: S.textSm,
                      fontWeight: FontWeight.bold,
                      color: c.accent)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final VoidCallback? onAdd;
  const _SectionLabel(this.text, {this.onAdd});

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.xxs, S.lg, 0, S.xs),
      child: Row(
        children: [
          Text(text,
              style: TextStyle(
                  fontSize: S.textSm, color: c.inkSoft, fontWeight: FontWeight.bold)),
          const Spacer(),
          if (onAdd != null)
            Pressable(
              onTap: onAdd,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: S.xs, vertical: S.xxs),
                child: Icon(Icons.add, size: 20, color: c.accent),
              ),
            ),
        ],
      ),
    );
  }
}

/// 列表空态：一句话，安静留白。
class _ListEmpty extends StatelessWidget {
  final String msg;
  const _ListEmpty({required this.msg});

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.lg),
      child: Center(
        child: Text(msg, style: TextStyle(fontSize: S.textSm, color: c.inkSoft)),
      ),
    );
  }
}

/// 日历事件行：小方点 + 标题 + 时刻，点击直达系统日历。
class _EventLine extends StatelessWidget {
  final Map<String, Object?> event;
  final int nowMs;
  const _EventLine({required this.event, required this.nowMs});

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final begin = (event['begin'] as num?)?.toInt() ?? 0;
    final title = (event['title'] as String?) ?? '';
    final calName = (event['calName'] as String?) ?? '';
    final overdue = begin > 0 && begin < nowMs;
    return Pressable(
      onTap: () => Native.openUrl('content://com.android.calendar/time/$begin'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.xs),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: overdue ? c.line : c.inkSoft,
              ),
            ),
            const SizedBox(width: S.sm),
            Expanded(
              child: Text(
                title.isEmpty ? '(无标题)' : title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: S.textMd,
                    fontWeight: FontWeight.bold,
                    color: c.ink),
              ),
            ),
            const SizedBox(width: S.sm),
            Text(
              overdue ? _mmdd(begin) : _hm(begin),
              style: TextStyle(
                  fontSize: S.textSm,
                  fontWeight: FontWeight.bold,
                  color: overdue ? c.inkSoft : c.accent,
                  fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            if (calName.isNotEmpty) ...[
              const SizedBox(width: S.xs),
              Icon(Icons.event_outlined, size: 13, color: c.inkSoft),
            ],
          ],
        ),
      ),
    );
  }

  static String _hm(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  static String _mmdd(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.month}/${d.day}';
  }
}

/// 日程时刻胶囊：番茄红小字，点一下闪红底并弹时间选择，同日改时分即时生效（提醒自动跟随）。
class _TimeChip extends StatefulWidget {
  final Item it;
  final bool overdue;
  final VoidCallback onChange;
  const _TimeChip({required this.it, required this.overdue, required this.onChange});

  @override
  State<_TimeChip> createState() => _TimeChipState();
}

class _TimeChipState extends State<_TimeChip> {
  bool _flash = false;

  Future<void> _pick() async {
    setState(() => _flash = true);
    Timer(const Duration(milliseconds: 240), () {
      if (mounted) setState(() => _flash = false);
    });
    final d0 = DateTime.fromMillisecondsSinceEpoch(widget.it.dueTime);
    final c = ThemeTokens.of(context);
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(d0),
      builder: (_, child) => Theme(
        data: Theme.of(context)
            .copyWith(colorScheme: Theme.of(context).colorScheme.copyWith(primary: c.accent)),
        child: child!,
      ),
    );
    if (t == null) return;
    widget.it.dueTime = DateTime(d0.year, d0.month, d0.day, t.hour, t.minute)
        .millisecondsSinceEpoch;
    await StartStore.I.put(widget.it);
    widget.onChange();
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final d = DateTime.fromMillisecondsSinceEpoch(widget.it.dueTime);
    final label = widget.overdue
        ? '${d.month}/${d.day}'
        : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return Pressable(
      scale: 0.88,
      onTap: _pick,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: S.xs, vertical: 2),
        decoration: BoxDecoration(
          color: _flash ? c.accent : c.accentSoft,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: S.textSm,
              fontWeight: FontWeight.bold,
              color: _flash
                  ? Colors.white
                  : widget.overdue
                      ? c.inkSoft
                      : c.accent,
              fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ),
    );
  }
}

/// 任务行（日程 / 随手做共用）：勾选、标题、小步骤进度、时刻，纯文字不套卡片。
class _TaskLine extends StatelessWidget {
  final Item it;
  final int nowMs;
  final bool selecting;
  final Set<int> selected;
  final VoidCallback onChange;
  const _TaskLine({
    required this.it,
    required this.nowMs,
    required this.selecting,
    required this.selected,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final s = StartStore.I;
    final progress = s.subtaskProgress(it.id);
    final hasSub = progress[1] > 0;
    final sel = selected.contains(it.id);
    final overdue = !it.done && it.dueTime > 0 && it.dueTime < nowMs;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.xs),
      child: Pressable(
        onTap: selecting
            ? () { selected.contains(it.id) ? selected.remove(it.id) : selected.add(it.id); onChange(); }
            : () => showItemEditor(context, it, onDeleted: onChange),
        child: Row(
          children: [
            if (selecting)
              Icon(
                sel ? Icons.check_circle : Icons.circle_outlined,
                color: sel ? c.accent : c.inkSoft,
                size: 22,
              )
            else
              CheckDot(done: it.done, onTap: () async {
                it.done = !it.done;
                await s.put(it);
                onChange();
              }),
            const SizedBox(width: S.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    it.title.isEmpty ? it.note.split('\n').first : it.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: S.textMd,
                      color: it.done ? c.done : c.ink,
                      decoration: it.done ? TextDecoration.lineThrough : null,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (hasSub)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Icon(Icons.call_split, size: 12, color: c.inkSoft),
                          const SizedBox(width: S.xxs),
                          Text('小步骤 ${progress[0]}/${progress[1]}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: c.inkSoft,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ])),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (it.dueTime > 0) ...[
              const SizedBox(width: S.sm),
              selecting
                  ? Text(
                      overdue ? _mmdd(it.dueTime) : _hm(it.dueTime),
                      style: TextStyle(
                          fontSize: S.textSm,
                          fontWeight: FontWeight.bold,
                          color: overdue ? c.inkSoft : c.accent,
                          fontFeatures: const [FontFeature.tabularFigures()]),
                    )
                  : _TimeChip(it: it, overdue: overdue, onChange: onChange),
            ],
          ],
        ),
      ),
    );
  }

  static String _hm(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  static String _mmdd(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.month}/${d.day}';
  }
}
