import 'package:flutter/material.dart';

import '../data/store.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

/// 统计：今日专注、连续天数、完成数、累计、近 7 天柱状图。
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: StartStore.I,
        builder: (context, _) => _build(context),
      );

  Widget _build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final s = StartStore.I;
    final last7 = s.focusMinutesLast7();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(S.md),
        children: [
          Text('统计',
              style: TextStyle(fontSize: S.textXl, fontWeight: FontWeight.bold, color: c.ink)),
          const SizedBox(height: S.md),
          Row(
            children: [
              Expanded(
                child: _StatCard(c, big: '${s.todayFocusMinutes()}', label: '今日专注分钟'),
              ),
              const SizedBox(width: S.xs),
              Expanded(
                child: _StatCard(c, big: '${s.activeDaysLast7()}', label: '近 7 天专注日'),
              ),
            ],
          ),
          const SizedBox(height: S.xs),
          Row(
            children: [
              Expanded(
                child: _StatCard(c, big: '${s.completedTasksCount()}', label: '完成的事'),
              ),
              const SizedBox(width: S.xs),
              Expanded(
                child: _StatCard(c, big: '${s.totalFocusMinutes()}', label: '累计专注分钟'),
              ),
            ],
          ),
          const SizedBox(height: S.md),
          StartCard(
            padding: const EdgeInsets.all(S.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('近 7 天',
                    style: TextStyle(
                        fontSize: S.textSm, color: c.inkSoft, fontWeight: FontWeight.bold)),
                const SizedBox(height: S.md),
                SizedBox(
                  height: 120,
                  child: CustomPaint(
                    size: const Size(double.infinity, 120),
                    painter: _BarsPainter(data: last7, accent: c.accent, soft: c.cardAlt, ink: c.inkSoft),
                    child: const SizedBox.expand(),
                  ),
                ),
                const SizedBox(height: S.xs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var i = 0; i < 7; i++)
                      Text('${i == 6 ? '今天' : '-${6 - i}'}',
                          style: TextStyle(fontSize: S.textSm, color: c.inkSoft)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final C c;
  final String big;
  final String label;
  const _StatCard(this.c, {required this.big, required this.label});

  @override
  Widget build(BuildContext context) {
    return StartCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(big,
              style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: c.ink,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(height: S.xxs),
          Text(label, style: TextStyle(fontSize: S.textSm, color: c.inkSoft)),
        ],
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  final List<int> data;
  final Color accent;
  final Color soft;
  final Color ink;

  _BarsPainter({required this.data, required this.accent, required this.soft, required this.ink});

  @override
  void paint(Canvas canvas, Size size) {
    final max = data.fold<int>(1, (a, b) => b > a ? b : a);
    final w = size.width / data.length;
    for (var i = 0; i < data.length; i++) {
      final h = data[i] <= 0 ? 4.0 : (data[i] / max) * (size.height - 8);
      final isToday = i == data.length - 1;
      final r = RRect.fromRectAndCorners(
        Rect.fromLTWH(i * w + w * 0.22, size.height - h, w * 0.56, h),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      canvas.drawRRect(r, Paint()..color = isToday || data[i] > 0 ? accent : soft);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.data != data;
}
