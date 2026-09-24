import 'package:flutter/material.dart';

import '../channels/native.dart';
import '../data/item.dart';
import '../data/store.dart';
import '../main.dart';
import '../theme/tokens.dart';
import 'ui.dart';

/// 任务/念头编辑弹层：标题、备注、时间、提醒三开关、焦点、拆步骤入口、删除。
/// [asSchedule]=true 为首页日程加号的「新建日程」模式：打开即选日期时间，
/// 日期底下排列提醒 / 写入日历 / 系统闹钟；没有标题或没选时间不会保存，
/// 既不会流落随手做，也不会留下空白日程。
Future<void> showItemEditor(BuildContext context, Item it,
    {VoidCallback? onDeleted, bool asSchedule = false}) {
  return showStartSheet(
    context,
    (_) => _EditorSheet(item: it, onDeleted: onDeleted, asSchedule: asSchedule),
  );
}

class _EditorSheet extends StatefulWidget {
  final Item item;
  final VoidCallback? onDeleted;
  final bool asSchedule;
  const _EditorSheet({required this.item, this.onDeleted, this.asSchedule = false});

  @override
  State<_EditorSheet> createState() => _EditorSheetState();
}

class _EditorSheetState extends State<_EditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _note;
  final FocusNode _titleFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.item.title);
    _note = TextEditingController(text: widget.item.note);
    _title.addListener(_onText);
    // 新建日程：弹层一打开直接进日期时间选择；取消即放弃，不建空白日程。
    if (widget.asSchedule) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pickDue(auto: true);
      });
    }
  }

  void _onText() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _title.removeListener(_onText);
    _title.dispose();
    _note.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  /// 新建日程被关闭时兜底：内容或时间不完整就清掉（id 为 0 时 delete 为空操作）。
  void _abandonIfIncomplete() {
    if (!widget.asSchedule) return;
    final it = widget.item;
    if (_title.text.trim().isEmpty || it.dueTime == 0) {
      StartStore.I.delete(it.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final it = widget.item;
    final pad = MediaQuery.of(context).viewInsets.bottom;
    // 新建日程必须标题与时间都齐才算数；未齐时不显示焦点 / 拆步骤入口。
    final complete = _title.text.trim().isNotEmpty && it.dueTime > 0;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _abandonIfIncomplete();
      },
      child: Padding(
        padding: EdgeInsets.only(left: S.md, right: S.md, top: S.md, bottom: pad + S.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: S.md),
            TextField(
              controller: _title,
              focusNode: _titleFocus,
              autofocus: it.title.isEmpty && !widget.asSchedule,
              style: TextStyle(fontSize: S.textLg, fontWeight: FontWeight.bold, color: c.ink),
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: widget.asSchedule
                    ? '这件日程是什么？'
                    : it.isIdea
                        ? '想到什么，先记下来'
                        : '这一步要做什么？',
                hintStyle: TextStyle(color: c.inkSoft),
                border: InputBorder.none,
              ),
            ),
            if (!it.isIdea)
              TextField(
                controller: _note,
                style: TextStyle(fontSize: S.textMd, color: c.ink),
                maxLines: null,
                decoration: InputDecoration(
                  hintText: '备注（可选）',
                  hintStyle: TextStyle(color: c.inkSoft),
                  border: InputBorder.none,
                ),
              ),
            const SizedBox(height: S.sm),
            Row(
              children: [
                IconBtn(Icons.today_outlined,
                    tip: '安排时间', color: it.dueTime > 0 ? c.accent : c.ink,
                    onTap: () => _pickDue()),
                Text(
                  it.dueTime > 0 ? _fmtDue(it.dueTime) : (widget.asSchedule ? '选个日期和时间' : '随时'),
                  style: TextStyle(
                      color: it.dueTime > 0 ? c.accent : c.inkSoft, fontSize: S.textSm),
                ),
                const Spacer(),
                // 新建日程必须带时间，不允许在编辑器里清空（清了就不成为日程）。
                if (it.dueTime > 0 && !widget.asSchedule)
                  IconBtn(Icons.close, tip: '清除时间', onTap: () async {
                    it.dueTime = 0;
                    await StartStore.I.put(it);
                    setState(() {});
                  }),
              ],
            ),
            const SizedBox(height: S.xs),
            Wrap(
              spacing: S.xs,
              runSpacing: S.xs,
              children: [
                // 日期底下的三项设置，仅定了时间后出现。
                if (!it.isIdea && it.dueTime > 0) ...[
                  _Chip(
                    label: it.alarm ? '提醒开着' : '提醒关着',
                    icon: it.alarm
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_off_outlined,
                    onTap: () async {
                      it.alarm = !it.alarm;
                      await StartStore.I.put(it);
                      setState(() {});
                    },
                  ),
                  _Chip(
                    label: it.eventId > 0 ? '已在日历' : '写入日历',
                    icon: it.eventId > 0
                        ? Icons.event_available_outlined
                        : Icons.calendar_today_outlined,
                    onTap: () async {
                      if (it.eventId > 0) {
                        Native.openUrl(
                            'content://com.android.calendar/time/${it.dueTime}');
                        return;
                      }
                      final id =
                          await Native.calendarInsert(it.alarmLabel, it.dueTime);
                      if (id > 0) {
                        it.eventId = id;
                        await StartStore.I.put(it);
                        StartApp.messengerKey.currentState?.showSnackBar(
                          SnackBar(
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: Colors.black87,
                            content: const Text('已写入手机日历，到点它自己会提醒',
                                style: TextStyle(color: Colors.white)),
                            action: SnackBarAction(
                              label: '好',
                              textColor: const Color(0xFFFF6347),
                              onPressed: () {},
                            ),
                          ),
                        );
                      } else {
                        // 无写入权限：退回系统日历新建页。
                        Native.addToCalendar(it.alarmLabel, it.dueTime);
                      }
                      if (mounted) setState(() {});
                    },
                  ),
                  _Chip(label: '系统闹钟', icon: Icons.alarm_outlined, onTap: () {
                    Native.setAlarm(it.alarmLabel, it.dueTime);
                  }),
                ],
                if (!widget.asSchedule || complete)
                  _Chip(label: '设为今日焦点', icon: Icons.star_outline, onTap: () async {
                    await StartStore.I.setFocus(it.id);
                    if (context.mounted) Navigator.pop(context);
                  }),
                if (it.isIdea)
                  _Chip(label: '移到随手做', icon: Icons.checklist_outlined, onTap: () async {
                    it.kind = Item.kindTask;
                    it.dueTime = 0;
                    it.alarm = false;
                    await StartStore.I.put(it);
                    if (context.mounted) Navigator.pop(context);
                  }),
                if (!it.isIdea && (!widget.asSchedule || complete))
                  _Chip(label: '拆成小步骤', icon: Icons.call_split, onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context, rootNavigator: true)
                        .pushNamed('/steps', arguments: it.id);
                  }),
                _Chip(label: '删除', icon: Icons.delete_outline, danger: true, onTap: () async {
                  final removed = StartStore.I.delete(it.id, cascade: !it.isIdea);
                  if (context.mounted) {
                    Navigator.pop(context);
                    widget.onDeleted?.call();
                    UndoHost.show(
                      context,
                      it.isIdea ? '已删除念头' : '已删除（含小步骤）',
                      () async => StartStore.I.restore(removed),
                    );
                  }
                }),
              ],
            ),
            const SizedBox(height: S.md),
            Pressable(
              onTap: () async {
                it.title = _title.text.trim();
                it.note = _note.text.trim();
                // 新建日程：没有标题或没选日期时间，不保存、不关闭，更不会流落随手做。
                if (widget.asSchedule && (it.title.isEmpty || it.dueTime == 0)) {
                  StartApp.messengerKey.currentState?.showSnackBar(
                    SnackBar(
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: Colors.black87,
                      content: Text(
                          it.title.isEmpty ? '先写一句日程内容' : '选个日期和时间，才算一条日程',
                          style: const TextStyle(color: Colors.white)),
                      action: SnackBarAction(
                        label: '好',
                        textColor: const Color(0xFFFF6347),
                        onPressed: () {},
                      ),
                    ),
                  );
                  return;
                }
                if (it.isEmpty) {
                  StartStore.I.delete(it.id);
                } else {
                  await StartStore.I.put(it);
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: Container(
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(S.radius)),
                child: const Text('好了',
                    style: TextStyle(color: Colors.white, fontSize: S.textMd, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 选日期再选时间。[auto]=true 为新建日程自动触发：任一步取消即放弃整条日程。
  Future<void> _pickDue({bool auto = false}) async {
    final it = widget.item;
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: it.dueTime > 0 ? DateTime.fromMillisecondsSinceEpoch(widget.item.dueTime) : now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (d == null || !mounted) {
      if (auto) Navigator.pop(context);
      return;
    }
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
          it.dueTime > 0 ? DateTime.fromMillisecondsSinceEpoch(widget.item.dueTime) : now),
    );
    if (t == null || !mounted) {
      if (auto) Navigator.pop(context);
      return;
    }
    widget.item.dueTime =
        DateTime(d.year, d.month, d.day, t.hour, t.minute).millisecondsSinceEpoch;
    // 设了时间默认开到点提醒（编辑器里可随手关）。
    widget.item.alarm = true;
    // 念头设时间后自动变日程任务（保留原内容）。
    if (widget.item.isIdea) {
      widget.item.kind = Item.kindTask;
    }
    await StartStore.I.put(widget.item);
    if (mounted) {
      setState(() {});
      // 选完时间接着写标题，键盘自动就位。
      _titleFocus.requestFocus();
    }
  }

  static String _fmtDue(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final day = DateTime(d.year, d.month, d.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = day.difference(today).inDays;
    final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (diff == 0) return '今天 $hm';
    if (diff == 1) return '明天 $hm';
    return '${d.month}/${d.day} $hm';
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool danger;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.icon, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final color = danger ? c.accentDark : c.ink;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: S.sm, vertical: S.xs),
        decoration: BoxDecoration(
          color: c.cardAlt,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: S.xxs),
            Text(label, style: TextStyle(color: color, fontSize: S.textSm)),
          ],
        ),
      ),
    );
  }
}

/// 快速记一批：随手做任务 / 念头 / 捋一捋暂存。
/// 多行输入，回车换行多写几条，保存时按行与句末标点（。！？；…）自动拆开，
/// 各成一条直接存入对应分区——全局与动手吧 / 捋一捋同一拆分规则。
Future<void> showQuickAdd(BuildContext context, {bool idea = false, bool inbox = false}) {
  return showStartSheet(
    context,
    (_) => _QuickAdd(idea: idea, inbox: inbox),
  );
}

class _QuickAdd extends StatefulWidget {
  final bool idea;
  final bool inbox;
  const _QuickAdd({required this.idea, this.inbox = false});

  @override
  State<_QuickAdd> createState() => _QuickAddState();
}

class _QuickAddState extends State<_QuickAdd> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final pad = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(left: S.md, right: S.md, top: S.md, bottom: pad + S.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctl,
            autofocus: true,
            minLines: 1,
            maxLines: 6,
            style: TextStyle(fontSize: S.textLg, color: c.ink, height: 1.4),
            decoration: InputDecoration(
              hintText: widget.inbox
                  ? '先倒进来，回头再捋；换行多记几条'
                  : widget.idea
                      ? '一个念头一句话，换行多记几条'
                      : '记几件要做的事，换行多写几件',
              hintStyle: TextStyle(color: c.inkSoft),
              border: InputBorder.none,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: S.xxs),
            child: Text('回车换行多写几条，自动拆开各存一条',
                style: TextStyle(fontSize: S.textSm, color: c.inkSoft)),
          ),
          const SizedBox(height: S.sm),
          Pressable(
            onTap: () async {
              final chunks = splitIntoLines(_ctl.text);
              if (chunks.isNotEmpty) {
                final kind = widget.inbox
                    ? Item.kindInbox
                    : widget.idea
                        ? Item.kindIdea
                        : Item.kindTask;
                final now = DateTime.now().millisecondsSinceEpoch;
                for (var i = 0; i < chunks.length; i++) {
                  await StartStore.I.put(
                    Item(kind: kind, title: chunks[i], rank: -1, created: now + i),
                    touchRank: true,
                  );
                }
                if (widget.idea && StartStore.I.prefBool('haptic', true)) {
                  Native.vibrate(15);
                }
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: Container(
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(S.radius)),
              child: const Icon(Icons.check, size: 22, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// 纯文字编辑弹层：只改标题文本（暂存/念头快改用）。
Future<void> showTextEdit(BuildContext context, Item it, {VoidCallback? onSaved}) {
  return showStartSheet(
    context,
    (_) => _TextEditSheet(item: it, onSaved: onSaved),
  );
}

class _TextEditSheet extends StatefulWidget {
  final Item item;
  final VoidCallback? onSaved;
  const _TextEditSheet({required this.item, this.onSaved});

  @override
  State<_TextEditSheet> createState() => _TextEditSheetState();
}

class _TextEditSheetState extends State<_TextEditSheet> {
  late final _ctl = TextEditingController(text: widget.item.title);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ThemeTokens.of(context);
    final pad = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(left: S.md, right: S.md, top: S.md, bottom: pad + S.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctl,
            autofocus: true,
            maxLines: null,
            style: TextStyle(fontSize: S.textLg, color: c.ink, height: 1.4),
            decoration: InputDecoration(
              hintText: '改一改',
              hintStyle: TextStyle(color: c.inkSoft),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: S.md),
          Pressable(
            onTap: () async {
              final t = _ctl.text.trim();
              if (t.isNotEmpty && t != widget.item.title) {
                widget.item.title = t;
                await StartStore.I.put(widget.item);
              }
              if (context.mounted) Navigator.pop(context);
              widget.onSaved?.call();
            },
            child: Container(
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(S.radius)),
              child: const Icon(Icons.check, size: 22, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
