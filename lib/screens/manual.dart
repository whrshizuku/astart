import 'package:flutter/material.dart';

import '../l10n/i18n.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';
import 'doc_screen.dart';

/// 使用说明：正文为 assets/docs 内嵌文档（随语言切换）。
class ManualScreen extends StatelessWidget {
  const ManualScreen({super.key});

  @override
  Widget build(BuildContext context) => DocScreen(
        doc: 'manual',
        icon: Icons.menu_book_outlined,
        title: tr('使用说明'),
      );
}

/// 用户协议 / 隐私政策：设置页独立入口，正文为内嵌文档。
class AgreeScreen extends StatelessWidget {
  final bool privacy;
  const AgreeScreen({super.key, required this.privacy});

  @override
  Widget build(BuildContext context) => DocScreen(
        doc: privacy ? 'privacy' : 'terms',
        icon: privacy ? Icons.privacy_tip_outlined : Icons.description_outlined,
        title: privacy ? tr('隐私政策') : tr('用户协议'),
      );
}

/// 开源协议：双许可内嵌文档 + AGPLv3 英文全文。
class LicenseScreen extends StatelessWidget {
  const LicenseScreen({super.key});

  @override
  Widget build(BuildContext context) => DocScreen(
        doc: 'license',
        icon: Icons.gavel_outlined,
        title: tr('开源协议（双许可）'),
        appendAgpl: true,
      );
}

/// 非简体中文时，正文顶部的 AI 翻译声明。
Widget _aiNote(BuildContext context) {
  if (Lang.current == Lang.zhCN) return const SizedBox.shrink();
  final c = ThemeTokens.of(context);
  return Padding(
    padding: const EdgeInsets.only(bottom: S.sm),
    child: Text(tr('除简体中文外，界面翻译由人工智能生成，仅供参考'),
        style: TextStyle(fontSize: S.textSm, color: c.inkSoft)),
  );
}

/// 首次启动欢迎页：只展示用户协议与隐私条款，无外链。
class FirstRunScreen extends StatelessWidget {
  final VoidCallback onAccept;
  const FirstRunScreen({super.key, required this.onAccept});

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(S.lg),
              child: Text(tr('欢迎使用{0}', [Lang.appNameOf(Lang.current)]),
                  style:
                      TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: c.ink)),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: S.md),
                children: [
                  _aiNote(context),
                  _P(tr('启序（英文名 Start）把待办和念头拆成小步骤，帮你一次只做好一件事。你的数据默认只存在手机里，不带走你任何数据。')),
                  const SizedBox(height: S.lg),
                  _H(tr('用户协议')),
                  _P(tr('1. 本应用对个人非商业使用永久免费，商业使用需开发者的书面授权。')),
                  _P(tr('2. 本应用由个人开发者独立设计与开发，开发过程中借助人工智能工具辅助编码；产品的设计方案、交互逻辑与工作流程均为开发者原创，人工智能仅用于功能实现，不参与原创设计。应用按"现状"提供，不作任何明示或暗示的担保。')),
                  _P(tr('3. 本应用是自由软件：源代码以 GNU AGPLv3+ 许可公开，衍生作品须继续开源；即使仅通过网络提供交互服务，也须向用户提供完整源代码。')),
                  _P(tr('4. 你的所有内容默认仅存储于设备本地；除检查更新外，在线语音、AI 助手、WebDAV 云备份均为默认关闭的可选功能，仅在你手动开启并主动使用时联网，详见应用内隐私政策。')),
                  _P(tr('5. 请使用设置里的导出功能自行备份；设备丢失、损坏或卸载造成的数据损失，开发者不承担责任。')),
                  _P(tr('6. 灵感与致敬：本应用的交互灵感来源于 Smartisan OS，谨此向其团队致敬。')),
                  _P(tr('7. 继续使用即表示同意本协议；协议有更新时会再次征求你的同意。')),
                  const SizedBox(height: S.lg),
                  _H(tr('隐私政策')),
                  _P(tr('1. 不收集、不上传：没有账户、没有广告、没有统计 SDK，所有内容只存在你的手机里。')),
                  _P(tr('2. 联网行为：默认仅检查更新；在线语音、AI 助手、云备份默认关闭，手动开启并主动使用时才联网，可随时关闭。')),
                  _P(tr('3. 日程与随手做的到点提醒、常驻通知，全部在你手机本机完成，不经过任何服务器。')),
                  _P(tr('4. 卸载应用即彻底删除全部数据；想留底请先用导出功能。')),
                  _P(tr('5. 对本政策有疑问，可通过设置里的「联系作者」咨询开发者。')),
                  const SizedBox(height: S.xl),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(S.md),
              child: Pressable(
                onTap: onAccept,
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: c.accent, borderRadius: BorderRadius.circular(S.radius)),
                  child: Text(tr('同意并开始'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: S.textMd,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _H extends StatelessWidget {
  final String t;
  const _H(this.t);
  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Text(t,
        style: TextStyle(fontSize: S.textLg, fontWeight: FontWeight.bold, color: c.ink));
  }
}

class _P extends StatelessWidget {
  final String t;
  const _P(this.t);
  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: S.xs),
      child: Text(t, style: TextStyle(fontSize: S.textMd, height: 1.6, color: c.ink)),
    );
  }
}
