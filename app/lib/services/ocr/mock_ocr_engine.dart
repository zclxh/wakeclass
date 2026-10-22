import 'package:wakeclass_core/wakeclass_core.dart';

import 'mock_schedule_data.dart';
import 'ocr_engine.dart';

/// 演示 OCR 引擎：返回内置的模拟识别结果。
///
/// 用于：
/// - Windows / macOS / Linux 桌面开发调试（ML Kit 仅支持移动端）；
/// - 新用户体验完整导入流程（无需真实课表截图）。
class MockOcrEngine implements OcrEngine {
  @override
  String get name => '演示数据';

  @override
  String get description => '内置一份模拟课表截图识别结果，无需图片即可体验导入流程';

  @override
  bool get isAvailable => true;

  @override
  Future<List<OcrTextBlock>> recognizeFile(String path) async {
    // 模拟识别耗时，让进度状态可见。
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return MockScheduleData.blocks();
  }
}
