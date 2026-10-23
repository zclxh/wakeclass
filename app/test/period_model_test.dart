import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeclass_core/wakeclass_core.dart';

import 'package:wakeclass_app/model/period_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PeriodModel 持久化', () {
    test('默认作息：12 节，第 1 节 08:00-08:45', () async {
      SharedPreferences.setMockInitialValues({});
      final model = PeriodModel();
      await model.init();
      expect(model.settings.count, 12);
      expect(model.settings.startOf(1), '08:00');
      expect(model.settings.timeText(1), '08:00-08:45');
      expect(model.settings.timeText(5), '14:00-14:45');
      expect(model.loaded, isTrue);
    });

    test('保存后写入字符串键（原生小组件读同一个键）', () async {
      SharedPreferences.setMockInitialValues({});
      final model = PeriodModel();
      await model.init();
      await model.update(PeriodSettings.uniform(
        firstStart: '09:10',
        durationMinutes: 50,
        breakMinutes: 5,
        count: 8,
      ));

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(PeriodModel.prefsKey);
      expect(raw, isNotNull);
      expect(raw, contains('09:10'));
      expect(raw, contains('"duration":50'));
    });

    test('重新读取后作息保持一致', () async {
      SharedPreferences.setMockInitialValues({});
      final model = PeriodModel();
      await model.init();
      await model.update(PeriodSettings.uniform(
        firstStart: '09:10',
        durationMinutes: 50,
        breakMinutes: 5,
        count: 8,
      ));

      final reloaded = PeriodModel();
      await reloaded.init();
      expect(reloaded.settings.count, 8);
      expect(reloaded.settings.durationMinutes, 50);
      expect(reloaded.settings.timeText(1), '09:10-10:00');
      expect(reloaded.settings.timeText(2), '10:05-10:55');
    });

    test('恢复默认作息', () async {
      SharedPreferences.setMockInitialValues({});
      final model = PeriodModel();
      await model.init();
      await model.update(PeriodSettings.uniform(
        firstStart: '07:30',
        durationMinutes: 40,
        breakMinutes: 10,
        count: 6,
      ));
      await model.resetToDefaults();
      expect(model.settings.timeText(1), '08:00-08:45');
      expect(model.settings.count, 12);
    });
  });
}
