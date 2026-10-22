import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show decodeImageFromList;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:wakeclass_core/wakeclass_core.dart';

import 'ocr_engine.dart';

/// Google ML Kit 文字识别（端上）：免费、离线、支持中英文，
/// 返回带边界框的文本行，是截图导入的默认引擎。
class MlKitOcrEngine implements OcrEngine {
  @override
  String get name => '端上识别（ML Kit）';

  @override
  String get description => '离线识别，不联网、不上传图片，支持中英文混合';

  @override
  bool get isAvailable => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Future<List<OcrTextBlock>> recognizeFile(String path) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
    try {
      final input = InputImage.fromFilePath(path);

      // 图片尺寸（用于把像素坐标归一化为 0..1）。
      final bytes = await File(path).readAsBytes();
      final image = await decodeImageFromList(bytes);
      final w = image.width.toDouble();
      final h = image.height.toDouble();
      image.dispose();

      final text = await recognizer.processImage(input);
      final blocks = <OcrTextBlock>[];
      for (final block in text.blocks) {
        for (final line in block.lines) {
          final rect = line.boundingBox;
          final content = line.text.trim();
          if (content.isEmpty) continue;
          blocks.add(OcrTextBlock(
            text: content,
            left: rect.left / w,
            top: rect.top / h,
            width: rect.width / w,
            height: rect.height / h,
          ));
        }
      }
      return blocks;
    } finally {
      recognizer.close();
    }
  }
}
