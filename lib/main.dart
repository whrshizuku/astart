import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ai/assist.dart';
import 'data/item.dart';
import 'data/store.dart';
import 'channels/native.dart';
import 'screens/dump.dart';
import 'screens/focus.dart';
import 'screens/home.dart';
import 'screens/manual.dart';
import 'screens/search.dart';
import 'screens/segment_screen.dart';
import 'screens/splash.dart';
import 'screens/stats.dart';
import 'screens/steps.dart';
import 'theme/tokens.dart';
import 'utils/update_checker.dart';
import 'widgets/ui.dart';
import 'widgets/voice_sheet.dart';

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
  runApp(const StartApp());
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
    await showDialog<void>(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(S.radius)),
        title: Text('发现新版本 v${u.version}',
            style: TextStyle(color: c.ink, fontSize: S.textLg, fontWeight: FontWeight.bold)),
        content: Text('去仓库下载最新安装包',
            style: TextStyle(color: c.inkSoft, fontSize: S.textMd)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('忽略', style: TextStyle(color: c.inkSoft)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Native.openUrl(u.url);
            },
            child: Text('下载', style: TextStyle(color: c.accent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
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
            title: '启序',
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
                // 拖拽激活时整个界面上移，红色垃圾桶区贴屏幕最底部出现，不遮内容。
                child: ValueListenableBuilder<bool>(
                  valueListenable: DragDockBus.active,
                  child: child,
                  builder: (_, dragging, nav) {
                    final lift = dragging
                        ? 72 + S.lg + MediaQuery.viewPaddingOf(context).bottom
                        : 0.0;
                    // 纸色铺底：界面上移后露出的区域不是黑边。
                    return ColoredBox(
                      color: c.paper,
                      child: Stack(
                        children: [
                          AnimatedPadding(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            padding: EdgeInsets.only(bottom: lift),
                            child: nav!,
                          ),
                          const UndoHost(),
                          const _GlobalDragDock(),
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

/// 全局拖拽落点底座：拖到「移到这删除」= 删除（可撤销）；
/// 拖到「开成导图」= 以该条目标题为根新建思维导图并打开（原条目保留不动）。
class _GlobalDragDock extends StatelessWidget {
  const _GlobalDragDock();

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

  static Future<void> _toTrash(int id) async {
    final s = StartStore.I;
    // 多选整批拖入：一次删除、一次撤销（防误删 6 秒窗口由 UndoHost 保证）。
    final ids = DragDockBus.pendingIds;
    DragDockBus.pendingIds = null;
    if (ids != null && ids.length > 1) {
      final snap = await s.deleteAll(ids);
      _showUndoWhenIdle('删了 ${ids.length} 条', () async => s.restoreJson(snap));
      return;
    }
    if (s.byId(id) == null) return;
    final removed = s.delete(id, cascade: true);
    _showUndoWhenIdle('已删除', () async => s.restore(removed));
  }

  @override
  Widget build(BuildContext context) => const DragDock(onTrash: _toTrash);
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
/// 底栏：搜索 · 捋一捋 · 动手吧 · 专注 · 统计。
/// body 内嵌一个 Navigator：首页是其根路由，section 页推到该嵌套 navigator
/// （只占 body 区，Scaffold.bottomNavigationBar 始终常驻——老版 selectNav 行为）。
/// 点键后该键保持番茄红，持续到另一个键被点击。切换 section 用 pushReplacement 防栈堆积。
class _RootState extends State<Root> {
  /// 最后按下的底栏键索引：0念头 1捋一捋 2功能键 3专注 4统计。-1=未按过（在首页）。
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

  /// 长按功能键 = 语音速记。识别完进动手吧输入条复核；开了 AI 可直接整批结构化入库。
  Future<void> _startVoice() async {
    final r = await showVoiceSheet(context);
    if (r == null) return;
    final text = (r['text'] as String? ?? '').trim();
    if (text.isEmpty) return;
    if (r['action'] == 'ai' && AiConfig.ready) {
      await _runAiOrganize(text);
    } else {
      _goto(DumpScreen(initial: text), 2);
    }
  }

  /// 语音 → AI 解析 → 整批落库，带 loading 与整批撤销。
  Future<void> _runAiOrganize(String text) async {
    final ctx = StartApp.navigatorKey.currentContext;
    if (ctx == null) return;
    unawaited(showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.all(S.lg),
          decoration: BoxDecoration(
            color: ThemeTokens.of(ctx).card,
            borderRadius: BorderRadius.circular(S.radius),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: ThemeTokens.of(ctx).accent),
              ),
              const SizedBox(height: S.sm),
              Text('AI 正在整理…',
                  style: TextStyle(
                      fontSize: S.textSm, color: ThemeTokens.of(ctx).inkSoft)),
            ],
          ),
        ),
      ),
    ));
    try {
      final result = await Assistant.handle(text);
      final mctx = StartApp.navigatorKey.currentContext;
      if (mctx != null && mctx.mounted) Navigator.of(mctx, rootNavigator: true).pop();
      if (result.count == 0) {
        StartApp.messengerKey.currentState
            ?.showSnackBar(const SnackBar(content: Text('没听出要做的事，换个说法试试')));
        return;
      }
      final uctx = StartApp.navigatorKey.currentContext;
      if (uctx != null && uctx.mounted) {
        UndoHost.show(uctx, 'AI 整理了 ${result.count} 条',
            () async => StartStore.I.restoreJson(result.snapshot));
      }
    } catch (e) {
      final mctx = StartApp.navigatorKey.currentContext;
      if (mctx != null && mctx.mounted) Navigator.of(mctx, rootNavigator: true).pop();
      StartApp.messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('AI 没连上：$e')),
      );
    }
  }

  void _openSearch() => _goto(const SearchScreen(), 0);
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
              _navKey(c, Icons.search_outlined, _last == 0, _openSearch),
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
      onLongPress: _startVoice,
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
