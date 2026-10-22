/// 节次与上课时间的对应关系（国内高校常见作息，供展示与时间行标签推断）。
///
/// 各校作息略有差异，后续版本支持在设置中自定义。
class PeriodTime {
  const PeriodTime(this.period, this.start, this.end);

  /// 节次（1 起始）。
  final int period;

  /// 开始时间，'HH:mm'。
  final String start;

  /// 结束时间，'HH:mm'。
  final String end;
}

/// 默认节次时间：上午 08:00 起，下午 14:00 起，晚上 19:00 起。
const List<PeriodTime> defaultPeriodTimes = [
  PeriodTime(1, '08:00', '08:45'),
  PeriodTime(2, '08:55', '09:40'),
  PeriodTime(3, '10:10', '10:55'),
  PeriodTime(4, '11:05', '11:50'),
  PeriodTime(5, '14:00', '14:45'),
  PeriodTime(6, '14:55', '15:40'),
  PeriodTime(7, '16:10', '16:55'),
  PeriodTime(8, '17:05', '17:50'),
  PeriodTime(9, '19:00', '19:45'),
  PeriodTime(10, '19:55', '20:40'),
  PeriodTime(11, '20:50', '21:35'),
  PeriodTime(12, '21:45', '22:30'),
];

PeriodTime? _find(int period) {
  for (final t in defaultPeriodTimes) {
    if (t.period == period) return t;
  }
  return null;
}

/// 某节次的上课时间文本，如「08:00-08:45」；未知节次返回空串。
String periodTimeText(int period) {
  final t = _find(period);
  return t == null ? '' : '${t.start}-${t.end}';
}

/// 由上课开始时间找节次，如 '08:00' → 1；找不到返回 null。
int? periodByStartTime(String hhmm) {
  for (final t in defaultPeriodTimes) {
    if (t.start == hhmm) return t.period;
  }
  return null;
}

/// 由下课结束时间找节次，如 '09:40' → 2；找不到返回 null。
int? periodByEndTime(String hhmm) {
  for (final t in defaultPeriodTimes) {
    if (t.end == hhmm) return t.period;
  }
  return null;
}

/// 节次区间文本，如「第1-2节」「第3节」；0 表示未知。
String periodLabel(int start, int end) {
  if (start <= 0) return '节次未知';
  if (end <= start) return '第$start节';
  return '第$start-$end节';
}
