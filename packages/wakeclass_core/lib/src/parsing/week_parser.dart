import 'dart:math' as math;

/// 周次表达式解析结果。
class WeekExpression {
  const WeekExpression(this.weeks, {this.isDefaulted = false});

  /// 解析出的周次集合（1 起始、升序、去重、已钳制到学期范围）。
  final List<int> weeks;

  /// 输入为空或无法解析时，是否用「1..totalWeeks」兜底。
  final bool isDefaulted;

  @override
  String toString() =>
      'WeekExpression($weeks${isDefaulted ? ', defaulted' : ''})';
}

/// 周次区间：`1-16周`、`3-15周(单)`、`1-8`、`第1-16周`。
final _rangeRe = RegExp(
  r'^(?:第)?(\d{1,2})\s*[-—–~～至]\s*(\d{1,2})\s*周?(?:\((?:单|双)\)|(?:单|双)周)?$',
);

/// 单个周次：`第3周`、`16周`、`5`。
final _singleRe =
    RegExp(r'^(?:第)?(\d{1,2})\s*周?(?:\((?:单|双)\)|(?:单|双)周)?$');

final _allRe = RegExp(r'全周|每周|全学期|整学期');
final _oddRe = RegExp(r'单周|\(单\)|单$');
final _evenRe = RegExp(r'双周|\(双\)|双$');
final _splitRe = RegExp(r'[,，、;；\s]+');

List<int> _allWeeks(int totalWeeks) =>
    List<int>.generate(totalWeeks, (i) => i + 1);

WeekExpression _defaulted(int totalWeeks) =>
    WeekExpression(_allWeeks(totalWeeks), isDefaulted: true);

/// 解析周次表达式（自 Web 版 [wakeclass] 移植并强化）。
///
/// 支持：
/// - `1-16周` → 1..16
/// - `1-16周(单)` / `3-15周(单)` / `单周` → 奇数周
/// - `2-16周(双)` / `双周` → 偶数周
/// - `1-8,10-16周` → 分段并集
/// - `第3周` → {3}
/// - `全周/每周/全学期` → 1..totalWeeks
/// - 纯数字列表 `1 2 3` → {1,2,3}
///
/// 输入为空或无法解析时，默认全学期并标记 [WeekExpression.isDefaulted]，
/// 由调用方决定是否告警。
WeekExpression parseWeeks(String? input, {int totalWeeks = 20}) {
  if (input == null || input.trim().isEmpty) return _defaulted(totalWeeks);
  final text = input.trim();
  if (_allRe.hasMatch(text)) return WeekExpression(_allWeeks(totalWeeks));

  final odd = !text.contains('单双周') && _oddRe.hasMatch(text);
  final even = !text.contains('单双周') && !odd && _evenRe.hasMatch(text);

  final tokens = text.split(_splitRe).where((t) => t.isNotEmpty);
  final set = <int>{};
  for (final token in tokens) {
    var m = _rangeRe.firstMatch(token);
    if (m != null) {
      final a = int.parse(m.group(1)!);
      final b = int.parse(m.group(2)!);
      final lo = math.min(a, b);
      final hi = math.max(a, b);
      for (var w = lo; w <= hi; w++) {
        if (w >= 1 && w <= totalWeeks) set.add(w);
      }
      continue;
    }
    m = _singleRe.firstMatch(token);
    if (m != null) {
      final w = int.parse(m.group(1)!);
      if (w >= 1 && w <= totalWeeks) set.add(w);
    }
  }

  if (set.isEmpty) {
    // 「单周」/「双周」单独出现：对全学期过滤。
    if (odd || even) {
      set.addAll(_allWeeks(totalWeeks));
    } else {
      return _defaulted(totalWeeks);
    }
  }

  var weeks = set.toList()..sort();
  if (odd) weeks = weeks.where((w) => w.isOdd).toList();
  if (even) weeks = weeks.where((w) => w.isEven).toList();
  if (weeks.isEmpty) return _defaulted(totalWeeks);
  return WeekExpression(List.unmodifiable(weeks));
}

/// 将周次集合格式化为可读文本（编辑页显示、导出用）。
///
/// 例如 `[1..16]` → `1-16周`，`[1,3,5,7]` → `1-7周(单)`，
/// `[1..8,10..16]` → `1-8周, 10-16周`。
String formatWeeks(List<int> weeks) {
  if (weeks.isEmpty) return '未设置';
  final sorted = [...weeks]..sort();

  // 按「连续（步长 1）」或「同奇偶连续（步长 2）」分段：
  // [1,3,5,7] 归并为一段，[1..8, 10..16] 归并为两段。
  final runs = <List<int>>[];
  for (final w in sorted) {
    if (runs.isEmpty) {
      runs.add([w]);
      continue;
    }
    final run = runs.last;
    final gap = w - run.last;
    final step = run.length >= 2 ? run[1] - run[0] : 0;
    if (run.length == 1 && gap >= 1 && gap <= 2) {
      run.add(w);
    } else if (run.length >= 2 && gap == step) {
      run.add(w);
    } else {
      runs.add([w]);
    }
  }

  final parts = <String>[];
  for (final run in runs) {
    final a = run.first;
    final b = run.last;
    if (a == b) {
      parts.add('$a周');
      continue;
    }
    final step = run[1] - run[0];
    if (step == 1) {
      parts.add('$a-$b周');
    } else {
      parts.add(a.isOdd ? '$a-$b周(单)' : '$a-$b周(双)');
    }
  }
  return parts.join(', ');
}
