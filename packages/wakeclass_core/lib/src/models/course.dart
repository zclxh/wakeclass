import '../parsing/period_times.dart';
import '../utils/ids.dart';

/// 一门课程（一个「课程单元」，即某天某节次的一段课程安排）。
///
/// 同一门课在一周内上多次会拆成多个 [Course] 记录（各自独立的
/// [dayOfWeek] / [startPeriod] / [endPeriod]），与教务系统课表单元格一一对应。
class Course {
  const Course({
    required this.id,
    required this.name,
    required this.teacher,
    required this.location,
    required this.weeks,
    required this.dayOfWeek,
    required this.startPeriod,
    required this.endPeriod,
    this.note = '',
    this.colorIndex = -1,
    this.source = 'manual',
  });

  /// 稳定唯一 id（[create] 自动生成；导入 JSON 时保留原值）。
  final String id;

  /// 课程名。
  final String name;

  /// 教师（可为空字符串）。
  final String teacher;

  /// 上课地点（可为空字符串）。
  final String location;

  /// 上课周次集合，1 起始、升序去重；空列表表示「每周」（全校学期）。
  final List<int> weeks;

  /// 星期几，1..7（周一 = 1）。0 表示未知（解析失败时）。
  final int dayOfWeek;

  /// 起始节次（含），1 起始。0 表示未知。
  final int startPeriod;

  /// 结束节次（含）。
  final int endPeriod;

  /// 备注。
  final String note;

  /// 配色索引（0..19），UI 按课程名稳定取色。
  final int colorIndex;

  /// 数据来源：`manual` / `ocr` / `mock` / `jwxt` / `file`。
  final String source;

  /// 创建新课程并自动生成 id、周次排序、配色。
  factory Course.create({
    required String name,
    String teacher = '',
    String location = '',
    List<int> weeks = const [],
    required int dayOfWeek,
    required int startPeriod,
    required int endPeriod,
    String note = '',
    int? colorIndex,
    String source = 'manual',
  }) {
    final sorted = [...weeks]..sort();
    return Course(
      id: generateCourseId(),
      name: name.trim(),
      teacher: teacher.trim(),
      location: location.trim(),
      weeks: List.unmodifiable(sorted),
      dayOfWeek: dayOfWeek,
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      note: note,
      colorIndex: colorIndex ?? colorIndexFor(name.trim()),
      source: source,
    );
  }

  /// 第 [week] 周是否上这门课。
  bool includesWeek(int week) => weeks.isEmpty || weeks.contains(week);

  /// 与 [other] 是否时间冲突：同一天、节次区间重叠、且周次有交集
  /// （任一周次列表为空视为「每周」，即与其他课程周次必然相交）。
  bool conflictsWith(Course other) {
    if (dayOfWeek != other.dayOfWeek) return false;
    if (endPeriod < other.startPeriod || other.endPeriod < startPeriod) {
      return false;
    }
    if (weeks.isEmpty || other.weeks.isEmpty) return true;
    return weeks.any(other.weeks.contains);
  }

  /// 节次文本，如「第1-2节」。
  String get periodText => periodLabel(startPeriod, endPeriod);

  /// 星期文本，如「周一」；未知时返回「未知」。
  String get dayText {
    const names = ['未知', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    if (dayOfWeek < 1 || dayOfWeek > 7) return names[0];
    return names[dayOfWeek];
  }

  Course copyWith({
    String? name,
    String? teacher,
    String? location,
    List<int>? weeks,
    int? dayOfWeek,
    int? startPeriod,
    int? endPeriod,
    String? note,
    int? colorIndex,
    String? source,
  }) {
    return Course(
      id: id,
      name: name ?? this.name,
      teacher: teacher ?? this.teacher,
      location: location ?? this.location,
      weeks: weeks != null ? List.unmodifiable([...weeks]..sort()) : this.weeks,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      startPeriod: startPeriod ?? this.startPeriod,
      endPeriod: endPeriod ?? this.endPeriod,
      note: note ?? this.note,
      colorIndex: colorIndex ?? this.colorIndex,
      source: source ?? this.source,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'teacher': teacher,
        'location': location,
        'weeks': weeks,
        'day_of_week': dayOfWeek,
        'start_period': startPeriod,
        'end_period': endPeriod,
        'note': note,
        'color_index': colorIndex,
        'source': source,
      };

  factory Course.fromJson(Map<String, dynamic> json) {
    final weeks = json['weeks'];
    return Course(
      id: json['id'] as String? ?? generateCourseId(),
      name: json['name'] as String? ?? '',
      teacher: json['teacher'] as String? ?? '',
      location: json['location'] as String? ?? '',
      weeks: [
        if (weeks is List) for (final w in weeks) (w as num).toInt(),
      ],
      dayOfWeek: (json['day_of_week'] as num?)?.toInt() ?? 0,
      startPeriod: (json['start_period'] as num?)?.toInt() ?? 0,
      endPeriod: (json['end_period'] as num?)?.toInt() ?? 0,
      note: json['note'] as String? ?? '',
      colorIndex: (json['color_index'] as num?)?.toInt() ?? -1,
      source: json['source'] as String? ?? 'manual',
    );
  }

  @override
  bool operator ==(Object other) {
    return other is Course &&
        other.id == id &&
        other.name == name &&
        other.teacher == teacher &&
        other.location == location &&
        _listEquals(other.weeks, weeks) &&
        other.dayOfWeek == dayOfWeek &&
        other.startPeriod == startPeriod &&
        other.endPeriod == endPeriod &&
        other.note == note &&
        other.source == source;
  }

  @override
  int get hashCode => Object.hash(id, name, teacher, location, dayOfWeek,
      startPeriod, endPeriod, note, source, Object.hashAll(weeks));

  @override
  String toString() => 'Course($dayText $periodText $name $location)';
}

bool _listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 兼容旧字段名 `week`（部分早期数据用单值周次）。
String courseDayName(int day) {
  const names = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  if (day < 1 || day > 7) return '未知';
  return names[day];
}

/// 与 [Course.dayText] 保持一致的周文本（供 UI 与测试共用）。
String weekDayName(int day) => courseDayName(day);

/// 仅日期相等的比较辅助（避免时区与时间部分干扰）。
bool sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
