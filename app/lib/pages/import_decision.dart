import 'package:wakeclass_core/wakeclass_core.dart';

import '../model/schedule_model.dart';

/// 校对页确认后的导入决定。
class ImportDecision {
  const ImportDecision({required this.courses, required this.replace});

  /// 确认导入的课程。
  final List<Course> courses;

  /// true = 覆盖导入；false = 追加导入。
  final bool replace;

  /// 把本次导入写进课表（覆盖 / 追加）。
  Future<void> applyTo(ScheduleModel model) async {
    if (replace) {
      await model.replaceCourses(courses);
    } else {
      await model.mergeCourses(courses);
    }
  }
}
