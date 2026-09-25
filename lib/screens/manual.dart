import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../theme/tokens.dart';
import '../widgets/ui.dart';

/// 文本页通用骨架：返回 + 标题 + 图标 + 正文。
class TextPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;
  const TextPage({super.key, required this.icon, required this.title, required this.children});

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
                    child: Text(title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: S.textLg, fontWeight: FontWeight.bold, color: c.ink)),
                  ),
                  Icon(icon, color: c.inkSoft),
                ],
              ),
            ),
            Expanded(
              child: ListView(padding: const EdgeInsets.all(S.md), children: children),
            ),
          ],
        ),
      ),
    );
  }
}

/// 使用说明：软件用途开头 + 使用心法 + 各区说明 + 页脚致敬。
class ManualScreen extends StatelessWidget {
  const ManualScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return TextPage(
      icon: Icons.menu_book_outlined,
      title: '使用说明',
      children: [
        Text('Start 是一款本地记事工具：把待办拆成小步骤，帮你一次只做好一件事。为 ADHD 人群设计：措辞鼓励、低阻力、不责备。所有数据仅存于设备本地，唯一的联网行为是检查更新。',
            style: TextStyle(fontSize: S.textMd, height: 1.6, color: c.ink)),
        const SizedBox(height: S.lg),
        const _H('使用心法：丢 → 捋 → 做'),
        const _P('丢：想到什么先全写下来，不必分类。'),
        const _P('捋：抽空把暂存分拣到日程或随手做。'),
        const _P('做：一天只盯一件焦点，事情大就拆成小步骤。'),
        const SizedBox(height: S.lg),
        const _H('首页'),
        const _P('自上而下：焦点、大时钟、日程、随手做。纯文字清单，一眼看完。大时钟旁常驻一句鼓励——做完了一天是「今天的事都做完了，了不起」。'),
        const SizedBox(height: S.lg),
        const _H('焦点'),
        const _P('页面最上方的大标语区。没有焦点时显示「只专注一件事」，点「开始吧」：有事就从今日未完成里挑一件，没有就现写一件；也可以把任意任务长按拖到顶部设焦点。进专注统一走底栏「专注」页。'),
        const _P('选定后大字显示标题，主胶囊「拆成小步骤」进步骤页把事拆小；另有完成、编辑、更换一件。完成后显示「主线完成，漂亮」，点「下一件」继续。'),
        const _P('小步骤：输入条写一步存一步，回车换行可多写几步，保存时按行拆分。标题仅为事件名，不参与拆分。全部完成后任务自动勾掉。'),
        const SizedBox(height: S.lg),
        const _H('日程'),
        const _P('定时的任务按时刻排成纯文字清单，右侧标注时刻；过期未完成的仅标注日期，不变红、不责备；手机日历当天事件以小方点并排显示，自动去重。未来的日程到了那天自然出现。'),
        const _P('右上角加号新建日程：可换行一次写多件，选一个共同的日期时间一次排进。设好时间会自动写入手机日历并静默设好系统闹钟，到点提醒，无需手动。'),
        const SizedBox(height: S.lg),
        const _H('随手做'),
        const _P('没定时间的事都待在这。右上角加号可一次写多件，回车换行或句末标点自动拆成多条。'),
        const _P('拖动手柄排序；点行打开编辑器，可就地设时间变日程。'),
        const SizedBox(height: S.lg),
        const _H('全局拖拽：拖到落点'),
        const _P('任意一条（日程、随手做、小步骤、搜索结果）长按拖起，底部会浮出两个落点：移到「垃圾桶」删除（6 秒内可撤销）、移到「思维导图」以它为根开一张新导图。'),
        const _P('另有快捷拖法：首页把行拖到顶部=设为焦点；随手做拖进日程区=选个时间转日程。拖错都可撤销。'),
        const SizedBox(height: S.lg),
        const _H('搜索'),
        const _P('底栏放大镜，就是全部任务的管理台：找全部条目（日程、随手做、小步骤），标题或备注包含即命中。下方分类胶囊一键筛选，点一条直达编辑，右侧叉号删除。'),
        const _P('右上角进批量态：全选后一键删除，误删可撤销。'),
        const SizedBox(height: S.lg),
        const _H('动手吧'),
        const _P('底栏中央红色圆钮。先写下来，不必分类；点「倒进来」后按行与句末标点（。！？；…）自动拆成多件，进入捋一捋。'),
        const SizedBox(height: S.lg),
        const _H('捋一捋'),
        const _P('底部输入条可直接速记：回车换行多写几条，保存时按行与句末标点自动拆成多条暂存，与「动手吧」同一规则。'),
        const _P('分类：逐条分到日程（可设日期时间）或随手做，分类后自动流入首页对应区域。'),
        const _P('思维导图点按选中节点后可加子枝、加同级、编辑、删除；按住拖动可连同子树移动，双指缩放。'),
        const _P('点导入图标可把日程、随手做、小步骤复制进导图拆解；长按节点直达编辑文字、加子节点、剪掉这枝。'),
        const _P('右上角加号新建单条暂存；点「批量整理」进入批量操作，支持全选。'),
        const SizedBox(height: S.lg),
        const _H('提醒与日历'),
        const _P('新建日程时，保存后会自动写入手机日历并静默设好系统闹钟，到点提醒，无需手动操作。也可在编辑器里手动开关提醒、查看日历写入状态。'),
        const _P('提醒全部在本机完成，重启后自动重排；相关开关在设置内。'),
        const SizedBox(height: S.lg),
        const _H('专注与统计'),
        const _P('专注：仅显示圆环与倒计时数字，无干扰。时长在进入专注前选择：预设 2 / 25 / 45 分钟，或自定义 1–240 分钟，当前时长会大字显示。每分钟滴答一声、做完提示方式与音量在设置中调整。'),
        const _P('统计：以日期为维度，左右滑动切换查看不同日期的专注分钟、专注次数、完成件数、新增条目和 24 小时整点分布。纯文字大数字，客观记录进展。'),
        const SizedBox(height: S.lg),
        const _H('数据与更新'),
        const _P('搜索里可以找到并删除任何条目，误删可撤销。设置中可导出 JSON 备份，导入前自动快照、可撤销。卸载应用即删除全部数据，请先导出。有新版本时会自动提醒。'),
        const SizedBox(height: S.lg),
        const _H('关于设计'),
        const _P('作者是锤子手机用户，深受 Smartisan OS 影响。这款小东西追求简洁、一致和以人为本的设计，全部代码由 Dart 独立编写。'),
        const SizedBox(height: S.lg),
        Center(
          child: Text('Start', style: TextStyle(fontSize: S.textSm, color: c.inkSoft)),
        ),
        const SizedBox(height: S.sm),
        Center(
          child: Text('── 工匠的骄傲与喜悦 · PRIDE & JOY ──',
              style: TextStyle(fontSize: 11, letterSpacing: 1, color: c.inkSoft)),
        ),
        const SizedBox(height: S.xl),
      ],
    );
  }
}

/// 用户协议 / 隐私政策：设置页独立入口。
class AgreeScreen extends StatelessWidget {
  final bool privacy;
  const AgreeScreen({super.key, required this.privacy});

  @override
  Widget build(BuildContext context) {
    return TextPage(
      icon: privacy ? Icons.privacy_tip_outlined : Icons.description_outlined,
      title: privacy ? '隐私政策' : '用户协议',
      children: privacy
          ? const [
              _P('1. 不收集、不上传：没有账户、没有广告、没有统计 SDK，所有内容只存在你的手机里。'),
              _P('2. 唯一联网：检查更新时访问代码托管平台的公开接口，仅取回最新版本号，不携带你的任何数据。'),
              _P('3. 日程与随手做的到点提醒、常驻通知，全部在你手机本机完成，不经过任何服务器。'),
              _P('4. 卸载应用即彻底删除全部数据；想留底请先用导出功能。'),
              _P('5. 对本政策有疑问，可通过设置里的「联系作者」咨询开发者。'),
            ]
          : const [
              _P('1. 本应用对个人非商业使用永久免费，商业使用需开发者的书面授权。'),
              _P('2. 本应用由个人开发者借助人工智能工具开发，开发者不编写程序代码。应用按"现状"提供，不作任何明示或暗示的担保。'),
              _P('3. 本应用是自由软件：源代码以 GNU AGPLv3+ 许可公开，你可以自由使用、研究、修改和再分发；衍生作品须继续以 AGPLv3+ 开源，即使不分发、仅通过网络提供交互服务，也须向用户提供完整源代码。希望闭源商用，请联系作者取得书面授权。'),
              _P('4. 你的所有内容仅存储在设备本地；唯一联网行为是检查软件更新（访问代码托管平台的公开接口，不发送你的任何数据）。'),
              _P('5. 请使用设置里的导出功能自行备份；设备丢失、损坏或卸载造成的数据损失，开发者不承担责任。'),
              _P('6. 本产品不能代替医疗。Start 是面向注意力管理挑战的辅助工具，不构成医疗建议、诊断或治疗。如有健康疑虑，请咨询专业医疗机构。'),
              _P('7. 致敬 Smartisan OS：本应用的交互理念深受其大爆炸、一步等开源组件启发，谨向其开源团队致敬。所有代码均为独立编写，未直接复制其源代码，相关开源组件遵循其原有许可证。'),
              _P('8. AI 辅助声明：本应用的部分界面文案、交互逻辑与代码实现由人工智能辅助生成，开发者对最终产品负责。'),
              _P('9. 继续使用即表示同意本协议；协议有更新时会再次征求你的同意。'),
            ],
    );
  }
}

/// 开源协议：AGPLv3 全文（assets/agpl.txt）。
class LicenseScreen extends StatefulWidget {
  const LicenseScreen({super.key});

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  String _gpl = '加载中…';

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('assets/agpl.txt').then((v) {
      if (mounted) setState(() => _gpl = v);
    }).catchError((_) {
      if (mounted) setState(() => _gpl = '许可证文本缺失，请查阅项目仓库 LICENSE 文件。');
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    return TextPage(
      icon: Icons.gavel_outlined,
      title: '开源协议（AGPLv3）',
      children: [
        const _P('本程序是自由软件，依据 GNU Affero 通用公共许可证第 3 版发布，你可以据此重新分发或修改它。即使不分发、仅通过网络提供本程序的交互服务，也必须向用户提供完整源代码。以下是许可证全文：'),
        const SizedBox(height: S.sm),
        SelectableText(_gpl, style: TextStyle(fontSize: 11, height: 1.4, color: c.inkSoft)),
        const SizedBox(height: S.xl),
      ],
    );
  }
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
              child: Text('欢迎使用 Start',
                  style:
                      TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: c.ink)),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: S.md),
                children: const [
                  _P('Start 把待办和念头拆成小步骤，帮你一次只做好一件事。数据只存在你手机里，不带走你任何数据。'),
                  SizedBox(height: S.lg),
                  _H('用户协议'),
                  _P('1. 本应用对个人非商业使用永久免费，商业使用需开发者的书面授权。'),
                  _P('2. 本应用由个人开发者借助人工智能工具开发，开发者不编写程序代码。应用按"现状"提供，不作任何明示或暗示的担保。'),
                  _P('3. 本应用是自由软件：源代码以 GNU AGPLv3+ 许可公开，衍生作品须继续开源；即使仅通过网络提供交互服务，也须向用户提供完整源代码。'),
                  _P('4. 你的所有内容仅存储在设备本地；唯一联网行为是检查软件更新（访问代码托管平台的公开接口，不发送你的任何数据）。'),
                  _P('5. 请使用设置里的导出功能自行备份；设备丢失、损坏或卸载造成的数据损失，开发者不承担责任。'),
                  _P('6. 灵感与致敬：本应用的交互灵感来源于 Smartisan OS，谨此向其团队致敬。'),
                  _P('7. 继续使用即表示同意本协议；协议有更新时会再次征求你的同意。'),
                  SizedBox(height: S.lg),
                  _H('隐私政策'),
                  _P('1. 不收集、不上传：没有账户、没有广告、没有统计 SDK，所有内容只存在你的手机里。'),
                  _P('2. 唯一联网：检查更新时访问代码托管平台的公开接口，仅取回最新版本号，不携带你的任何数据。'),
                  _P('3. 日程与随手做的到点提醒、常驻通知，全部在你手机本机完成，不经过任何服务器。'),
                  _P('4. 卸载应用即彻底删除全部数据；想留底请先用导出功能。'),
                  _P('5. 对本政策有疑问，可通过设置里的「联系作者」咨询开发者。'),
                  SizedBox(height: S.xl),
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
                  child: const Text('同意并开始',
                      style: TextStyle(
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
