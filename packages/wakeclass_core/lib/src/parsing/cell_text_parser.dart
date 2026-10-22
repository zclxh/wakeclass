import 'week_parser.dart';

/// 单元格文本解析出的一门课程（未含星期/节次，由网格层补充）。
class ParsedCellCourse {
  const ParsedCellCourse({
    required this.name,
    required this.teacher,
    required this.location,
    required this.weekExpression,
    required this.warnings,
  });

  final String name;
  final String teacher;
  final String location;
  final WeekExpression weekExpression;

  /// 解析告警（周次缺失、教师/地点缺失等）。
  final List<String> warnings;

  List<int> get weeks => weekExpression.weeks;

  @override
  String toString() =>
      'ParsedCellCourse($name | $teacher | $location | $weeks)';
}

/// 周次行模式：数字区间/单值 + 周，或单双周/全周等关键字。
final _weekPattern = RegExp(
  r'\d{1,2}\s*[-—–~～至]\s*\d{1,2}\s*周?'
  r'|(?:第)?\d{1,2}\s*周'
  r'|单周|双周|全周|每周|全学期|整学期',
);

/// 地点关键字。
final _locationKeyRe = RegExp(r'楼|室|场|馆|教|区|中心|空间|厅|教室');

/// 教室编号（以 2-4 位数字结尾），如「教一101」「A-203」。
final _roomNumberRe = RegExp(r'[A-Za-z0-9-]?\d{2,4}$');

/// 人名模式：2-12 个汉字/拉丁字母/间隔号，不含数字。
final _teacherRe = RegExp(r'^[\u4e00-\u9fa5A-Za-z·]{2,12}$');

/// 分隔线（表格横线在 OCR 中常呈现为一串横线/等号）。
final _separatorRe = RegExp(r'^[-—_=·*~]{2,}$');

/// 单元格内噪声：段标题与节次标签（OCR 跨格合并时可能混入）。
/// 注意：早自习/晚自习是合法课程名，不在过滤之列。
final _noiseRe = RegExp(
  r'^(?:上午|下午|晚上|中午|早晨|第?[一二三]大节'
  r'|第?\d{1,2}(?:[-—–~～至]\d{1,2})?节)$',
);

/// 该行是否含周次表达式。
bool hasWeekPattern(String text) => _weekPattern.hasMatch(text);

/// 该行是否为地点行（周次行优先判定，地点次之）。
bool isLocationLine(String text) {
  if (hasWeekPattern(text)) return false;
  if (_locationKeyRe.hasMatch(text)) return true;
  return text.length <= 12 && _roomNumberRe.hasMatch(text);
}

/// 该行是否像人名（短、无数字、非周次/地点）。
bool isTeacherLike(String text) =>
    !hasWeekPattern(text) &&
    !isLocationLine(text) &&
    text.length <= 12 &&
    _teacherRe.hasMatch(text);

/// 该行是否为分隔线。
bool isSeparatorLine(String text) => _separatorRe.hasMatch(text);

/// 解析一个课表单元格的文本，返回其中包含的一门或多门课程。
///
/// 单元格文本来自 OCR 文本块聚合，行序保持屏幕顺序（从上到下）。
/// 支持单元格内多门课（按周次行分段）以及 `----` 分隔线分段。
///
/// 单元格典型格式（强智/正方教务系统）：
/// ```
/// 高数A
/// 张明
/// 1-16周(单)
/// 教一101
/// ```
List<ParsedCellCourse> parseCellText(String text, {int totalWeeks = 20}) {
  final lines = text
      .split(RegExp(r'[\r\n]+'))
      .map((l) => l.trim())
      .where(
          (l) => l.isNotEmpty && !isSeparatorLine(l) && !_noiseRe.hasMatch(l))
      .toList();
  if (lines.isEmpty) return const [];

  // 定位周次行。
  final weekIdx = <int>[];
  for (var i = 0; i < lines.length; i++) {
    if (hasWeekPattern(lines[i])) weekIdx.add(i);
  }

  // 划分条目（每门课一个条目，含起止行）。
  final entries = <List<int>>[];
  if (weekIdx.length <= 1) {
    entries.add([0, lines.length - 1]);
  } else {
    var entryStart = 0;
    for (var i = 0; i < weekIdx.length; i++) {
      final w = weekIdx[i];
      var nextStart = lines.length;
      if (i + 1 < weekIdx.length) {
        final wNext = weekIdx[i + 1];
        var j = w + 1;
        while (j < wNext) {
          final line = lines[j];
          if (isLocationLine(line)) {
            j++;
            continue;
          }
          if (isTeacherLike(line)) {
            // 人名行后面 2 行内若紧跟周次行，说明它是下一门课的字段
            // （例：「体育」→ 教师 → 周次），本条目在此结束。
            final hasWeekAhead =
                lines.skip(j + 1).take(2).any(hasWeekPattern);
            if (hasWeekAhead) break;
            j++;
            continue;
          }
          break;
        }
        nextStart = j;
      }
      entries.add([entryStart, nextStart - 1]);
      entryStart = nextStart;
    }
  }

  final result = <ParsedCellCourse>[];
  for (final range in entries) {
    result.add(_parseEntry(lines.sublist(range[0], range[1] + 1),
        totalWeeks: totalWeeks));
  }
  return result;
}

ParsedCellCourse _parseEntry(List<String> lines, {required int totalWeeks}) {
  final warnings = <String>[];

  // 周次。
  String? weekLine;
  for (final l in lines) {
    if (hasWeekPattern(l)) {
      weekLine = l;
      break;
    }
  }
  final weekExpr = weekLine == null
      ? parseWeeks(null, totalWeeks: totalWeeks)
      : parseWeeks(weekLine, totalWeeks: totalWeeks);
  if (weekExpr.isDefaulted) {
    warnings.add('未识别周次，已默认 1-$totalWeeks 周');
  }

  // 地点（取最后一个地点行，覆盖「多行地址」与「地点在周次之后」两种排布）。
  String location = '';
  for (final l in lines.reversed) {
    if (isLocationLine(l)) {
      location = l;
      break;
    }
  }

  // 课程名：第一个既不是周次也不是地点的行。
  String name = '';
  for (final l in lines) {
    if (!hasWeekPattern(l) && !isLocationLine(l)) {
      name = l;
      break;
    }
  }
  if (name.isEmpty) {
    // OCR 把多行粘成一行时，按词过滤周次与地点后取剩余。
    final tokens = lines.first
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .where((t) => !hasWeekPattern(t) && !isLocationLine(t))
        .toList();
    name = tokens.join(' ');
  }
  if (name.isEmpty) {
    name = '未命名课程';
    warnings.add('未识别课程名');
  }

  // 教师：与课程名不同的人名行。
  String teacher = '';
  for (final l in lines) {
    if (l != name && isTeacherLike(l) && !isLocationLine(l)) {
      teacher = l;
      break;
    }
  }
  if (teacher.isEmpty) warnings.add('未识别教师');
  if (location.isEmpty) warnings.add('未识别地点');

  return ParsedCellCourse(
    name: name,
    teacher: teacher,
    location: location,
    weekExpression: weekExpr,
    warnings: warnings,
  );
}
