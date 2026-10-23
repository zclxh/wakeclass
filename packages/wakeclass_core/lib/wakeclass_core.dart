/// 醒课课程表核心领域逻辑（纯 Dart，零 Flutter 依赖）。
///
/// 分层：
/// - [Course] / [Schedule] / [OcrTextBlock]：领域模型
/// - [parseWeeks] / [parseCellText]：文本级解析
/// - [GridParser]：OCR 文本块 → 课表网格 → 课程列表（截图导入核心）
/// - [findConflicts]：课程冲突检测
library;

export 'src/models/course.dart';
export 'src/models/ocr_block.dart';
export 'src/models/raw_cell.dart';
export 'src/models/schedule.dart';
export 'src/parsing/cell_text_parser.dart';
export 'src/parsing/period_settings.dart';
export 'src/parsing/period_times.dart';
export 'src/parsing/week_parser.dart';
export 'src/grid/grid_parser.dart';
export 'src/conflict.dart';
export 'src/utils/dates.dart';
export 'src/utils/ids.dart';
