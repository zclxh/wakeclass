import 'package:flutter/material.dart';
import 'package:wakeclass_core/wakeclass_core.dart';

import '../theme.dart';

/// 课程卡片上可执行的操作。
enum CourseAction { edit, delete }

/// 打开课程详情面板：查看信息、换颜色、编辑或删除。
///
/// [onColorSelected] 在用户点颜色时立即回调（课程颜色即时生效并落盘），
/// 返回值表示用户是否点了「编辑」/「删除」。
Future<CourseAction?> showCourseActionsSheet(
  BuildContext context, {
  required Course course,
  required PeriodSettings periods,
  required Future<void> Function(int colorIndex) onColorSelected,
}) {
  return showModalBottomSheet<CourseAction>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => CourseActionsSheet(
      course: course,
      periods: periods,
      onColorSelected: onColorSelected,
    ),
  );
}

/// 课程详情面板。
class CourseActionsSheet extends StatefulWidget {
  const CourseActionsSheet({
    super.key,
    required this.course,
    required this.periods,
    required this.onColorSelected,
  });

  final Course course;
  final PeriodSettings periods;
  final Future<void> Function(int colorIndex) onColorSelected;

  @override
  State<CourseActionsSheet> createState() => _CourseActionsSheetState();
}

class _CourseActionsSheetState extends State<CourseActionsSheet> {
  late int _colorIndex;

  @override
  void initState() {
    super.initState();
    _colorIndex = widget.course.colorIndex;
  }

  Future<void> _pickColor(int index) async {
    setState(() => _colorIndex = index);
    await widget.onColorSelected(index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final course = widget.course;
    final timeText = widget.periods.timeText(course.startPeriod).isEmpty
        ? ''
        : '${widget.periods.startOf(course.startPeriod)}-'
            '${widget.periods.endOf(course.endPeriod)}';
    final weeks = course.weeks.isEmpty
        ? '每周'
        : '${formatWeeks(course.weeks)}（共 ${course.weeks.length} 周）';
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: courseColor(_colorIndex),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    course.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [
                course.dayText,
                course.periodText,
                if (timeText.isNotEmpty) timeText,
              ].join(' · '),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            _InfoRow(icon: Icons.place_outlined, text: course.location.isEmpty ? '未填写地点' : course.location),
            _InfoRow(icon: Icons.person_outline, text: course.teacher.isEmpty ? '未填写教师' : course.teacher),
            _InfoRow(icon: Icons.date_range_outlined, text: weeks),
            if (course.note.trim().isNotEmpty)
              _InfoRow(icon: Icons.sticky_note_2_outlined, text: course.note.trim()),
            const SizedBox(height: 16),
            Text(
              '课程颜色',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < coursePalette.length; i++)
                  _ColorChip(
                    key: ValueKey('course-color-$i'),
                    color: coursePalette[i],
                    label: courseColorNames[i],
                    selected: i == _colorIndex,
                    onTap: () => _pickColor(i),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('course-edit'),
                    onPressed: () =>
                        Navigator.of(context).pop(CourseAction.edit),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('编辑课程'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('course-delete'),
                    onPressed: () =>
                        Navigator.of(context).pop(CourseAction.delete),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('删除'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// 颜色圆点（选中打勾）。
class _ColorChip extends StatelessWidget {
  const _ColorChip({
    super.key,
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.black12,
              width: selected ? 3 : 1,
            ),
          ),
          child: selected
              ? Icon(
                  Icons.check,
                  size: 20,
                  color: color.computeLuminance() > 0.6
                      ? Colors.black87
                      : Colors.white,
                )
              : null,
        ),
      ),
    );
  }
}
