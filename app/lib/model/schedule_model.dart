import 'package:flutter/material.dart';
import 'package:wakeclass_core/wakeclass_core.dart';

import '../services/storage/schedule_store.dart';
import '../services/widget/widget_bridge.dart';

/// 课表状态模型：持有当前课表与展示周次，负责持久化。
class ScheduleModel extends ChangeNotifier {
  ScheduleModel(this._store);

  final ScheduleStore _store;

  Schedule _schedule = Schedule.empty();
  bool _loaded = false;

  /// 展示周次偏移：0 = 本周，正负为前后偏移。
  int _weekOffset = 0;

  bool get loaded => _loaded;
  Schedule get schedule => _schedule;
  int get weekOffset => _weekOffset;

  /// 当前展示的教学周（1 起始，钳制到学期范围）。
  int get displayWeek {
    final current = _schedule.currentWeek();
    final target = current + _weekOffset;
    return target.clamp(1, _schedule.totalWeeks);
  }

  /// 是否为当前周。
  bool get isCurrentWeek => displayWeek == _schedule.currentWeek();

  Future<void> init() async {
    _schedule = await _store.load();
    _loaded = true;
    notifyListeners();
  }

  void shiftWeek(int delta) {
    _weekOffset += delta;
    notifyListeners();
  }

  void backToCurrentWeek() {
    if (_weekOffset == 0) return;
    _weekOffset = 0;
    notifyListeners();
  }

  /// 覆盖导入（识别结果直接替换现有课表）。
  Future<void> replaceCourses(List<Course> courses) async {
    _schedule = _schedule.copyWith(
      courses: List.of(courses),
      updatedAt: DateTime.now(),
    );
    await _store.save(_schedule);
    _afterSave();
    notifyListeners();
  }

  /// 追加导入（与现有课表合并，冲突保留由 UI 提示）。
  Future<int> mergeCourses(List<Course> courses) async {
    final existing = _schedule.courses;
    var added = 0;
    final merged = List<Course>.of(existing);
    for (final c in courses) {
      final duplicate = existing.any((e) =>
          e.name == c.name &&
          e.dayOfWeek == c.dayOfWeek &&
          e.startPeriod == c.startPeriod &&
          _weeksEqual(e.weeks, c.weeks));
      if (!duplicate) {
        merged.add(c);
        added++;
      }
    }
    _schedule = _schedule.copyWith(
      courses: merged,
      updatedAt: DateTime.now(),
    );
    await _store.save(_schedule);
    _afterSave();
    notifyListeners();
    return added;
  }

  /// 更新/删除单门课程。
  Future<void> upsertCourse(Course course) async {
    final list = List<Course>.of(_schedule.courses);
    final idx = list.indexWhere((c) => c.id == course.id);
    if (idx >= 0) {
      list[idx] = course;
    } else {
      list.add(course);
    }
    _schedule = _schedule.copyWith(courses: list, updatedAt: DateTime.now());
    await _store.save(_schedule);
    _afterSave();
    notifyListeners();
  }

  Future<void> removeCourse(String id) async {
    final list =
        _schedule.courses.where((c) => c.id != id).toList();
    _schedule = _schedule.copyWith(courses: list, updatedAt: DateTime.now());
    await _store.save(_schedule);
    _afterSave();
    notifyListeners();
  }

  /// 更新学期信息（标题/开学日/总周数）。
  Future<void> updateMeta(
      {String? title, DateTime? termStart, int? totalWeeks}) async {
    _schedule = _schedule.copyWith(
      title: title,
      termStart: termStart,
      totalWeeks: totalWeeks,
      updatedAt: DateTime.now(),
    );
    await _store.save(_schedule);
    _afterSave();
    notifyListeners();
  }

  /// 清空课表。
  Future<void> clearAll() async {
    _schedule = _schedule.copyWith(courses: const [], updatedAt: DateTime.now());
    await _store.save(_schedule);
    _afterSave();
    notifyListeners();
  }

  String exportJson() => _store.encode(_schedule);

  Future<void> importJson(String raw) async {
    _schedule = _store.decode(raw);
    await _store.save(_schedule);
    _afterSave();
    notifyListeners();
  }

  /// 课表已保存后：通知刷新桌面小组件。
  void _afterSave() {
    WidgetBridge.refresh();
  }

  bool _weeksEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
