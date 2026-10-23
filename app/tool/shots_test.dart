// UI 快照工具（不参与 CI）：把关键页面渲染成 PNG，用来检查视觉效果。
//
//   cd app && flutter test tool/shots_test.dart
//   输出：app/tool/shots/*.png
//
// 说明：flutter test 默认字体是 Ahem（方块字），这里把系统中文字体注册成
// `Roboto`（测试环境的默认族名）+ 图标字体，才能渲染出真实中文与图标。
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeclass_app/app.dart';
import 'package:wakeclass_core/wakeclass_core.dart';

const _rootKey = ValueKey('shot-root');

const _fontDir = r'C:\Windows\Fonts';
const _flutterFonts =
    r'C:\Users\30521\Documents\deepseek-harness\default-workspace\.tools\flutter-sdk\flutter\bin\cache\artifacts\material_fonts';

Future<void> _loadFamily(String family, List<String> paths) async {
  final loader = FontLoader(family);
  var any = false;
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) continue;
    any = true;
    loader.addFont(
      Future.value(ByteData.sublistView(file.readAsBytesSync())),
    );
  }
  if (any) await loader.load();
}

/// 一次截图。
Future<void> _shoot(WidgetTester tester, String name) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_rootKey));
  final image = await boundary.toImage(pixelRatio: 2);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final dir = Directory('tool/shots')..createSync(recursive: true);
  File('${dir.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  // ignore: avoid_print
  print('shot -> ${dir.path}/$name.png');
}

Schedule _demoSchedule() {
  Course c(String name, String teacher, String room, int day, int s, int e) =>
      Course.create(
        name: name,
        teacher: teacher,
        location: room,
        dayOfWeek: day,
        startPeriod: s,
        endPeriod: e,
        source: 'mock',
      );
  return Schedule(
    id: 'demo',
    title: '2026-2027 学年第一学期',
    termStart: DateTime(2026, 9, 7),
    totalWeeks: 20,
    courses: [
      c('高等数学A', '张明远', '教一101', 1, 1, 2),
      c('大学英语', '李华', '外语楼203', 1, 3, 4),
      c('人体解剖学', '王芳', '医技楼302', 1, 5, 6),
      c('体育', '赵强', '田径场', 1, 7, 8),
      c('生理学', '陈静', '医技楼201', 2, 1, 2),
      c('病理学', '刘伟', '医技楼205', 2, 3, 4),
      c('护理学基础', '孙丽', '实训楼401', 2, 5, 6),
      c('大学英语', '李华', '外语楼203', 3, 1, 2),
      c('计算机应用', '周涛', '信息楼302', 3, 3, 4),
      c('药理学', '吴敏', '医技楼303', 3, 5, 6),
      c('思想道德与法治', '郑海', '文科楼101', 3, 7, 8),
      c('人体解剖学', '王芳', '医技楼302', 4, 1, 2),
      c('生理学', '陈静', '医技楼201', 4, 3, 4),
      c('护理学基础', '孙丽', '实训楼401', 4, 5, 6),
      c('病理学', '刘伟', '医技楼205', 5, 1, 2),
      c('体育', '赵强', '田径场', 5, 3, 4),
      c('大学生心理健康', '林小雨', '文科楼203', 5, 5, 6),
    ],
  );
}

/// 固定推进若干帧（不用 pumpAndSettle：首页启动时的转圈会让它永远等下去）。
Future<void> _settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFamily('Roboto', [
      '$_fontDir\\Deng.ttf',
      '$_fontDir\\Dengb.ttf',
    ]);
    await _loadFamily('MaterialIcons', [
      '$_flutterFonts\\materialicons-regular.otf',
    ]);
  });

  Future<void> pumpApp(WidgetTester tester, {bool empty = false}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(
      empty
          ? {}
          : {
              'flutter.wakeclass_schedule_v1':
                  jsonEncode(_demoSchedule().toJson()),
            },
    );
    await tester.pumpWidget(
      const RepaintBoundary(key: _rootKey, child: WakeClassApp()),
    );
    await _settle(tester);
  }

  testWidgets('schedule', (tester) async {
    await pumpApp(tester);
    await _shoot(tester, '01-schedule');
  });

  testWidgets('empty', (tester) async {
    await pumpApp(tester, empty: true);
    await _shoot(tester, '02-empty');
  });

  testWidgets('import', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined).first);
    await _settle(tester);
    await _shoot(tester, '03-import');
  });

  testWidgets('settings', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await _settle(tester);
    await _shoot(tester, '04-settings');
  });

  testWidgets('course-actions', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('高等数学A').first);
    await _settle(tester);
    await _shoot(tester, '05-course-actions');
  });
}
