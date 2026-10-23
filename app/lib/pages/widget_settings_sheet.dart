import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakeclass_core/wakeclass_core.dart';

import '../services/widget/widget_bridge.dart';
import '../services/widget/widget_settings.dart';
import '../theme.dart';

/// 打开「桌面小组件」设置面板（文字 / 尺寸 / 配色 / 一键添加）。
Future<void> showWidgetSettingsSheet(
  BuildContext context, {
  required Schedule schedule,
  PeriodSettings? periods,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => WidgetSettingsSheet(schedule: schedule, periods: periods),
  );
}

/// 桌面小组件设置面板。
class WidgetSettingsSheet extends StatefulWidget {
  const WidgetSettingsSheet({super.key, required this.schedule, this.periods});

  final Schedule schedule;

  /// 作息设置（决定预览里的上课时间）。
  final PeriodSettings? periods;

  @override
  State<WidgetSettingsSheet> createState() => _WidgetSettingsSheetState();
}

class _WidgetSettingsSheetState extends State<WidgetSettingsSheet> {
  final TextEditingController _title = TextEditingController();
  final ScrollController _scroll = ScrollController();
  WidgetSettings? _settings;
  Timer? _saveTimer;
  String? _hint;

  /// 是否展开手动添加步骤（MIUI / HyperOS 等桌面不会弹窗，只能手动添加）。
  bool _showGuide = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _title.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final fallback = widget.schedule.title.trim().isEmpty
        ? WidgetSettings.defaultTitle
        : widget.schedule.title;
    final settings = await WidgetSettings.load(fallbackTitle: fallback);
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _title.text = settings.title;
    });
  }

  /// 输入自定义文字：预览立即更新，停止输入 400ms 后落盘并刷新小组件。
  void _onTitleChanged(String value) {
    final settings = _settings;
    if (settings == null) return;
    final normalized = normalizeWidgetTitle(value);
    setState(() => settings.title = normalized);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _persist);
  }

  Future<void> _persist() async {
    final settings = _settings;
    if (settings == null) return;
    await settings.save();
    await WidgetBridge.refresh();
  }

  Future<void> _setColor(int index) async {
    final settings = _settings;
    if (settings == null) return;
    setState(() => settings.colorIndex = index);
    await _persist();
  }

  Future<void> _setSize(String id) async {
    final settings = _settings;
    if (settings == null) return;
    setState(() {
      settings.sizeId = id;
      _hint = null;
    });
    await _persist();
  }

  Future<void> _pin() async {
    final settings = _settings;
    if (settings == null) return;
    _saveTimer?.cancel();
    await _persist();
    setState(() {
      _hint = null;
      _showGuide = false;
    });
    final accepted = await WidgetBridge.pinWidget(settings.sizeId);
    if (!mounted) return;
    // 无论系统是否弹出确认框，都直接给出手动步骤：
    // MIUI / HyperOS 等品牌桌面会「返回成功但不弹窗」，用户最终仍要手动添加。
    setState(() {
      _hint = accepted
          ? '已请求系统添加。部分桌面（MIUI / HyperOS 等）不会弹出确认框，请按下面步骤手动添加：'
          : '当前系统 / 桌面不支持一键添加，请按下面步骤手动添加：';
      _showGuide = true;
    });
    _revealGuide();
  }

  /// 把手动添加步骤滚动到可见位置（避免长面板里被折叠在下方）。
  void _revealGuide() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  /// 回到系统桌面，方便长按添加。
  Future<void> _backToHome() async {
    Navigator.of(context).pop();
    await WidgetBridge.openHome();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = _settings;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: settings == null
          ? const SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '桌面小组件',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '显示今天还没上的课，上完一门自动划掉一门',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  _WidgetPreview(
                    settings: settings,
                    schedule: widget.schedule,
                    periods: widget.periods,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    key: const ValueKey('widget-title-field'),
                    controller: _title,
                    maxLength: WidgetSettings.maxTitleLength,
                    onChanged: _onTitleChanged,
                    decoration: const InputDecoration(
                      labelText: '左上角自定义文字',
                      hintText: '最多 6 个字，如：26年秋',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '尺寸',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final size in widgetSizePresets)
                        ChoiceChip(
                          key: ValueKey('widget-size-${size.id}'),
                          label: Text(size.label),
                          selected: settings.size.id == size.id,
                          onSelected: (_) => _setSize(size.id),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    settings.size.description,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '配色',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (var i = 0; i < widgetColorPresets.length; i++)
                        _ColorDot(
                          key: ValueKey('widget-color-$i'),
                          preset: widgetColorPresets[i],
                          selected: i == settings.colorIndex,
                          onTap: () => _setColor(i),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const ValueKey('widget-pin-button'),
                      onPressed: _pin,
                      icon: const Icon(Icons.add_to_home_screen),
                      label: const Text('添加到桌面'),
                    ),
                  ),
                  if (_hint != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _hint!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                  if (_showGuide) ...[
                    const SizedBox(height: 12),
                    _ManualGuide(
                      size: settings.size,
                      onBackHome: _backToHome,
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

/// App 内的实时预览（与原生小组件同一套规则）。
class _WidgetPreview extends StatelessWidget {
  const _WidgetPreview({
    required this.settings,
    required this.schedule,
    this.periods,
  });

  final WidgetSettings settings;
  final Schedule schedule;
  final PeriodSettings? periods;

  @override
  Widget build(BuildContext context) {
    final color = settings.color;
    final now = DateTime.now();
    final lines = widgetTodayCourses(
      schedule,
      now,
      periods: periods,
      max: settings.size.maxCourses,
    );
    final height = switch (settings.size.id) {
      'large' => 268.0,
      'medium' => 214.0,
      _ => 142.0,
    };
    final dateText =
        '${now.month}.${now.day} 第${schedule.currentWeek(now)}周 '
        '${widgetWeekdayName(now.weekday)}';
    final title = settings.title.isEmpty ? '醒课' : settings.title;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: height,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: color.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          // 上 1/5：自定义文字 + 日期/周次/周几（显示在自定义底色上）
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      key: const ValueKey('widget-preview-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: color.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    dateText,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 下 4/5：白色面板 + 剩余课程平均等分
          Expanded(
            flex: 4,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
              ),
              child: lines.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '(〃\'▽\'〃)',
                            style: TextStyle(fontSize: 11, color: color.muted),
                          ),
                          const Text(
                            '今天没有课啦',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        for (final line in lines)
                          Expanded(
                            child: _PreviewRow(line: line, accent: color.accent),
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

/// 预览里的一行课程：左侧时间列 + 课程色条 + 课程名 / 详情 / 倒计时。
class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.line, required this.accent});

  final WidgetCourseLine line;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 34,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.startText,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              Text(
                line.endText,
                maxLines: 1,
                style: const TextStyle(fontSize: 8, color: Color(0xFF9AA3AF)),
              ),
            ],
          ),
        ),
        Container(
          width: 3,
          height: 26,
          decoration: BoxDecoration(
            color: courseColor(line.colorIndex),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      line.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 8.5,
                        color: Color(0xFF8A93A0),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    line.status,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 手动添加小组件的步骤卡片（MIUI / HyperOS 等桌面不支持一键添加时展示）。
class _ManualGuide extends StatelessWidget {
  const _ManualGuide({required this.size, required this.onBackHome});

  final WidgetSizePreset size;
  final VoidCallback onBackHome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = [
      '点下面「回到桌面」，在桌面空白处长按 1 秒',
      '点「添加小部件 / 小组件」（一般在屏幕左下或右下）',
      '搜索框输入「醒课」，找到「醒课 · 今日课程（${size.cells}）」',
      '长按它拖到桌面空白位置即可',
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.touch_app_outlined,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                '手动添加（${size.cells}·最多 ${size.maxCourses} 门课）',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${i + 1}. ${steps[i]}',
                style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
              ),
            ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onBackHome,
              icon: const Icon(Icons.home_outlined, size: 18),
              label: const Text('回到桌面'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 配色圆点（选中打勾）。
class _ColorDot extends StatelessWidget {
  const _ColorDot({
    super.key,
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final WidgetColorPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: preset.background,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? preset.accent : Colors.black12,
            width: selected ? 3 : 1,
          ),
        ),
        child: selected
            ? Icon(Icons.check, size: 18, color: preset.accent)
            : null,
      ),
    );
  }
}
