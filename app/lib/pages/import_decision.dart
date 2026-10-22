import 'package:wakeclass_core/wakeclass_core.dart';

/// 校对页确认后的导入决定。
class ImportDecision {
  const ImportDecision({required this.courses, required this.replace});

  /// 确认导入的课程。
  final List<Course> courses;

  /// true = 覆盖导入；false = 追加导入。
  final bool replace;
}
