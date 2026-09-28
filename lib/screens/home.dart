import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../channels/native.dart';
import '../data/item.dart';
import '../data/store.dart';
import '../main.dart';
import '../theme/tokens.dart';
import '../widgets/editor.dart';
import '../widgets/ui.dart';
import 'search.dart';
import 'settings.dart';
import '../l10n/i18n.dart';

/// 首页 = 今日（复刻老版 TodayScreen 的极简布局）。
/// 顶栏：Start 字标 + 搜索 + 设置。
/// 今日焦点 hero 占首屏最上方：无焦点=大标语+选一件胶囊；
/// 有焦点=大字标题+主胶囊「只做它」（自动进小步骤页）+次操作图标。日程卡长按可拖上来设焦点。
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

  /// 边沿检测：上一次悬停状态（用于 hover 震动只震一次）。
  bool _prevHoverSchedule = false;
  final Map<String, bool> _prevHoverGap = {};

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
    final wk = [tr('周日'), tr('周一'), tr('周二'), tr('周三'), tr('周四'), tr('周五'), tr('周六')];
    return tr('{0}月{1}日 {2}', [n.month, n.day, wk[n.weekday - 1]]);
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

  /// 「开始吧」：想到什么直接写一件；或从下面未完成的事里选一件。
  /// 返回 String=新写标题，Item=选已有，均设为今日焦点。
  Future<void> _pickFocus() async {
    final s = StartStore.I;
    final ctl = TextEditingController();
    final list = s.openTasks().where((e) => !e.done).toList();
    final result = await showStartSheet<Object>(context, (ctx) {
      final c = ThemeTokens.of(ctx);
      final pad = MediaQuery.of(ctx).viewInsets.bottom;
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(S.md, S.md, S.md, pad + S.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('今天只盯一件事'),
                  style: TextStyle(
                      fontSize: S.textLg, fontWeight: FontWeight.bold, color: c.ink)),
              const SizedBox(height: S.xxs),
              Text(tr('写一件，或者从下面选一件'),
                  style: TextStyle(fontSize: S.textSm, color: c.inkSoft)),
              const SizedBox(height: S.sm),
              TextField(
                controller: ctl,
                autofocus: true,
                maxLines: null,
                style: TextStyle(fontSize: S.textLg, color: c.ink, height: 1.4),
                decoration: InputDecoration(
                  hintText: tr('想到什么，直接写'),
                  hintStyle: TextStyle(color: c.inkSoft),
                  border: InputBorder.none,
                ),
              ),
              if (list.isNotEmpty) ...[
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
                          onTap: () => Navigator.pop(ctx, it),
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
              const SizedBox(height: S.sm),
              Pressable(
                onTap: () {
                  final t = ctl.text.trim();
                  if (t.isNotEmpty) Navigator.pop(ctx, t);
                },
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(S.radius)),
                  child: Text(tr('好了'),
                      style: TextStyle(color: Colors.white, fontSize: S.textMd, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      );
    });
    if (result is Item) {
      await s.setFocus(result.id);
    } else if (result is String && result.isNotEmpty) {
      final it = Item(kind: Item.kindTask, title: result);
      await s.put(it);
      await s.setFocus(it.id);
    }
  }

  /// 今天：今天到期 + 过期未完成（未来的日子还没到，先不来添乱）。
  /// 排序优先用用户手动拖拽写入的 rank（0 视为未排），其次按 dueTime。
  /// 已完成的日程自动从首页移除，数据保留在统计与搜索中。
  List<Item> _todaySchedule() {
    final now = DateTime.now();
    final dayEnd =
        DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final fid = StartStore.I.todayFocus()?.id;
    final list = StartStore.I
        .openTasks()
        .where((it) =>
            it.dueTime > 0 &&
            it.dueTime < dayEnd.millisecondsSinceEpoch &&
            it.id != fid &&
            !it.done)
        .toList()
      ..sort((a, b) {
        final ra = a.rank == 0 ? 1 << 30 : a.rank;
        final rb = b.rank == 0 ? 1 << 30 : b.rank;
        if (ra != rb) return ra.compareTo(rb);
        return a.dueTime.compareTo(b.dueTime);
      });
    return list;
  }

  /// 已完成的日程（顶层任务，按 dueTime 升序）：平时隐藏，选择态才列出，
  /// 供逐条勾选/全选/拖到垃圾桶清理，删除走现有选择态链路（可撤销）。
  List<Item> _doneSchedule() {
    final list = StartStore.I.items
        .where((it) => it.kind == Item.kindTask && it.parentId == 0 && it.done)
        .toList()
      ..sort((a, b) => a.dueTime.compareTo(b.dueTime));
    return list;
  }

  /// 合并今日任务与手机日历事件，按 begin 升序。被任务 eventId 消费的事件跳过；
  /// 服药计划写入日历的事件也跳过（服药数据只出现在服药页，不进日程区）。
  /// 兜底：旧版本写入、偏好已丢的残留服药事件，按标题（药名 · 剂量）匹配跳过显示，
  /// 只隐藏不删除（标题匹配删除用户日历太激进）。
  List<Map<String, Object?>> _mergeToday(List<Item> schedule) {
    final consumed = schedule.map((e) => e.eventId).where((e) => e > 0).toSet();
    final medEvents = StartStore.I.medCalendarEventIds();
    final medLabels = StartStore.I.medPlans().map((p) {
      final meta = StartStore.medPlanMeta(p);
      return '${p.title} · ${(meta['dose'] as String?) ?? ''}'.trim();
    }).toSet();
    final entries = <Map<String, Object?>>[];
    for (final it in schedule) {
      entries.add({'kind': 'task', 'item': it, 'time': it.dueTime});
    }
    for (final ev in _events) {
      final id = (ev['id'] as num?)?.toInt() ?? 0;
      if (consumed.contains(id) || medEvents.contains(id)) continue;
      if (medLabels.contains(ev['title'])) continue;
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
    // DragDockBus 兜底：若 active=true 超过 8 秒视为卡死（正常拖拽不可能撑这么久），
    // 延迟一帧重置。阈值放宽到 8s 避免慢速拖拽时垃圾桶中途消失。
    if (DragDockBus.active.value &&
        DateTime.now().millisecondsSinceEpoch - DragDockBus.lastActiveAt > 8000) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        DragDockBus.active.value = false;
        DragDockBus.pendingIds = null;
      });
    }

    final c = ThemeTokens.of(context);
    final s = StartStore.I;
    final focus = s.todayFocus();
    final fid = focus?.id;
    // 焦点任务不在下方列表重复出现：一次只做一件事，避免两套按钮。
    final today = _todaySchedule();
    final anytime = s.anytimeTasks().where((it) => it.id != fid).toList();
    final entries = _mergeToday(today);
    // 已完成的日程平时隐藏，选择态才列出（勾选/全选/拖垃圾桶都走现有链路）。
    final doneSchedule = _selecting ? _doneSchedule() : const <Item>[];
    final remaining = today.length + anytime.length;
    final encourage =
        remaining == 0 ? tr('今天的事都做完了，了不起') : tr('还有 {0} 件，一件件来', [remaining]);

    return SafeArea(
      child: Column(
        children: [
          if (_selecting)
            _selectBar(c, [...today, ...anytime, ...doneSchedule])
          else
            const _TopBar(),
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
                // 日程区：任何有效条目都能拖进来转日程（不管选没选）。
                DragTarget<int>(
                  onWillAcceptWithDetails: (d) => d.data > 0,
                  onAcceptWithDetails: (d) => _dragToSchedule(d.data),
                  builder: (ctx, cand, _) {
                    final hov = cand.isNotEmpty;
                    // 边沿震动：只在首次进入时震一次，不连震
                    if (hov && !_prevHoverSchedule) HapticFeedback.lightImpact();
                    _prevHoverSchedule = hov;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      decoration: BoxDecoration(
                        color: hov ? c.accentSoft : Colors.transparent,
                        borderRadius: BorderRadius.circular(S.radius),
                      ),
                      child: Column(
                        children: [
                          GestureDetector(
                            onLongPress: () => setState(() => _selecting = true),
                            child: _SectionLabel(tr('日程'), onAdd: _newSchedule),
                          ),
                          if (entries.isNotEmpty)
                            ..._scheduleRowsWithGaps(entries, c)
                          else
                            _ListEmpty(msg: tr('还没有日程')),
                          // 选择态追加已完成日程：删除线/弱化色由行组件完成态自带。
                          if (_selecting)
                            for (var i = 0; i < doneSchedule.length; i++) ...[
                              const SizedBox(height: S.xxs),
                              _todayEntry({
                                'kind': 'task',
                                'item': doneSchedule[i],
                                'time': doneSchedule[i].dueTime,
                              }),
                            ],
                        ],
                      ),
                    );
                  },
                ),
                // 随手做：没定时间的都待在这，头部长按可跨模块拖拽/排序/删，尾部长按进多选。
                GestureDetector(
                  onLongPress: () => setState(() => _selecting = true),
                  child: _SectionLabel(tr('随手做'), onAdd: _quickAdd),
                ),
                if (anytime.isNotEmpty)
                  Column(
                    children: [
                      // 第 0 行上方的插入缝（之前漏了，拖不到最顶）
                      DragTarget<int>(
                        onWillAcceptWithDetails: (d) => !_selecting,
                        onAcceptWithDetails: (d) async {
                          final o = anytime.indexWhere((e) => e.id == d.data);
                          if (o < 0) return;
                          final ids = anytime.map((e) => e.id).toList();
                          ids.removeAt(o);
                          ids.insert(0, d.data);
                          await s.reorder(ids);
                          if (mounted) setState(() {});
                        },
                        builder: (ctx, cand, _) {
                          final hov = cand.isNotEmpty;
                          // 边沿震动：只在首次进入时震一次，悬停期间不连震
                          final key = 'top';
                          final prev = _prevHoverGap[key] ?? false;
                          if (hov && !prev) HapticFeedback.lightImpact();
                          _prevHoverGap[key] = hov;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            curve: Curves.easeOut,
                            height: hov ? 28 : 0,
                            margin: hov
                                ? const EdgeInsets.symmetric(vertical: 4)
                                : EdgeInsets.zero,
                            decoration: BoxDecoration(
                              color: hov
                                  ? c.accent.withValues(alpha: 0.18)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: hov
                                  ? [
                                      BoxShadow(
                                        color: c.accent.withValues(alpha: 0.3),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                          );
                        },
                      ),
                      for (var i = 0; i < anytime.length; i++) ...[
                        _anytimeRow(anytime[i]),
                        if (i < anytime.length - 1)
                          DragTarget<int>(
                            onWillAcceptWithDetails: (d) => !_selecting,
                            onAcceptWithDetails: (d) async {
                              final o = anytime.indexWhere((e) => e.id == d.data);
                              if (o < 0) return;
                              final ids = anytime.map((e) => e.id).toList();
                              var n = i + 1;
                              if (n > o) n--;
                              ids.removeAt(o);
                              ids.insert(n, d.data);
                              await s.reorder(ids);
                              if (mounted) setState(() {});
                            },
                            builder: (ctx, cand, _) {
                              final hov = cand.isNotEmpty;
                              final key = 'gap_$i';
                              final prev = _prevHoverGap[key] ?? false;
                              if (hov && !prev) HapticFeedback.lightImpact();
                              _prevHoverGap[key] = hov;
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 120),
                                curve: Curves.easeOut,
                                height: hov ? 28 : 6,
                                margin: hov
                                    ? const EdgeInsets.symmetric(vertical: 4)
                                    : const EdgeInsets.symmetric(vertical: 2),
                                decoration: BoxDecoration(
                                  color: hov
                                      ? c.accent.withValues(alpha: 0.18)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: hov
                                      ? [
                                          BoxShadow(
                                            color: c.accent.withValues(alpha: 0.3),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                              );
                            },
                          ),
                      ],
                    ],
                  )
                else
                  _ListEmpty(msg: tr('随手做的事，会排在这里')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 日程 entries（task + event 混排）生成带排序缝的 rows。
  /// 手机日历 event 条目不参与排序（只读），缝只插在 task 之间（含首尾）。
  List<Widget> _scheduleRowsWithGaps(List<Map<String, Object?>> entries, C c) {
    final s = StartStore.I;
    final taskIds = <int>[];
    for (final e in entries) {
      if (e['kind'] != 'event') taskIds.add((e['item'] as Item).id);
    }
    if (taskIds.isEmpty) {
      // 没日程 task 就直接按 entries 出（只有 event 手机日历条目）
      final out = <Widget>[];
      for (var i = 0; i < entries.length; i++) {
        if (i > 0) out.add(const SizedBox(height: S.xxs));
        out.add(_todayEntry(entries[i]));
      }
      return out;
    }

    Widget gapWidget(String key, int insertAtTaskIdx, C c) {
      final prev = _prevHoverGap['sch_$key'] ?? false;
      return DragTarget<int>(
        onWillAcceptWithDetails: (d) => !_selecting,
        onAcceptWithDetails: (d) async {
          final o = taskIds.indexOf(d.data);
          if (o < 0) return;
          final ids = List<int>.from(taskIds);
          ids.removeAt(o);
          var n = insertAtTaskIdx;
          if (n > o) n--;
          ids.insert(n, d.data);
          await s.reorder(ids);
          if (mounted) setState(() {});
        },
        builder: (ctx, cand, _) {
          final hov = cand.isNotEmpty;
          // 边沿震动：首次进入时震一次，悬停期间不连震
          if (hov && !prev) HapticFeedback.lightImpact();
          _prevHoverGap['sch_$key'] = hov;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            height: hov ? 28 : 6,
            margin: hov
                ? const EdgeInsets.symmetric(vertical: 4)
                : const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: hov
                  ? c.accent.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              boxShadow: hov
                  ? [
                      BoxShadow(
                        color: c.accent.withValues(alpha: 0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
          );
        },
      );
    }

    final out = <Widget>[];
    int taskIdx = 0;
    // 顶缝（第一个 task 之前）
    out.add(gapWidget('top', 0, c));
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (e['kind'] == 'event') {
        // event 只读，直接插
        out.add(const SizedBox(height: S.xxs));
        out.add(_todayEntry(e));
        continue;
      }
      // task
      if (taskIdx > 0) {
        // 上一个是 task，插 task->task 的缝
        out.add(const SizedBox(height: S.xxs));
        out.add(gapWidget('${taskIdx - 1}to$taskIdx', taskIdx, c));
      }
      out.add(_todayEntry(e));
      taskIdx++;
    }
    // 尾缝（最后一个 task 之后）
    if (taskIdx > 0) out.add(gapWidget('bottom', taskIdx, c));
    return out;
  }

  /// 「今天」列表里的一行：根据选择态走对应的独立行组件。
  Widget _todayEntry(Map<String, Object?> e) {
    if (e['kind'] == 'event') {
      final ev = e['event'] as Map<String, Object?>;
      return _EventLine(event: ev, nowMs: _nowMs);
    }
    return _selecting
        ? _itemRowSelecting(e['item'] as Item)
        : _itemRowNormal(e['item'] as Item);
  }

  /// 随手做区的一行：同日程区，头尾拆分统一交互。
  Widget _anytimeRow(Item it) =>
      _selecting ? _itemRowSelecting(it) : _itemRowNormal(it);

  // ================================================================
  //  两个独立行组件，职责单一，互不嵌套
  // ================================================================

  /// 非选择态行：
  ///   头部 44x44 CheckDot（扩大命中区）+ 长按拖拽（LongPressDraggable 120ms）
  ///   尾部 GestureDetector → 长按进多选 / 点击进编辑器
  Widget _itemRowNormal(Item it) {
    final s = StartStore.I;
    final c = ThemeTokens.of(context);
    final overdue = !it.done && it.dueTime > 0 && it.dueTime < _nowMs;
    final progress = s.subtaskProgress(it.id);
    final hasSub = progress[1] > 0;

    final headContent = SizedBox(
      width: 44,
      height: 44,
      child: Center(
        child: CheckDot(
          done: it.done,
          onTap: () async {
            it.done = !it.done;
            await s.put(it);
            setState(() {});
          },
        ),
      ),
    );

    final tail = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () {
        HapticFeedback.selectionClick();
        setState(() {
          _selecting = true;
          _selected.add(it.id);
        });
      },
      onTap: () => showItemEditor(context, it, onDeleted: () => setState(() {})),
      child: _itemTailBody(it, c, overdue, hasSub, progress, selecting: false),
    );

    // DraggableLine 只包头部 44x44 区域 —— 尾部 GestureDetector 是 sibling，
    // 手势竞技场不会被 LongPressDraggable(120ms) 吞掉尾部 long press(500ms)。
    // 这样头部长按起拖、尾部长按进多选两个手势互不干扰。
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.xs),
      child: Row(
        children: [
          DraggableLine(id: it.id, title: it.title, child: headContent),
          Expanded(child: tail),
        ],
      ),
    );
  }

  /// 选择态行：
  ///   头部 44x44 drag_indicator 拖柄图标（视觉上一眼可辨，消两圈撞车）
  ///   整条 Row 只包一层 DraggableLine（已选可整组拖桶）
  ///   尾部末尾是勾选圆圈 Icon（唯一选择/取消入口）
  Widget _itemRowSelecting(Item it) {
    final c = ThemeTokens.of(context);
    final sel = _selected.contains(it.id);
    final overdue = !it.done && it.dueTime > 0 && it.dueTime < _nowMs;
    final s = StartStore.I;
    final progress = s.subtaskProgress(it.id);
    final hasSub = progress[1] > 0;

    // 选择态头部换成拖柄图标——视觉上一眼区分（灰色拖柄 vs 尾部彩色勾选圆圈），
    // 消除两个圆圈含义撞车。44x44 透明命中区保证拖起不难。
    final headContent = SizedBox(
      width: 44,
      height: 44,
      child: Center(
        child: Icon(Icons.drag_indicator_rounded, size: 22, color: c.inkSoft),
      ),
    );

    final tail = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () {
        HapticFeedback.selectionClick();
        setState(() {
          sel ? _selected.remove(it.id) : _selected.add(it.id);
        });
      },
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          sel ? _selected.remove(it.id) : _selected.add(it.id);
        });
      },
      child: _itemTailBody(it, c, overdue, hasSub, progress, selecting: true, sel: sel),
    );

    // DraggableLine 只包头部拖柄区域——尾部 GestureDetector（切换选中）是 sibling，
    // 120ms 长按起拖不会吞掉尾部的 tap/long press 切换。
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.xs),
      child: Row(
        children: [
          DraggableLine(
            id: it.id,
            title: it.title,
            enabled: sel, // 只有已选中的才能起拖
            dragIds: sel && _selected.length > 1 ? _selected.toList() : null,
            selected: sel,
            onDragEnd: () => setState(() {
              _selecting = false;
              _selected.clear();
            }),
            child: headContent,
          ),
          Expanded(child: tail),
        ],
      ),
    );
  }

  /// 共享尾部主体（标题 / 小步骤 / 日期 / 末位图标位）。
  /// [selecting] → 末尾为勾选圆圈 Icon（由外层传入 sel 决定）；否则为 more_horiz。
  Widget _itemTailBody(Item it, C c, bool overdue, bool hasSub,
      List<int> progress, {required bool selecting, bool sel = false}) {
    return Row(
      children: [
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
                      Icon(Icons.hexagon_outlined, size: 12, color: c.inkSoft),
                      const SizedBox(width: S.xxs),
                      Text(tr('小步骤 {0}/{1}', [progress[0], progress[1]]),
                          style: TextStyle(
                              fontSize: 11,
                              color: c.inkSoft,
                              fontFeatures: const [FontFeature.tabularFigures()])),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (it.dueTime > 0) ...[
          const SizedBox(width: S.sm),
          Text(
            overdue ? _mmdd(it.dueTime) : _hm(it.dueTime),
            style: TextStyle(
                fontSize: S.textSm,
                fontWeight: FontWeight.bold,
                color: overdue ? c.accent : (it.done ? c.done : c.inkSoft),
                fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
        const SizedBox(width: S.xs),
        selecting
            ? Icon(sel ? Icons.check_circle : Icons.circle_outlined,
                color: sel ? c.accent : c.inkSoft, size: 22)
            : Icon(Icons.more_horiz, size: 16, color: c.inkSoft),
      ],
    );
  }

  /// 随手做拖进「日程」区：先弹编辑器让用户选时间，**确认后**才删原条目，
  /// 用户取消则原条目不动，避免静默丢数据。
  Future<void> _dragToSchedule(int id) async {
    final s = StartStore.I;
    final it = s.items.firstWhere((e) => e.id == id, orElse: () => Item());
    if (it.id == 0) return;
    final ctx = StartApp.navigatorKey.currentContext ?? context;
    if (!ctx.mounted) return;
    final ok = await showScheduleEditor(ctx, title: it.title);
    if (ok) {
      s.delete(id, cascade: true);
      if (mounted) setState(() {});
    }
  }

  /// 日程区右上角加号：多行批量写入日程（单行也能正常创建）。
  Future<void> _newSchedule() async {
    final ctx = StartApp.navigatorKey.currentContext ?? context;
    if (ctx.mounted) await showScheduleBatch(ctx);
  }

  /// 选择态顶栏：关闭 + 计数 + 全选（次级） + 完成（主按钮，accent 实心）。
  /// 删除统一走底部红色拖桶，顶栏不再放删除按钮。
  Widget _selectBar(C c, List<Item> list) {
    final allDone = _selected.length == list.length && _selected.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.md, S.sm, S.md, S.sm),
      child: Row(
        children: [
          IconBtn(Icons.close, tip: tr('退出选择'), onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              _selecting = false;
              _selected.clear();
            });
          }),
          const SizedBox(width: S.sm),
          Expanded(
            child: Text(tr('已选 {0}', [_selected.length]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: S.textMd,
                    fontWeight: FontWeight.bold,
                    color: c.ink,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          const SizedBox(width: S.sm),
          // 全选：次级 outline 小按钮
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: c.inkSoft,
              side: BorderSide(color: c.inkSoft.withValues(alpha: 0.3), width: 1),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() {
                allDone
                    ? _selected.clear()
                    : _selected.addAll(list.map((e) => e.id));
              });
            },
            child: Icon(allDone ? Icons.deselect : Icons.select_all, size: 18),
          ),
          const SizedBox(width: S.sm),
          // 完成：主按钮，accent 实心圆角
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: c.accent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: _selected.isEmpty
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    _batchComplete();
                  },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check, size: 18),
                const SizedBox(width: 4),
                Text(tr('完成'),
                    style: const TextStyle(
                        fontSize: S.textSm, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
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
    UndoHost.show(context, tr('完成了'), () async => s.restoreJson(snap));
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

/// 顶栏：Start 字标 + 搜索 + 设置。
class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.md, S.sm, S.md, S.sm),
      child: Row(
        children: [
          Text(Lang.appNameOf(Lang.current),
              style: TextStyle(
                  fontSize: S.textLg, fontWeight: FontWeight.bold, color: c.ink)),
          const Spacer(),
          IconBtn(Icons.search_outlined, tip: tr('搜索'), onTap: () {
            Navigator.of(context, rootNavigator: true)
                .push(MaterialPageRoute(builder: (_) => const SearchScreen()));
          }),
          const SizedBox(width: S.xxs),
          IconBtn(Icons.settings_outlined, tip: tr('设置'), onTap: () {
            Navigator.of(context, rootNavigator: true)
                .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
          }),
        ],
      ),
    );
  }
}

/// 今日焦点 hero：无卡片、大留白，是整页最大的视觉锚点。
/// 无焦点 = 超大标语 + 选一件胶囊；有焦点 = 大字标题 + 主胶囊 + 次操作。
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
    UndoHost.show(context, tr('完成一件，漂亮'), () async => s.restoreJson(snap));
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
            Text(tr('只专注一件事'),
                style: TextStyle(
                    fontSize: 32,
                    height: 1.25,
                    fontWeight: FontWeight.bold,
                    color: c.ink)),
            const SizedBox(height: S.xs),
            Text(tr('选好后，打开启序就能直接开始'),
                style: TextStyle(fontSize: S.textSm, color: c.inkSoft)),
            const SizedBox(height: S.md),
            // 主胶囊：开始吧——写一件或选一件，也可以把日程卡直接拖到这里。
            Pressable(
              onTap: onPick,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 30, vertical: 13),
                decoration: BoxDecoration(
                    color: c.accent, borderRadius: BorderRadius.circular(999)),
                child: Text(tr('开始吧'),
                    style: TextStyle(
                        fontSize: S.textLg,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
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
                    Flexible(
                      child: Text(tr('主线完成，漂亮'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: S.textSm,
                              fontWeight: FontWeight.bold,
                              color: c.inkSoft)),
                    ),
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
                  // 主胶囊：只做它——点它自动进小步骤页，事大先拆小，降低启动阻力。
                  Pressable(
                    onTap: () {
                      Navigator.of(context, rootNavigator: true)
                          .pushNamed('/steps', arguments: it.id);
                    },
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
                          Text(tr('只做它'),
                              style: TextStyle(
                                  fontSize: S.textMd,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  // 次操作：完成 / 换一件 / 编辑，纯图标不抢戏。进专注统一走底栏专注页。
                  IconBtn(Icons.check, tip: tr('完成'), onTap: () => _complete(context)),
                  // 换一件：降低承诺压力，随时可以换。
                  IconBtn(Icons.swap_horiz, tip: tr('换一件'), onTap: onPick),
                  IconBtn(Icons.edit_outlined, tip: tr('编辑'),
                      onTap: () => showItemEditor(context, it)),
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
                        Text(tr('下一件'),
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
      Text(tr('小步骤 {0}/{1}', [progress[0], progress[1]]),
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
          // 时钟列按内容定宽，不参与剩余空间分配：再长的外语鼓励语也不能把
          // HH:mm 挤压折行（日语环境 monospace 回退到 CJK 等宽字体，数字偏宽）。
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(hhmm,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.bold,
                      color: c.ink,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      height: 1.0,
                      letterSpacing: -1,
                    )),
              ),
              const SizedBox(height: S.xxs),
              Text(date,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: TextStyle(fontSize: S.textSm, color: c.inkSoft)),
            ],
          ),
          const SizedBox(width: S.sm),
          // 鼓励语：低阻力措辞，永远不催。占剩余宽度，右对齐自行换行。
          Expanded(
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

/// 日历事件行：小方点 + 标题 + 时刻，纯展示不跳转（避免误入系统打开方式界面）。
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
    return Padding(
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
                title.isEmpty ? tr('(无标题)') : title,
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
    final t = await showStartTimePicker(context,
        initial: TimeOfDay.fromDateTime(d0));
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

/// 日程条目的「不做了 / 改日再做」：右侧小圆钮展开两个小胶囊，不遮挡标题。
/// 不做了 = 删除（5 秒可撤销）；改日再做 = 日期往后推（+1/+2/+3 天或选日期），
/// 提醒与日历随 StartStore.put 自动重挂。
class _ScheduleActions extends StatefulWidget {
  final Item it;
  final VoidCallback onChange;
  const _ScheduleActions({required this.it, required this.onChange});

  @override
  State<_ScheduleActions> createState() => _ScheduleActionsState();
}

class _ScheduleActionsState extends State<_ScheduleActions> {
  bool _open = false;

  /// 不做了：整件事从清单移除，可撤销。
  Future<void> _skip() async {
    if (widget.it.id <= 0) return;
    final s = StartStore.I;
    final snap = s.exportJson();
    s.delete(widget.it.id, cascade: true);
    widget.onChange();
    if (!context.mounted) return;
    UndoHost.show(context, tr('不做了'), () async => s.restoreJson(snap));
  }

  /// 改日再做：dueTime 平移到未来某天的同一时分。
  Future<void> _postpone(int days) async {
    final it = widget.it;
    final d0 = DateTime.fromMillisecondsSinceEpoch(it.dueTime);
    it.dueTime = DateTime(d0.year, d0.month, d0.day + days, d0.hour, d0.minute)
        .millisecondsSinceEpoch;
    await StartStore.I.put(it);
    widget.onChange();
  }

  Future<void> _postponePick() async {
    final it = widget.it;
    final d0 = DateTime.fromMillisecondsSinceEpoch(it.dueTime);
    final d = await showDatePicker(
      context: context,
      initialDate: d0.add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    it.dueTime = DateTime(d.year, d.month, d.day, d0.hour, d0.minute)
        .millisecondsSinceEpoch;
    await StartStore.I.put(it);
    widget.onChange();
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_open) ...[
          _pill(c, tr('不做了'), _skip),
          const SizedBox(width: S.xxs),
          _pill(c, tr('改日再做'), () async {
            final r = await showStartSheet<String>(context, (ctx) {
              final c2 = ThemeTokens.of(ctx);
              final pad = MediaQuery.of(ctx).viewInsets.bottom;
              Widget opt(String label, String key) => Padding(
                    padding: const EdgeInsets.only(bottom: S.xs),
                    child: Pressable(
                      onTap: () => Navigator.pop(ctx, key),
                      child: Container(
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c2.cardAlt,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(label,
                            style: TextStyle(
                                fontSize: S.textMd,
                                fontWeight: FontWeight.bold,
                                color: c2.ink)),
                      ),
                    ),
                  );
              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(S.md, S.md, S.md, pad + S.md),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(tr('改日再做'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: S.textLg,
                              fontWeight: FontWeight.bold,
                              color: c2.ink)),
                      const SizedBox(height: S.sm),
                      opt(tr('明天'), '1'),
                      opt(tr('后天'), '2'),
                      opt(tr('三天后'), '3'),
                      opt(tr('选个日期'), 'pick'),
                    ],
                  ),
                ),
              );
            });
            if (r == 'pick') {
              await _postponePick();
            } else if (r != null) {
              await _postpone(int.parse(r));
            }
          }),
          const SizedBox(width: S.xxs),
        ],
        Pressable(
          scale: 0.88,
          onTap: () => setState(() => _open = !_open),
          child: Icon(
            _open ? Icons.close : Icons.more_horiz,
            size: 18,
            color: c.inkSoft,
          ),
        ),
      ],
    );
  }

  Widget _pill(C c, String label, VoidCallback onTap) {
    return Pressable(
      scale: 0.92,
      onTap: () {
        setState(() => _open = false);
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: S.xs, vertical: 2),
        decoration: BoxDecoration(
          color: c.cardAlt,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: S.textSm,
                fontWeight: FontWeight.bold,
                color: c.inkSoft,
                height: 1.2)),
      ),
    );
  }
}
