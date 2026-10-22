import 'package:test/test.dart';
import 'package:wakeclass_core/wakeclass_core.dart';

void main() {
  group('parseCellText', () {
    test('标准四行单元格（强智/正方格式）', () {
      final result = parseCellText('高等数学A\n张明远\n1-16周\n教一101');
      expect(result, hasLength(1));
      final c = result.single;
      expect(c.name, '高等数学A');
      expect(c.teacher, '张明远');
      expect(c.location, '教一101');
      expect(c.weeks, List.generate(16, (i) => i + 1));
      expect(c.warnings, isEmpty);
    });

    test('周次在前、教师在地点前的排布', () {
      final c = parseCellText('1-16周\n高数\n张明\n教一101').single;
      expect(c.name, '高数');
      expect(c.teacher, '张明');
      expect(c.location, '教一101');
    });

    test('一格两门课（按周次行分段）', () {
      final result = parseCellText(
          '线性代数\n王建国\n1-8周\n教二201\n概率论与数理统计\n李芳\n10-16周\n教二202');
      expect(result, hasLength(2));
      expect(result[0].name, '线性代数');
      expect(result[0].teacher, '王建国');
      expect(result[0].location, '教二201');
      expect(result[0].weeks, List.generate(8, (i) => i + 1));
      expect(result[1].name, '概率论与数理统计');
      expect(result[1].teacher, '李芳');
      expect(result[1].location, '教二202');
      expect(result[1].weeks, List.generate(7, (i) => i + 10));
    });

    test('一格两门课（横线分隔）', () {
      final result = parseCellText(
          '线代\n王建国\n1-8周\n教二201\n--------\n概率论\n李芳\n10-16周\n教二202');
      expect(result, hasLength(2));
      expect(result[0].name, '线代');
      expect(result[1].name, '概率论');
    });

    test('短课程名像人名时不被误判（体育）', () {
      final c = parseCellText('体育\n王强\n1-16周\n东区体育场').single;
      expect(c.name, '体育');
      expect(c.teacher, '王强');
      expect(c.location, '东区体育场');
    });

    test('短课程名后接教师与周次的两门课分段', () {
      final result = parseCellText(
          '高数\n1-16周\n张明\n教一101\n体育\n王强\n1-16周\n东区体育场');
      expect(result, hasLength(2));
      expect(result[0].name, '高数');
      expect(result[0].teacher, '张明');
      expect(result[1].name, '体育');
      expect(result[1].teacher, '王强');
    });

    test('单双周解析', () {
      final c = parseCellText('创新创业实践\n林晓\n3-15周(单)\n创客空间').single;
      expect(c.weeks, [3, 5, 7, 9, 11, 13, 15]);
      expect(c.location, '创客空间');
    });

    test('缺周次 → 默认全学期并告警', () {
      final c = parseCellText('高数\n张明\n教一101').single;
      expect(c.weeks, List.generate(20, (i) => i + 1));
      expect(c.weekExpression.isDefaulted, isTrue);
      expect(c.warnings, contains(startsWith('未识别周次')));
    });

    test('缺教师与地点 → 告警', () {
      final c = parseCellText('高数\n1-16周').single;
      expect(c.teacher, isEmpty);
      expect(c.location, isEmpty);
      expect(c.warnings, contains(startsWith('未识别教师')));
      expect(c.warnings, contains(startsWith('未识别地点')));
    });

    test('OCR 把多行粘成一行时剥离字段', () {
      final c = parseCellText('高数 张明 1-16周 教一101').single;
      expect(c.name, '高数 张明');
      expect(c.weeks, List.generate(16, (i) => i + 1));
      expect(c.warnings, isNotEmpty);
    });

    test('单元格内混入段标题/节次噪声行时被过滤', () {
      final c = parseCellText('上午\n高数\n张明\n1-16周\n教一101').single;
      expect(c.name, '高数');
      expect(c.teacher, '张明');
    });

    test('空文本 → 空列表', () {
      expect(parseCellText(''), isEmpty);
      expect(parseCellText('\n\n'), isEmpty);
    });
  });

  group('行分类辅助函数', () {
    test('hasWeekPattern', () {
      expect(hasWeekPattern('1-16周'), isTrue);
      expect(hasWeekPattern('第3周'), isTrue);
      expect(hasWeekPattern('单周'), isTrue);
      expect(hasWeekPattern('高数A'), isFalse);
      expect(hasWeekPattern('教一101'), isFalse);
    });

    test('isLocationLine', () {
      expect(isLocationLine('教一101'), isTrue);
      expect(isLocationLine('计算机楼205'), isTrue);
      expect(isLocationLine('东区体育场'), isTrue);
      expect(isLocationLine('创客空间'), isTrue);
      expect(isLocationLine('高等数学A'), isFalse);
      expect(isLocationLine('大学英语III'), isFalse);
      expect(isLocationLine('数字电路实验'), isFalse);
      expect(isLocationLine('1-16周'), isFalse);
    });
  });
}
