/// OCR 引擎工厂：按平台导出 ML Kit 实现或 Web 占位实现。
///
/// Web 构建时 `dart.library.js_interop` 为真，选择占位实现，
/// 避免编译 google_mlkit 插件（无 Web 支持）与 dart:io 代码。
library;

export 'mlkit_ocr_engine.dart'
    if (dart.library.js_interop) 'mlkit_ocr_engine_stub.dart';
