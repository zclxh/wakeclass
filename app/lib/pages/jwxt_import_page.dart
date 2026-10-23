import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/import/import_preview.dart';
import '../services/jwxt/jwxt_adapter.dart';
import '../services/jwxt/jwxt_exception.dart';
import '../services/jwxt/jwxt_types.dart';
import 'import_decision.dart';
import 'review_page.dart';

/// 教务直连导入页。
///
/// 通过 [JwxtAdapter] 统一接入多种教务系统（正方 / 强智 / 统一认证 / 通用），
/// 自动识别系统类型；页面不再按厂商分支，新增系统只要加一个适配器。
class JwxtImportPage extends StatefulWidget {
  const JwxtImportPage({super.key});

  @override
  State<JwxtImportPage> createState() => _JwxtImportPageState();
}

class _JwxtImportPageState extends State<JwxtImportPage> {
  final _url = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _semester = TextEditingController();
  final _captcha = TextEditingController();

  late final List<JwxtAdapter> _adapters = JwxtAdapterRegistry.create();

  /// 下拉框手动选择的适配器；null 表示自动识别。
  JwxtAdapter? _selected;
  JwxtAdapter? _active;
  JwxtLoginState? _state;

  Uint8List? _captchaImage;
  bool _captchaShown = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _errorHint;
  String? _detected;

  /// 快速选择学校下拉框的当前值（空串 = 未选）。
  String _presetSchool = '';

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    _semester.dispose();
    _captcha.dispose();
    for (final adapter in _adapters) {
      adapter.close();
    }
    super.dispose();
  }

  /// 当前应使用的适配器（下拉框选择优先，否则按 URL 自动识别）。
  JwxtAdapter _primaryAdapter(String url) =>
      _selected ?? JwxtAdapterRegistry.detect(url, _adapters);

  Future<void> _start() async {
    final text = _url.text.trim();
    if (text.isEmpty) {
      setState(() {
        _error = '请填写教务系统登录地址';
        _errorHint = '把浏览器地址栏里登录页的完整地址粘贴进来';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _errorHint = null;
      _captchaShown = false;
      _captchaImage = null;
      _detected = null;
      _state = null;
      _active = null;
    });

    final primary = _primaryAdapter(text);
    final candidates = <JwxtAdapter>[primary];
    // 自动识别落到「通用」时，如果其实是统一认证页，再试一次 CAS。
    if (_selected == null && primary.id == 'generic') {
      final cas = JwxtAdapterRegistry.byId('cas', _adapters);
      if (cas != null) candidates.add(cas);
    }

    JwxtException? lastError;
    for (final adapter in candidates) {
      try {
        final state = await adapter.prepare(text);
        if (!mounted) return;
        setState(() {
          _active = adapter;
          _state = state;
          _detected = state.systemName;
          _busy = false;
        });
        if (state.needsCaptcha) {
          setState(() {
            _captchaShown = true;
            _captchaImage = state.captchaImage;
            _captcha.clear();
          });
          return;
        }
        await _login(state, '');
        return;
      } on JwxtException catch (e) {
        lastError = e;
        if (adapter == candidates.last) break;
        // 继续尝试下一个候选适配器
      } catch (e) {
        lastError = JwxtException(JwxtErrorKind.network, '连接失败：$e');
        if (adapter == candidates.last) break;
      }
    }
    _fail(lastError ??
        const JwxtException(JwxtErrorKind.network, '无法连接教务系统'));
  }

  Future<void> _login(JwxtLoginState state, String captcha) async {
    final adapter = _active;
    if (adapter == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _errorHint = null;
    });
    try {
      final result = await adapter.login(
        state,
        username: _username.text.trim(),
        password: _password.text,
        captcha: captcha,
        semester: _semester.text.trim(),
      );
      await _openReview(result);
    } on JwxtException catch (e) {
      if (e.kind == JwxtErrorKind.captchaRequired) {
        Uint8List? image;
        try {
          image = await adapter.refreshCaptcha(state);
        } catch (_) {
          image = state.captchaImage;
        }
        if (!mounted) return;
        setState(() {
          _captchaShown = true;
          _captchaImage = image ?? state.captchaImage;
          _captcha.clear();
          _busy = false;
          _error = e.message;
          _errorHint = e.hint;
        });
      } else {
        _fail(e);
      }
    } catch (e) {
      _fail(JwxtException(JwxtErrorKind.network, '导入失败：$e'));
    }
  }

  Future<void> _openReview(JwxtImportResult result) async {
    if (!mounted) return;
    setState(() => _busy = false);
    final decision = await Navigator.of(context).push<ImportDecision>(
      MaterialPageRoute(
        builder: (_) => ReviewPage(preview: ImportPreview.fromJwxtResult(result)),
      ),
    );
    if (decision != null && mounted) {
      Navigator.of(context).pop(decision);
    }
  }

  void _fail(JwxtException e) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = e.message;
      _errorHint = e.hint;
    });
  }

  void _submit() {
    if (_captchaShown) {
      final state = _state;
      if (state != null) {
        _login(state, _captcha.text.trim());
      } else {
        _start();
      }
    } else {
      _start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selected;
    final hint = selected?.hint ??
        '支持正方（jwglxt）、强智（jsxsd）、统一认证（CAS）+ URP，以及其它「表单登录 + 表格课表」的系统';
    return Scaffold(
      appBar: AppBar(title: const Text('教务直连')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) ...[
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _error!,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onErrorContainer),
                    ),
                    if (_errorHint != null && _errorHint!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        _errorHint!,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          DropdownButtonFormField<String>(
            initialValue: _presetSchool,
            decoration: const InputDecoration(
              labelText: '快速选择学校（可选）',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('不选，手动填写地址')),
              for (final preset in jwxtPresets)
                DropdownMenuItem(
                    value: preset.school, child: Text(preset.school)),
            ],
            onChanged: (value) {
              if (value == null || value.isEmpty) {
                setState(() => _presetSchool = '');
                return;
              }
              final preset = jwxtPresets.firstWhere((p) => p.school == value);
              setState(() {
                _presetSchool = value;
                _url.text = preset.loginUrl;
                _selected = JwxtAdapterRegistry.byId(preset.adapterId, _adapters);
              });
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selected?.id ?? 'auto',
            decoration: const InputDecoration(
              labelText: '系统类型',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: 'auto', child: Text('自动识别')),
              for (final adapter in _adapters)
                DropdownMenuItem(value: adapter.id, child: Text(adapter.name)),
            ],
            onChanged: (v) => setState(() {
              _selected = (v == null || v == 'auto')
                  ? null
                  : JwxtAdapterRegistry.byId(v, _adapters);
            }),
          ),
          if (_detected != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.check_circle_outline,
                    size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  '已识别：$_detected',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: '教务系统登录地址 *',
              hintText: '浏览器地址栏里登录页的完整地址',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hint,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _username,
            decoration: const InputDecoration(
              labelText: '学号 *',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: '密码 *',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _semester,
            decoration: const InputDecoration(
              labelText: '学期（可选）',
              hintText: '如 2026-2027-1；留空导入当前学期',
              border: OutlineInputBorder(),
            ),
          ),
          if (_captchaShown) ...[
            const SizedBox(height: 12),
            if (_captchaImage != null)
              Center(
                child: Image.memory(
                  _captchaImage!,
                  height: 56,
                  fit: BoxFit.fitHeight,
                  errorBuilder: (context, error, stack) => const Text(
                    '验证码图片加载失败',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _captcha,
              decoration: const InputDecoration(
                labelText: '验证码 *',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: const Icon(Icons.cloud_download_outlined),
            label: Text(_captchaShown ? '提交验证码并登录' : '登录并导入'),
          ),
          const SizedBox(height: 16),
          Text(
            '账号密码仅用于本次登录请求，不写入本地存储。\n'
            '统一认证支持验证码图片人工输入；微信扫码 / 短信验证码等'
            '登录方式无法自动完成，请改用截图导入。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
