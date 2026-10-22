import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeclass_core/wakeclass_core.dart';

/// 课表本地存储：`shared_preferences` 中保存单课表 JSON。
///
/// 单学期课表规模（10-40 门课）远小于 JSON 文件性能瓶颈，
/// 数据结构已为后续升级 sqflite 预留（id、updatedAt 字段齐全）。
class ScheduleStore {
  static const _key = 'wakeclass_schedule_v1';

  Future<Schedule> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return Schedule.empty();
      return decode(raw);
    } catch (_) {
      return Schedule.empty();
    }
  }

  Future<void> save(Schedule schedule) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, encode(schedule));
  }

  String encode(Schedule schedule) => jsonEncode(schedule.toJson());

  Schedule decode(String raw) {
    try {
      final map = jsonDecode(raw);
      if (map is Map<String, dynamic>) return Schedule.fromJson(map);
    } catch (_) {
      // 数据损坏时回退空课表
    }
    return Schedule.empty();
  }
}
