import 'package:wakeclass_core/wakeclass_core.dart';

/// OCR 引擎抽象：图片 → 带边界框的文本块列表。
///
/// 实现与识别细节解耦：
/// - [MlKitOcrEngine]：端上识别（Android / iOS）；
/// - [MockOcrEngine]：内置演示数据（开发机 / 无真机时体验全流程）；
/// - 未来可扩展云端 OCR（百度/腾讯）或 PaddleOCR。
abstract class OcrEngine {
  /// 引擎名称（展示用）。
  String get name;

  /// 引擎说明。
  String get description;

  /// 当前平台是否可用。
  bool get isAvailable;

  /// 识别图片文件，返回带相对坐标（0..1）的文本块。
  Future<List<OcrTextBlock>> recognizeFile(String path);
}
