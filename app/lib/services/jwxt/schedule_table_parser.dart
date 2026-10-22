import 'package:html/dom.dart';
import 'package:html/parser.dart' show parse;
import 'package:wakeclass_core/wakeclass_core.dart';

/// 教务课表页 HTML 表格 → 课程列表。
///
/// 移植自 Web 版 `wakeclass`（public/js/parser.js 的表格解析逻辑）：
/// 定位课表表格 → 表头（星期列）→ 行首节次标签 → 遍历单元格
/// （处理 rowspan/colspan 合并）→ 单元格文本交给 core 的 [parseCellText]
/// 解析出课程名/教师/周次/地点。
class ScheduleTableParser {
  const ScheduleTableParser();

  static final _dayCellRe =
      RegExp(r'^(?:星期|周|礼拜)\s*([一二三四五六日天])$');
  static final _dayHeaderRe = RegExp(r'(?:星期|周|礼拜)\s*[一二三四五六日天]');
  static final _periodCellRe =
      RegExp(r'^(?:第)?(\d{1,2})\s*(?:[-—–~～至]\s*(\d{1,2}))?\s*节$');
  static final _periodCnRe = RegExp(
      r'^第?([一二三四五六七八九十]+)\s*(?:[-—–~～至]\s*([一二三四五六七八九十]+))?\s*节课?$');
  static const _cnDigits = <String, int>{
    '一': 1, '二': 2, '三': 3, '四': 4, '五': 5,
    '六': 6, '七': 7, '八': 8, '九': 9, '十': 10,
  };
  static final _numberCellRe = RegExp(r'^\d{1,2}$');
  static final _timeCellRe = RegExp(
      r'^(\d{1,2}:\d{2})\s*[-—–~～至]\s*(\d{1,2}:\d{2})$');
  static final _timeSingleRe = RegExp(r'^(\d{1,2}:\d{2})$');

  /// 解析结果：课程列表与告警。
  /// [cleanCellText] 可选：解析前对单元格文本做清洗（如 URP 的按钮噪声行）。
  ({List<Course> courses, List<String> warnings}) parseSchedule(String html,
      {String source = 'jwxt',
      int totalWeeks = 20,
      String Function(String cellText)? cleanCellText}) {
    final document = parse(html);
    final table = _findScheduleTable(document);
    if (table == null) {
      return (courses: const [], warnings: const ['页面中没有找到课表表格']);
    }
    final (courses, warnings) = _parseTable(table,
        source: source, totalWeeks: totalWeeks, cleanCellText: cleanCellText);
    return (courses: courses, warnings: warnings);
  }

  // ---------- 表格定位 ----------

  Element? _findScheduleTable(Document document) {
    Element? best;
    var bestScore = 0.0;
    for (final table in document.querySelectorAll('table')) {
      final score = _scoreTable(table);
      if (score > bestScore) {
        best = table;
        bestScore = score;
      }
    }
    return best;
  }

  /// 课表表格评分：行数 × 星期列数 + 节次命中加权。
  double _scoreTable(Element table) {
    final rows = table.querySelectorAll('tr');
    final text = table.text;
    var dayCells = 0;
    for (final row in rows) {
      for (final cell in row.children) {
        if (_dayCellRe.hasMatch(cell.text.trim())) dayCells++;
      }
    }
    if (dayCells < 3) return 0;
    final periodHits =
        RegExp(r'第?\s*\d{1,2}\s*(?:[-—–~～至]\s*\d{1,2})?\s*节')
            .allMatches(text)
            .length;
    final titleBonus =
        text.contains('节次') || text.contains('课表') ? 100.0 : 0.0;
    return rows.length * dayCells.toDouble() + periodHits * 10 + titleBonus;
  }

  // ---------- 表格解析 ----------

  (List<Course>, List<String>) _parseTable(Element table,
      {required String source,
      required int totalWeeks,
      String Function(String cellText)? cleanCellText}) {
    final warnings = <String>[];
    final rows = table.querySelectorAll('tr').toList();
    if (rows.isEmpty) return (const [], const ['课表表格为空']);

    // 表头行：星期 → 列号。
    final dayByColumn = <int, int>{};
    for (final row in rows) {
      var col = 0;
      for (final cell in row.children) {
        final colspan = int.tryParse(cell.attributes['colspan'] ?? '') ?? 1;
        if (_dayHeaderRe.hasMatch(cell.text.trim())) {
          final day = _dayNumber(cell.text.trim());
          for (var k = 0; k < colspan; k++) {
            dayByColumn[col + k] = day;
          }
        }
        col += colspan;
      }
      if (dayByColumn.length >= 3) break;
    }
    if (dayByColumn.isEmpty) {
      return (const [], const ['课表表格中没有识别到星期表头']);
    }

    // 第一遍：每行的节次（行首标签）。
    final rowPeriods = <(int, int)>[];
    var prevEnd = 0;
    for (final row in rows) {
      String? firstCellText;
      for (final cell in row.children) {
        firstCellText = _cellText(cell).trim();
        break;
      }
      final (s, e) = _periodsOf(firstCellText ?? '');
      if (s != 0) {
        rowPeriods.add((s, e));
        prevEnd = e;
      } else if (rowPeriods.isEmpty) {
        rowPeriods.add((0, 0));
      } else {
        // 行首不是节次标签（合并单元格延续行等）：沿用上一行区间。
        rowPeriods.add((prevEnd + 1, prevEnd + 1));
      }
    }

    // 第二遍：遍历单元格（处理 rowspan 占用）。
    final carry = <int, int>{}; // 列号 → 剩余 rowspan（不含当前行）
    final courses = <Course>[];
    final blocks = <(int day, int rowStart, int rowspan, String text)>[];
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      var col = 0;
      for (final cell in row.children) {
        while ((carry[col] ?? 0) > 0) {
          carry[col] = carry[col]! - 1;
          if (carry[col] == 0) carry.remove(col);
          col++;
        }
        final colspan = int.tryParse(cell.attributes['colspan'] ?? '') ?? 1;
        final rowspan = int.tryParse(cell.attributes['rowspan'] ?? '') ?? 1;
        final text = _cellText(cell).trim();
        if (text.isNotEmpty) {
          final day = dayByColumn[col];
          if (_dayCellRe.hasMatch(text)) {
            // 表头行（星期一…）：跳过。
          } else if (day == null) {
            // 节次/段标题列：忽略（节次已由第一遍处理）。
          } else if (day == 0) {
            warnings.add('第${r + 1}行第${col + 1}列无法定位星期：$text');
          } else {
            blocks.add((day, r, rowspan, text));
          }
        }
        if (rowspan > 1) carry[col] = rowspan - 1;
        col += colspan;
      }
    }

    // 第三遍：单元格文本 → 课程。
    for (final block in blocks) {
      final (day, rowStart, rowspan, text) = block;
      final startPeriod = _safePeriod(rowPeriods, rowStart)?.$1 ?? 0;
      final endPeriod = _safePeriod(rowPeriods, rowStart + rowspan - 1)?.$2 ??
          (_safePeriod(rowPeriods, rowStart)?.$2 ?? startPeriod);
      if (startPeriod == 0) {
        warnings.add('${courseDayName(day)} 节次未知，跳过：「${_short(text)}」');
        continue;
      }
      final cleaned = cleanCellText?.call(text) ?? text;
      final parsed = parseCellText(cleaned, totalWeeks: totalWeeks);
      for (final p in parsed) {
        final course = Course.create(
          name: p.name,
          teacher: p.teacher,
          location: p.location,
          weeks: p.weeks,
          dayOfWeek: day,
          startPeriod: startPeriod,
          endPeriod: endPeriod,
          source: source,
        );
        for (final w in p.warnings) {
          warnings.add(
              '${courseDayName(day)} 第$startPeriod-$endPeriod节「${p.name}」：$w');
        }
        courses.add(course);
      }
    }

    return (courses, warnings);
  }

  (int, int)? _safePeriod(List<(int, int)> rowPeriods, int row) {
    if (row < 0 || row >= rowPeriods.length) return null;
    final p = rowPeriods[row];
    return p.$1 == 0 ? null : p;
  }

  /// 节次标签 → (起始节, 结束节)。
  (int, int) _periodsOf(String text) {
    var m = _periodCellRe.firstMatch(text);
    if (m != null) {
      final s = int.parse(m.group(1)!);
      final e = m.group(2) != null ? int.parse(m.group(2)!) : s;
      return (s, e);
    }
    // 中文数字节次：第一节课 / 第十二节课。
    m = _periodCnRe.firstMatch(text);
    if (m != null) {
      final s = _cnNumber(m.group(1)!);
      if (s != null) {
        final e = m.group(2) != null ? _cnNumber(m.group(2)!) : null;
        return (s, e ?? s);
      }
    }
    m = _numberCellRe.firstMatch(text);
    if (m != null) {
      final p = int.parse(m.group(1)!);
      return (p, p);
    }
    m = _timeCellRe.firstMatch(text);
    if (m != null) {
      final s = periodByStartTime(m.group(1)!) ?? 0;
      final e = periodByEndTime(m.group(2)!) ?? 0;
      if (s != 0 && e != 0) return (s, e);
      if (s != 0) return (s, s);
      if (e != 0) return (e, e);
      return (0, 0);
    }
    m = _timeSingleRe.firstMatch(text);
    if (m != null) {
      final s = periodByStartTime(m.group(1)!) ??
          periodByEndTime(m.group(1)!) ??
          0;
      return (s, s);
    }
    return (0, 0);
  }

  /// 中文数字 → 整数（支持 一..十、十一..十九、二十..九十九）。
  int? _cnNumber(String s) {
    if (s.isEmpty) return null;
    final single = _cnDigits[s];
    if (single != null) return single;
    if (s.startsWith('十') && s.length == 2) {
      final unit = _cnDigits[s.substring(1)];
      if (unit != null) return 10 + unit;
    }
    if (s.length == 3 && s[1] == '十') {
      final tens = _cnDigits[s[0]];
      final unit = _cnDigits[s[2]];
      if (tens != null && unit != null) return tens * 10 + unit;
    }
    return null;
  }

  int _dayNumber(String text) {
    if (RegExp(r'[日天]').hasMatch(text)) return 7;
    final m = RegExp(r'[一二三四五六]').firstMatch(text);
    if (m == null) return 0;
    return '一二三四五六'.indexOf(m.group(0)!) + 1;
  }

  /// 单元格 → 文本：`<br>`/`<hr>` 转为换行。
  String _cellText(Element cell) {
    final buf = StringBuffer();
    void walk(Node node) {
      if (node is Text) {
        buf.write(node.text);
        return;
      }
      if (node is Element) {
        if (node.localName == 'br' || node.localName == 'hr') {
          buf.write('\n');
          return;
        }
        for (final child in node.nodes) {
          walk(child);
        }
      }
    }

    walk(cell);
    return buf.toString();
  }

  String _short(String s) => s.length > 20 ? '${s.substring(0, 20)}…' : s;
}
