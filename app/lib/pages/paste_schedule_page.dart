import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakeclass_core/wakeclass_core.dart';

import '../services/import/external_import.dart';
import '../services/import/import_preview.dart';
import '../services/import/pc_capture_scripts.dart';
import '../services/jwxt/schedule_table_parser.dart';
import '../services/jwxt/zfsoft_client.dart' show courseFromKbItem;
import 'import_decision.dart';
import 'review_page.dart';

/// 粘贴导入：把电脑上取到的课表页面 HTML 或接口 JSON 弄进手机解析。
///
/// 专门解决「教务系统只能在校园网 / 内网访问，手机上又连不上」：
/// 电脑打开课表页 → 取到数据（书签脚本 / F12 / 复制源代码）→ 发到手机 →
/// 粘贴（或直接把文件分享给醒课）→ 解析 → 校对 → 导入。
class PasteSchedulePage extends StatefulWidget {
  const PasteSchedulePage({super.key, this.initialText, this.autoParse = false});

  /// 外部送进来、预填到输入框的内容（如微信里「用其他应用打开」的文件）。
  final String? initialText;

  /// 预填后是否立刻解析（外部导入时省一次点击）。
  final bool autoParse;

  @override
  State<PasteSchedulePage> createState() => _PasteSchedulePageState();
}

class _PasteSchedulePageState extends State<PasteSchedulePage> {
  /// 超过这个长度就不往输入框里塞：几百 KB 的网页源码会让输入框排版卡住。
  static const int _bulkThreshold = 20000;

  final TextEditingController _text = TextEditingController();

  /// 超长内容（不进输入框），与 [_text] 二选一。
  String? _bulk;

  bool _busy = false;
  String? _error;
  String _subtitle = '粘贴导入';

  @override
  void initState() {
    super.initState();
    final initial = widget.initialText;
    if (initial != null && initial.trim().isNotEmpty) {
      _load(initial, subtitle: '文件导入');
      if (widget.autoParse) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _parse();
        });
      }
    }
  }

  /// 把一段内容放进页面：太长就只记在内存里，不塞进输入框。
  void _load(String text, {required String subtitle}) {
    _subtitle = subtitle;
    if (text.length > _bulkThreshold) {
      _bulk = text;
      _text.clear();
    } else {
      _bulk = null;
      _text.text = text;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text ?? '';
    if (text.isEmpty) {
      setState(() => _error = '剪贴板是空的');
      return;
    }
    setState(() {
      _load(text, subtitle: '粘贴导入');
      _error = null;
    });
  }

  /// 系统文件选择器（微信收到的 .html / .txt / .json 也能在这里选）。
  Future<void> _importFromFile() async {
    if (!ExternalImport.isSupported) {
      setState(() => _error = '当前系统不支持选择文件，请用「从剪贴板粘贴」');
      return;
    }
    final text = await ExternalImport.pickFile();
    if (!mounted || text == null) return; // 取消选择
    setState(() {
      _load(text, subtitle: '文件导入');
      _error = null;
    });
    await _parse();
  }

  Future<void> _parse() async {
    final raw = (_bulk ?? _text.text).trim();
    if (raw.isEmpty) {
      setState(() => _error = '请先粘贴课表页面的 HTML 或接口返回的 JSON');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final warnings = <String>[];
    final courses = <Course>[];

    // 1) JSON（正方 kbList / 直接是数组）。
    if (raw.startsWith('{') || raw.startsWith('[')) {
      try {
        final decoded = jsonDecode(raw);
        final list = _kbListOf(decoded);
        if (list != null) {
          for (final item in list) {
            if (item is! Map) continue;
            final course = courseFromKbItem(item, warnings);
            if (course != null) courses.add(course);
          }
        }
      } catch (_) {
        // 不是 JSON：继续按 HTML 解析
      }
    }

    // 2) HTML 表格。
    if (courses.isEmpty) {
      const parser = ScheduleTableParser();
      final parsed = parser.parseSchedule(raw, source: 'paste');
      courses.addAll(parsed.courses);
      warnings.addAll(parsed.warnings);
    }

    if (!mounted) return;
    setState(() => _busy = false);
    if (courses.isEmpty) {
      setState(() => _error =
          '没有解析出课程。正方请用书签脚本或 F12 取接口 JSON（直接复制网页源代码是空的）；'
          '其他系统请复制「含星期表头」的课表表格。');
      return;
    }

    final decision = await Navigator.of(context).push<ImportDecision>(
      MaterialPageRoute(
        builder: (_) => ReviewPage(
          preview: ImportPreview(
            courses: courses,
            warnings: warnings,
            subtitle: _subtitle,
          ),
        ),
      ),
    );
    if (decision != null && mounted) {
      Navigator.of(context).pop(decision);
    }
  }

  /// 从 JSON 里找课程数组：`{kbList:[...]}` 或 `{data:{kbList:[...]}}` 或直接数组。
  List? _kbListOf(Object? decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      final direct = decoded['kbList'];
      if (direct is List) return direct;
      for (final value in decoded.values) {
        if (value is Map) {
          final nested = value['kbList'];
          if (nested is List) return nested;
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chars = (_bulk ?? _text.text).trim().length;
    return Scaffold(
      appBar: AppBar(title: const Text('粘贴导入')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '教务只能校园网 / 内网访问、手机上连不上时用这里：'
            '在电脑上取到课表数据，发到手机粘进来。',
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            '最省事的替代方案：电脑打开课表页截图 → 发到手机 → 用「截图导入」识别。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          if (_bulk != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '已读取 ${_bulk!.length} 个字符（内容较大，不显示在输入框里）',
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _bulk = null),
                    child: const Text('清空'),
                  ),
                ],
              ),
            )
          else
            TextField(
              controller: _text,
              maxLines: 8,
              minLines: 5,
              style: const TextStyle(fontSize: 12, height: 1.35),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: '课表页面 HTML / 接口 JSON',
                hintText: '<html>… 或 {"kbList":[…]',
                helperText: chars == 0 ? null : '已粘贴 $chars 个字符',
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _pasteFromClipboard,
                  icon: const Icon(Icons.content_paste, size: 18),
                  label: const Text('从剪贴板粘贴'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _parse,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('解析'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy || !ExternalImport.isSupported ? null : _importFromFile,
            icon: const Icon(Icons.folder_open, size: 18),
            label: Text(
              ExternalImport.isSupported
                  ? '选择文件（.html / .txt / .json）'
                  : '当前系统不支持选择文件',
            ),
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 16),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              leading: const Icon(Icons.desktop_windows_outlined),
              title: const Text('电脑上怎么取数据（点开看）'),
              subtitle: const Text('正方要用书签脚本或 F12；强智 / 青果可直接复制源代码'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '⚠️ 正方（jwglxt）的课表格子是浏览器里现画的，'
                    '右键「查看网页源代码」只有空壳、拿不到课程。'
                    '正方请用下面的书签脚本，或 F12 里的接口返回。',
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                  ),
                ),
                const _ScriptTile(
                  title: '① 正方：一键复制课表接口 JSON（推荐）',
                  script: PcCaptureScripts.zfsoft,
                ),
                const _ScriptTile(
                  title: '② 任意系统：复制页面上渲染好的课表表格',
                  script: PcCaptureScripts.table,
                ),
                const SizedBox(height: 12),
                Text(
                  '怎么用书签脚本\n'
                  '1. 电脑浏览器按 Ctrl+D 收藏当前页 → 「修改 / 更多」→ 名称随便填，'
                  '网址清空后粘贴上面整段脚本 → 保存\n'
                  '2. 打开教务课表页（能看到一行行课程格子）\n'
                  '3. 点一下这个书签 → 会弹窗提示「已复制 N 个字符」\n'
                  '4. 微信「文件传输助手」把内容发到手机 → 复制 → 回来点「从剪贴板粘贴」',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.6),
                ),
                const SizedBox(height: 12),
                Text(
                  '不用脚本的办法\n'
                  '• 正方：F12 → Network（网络）→ 刷新课表页 → 点开 '
                  'xskbcx_cxXsKb.html → 右键「Copy response」\n'
                  '• 强智 / 青果 / URP：右键「查看网页源代码」→ Ctrl+A → Ctrl+C\n'
                  '• 懒人版：课表页直接截图发手机，用「截图导入」识别，任何系统都能用',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 一段书签脚本：预览 + 复制 / 发到电脑。
class _ScriptTile extends StatelessWidget {
  const _ScriptTile({required this.title, required this.script});

  final String title;
  final String script;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: script));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('脚本已复制。要在电脑上添加成书签，请点「发到电脑」'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _send(BuildContext context) async {
    final ok = await ExternalImport.shareText(script);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '选择「文件传输助手」发到电脑，再复制成书签' : '当前系统不支持分享'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              script,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _copy(context),
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('复制脚本'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: ExternalImport.isSupported
                    ? () => _send(context)
                    : null,
                icon: const Icon(Icons.send_outlined, size: 16),
                label: const Text('发到电脑'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
