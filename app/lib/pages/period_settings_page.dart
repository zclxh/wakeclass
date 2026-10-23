import 'package:flutter/material.dart';
import 'package:wakeclass_core/wakeclass_core.dart';

import '../model/period_model.dart';

/// 上课时间（作息）设置页。
///
/// - 按「第 1 节几点 + 每节多久 + 课间休息 + 每天几节」一键生成整天的作息；
/// - 也可以点某一节单独微调开始时间（各校第 3 节、下午第 1 节常有特殊安排）。
/// - 改动立即生效：课表时间轴、课程提醒、桌面小组件倒计时都用这一套时间。
class PeriodSettingsPage extends StatefulWidget {
  const PeriodSettingsPage({super.key, required this.model});

  final PeriodModel model;

  @override
  State<PeriodSettingsPage> createState() => _PeriodSettingsPageState();
}

class _PeriodSettingsPageState extends State<PeriodSettingsPage> {
  late PeriodSettings _settings;
  late String _firstStart;
  late int _duration;
  late int _break;
  late int _count;

  static const _durationOptions = [30, 35, 40, 45, 50, 55, 60];
  static const _breakOptions = [0, 5, 10, 15, 20];

  @override
  void initState() {
    super.initState();
    _settings = widget.model.settings;
    _firstStart = _settings.firstStart;
    _duration = _settings.durationMinutes;
    _break = _settings.breakMinutes;
    _count = _settings.count;
  }

  /// 按当前规则重新生成一整天的作息。
  Future<void> _regenerate() async {
    final next = PeriodSettings.uniform(
      firstStart: _firstStart,
      durationMinutes: _duration,
      breakMinutes: _break,
      count: _count,
    );
    setState(() => _settings = next);
    await widget.model.update(next);
  }

  Future<void> _pickFirstStart() async {
    final picked = await _pickTime(_firstStart);
    if (picked == null) return;
    setState(() => _firstStart = picked);
    await _regenerate();
  }

  Future<void> _pickPeriodStart(int period) async {
    final picked = await _pickTime(_settings.startOf(period));
    if (picked == null) return;
    final next = _settings.withStart(period, picked);
    setState(() {
      _settings = next;
      _firstStart = next.startOf(1);
    });
    await widget.model.update(next);
  }

  Future<String?> _pickTime(String initial) async {
    final parts = (minutesOfHhmm(initial) ?? 8 * 60);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: parts ~/ 60, minute: parts % 60),
      helpText: '选择上课时间',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return null;
    return formatHhmm(picked.hour * 60 + picked.minute);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('上课时间'),
        actions: [
          TextButton(
            onPressed: () async {
              await widget.model.resetToDefaults();
              if (!mounted) return;
              final next = widget.model.settings;
              setState(() {
                _settings = next;
                _firstStart = next.firstStart;
                _duration = next.durationMinutes;
                _break = next.breakMinutes;
                _count = next.count;
              });
            },
            child: const Text('恢复默认'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            '改完下面任意一项会按规则重新生成全天作息；生成后再点某一节即可单独微调。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          ListTile(
            key: const ValueKey('period-start-tile'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: const Text('第 1 节开始时间'),
            subtitle: Text(_firstStart),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _pickFirstStart,
          ),
          const Divider(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: const ValueKey('period-duration'),
                  initialValue: _duration,
                  decoration: const InputDecoration(
                    labelText: '每节时长',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final m in _durationOptions)
                      DropdownMenuItem(value: m, child: Text('$m 分钟')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _duration = v);
                    _regenerate();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: const ValueKey('period-break'),
                  initialValue: _break,
                  decoration: const InputDecoration(
                    labelText: '课间休息',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final m in _breakOptions)
                      DropdownMenuItem(value: m, child: Text('$m 分钟')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _break = v);
                    _regenerate();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            key: const ValueKey('period-count'),
            initialValue: _count,
            decoration: const InputDecoration(
              labelText: '每天几节课',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (var n = PeriodSettings.minCount; n <= PeriodSettings.maxCount; n++)
                DropdownMenuItem(value: n, child: Text('$n 节')),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _count = v);
              _regenerate();
            },
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            key: const ValueKey('period-regenerate'),
            onPressed: _regenerate,
            icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
            label: const Text('按规则重新生成'),
          ),
          const SizedBox(height: 20),
          Text(
            '各节时间',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '点任意一节可以单独改开始时间（例：下午第 1 节 14:00、晚上 19:00）。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          for (var p = 1; p <= _settings.count; p++)
            ListTile(
              key: ValueKey('period-row-$p'),
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  '$p',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              title: Text(
                '第 $p 节',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              trailing: Text(
                _settings.timeText(p),
                style: theme.textTheme.bodyMedium,
              ),
              onTap: () => _pickPeriodStart(p),
            ),
        ],
      ),
    );
  }
}
