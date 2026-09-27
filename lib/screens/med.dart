import 'package:flutter/material.dart';

import '../data/item.dart';
import '../data/store.dart';
import '../channels/native.dart';
import '../l10n/i18n.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

Widget _slotChip(C c, String label, bool selected, VoidCallback onTap) {
  return Pressable(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: S.sm, vertical: S.xs),
      decoration: BoxDecoration(
        color: selected ? c.accent : c.cardAlt,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: S.textSm,
              fontWeight: FontWeight.bold,
              color: selected ? Colors.white : c.ink)),
    ),
  );
}

/// 服药 = 每日用药管理：按日期翻页查看，按自定义时间点分组，药品带规格与剂量。
/// 计划存 kind=3 顶层 Item（title=药名，note JSON 存 times/cat/dose/start/end，
/// times 为用户自定义的任意多个 HH:mm 时间点）。
/// 服药记录 = kind=3 + parentId=计划id + dueTime=该日该时刻毫秒 + done=true。
/// 提醒/日历 = 保存计划时由 StartStore.armMedPlanNotify 统一挂上（30 天滚动窗口）。
class MedScreen extends StatefulWidget {
  const MedScreen({super.key});

  @override
  State<MedScreen> createState() => _MedScreenState();
}

class _MedScreenState extends State<MedScreen> {
  int _dayOffset = 0; // 0=今天，-1=昨天，1=明天
  String _catFilter = ''; // ''=全部
  bool _showCalendar = false; // 日历视图开关
  late DateTime _calMonth = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    StartStore.I.addListener(_onStore);
  }

  @override
  void dispose() {
    StartStore.I.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  DateTime get _date {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
        .add(Duration(days: _dayOffset));
  }

  /// 相对日胶囊文案：今天 / 昨天 / 明天，其余日期不标（与统计页同款）。
  String? get _relDay => _dayOffset == 0
      ? tr('今天')
      : _dayOffset == 1
          ? tr('明天')
          : _dayOffset == -1
              ? tr('昨天')
              : null;

  static int _dueMs(DateTime day, String t) {
    final parts = t.split(':');
    final h = int.tryParse(parts[0]) ?? 8;
    final min = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return DateTime(day.year, day.month, day.day, h, min)
        .millisecondsSinceEpoch;
  }

  /// 当日应服计划：过滤日期范围 + 分类，按自定义时间点分组（时间点升序）。
  Map<String, List<Item>> _plansByTime() {
    final dayMs =
        DateTime(_date.year, _date.month, _date.day).millisecondsSinceEpoch;
    final map = <String, List<Item>>{};
    for (final p in StartStore.I.medPlans()) {
      final m = StartStore.medPlanMeta(p);
      final start = (m['start'] as int?) ?? 0;
      final end = (m['end'] as int?) ?? 0;
      if (start > 0 && dayMs < start) continue;
      if (end > 0 && dayMs > end) continue;
      final cat = (m['cat'] as String?) ?? '';
      if (_catFilter.isNotEmpty && cat != _catFilter) continue;
      final times = (m['times'] as List?)?.cast<String>() ?? const [];
      for (final t in times) {
        map.putIfAbsent(t, () => []).add(p);
      }
    }
    return map;
  }

  /// 该计划在该日该时间点是否已服。
  bool _isDone(Item plan, String time) {
    final due = _dueMs(_date, time);
    return StartStore.I.medLogsOf(plan.id).any((l) => l.dueTime == due && l.done);
  }

  /// 打勾记录服药（不可撤销单条，仅作记录）。
  Future<void> _logDose(Item plan, String time) async {
    final due = _dueMs(_date, time);
    // 已存在则跳过（防重复）。
    final existing = StartStore.I.medLogsOf(plan.id).where((l) => l.dueTime == due);
    if (existing.isNotEmpty) return;
    await StartStore.I.put(Item(
      kind: Item.kindMed,
      parentId: plan.id,
      title: plan.title,
      note: 'dose',
      dueTime: due,
      done: true,
    ));
  }

  /// 某天服药状态：0=无计划，1=有漏服（过去），2=部分已服，3=全部已服，4=未来有计划。
  int _dayStatus(DateTime day) {
    final day0 = DateTime(day.year, day.month, day.day);
    final dayMs = day0.millisecondsSinceEpoch;
    final now = DateTime.now();
    final today0 = DateTime(now.year, now.month, now.day);
    var total = 0, done = 0;
    for (final p in StartStore.I.medPlans()) {
      final m = StartStore.medPlanMeta(p);
      final start = (m['start'] as int?) ?? 0;
      final end = (m['end'] as int?) ?? 0;
      if (start > 0 && dayMs < start) continue;
      if (end > 0 && dayMs > end) continue;
      final times = (m['times'] as List?)?.cast<String>() ?? const [];
      if (times.isEmpty) continue;
      final logs = StartStore.I.medLogsOf(p.id);
      for (final t in times) {
        total++;
        final due = _dueMs(day0, t);
        if (logs.any((l) => l.dueTime == due && l.done)) done++;
      }
    }
    if (total == 0) return 0;
    if (done == total) return 3;
    if (done > 0) return 2;
    return day0.isBefore(today0) ? 1 : 4;
  }

  /// 删除走全局拖拽：长按卡片拖进底部红区垃圾桶，撤销与提醒取消由
  /// GlobalDragDock / StartStore 统一处理，这里不再单设删除按钮。
  /// 提醒/日历由 StartStore.armMedPlanNotify 统一处理（通知 + 日历 + 开机重排）。

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final plansByTime = _plansByTime();
    final times = plansByTime.keys.toList()..sort();
    final cats = StartStore.I.medPlans()
        .map((p) => (StartStore.medPlanMeta(p)['cat'] as String?) ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Column(
          children: [
            // 日期翻页器：与统计页同款——箭头 + 日期 + 相对日胶囊收拢居中；
            // 右侧日历/列表切换按钮。
            Padding(
              padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.xs),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconBtn(Icons.chevron_left, tip: tr('前一天'), onTap: () {
                        setState(() => _dayOffset--);
                      }),
                      const SizedBox(width: S.sm),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            tr('{0}月{1}日', [_date.month, _date.day]),
                            style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: c.ink,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                                height: 1.0),
                          ),
                          if (_relDay != null) ...[
                            const SizedBox(width: S.xs),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: S.xs, vertical: 2),
                              decoration: BoxDecoration(
                                color: c.accentSoft,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(_relDay!,
                                  style: TextStyle(
                                      fontSize: S.textSm,
                                      fontWeight: FontWeight.bold,
                                      color: c.accent,
                                      height: 1.0)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(width: S.sm),
                      IconBtn(Icons.chevron_right, tip: tr('后一天'), onTap: () {
                        setState(() => _dayOffset++);
                      }),
                      const SizedBox(width: S.xs),
                      // 日历 / 列表视图切换。
                      IconBtn(
                        _showCalendar
                            ? Icons.view_list_outlined
                            : Icons.calendar_month_outlined,
                        tip: tr('服药日历'),
                        onTap: () => setState(() {
                          _showCalendar = !_showCalendar;
                          if (_showCalendar) {
                            _calMonth = DateTime(_date.year, _date.month);
                          }
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: S.xxs),
                  Text(_weekday(_date),
                      style: TextStyle(
                          fontSize: S.textSm,
                          color: c.inkSoft,
                          fontFeatures: const [
                            FontFeature.tabularFigures()
                          ],
                          height: 1.2)),
                ],
              ),
            ),
            // 分类筛选胶囊（日历视图下隐藏，避免干扰）。
            if (cats.isNotEmpty && !_showCalendar)
              Padding(
                padding: const EdgeInsets.fromLTRB(S.lg, 0, S.lg, S.xxs),
                child: Wrap(
                  spacing: S.xs,
                  children: [
                    _CatChip(
                      label: tr('全部'),
                      selected: _catFilter.isEmpty,
                      onTap: () => setState(() => _catFilter = ''),
                    ),
                    for (final cat in cats)
                      _CatChip(
                        label: cat,
                        selected: _catFilter == cat,
                        onTap: () => setState(() => _catFilter = cat),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: _showCalendar
                  ? _MedCalendar(
                      month: _calMonth,
                      statusOf: _dayStatus,
                      onMonthChange: (m) => setState(() => _calMonth = m),
                      onPickDay: (d) {
                        final now = DateTime.now();
                        final today = DateTime(now.year, now.month, now.day);
                        setState(() {
                          _dayOffset =
                              DateTime(d.year, d.month, d.day)
                                  .difference(today)
                                  .inDays;
                          _showCalendar = false;
                        });
                      },
                    )
                  : ListView(
                      padding:
                          const EdgeInsets.fromLTRB(S.lg, S.sm, S.lg, S.lg),
                      children: [
                        if (times.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: S.md),
                            child: Text(tr('没有要吃的药'),
                                style: TextStyle(
                                    fontSize: S.textSm, color: c.inkSoft)),
                          )
                        else
                          for (final t in times)
                            _TimeSection(
                              time: t,
                              plans: plansByTime[t]!,
                              isDone: _isDone,
                              onLog: _logDose,
                              onEdit: _editPlan,
                              onAdd: () => _addPlan(t),
                            ),
                        // 底部固定新建入口：无分组可加点这里。
                        Padding(
                          padding: const EdgeInsets.only(top: S.sm),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Pressable(
                              onTap: () => _addPlan(null),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add, size: 20, color: c.accent),
                                  const SizedBox(width: S.xxs),
                                  Text(tr('新建服药计划'),
                                      style: TextStyle(
                                          fontSize: S.textSm,
                                          fontWeight: FontWeight.bold,
                                          color: c.accent)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _weekday(DateTime d) {
    final wk = [tr('周一'), tr('周二'), tr('周三'), tr('周四'), tr('周五'), tr('周六'), tr('周日')];
    return wk[d.weekday - 1];
  }

  Future<void> _addPlan([String? initialTime]) async {
    final r = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ThemeTokens.of(context).paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(S.lg)),
      ),
      builder: (_) => _MedPlanSheet(initialTime: initialTime),
    );
    if (r == null) return;
    // 保存计划前先绑定闹钟/日程权限（缺哪个申请哪个，已授权自动跳过）。
    await Native.ensureReminderPerms();
    final plan = Item(
      kind: Item.kindMed,
      title: r['name'] as String,
      note: StartStore.encodeMedPlan(
        times: (r['times'] as List).cast<String>(),
        cat: r['cat'] as String? ?? '',
        dose: r['dose'] as String? ?? '',
        start: r['start'] as int? ?? 0,
        end: r['end'] as int? ?? 0,
      ),
    );
    await StartStore.I.put(plan);
    await StartStore.I.armMedPlanNotify(plan);
    await _bindSystemAlarms(plan);
  }

  /// 绑定系统闹钟（与日程保存时自动设系统闹钟一致）：常驻每天的计划，
  /// 每个时间点设一个每日重复闹钟；按日期范围的计划不设（防范围外天天响）。
  /// 编辑时先按旧标签撤掉再重设；标签记入 alarm_title_{id} 供删除时清理——
  /// 仅当确实设过系统闹钟才记录，否则删除时的撤销闹钟 intent 找不到匹配，
  /// 部分系统时钟会因此跳出应用。
  Future<void> _bindSystemAlarms(Item plan, {String? oldLabel}) async {
    final meta = StartStore.medPlanMeta(plan);
    final times = (meta['times'] as List?)?.cast<String>() ?? const [];
    final start = (meta['start'] as int?) ?? 0;
    final end = (meta['end'] as int?) ?? 0;
    final label = '${plan.title} · ${(meta['dose'] as String?) ?? ''}'.trim();
    if (oldLabel != null && oldLabel.isNotEmpty) {
      await Native.dismissAlarm(oldLabel);
    }
    if (times.isEmpty || start != 0 || end != 0) {
      // 未设系统闹钟：清空标签，删除计划时不再发撤销 intent。
      await StartStore.I.setPref('alarm_title_${plan.id}', '');
      return;
    }
    await StartStore.I.setPref('alarm_title_${plan.id}', label);
    final now = DateTime.now();
    for (final t in times) {
      final parts = t.split(':');
      final h = int.tryParse(parts[0]) ?? 8;
      final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
      final ms = DateTime(now.year, now.month, now.day, h, m)
          .millisecondsSinceEpoch;
      await Native.setAlarm(label, ms, daily: true);
    }
  }

  Future<void> _editPlan(Item plan) async {
    final meta = StartStore.medPlanMeta(plan);
    final oldLabel = '${plan.title} · ${(meta['dose'] as String?) ?? ''}'.trim();
    final r = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ThemeTokens.of(context).paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(S.lg)),
      ),
      builder: (_) => _MedPlanSheet(plan: plan, meta: meta),
    );
    if (r == null) return;
    await Native.ensureReminderPerms();
    final updated = plan.copy()
      ..title = r['name'] as String
      ..note = StartStore.encodeMedPlan(
        times: (r['times'] as List).cast<String>(),
        cat: r['cat'] as String? ?? '',
        dose: r['dose'] as String? ?? '',
        start: r['start'] as int? ?? 0,
        end: r['end'] as int? ?? 0,
      );
    await StartStore.I.put(updated);
    await StartStore.I.armMedPlanNotify(updated);
    await _bindSystemAlarms(updated, oldLabel: oldLabel);
  }
}

class _CatChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CatChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: S.sm, vertical: S.xxs),
        decoration: BoxDecoration(
          color: selected ? c.accentSoft : c.cardAlt,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: S.textSm,
                color: selected ? c.accent : c.inkSoft,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }
}

/// 服药日历：月历格子 + 每日状态点（绿=全服/橙=部分/红=漏服/灰=未来）。
class _MedCalendar extends StatelessWidget {
  final DateTime month;
  final int Function(DateTime) statusOf;
  final ValueChanged<DateTime> onMonthChange;
  final ValueChanged<DateTime> onPickDay;

  const _MedCalendar({
    required this.month,
    required this.statusOf,
    required this.onMonthChange,
    required this.onPickDay,
  });

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = first.weekday - 1; // 周一开头
    final wk = [tr('周一'), tr('周二'), tr('周三'), tr('周四'), tr('周五'), tr('周六'), tr('周日')];

    return ListView(
      padding: const EdgeInsets.fromLTRB(S.lg, S.sm, S.lg, S.lg),
      children: [
        // 月份翻页
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconBtn(Icons.chevron_left, tip: tr('前一天'), onTap: () {
              onMonthChange(DateTime(month.year, month.month - 1));
            }),
            const SizedBox(width: S.sm),
            Text(
              tr('{0}年{1}月', [month.year, month.month]),
              style: TextStyle(
                  fontSize: S.textMd,
                  fontWeight: FontWeight.bold,
                  color: c.ink,
                  fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            const SizedBox(width: S.sm),
            IconBtn(Icons.chevron_right, tip: tr('后一天'), onTap: () {
              onMonthChange(DateTime(month.year, month.month + 1));
            }),
          ],
        ),
        const SizedBox(height: S.sm),
        // 星期表头
        Row(
          children: [
            for (final w in wk)
              Expanded(
                child: Center(
                  child: Text(w,
                      style: TextStyle(fontSize: 11, color: c.inkSoft)),
                ),
              ),
          ],
        ),
        const SizedBox(height: S.xs),
        // 日期格子
        for (var row = 0; row * 7 - leading < daysInMonth; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: _dayCell(
                    c,
                    row * 7 + col - leading + 1,
                    daysInMonth,
                    today,
                  ),
                ),
            ],
          ),
        const SizedBox(height: S.md),
        // 图例
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legend(c, c.accent, tr('已服')),
            const SizedBox(width: S.md),
            _legend(c, Colors.orange, tr('部分')),
            const SizedBox(width: S.md),
            _legend(c, Colors.red, tr('漏服')),
          ],
        ),
      ],
    );
  }

  Widget _legend(C c, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: S.xxs),
        Text(label, style: TextStyle(fontSize: 11, color: c.inkSoft)),
      ],
    );
  }

  Widget _dayCell(C c, int dayNum, int daysInMonth, DateTime today) {
    if (dayNum < 1 || dayNum > daysInMonth) {
      return const SizedBox(height: 44);
    }
    final d = DateTime(month.year, month.month, dayNum);
    final status = statusOf(d);
    final isToday = d == today;
    final dotColor = switch (status) {
      3 => c.accent,
      2 => Colors.orange,
      1 => Colors.red,
      4 => c.line,
      _ => Colors.transparent,
    };
    return Pressable(
      onTap: () => onPickDay(d),
      child: SizedBox(
        height: 44,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isToday ? c.accentSoft : Colors.transparent,
              ),
              child: Text(
                '$dayNum',
                style: TextStyle(
                    fontSize: S.textSm,
                    fontWeight:
                        isToday ? FontWeight.bold : FontWeight.normal,
                    color: isToday ? c.accent : c.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    height: 1.0),
              ),
            ),
            const SizedBox(height: 2),
            Container(
              width: 6,
              height: 6,
              decoration:
                  BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个时间点分组：时间标题 + 该时刻要吃的药。
class _TimeSection extends StatelessWidget {
  final String time;
  final List<Item> plans;
  final bool Function(Item, String) isDone;
  final Future<void> Function(Item, String) onLog;
  final Future<void> Function(Item) onEdit;
  final VoidCallback onAdd;

  const _TimeSection({
    required this.time,
    required this.plans,
    required this.isDone,
    required this.onLog,
    required this.onEdit,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: S.md, bottom: S.xs),
          child: Row(
            children: [
              Text(time,
                  style: TextStyle(
                      fontSize: S.textMd,
                      fontWeight: FontWeight.bold,
                      color: c.accent,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              const Spacer(),
              // 分组标题加号：与首页日程/随手做同款，新建时预选本时间点。
              Pressable(
                onTap: onAdd,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: S.xs, vertical: S.xxs),
                  child: Icon(Icons.add, size: 20, color: c.accent),
                ),
              ),
            ],
          ),
        ),
        for (final p in plans)
          _PlanLine(
            plan: p,
            time: time,
            done: isDone(p, time),
            onLog: () => onLog(p, time),
            onEdit: () => onEdit(p),
          ),
      ],
    );
  }
}

class _PlanLine extends StatelessWidget {
  final Item plan;
  final String time;
  final bool done;
  final VoidCallback onLog;
  final VoidCallback onEdit;

  const _PlanLine({
    required this.plan,
    required this.time,
    required this.done,
    required this.onLog,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final meta = StartStore.medPlanMeta(plan);
    final dose = (meta['dose'] as String?) ?? '';
    final cat = (meta['cat'] as String?) ?? '';
    // 重复方式：常驻每天 or 日期范围（让两类计划在清单上一眼分清）。
    final start = (meta['start'] as int?) ?? 0;
    final end = (meta['end'] as int?) ?? 0;
    final String repeat;
    if (start == 0 && end == 0) {
      repeat = tr('每天');
    } else {
      final s = DateTime.fromMillisecondsSinceEpoch(start);
      final e = DateTime.fromMillisecondsSinceEpoch(end);
      repeat = '${s.month}/${s.day}–${e.month}/${e.day}';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: S.xs),
      // 接入全局拖拽删除：长按拖起 → 底部红区垃圾桶 → 6 秒可撤销。
      // 点卡片编辑、拖到红区删除，与首页行交互一致，不再放编辑/删除小按钮。
      child: DraggableLine(
        key: ValueKey('${plan.id}_$time'),
        id: plan.id,
        title: plan.title,
        child: Pressable(
          onTap: onEdit,
          child: StartCard(
            padding:
                const EdgeInsets.symmetric(horizontal: S.md, vertical: S.sm),
            child: Row(
              children: [
                // 打勾区
                Pressable(
                  onTap: done ? null : onLog,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done ? c.accent : Colors.transparent,
                      border: Border.all(
                          color: done ? c.accent : c.line, width: 1.5),
                    ),
                    child: done
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : null,
                  ),
                ),
                const SizedBox(width: S.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(plan.title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: S.textMd,
                              fontWeight: FontWeight.bold,
                              color: c.ink,
                              decoration: done
                                  ? TextDecoration.lineThrough
                                  : null)),
                      // 副信息行：剂量 · 分类 · 重复，不堆时间。
                      Text(
                        [if (dose.isNotEmpty) dose,
                          if (cat.isNotEmpty) cat,
                          repeat].join(' · '),
                        style: TextStyle(fontSize: S.textSm, color: c.inkSoft),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 新建/编辑服药计划底部弹层：时间点为动态列表，可增可删，不限早中晚。
class _MedPlanSheet extends StatefulWidget {
  final Item? plan;
  final Map<String, Object?> meta;
  final String? initialTime; // 新建时预选的时间点（从分组标题加号进入时）
  const _MedPlanSheet({this.plan, this.meta = const {}, this.initialTime});

  @override
  State<_MedPlanSheet> createState() => _MedPlanSheetState();
}

class _MedPlanSheetState extends State<_MedPlanSheet> {
  late final TextEditingController _nameCtl;
  late final TextEditingController _doseCtl;
  late final TextEditingController _catCtl;
  late List<String> _times;
  late int _start;
  late int _end;

  bool _daily = true; // 常驻每天 vs 按日期范围

  @override
  void initState() {
    super.initState();
    final m = widget.meta;
    _nameCtl = TextEditingController(text: widget.plan?.title ?? '');
    _doseCtl = TextEditingController(text: (m['dose'] as String?) ?? '');
    _catCtl = TextEditingController(text: (m['cat'] as String?) ?? '');
    _times = List<String>.from(
        (m['times'] as List?)?.cast<String>() ??
            [widget.initialTime ?? '08:00']);
    if (_times.isEmpty) _times = ['08:00'];
    _times.sort();
    _start = (m['start'] as int?) ?? 0;
    _end = (m['end'] as int?) ?? 0;
    // 没有日期范围 = 常驻每天
    _daily = _start == 0 && _end == 0;
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _doseCtl.dispose();
    _catCtl.dispose();
    super.dispose();
  }

  Future<void> _pickTime(int i) async {
    final parts = _times[i].split(':');
    final init = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 8,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
    final t = await showStartTimePicker(context, initial: init);
    if (t == null) return;
    setState(() {
      _times[i] =
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      _times.sort();
    });
  }

  Future<void> _addTime() async {
    final t = await showStartTimePicker(context,
        initial: const TimeOfDay(hour: 8, minute: 0));
    if (t == null) return;
    final s =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    if (_times.contains(s)) return;
    setState(() {
      _times.add(s);
      _times.sort();
    });
  }

  void _submit() {
    final name = _nameCtl.text.trim();
    if (name.isEmpty) return;
    if (_times.isEmpty) _times = ['08:00'];
    Navigator.pop(context, {
      'name': name,
      'times': _times,
      'cat': _catCtl.text.trim(),
      'dose': _doseCtl.text.trim(),
      'start': _daily ? 0 : _start,
      'end': _daily ? 0 : _end,
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final pad = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(S.md, S.md, S.md, pad + S.md),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.plan == null ? tr('新建服药计划') : tr('编辑服药计划'),
                style: TextStyle(
                    fontSize: S.textLg,
                    fontWeight: FontWeight.bold,
                    color: c.ink),
              ),
              const SizedBox(height: S.sm),
              TextField(
                controller: _nameCtl,
                autofocus: true,
                style: TextStyle(fontSize: S.textMd, color: c.ink),
                decoration: InputDecoration(
                  hintText: tr('药品名称'),
                  hintStyle: TextStyle(color: c.inkSoft),
                  border: InputBorder.none,
                ),
              ),
              const SizedBox(height: S.xs),
              TextField(
                controller: _doseCtl,
                style: TextStyle(fontSize: S.textMd, color: c.ink),
                decoration: InputDecoration(
                  hintText: tr('剂量（如 1片 / 0.25g）'),
                  hintStyle: TextStyle(color: c.inkSoft),
                  border: InputBorder.none,
                ),
              ),
              const SizedBox(height: S.xs),
              TextField(
                controller: _catCtl,
                style: TextStyle(fontSize: S.textMd, color: c.ink),
                decoration: InputDecoration(
                  hintText: tr('分类'),
                  hintStyle: TextStyle(color: c.inkSoft),
                  border: InputBorder.none,
                ),
              ),
              const SizedBox(height: S.sm),
              // 自定义时间点列表：点胶囊改时间，× 删除，可任意添加。
              Row(
                children: [
                  Text(tr('服药时间'),
                      style: TextStyle(fontSize: S.textSm, color: c.inkSoft)),
                  const Spacer(),
                  Pressable(
                    onTap: _addTime,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: S.xs, vertical: S.xxs),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, size: 16, color: c.accent),
                          Text(tr('添加时间'),
                              style: TextStyle(
                                  fontSize: S.textSm,
                                  fontWeight: FontWeight.bold,
                                  color: c.accent)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: S.xxs),
              Wrap(
                spacing: S.xs,
                runSpacing: S.xs,
                children: [
                  for (var i = 0; i < _times.length; i++)
                    Container(
                      padding: const EdgeInsets.only(left: S.sm, right: 2),
                      decoration: BoxDecoration(
                        color: c.cardAlt,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Pressable(
                            onTap: () => _pickTime(i),
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: S.xs),
                              child: Text(
                                _times[i],
                                style: TextStyle(
                                    fontSize: S.textMd,
                                    fontWeight: FontWeight.bold,
                                    color: c.accent,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ]),
                              ),
                            ),
                          ),
                          Pressable(
                            onTap: _times.length > 1
                                ? () => setState(() => _times.removeAt(i))
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.all(S.xxs),
                              child: Icon(Icons.close,
                                  size: 16,
                                  color: _times.length > 1
                                      ? c.inkSoft
                                      : c.line),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: S.sm),
              Text(tr('重复'),
                  style: TextStyle(fontSize: S.textSm, color: c.inkSoft)),
              const SizedBox(height: S.xxs),
              // 重复方式：常驻每天 / 按日期范围，独立分组不与时段混淆。
              Wrap(
                spacing: S.xs,
                children: [
                  _slotChip(c, tr('每天都吃'), _daily, () => setState(() => _daily = true)),
                  _slotChip(c, tr('按日期范围'), !_daily, () => setState(() => _daily = false)),
                ],
              ),
              if (!_daily) ...[
                const SizedBox(height: S.sm),
                Row(
                  children: [
                    Expanded(
                      child: Pressable(
                        onTap: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _start > 0
                                ? DateTime.fromMillisecondsSinceEpoch(_start)
                                : DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (d != null) {
                            setState(() => _start = DateTime(d.year, d.month, d.day).millisecondsSinceEpoch);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: S.sm, horizontal: S.sm),
                          decoration: BoxDecoration(
                            color: c.cardAlt,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _start > 0
                                ? tr('{0}月{1}日', [
                                    DateTime.fromMillisecondsSinceEpoch(_start)
                                        .month,
                                    DateTime.fromMillisecondsSinceEpoch(_start)
                                        .day
                                  ])
                                : tr('开始日期'),
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: S.textSm, color: c.ink),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: S.xs),
                    Text('→', style: TextStyle(color: c.inkSoft)),
                    const SizedBox(width: S.xs),
                    Expanded(
                      child: Pressable(
                        onTap: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _end > 0
                                ? DateTime.fromMillisecondsSinceEpoch(_end)
                                : DateTime.now().add(const Duration(days: 7)),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (d != null) {
                            setState(() => _end = DateTime(d.year, d.month, d.day, 23, 59, 59).millisecondsSinceEpoch);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: S.sm, horizontal: S.sm),
                          decoration: BoxDecoration(
                            color: c.cardAlt,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _end > 0
                                ? tr('{0}月{1}日', [
                                    DateTime.fromMillisecondsSinceEpoch(_end)
                                        .month,
                                    DateTime.fromMillisecondsSinceEpoch(_end)
                                        .day
                                  ])
                                : tr('结束日期'),
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: S.textSm, color: c.ink),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: S.sm),
              Row(
                children: [
                  Expanded(
                    child: Pressable(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.cardAlt,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(tr('取消'),
                            style: TextStyle(
                                fontSize: S.textMd,
                                fontWeight: FontWeight.bold,
                                color: c.ink)),
                      ),
                    ),
                  ),
                  const SizedBox(width: S.sm),
                  Expanded(
                    child: Pressable(
                      onTap: _submit,
                      child: Container(
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.accent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(tr('保存'),
                            style: TextStyle(
                                fontSize: S.textMd,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
