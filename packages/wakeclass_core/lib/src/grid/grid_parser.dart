import 'dart:math' as math;

import '../models/course.dart';
import '../models/ocr_block.dart';
import '../models/raw_cell.dart';
import '../parsing/cell_text_parser.dart';
import '../parsing/period_times.dart';

/// 星期表头：`星期一` / `周二` / `礼拜三` / `星期日` / `星期天`。
final _dayHeaderRe = RegExp(r'(?:周|星期|礼拜)\s*([一二三四五六日天])');

/// 段标题（左列的上午/下午/晚上等），不参与网格。
final _groupLabelRe = RegExp(
  r'^(?:上午|下午|晚上|中午|早晨|早自习|晚自习|第一节|第一大节|第二大节|第[一二三]大节)$',
);

/// 节次行标签：`第1-2节` / `第3节` / 纯数字 `12` / 时间范围 `08:00-09:40`。
final _periodRangeRe = RegExp(r'^(?:第)?(\d{1,2})\s*[-—–~～至]\s*(\d{1,2})\s*节$');
final _periodSingleRe = RegExp(r'^(?:第)?(\d{1,2})\s*节$');
final _numberRe = RegExp(r'^\d{1,2}$');
final _timeRangeRe =
    RegExp(r'^(\d{1,2}:\d{2})\s*[-—–~～至]\s*(\d{1,2}:\d{2})$');
final _timeSingleRe = RegExp(r'^(\d{1,2}:\d{2})$');

class _Column {
  const _Column(this.day, this.left, this.right);
  final int day;
  final double left;
  final double right;
}

class _Row {
  const _Row(this.startPeriod, this.endPeriod, this.top, this.bottom);
  final int startPeriod;
  final int endPeriod;
  final double top;
  final double bottom;
}

/// 截图课表网格解析器：OCR 文本块 → 课程列表。
///
/// 流程：文本块分类 → 表头/节次行推断网格 → 文本块分配到单元格
/// （含合并单元格检测）→ 单元格文本解析 → 冲突检测。
///
/// 针对强智/正方教务系统课表截图（12 行节次 + 星期表头 + rowspan 合并）
/// 设计；坐标均为相对值（0..1），与图片分辨率无关。
class GridParser {
  const GridParser();

  GridParseResult parse(List<OcrTextBlock> blocks, {int totalWeeks = 20}) {
    final warnings = <String>[];
    final all = blocks.where((b) => b.text.trim().isNotEmpty).toList();

    // ---- 第 1 步：文本块分类 ----
    final headers = <OcrTextBlock>[];
    final periodLabels = <OcrTextBlock>[];
    final body = <OcrTextBlock>[];
    for (final b in all) {
      final t = b.text.trim();
      if (_groupLabelRe.hasMatch(t)) continue; // 上午/下午/晚上
      if (_isDayHeader(t)) {
        headers.add(b);
        continue;
      }
      if (_isPeriodLabel(b, t)) {
        periodLabels.add(b);
        continue;
      }
      body.add(b);
    }

    // ---- 第 2 步：列布局（星期） ----
    final columns = <_Column>[];
    if (headers.isNotEmpty) {
      final row = _headerRow(headers);
      final days = _daysOf(row);
      for (var i = 0; i < row.length; i++) {
        final h = row[i];
        final left = i == 0
            ? h.left - h.width / 2
            : (row[i - 1].centerX + h.centerX) / 2;
        final right = i == row.length - 1
            ? h.right + h.width / 2
            : (h.centerX + row[i + 1].centerX) / 2;
        columns.add(_Column(days[i], left, right));
      }
    } else {
      warnings.add('未检测到星期表头，无法确定课程所在星期');
    }

    // ---- 第 3 步：行布局（节次） ----
    final rows = <_Row>[];
    if (periodLabels.isNotEmpty) {
      final labels = periodLabels.toList()
        ..sort((a, b) => a.centerY.compareTo(b.centerY));
      for (var i = 0; i < labels.length; i++) {
        final (s, e) = _periodsOf(labels[i].text);
        if (s == 0) continue;
        final top = i == 0
            ? labels[i].top - labels[i].height / 2
            : (labels[i - 1].centerY + labels[i].centerY) / 2;
        final bottom = i == labels.length - 1
            ? labels[i].bottom + labels[i].height / 2
            : (labels[i].centerY + labels[i + 1].centerY) / 2;
        rows.add(_Row(s, e, top, bottom));
      }
    } else {
      warnings.add('未检测到节次列，无法确定上课节次');
    }

    // ---- 第 4 步：表体区域过滤 ----
    final headerBottom =
        headers.isEmpty ? -1.0 : headers.map((b) => b.bottom).reduce(math.max);
    final labelRight =
        periodLabels.isEmpty ? null : periodLabels.map((b) => b.right).reduce(math.max);
    final unassigned = <String>[];
    final bodyBlocks = <OcrTextBlock>[];
    for (final b in body) {
      final belowHeader = headerBottom < 0 || b.centerY > headerBottom;
      final rightOfLabels =
          labelRight == null || b.centerX > labelRight - 0.01;
      if (!belowHeader || !rightOfLabels) {
        unassigned.add(b.text.trim());
      } else {
        bodyBlocks.add(b);
      }
    }

    // ---- 第 5 步：文本块分配到单元格（含合并单元格检测） ----
    final cellBlocks = <String, List<OcrTextBlock>>{};
    final cellOrder = <String>[];
    final cellInfo = <String, (int, int, int)>{};
    for (final b in bodyBlocks) {
      final day = _columnFor(b, columns);
      if (day == 0) {
        unassigned.add(b.text.trim());
        continue;
      }
      final (r1, r2) = _rowsFor(b, rows);
      final key = 'd$day,r$r1-$r2';
      cellInfo.putIfAbsent(key, () => (day, r1, r2));
      cellBlocks.putIfAbsent(key, () => <OcrTextBlock>[]).add(b);
      if (!cellOrder.contains(key)) cellOrder.add(key);
    }

    // ---- 第 6 步：单元格聚合与解析 ----
    final cells = <RawCell>[];
    final courses = <Course>[];
    for (final key in cellOrder) {
      final blocksInCell = cellBlocks[key]!
        ..sort((a, b) {
          final byTop = a.top.compareTo(b.top);
          return byTop != 0 ? byTop : a.left.compareTo(b.left);
        });
      final rawText = blocksInCell
          .expand((b) => b.text.split(RegExp(r'[\r\n]+')))
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .join('\n');
      final (day, r1, r2) = cellInfo[key]!;
      final startPeriod = r1 < 0 ? 0 : rows[r1].startPeriod;
      final endPeriod = r1 < 0 ? 0 : rows[r2].endPeriod;
      cells.add(RawCell(
        day: day,
        startPeriod: startPeriod,
        endPeriod: endPeriod,
        rawText: rawText,
        blocks: blocksInCell,
      ));

      final parsed = parseCellText(rawText, totalWeeks: totalWeeks);
      for (final p in parsed) {
        final where = '${courseDayName(day)} 第$startPeriod-$endPeriod节';
        if (day == 0 || startPeriod == 0) {
          warnings.add('「${_short(rawText)}」缺少星期/节次信息，无法导入');
          continue;
        }
        final course = Course.create(
          name: p.name,
          teacher: p.teacher,
          location: p.location,
          weeks: p.weeks,
          dayOfWeek: day,
          startPeriod: startPeriod,
          endPeriod: endPeriod,
          source: 'ocr',
        );
        for (final w in p.warnings) {
          warnings.add('$where 「${p.name}」：$w');
        }
        courses.add(course);
      }
    }

    // ---- 第 7 步：冲突检测 ----
    for (var i = 0; i < courses.length; i++) {
      for (var j = i + 1; j < courses.length; j++) {
        if (courses[i].conflictsWith(courses[j])) {
          warnings.add('冲突：${courses[i].name} 与 ${courses[j].name} '
              '同在${courseDayName(courses[i].dayOfWeek)} '
              '第${courses[i].startPeriod}-${courses[i].endPeriod}节');
        }
      }
    }

    return GridParseResult(
      courses: courses,
      cells: cells,
      warnings: warnings,
      unassignedTexts: unassigned,
      layout: GridLayout(
        dayCount: columns.length,
        days: columns.map((c) => c.day).toList(),
        rowPeriodStarts: rows.map((r) => r.startPeriod).toList(),
        rowPeriodEnds: rows.map((r) => r.endPeriod).toList(),
        headerDetected: headers.isNotEmpty,
        periodColumnDetected: periodLabels.isNotEmpty,
      ),
    );
  }

  // ---------- 分类判定 ----------

  bool _isDayHeader(String t) {
    if (!_dayHeaderRe.hasMatch(t)) return false;
    if (t.contains('节')) return false;
    return !hasWeekPattern(t);
  }

  bool _isPeriodLabel(OcrTextBlock b, String t) {
    if (_periodRangeRe.hasMatch(t) || _periodSingleRe.hasMatch(t)) {
      return true;
    }
    if (_timeRangeRe.hasMatch(t) || _timeSingleRe.hasMatch(t)) return true;
    if (_numberRe.hasMatch(t)) {
      // 纯数字：仅当位于左侧窄条（节次列）时视为节次标签，
      // 避免把正文中的教室号/周次误判为行标签。
      return b.width <= 0.08 && b.left <= 0.3;
    }
    return false;
  }

  /// 表头可能因截图/OCR 出现多行重复，取最上方一行的星期序列。
  List<OcrTextBlock> _headerRow(List<OcrTextBlock> hs) {
    final sorted = hs.toList()..sort((a, b) => a.centerY.compareTo(b.centerY));
    final topY = sorted.first.centerY;
    final sameRow =
        sorted.where((b) => (b.centerY - topY).abs() <= 0.02).toList();
    final pick = sameRow.length >= 5 ? sameRow : sorted;
    pick.sort((a, b) => a.centerX.compareTo(b.centerX));
    return pick.length > 7 ? pick.sublist(0, 7) : pick;
  }

  /// 表头按 x 排序后映射星期编号；若首列是「日」（周日起始表）则整体平移。
  List<int> _daysOf(List<OcrTextBlock> hs) {
    final first = _dayNumberOf(hs.first.text);
    final shift = first - 1;
    return [for (var i = 0; i < hs.length; i++) (shift + i) % 7 + 1];
  }

  int _dayNumberOf(String text) {
    if (RegExp(r'[日天]').hasMatch(text)) return 7;
    final m = RegExp(r'[一二三四五六]').firstMatch(text);
    if (m == null) return 1;
    return '一二三四五六'.indexOf(m.group(0)!) + 1;
  }

  /// 节次标签 → (起始节, 结束节)；无法解析返回 (0, 0)。
  (int, int) _periodsOf(String text) {
    var m = _periodRangeRe.firstMatch(text);
    if (m != null) return (int.parse(m.group(1)!), int.parse(m.group(2)!));
    m = _periodSingleRe.firstMatch(text);
    if (m != null) {
      final p = int.parse(m.group(1)!);
      return (p, p);
    }
    m = _numberRe.firstMatch(text);
    if (m != null) {
      final p = int.parse(m.group(1)!);
      return (p, p);
    }
    m = _timeRangeRe.firstMatch(text);
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

  // ---------- 块分配 ----------

  /// 文本块所属列（星期）；无列或完全不在任何列时返回 0。
  int _columnFor(OcrTextBlock b, List<_Column> columns) {
    if (columns.isEmpty) return 0;
    var best = columns.first;
    var bestOverlap = b.horizontalOverlapWith(best.left, best.right);
    for (final c in columns.skip(1)) {
      final o = b.horizontalOverlapWith(c.left, c.right);
      if (o > bestOverlap) {
        best = c;
        bestOverlap = o;
      }
    }
    if (bestOverlap > 0) return best.day;
    // 中心点不在任何列内：取中心最近的列。
    var nearest = columns.first;
    var dist = _distToSpan(b.centerX, nearest.left, nearest.right);
    for (final c in columns.skip(1)) {
      final d = _distToSpan(b.centerX, c.left, c.right);
      if (d < dist) {
        dist = d;
        nearest = c;
      }
    }
    return nearest.day;
  }

  /// 文本块覆盖的网格行范围（首末行索引）；无行信息返回 (-1, -1)。
  ///
  /// 覆盖判定：块与行的重叠占块高 ≥ 30%，或占行高 ≥ 50%。
  /// 前者识别合并单元格（rowspan=2 的文本块横跨两行），
  /// 后者避免把恰好压线的行间文本误扩到相邻行。
  (int, int) _rowsFor(OcrTextBlock b, List<_Row> rows) {
    if (rows.isEmpty) return (-1, -1);
    var first = -1;
    var last = -1;
    for (var i = 0; i < rows.length; i++) {
      final overlap = b.verticalOverlapWith(rows[i].top, rows[i].bottom);
      final rowHeight = rows[i].bottom - rows[i].top;
      final blockRatio = b.height <= 0 ? 0.0 : overlap / b.height;
      final rowRatio = rowHeight <= 0 ? 0.0 : overlap / rowHeight;
      if (blockRatio >= 0.3 || rowRatio >= 0.5) {
        if (first < 0) first = i;
        last = i;
      }
    }
    if (first >= 0) return (first, last);
    // 中心点落在哪一行。
    for (var i = 0; i < rows.length; i++) {
      if (b.centerY >= rows[i].top && b.centerY <= rows[i].bottom) {
        return (i, i);
      }
    }
    // 取最近的行。
    var nearest = 0;
    var best = double.infinity;
    for (var i = 0; i < rows.length; i++) {
      final d = math.min(
        (b.centerY - rows[i].top).abs(),
        (b.centerY - rows[i].bottom).abs(),
      );
      if (d < best) {
        best = d;
        nearest = i;
      }
    }
    return (nearest, nearest);
  }

  double _distToSpan(double x, double left, double right) {
    if (x < left) return left - x;
    if (x > right) return x - right;
    return 0;
  }

  String _short(String s) =>
      s.length > 24 ? '${s.substring(0, 24)}…' : s;
}
