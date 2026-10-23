import 'dart:convert';

import 'period_times.dart';

/// 作息设置：每节课的开始时间 + 单节时长。
///
/// 各校作息差异很大（第 3 节可能是 09:50 也可能是 10:10、午休一小时还是两小时），
/// 所以这里保存**每一节自己的开始时间**，而不是只保存「几点上课 + 每节多久」。
/// 同时保留生成参数（[firstStart] / [breakMinutes]），方便在设置页里
/// 「按规则重新生成」一整天的作息。
///
/// 时间统一用 `HH:mm` 文本，便于直接写入 JSON / shared_preferences，
/// 原生桌面小组件也按同样格式解析。
class PeriodSettings {
  const PeriodSettings({
    required this.starts,
    this.durationMinutes = defaultDuration,
    this.firstStart = '08:00',
    this.breakMinutes = defaultBreak,
  });

  /// 每一节的开始时间（`HH:mm`），下标 0 = 第 1 节。
  final List<String> starts;

  /// 单节课时长（分钟），所有节次相同。
  final int durationMinutes;

  /// 生成参数：第 1 节开始时间。
  final String firstStart;

  /// 生成参数：课间休息（分钟）。
  final int breakMinutes;

  static const int defaultDuration = 45;
  static const int defaultBreak = 10;
  static const int minDuration = 20;
  static const int maxDuration = 120;
  static const int minCount = 4;
  static const int maxCount = 16;

  /// 默认作息（与 [defaultPeriodTimes] 一致）。
  factory PeriodSettings.defaults() => PeriodSettings(
        starts: [for (final t in defaultPeriodTimes) t.start],
      );

  /// 按「第 1 节开始 + 每节时长 + 课间休息」生成一整天的作息。
  factory PeriodSettings.uniform({
    String firstStart = '08:00',
    int durationMinutes = defaultDuration,
    int breakMinutes = defaultBreak,
    int count = 12,
  }) {
    final startMinute = minutesOfHhmm(firstStart) ?? 8 * 60;
    final step = durationMinutes + breakMinutes;
    final n = count.clamp(minCount, maxCount);
    return PeriodSettings(
      starts: [
        for (var i = 0; i < n; i++) formatHhmm(startMinute + i * step),
      ],
      durationMinutes: durationMinutes.clamp(minDuration, maxDuration),
      firstStart: formatHhmm(startMinute),
      breakMinutes: breakMinutes,
    );
  }

  int get count => starts.length;

  /// 第 [period] 节的开始时间（`HH:mm`），越界返回空串。
  String startOf(int period) {
    if (period < 1 || period > starts.length) return '';
    return starts[period - 1];
  }

  /// 第 [period] 节的结束时间（`HH:mm`），越界返回空串。
  String endOf(int period) {
    final start = minutesOfHhmm(startOf(period));
    if (start == null) return '';
    return formatHhmm(start + durationMinutes);
  }

  /// 第 [period] 节的时间文本，如 `08:00-08:45`；越界返回空串。
  String timeText(int period) {
    final start = startOf(period);
    if (start.isEmpty) return '';
    return '$start-${endOf(period)}';
  }

  /// 第 [period] 节开始时刻（0:00 起的分钟数）。
  int? startMinute(int period) => minutesOfHhmm(startOf(period));

  /// 第 [period] 节结束时刻（0:00 起的分钟数）。
  int? endMinute(int period) {
    final start = startMinute(period);
    return start == null ? null : start + durationMinutes;
  }

  /// 从第 [period] 节开始到结束的分钟数（用于课表块高度比例）。
  int get totalMinutes => count * (durationMinutes + breakMinutes);

  PeriodSettings copyWith({
    List<String>? starts,
    int? durationMinutes,
    String? firstStart,
    int? breakMinutes,
  }) {
    return PeriodSettings(
      starts: starts == null ? this.starts : List.unmodifiable(starts),
      durationMinutes: durationMinutes ?? this.durationMinutes,
      firstStart: firstStart ?? this.firstStart,
      breakMinutes: breakMinutes ?? this.breakMinutes,
    );
  }

  /// 修改某一节的开始时间（其余节次不变）。
  PeriodSettings withStart(int period, String hhmm) {
    final minute = minutesOfHhmm(hhmm);
    if (minute == null || period < 1 || period > starts.length) return this;
    final next = [...starts];
    next[period - 1] = formatHhmm(minute);
    return copyWith(starts: next);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'starts': starts,
        'duration': durationMinutes,
        'first_start': firstStart,
        'break': breakMinutes,
      };

  factory PeriodSettings.fromJson(Map<String, dynamic> json) {
    final rawStarts = json['starts'];
    final parsed = <String>[];
    if (rawStarts is List) {
      for (final item in rawStarts) {
        if (item is! String) continue;
        final minute = minutesOfHhmm(item);
        if (minute == null) continue;
        parsed.add(formatHhmm(minute));
      }
    }
    final fallback = PeriodSettings.defaults();
    final duration = (json['duration'] as num?)?.toInt() ?? defaultDuration;
    final breakMinutes = (json['break'] as num?)?.toInt() ?? defaultBreak;
    final firstStart = json['first_start'] as String? ?? fallback.firstStart;
    return PeriodSettings(
      starts: parsed.length >= minCount
          ? List.unmodifiable(parsed.take(maxCount).toList())
          : fallback.starts,
      durationMinutes: duration.clamp(minDuration, maxDuration),
      firstStart: minutesOfHhmm(firstStart) == null
          ? fallback.firstStart
          : formatHhmm(minutesOfHhmm(firstStart)!),
      breakMinutes: breakMinutes.clamp(0, 120),
    );
  }

  /// 序列化为 JSON 文本（写入 shared_preferences，原生端按同样结构解析）。
  String encode() => jsonEncode(toJson());

  /// 从 JSON 文本解析；空串或格式错误时返回默认作息。
  static PeriodSettings decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return PeriodSettings.defaults();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return PeriodSettings.fromJson(decoded);
      }
    } catch (_) {
      // 数据损坏时退回默认作息
    }
    return PeriodSettings.defaults();
  }

  @override
  bool operator ==(Object other) {
    if (other is! PeriodSettings) return false;
    if (other.durationMinutes != durationMinutes) return false;
    if (other.starts.length != starts.length) return false;
    for (var i = 0; i < starts.length; i++) {
      if (other.starts[i] != starts[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(durationMinutes, Object.hashAll(starts));

  @override
  String toString() =>
      'PeriodSettings(${starts.length} 节, 每节 $durationMinutes 分钟, 第 1 节 ${starts.isEmpty ? '-' : starts.first})';
}

/// `HH:mm` → 自 0:00 起的分钟数；格式非法返回 null。
int? minutesOfHhmm(String text) {
  final parts = text.trim().split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return hour * 60 + minute;
}

/// 自 0:00 起的分钟数 → `HH:mm`（超出一天按 24 小时取模）。
String formatHhmm(int minutes) {
  final normalized = ((minutes % (24 * 60)) + 24 * 60) % (24 * 60);
  final hour = normalized ~/ 60;
  final minute = normalized % 60;
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
