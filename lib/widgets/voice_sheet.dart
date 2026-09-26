import 'dart:async';

import 'package:flutter/material.dart';

import '../channels/native.dart';
import '../data/store.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';
import '../l10n/i18n.dart';

/// 长按「动手吧」唤起的语音面板。默认系统离线引擎（不联网）；
/// 用户在设置开启「在线语音」后允许在线识别。
///
/// 返回 {'action': 'dump'|'ai', 'text': 识别全文}；取消返回 null。
Future<Map<String, dynamic>?> showVoiceSheet(BuildContext context) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ThemeTokens.of(context).paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(S.lg)),
    ),
    builder: (_) => const _VoiceSheet(),
  );
}

class _VoiceSheet extends StatefulWidget {
  const _VoiceSheet();

  @override
  State<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<_VoiceSheet> with TickerProviderStateMixin {
  StreamSubscription? _sub;
  final List<String> _parts = []; // 已确认的句子
  String _partial = ''; // 本轮临时结果
  String _error = '';
  bool _closing = false;
  Timer? _restart;
  late final AnimationController _pulse;

  bool get _aiReady => StartStore.I.prefBool('ai_on', false);

  String get _text => [..._parts, if (_partial.isNotEmpty) _partial].join('，');

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _sub = SystemVoice.events().listen(_onEvent);
    _begin();
  }

  Future<void> _begin() async {
    await SystemVoice.start(
      online: StartStore.I.prefBool('voice_online', false),
    );
  }

  /// 一句说完后自动续听（停顿/无匹配/引擎忙都静默重开），直到用户手动结束。
  void _autoRestart() {
    _restart?.cancel();
    _restart = Timer(const Duration(milliseconds: 350), () {
      if (!mounted || _closing) return;
      _begin();
    });
  }

  void _onEvent(Map<String, Object?> e) {
    if (!mounted || _closing) return;
    final type = e['type'] as String? ?? '';
    final text = (e['text'] as String? ?? '').trim();
    switch (type) {
      case 'ready':
        setState(() => _error = '');
        break;
      case 'partial':
        setState(() => _partial = text);
        break;
      case 'final':
        if (text.isNotEmpty) {
          setState(() {
            _parts.add(text);
            _partial = '';
            _error = '';
          });
        }
        _autoRestart();
        break;
      case 'end':
        _autoRestart();
        break;
      case 'error':
        final code = int.tryParse(text);
        // 6 超时 / 7 没听清 / 8 引擎忙：安静环境下的正常事件，静默续听。
        if (code != null && (code == 6 || code == 7 || code == 8)) {
          _autoRestart();
        } else if (code == null) {
          // 原生侧给的中文人话提示（无引擎 / 麦克风权限）。
          setState(() => _error = text);
        } else {
          setState(() => _error = tr('识别出了点问题（{0}），请重试', [code]));
        }
        break;
    }
  }

  Future<void> _finish(String action) async {
    if (_closing) return;
    _closing = true;
    _restart?.cancel();
    await SystemVoice.stop();
    if (!mounted) return;
    Navigator.pop(context, {'action': action, 'text': _text});
  }

  Future<void> _cancel() async {
    if (_closing) return;
    _closing = true;
    _restart?.cancel();
    await SystemVoice.stop();
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _restart?.cancel();
    _sub?.cancel();
    _pulse.dispose();
    // 非正常退出（下滑关 sheet）也要停麦。
    SystemVoice.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final online = StartStore.I.prefBool('voice_online', false);
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (_, __) => _cancel(),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(S.md, S.sm, S.md, S.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 抓手条
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: S.sm),
                  decoration: BoxDecoration(
                    color: c.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _PulsingMic(pulse: _pulse, color: c.accent),
                  const SizedBox(width: S.sm),
                  Flexible(
                    child: Text(_error.isEmpty ? tr('正在听，说完自动续听') : tr('没在听'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: S.textMd,
                            fontWeight: FontWeight.bold,
                            color: _error.isEmpty ? c.ink : c.accentDark)),
                  ),
                  const SizedBox(width: S.sm),
                  Text(online ? tr('在线') : tr('离线'),
                      style: TextStyle(fontSize: S.textSm, color: c.inkSoft)),
                ],
              ),
              const SizedBox(height: S.sm),
              // 识别文字区
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 168, minHeight: 72),
                child: StartCard(
                  color: c.ringWell,
                  padding: const EdgeInsets.all(S.md),
                  child: SingleChildScrollView(
                    reverse: true,
                    child: SizedBox(
                      width: double.infinity,
                      child: _error.isNotEmpty
                          ? Text(_error,
                              style: TextStyle(
                                  fontSize: S.textMd, color: c.accentDark, height: 1.5))
                          : Text.rich(
                              TextSpan(children: [
                                TextSpan(
                                  text: _parts.join('，'),
                                  style: TextStyle(
                                      fontSize: S.textMd, color: c.ink, height: 1.5),
                                ),
                                if (_parts.isNotEmpty && _partial.isNotEmpty)
                                  const TextSpan(text: '，'),
                                TextSpan(
                                  text: _partial,
                                  style: TextStyle(
                                      fontSize: S.textMd, color: c.inkSoft, height: 1.5),
                                ),
                              ]),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: S.md),
              Row(
                children: [
                  Expanded(
                    child: Pressable(
                      onTap: _cancel,
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
                  if (_aiReady) ...[
                    const SizedBox(width: S.sm),
                    Expanded(
                      child: Pressable(
                        onTap: () => _finish('ai'),
                        child: Container(
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: c.accentSoft,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: c.accent, width: 1.5),
                          ),
                          child: Text(tr('AI 整理'),
                              style: TextStyle(
                                  fontSize: S.textMd,
                                  fontWeight: FontWeight.bold,
                                  color: c.accentDark)),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: S.sm),
                  Expanded(
                    child: Pressable(
                      onTap: () => _finish('dump'),
                      child: Container(
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.accent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(tr('说完了'),
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

/// 录音中的脉动麦克风：番茄红圆点 + 呼吸外扩波纹。
class _PulsingMic extends StatelessWidget {
  final Animation<double> pulse;
  final Color color;
  const _PulsingMic({required this.pulse, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: AnimatedBuilder(
        animation: pulse,
        builder: (_, __) {
          final t = pulse.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 28 + 8 * t,
                height: 28 + 8 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.18 * (1 - t)),
                ),
              ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [
                    BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 8),
                  ],
                ),
                child: const Icon(Icons.mic, size: 16, color: Colors.white),
              ),
            ],
          );
        },
      ),
    );
  }
}
