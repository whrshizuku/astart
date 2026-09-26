import 'docs_en.dart';
import 'docs_ja.dart';
import 'docs_zh_tw.dart';
import 'ui_en.dart';
import 'ui_ja.dart';
import 'ui_zh_tw.dart';

/// 翻译词典：key 一律为简体中文原文（与代码中 tr('…') 的原文逐字一致）。
///
/// 简体中文不设词典（tr 直接返回原文）；以下三种语言除中文外暂由 AI 翻译。
/// 维护规则：
/// 1. 新增界面文字时，直接在代码里写简体中文 tr('新文案')，然后在此补三份译文；
/// 2. 占位符沿用 {0} {1}，三种语言保持位置与数量一致；
/// 3. 标点风格跟随目标语言习惯（英/日文句末不用中文句号）。
const Map<String, Map<String, String>> translations = {
  'en': {...kUiEn, ...kDocsEn},
  'ja': {...kUiJa, ...kDocsJa},
  'zh-TW': {...kUiZhTw, ...kDocsZhTw},
};
