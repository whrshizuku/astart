import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/item.dart';
import 'data/store.dart';
import 'channels/native.dart';
import 'screens/dump.dart';
import 'screens/focus.dart';
import 'screens/home.dart';
import 'screens/manual.dart';
import 'screens/med.dart';
import 'screens/segment_screen.dart';
import 'screens/splash.dart';
import 'screens/stats.dart';
import 'screens/steps.dart';
import 'theme/tokens.dart';
import 'utils/update_checker.dart';
import 'widgets/ui.dart';
import 'l10n/i18n.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 全面屏：内容延伸到状态栏/手势条后面，系统栏全透明，界面用 SafeArea 让位。
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  ));
  await StartStore.I.init();
  Lang.current = Lang.resolve();
  runApp(const StartApp());
  // 冷启动重挂全部闹钟：滑掉卡片/强停会清空 AlarmManager，不重挂就永远不响。
  // 放 runApp 之后异步执行，不阻塞首屏。
  StartStore.I.rearmAll();
}

class StartApp extends StatefulWidget {
  const StartApp({super.key});

  static final navigatorKey = GlobalKey<NavigatorState>();
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  State<StartApp> createState() => _StartAppState();
}

class _StartAppState extends State<StartApp> {
  @override
  void initState() {
    super.initState();
    // 启动后静默检查更新，有新版自动提醒。
    Future.delayed(const Duration(seconds: 2), _autoUpdateCheck);
  }

  Future<void> _autoUpdateCheck() async {
    final u = await UpdateChecker.check();
    if (u == null || !mounted) return;
    final ctx = StartApp.navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final c = ThemeTokens.of(ctx);
    // 统一对话框风格（showStartDialog）：卡片底圆角，按钮用 dctx 关闭。
    await showStartDialog<void>(
      ctx,
      title: tr('发现新版本 v{0}', [u.version]),
      content: Text(tr('去仓库下载最新安装包'),
          style: TextStyle(color: c.inkSoft, fontSize: S.textMd)),
      actions: (dctx) => [
        TextButton(
          onPressed: () => Navigator.pop(dctx),
          child: Text(tr('忽略'), style: TextStyle(color: c.inkSoft)),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(dctx);
            Native.openUrl(u.url);
          },
          child: Text(tr('下载'), style: TextStyle(color: c.accent, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: StartStore.I,
      builder: (context, _) {
        final s = StartStore.I;
        // 语言偏好变化（setPref 会 notify）后整树重建，重算生效语言。
        Lang.current = Lang.resolve();
        final darkMode = s.prefInt('dark_mode', 0);
        final themeMode = switch (darkMode) {
          1 => ThemeMode.dark,
          2 => ThemeMode.light,
          _ => ThemeMode.system,
        };
        final scale = s.prefDouble('font_scale', 1.0);
        final platformDark =
            WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
        final isDark =
            themeMode == ThemeMode.dark || (themeMode == ThemeMode.system && platformDark);
        final c = isDark ? C.dark : C.light;

        return ThemeTokens(
          c: c,
          child: MaterialApp(
            title: Lang.appNameOf(Lang.current),
            debugShowCheckedModeBanner: false,
            navigatorKey: StartApp.navigatorKey,
            scaffoldMessengerKey: StartApp.messengerKey,
            theme: AppThemes.build(C.light, Brightness.light),
            darkTheme: AppThemes.build(C.dark, Brightness.dark),
            themeMode: themeMode,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
              // 全面屏：状态栏/手势条图标色随明暗主题。
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle(
                  statusBarColor: Colors.transparent,
                  statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
                  systemNavigationBarColor: Colors.transparent,
                  systemNavigationBarIconBrightness:
                      isDark ? Brightness.light : Brightness.dark,
                  systemNavigationBarDividerColor: Colors.transparent,
                  systemNavigationBarContrastEnforced: false,
                ),
                // 全局撤销条 + 拖拽落点底座：挂在 navigator 之上，任何页面都能用。
                // 层级（自下而上）：
                //   1) DragDock 红区：固定贴物理屏底，不随内容上移；
                //   2) navigator：拖拽激活时整体上移露出红区，长按浮影（rootOverlay）
                //      随页面在这一层，拖到桶上时整卡仍在红区之上可见；
                //   3) UndoHost 撤销条：拖拽中自动隐藏。
                child: ValueListenableBuilder<bool>(
                  valueListenable: DragDockBus.active,
                  child: child,
                  builder: (_, dragging, nav) {
                    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
                    // 红区高 72 + 手势条安全区，再留 24dp 间隙；页面（含底栏、
                    // 捋一捋输入条）整体上移这个距离，红区永不遮住输入条。
                    final lift = 72 + S.lg + bottomInset;
                    // 纸色铺底：界面上移后露出的区域不是黑边。
                    return ColoredBox(
                      color: c.paper,
                      child: Stack(
                        children: [
                          // 红区在最下层：仅在上移腾空的底部区域露出。
                          DragDock(onTrash: GlobalDragDock.handleTrash),
                          AnimatedPadding(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            padding: EdgeInsets.only(bottom: dragging ? lift : 0),
                            child: nav!,
                          ),
                          const UndoHost(),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            home: const BootGate(),
            onGenerateRoute: (settings) {
              switch (settings.name) {
                case '/steps':
                  return MaterialPageRoute(
                    builder: (_) => StepsScreen(taskId: settings.arguments as int),
                  );
                case '/focus':
                  final arg = settings.arguments;
                  return MaterialPageRoute(
                    builder: (_) => FocusScreen(taskId: arg is int ? arg : null),
                  );
              }
              return null;
            },
          ),
        );
      },
    );
  }
}

/// 全局拖拽落点的删除处理：红区 [DragDock] 作为静态层挂在 MaterialApp.builder
/// 的 Stack 最底层（固定贴屏底，不随页面上移），拖入后调用本处理器。
class GlobalDragDock {
  GlobalDragDock._();

  /// 等拖拽彻底结束（红区完全收起）后再弹撤销条，避免与红区同屏两条并存。
  static void _showUndoWhenIdle(String text, Future<void> Function() onUndo) {
    void tryShow() {
      if (DragDockBus.active.value) return;
      DragDockBus.active.removeListener(tryShow);
      final ctx = StartApp.navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        UndoHost.show(ctx, text, () async => onUndo());
      }
    }

    if (!DragDockBus.active.value) {
      tryShow();
    } else {
      DragDockBus.active.addListener(tryShow);
    }
  }

  static Future<void> handleTrash(int id) async {
    if (id <= 0) return;
    final s = StartStore.I;
    // 多选整批拖入：只有 d.data 确实在 pendingIds 里才整组删（防 pendingIds 残留脏数据）。
    final pending = DragDockBus.pendingIds;
    DragDockBus.pendingIds = null;
    if (pending != null && pending.length > 1 && pending.contains(id)) {
      final snap = await s.deleteAll(pending);
      _showUndoWhenIdle(tr('删了 {0} 条', [pending.length]),
          () async => s.restoreJson(snap));
      return;
    }
    if (s.byId(id) == null) return;
    final removed = s.delete(id, cascade: true);
    _showUndoWhenIdle(tr('已删除'), () async => s.restore(removed));
  }
}

/// 启动门：先播放开机动画，结束后进协议门与主界面。
class BootGate extends StatefulWidget {
  const BootGate({super.key});

  @override
  State<BootGate> createState() => _BootGateState();
}

class _BootGateState extends State<BootGate> {
  bool _splash = true;

  @override
  Widget build(BuildContext context) {
    return _splash
        ? SplashScreen(onDone: () => setState(() => _splash = false))
        : const EulaGate(child: Root());
  }
}

/// 首次启动/协议更新时先同意再进主界面。
class EulaGate extends StatefulWidget {
  final Widget child;
  const EulaGate({super.key, required this.child});

  @override
  State<EulaGate> createState() => _EulaGateState();
}

class _EulaGateState extends State<EulaGate> {
  bool? _ok;

  @override
  void initState() {
    super.initState();
    _ok = StartStore.I.prefInt('eula_accepted_version', 0) >= StartStore.eulaVersion;
  }

  @override
  Widget build(BuildContext context) {
    if (_ok == true) return widget.child;
    return FirstRunScreen(onAccept: () async {
      await StartStore.I.setPref('eula_accepted_version', StartStore.eulaVersion);
      setState(() => _ok = true);
    });
  }
}

class Root extends StatefulWidget {
  const Root({super.key});

  @override
  State<Root> createState() => _RootState();
}

/// 主骨架：首页是主体（老版 TodayScreen），底栏 5 键切换 section。
/// 底栏：服药 · 捋一捋 · 动手吧 · 专注 · 统计。搜索在首页顶栏设置左侧。
/// body 内嵌一个 Navigator：首页是其根路由，section 页推到该嵌套 navigator
/// （只占 body 区，Scaffold.bottomNavigationBar 始终常驻——老版 selectNav 行为）。
/// 点键后该键保持番茄红，持续到另一个键被点击。切换 section 用 pushReplacement 防栈堆积。
class _RootState extends State<Root> {
  /// 最后按下的底栏键索引：0服药 1捋一捋 2功能键 3专注 4统计。-1=未按过（在首页）。
  int _last = -1;
  final GlobalKey _funcKey = GlobalKey();
  final GlobalKey<NavigatorState> _bodyNav = GlobalKey<NavigatorState>();
  late final NavigatorObserver _navObserver = _HomeObserver(() {
    if (mounted) setState(() => _last = -1);
  });

  /// 跳转 section：在首页则 push，已在某 section 则 pushReplacement 换页。
  /// 用快速淡入替代默认上滑动画，避免切换时白屏卡顿。
  void _goto(Widget page, int idx) {
    setState(() => _last = idx);
    final nav = _bodyNav.currentState;
    if (nav == null) return;
    final route = PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 150),
      reverseTransitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: child,
      ),
    );
    if (nav.canPop()) {
      nav.pushReplacement(route);
    } else {
      nav.push(route);
    }
  }

  /// 短按功能键 = 动手吧(速记倒进来)文字输入。
  void _openDumpText() => _goto(const DumpScreen(), 2);

  /// 语音速记功能暂时移除，后续版本再上线。AI 接口保留在开发者模式中测试。

  void _openMed() => _goto(const MedScreen(), 0);
  void _openSegment() => _goto(const SegmentScreen(), 1);
  void _openFocus() => _goto(const FocusScreen(showBack: true), 3);
  void _openStats() => _goto(const StatsScreen(), 4);

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Scaffold(
      body: WillPopScope(
        onWillPop: () async {
          final nav = _bodyNav.currentState;
          if (nav != null && nav.canPop()) {
            setState(() => _last = -1);
            nav.pop();
            return false;
          }
          return true;
        },
        child: Stack(
          children: [
            Navigator(
              key: _bodyNav,
              observers: [_navObserver],
              onGenerateRoute: (_) => MaterialPageRoute(
                builder: (_) => const HomeScreen(),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navKey(c, Icons.medication_outlined, _last == 0, _openMed),
              _navKey(c, Icons.alt_route, _last == 1, _openSegment),
              _funcButton,
              _navKey(c, Icons.timer_outlined, _last == 3, _openFocus),
              _navKey(c, Icons.bar_chart_outlined, _last == 4, _openStats),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navKey(C c, IconData icon, bool selected, VoidCallback onTap) {
    return Pressable(
      scale: 0.9,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.sm, vertical: S.sm),
        child: Icon(icon, size: 24, color: selected ? c.accent : c.inkSoft),
      ),
    );
  }

  /// 中央红钮 = 动手吧。短按=文字输入，长按=语音速记。全局无字，纯图标。
  Widget get _funcButton {
    final c = ThemeTokens.of(context);
    return GestureDetector(
      key: _funcKey,
      behavior: HitTestBehavior.opaque,
      onTap: _openDumpText,
      // 长按语音速记暂时移除，后续版本再上线
      onLongPress: _openDumpText,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c.accent,
          border: Border.all(color: c.card, width: 2),
          boxShadow: [
            BoxShadow(color: c.accent.withValues(alpha: 0.4), blurRadius: 10, spreadRadius: 1),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Image.asset('assets/app_icon.png', fit: BoxFit.contain),
        ),
      ),
    );
  }
}

/// 监听嵌套 navigator：pop 回到首页根路由时重置底栏高亮（_last=-1）。
class _HomeObserver extends NavigatorObserver {
  _HomeObserver(this.onHome);
  final VoidCallback onHome;

  @override
  void didPop(Route<dynamic>? route, Route<dynamic>? previousRoute) {
    if (previousRoute?.isFirst ?? false) onHome();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // pushReplacement 后栈底仍是首页，无需处理。
  }
}