import 'package:wakeclass_core/wakeclass_core.dart';

import 'ocr_engine.dart';

/// Web 平台占位实现：ML Kit 端上识别不支持 Web。
///
/// 通过 `ocr_engines.dart` 的条件导出在 Web 构建时替换真实实现，
/// 使 `flutter build web` 不编译 google_mlkit 插件与 dart:io 代码；
/// Web 端使用「演示导入」体验完整流程。
class MlKitOcrEngine implements OcrEngine {
  @override
  String get name => '端上识别（ML Kit）';

  @override
  String get description => '端上识别仅支持 Android / iOS；Web 端请使用演示导入';

  @override
  bool get isAvailable => false;

  @override
  Future<List<OcrTextBlock>> recognizeFile(String path) {
    throw UnsupportedError('ML Kit 不支持当前平台');
  }
}
