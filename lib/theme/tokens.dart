import 'package:flutter/material.dart';

/// 颜色令牌：浅色/夜间两套，照抄老版 colors.xml。
class C {
  final Color paper, card, cardAlt, ink, inkSoft, line, ringWell;
  final Color accent, accentDark, accentLight, accentSoft, accentRipple, done;
  const C({
    required this.paper,
    required this.card,
    required this.cardAlt,
    required this.ink,
    required this.inkSoft,
    required this.line,
    required this.ringWell,
    required this.accent,
    required this.accentDark,
    required this.accentLight,
    required this.accentSoft,
    required this.accentRipple,
    required this.done,
  });

  static const light = C(
    paper: Color(0xFFF5EFE3),
    card: Color(0xFFFFFDF7),
    cardAlt: Color(0xFFEFE7D6),
    ink: Color(0xFF2E2820),
    inkSoft: Color(0xFF8C8270),
    line: Color(0xFFE3D8C2),
    ringWell: Color(0xFFF4EDE1),
    accent: Color(0xFFFF6347),
    accentDark: Color(0xFFE04E36),
    accentLight: Color(0xFFFF7F63),
    accentSoft: Color(0xFFFFE3DE),
    accentRipple: Color(0x33FF6347),
    done: Color(0xFFA99F8D),
  );

  static const dark = C(
    paper: Color(0xFF191714),
    card: Color(0xFF23201B),
    cardAlt: Color(0xFF2B2721),
    ink: Color(0xFFEFE9DC),
    inkSoft: Color(0xFF968C79),
    line: Color(0xFF35302A),
    ringWell: Color(0xFF2B2721),
    accent: Color(0xFFEF7A5C),
    accentDark: Color(0xFFE2563A),
    accentLight: Color(0xFFF29478),
    accentSoft: Color(0xFF3A2620),
    accentRipple: Color(0x33EF7A5C),
    done: Color(0xFF6E665A),
  );
}

/// 间距与字号令牌（老版 StartTheme：4/8/12/16/24/32 dp，13/15/17 sp）。
class S {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const radius = 16.0;
  static const textSm = 13.0;
  static const textMd = 15.0;
  static const textLg = 17.0;
  static const textXl = 22.0;
}

/// 由 prefs 构建亮/暗两套 ThemeData 与字体缩放。
class AppThemes {
  static ThemeData build(C c, Brightness brightness) {
    final base = ThemeData(brightness: brightness, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: c.paper,
      colorScheme: base.colorScheme.copyWith(
        primary: c.accent,
        onPrimary: Colors.white,
        secondary: c.accent,
        surface: c.card,
        onSurface: c.ink,
        error: c.accentDark,
      ),
      splashFactory: InkSparkle.splashFactory,
      textTheme: base.textTheme.apply(
        bodyColor: c.ink,
        displayColor: c.ink,
        fontFamily: null,
      ),
      textSelectionTheme: TextSelectionThemeData(cursorColor: c.accent, selectionColor: c.accentRipple),
      dialogTheme: DialogThemeData(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(S.radius)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Colors.transparent),
    );
  }

  static const fontScales = [0.9, 1.0, 1.18];
}
