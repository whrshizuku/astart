import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../channels/native.dart';
import '../data/item.dart';
import '../data/store.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

/// 专注：空心圆环 + 倒计时数字，无多余文本。Ticker 驱动，250ms 平滑刷新。
class FocusScreen extends StatefulWidget {
  final int? taskId;
  final bool showBack;
  const FocusScreen({super.key, this.taskId, this.showBack = true});

  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> {
  static const presets = [2, 25, 45];

  Item? _task;
  int _minutes = 25;
  bool _running = false;
  bool _paused = false;
  int _remainMs = 0;
  Timer? _timer;
  int _tickCount = 0;

  @override
  void initState() {
    super.initState();
    final s = StartStore.I;
    final id = widget.taskId;
    if (id != null) {
      _task = s.byId(id);
    } else {
      _task = s.todayFocus() ?? (s.openTasks().isNotEmpty ? s.openTasks().first : null);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    Native.keepScreenOn(false);
    Native.stopChime();
    super.dispose();
  }

  void _start() {
    setState(() {
      _running = true;
      _paused = false;
      _remainMs = _minutes * 60 * 1000;
    });
    Native.keepScreenOn(true);
    _timer = Timer.periodic(const Duration(milliseconds: 250), _onTick);
  }

  Future<void> _onTick(Timer t) async {
    if (!mounted) return;
    setState(() => _remainMs -= 250);
    final s = StartStore.I;
    // 滴答：每分钟响一下（设置开启时）
    if (++_tickCount % 240 == 0 && s.prefBool('focus_tick', false)) {
      await Native.tick(s.prefInt('sound_volume', 70));
    }
    if (_remainMs <= 0) {
      t.cancel();
      await _finish();
    }
  }

  Future<void> _finish() async {
    final s = StartStore.I;
    _running = false;
    _timer = null;
    Native.keepScreenOn(false);
    await s.addFocusMinutes(_minutes);
    switch (s.prefInt('focus_notify', 0)) {
      case 0:
        await Native.chime();
        break;
      case 1:
        Native.vibrate(400);
        break;
      default:
        break;
    }
    if (mounted) setState(() {});
  }

  void _pause() {
    if (_paused) {
      _timer = Timer.periodic(const Duration(milliseconds: 250), _onTick);
    } else {
      _timer?.cancel();
      _timer = null;
    }
    setState(() => _paused = !_paused);
  }

  Future<void> _giveUp() async {
    _timer?.cancel();
    _timer = null;
    _running = false;
    Native.keepScreenOn(false);
    Native.stopChime();
    // 做满 1 分钟以上也记一部分
    final elapsed = _minutes * 60 * 1000 - _remainMs;
    if (elapsed > 60 * 1000) {
      await StartStore.I.addFocusMinutes(elapsed ~/ (60 * 1000));
    }
    if (mounted) setState(() {});
  }

  String get _timeLabel {
    final sec = (_remainMs / 1000).ceil();
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final s = StartStore.I;

    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: _running ? _buildRunning(c) : _buildSetup(c, s),
      ),
    );
  }

  Widget _buildSetup(C c, StartStore s) {
    return Column(
      children: [
        _TopBar(onBack: widget.showBack ? () => Navigator.pop(context) : null),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _task?.title ?? '只做一件事',
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: S.textLg, fontWeight: FontWeight.bold, color: c.ink),
              ),
              const SizedBox(height: S.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final m in presets)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: S.xs),
                      child: Pressable(
                        onTap: () => setState(() => _minutes = m),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.xs),
                          decoration: BoxDecoration(
                            color: _minutes == m ? c.accent : c.card,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: _minutes == m ? c.accent : c.line),
                          ),
                          child: Text('$m',
                              style: TextStyle(
                                  fontSize: S.textMd,
                                  fontWeight: FontWeight.bold,
                                  color: _minutes == m ? Colors.white : c.ink)),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: S.sm),
              Pressable(
                onTap: () async {
                  final ctl = TextEditingController(text: '$_minutes');
                  final v = await showStartDialog<int>(
                    context,
                    title: '自定义时长（分钟）',
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: Text('算了')),
                      TextButton(
                          onPressed: () => Navigator.pop(context, int.tryParse(ctl.text)),
                          child: Text('好', style: TextStyle(color: c.accent))),
                    ],
                  );
                  if (v != null && v > 0 && v <= 240) setState(() => _minutes = v);
                },
                child: Text('自定义',
                    style: TextStyle(fontSize: S.textSm, color: c.inkSoft)),
              ),
              const SizedBox(height: S.lg),
              Pressable(
                onTap: _start,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.accent,
                  ),
                  child: const Icon(Icons.play_arrow, color: Colors.white, size: 36),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRunning(C c) {
    final total = _minutes * 60 * 1000.0;
    final progress = (1 - _remainMs / total).clamp(0.0, 1.0);
    return Column(
      children: [
        const Spacer(),
        Center(
          child: SizedBox(
            width: 260,
            height: 260,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(260, 260),
                  painter: _RingPainter(
                    progress: progress,
                    track: c.ringWell,
                    accent: c.accent,
                    line: c.line,
                  ),
                ),
                Text(_timeLabel,
                    style: TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.w300,
                        color: c.ink,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            ),
          ),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.only(bottom: S.lg),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconBtn(Icons.close, tip: '不做了', onTap: _giveUp, color: c.inkSoft),
              const SizedBox(width: S.lg),
              Pressable(
                onTap: _pause,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: c.accent),
                  child: Icon(_paused ? Icons.play_arrow : Icons.pause, color: Colors.white),
                ),
              ),
              const SizedBox(width: S.lg),
              IconBtn(Icons.check, tip: '提前完成', onTap: _finish, color: c.inkSoft),
            ],
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback? onBack;
  const _TopBar({this.onBack});

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.md, S.sm, S.md, 0),
      child: Row(
        children: [
          if (onBack != null)
            IconBtn(Icons.arrow_back, onTap: onBack, color: c.ink)
          else
            const SizedBox(width: 40),
          const Spacer(),
          Icon(Icons.timer_outlined, color: c.inkSoft),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color track;
  final Color accent;
  final Color line;

  _RingPainter({required this.progress, required this.track, required this.accent, required this.line});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = 10.0;
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.shortestSide - stroke) / 2 - 8;

    // 凹槽盘
    canvas.drawCircle(center, radius - stroke, Paint()..color = track);
    // 底环
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = line,
    );
    // 进度环
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = accent;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -3.14159 / 2,
        6.283185 * progress, false, p);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.accent != accent;
}
