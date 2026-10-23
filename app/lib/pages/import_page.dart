import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/import/screenshot_import_service.dart';
import '../services/ocr/mock_ocr_engine.dart';
import '../services/ocr/ocr_engine.dart';
import '../services/ocr/ocr_engines.dart';
import 'import_decision.dart';
import 'jwxt_import_page.dart';
import 'paste_schedule_page.dart';
import 'review_page.dart';

/// 导入页：演示导入 / 相册选图 / 拍照。
class ImportPage extends StatefulWidget {
  const ImportPage({super.key});

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  final MlKitOcrEngine _mlkit = MlKitOcrEngine();
  final MockOcrEngine _mock = MockOcrEngine();
  final ImagePicker _picker = ImagePicker();
  bool _busy = false;

  Future<void> _run(OcrEngine engine, {String path = ''}) async {
    setState(() => _busy = true);
    final outcome =
        await ScreenshotImportService(engine).importImage(path);
    if (!mounted) return;
    setState(() => _busy = false);

    if (!outcome.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(outcome.error ?? '识别失败')),
      );
      return;
    }
    final decision = await Navigator.of(context).push<ImportDecision>(
      MaterialPageRoute(
        builder: (_) => ReviewPage(preview: outcome.preview!),
      ),
    );
    if (decision != null && mounted) {
      Navigator.of(context).pop(decision);
    }
  }

  Future<void> _openJwxt() async {
    final decision = await Navigator.of(context).push<ImportDecision>(
      MaterialPageRoute(builder: (_) => const JwxtImportPage()),
    );
    if (decision != null && mounted) {
      Navigator.of(context).pop(decision);
    }
  }

  Future<void> _openPaste() async {
    final decision = await Navigator.of(context).push<ImportDecision>(
      MaterialPageRoute(builder: (_) => const PasteSchedulePage()),
    );
    if (decision != null && mounted) {
      Navigator.of(context).pop(decision);
    }
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await _picker.pickImage(source: source, imageQuality: 95);
      if (file == null) return;
      await _run(_mlkit, path: file.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择图片失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入课表')),
      body: _busy
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在识别课表…'),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _ImportCard(
                  icon: Icons.auto_fix_high,
                  title: '演示导入',
                  subtitle: '用内置的模拟课表截图体验完整识别流程，无需真实图片',
                  child: FilledButton.tonalIcon(
                    onPressed: () => _run(_mock),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('体验导入流程'),
                  ),
                ),
                _ImportCard(
                  icon: Icons.cloud_download_outlined,
                  title: '教务直连',
                  subtitle: '填写学校教务系统地址、学号和密码，支持正方（jwglxt）、'
                      '强智（jsxsd）、统一认证（CAS）与通用识别。'
                      '账号密码仅用于本次登录请求，不保存。',
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _openJwxt,
                    icon: const Icon(Icons.login),
                    label: const Text('直连导入'),
                  ),
                ),
                _ImportCard(
                  icon: Icons.content_paste_go,
                  title: '粘贴导入（内网专用）',
                  subtitle: '教务只能校园网访问、学校又没有 VPN 时：电脑上取到课表数据'
                      '（书签脚本 / F12 / 源代码）→ 发到手机 → 粘贴或选文件解析。'
                      '微信收到的 .html 也能「用其他应用打开 → 醒课」直接导入',
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _openPaste,
                    icon: const Icon(Icons.content_paste),
                    label: const Text('粘贴导入'),
                  ),
                ),
                _ImportCard(
                  icon: Icons.add_photo_alternate_outlined,
                  title: '截图导入（端上识别）',
                  subtitle: _mlkit.isAvailable
                      ? '选择教务系统课表页面的截图，离线识别、图片不上传'
                      : '端上识别需在 Android / iOS 真机运行；桌面端请使用演示导入',
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      FilledButton.icon(
                        onPressed:
                            _mlkit.isAvailable ? () => _pick(ImageSource.gallery) : null,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('从相册选择'),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            _mlkit.isAvailable ? () => _pick(ImageSource.camera) : null,
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('拍照'),
                      ),
                    ],
                  ),
                ),
                const _ImportCard(
                  icon: Icons.tips_and_updates_outlined,
                  title: '截图建议',
                  subtitle: '1. 截取完整课表（含星期表头与左侧节次列）\n'
                      '2. 尽量清晰、无缩放，避免反光\n'
                      '3. 识别后可在校对页修正任何字段',
                  child: SizedBox.shrink(),
                ),
              ],
            ),
    );
  }
}

class _ImportCard extends StatelessWidget {
  const _ImportCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
