import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/import/import_preview.dart';
import '../services/jwxt/cas_urp_client.dart';
import '../services/jwxt/jwxt_exception.dart';
import '../services/jwxt/jwxt_types.dart';
import '../services/jwxt/qz_jwxt_client.dart';
import 'import_decision.dart';
import 'review_page.dart';

/// 系统类型选择。
enum _JwxtSystem { auto, qz, cas }

/// 教务直连导入页：支持强智教务（jsxsd）与统一身份认证（CAS）+ URP。
/// 自动识别系统类型，支持验证码人工输入（不绕过、不破解）。
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
  final QzJwxtClient _qzClient = QzJwxtClient();
  final CasUrpClient _casClient = CasUrpClient();

  _JwxtSystem _system = _JwxtSystem.auto;
  bool _isCas = false;
  JwxtLoginChallenge? _qzChallenge;
  CasLoginChallenge? _casChallenge;
  Uint8List? _captchaImage;
  bool _captchaShown = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _errorHint;

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    _semester.dispose();
    _captcha.dispose();
    _qzClient.close();
    _casClient.close();
    super.dispose();
  }

  bool _detectCas() {
    final text = _url.text.trim();
    switch (_system) {
      case _JwxtSystem.cas:
        return true;
      case _JwxtSystem.qz:
        return false;
      case _JwxtSystem.auto:
        if (RegExp(r'authserver|/cas\b|eams', caseSensitive: false)
            .hasMatch(text)) {
          return true;
        }
        if (RegExp(r'jsxsd', caseSensitive: false).hasMatch(text)) return false;
        return _isCas; // 无法识别：保持上次选择
    }
  }

  Future<void> _start() async {
    final text = _url.text.trim();
    if (text.isEmpty) {
      setState(() {
        _error = '请填写教务系统登录地址';
        _errorHint = '把浏览器地址栏里登录页的完整地址粘贴进来';
      });
      return;
    }
    final isCas = _detectCas();
    if (_system == _JwxtSystem.auto &&
        !RegExp(r'authserver|/cas\b|eams|jsxsd', caseSensitive: false)
            .hasMatch(text)) {
      setState(() {
        _error = '无法自动识别教务系统类型';
        _errorHint = '请手动选择「强智教务」或「统一认证（CAS）」后重试';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _errorHint = null;
      _isCas = isCas;
      _qzChallenge = null;
      _casChallenge = null;
      _captchaShown = false;
      _captchaImage = null;
    });
    try {
      if (isCas) {
        final challenge = await _casClient.prepareLogin(text);
        if (!mounted) return;
        setState(() => _casChallenge = challenge);
        await _loginCas(challenge, '');
      } else {
        final challenge = await _qzClient.prepareLogin(text);
        if (!mounted) return;
        setState(() => _qzChallenge = challenge);
        if (challenge.captchaField == null) {
          await _loginQz(challenge, '');
        } else {
          setState(() {
            _captchaShown = true;
            _captchaImage = challenge.captchaImage;
            _busy = false;
          });
        }
      }
    } on JwxtException catch (e) {
      _fail(e);
    } catch (e) {
      _fail(JwxtException(JwxtErrorKind.network, '连接失败：$e'));
    }
  }

  Future<void> _loginQz(JwxtLoginChallenge challenge, String captcha) async {
    setState(() {
      _busy = true;
      _error = null;
      _errorHint = null;
    });
    try {
      final result = await _qzClient.loginAndImport(
        challenge,
        username: _username.text.trim(),
        password: _password.text,
        captcha: captcha,
        semester: _semester.text.trim(),
      );
      await _openReview(result);
    } on JwxtException catch (e) {
      _fail(e);
    } catch (e) {
      _fail(JwxtException(JwxtErrorKind.network, '导入失败：$e'));
    }
  }

  Future<void> _loginCas(CasLoginChallenge challenge, String captcha) async {
    setState(() {
      _busy = true;
      _error = null;
      _errorHint = null;
    });
    try {
      final result = await _casClient.loginAndImport(
        challenge,
        username: _username.text.trim(),
        password: _password.text,
        captcha: captcha,
      );
      await _openReview(result);
    } on JwxtException catch (e) {
      if (e.kind == JwxtErrorKind.captchaRequired) {
        try {
          final bytes = await _casClient.fetchCaptcha(challenge);
          if (!mounted) return;
          setState(() {
            _captchaShown = true;
            _captchaImage = bytes;
            _captcha.clear();
            _busy = false;
            _error = e.message;
            _errorHint = e.hint;
          });
        } catch (fe) {
          _fail(JwxtException(
              JwxtErrorKind.network, '验证码图片加载失败：$fe'));
        }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          DropdownButtonFormField<_JwxtSystem>(
            initialValue: _system,
            decoration: const InputDecoration(
              labelText: '系统类型',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                  value: _JwxtSystem.auto, child: Text('自动识别')),
              DropdownMenuItem(
                  value: _JwxtSystem.qz, child: Text('强智教务（jsxsd）')),
              DropdownMenuItem(
                  value: _JwxtSystem.cas, child: Text('统一身份认证（CAS）')),
            ],
            onChanged: (v) => setState(() => _system = v ?? _JwxtSystem.auto),
          ),
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
          if (!_isCas) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _semester,
              decoration: const InputDecoration(
                labelText: '学期（可选）',
                hintText: '如 2026-2027-1；留空导入当前学期',
                border: OutlineInputBorder(),
              ),
            ),
          ],
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
            onPressed: _busy
                ? null
                : () {
                    if (_captchaShown) {
                      if (_isCas && _casChallenge != null) {
                        _loginCas(_casChallenge!, _captcha.text.trim());
                      } else if (_qzChallenge != null) {
                        _loginQz(_qzChallenge!, _captcha.text.trim());
                      } else {
                        _start();
                      }
                    } else {
                      _start();
                    }
                  },
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
