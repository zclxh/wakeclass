import 'package:test/test.dart';
import 'package:wakeclass_core/wakeclass_core.dart';

List<int> range(int a, [int? b]) =>
    List.generate((b ?? a) - a + 1, (i) => a + i);

void main() {
  group('parseWeeks', () {
    test('1-16周 → 1..16', () {
      expect(parseWeeks('1-16周').weeks, range(1, 16));
      expect(parseWeeks('1-16周').isDefaulted, isFalse);
    });

    test('第1-16周 带「第」前缀', () {
      expect(parseWeeks('第1-16周').weeks, range(1, 16));
    });

    test('3-15周(单) → 3..15 的奇数周', () {
      expect(parseWeeks('3-15周(单)').weeks, [3, 5, 7, 9, 11, 13, 15]);
    });

    test('2-16周(双) → 2..16 的偶数周', () {
      expect(parseWeeks('2-16周(双)').weeks, [2, 4, 6, 8, 10, 12, 14, 16]);
    });

    test('1-16周单周 → 全范围奇周', () {
      expect(parseWeeks('1-16周单周').weeks, [1, 3, 5, 7, 9, 11, 13, 15]);
    });

    test('「单周」单独出现 → 全学期奇周', () {
      expect(parseWeeks('单周').weeks, [1, 3, 5, 7, 9, 11, 13, 15, 17, 19]);
      expect(parseWeeks('单周').isDefaulted, isFalse);
    });

    test('「双周」单独出现 → 全学期偶周', () {
      expect(parseWeeks('双周').weeks, [2, 4, 6, 8, 10, 12, 14, 16, 18, 20]);
    });

    test('1-8,10-16周 → 分段并集', () {
      expect(parseWeeks('1-8,10-16周').weeks, [...range(1, 8), ...range(10, 16)]);
    });

    test('第3周 → {3}', () {
      expect(parseWeeks('第3周').weeks, [3]);
    });

    test('16周 → {16}', () {
      expect(parseWeeks('16周').weeks, [16]);
    });

    test('全周/每周/全学期 → 1..20', () {
      expect(parseWeeks('全周').weeks, range(1, 20));
      expect(parseWeeks('每周').weeks, range(1, 20));
      expect(parseWeeks('全学期').weeks, range(1, 20));
    });

    test('纯数字列表 1 3 5', () {
      expect(parseWeeks('1 3 5').weeks, [1, 3, 5]);
    });

    test('空输入 → 默认全学期', () {
      final expr = parseWeeks('');
      expect(expr.weeks, range(1, 20));
      expect(expr.isDefaulted, isTrue);
    });

    test('无法解析的文本 → 默认全学期', () {
      final expr = parseWeeks('待定');
      expect(expr.weeks, range(1, 20));
      expect(expr.isDefaulted, isTrue);
    });

    test('钳制到 totalWeeks', () {
      expect(parseWeeks('1-30周', totalWeeks: 20).weeks, range(1, 20));
    });
  });

  group('formatWeeks', () {
    test('连续区间', () {
      expect(formatWeeks(range(1, 16)), '1-16周');
    });

    test('单双周表示', () {
      expect(formatWeeks([1, 3, 5, 7]), '1-7周(单)');
      expect(formatWeeks([2, 4, 6, 8]), '2-8周(双)');
    });

    test('分段区间', () {
      expect(formatWeeks(<int>[...range(1, 8), ...range(10, 16)]), '1-8周, 10-16周');
    });

    test('单周', () {
      expect(formatWeeks([3]), '3周');
    });

    test('空', () {
      expect(formatWeeks([]), '未设置');
    });
  });
}
