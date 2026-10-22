import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:wakeclass_core/wakeclass_core.dart';

import '../model/schedule_model.dart';
import '../model/theme_model.dart';
import '../services/notifications/reminders.dart';
import 'widget_settings_sheet.dart';

/// 设置页：学期信息、主题色、课程提醒、数据备份/恢复、清空课表。
class SettingsPage extends StatefulWidget {
  const SettingsPage(
      {super.key, required this.model, required this.themeModel});

  final ScheduleModel model;
  final ThemeModel themeModel;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _title;
  late DateTime _termStart;
  late int _totalWeeks;
  ReminderSettings _reminder = const ReminderSettings(
      enabled: false, leadMinutes: ReminderSettings.defaultLead);

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.model.schedule.title);
    _termStart = widget.model.schedule.termStart;
    _totalWeeks = widget.model.schedule.totalWeeks;
    _loadReminder();
  }

  Future<void> _loadReminder() async {
    final settings = await CourseReminderService.loadSettings();
    if (!mounted) return;
    setState(() => _reminder = settings);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.model.updateMeta(
      title: _title.text.trim().isEmpty ? '新学期课表' : _title.text.trim(),
      termStart: _termStart,
      totalWeeks: _totalWeeks,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存设置')),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _termStart,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2035, 12, 31),
      helpText: '选择第 1 周周一',
    );
    if (picked != null) {
      setState(() => _termStart = mondayOf(picked));
    }
  }

  Future<void> _setReminderEnabled(bool enabled) async {
    if (enabled) {
      await CourseReminderService.requestPermission();
    }
    final next = _reminder.copyWith(enabled: enabled);
    await CourseReminderService.saveSettings(next);
    await CourseReminderService.sync(widget.model.schedule, settings: next);
    if (!mounted) return;
    setState(() => _reminder = next);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(enabled ? '已开启课程提醒' : '已关闭课程提醒')),
    );
  }

  Future<void> _setLeadMinutes(int minutes) async {
    final next = _reminder.copyWith(leadMinutes: minutes);
    await CourseReminderService.saveSettings(next);
    await CourseReminderService.sync(widget.model.schedule, settings: next);
    if (!mounted) return;
    setState(() => _reminder = next);
  }

  Future<void> _export() async {
    final json = widget.model.exportJson();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('备份数据（JSON）'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(json),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: json));
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('复制'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _import() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('从备份恢复'),
        content: TextField(
          controller: controller,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: '粘贴备份的 JSON…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.model.importJson(controller.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已从备份恢复')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('恢复失败：$e')),
      );
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空课表'),
        content: const Text('将删除全部课程，且不可恢复。确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.model.clearAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateText = DateFormat('yyyy年M月d日').format(_termStart);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: '课表标题',
              hintText: '如：2026-2027学年第一学期',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: BorderSide(color: Theme.of(context).dividerColor),
            ),
            leading: const Icon(Icons.event),
            title: const Text('第 1 周周一（开学日）'),
            subtitle: Text(dateText),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _pickDate,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _totalWeeks,
            decoration: const InputDecoration(
              labelText: '学期总周数',
              border: OutlineInputBorder(),
            ),
            items: [
              for (var w = 16; w <= 22; w++)
                DropdownMenuItem(value: w, child: Text('$w 周')),
            ],
            onChanged: (v) => setState(() => _totalWeeks = v ?? 20),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('保存设置'),
          ),
          const SizedBox(height: 32),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: const Icon(Icons.palette_outlined),
            title: const Text('主题色'),
            subtitle: Text('当前：${widget.themeModel.preset.name}'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < themePresets.length; i++)
                  _ColorSwatch(
                    key: ValueKey('theme-$i'),
                    color: themePresets[i].seed,
                    selected: i == widget.themeModel.colorIndex,
                    onTap: () => widget.themeModel.setColorIndex(i),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          // 桌面小组件
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: const Icon(Icons.widgets_outlined),
            title: const Text('桌面小组件'),
            subtitle: const Text('自定义文字 / 尺寸 / 配色，一键添加到桌面'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showWidgetSettingsSheet(
              context,
              schedule: widget.model.schedule,
            ),
          ),
          const SizedBox(height: 8),
          const Divider(),
          // 课程提醒
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('课程提醒'),
            subtitle: Text(_reminder.enabled
                ? '课前 ${_reminder.leadMinutes} 分钟通知课程与教室'
                : '关闭'),
            trailing: Switch(
              value: _reminder.enabled,
              onChanged: _setReminderEnabled,
            ),
          ),
          if (_reminder.enabled)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButtonFormField<int>(
                initialValue: _reminder.leadMinutes,
                decoration: const InputDecoration(
                  labelText: '提前提醒时间',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final m in const [5, 10, 15, 30])
                    DropdownMenuItem(value: m, child: Text('提前 $m 分钟')),
                ],
                onChanged: (v) => _setLeadMinutes(v ?? 10),
              ),
            ),
          const SizedBox(height: 8),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('导出备份（JSON）'),
            subtitle: const Text('复制课表数据，用于换设备迁移'),
            onTap: _export,
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('从备份恢复'),
            subtitle: const Text('粘贴之前导出的 JSON'),
            onTap: _import,
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined),
            title: const Text('清空课表'),
            subtitle: const Text('删除全部课程，不可恢复'),
            onTap: _clear,
          ),
        ],
      ),
    );
  }
}

/// 主题色色块（选中带勾）。
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
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
            ? const Icon(Icons.check, color: Colors.white, size: 22)
            : null,
      ),
    );
  }
}
