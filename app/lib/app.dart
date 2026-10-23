import 'dart:async';

import 'package:flutter/material.dart';

import 'model/period_model.dart';
import 'model/schedule_model.dart';
import 'model/theme_model.dart';
import 'pages/import_decision.dart';
import 'pages/paste_schedule_page.dart';
import 'pages/schedule_page.dart';
import 'services/import/external_import.dart';
import 'services/notifications/reminders.dart';
import 'services/storage/schedule_store.dart';
import 'services/widget/widget_bridge.dart';
import 'theme.dart';

/// 醒课 App 根组件。
class WakeClassApp extends StatefulWidget {
  const WakeClassApp({super.key});

  @override
  State<WakeClassApp> createState() => _WakeClassAppState();
}

class _WakeClassAppState extends State<WakeClassApp> {
  final ThemeModel _themeModel = ThemeModel();

  @override
  void initState() {
    super.initState();
    _themeModel.init();
  }

  @override
  void dispose() {
    _themeModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _themeModel,
      builder: (context, _) => MaterialApp(
        title: '醒课',
        debugShowCheckedModeBanner: false,
        theme: buildLightTheme(
          seedColor: _themeModel.seedColor,
          backgroundColor: _themeModel.backgroundColor,
        ),
        darkTheme: buildDarkTheme(seedColor: _themeModel.seedColor),
        themeMode: ThemeMode.system,
        home: HomeBoot(themeModel: _themeModel),
      ),
    );
  }
}

/// 应用入口：加载本地课表后进入课表主页。
class HomeBoot extends StatefulWidget {
  const HomeBoot({super.key, required this.themeModel});

  final ThemeModel themeModel;

  @override
  State<HomeBoot> createState() => _HomeBootState();
}

class _HomeBootState extends State<HomeBoot> with WidgetsBindingObserver {
  final ScheduleModel _model = ScheduleModel(ScheduleStore());
  final PeriodModel _periodModel = PeriodModel();

  /// 课表读完后才渲染主页：保证打开时直接停在「当前周」而不是第 1 周。
  bool _ready = false;

  /// 上次同步课前提醒的时间（回到前台时节流同步）。
  DateTime? _lastReminderSync;

  /// 运行中从外部送进来的课表内容（分享 / 用其他应用打开）。
  StreamSubscription<String>? _externalSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _externalSub =
        ExternalImport.incoming.listen((text) => unawaited(_importExternal(text)));
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _externalSub?.cancel();
    _model.dispose();
    _periodModel.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 回到前台时补一次提醒同步（系统可能清掉过闹钟 / 跨周了）
    if (state == AppLifecycleState.resumed) {
      final last = _lastReminderSync;
      if (last == null || DateTime.now().difference(last) > const Duration(hours: 6)) {
        unawaited(_syncReminders());
      }
    }
  }

  /// 读取本地课表 → 放开首屏。
  ///
  /// 小组件刷新与提醒排程都走平台通道，放到后台进行（不阻塞首屏，
  /// 也避免通道不可用时卡住启动）。
  Future<void> _boot() async {
    try {
      await Future.wait([_model.init(), _periodModel.init()]);
    } catch (_) {
      // 读取失败也进主页（会显示空课表）
    }
    if (mounted) setState(() => _ready = true);
    unawaited(_postBoot());
    // 冷启动时从「打开 / 分享」带进来的课表文件
    final pending = await ExternalImport.takePending();
    if (pending != null) unawaited(_importExternal(pending));
  }

  /// 外部送进来的内容 → 粘贴导入页（预填 + 自动解析）。
  Future<void> _importExternal(String text) async {
    if (!mounted) return;
    final decision = await Navigator.of(context).push<ImportDecision>(
      MaterialPageRoute(
        builder: (_) => PasteSchedulePage(initialText: text, autoParse: true),
      ),
    );
    if (decision == null || !mounted) return;
    await decision.applyTo(_model);
    unawaited(_syncReminders());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '已${decision.replace ? '覆盖' : '追加'}导入 ${decision.courses.length} 门课'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _postBoot() async {
    try {
      await WidgetBridge.refresh();
    } catch (_) {
      // 非 Android / 测试环境
    }
    await _syncReminders();
  }

  Future<void> _syncReminders() async {
    try {
      final settings = await CourseReminderService.loadSettings();
      await CourseReminderService.sync(
        _model.schedule,
        settings: settings,
        periods: _periodModel.settings,
      );
      _lastReminderSync = DateTime.now();
    } catch (_) {
      // 通知不可用时忽略
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_model, _periodModel]),
      builder: (context, _) {
        if (!_ready) return const _BootScreen();
        return SchedulePage(
          model: _model,
          themeModel: widget.themeModel,
          periodModel: _periodModel,
        );
      },
    );
  }
}

/// 启动占位（读本地课表通常只有几十毫秒）。
class _BootScreen extends StatelessWidget {
  const _BootScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '醒课',
              style: theme.textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ],
        ),
      ),
    );
  }
}
