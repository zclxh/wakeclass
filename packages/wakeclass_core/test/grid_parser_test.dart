import 'package:test/test.dart';
import 'package:wakeclass_core/wakeclass_core.dart';

import 'helpers/grid_fixture.dart';

Course by(List<Course> courses, String name, int day, int startPeriod) =>
    courses.firstWhere((c) =>
        c.name == name &&
        c.dayOfWeek == day &&
        c.startPeriod == startPeriod);

void main() {
  group('GridParser', () {
    test('完整强智课表截图：14 门课全部落到正确 (星期, 节次)', () {
      final result = GridParser().parse([
        ...GridFixture.headers(),
        ...GridFixture.periodLabels(),
        ...GridFixture.groupLabels(),
        ...GridFixture.courseBlocks(),
      ]);

      expect(result.layout.headerDetected, isTrue);
      expect(result.layout.periodColumnDetected, isTrue);
      expect(result.layout.days, [1, 2, 3, 4, 5, 6, 7]);
      expect(result.layout.rowPeriodStarts, List.generate(12, (i) => i + 1));
      expect(result.courses, hasLength(14));
      expect(result.unassignedTexts, isEmpty);
      expect(result.warnings, isEmpty);

      // 周一 1-2 节 高数A
      final math = by(result.courses, '高等数学A', 1, 1);
      expect(math.endPeriod, 2);
      expect(math.teacher, '张明远');
      expect(math.location, '教一101');
      expect(math.weeks, List.generate(16, (i) => i + 1));

      // 周一 3-4 节 大学英语
      expect(by(result.courses, '大学英语III', 1, 3).location, '外语楼302');

      // 周三 3-4 节 高数A（同名课的另一条记录）
      expect(by(result.courses, '高等数学A', 3, 3).endPeriod, 4);

      // 周六 1-2 节 创新创业（单周）
      final innovation = by(result.courses, '创新创业实践', 6, 1);
      expect(innovation.weeks, [3, 5, 7, 9, 11, 13, 15]);
      expect(innovation.location, '创客空间');

      // 周二 7-8 节：一格两门课拆分
      final linear = by(result.courses, '线性代数', 2, 7);
      expect(linear.teacher, '王建国');
      expect(linear.weeks, List.generate(8, (i) => i + 1));
      final prob = by(result.courses, '概率论与数理统计', 2, 7);
      expect(prob.teacher, '李芳');
      expect(prob.weeks, List.generate(7, (i) => i + 10));

      // 周五 9-10 节
      expect(by(result.courses, '数字电路实验', 5, 9).endPeriod, 10);
    });

    test('双节次行（第1-2节/第3-4节…）同样正确映射', () {
      final result = GridParser().parse([
        ...GridFixture.headers(),
        ...GridFixture.periodLabels(grouped: true),
        ...GridFixture.courseBlocks(),
      ]);

      expect(result.layout.rowPeriodStarts, [1, 3, 5, 7, 9, 11]);
      expect(result.courses, hasLength(14));
      final math = by(result.courses, '高等数学A', 1, 1);
      expect(math.endPeriod, 2);
      expect(by(result.courses, '数字电路实验', 5, 9).endPeriod, 10);
      expect(result.warnings, isEmpty);
    });

    test('单节次课程（非合并单元格）', () {
      final result = GridParser().parse([
        ...GridFixture.headers(),
        ...GridFixture.periodLabels(),
        GridFixture.singleSlotBlock('晚自习\n1-16周\n教一201', 5, 9),
      ]);

      expect(result.courses, hasLength(1));
      final c = result.courses.single;
      expect(c.dayOfWeek, 5);
      expect(c.startPeriod, 9);
      expect(c.endPeriod, 9);
      expect(c.name, '晚自习');
      // 缺教师 → 告警（网格层告警带位置前缀）
      expect(result.warnings, anyElement(contains('未识别教师')));
    });

    test('时间行标签（08:00 等）可替代节次编号', () {
      final result = GridParser().parse([
        ...GridFixture.headers(),
        ...GridFixture.timeLabels(),
        GridFixture.courseBlock('高等数学A\n张明远\n1-16周\n教一101', 1, 1, 2),
      ]);

      expect(result.layout.rowPeriodStarts, List.generate(12, (i) => i + 1));
      final c = by(result.courses, '高等数学A', 1, 1);
      expect(c.endPeriod, 2);
    });

    test('缺表头：全部课程进未分配区并告警', () {
      final result = GridParser().parse([
        ...GridFixture.periodLabels(),
        ...GridFixture.courseBlocks(),
      ]);

      expect(result.courses, isEmpty);
      expect(result.unassignedTexts, isNotEmpty);
      expect(result.warnings, contains('未检测到星期表头，无法确定课程所在星期'));
    });

    test('缺节次列：单元格保留但课程无法定位节次', () {
      final result = GridParser().parse([
        ...GridFixture.headers(),
        ...GridFixture.courseBlocks(),
      ]);

      expect(result.courses, isEmpty);
      expect(result.cells, isNotEmpty);
      expect(result.cells.first.startPeriod, 0);
      expect(result.warnings, contains('未检测到节次列，无法确定上课节次'));
      expect(result.warnings, anyElement(startsWith('「')));
    });

    test('同格冲突检测', () {
      final result = GridParser().parse([
        ...GridFixture.headers(),
        ...GridFixture.periodLabels(),
        GridFixture.courseBlock('高数\n张明\n1-16周\n教一101', 1, 1, 2),
        GridFixture.courseBlock('线代\n王强\n1-8周\n教二201', 1, 1, 2),
      ]);

      expect(result.courses, hasLength(2));
      expect(result.warnings, contains(startsWith('冲突：高数')));
    });

    test('周日起始表头（周日排第一列）也能正确编号', () {
      const sunFirst = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
      final headers = [
        for (var i = 0; i < 7; i++)
          GridFixture.block(
              sunFirst[i], GridFixture.columnLefts[i] + 0.015, 0.015, 0.06, 0.025),
      ];
      final result = GridParser().parse([
        ...headers,
        ...GridFixture.periodLabels(),
        GridFixture.courseBlock('高数\n张明\n1-16周\n教一101', 2, 1, 2),
      ]);

      // 表头第 2 列是星期一 → 课程 day 应为 1
      final c = result.courses.single;
      expect(c.name, '高数');
      expect(c.dayOfWeek, 1);
      expect(c.startPeriod, 1);
    });

    test('全部课程 source 标记为 ocr 且配色按课程名稳定', () {
      final result = GridParser().parse([
        ...GridFixture.headers(),
        ...GridFixture.periodLabels(),
        ...GridFixture.courseBlocks(),
      ]);

      for (final c in result.courses) {
        expect(c.source, 'ocr');
        expect(c.colorIndex, inInclusiveRange(0, 19));
      }
      final a1 = by(result.courses, '高等数学A', 1, 1);
      final a2 = by(result.courses, '高等数学A', 3, 3);
      expect(a1.colorIndex, a2.colorIndex);
      expect(a1.id, isNot(a2.id));
    });
  });
}
