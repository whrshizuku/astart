import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../channels/native.dart';
import 'item.dart';

/// 全局数据仓库：条目内存库 + 偏好缓存 + 落盘。
/// 数据格式与老版完全兼容：start_items.json / start_prefs / focus_min_* 历史。
class StartStore extends ChangeNotifier {
  StartStore._();
  static final StartStore I = StartStore._();

  static const fileJson = 'start_items.json';
  static const eulaVersion = 8;

  final List<Item> items = [];
  int seq = 1;
  Map<String, Object?> prefs = {};
  String _dir = '';
  String get dir => _dir;

  File get _file => File('$_dir/$fileJson');

  Future<void> init() async {
    _dir = await Native.filesDir();
    prefs = await Prefs.getAll();
    try {
      if (await _file.exists()) {
        final root = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
        seq = _int(root['seq'], 1);
        final arr = root['items'] as List<dynamic>? ?? [];
        items
          ..clear()
          ..addAll(arr.whereType<Map<String, dynamic>>().map(Item.fromJson));
      }
    } catch (_) {}
    _ensureIds();
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

  String exportJson() {
    return const JsonEncoder.withIndent('  ').convert({
      'version': 4,
      'seq': seq,
      'items': items.map((e) => e.toJson()).toList(),
    });
  }

  Future<void> persist() async {
    try {
      final tmp = File('$_dir/$fileJson.tmp');
      await tmp.writeAsString(exportJson(), flush: true);
      await tmp.rename(_file.path);
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
    items.clear();
    seq = 1;
    await persist();
    notifyListeners();
    return snap;
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
      it.created = now;
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
      if (it.isIdea || it.isInbox || it.done || it.parentId != 0) continue;
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
      if (!it.isIdea && !it.isInbox && !it.done && it.parentId == 0 && it.dueTime == 0) r.add(it);
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
    if (it == null || it.isIdea) {
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
}
