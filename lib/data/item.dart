/// 一条记录：任务（可打勾、可排期、可拆步骤）或念头（随手速记）。
/// JSON 字段与老版 start_items.json 完全一致。
class Item {
  static const int kindTask = 0;
  static const int kindInbox = 1; // 动手吧暂存：语音/手动倾倒进来，待捋一捋分类
  static const int kindIdea = 2;

  int id;
  int kind;
  int parentId; // 所属大任务，0 表示顶层
  String title;
  String note;
  bool done;
  int dueTime; // 安排的开始时间（毫秒），0 表示随时
  int eventId;
  bool alarm;
  int alarmArmed;
  int created;
  int updated;
  int completedAt;
  /// 手动排序号：0=未排过（按时间排）；拖动后按 1..n 写入，新条目取最小值-1 保持置顶。
  int rank;

  Item({
    this.id = 0,
    this.kind = kindTask,
    this.parentId = 0,
    this.title = '',
    this.note = '',
    this.done = false,
    this.dueTime = 0,
    this.eventId = 0,
    this.alarm = false,
    this.alarmArmed = 0,
    this.created = 0,
    this.updated = 0,
    this.completedAt = 0,
    this.rank = 0,
  });

  bool get isIdea => kind == kindIdea;
  bool get isInbox => kind == kindInbox;
  bool get isEmpty => title.trim().isEmpty && note.trim().isEmpty;

  String get alarmLabel {
    final t = title.trim();
    if (t.isNotEmpty) return t;
    final n = note.trim();
    if (n.isNotEmpty) return n.split(RegExp(r'\r?\n')).first;
    return '启序';
  }

  factory Item.fromJson(Map<String, dynamic> j) => Item(
        id: _l(j['id']),
        kind: _l(j['kind']) == kindIdea
            ? kindIdea
            : (_l(j['kind']) == kindInbox ? kindInbox : kindTask),
        parentId: _l(j['parent']),
        title: j['title'] as String? ?? '',
        note: j['note'] as String? ?? '',
        done: j['done'] as bool? ?? false,
        dueTime: _l(j['due']),
        eventId: _l(j['event']),
        alarm: j['alarm'] as bool? ?? false,
        alarmArmed: _l(j['armed']),
        created: _l(j['created']),
        updated: _l(j['updated']),
        completedAt: _l(j['completed']),
        rank: _l(j['rank']),
      );

  static int _l(Object? v) => v is int ? v : (int.tryParse('${v ?? ''}') ?? 0);

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'parent': parentId,
        'title': title,
        'note': note,
        'done': done,
        'due': dueTime,
        'event': eventId,
        'alarm': alarm,
        'armed': alarmArmed,
        'created': created,
        'updated': updated,
        'completed': completedAt,
        'rank': rank,
      };

  Item copy() => Item.fromJson(toJson());
}
