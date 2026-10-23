import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakeclass_core/wakeclass_core.dart';

import '../services/import/import_preview.dart';
import '../services/jwxt/schedule_table_parser.dart';
import '../services/jwxt/zfsoft_client.dart' show courseFromKbItem;
import 'import_decision.dart';
import 'review_page.dart';

/// 粘贴导入：把电脑上拿到的课表页面 HTML 或接口 JSON 粘进来解析。
///
/// 专门解决「教务系统只能内网 / VPN 访问，手机上连不上」的情况：
/// 电脑连学校 VPN → 打开课表页 → 右键「查看网页源代码」复制，
/// 或 F12 里复制 `xskbcx_cxXsKb.html` 接口返回的 JSON → 微信发到手机 → 粘贴到这里。
class PasteSchedulePage extends StatefulWidget {
  const PasteSchedulePage({super.key});

  @override
  State<PasteSchedulePage> createState() => _PasteSchedulePageState();
}

class _PasteSchedulePageState extends State<PasteSchedulePage> {
  final TextEditingController _text = TextEditingController();
  bool _busy = false;
  String? _error;

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
    _text.text = text;
    setState(() => _error = null);
  }

  Future<void> _parse() async {
    final raw = _text.text.trim();
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

    // 1) JSON（正方 kbList / 数组）。
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
          '没有解析出课程。请确认粘贴的是「课表页面」的源代码（含星期表头），'
          '或正方课表接口返回的 JSON（含 kbList）。');
      return;
    }

    final decision = await Navigator.of(context).push<ImportDecision>(
      MaterialPageRoute(
        builder: (_) => ReviewPage(
          preview: ImportPreview(
            courses: courses,
            warnings: warnings,
            subtitle: '粘贴导入',
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
    return Scaffold(
      appBar: AppBar(title: const Text('粘贴导入')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '适用场景：学校教务只能在校园网 / VPN 里访问，手机上连不上。',
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            '1. 电脑连上学校 VPN / 校园网，打开教务课表页\n'
            '2. 右键「查看网页源代码」→ Ctrl+A 全选复制\n'
            '   （正方也可按 F12 → Network → 点开 xskbcx_cxXsKb.html → 复制返回的 JSON）\n'
            '3. 把内容发到手机（微信/QQ 文件传输），回来点「从剪贴板粘贴」\n'
            '4. 解析后进入校对页，确认无误再导入',
            style: theme.textTheme.bodySmall?.copyWith(height: 1.6),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            maxLines: 12,
            minLines: 6,
            style: const TextStyle(fontSize: 12, height: 1.35),
            decoration: const InputDecoration(
              labelText: '课表页面 HTML / 接口 JSON',
              hintText: '<html>… 或 {"kbList":[…]',
              border: OutlineInputBorder(),
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
          const SizedBox(height: 16),
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
          if (_busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }
}
