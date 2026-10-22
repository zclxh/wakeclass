import 'package:wakeclass_core/wakeclass_core.dart';

import '../ocr/ocr_engine.dart';
import 'import_preview.dart';

/// 一次导入的结果：成功携带 [ImportPreview]，失败携带 [error]。
class ImportOutcome {
  const ImportOutcome({this.preview, this.error, this.engineName = ''});

  final ImportPreview? preview;
  final String? error;
  final String engineName;

  bool get ok => error == null;
}

/// 截图导入服务：图片 → OCR → 网格解析 → 课程预览。
class ScreenshotImportService {
  const ScreenshotImportService(this.engine);

  final OcrEngine engine;

  Future<ImportOutcome> importImage(String path, {int totalWeeks = 20}) async {
    try {
      final blocks = await engine.recognizeFile(path);
      if (blocks.isEmpty) {
        return ImportOutcome(
          error: '未识别到任何文字。请换一张更清晰、完整的课表截图。',
          engineName: engine.name,
        );
      }
      final result = const GridParser().parse(blocks, totalWeeks: totalWeeks);
      return ImportOutcome(
        preview: ImportPreview.fromGridParseResult(result).withSubtitle(
          '${engine.name} · 识别出 ${result.courses.length} 门课',
        ),
        engineName: engine.name,
      );
    } catch (e) {
      return ImportOutcome(
        error: '识别失败：$e',
        engineName: engine.name,
      );
    }
  }
}
