import 'package:flutter/material.dart';

import 'model/schedule_model.dart';
import 'model/theme_model.dart';
import 'pages/schedule_page.dart';
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
        theme: buildLightTheme(seedColor: _themeModel.seedColor),
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

class _HomeBootState extends State<HomeBoot> {
  final ScheduleModel _model = ScheduleModel(ScheduleStore());

  @override
  void initState() {
    super.initState();
    _boot();
  }

  /// 加载课表、刷新桌面小组件并同步课前提醒。
  Future<void> _boot() async {
    try {
      await _model.init();
      // 打开 App 时刷新一次小组件（同时重新安排每分钟刷新）
      await WidgetBridge.refresh();
      final settings = await CourseReminderService.loadSettings();
      await CourseReminderService.sync(_model.schedule, settings: settings);
    } catch (_) {
      // 通知初始化失败不影响主流程
    }
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _model,
      builder: (context, _) =>
          SchedulePage(model: _model, themeModel: widget.themeModel),
    );
  }
}
