import 'package:flutter/material.dart';

import '../data/store.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

/// 统计：按日期维度查看——左右滑动切换日期，从首次使用到今天，一天一页。
/// 每页四个数字（专注分钟 / 专注次数 / 完成的事 / 新增条目）+ 当日整点专注分布。
/// 数字等宽对齐，无卡片底，与全局风格一致。
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  PageController? _ctl;
  DateTime? _firstDay;
  int _days = 0;
  int _index = 0;

  static const _wk = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final first = await StartStore.I.firstUseDate();
    if (!mounted) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(first).inDays + 1;
    setState(() {
      _firstDay = first;
      _days = days;
      _index = days - 1;
      _ctl = PageController(initialPage: days - 1);
    });
  }

  @override
  void dispose() {
    _ctl?.dispose();
    super.dispose();
  }

  DateTime _dayOf(int i) => _firstDay!.add(Duration(days: i));

  void _go(int i) {
    _ctl?.animateToPage(i,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    if (_ctl == null) {
      return const SafeArea(
        child: Center(
          child:
              SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    return SafeArea(
      child: ListenableBuilder(
        listenable: StartStore.I,
        builder: (context, _) => _build(c),
      ),
    );
  }

  Widget _build(C c) {
    final idx = _index;
    final day = _dayOf(idx);
    final isToday = idx == _days - 1;
    final rel = isToday ? '今天' : (idx == _days - 2 ? '昨天' : null);
    return Column(
      children: [
        // 日期翻页器：箭头与日期组收拢居中，是一个完整控件而非三摊散件。
        Padding(
          padding: const EdgeInsets.fromLTRB(S.md, S.sm, S.md, S.xs),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  IconBtn(
                    Icons.chevron_left,
                    tip: '前一天',
                    color: idx > 0 ? c.inkSoft : c.line,
                    onTap: idx > 0 ? () => _go(idx - 1) : null,
                  ),
                  const SizedBox(width: S.sm),
                  // 主标题与胶囊基线对齐，避免视觉错位。
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '${day.month}月${day.day}日',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          color: c.ink,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          height: 1.0,
                        ),
                      ),
                      if (rel != null) ...[
                        const SizedBox(width: S.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: S.xs, vertical: 2),
                          decoration: BoxDecoration(
                            color: c.accentSoft,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(rel,
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
                  IconBtn(
                    Icons.chevron_right,
                    tip: '后一天',
                    color: !isToday ? c.inkSoft : c.line,
                    onTap: !isToday ? () => _go(idx + 1) : null,
                  ),
                ],
              ),
              const SizedBox(height: S.xxs),
              Text(
                '${_wk[day.weekday - 1]} · 第 ${idx + 1} 天',
                style: TextStyle(
                    fontSize: S.textSm,
                    color: c.inkSoft,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    height: 1.2),
              ),
            ],
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: _ctl,
            itemCount: _days,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => _DayPage(day: _dayOf(i)),
          ),
        ),
      ],
    );
  }
}

/// 单日统计页。
class _DayPage extends StatelessWidget {
  final DateTime day;
  const _DayPage({required this.day});

  static int _epochOf(DateTime d) =>
      DateTime(d.year, d.month, d.day).difference(DateTime(1970, 1, 1)).inDays;

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final s = StartStore.I;
    final epoch = _epochOf(day);
    final focus = s.focusMinutesOn(epoch);
    final sessions = s.focusCountOn(epoch);
    final done = s.completedOn(epoch);
    final added = s.createdOn(epoch);
    final hours = s.focusHoursOn(epoch);
    final quiet = focus == 0 && done == 0 && added == 0;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
      child: ListView(
      key: ValueKey(epoch),
      padding: const EdgeInsets.fromLTRB(S.lg, S.sm, S.lg, S.xl + 16),
      children: [
        Row(children: [
          Expanded(child: _Stat(c, big: '$focus', label: '专注分钟')),
          Expanded(child: _Stat(c, big: '$sessions', label: '专注次数')),
        ]),
        const SizedBox(height: S.lg),
        Row(children: [
          Expanded(child: _Stat(c, big: '$done', label: '完成的事')),
          Expanded(child: _Stat(c, big: '$added', label: '新增条目')),
        ]),
        const SizedBox(height: S.xl),
        Text('整点专注分布',
            style: TextStyle(
                fontSize: S.textMd, fontWeight: FontWeight.bold, color: c.ink)),
        const SizedBox(height: S.md),
        SizedBox(
          height: 96,
          width: double.infinity,
          child: CustomPaint(
              painter: _HoursPainter(data: hours, accent: c.accent, soft: c.cardAlt)),
        ),
        const SizedBox(height: S.xxs),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: ['0', '6', '12', '18', '24']
              .map((t) => Text(t,
                  style: TextStyle(fontSize: S.textSm, color: c.inkSoft)))
              .toList(),
        ),
        if (quiet)
          Padding(
            padding: const EdgeInsets.only(top: S.xl),
            child: Center(
              child: Text('这一天安安静静，没有记录',
                  style: TextStyle(fontSize: S.textSm, color: c.inkSoft)),
            ),
          ),
      ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final C c;
  final String big;
  final String label;
  const _Stat(this.c, {required this.big, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          big,
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.bold,
            color: c.ink,
            fontFeatures: const [FontFeature.tabularFigures()],
            height: 1.1,
          ),
        ),
        const SizedBox(height: S.xxs),
        Text(label,
            style: TextStyle(
                fontSize: S.textSm,
                color: c.inkSoft,
                height: 1.2)),
      ],
    );
  }
}

/// 整点专注分布：24 格柱，当天有专注的整点以番茄红标出。
class _HoursPainter extends CustomPainter {
  final List<int> data;
  final Color accent;
  final Color soft;
  _HoursPainter({required this.data, required this.accent, required this.soft});

  @override
  void paint(Canvas canvas, Size size) {
    final max = data.fold<int>(0, (m, v) => v > m ? v : m);
    final slot = size.width / 24;
    final barW = slot * 0.55;
    for (var i = 0; i < 24; i++) {
      final v = data[i];
      final frac = max == 0 ? 0.0 : v / max;
      final h = v <= 0 ? 3.0 : (size.height * frac).clamp(6.0, size.height);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(i * slot + (slot - barW) / 2, size.height - h, barW, h),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, Paint()..color = v > 0 ? accent : soft);
    }
  }

  @override
  bool shouldRepaint(_HoursPainter old) =>
      old.data != data || old.accent != accent || old.soft != soft;
}
