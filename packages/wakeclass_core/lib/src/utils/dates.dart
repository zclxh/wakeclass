/// 某个日期所在周的周一（只保留日期部分）。
DateTime mondayOf(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

/// `yyyy-MM-dd` 格式化。
String formatDate(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// 解析 `yyyy-MM-dd` 或 ISO 日期；非法输入返回 2000-01-01（UI 层可再校验）。
DateTime parseDate(String s) {
  final parsed = DateTime.tryParse(s);
  if (parsed == null) return DateTime(2000, 1, 1);
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// 解析可空日期字符串；非法/空返回 null。
DateTime? parseDateOrNull(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  final parsed = DateTime.tryParse(s);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}
