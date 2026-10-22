import 'package:wakeclass_core/wakeclass_core.dart';

import '../jwxt/jwxt_types.dart';

/// 导入预览：截图 OCR 与教务直连两条路线产出的统一中间结果，
/// 供「识别校对页」展示与人工修正。
class ImportPreview {
  const ImportPreview({
    required this.courses,
    this.warnings = const [],
    this.unassignedTexts = const [],
    this.subtitle,
  });

  /// 解析出的课程。
  final List<Course> courses;

  /// 告警（周次缺失、字段缺失、冲突、学期提示等）。
  final List<String> warnings;

  /// 未能识别的文本（截图路线）。
  final List<String> unassignedTexts;

  /// 附加说明（如识别引擎名、学期标签），展示在校对页顶部。
  final String? subtitle;

  /// 由网格解析结果构造（截图路线）。
  factory ImportPreview.fromGridParseResult(GridParseResult result) {
    return ImportPreview(
      courses: result.courses,
      warnings: result.warnings,
      unassignedTexts: result.unassignedTexts,
    );
  }

  /// 由教务直连结果构造。
  factory ImportPreview.fromJwxtResult(JwxtImportResult result) {
    return ImportPreview(
      courses: result.courses,
      warnings: result.warnings,
      subtitle: result.semesterLabel ?? result.systemName,
    );
  }

  /// 复制并替换附加说明。
  ImportPreview withSubtitle(String? subtitle) {
    return ImportPreview(
      courses: courses,
      warnings: warnings,
      unassignedTexts: unassignedTexts,
      subtitle: subtitle,
    );
  }
}
