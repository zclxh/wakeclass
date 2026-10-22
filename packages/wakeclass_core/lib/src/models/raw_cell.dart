import 'course.dart';
import 'ocr_block.dart';

/// 网格解析中间产物：一个（星期, 节次区间）单元格及其聚合后的原始文本。
///
/// 供「识别校对页」展示与人工修正使用。
class RawCell {
  const RawCell({
    required this.day,
    required this.startPeriod,
    required this.endPeriod,
    required this.rawText,
    required this.blocks,
  });

  /// 星期几，1..7；0 = 未知（未检测到表头列）。
  final int day;

  /// 起始节次；0 = 未知（未检测到节次行）。
  final int startPeriod;

  /// 结束节次（含）。
  final int endPeriod;

  /// 单元格聚合后的原始 OCR 文本（按行拼接）。
  final String rawText;

  /// 组成该单元格的 OCR 文本块（按 top, left 排序）。
  final List<OcrTextBlock> blocks;

  String get periodText => startPeriod == 0
      ? '节次未知'
      : (startPeriod == endPeriod ? '第$startPeriod节' : '第$startPeriod-$endPeriod节');

  String get dayText {
    const names = ['星期未知', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    if (day < 1 || day > 7) return names[0];
    return names[day];
  }

  @override
  String toString() => 'RawCell($dayText $periodText: "$rawText")';
}

/// 检测到的网格布局信息（用于调试与 UI 提示）。
class GridLayout {
  const GridLayout({
    required this.dayCount,
    required this.days,
    required this.rowPeriodStarts,
    required this.rowPeriodEnds,
    required this.headerDetected,
    required this.periodColumnDetected,
  });

  /// 检测到的列数（星期数）。
  final int dayCount;

  /// 每列对应的星期编号（1..7）。
  final List<int> days;

  /// 每个网格行的起始节次。
  final List<int> rowPeriodStarts;

  /// 每个网格行的结束节次。
  final List<int> rowPeriodEnds;

  /// 是否检测到星期表头。
  final bool headerDetected;

  /// 是否检测到节次列。
  final bool periodColumnDetected;
}

/// 网格解析的最终结果。
class GridParseResult {
  const GridParseResult({
    required this.courses,
    required this.cells,
    required this.warnings,
    required this.unassignedTexts,
    required this.layout,
  });

  /// 解析成功的课程单元（已生成 id，source = 'ocr'）。
  final List<Course> courses;

  /// 全部识别到的单元格（含解析失败、仅作展示的单元格）。
  final List<RawCell> cells;

  /// 解析过程中的告警（周次缺失、字段缺失、冲突等），供校对页展示。
  final List<String> warnings;

  /// 未能分配到网格的文本块内容，供校对页人工处理。
  final List<String> unassignedTexts;

  final GridLayout layout;

  @override
  String toString() =>
      'GridParseResult(${courses.length} courses, ${cells.length} cells, '
      '${warnings.length} warnings, ${unassignedTexts.length} unassigned)';
}
