import 'package:flutter/material.dart';
import 'package:wakeclass_core/wakeclass_core.dart';

/// 课程编辑页返回结果。
class CourseEditResult {
  const CourseEditResult.save(this.course) : delete = false, id = null;
  const CourseEditResult.delete(String this.id) : course = null, delete = true;

  /// 保存时携带的课程。
  final Course? course;

  /// 是否为删除操作。
  final bool delete;

  /// 删除的课程 id。
  final String? id;
}

/// 新增 / 编辑单门课程。
class CourseEditPage extends StatefulWidget {
  const CourseEditPage({
    super.key,
    this.course,
    this.totalWeeks = 20,
    this.periods,
  });

  /// 为空表示新增。
  final Course? course;
  final int totalWeeks;

  /// 作息设置（决定「开始节次」下拉里可选几节、各节时间）。
  final PeriodSettings? periods;

  @override
  State<CourseEditPage> createState() => _CourseEditPageState();
}

class _CourseEditPageState extends State<CourseEditPage> {
  late final TextEditingController _name;
  late final TextEditingController _teacher;
  late final TextEditingController _location;
  late final TextEditingController _weeks;
  late final TextEditingController _note;
  late int _day;
  late int _startPeriod;
  late int _endPeriod;

  PeriodSettings get _periods => widget.periods ?? PeriodSettings.defaults();

  int get _maxPeriod {
    var max = _periods.count;
    for (final p in [_startPeriod, _endPeriod]) {
      if (p > max) max = p;
    }
    return max;
  }

  bool get _isNew => widget.course == null;

  @override
  void initState() {
    super.initState();
    final c = widget.course;
    _name = TextEditingController(text: c?.name ?? '');
    _teacher = TextEditingController(text: c?.teacher ?? '');
    _location = TextEditingController(text: c?.location ?? '');
    _weeks = TextEditingController(
      text: (c == null || c.weeks.isEmpty) ? '' : formatWeeks(c.weeks),
    );
    _note = TextEditingController(text: c?.note ?? '');
    _day = c?.dayOfWeek ?? 1;
    _startPeriod = c?.startPeriod ?? 1;
    _endPeriod = c?.endPeriod ?? 2;
  }

  @override
  void dispose() {
    _name.dispose();
    _teacher.dispose();
    _location.dispose();
    _weeks.dispose();
    _note.dispose();
    super.dispose();
  }

  String get _weekPreview {
    final text = _weeks.text.trim();
    if (text.isEmpty) return '未填写：按每周上课处理';
    final expr = parseWeeks(text, totalWeeks: widget.totalWeeks);
    if (expr.isDefaulted) return '无法解析，将按 1-${widget.totalWeeks} 周导入';
    return '解析为：${formatWeeks(expr.weeks)}';
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入课程名')),
      );
      return;
    }
    final expr = parseWeeks(_weeks.text, totalWeeks: widget.totalWeeks);
    final end = _endPeriod < _startPeriod ? _startPeriod : _endPeriod;
    final course = widget.course == null
        ? Course.create(
            name: name,
            teacher: _teacher.text.trim(),
            location: _location.text.trim(),
            weeks: expr.weeks,
            dayOfWeek: _day,
            startPeriod: _startPeriod,
            endPeriod: end,
            note: _note.text.trim(),
            source: 'manual',
          )
        : widget.course!.copyWith(
            name: name,
            teacher: _teacher.text.trim(),
            location: _location.text.trim(),
            weeks: expr.weeks,
            dayOfWeek: _day,
            startPeriod: _startPeriod,
            endPeriod: end,
            note: _note.text.trim(),
            // 编辑时保留用户自定义的颜色，不要按课程名重置
            colorIndex: widget.course!.colorIndex,
            source: widget.course!.source.isEmpty
                ? 'manual'
                : widget.course!.source,
          );
    if (!mounted) return;
    Navigator.of(context).pop(CourseEditResult.save(course));
  }

  Future<void> _delete() async {
    final id = widget.course?.id;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除课程'),
        content: Text('确定删除「${widget.course!.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.of(context).pop(CourseEditResult.delete(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    const dayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? '添加课程' : '编辑课程'),
        actions: [
          if (!_isNew)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除课程',
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '课程名 *',
              hintText: '如：高等数学A',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _teacher,
            decoration: const InputDecoration(
              labelText: '教师',
              hintText: '如：张明远',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _location,
            decoration: const InputDecoration(
              labelText: '地点',
              hintText: '如：教一101',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _weeks,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '周次',
              hintText: '如：1-16周、3-15周(单)、1-8,10-16周',
              helperText: _weekPreview,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _day,
                  decoration: const InputDecoration(
                    labelText: '星期',
                  ),
                  items: [
                    for (var d = 1; d <= 7; d++)
                      DropdownMenuItem(value: d, child: Text(dayNames[d - 1])),
                  ],
                  onChanged: (v) => setState(() => _day = v ?? 1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _startPeriod,
                  decoration: const InputDecoration(
                    labelText: '开始节次',
                    isDense: true,
                  ),
                  items: [
                    for (var p = 1; p <= _maxPeriod; p++)
                      DropdownMenuItem(
                        value: p,
                        child: Text(
                          _periods.timeText(p).isEmpty
                              ? '第$p节'
                              : '第$p节 ${_periods.startOf(p)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _startPeriod = v ?? 1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _endPeriod,
                  decoration: const InputDecoration(
                    labelText: '结束节次',
                    isDense: true,
                  ),
                  items: [
                    for (var p = 1; p <= _maxPeriod; p++)
                      DropdownMenuItem(
                        value: p,
                        child: Text(
                          _periods.timeText(p).isEmpty
                              ? '第$p节'
                              : '第$p节 ${_periods.endOf(p)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) =>
                      setState(() => _endPeriod = v ?? _startPeriod),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: '备注（可选）',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
