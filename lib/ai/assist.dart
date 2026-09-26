import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/item.dart';
import '../data/store.dart';

/// 智能助手配置：OpenAI 兼容协议（chat/completions），可接任意兼容端点。
/// 所有配置只存在本机 start_prefs；功能默认关闭，由用户在设置里手动开启。
class AiConfig {
  AiConfig._();

  /// (展示名, baseUrl, 默认模型)。前两个为注册即送免费额度的公开服务。
  static const presets = <(String, String, String)>[
    ('智谱 GLM-4-Flash（免费）', 'https://open.bigmodel.cn/api/paas/v4', 'glm-4-flash'),
    ('硅基流动 Qwen2.5-7B（免费）', 'https://api.siliconflow.cn/v1',
        'Qwen/Qwen2.5-7B-Instruct'),
    ('自定义端点', '', ''),
  ];

  static bool get on => StartStore.I.prefBool('ai_on', false);
  static String get base => StartStore.I.prefStr('ai_base');
  static String get key => StartStore.I.prefStr('ai_key');
  static String get model => StartStore.I.prefStr('ai_model');

  static bool get ready => on && base.isNotEmpty && model.isNotEmpty && key.isNotEmpty;

  static Future<void> setOn(bool v) => StartStore.I.setPref('ai_on', v);
  static Future<void> setBase(String v) => StartStore.I.setPref('ai_base', v.trim());
  static Future<void> setKey(String v) => StartStore.I.setPref('ai_key', v.trim());
  static Future<void> setModel(String v) => StartStore.I.setPref('ai_model', v.trim());
}

class AiClient {
  AiClient._();

  /// 单轮对话，返回模型文本。端点/模型/密钥取自 [AiConfig]。
  static Future<String> chat(String user, {String? system, double temperature = 0.2}) async {
    final uri = Uri.parse('${AiConfig.base.replaceAll(RegExp(r'/+$'), '')}/chat/completions');
    final body = jsonEncode({
      'model': AiConfig.model,
      'temperature': temperature,
      'messages': [
        if (system != null) {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
    });
    final resp = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${AiConfig.key}',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }
    final root = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final choices = root['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) throw Exception('返回为空');
    return ((choices.first as Map<String, dynamic>)['message']
            as Map<String, dynamic>)['content'] as String? ??
        '';
  }

  /// 连通性自检：发一句最短的对话。
  static Future<String> ping() async => chat('ping', temperature: 0);
}

/// 解析出的动作：随手做 / 日程 / 念头 / 无。
class AssistIntent {
  final String action; // task | schedule | idea | none
  final String title;
  final int dueMs;
  const AssistIntent(this.action, this.title, this.dueMs);

  bool get valid => action != 'none' && title.trim().isNotEmpty;
}

/// 一批结构化结果：落库条目数 + 落库前快照（供整批撤销）。
class ApplyResult {
  final int count;
  final String snapshot;
  const ApplyResult(this.count, this.snapshot);
}

class Assistant {
  Assistant._();

  /// 2.0 重构：一段语音/文字可能含多件事，统一解析为动作数组。
  static const _sysPrompt = '''
你是一个待办 App 的意图解析器。把用户的一段话解析为若干个动作，只输出 JSON 数组，禁止输出任何解释或 Markdown 代码块。
输出格式：[{"action":"task|idea|schedule|none","title":"精简后的事项名","due":"yyyy-MM-dd HH:mm"}]
规则：
- schedule：话里有明确日期或时刻（明天、下周一、晚上八点等），due 必须换算为绝对时间；
- idea：灵感、备忘、参考资料、还没决定要不要做的事；
- task：其余打算做但没有明确时间的事；
- none：与待办完全无关的寒暄、语气词，单独成段时才用；
- title 用简短中文动宾短语，去掉语气词，不超过 20 个字；
- 拿不准具体时间时按 task 处理，due 留空；
- 没有任何有效事项时输出 []。''';

  /// 自然语言 → 结构化意图列表。模型异常时抛出，调用方自行提示。
  static Future<List<AssistIntent>> parseList(String spoken) async {
    final now = DateTime.now();
    final stamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}，星期${'一 二三四五六日'[now.weekday - 1]}';
    final raw = await AiClient.chat('当前时间：$stamp\n用户说：$spoken', system: _sysPrompt);
    final match = RegExp(r'\[.*\]', dotAll: true).firstMatch(raw);
    if (match == null) throw Exception('模型未返回 JSON 数组');
    final arr = jsonDecode(match.group(0)!) as List<dynamic>;
    return arr.whereType<Map<String, dynamic>>().map((m) {
      final action = (m['action'] as String? ?? 'none').trim();
      final title = (m['title'] as String? ?? '').trim();
      var dueMs = 0;
      final due = (m['due'] as String? ?? '').trim();
      if (due.isNotEmpty) {
        final t = DateTime.tryParse(due.replaceAll(' ', 'T'));
        if (t != null) dueMs = t.millisecondsSinceEpoch;
      }
      final normalized = {'task', 'schedule', 'idea'}.contains(action) ? action : 'none';
      return AssistIntent(normalized, title, dueMs);
    }).toList();
  }

  /// 整批落库：先快照（供撤销），日程自动开提醒，念头走 rank 队尾。
  static Future<ApplyResult> applyList(List<AssistIntent> intents) async {
    final s = StartStore.I;
    final snap = s.exportJson();
    final valid = intents.where((e) => e.valid).toList();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < valid.length; i++) {
      final intent = valid[i];
      final it = Item(
        kind: intent.action == 'idea' ? Item.kindIdea : Item.kindTask,
        title: intent.title,
        created: now + i,
      );
      if (intent.action == 'schedule' && intent.dueMs > 0) {
        it.dueTime = intent.dueMs;
        it.alarm = true;
      }
      await s.put(it, touchRank: it.isIdea);
    }
    return ApplyResult(valid.length, snap);
  }

  /// 一步到位：说话/文字 → 解析 → 整批落库。
  static Future<ApplyResult> handle(String text) async => applyList(await parseList(text));
}
