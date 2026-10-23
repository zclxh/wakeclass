import 'package:test/test.dart';
import 'package:wakeclass_core/wakeclass_core.dart';

void main() {
  group('PeriodSettings 默认值', () {
    test('与 defaultPeriodTimes 一致：12 节，每节 45 分钟', () {
      final settings = PeriodSettings.defaults();
      expect(settings.count, 12);
      expect(settings.durationMinutes, 45);
      expect(settings.startOf(1), '08:00');
      expect(settings.endOf(1), '08:45');
      expect(settings.timeText(3), '10:10-10:55');
      expect(settings.timeText(5), '14:00-14:45');
      expect(settings.timeText(12), '21:45-22:30');
    });

    test('越界节次返回空串 / null', () {
      final settings = PeriodSettings.defaults();
      expect(settings.startOf(0), '');
      expect(settings.startOf(99), '');
      expect(settings.timeText(99), '');
      expect(settings.startMinute(0), isNull);
      expect(settings.endMinute(99), isNull);
    });
  });

  group('按规则生成', () {
    test('每节 45 分钟 + 课间 10 分钟', () {
      final settings = PeriodSettings.uniform(
        firstStart: '08:00',
        durationMinutes: 45,
        breakMinutes: 10,
        count: 4,
      );
      expect(settings.starts, ['08:00', '08:55', '09:50', '10:45']);
      expect(settings.timeText(1), '08:00-08:45');
      expect(settings.timeText(4), '10:45-11:30');
      expect(settings.firstStart, '08:00');
      expect(settings.breakMinutes, 10);
    });

    test('节数被限制在 4..16', () {
      expect(
        PeriodSettings.uniform(count: 99).count,
        PeriodSettings.maxCount,
      );
      expect(
        PeriodSettings.uniform(count: 1).count,
        PeriodSettings.minCount,
      );
    });

    test('时长被限制在 20..120 分钟', () {
      expect(
        PeriodSettings.uniform(durationMinutes: 5).durationMinutes,
        PeriodSettings.minDuration,
      );
      expect(
        PeriodSettings.uniform(durationMinutes: 999).durationMinutes,
        PeriodSettings.maxDuration,
      );
    });
  });

  group('单节微调', () {
    test('只改指定节次，其余不变', () {
      final settings = PeriodSettings.defaults().withStart(3, '10:15');
      expect(settings.startOf(3), '10:15');
      expect(settings.endOf(3), '11:00');
      expect(settings.startOf(2), '08:55');
      expect(settings.startOf(4), '11:05');
    });

    test('非法时间 / 越界节次不改动', () {
      final settings = PeriodSettings.defaults();
      expect(settings.withStart(1, '25:00'), same(settings));
      expect(settings.withStart(0, '09:00'), same(settings));
    });
  });

  group('编码 / 解码', () {
    test('encode → decode 保持一致', () {
      final settings = PeriodSettings.uniform(
        firstStart: '09:10',
        durationMinutes: 50,
        breakMinutes: 5,
        count: 8,
      );
      final decoded = PeriodSettings.decode(settings.encode());
      expect(decoded, settings);
      expect(decoded.timeText(1), '09:10-10:00');
    });

    test('空串 / 脏数据回退默认作息', () {
      expect(PeriodSettings.decode(''), PeriodSettings.defaults());
      expect(PeriodSettings.decode(null), PeriodSettings.defaults());
      expect(PeriodSettings.decode('not json'), PeriodSettings.defaults());
      expect(
        PeriodSettings.decode('{"starts":["bad","08:00"]}'),
        PeriodSettings.defaults(),
      );
    });

    test('时长越界时被夹到合理范围', () {
      final decoded = PeriodSettings.decode(
        '{"starts":["08:00","08:55","09:50","10:45"],"duration":999}',
      );
      expect(decoded.durationMinutes, PeriodSettings.maxDuration);
      expect(decoded.count, 4);
    });
  });

  group('时间工具', () {
    test('minutesOfHhmm', () {
      expect(minutesOfHhmm('08:00'), 480);
      expect(minutesOfHhmm('23:59'), 1439);
      expect(minutesOfHhmm('8:5'), 485);
      expect(minutesOfHhmm('24:00'), isNull);
      expect(minutesOfHhmm('08:60'), isNull);
      expect(minutesOfHhmm('abc'), isNull);
    });

    test('formatHhmm', () {
      expect(formatHhmm(480), '08:00');
      expect(formatHhmm(485), '08:05');
      expect(formatHhmm(1440), '00:00');
      expect(formatHhmm(-60), '23:00');
    });
  });
}
