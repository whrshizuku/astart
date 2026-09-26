import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../channels/native.dart';
import '../l10n/i18n.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

/// 内嵌文档页：从 `assets/docs/<语言>/<id>.md` 加载正文。
///
/// 极简标记：
///   `# ` 章节标题；`> ` 小号说明（法律效力声明）；`~ ` 居中小字（页脚/彩蛋）；
///   空行 = 间距；其余为正文段落，网址与邮箱自动可点。
/// [appendAgpl] 为 true 时在正文后拼接 AGPLv3 英文全文（assets/agpl.txt）。
class DocScreen extends StatefulWidget {
  final String doc;
  final IconData icon;
  final String title;
  final bool appendAgpl;

  const DocScreen({
    super.key,
    required this.doc,
    required this.icon,
    required this.title,
    this.appendAgpl = false,
  });

  @override
  State<DocScreen> createState() => _DocScreenState();
}

class _DocScreenState extends State<DocScreen> {
  String? _text;
  String? _agpl;
  bool _failed = false;

  static final _linkRe = RegExp(r'https?://[^\s)]+|[\w.+-]+@[\w-]+\.[\w.-]+');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    String? body;
    try {
      body = await rootBundle.loadString('assets/docs/${Lang.current}/${widget.doc}.md');
    } catch (_) {
      try {
        body = await rootBundle.loadString('assets/docs/zh-CN/${widget.doc}.md');
      } catch (_) {
        body = null;
      }
    }
    if (!mounted) {
      return;
    }
    if (body == null) {
      setState(() => _failed = true);
      return;
    }
    String? agpl;
    if (widget.appendAgpl) {
      try {
        agpl = await rootBundle.loadString('assets/agpl.txt');
      } catch (_) {
        agpl = tr('许可证文本缺失，请查阅项目仓库 LICENSE 文件。');
      }
    }
    if (mounted) setState(() {
      _text = body;
      _agpl = agpl;
    });
  }

  List<Widget> _render(String content) {
    final c = ThemeTokens.of(context);
    final lines = content.split('\n');
    final out = <Widget>[];
    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.isEmpty) {
        out.add(const SizedBox(height: S.sm));
      } else if (line.startsWith('# ')) {
        out.add(Padding(
          padding: const EdgeInsets.only(top: S.md, bottom: S.xs),
          child: Text(line.substring(2),
              style:
                  TextStyle(fontSize: S.textLg, fontWeight: FontWeight.bold, color: c.ink)),
        ));
      } else if (line.startsWith('> ')) {
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: S.sm),
          child: Text(line.substring(2),
              style: TextStyle(fontSize: S.textSm, height: 1.5, color: c.inkSoft)),
        ));
      } else if (line.startsWith('~ ')) {
        out.add(Padding(
          padding: const EdgeInsets.only(top: S.sm),
          child: Center(
            child: Text(line.substring(2),
                style: TextStyle(fontSize: 11, letterSpacing: 1, color: c.inkSoft)),
          ),
        ));
      } else {
        out.add(Padding(
          padding: const EdgeInsets.only(top: S.xs),
          child: _para(line, c),
        ));
      }
    }
    if (widget.appendAgpl && _agpl != null) {
      out.addAll([
        const SizedBox(height: S.sm),
        SelectableText(_agpl!,
            style: TextStyle(fontSize: 11, height: 1.4, color: c.inkSoft)),
      ]);
    }
    out.add(const SizedBox(height: S.xl));
    return out;
  }

  /// 正文段落：自动把网址/邮箱渲染成可点击链接。
  Widget _para(String text, C c) {
    final base = TextStyle(fontSize: S.textMd, height: 1.6, color: c.ink);
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _linkRe.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      final hit = m.group(0)!;
      final isMail = !hit.startsWith('http');
      final uri = isMail ? 'mailto:$hit' : hit;
      spans.add(TextSpan(
        text: hit,
        style: TextStyle(color: c.accent, decoration: TextDecoration.underline),
        recognizer: TapGestureRecognizer()..onTap = () => Native.openUrl(uri),
      ));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return RichText(text: TextSpan(style: base, children: spans));
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(S.md, S.sm, S.md, 0),
              child: Row(
                children: [
                  IconBtn(Icons.arrow_back, onTap: () => Navigator.pop(context)),
                  Expanded(
                    child: Text(widget.title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: S.textLg,
                            fontWeight: FontWeight.bold,
                            color: c.ink)),
                  ),
                  Icon(widget.icon, color: c.inkSoft),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(S.md),
                children: [
                  if (Lang.current != Lang.zhCN)
                    Padding(
                      padding: const EdgeInsets.only(bottom: S.sm),
                      child: Text(tr('除简体中文外，界面翻译由人工智能生成，仅供参考'),
                          style: TextStyle(fontSize: S.textSm, color: c.inkSoft)),
                    ),
                  if (_text != null)
                    ..._render(_text!)
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: S.xl),
                      child: Center(
                        child: Text(
                            _failed
                                ? tr('文档加载失败，请稍后重试。')
                                : tr('加载中…'),
                            style: TextStyle(fontSize: S.textMd, color: c.inkSoft)),
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
}
