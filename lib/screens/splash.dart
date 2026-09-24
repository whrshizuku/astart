import 'dart:math' show pi;

import 'package:flutter/material.dart';

import '../channels/native.dart';
import '../data/store.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

/// 开机动画页：图标淡入上浮 + 番茄红圆环描边转满 + 底部小字，末尾安静停顿。
/// 默认 2.6 秒后回调进入主界面（协议门 / 首页）。纯图标，无按钮无干扰。
class SplashScreen extends StatefulWidget {
  final VoidCallback onDone;
  const SplashScreen({super.key, required this.onDone});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final int _ms;
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ms = StartStore.I.prefInt('dev_splash_ms', 2600).clamp(1400, 6000);
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _ms),
    )..forward();
    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
    // 圆环开始描边后轻轻响起开机铃声（开关在设置/开发者选项里）。
    Future.delayed(Duration(milliseconds: (_ms * 0.22).round()),
        Native.bootSound);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    // 0–0.42：圆环描边转满；0.15–0.55：图标淡入上浮；0.5–0.78：小字淡入；末尾停顿。
    final ring = CurvedAnimation(
        parent: _ctrl, curve: const Interval(0, 0.42, curve: Curves.easeOut));
    final logo = CurvedAnimation(
        parent: _ctrl, curve: const Interval(0.15, 0.55, curve: Curves.easeOut));
    final word = CurvedAnimation(
        parent: _ctrl, curve: const Interval(0.5, 0.78, curve: Curves.easeIn));

    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 108,
                height: 108,
                child: AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, __) => CustomPaint(
                    painter: _RingPainter(ring.value, c.accent),
                    child: Center(
                      child: FadeTransition(
                        opacity: logo,
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(0, 0.12),
                            end: Offset.zero,
                          ).animate(logo),
                          child: Image.asset('assets/app_icon.png',
                              width: 58, height: 58, fit: BoxFit.contain),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: S.lg),
              FadeTransition(
                opacity: word,
                child: Text('Start',
                    style: TextStyle(
                        fontSize: S.textMd,
                        letterSpacing: 4,
                        color: c.inkSoft,
                        fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 番茄红细圆环：从顶部起顺时针描边到满圈。
class _RingPainter extends CustomPainter {
  final double t; // 0–1
  final Color color;
  _RingPainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final rect = Offset.zero & size;
    // 起点在正上方（-90°），扫过角度随动画增长。
    const start = -pi / 2;
    final sweep = 2 * pi * t;
    canvas.drawArc(rect.deflate(1.25), start, sweep, false, paint);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.t != t || old.color != color;
}
