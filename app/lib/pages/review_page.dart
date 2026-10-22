import 'package:flutter/material.dart';
import 'package:wakeclass_core/wakeclass_core.dart';

import '../services/import/import_preview.dart';
import 'course_edit_page.dart';
import 'import_decision.dart';

/// 识别结果校对页：勾选课程、查看告警、编辑字段，最后确认导入。
///
/// 截图 OCR 与教务直连两条导入路线共用本页（统一输入 [ImportPreview]）。
class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, required this.preview, this.totalWeeks = 20});

  final ImportPreview preview;
  final int totalWeeks;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  late final List<Course> _courses = List.of(widget.preview.courses);
  final Set<String> _selected = <String>{};

  @override
  void initState() {
    super.initState();
    _selected.addAll(_courses.map((c) => c.id));
  }

  List<Course> get _chosen =>
      _courses.where((c) => _selected.contains(c.id)).toList();

  Future<void> _edit(Course course) async {
    final result = await Navigator.of(context).push<CourseEditResult>(
      MaterialPageRoute(builder: (_) => CourseEditPage(course: course)),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.delete && result.id != null) {
        _courses.removeWhere((c) => c.id == result.id);
        _selected.remove(result.id);
      } else if (result.course != null) {
        final idx = _courses.indexWhere((c) => c.id == result.course!.id);
        if (idx >= 0) _courses[idx] = result.course!;
        _selected.add(result.course!.id);
      }
    });
  }

  Future<void> _addNew() async {
    final result = await Navigator.of(context).push<CourseEditResult>(
      MaterialPageRoute(builder: (_) => const CourseEditPage()),
    );
    if (result?.course == null || !mounted) return;
    setState(() {
      _courses.add(result!.course!);
      _selected.add(result.course!.id);
    });
  }

  void _confirm(bool replace) {
    Navigator.of(context).pop(
      ImportDecision(courses: List.of(_chosen), replace: replace),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conflicts = findConflicts(_chosen);
    final hasIssues = widget.preview.warnings.isNotEmpty ||
        widget.preview.unassignedTexts.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('校对识别结果'),
        actions: [
          TextButton.icon(
            onPressed: _addNew,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('手动添加'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Column(
              children: [
                Text(
                  '识别出 ${_courses.length} 门课，已选 ${_selected.length} 门',
                  style: theme.textTheme.bodyMedium,
                ),
                if (widget.preview.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.preview.subtitle!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
                if (conflicts.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '⚠ 所选课程存在 ${conflicts.length} 处时间冲突',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                if (hasIssues)
                  _IssuesTile(
                    warnings: widget.preview.warnings,
                    unassigned: widget.preview.unassignedTexts,
                  ),
                for (final course in _courses)
                  _CourseRow(
                    course: course,
                    selected: _selected.contains(course.id),
                    onToggle: (value) => setState(() {
                      if (value) {
                        _selected.add(course.id);
                      } else {
                        _selected.remove(course.id);
                      }
                    }),
                    onTap: () => _edit(course),
                    onDelete: () => setState(() {
                      _courses.removeWhere((c) => c.id == course.id);
                      _selected.remove(course.id);
                    }),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          _selected.isEmpty ? null : () => _confirm(false),
                      icon: const Icon(Icons.playlist_add),
                      label: const Text('追加导入'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          _selected.isEmpty ? null : () => _confirm(true),
                      icon: const Icon(Icons.done_all),
                      label: const Text('覆盖导入'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IssuesTile extends StatelessWidget {
  const _IssuesTile({required this.warnings, required this.unassigned});

  final List<String> warnings;
  final List<String> unassigned;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = warnings.length + unassigned.length;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ExpansionTile(
        leading: Icon(Icons.warning_amber_rounded,
            color: theme.colorScheme.tertiary),
        title: Text('告警与未识别文本（$count）'),
        subtitle: const Text('点击展开查看，可在下方课程中手动修正'),
        children: [
          for (final w in warnings)
            ListTile(dense: true, title: Text(w, style: theme.textTheme.bodySmall)),
          for (final u in unassigned)
            ListTile(
              dense: true,
              leading: const Icon(Icons.help_outline, size: 18),
              title: Text(
                '未识别文本：$u',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

class _CourseRow extends StatelessWidget {
  const _CourseRow({
    required this.course,
    required this.selected,
    required this.onToggle,
    required this.onTap,
    required this.onDelete,
  });

  final Course course;
  final bool selected;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weekText =
        course.weeks.isEmpty ? '每周' : formatWeeks(course.weeks);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: (v) => onToggle(v ?? false),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(course.name,
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      '${course.dayText} ${course.periodText}'
                      ' · ${course.teacher.isEmpty ? '无教师' : course.teacher}'
                      ' · ${course.location.isEmpty ? '无地点' : course.location}'
                      ' · $weekText',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '移除',
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
