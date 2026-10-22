import 'dart:math';

final Random _random = Random();

/// 生成课程 id（时间戳 + 随机数，同批导入也不重复）。
String generateCourseId() =>
    'c-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
    '${_random.nextInt(0x7fffffff).toRadixString(36)}';

/// 生成课表 id。
String generateScheduleId() =>
    's-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

/// 按课程名稳定取色（0..19），同名课程颜色一致。
int colorIndexFor(String name) {
  var h = 0;
  for (final unit in name.codeUnits) {
    h = (h * 31 + unit) & 0x7fffffff;
  }
  return h % 20;
}
