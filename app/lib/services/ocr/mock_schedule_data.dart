import 'package:wakeclass_core/wakeclass_core.dart';

/// 演示数据：模拟一张「强智教务系统」课表截图的 OCR 文本块（相对坐标）。
///
/// 数据与 core 包测试夹具一致（源自真实教务系统课表页），
/// 供开发机（Windows 桌面）体验完整导入流程。
class MockScheduleData {
  MockScheduleData._();

  static const columnLefts = <double>[
    0.13, 0.25, 0.37, 0.49, 0.61, 0.73, 0.85, //
  ];
  static const columnWidth = 0.10;
  static const firstRowCenter = 0.06;
  static const rowStep = 0.07;

  static double rowCenter(int rowIndex) =>
      firstRowCenter + rowIndex * rowStep;

  static OcrTextBlock block(
          String text, double left, double top, double width, double height) =>
      OcrTextBlock(
          text: text, left: left, top: top, width: width, height: height);

  static List<OcrTextBlock> headers() {
    const names = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return [
      for (var i = 0; i < 7; i++)
        block(names[i], columnLefts[i] + 0.015, 0.015, 0.06, 0.025),
    ];
  }

  static List<OcrTextBlock> periodLabels() => [
        for (var i = 0; i < 12; i++)
          block('第${i + 1}节', 0.02, rowCenter(i) - 0.02, 0.09, 0.04),
      ];

  static List<OcrTextBlock> groupLabels() => [
        block('上午', 0.02, 0.11, 0.09, 0.30),
        block('下午', 0.02, 0.43, 0.09, 0.30),
        block('晚上', 0.02, 0.75, 0.09, 0.30),
      ];

  static OcrTextBlock courseBlock(
      String cellText, int day, int startSlot, int endSlot,
      {double margin = 0.008}) {
    final colLeft = columnLefts[day - 1];
    final top = rowCenter(startSlot - 1) - 0.03 + margin;
    final bottom = rowCenter(endSlot - 1) + 0.03 - margin;
    return block(cellText, colLeft + 0.01, top, columnWidth - 0.02,
        bottom - top);
  }

  static const courseData = <(String, int, int, int)>[
    ('高等数学A\n张明远\n1-16周\n教一101', 1, 1, 2),
    ('数据结构\n周启航\n1-16周\n计算机楼205', 2, 1, 2),
    ('创新创业实践\n林晓\n3-15周(单)\n创客空间', 6, 1, 2),
    ('大学英语III\n李婉清\n1-16周\n外语楼302', 1, 3, 4),
    ('高等数学A\n张明远\n1-16周\n教一101', 3, 3, 4),
    ('体育\n王强\n1-16周\n东区体育场', 4, 3, 4),
    ('数据结构\n周启航\n1-16周\n计算机楼205', 5, 3, 4),
    ('计算机网络\n陈思远\n1-16周\n实验楼401', 2, 5, 6),
    ('操作系统\n刘一鸣\n1-16周\n计算机楼301', 3, 5, 6),
    ('机器学习导论\n孙宁\n1-12周\n计算机楼402', 5, 5, 6),
    ('线性代数\n王建国\n1-8周\n教二201\n概率论与数理统计\n李芳\n10-16周\n教二202', 2, 7, 8),
    ('形势与政策\n赵海燕\n1-8周\n文科楼108', 4, 7, 8),
    ('数字电路实验\n郑伟\n3-14周\n实验楼203', 5, 9, 10),
  ];

  /// 完整模拟识别结果（14 门课、12 行节次、7 列星期 + 段标题噪声）。
  static List<OcrTextBlock> blocks() => [
        ...headers(),
        ...periodLabels(),
        ...groupLabels(),
        for (final c in courseData) courseBlock(c.$1, c.$2, c.$3, c.$4),
      ];
}
