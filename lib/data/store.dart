import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../channels/native.dart';
import 'item.dart';

/// 全局数据仓库：条目内存库 + 偏好缓存 + 落盘。
/// 数据格式与老版完全兼容：start_items.json / start_prefs / focus_min_* 历史。
class StartStore extends ChangeNotifier {
  StartStore._();
  static final StartStore I = StartStore._();

  static const fileJson = 'start_items.json';
  static const eulaVersion = 11;

  final List<Item> items = [];
  int seq = 1;
  Map<String, Object?> prefs = {};
  String _dir = '';
  String get dir => _dir;

  String get _filePath => '$_dir/$fileJson';

  Future<void> init() async {
    _dir = await PlatformIO.filesDir();
    prefs = await Prefs.getAll();
    try {
      final content = await PlatformIO.readFile(_filePath);
      if (content != null) {
        final root = jsonDecode(content) as Map<String, dynamic>;
        seq = _int(root['seq'], 1);
        final arr = root['items'] as List<dynamic>? ?? [];
        items
          ..clear()
          ..addAll(arr.whereType<Map<String, dynamic>>().map(Item.fromJson));
      }
    } catch (_) {}
    _ensureIds();
    await _purgeMedCalendarEvents();
  }

  /// 一次性迁移：服药计划不再写入系统日历。把历史版本写入的日历事件
  /// （cal_ids_* 偏好记录）逐个删除，并清掉全部 cal_ids_*/cal_sig_* 偏好。
  /// med_cal_purged_v1 标记防重复执行。
  Future<void> _purgeMedCalendarEvents() async {
    if (prefBool('med_cal_purged_v1')) return;
    final keys = prefs.keys
        .where((k) => k.startsWith('cal_ids_') || k.startsWith('cal_sig_'))
        .toList();
    for (final k in keys) {
      final v = prefs[k];
      if (k.startsWith('cal_ids_') && v is String) {
        for (final e in v.split(',')) {
          final id = int.tryParse(e.trim()) ?? 0;
          if (id > 0) await Native.calendarDelete(id);
        }
      }
      prefs.remove(k);
      await Prefs.set(k, null);
    }
    prefs['med_cal_purged_v1'] = true;
    await Prefs.set('med_cal_purged_v1', true);
  }

  void _ensureIds() {
    for (final it in items) {
      if (it.id >= seq) seq = it.id + 1;
    }
  }

  static int _int(Object? v, int d) => v is int ? v : (int.tryParse('${v ?? ''}') ?? d);

  // ---------------- 偏好 ----------------

  Object? pref(String k) => prefs[k];

  /// 供外部在直接改 prefs 缓存后通知刷新。
  void refresh() => notifyListeners();
  bool prefBool(String k, [bool d = false]) => prefs[k] as bool? ?? d;
  int prefInt(String k, [int d = 0]) => _int(prefs[k], d);
  double prefDouble(String k, [double d = 0]) {
    final v = prefs[k];
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse('${v ?? ''}') ?? d;
  }

  String prefStr(String k, [String d = '']) => prefs[k] as String? ?? d;

  Future<void> setPref(String k, Object? v) async {
    prefs[k] = v;
    await Prefs.set(k, v);
    notifyListeners();
  }

  // ---------------- 落盘 ----------------

  /// 启动重挂全部提醒（幂等）：滑掉卡片/强停/系统清后台会清掉 AlarmManager 里
  /// 全部闹钟，不重开机就永远不响——所以每次冷启动都重挂一遍。
  /// 任务只挂未来到点的；服药走 armMedPlanNotify（内部跳过过去时刻，不再写日历）。
  Future<void> rearmAll() async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    for (final it in List<Item>.from(items)) {
      if (it.kind == Item.kindTask && !it.done && it.dueTime > nowMs && it.alarm) {
        if (prefBool('notify_on', true)) {
          await Native.scheduleNotify(it.id, it.alarmLabel, it.dueTime);
        }
      } else if (it.isMed && it.parentId == 0) {
        await armMedPlanNotify(it);
      }
    }
  }

  String exportJson() {
    return const JsonEncoder.withIndent('  ').convert({
      'version': 4,
      'seq': seq,
      'items': items.map((e) => e.toJson()).toList(),
    });
  }

  Future<void> persist() async {
    try {
      await PlatformIO.writeFile(_filePath, exportJson());
    } catch (_) {}
  }

  Future<bool> restoreJson(String s) async {
    try {
      final root = jsonDecode(s) as Map<String, dynamic>;
      final arr = root['items'] as List<dynamic>?;
      if (arr == null) return false;
      var maxSeq = _int(root['seq'], 1);
      final parsed = arr.whereType<Map<String, dynamic>>().map(Item.fromJson).toList();
      for (final it in parsed) {
        if (it.id >= maxSeq) maxSeq = it.id + 1;
      }
      items
        ..clear()
        ..addAll(parsed);
      seq = maxSeq;
      await persist();
      for (final it in items) {
        if (it.kind == Item.kindTask && !it.done && it.dueTime > 0 && it.alarm) {
          await Native.scheduleNotify(it.id, it.alarmLabel, it.dueTime);
        } else if (it.isMed && it.parentId == 0) {
          await armMedPlanNotify(it);
        } else {
          await Native.cancelNotify(it.id);
        }
      }
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 清空全部，返回清空前快照 JSON 供撤销。
  Future<String> clearAll() async {
    final snap = exportJson();
    for (final it in items) {
      Native.cancelNotify(it.id);
      if (it.isMed && it.parentId == 0) cancelMedPlanNotify(it);
    }
    items.clear();
    seq = 1;
    await persist();
    notifyListeners();
    return snap;
  }

  /// 恢复出厂（Dart 侧）：取消全部提醒与日历事件、清内存库与偏好缓存、删落盘文件。
  /// 之后由 Native.factoryReset 清原生偏好文件并重启。
  Future<void> factoryReset() async {
    for (final it in List<Item>.from(items)) {
      Native.cancelNotify(it.id);
      if (it.isMed && it.parentId == 0) cancelMedPlanNotify(it);
    }
    items.clear();
    seq = 1;
    prefs.clear();
    try {
      await PlatformIO.deleteFile(_filePath);
    } catch (_) {}
    notifyListeners();
  }

  // ---------------- 条目操作 ----------------

  Item? byId(int id) {
    for (final it in items) {
      if (it.id == id) return it;
    }
    return null;
  }

  int _minRank() {
    var m = 0;
    for (final it in items) {
      if (it.rank < m) m = it.rank;
    }
    return m;
  }

  /// 新增或更新：新条目必须入库（items.add），同 id 不同实例则整体替换。
  /// 完成态维护 completedAt。
  Future<void> put(Item it, {bool touchRank = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = it.id > 0 ? byId(it.id) : null;
    if (existing == null) {
      it.id = seq++;
      // 批量新建（拆词/多行）会显式传 created=now+k 保证子步骤顺序，不能覆盖。
      if (it.created == 0) it.created = now;
      if (touchRank) it.rank = _minRank() - 1;
      items.add(it);
    } else if (!identical(existing, it)) {
      it.id = existing.id;
      it.created = existing.created;
      items[items.indexOf(existing)] = it;
    }
    it.updated = now;
    if (it.done && it.completedAt == 0) it.completedAt = now;
    if (!it.done) it.completedAt = 0;
    await persist();
    // 到点提醒：日程任务未完成、有时间且开了提醒 → 定时悬浮通知；否则撤销。
    if (it.kind == Item.kindTask &&
        !it.done &&
        it.dueTime > 0 &&
        it.alarm &&
        prefBool('notify_on', true)) {
      await Native.scheduleNotify(it.id, it.alarmLabel, it.dueTime);
    } else {
      await Native.cancelNotify(it.id);
    }
    notifyListeners();
  }

  /// 删除（cascade 时级联删子步骤），返回被删条目供撤销。
  List<Item> delete(int id, {bool cascade = true}) {
    final removed = <Item>[];
    void rec(int pid) {
      for (final it in List<Item>.from(items)) {
        if (it.parentId == pid) rec(it.id);
      }
      final it = byId(pid);
      if (it != null) {
        removed.add(it);
        items.remove(it);
      }
    }

    rec(id);
    persist();
    for (final it in removed) {
      Native.cancelNotify(it.id);
      // 服药计划的提醒挂在 计划id*10+i，一并取消，避免删除后仍然到点响。
      if (it.isMed && it.parentId == 0) cancelMedPlanNotify(it);
    }
    notifyListeners();
    return removed;
  }

  Future<void> restore(List<Item> snapshot) async {
    for (final it in snapshot) {
      if (byId(it.id) == null) items.add(it);
      if (it.id >= seq) seq = it.id + 1;
    }
    await persist();
    for (final it in snapshot) {
      if (it.kind == Item.kindTask && !it.done && it.dueTime > 0 && it.alarm) {
        await Native.scheduleNotify(it.id, it.alarmLabel, it.dueTime);
      } else if (it.isMed && it.parentId == 0) {
        await armMedPlanNotify(it);
      }
    }
    notifyListeners();
  }

  /// 批量删除（选择态），返回快照供整批撤销。
  Future<String> deleteAll(List<int> ids, {bool complete = false}) async {
    final snap = exportJson();
    for (final id in ids) {
      if (complete) {
        final it = byId(id);
        if (it != null && !it.done) {
          it.done = true;
          it.completedAt = DateTime.now().millisecondsSinceEpoch;
          await Native.cancelNotify(id);
        }
      } else {
        delete(id);
      }
    }
    await persist();
    notifyListeners();
    return snap;
  }

  /// 拖动排序：按给出的顺序写 rank 1..n。
  Future<void> reorder(List<int> orderedIds) async {
    for (var i = 0; i < orderedIds.length; i++) {
      final it = byId(orderedIds[i]);
      if (it != null) it.rank = i + 1;
    }
    await persist();
    notifyListeners();
  }

  // ---------------- 查询 ----------------

  void _sortByRank(List<Item> r) {
    r.sort((a, b) {
      if (a.rank != b.rank) return a.rank.compareTo(b.rank);
      return b.updated.compareTo(a.updated);
    });
  }

  /// 未完成任务：已排期升序在前，随时任务在后。
  List<Item> openTasks() {
    final timed = <Item>[];
    final anytime = <Item>[];
    for (final it in items) {
      if (it.isIdea || it.isInbox || it.isMed || it.done || it.parentId != 0) continue;
      if (it.dueTime > 0) {
        timed.add(it);
      } else {
        anytime.add(it);
      }
    }
    timed.sort((a, b) => a.dueTime.compareTo(b.dueTime));
    _sortByRank(anytime);
    return timed..addAll(anytime);
  }

  /// 全部"随手做"：顶层、未完成、无排期。
  List<Item> anytimeTasks() {
    final r = <Item>[];
    for (final it in items) {
      if (!it.isIdea && !it.isInbox && !it.isMed && !it.done && it.parentId == 0 && it.dueTime == 0) r.add(it);
    }
    _sortByRank(r);
    return r;
  }

  /// 动手吧暂存：待捋一捋分类的条目（语音/手动倾倒进来）。
  List<Item> inboxTasks() {
    final r = items.where((it) => it.isInbox && it.parentId == 0).toList();
    _sortByRank(r);
    return r;
  }

  /// 念头：拖过按 rank，否则按更新时间倒序。
  List<Item> ideas() {
    final r = items.where((it) => it.isIdea).toList();
    _sortByRank(r);
    return r;
  }

  /// 捋一捋子步骤：按创建时间正序。
  List<Item> subtasksOf(int parentId) {
    final r = items.where((it) => it.parentId == parentId).toList();
    r.sort((a, b) => a.created.compareTo(b.created));
    return r;
  }

  /// 子步骤进度：[已完成, 总数]。
  List<int> subtaskProgress(int parentId) {
    var done = 0, total = 0;
    for (final it in items) {
      if (it.parentId == parentId) {
        total++;
        if (it.done) done++;
      }
    }
    return [done, total];
  }

  // ---------------- 服药 ----------------

  /// 全部服药计划（顶层 kind=3）。
  List<Item> medPlans() {
    final r = items.where((it) => it.isMed && it.parentId == 0).toList();
    _sortByRank(r);
    return r;
  }

  /// 服药记录：parentId=计划id 的子项集合。
  List<Item> medLogsOf(int planId) =>
      items.where((it) => it.isMed && it.parentId == planId).toList();

  /// 解析服药计划 note JSON：{slots:[0,1,2], times:["08:00","12:30","21:00"], cat:"", dose:"1片", start:ms, end:ms}
  static Map<String, Object?> medPlanMeta(Item it) {
    if (!it.isMed || it.note.isEmpty) return const {};
    try {
      final j = jsonDecode(it.note);
      if (j is Map<String, Object?>) return j;
      if (j is Map) return j.cast<String, Object?>();
    } catch (_) {}
    return const {};
  }

  static String encodeMedPlan({
    List<int> slots = const [],
    required List<String> times,
    String cat = '',
    String dose = '',
    int start = 0,
    int end = 0,
  }) {
    return jsonEncode({
      if (slots.isNotEmpty) 'slots': slots,
      'times': times,
      'cat': cat,
      'dose': dose,
      'start': start,
      'end': end,
    });
  }

  // ---------------- 服药计划提醒 ----------------

  /// 服药计划提醒 id（与 Kotlin 侧 ReminderAlarm.medNotifyId 完全一致）：
  /// 1500000000 + 计划id*1000 + 天序*10 + 时段序。高位隔离带避免与任务通知 id
  /// （=条目 id）撞号；1000 步长支持最多 10 个自定义时段。旧版固定 plan.id*10+i
  /// 会跨天互相覆盖导致闹钟不响，已弃用，仅在取消/重挂时顺带清理遗留。
  int medNotifyId(int planId, int day, int slot) =>
      1500000000 + planId * 1000 + day * 10 + slot;

  static int _hMToMs(DateTime day, String t) {
    final parts = t.split(':');
    final h = int.tryParse(parts[0]) ?? 8;
    final min = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return DateTime(day.year, day.month, day.day, h, min).millisecondsSinceEpoch;
  }

  /// 此前写入日历的事件 id 列表（cal_ids_{planId} 逗号串）。
  List<int> _calEventIds(int planId) {
    final raw = prefs['cal_ids_$planId'] as String? ?? '';
    return raw
        .split(',')
        .map((e) => int.tryParse(e.trim()) ?? 0)
        .where((e) => e > 0)
        .toList();
  }

  /// 全部服药计划写入手机日历的事件 id 集合（cal_ids_* 偏好并集）。
  /// 首页「日程」合并手机日历时按此排除，服药数据只出现在服药页。
  Set<int> medCalendarEventIds() {
    final r = <int>{};
    prefs.forEach((k, v) {
      if (k.startsWith('cal_ids_') && v is String) {
        for (final e in v.split(',')) {
          final id = int.tryParse(e.trim()) ?? 0;
          if (id > 0) r.add(id);
        }
      }
    });
    return r;
  }

  /// 取消服药计划全部提醒：30 天 × 全时段新版 id + 旧版固定 id + 系统闹钟 + 日历事件。
  Future<void> cancelMedPlanNotify(Item plan) async {
    final meta = medPlanMeta(plan);
    final times = (meta['times'] as List?)?.cast<String>() ?? const [];
    final maxSlot = times.isEmpty ? 10 : times.length;
    for (var d = 0; d < 30; d++) {
      for (var i = 0; i < maxSlot; i++) {
        await Native.cancelNotify(medNotifyId(plan.id, d, i));
      }
    }
    for (var i = 0; i < 3; i++) {
      await Native.cancelNotify(plan.id * 10 + i);
    }
    // 清系统闹钟：按上次存的标题撤掉（防改名后旧闹钟残留）。
    final oldTitle = prefStr('alarm_title_${plan.id}', '');
    if (oldTitle.isNotEmpty) {
      await Native.dismissAlarm(oldTitle);
    }
    for (final eid in _calEventIds(plan.id)) {
      await Native.calendarDelete(eid);
    }
    prefs.remove('cal_ids_${plan.id}');
    prefs.remove('cal_sig_${plan.id}');
    prefs.remove('alarm_title_${plan.id}');
    await Prefs.set('cal_ids_${plan.id}', null);
    await Prefs.set('cal_sig_${plan.id}', null);
    await Prefs.set('alarm_title_${plan.id}', null);
  }

  /// 保存/编辑/恢复后重挂服药计划：
  /// 通知 = 逐日逐时段独立 id，30 天滚动窗口（notify_on 总开关控制）。
  /// 服药不写入系统日历；此处顺带清理历史版本写入的日历事件与签名偏好。
  Future<void> armMedPlanNotify(Item plan) async {
    final meta = medPlanMeta(plan);
    final times = (meta['times'] as List?)?.cast<String>() ?? const [];
    final start = (meta['start'] as int?) ?? 0;
    final end = (meta['end'] as int?) ?? 0;
    final label = '${plan.title} · ${(meta['dose'] as String?) ?? ''}'.trim();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final nowMs = now.millisecondsSinceEpoch;

    // 旧版固定 id 清理 + 新版全部撤销后重挂（时间/日期范围可能已改，防陈旧闹钟残留）。
    for (var i = 0; i < 3; i++) {
      await Native.cancelNotify(plan.id * 10 + i);
    }
    for (var d = 0; d < 30; d++) {
      for (var i = 0; i < times.length; i++) {
        await Native.cancelNotify(medNotifyId(plan.id, d, i));
      }
    }
    if (prefBool('notify_on', true)) {
      for (var d = 0; d < 30; d++) {
        final day = today.add(Duration(days: d));
        final dayMs = day.millisecondsSinceEpoch;
        if (start > 0 && dayMs < start) continue;
        if (end > 0 && dayMs > end) continue;
        for (var i = 0; i < times.length; i++) {
          final when = _hMToMs(day, times[i]);
          if (when <= nowMs) continue;
          await Native.scheduleNotify(medNotifyId(plan.id, d, i), label, when);
        }
      }
    }

    // 日历：服药不再写入系统日历。清理历史版本为该计划写入的日历事件，
    // 并清掉内容签名/事件 id 偏好（删除路径见 cancelMedPlanNotify）。
    for (final eid in _calEventIds(plan.id)) {
      await Native.calendarDelete(eid);
    }
    prefs.remove('cal_sig_${plan.id}');
    prefs.remove('cal_ids_${plan.id}');
    await Prefs.set('cal_sig_${plan.id}', null);
    await Prefs.set('cal_ids_${plan.id}', null);
  }

  // ---------------- 今日焦点 ----------------

  /// 本地日期的 epoch day（与 Java LocalDate.now().toEpochDay() 一致）。
  static int epochDay([DateTime? dt]) {
    final x = dt ?? DateTime.now();
    return DateTime(x.year, x.month, x.day)
        .difference(DateTime(1970, 1, 1))
        .inDays;
  }

  static String focusDayKey(int epochDay) {
    final d = DateTime(1970, 1, 1).add(Duration(days: epochDay));
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return 'focus_min_${d.year}-$m-$day';
  }

  Item? todayFocus() {
    final day = _int(prefs['focus_of_day'], -9223372036854775808);
    final id = _int(prefs['focus_of_day_id'], 0);
    if (day != epochDay() || id <= 0) return null;
    final it = byId(id);
    // 念头与服药一律不做今日焦点（服药只出现在服药页）。
    if (it == null || it.isIdea || it.isMed) {
      // 过期焦点静默清理：不 notify（调用方多在 build 期读取，notify 会打断构建）。
      prefs.remove('focus_of_day');
      prefs.remove('focus_of_day_id');
      Prefs.set('focus_of_day', null);
      Prefs.set('focus_of_day_id', null);
      return null;
    }
    return it;
  }

  Future<void> setFocus(int id) async {
    if (id <= 0) return clearFocus();
    await Prefs.set('focus_of_day', epochDay());
    await Prefs.set('focus_of_day_id', id);
    prefs['focus_of_day'] = epochDay();
    prefs['focus_of_day_id'] = id;
    notifyListeners();
  }

  Future<void> clearFocus() async {
    await Prefs.set('focus_of_day', null);
    await Prefs.set('focus_of_day_id', null);
    prefs.remove('focus_of_day');
    prefs.remove('focus_of_day_id');
    notifyListeners();
  }

  // ---------------- 专注统计 ----------------

  Future<void> addFocusMinutes(int minutes) async {
    final today = epochDay();
    final cur = _int(prefs['focus_day'], -1) == today ? _int(prefs['focus_min'], 0) : 0;
    final total = (cur + minutes).clamp(0, 1440);
    await Prefs.set('focus_day', today);
    await Prefs.set('focus_min', total);
    await Prefs.set(focusDayKey(today), total);
    prefs['focus_day'] = today;
    prefs['focus_min'] = total;
    prefs[focusDayKey(today)] = total;
    // 按日统计（1.5 起）：当天专注次数 + 各小时专注分布，供统计页按日期查看。
    final cntKey = focusDayKey(today).replaceFirst('focus_min_', 'focus_cnt_');
    final cnt = _int(prefs[cntKey], 0) + 1;
    final hrs = focusHoursOn(today);
    final h = DateTime.now().hour;
    hrs[h] = (hrs[h] + minutes).clamp(0, 1440);
    final hrsStr = hrs.join(',');
    final hrsKey = focusDayKey(today).replaceFirst('focus_min_', 'focus_hrs_');
    await Prefs.set(cntKey, cnt);
    await Prefs.set(hrsKey, hrsStr);
    prefs[cntKey] = cnt;
    prefs[hrsKey] = hrsStr;
    notifyListeners();
  }

  int todayFocusMinutes() =>
      _int(prefs['focus_day'], -1) == epochDay() ? _int(prefs['focus_min'], 0) : 0;

  /// 最近 7 天每天专注分钟，下标 0=6 天前，6=今天。
  List<int> focusMinutesLast7() {
    final r = List<int>.filled(7, 0);
    final today = epochDay();
    for (var i = 0; i < 7; i++) {
      r[6 - i] = _int(prefs[focusDayKey(today - i)], 0);
    }
    return r;
  }

  int totalFocusMinutes() {
    var sum = 0;
    prefs.forEach((k, v) {
      if (k.startsWith('focus_min_') && v is int) sum += v;
      if (k.startsWith('focus_min_') && v is double) sum += v.toInt();
    });
    return sum;
  }

  /// 近 7 天有专注记录的天数。
  int activeDaysLast7() {
    var n = 0;
    final today = epochDay();
    for (var i = 0; i < 7; i++) {
      if (_int(prefs[focusDayKey(today - i)], 0) > 0) n++;
    }
    return n;
  }

  /// 已完成顶层任务数。
  int completedTasksCount() => items
      .where((it) => it.parentId == 0 && !it.isIdea && it.done && it.completedAt > 0)
      .length;

  // ---------------- 按日统计（统计页左右滑动按日期查看） ----------------

  static int _dayStartMs(int epochDay) =>
      DateTime(1970, 1, 1).add(Duration(days: epochDay)).millisecondsSinceEpoch;

  /// 某天的专注分钟。
  int focusMinutesOn(int epochDay) => _int(prefs[focusDayKey(epochDay)], 0);

  /// 某天的专注次数（1.5 起记录，更早的日子为 0）。
  int focusCountOn(int epochDay) => _int(
      prefs[focusDayKey(epochDay).replaceFirst('focus_min_', 'focus_cnt_')], 0);

  /// 某天各小时专注分钟（24 格；1.5 起记录，更早的日子全 0）。
  List<int> focusHoursOn(int epochDay) {
    final raw =
        prefs[focusDayKey(epochDay).replaceFirst('focus_min_', 'focus_hrs_')];
    final r = List<int>.filled(24, 0);
    if (raw is String && raw.isNotEmpty) {
      final parts = raw.split(',');
      for (var i = 0; i < 24 && i < parts.length; i++) {
        r[i] = int.tryParse(parts[i]) ?? 0;
      }
    }
    return r;
  }

  /// 某天完成的顶层任务数（completedAt 落在当日）。
  int completedOn(int epochDay) {
    final lo = _dayStartMs(epochDay);
    final hi = lo + const Duration(days: 1).inMilliseconds;
    return items
        .where((it) =>
            it.parentId == 0 &&
            !it.isIdea &&
            it.done &&
            it.completedAt >= lo &&
            it.completedAt < hi)
        .length;
  }

  /// 某天新增的条目数（created 落在当日，含全部类型与步骤）。
  int createdOn(int epochDay) {
    final lo = _dayStartMs(epochDay);
    final hi = lo + const Duration(days: 1).inMilliseconds;
    return items.where((it) => it.created >= lo && it.created < hi).length;
  }

  /// 首次使用日期：Prefs 已存直取；老用户以现有数据（条目创建/完成时间、
  /// focus_min_* 历史键）里最早的一天回填，保证统计页覆盖全部使用周期。
  Future<DateTime> firstUseDate() async {
    final saved = _int(prefs['first_use'], 0);
    if (saved > 0) return DateTime.fromMillisecondsSinceEpoch(saved);
    var earliest = DateTime.now();
    for (final it in items) {
      for (final ts in [it.created, it.completedAt]) {
        if (ts > 0) {
          final d = DateTime.fromMillisecondsSinceEpoch(ts);
          if (d.isBefore(earliest)) earliest = d;
        }
      }
    }
    prefs.forEach((k, v) {
      if (k.startsWith('focus_min_')) {
        final p = k.substring(10).split('-');
        if (p.length == 3) {
          final d = DateTime(int.tryParse(p[0]) ?? 9999,
              int.tryParse(p[1]) ?? 1, int.tryParse(p[2]) ?? 1);
          if (d.isBefore(earliest)) earliest = d;
        }
      }
    });
    final day = DateTime(earliest.year, earliest.month, earliest.day);
    prefs['first_use'] = day.millisecondsSinceEpoch;
    await Prefs.set('first_use', day.millisecondsSinceEpoch);
    return day;
  }
}
