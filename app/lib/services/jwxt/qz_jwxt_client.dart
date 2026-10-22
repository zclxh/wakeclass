import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart';
import 'package:html/parser.dart' show parse;
import 'package:http/http.dart' as http;

import 'jwxt_exception.dart';
import 'jwxt_types.dart';
import 'schedule_table_parser.dart';

/// 一次 HTTP 响应的摘要。
class _HttpResult {
  const _HttpResult(this.status, this.text, this.cookie, this.url);

  final int status;
  final String text;
  final String cookie;
  final String url;
}

/// 强智教务系统（jsxsd）直连客户端。
///
/// 移植自 Web 版 `wakeclass/lib/importers.mjs` 的 `qz()` 流程：
/// 探测登录页 → 识别表单/验证码 → 登录 → 定位课表页（xskb_list.do）
/// → 学期选择 → 解析课表 HTML。
///
/// 账号密码仅在本对象内存中随登录请求使用，不写入任何存储。
class QzJwxtClient {
  QzJwxtClient({http.Client? client, this.timeout = const Duration(seconds: 15)})
      : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  static const String systemName = '强智教务系统';

  /// 登录失败特征（响应仍含密码表单，或出现错误文案）。
  static final _loginFailRe =
      RegExp(r'用户名或密码|密码错误|登录失败|验证码错误|账号或密码');

  static final _credFieldPatterns = [
    RegExp(
        r'(?:^|_)(?:yhm|useraccount|username|userid|user_name|account|loginname|login_name|loginid|xh|studentid|studentno|uid|uname|accountname)(?:$|_)',
        caseSensitive: false),
    RegExp(r'学号|账号|帐号|用户名|工号'),
  ];

  static final _captchaNameRe = RegExp(
      r'^(?:yzm|randcode|randomcode|checkcode|validatecode|captcha|verifycode|vcode|jcaptcha)$',
      caseSensitive: false);
  static final _captchaImgRe = RegExp(
      r'(?:yzm|captcha|verify|checkcode|randcode|validate)',
      caseSensitive: false);

  // ---------- 第一步：探测登录页 ----------

  /// 归一化教务地址 → 强智根地址。
  static String normalizeBase(String raw) {
    final trimmed = raw.trim();
    Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (_) {
      throw const JwxtException(
          JwxtErrorKind.badUrl, '教务系统地址格式不正确', hint: '示例：https://jw.example.edu.cn');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const JwxtException(
          JwxtErrorKind.badUrl, '只支持 http / https 地址');
    }
    final origin = '${uri.scheme}://${uri.authority}';
    final path = uri.path;
    if (RegExp(r'/jsxsd', caseSensitive: false).hasMatch(path)) {
      final root =
          path.replaceFirst(RegExp(r'/jsxsd.*$', caseSensitive: false), '/jsxsd/');
      return '$origin$root';
    }
    return '$origin/jsxsd/';
  }

  /// 访问登录页，返回登录挑战（含是否需要验证码、验证码图片等）。
  Future<JwxtLoginChallenge> prepareLogin(String inputUrl) async {
    final base = normalizeBase(inputUrl);
    final _HttpResult loginPage;
    try {
      loginPage = await _get(base);
    } on TimeoutException {
      throw const JwxtException(
          JwxtErrorKind.network, '连接教务系统超时', hint: '请检查地址是否正确，或学校系统只允许校园网访问。');
    } catch (e) {
      throw JwxtException(JwxtErrorKind.network, '无法连接教务系统：$e');
    }
    if (!_hasPasswordForm(loginPage.text)) {
      throw const JwxtException(
          JwxtErrorKind.loginFormNotFound, '没有找到强智登录表单',
          hint: '请确认地址指向强智教务系统（通常以 /jsxsd/ 结尾）。');
    }

    final document = parse(loginPage.text);
    final form = _findLoginForm(document);
    if (form == null) {
      throw const JwxtException(
          JwxtErrorKind.loginFormNotFound, '强智登录表单结构无法识别');
    }

    final (userField, passwordField) = _findCredentialFields(form);
    final hidden = <String, String>{};
    for (final input in form.querySelectorAll('input')) {
      if (_typeOf(input) == 'hidden' && input.attributes['name'] != null) {
        hidden[input.attributes['name']!] = input.attributes['value'] ?? '';
      }
    }

    // 验证码探测。
    String? captchaField;
    Uint8List? captchaImage;
    final captchaCandidates = <String>[];
    for (final input in form.querySelectorAll('input')) {
      final type = _typeOf(input);
      if (type == 'text' || type.isEmpty) {
        final name = input.attributes['name'] ?? input.attributes['id'] ?? '';
        final placeholder = input.attributes['placeholder'] ?? '';
        if (_captchaNameRe.hasMatch(name) || placeholder.contains('验证码')) {
          captchaCandidates.add(name);
        }
      }
    }
    if (captchaCandidates.isNotEmpty) {
      captchaField = captchaCandidates.first;
      captchaImage = await _fetchCaptchaImage(form, base, loginPage.cookie);
    }

    final action = _absolute(form.attributes['action'], loginPage.url, base);

    return JwxtLoginChallenge(
      baseUrl: base,
      loginAction: action,
      userField: userField,
      passwordField: passwordField,
      hiddenFields: hidden,
      cookie: loginPage.cookie,
      captchaField: captchaField,
      captchaImage: captchaImage,
    );
  }

  // ---------- 第二步：登录并导入课表 ----------

  Future<JwxtImportResult> loginAndImport(
    JwxtLoginChallenge challenge, {
    required String username,
    required String password,
    String captcha = '',
    String? semester,
  }) async {
    // 登录。
    final data = <String, String>{...challenge.hiddenFields};
    data[challenge.userField] = username;
    data[challenge.passwordField] = password;
    if (challenge.captchaField != null) {
      data[challenge.captchaField!] = captcha;
    }

    _HttpResult loginRes;
    try {
      loginRes = await _post(
        challenge.loginAction,
        data,
        cookie: challenge.cookie,
        referer: challenge.baseUrl,
      );
    } on TimeoutException {
      throw const JwxtException(
          JwxtErrorKind.network, '登录请求超时', hint: '请检查网络后重试。');
    } catch (e) {
      throw JwxtException(JwxtErrorKind.network, '登录请求失败：$e');
    }

    if (_hasPasswordForm(loginRes.text) || _loginFailRe.hasMatch(loginRes.text)) {
      throw JwxtException(
        JwxtErrorKind.loginFailed,
        _loginErrorText(loginRes.text),
        hint: '请核对账号密码与验证码；如学校使用统一身份认证/微信扫码，请改用截图导入。',
      );
    }
    var cookie = loginRes.cookie;

    // 课表页（两个候选入口）。
    final scheduleUrl = '${challenge.baseUrl}xskb/xskb_list.do';
    var page = await _get(scheduleUrl, cookie: cookie, referer: loginRes.url);
    if (page.status >= 400 || !looksLikeSchedule(page.text)) {
      final alt = '${challenge.baseUrl}xskb/xskb_list.do?Ves632DSdyV=NEW';
      final altPage = await _get(alt, cookie: cookie, referer: loginRes.url);
      if (altPage.status < 400 && looksLikeSchedule(altPage.text)) {
        page = altPage;
      }
    }
    if (_hasPasswordForm(page.text)) {
      throw const JwxtException(JwxtErrorKind.sessionLost, '登录后访问课表页时登录状态失效');
    }
    if (!looksLikeSchedule(page.text)) {
      throw const JwxtException(
          JwxtErrorKind.noSchedule, '登录成功，但没有读取到课表',
          hint: '请确认本学期已排课，或在教务系统中手动打开一次课表后再试。');
    }

    // 学期选择。
    final warnings = <String>[];
    String? semesterLabel;
    var scheduleHtml = page.text;
    final options = _parseSemesters(parse(scheduleHtml));
    if (options.isNotEmpty) {
      final picked = _pickSemester(options, semester);
      semesterLabel = picked.label;
      if (picked.value.isNotEmpty) {
        try {
          final selected = await _post(
            page.url,
            {'xnxq01id': picked.value},
            cookie: cookie,
            referer: page.url,
          );
          if (looksLikeSchedule(selected.text)) {
            scheduleHtml = selected.text;
            cookie = selected.cookie;
          }
        } catch (_) {
          warnings.add('切换学期时网络异常，已导入默认学期课表。');
        }
      }
      warnings.add('学期：${picked.label}');
    }

    // 解析课表。
    const parser = ScheduleTableParser();
    final parsed = parser.parseSchedule(scheduleHtml, source: 'jwxt');
    final courses = parsed.courses;
    warnings.addAll(parsed.warnings);
    if (courses.isEmpty) {
      throw const JwxtException(
          JwxtErrorKind.noSchedule, '课表页面中没有解析出课程',
          hint: '页面结构可能比较特殊，请使用截图导入。');
    }

    return JwxtImportResult(
      courses: courses,
      warnings: warnings,
      systemName: systemName,
      semesterLabel: semesterLabel,
    );
  }

  void close() => _client.close();

  // ---------- HTTP 基础 ----------

  Future<_HttpResult> _get(String url,
      {String cookie = '', String referer = ''}) async {
    final request = http.Request('GET', Uri.parse(url));
    request.followRedirects = false;
    if (cookie.isNotEmpty) request.headers['Cookie'] = cookie;
    if (referer.isNotEmpty) request.headers['Referer'] = referer;
    request.headers['User-Agent'] =
        'Mozilla/5.0 (WakeClass) AppleWebKit/537.36';
    final streamed = await _client.send(request).timeout(timeout);
    final bytes = await streamed.stream.toBytes();
    final text = utf8.decode(bytes, allowMalformed: true);
    return _HttpResult(
      streamed.statusCode,
      text,
      _mergeCookie(cookie, streamed.headers['set-cookie']),
      streamed.request?.url.toString() ?? url,
    );
  }

  Future<_HttpResult> _post(
    String url,
    Map<String, String> data, {
    String cookie = '',
    String referer = '',
  }) async {
    final request = http.Request('POST', Uri.parse(url));
    request.followRedirects = false;
    if (cookie.isNotEmpty) request.headers['Cookie'] = cookie;
    if (referer.isNotEmpty) {
      request.headers['Referer'] = referer;
      request.headers['Origin'] = Uri.parse(referer).origin;
    }
    request.headers['User-Agent'] =
        'Mozilla/5.0 (WakeClass) AppleWebKit/537.36';
    request.bodyFields = data;
    final streamed = await _client.send(request).timeout(timeout);
    final bytes = await streamed.stream.toBytes();
    final text = utf8.decode(bytes, allowMalformed: true);
    return _HttpResult(
      streamed.statusCode,
      text,
      _mergeCookie(cookie, streamed.headers['set-cookie']),
      streamed.request?.url.toString() ?? url,
    );
  }

  String _mergeCookie(String existing, String? setCookie) {
    if (setCookie == null || setCookie.isEmpty) return existing;
    final jar = <String, String>{};
    for (final part in existing.split(';')) {
      final kv = part.trim().split('=');
      if (kv.length == 2 && kv[0].isNotEmpty) jar[kv[0]] = kv[1];
    }
    for (final sc in setCookie.split(',')) {
      final first = sc.trim().split(';').first;
      final kv = first.split('=');
      if (kv.length >= 2 && kv[0].isNotEmpty) jar[kv[0]] = kv[1];
    }
    return jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  // ---------- 表单解析 ----------

  bool _hasPasswordForm(String html) =>
      RegExp('<input\\b[^>]*type\\s*=\\s*["\']?password', caseSensitive: false)
          .hasMatch(html);

  Element? _findLoginForm(Document document) {
    for (final form in document.querySelectorAll('form')) {
      for (final input in form.querySelectorAll('input')) {
        if (_typeOf(input) == 'password') return form;
      }
    }
    return null;
  }

  String _typeOf(Element e) => (e.attributes['type'] ?? 'text').toLowerCase();

  (String, String) _findCredentialFields(Element form) {
    final inputs = form.querySelectorAll('input');
    String? passwordField;
    final textFields = <Element>[];
    for (final input in inputs) {
      final type = _typeOf(input);
      if (type == 'password' && passwordField == null) {
        passwordField = input.attributes['name'] ?? input.attributes['id'] ?? '';
      }
      if (type == 'text' || type == 'email' || type.isEmpty) {
        textFields.add(input);
      }
    }
    if (passwordField == null || passwordField.isEmpty) {
      throw const JwxtException(
          JwxtErrorKind.loginFormNotFound, '登录表单中没有密码输入框');
    }

    String fieldText(Element e) =>
        '${e.attributes['name'] ?? ''} ${e.attributes['id'] ?? ''} '
        '${e.attributes['placeholder'] ?? ''}';

    Element? userField;
    for (final pattern in _credFieldPatterns) {
      for (final f in textFields) {
        if (pattern.hasMatch(fieldText(f))) {
          userField = f;
          break;
        }
      }
      if (userField != null) break;
    }
    userField ??= textFields.where((f) {
      final t = fieldText(f);
      return !_captchaNameRe.hasMatch(t) &&
          !RegExp(r'验证码|search|keyword', caseSensitive: false).hasMatch(t);
    }).firstOrNull;

    if (userField == null) {
      throw const JwxtException(
          JwxtErrorKind.loginFormNotFound, '登录表单中找不到账号输入框');
    }
    return (
      userField.attributes['name'] ?? userField.attributes['id'] ?? '',
      passwordField,
    );
  }

  Future<Uint8List?> _fetchCaptchaImage(
      Element form, String base, String cookie) async {
    for (final img in form.querySelectorAll('img')) {
      final src = img.attributes['src'] ?? '';
      if (src.isEmpty || !_captchaImgRe.hasMatch(src)) continue;
      final url = _absolute(src, base, base);
      if (!url.startsWith('http')) continue;
      try {
        final request = http.Request('GET', Uri.parse(url));
        if (cookie.isNotEmpty) request.headers['Cookie'] = cookie;
        final streamed = await _client.send(request).timeout(timeout);
        if (streamed.statusCode >= 400) return null;
        return await streamed.stream.toBytes();
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  String _absolute(String? value, String baseUrl, String root) {
    if (value == null || value.isEmpty) return root;
    try {
      return Uri.parse(baseUrl).resolve(value).toString();
    } catch (_) {
      return root;
    }
  }

  // ---------- 课表判定与学期 ----------

  static bool looksLikeSchedule(String html) {
    final text = parse(html).documentElement?.text ?? '';
    final dayHits = RegExp(r'星期一|星期二|星期三|星期四|星期五|星期六|星期日|周一|周二|周三|周四|周五|周六|周日')
        .allMatches(text)
        .length;
    final weekHits =
        RegExp(r'\d{1,2}\s*[-~—–至]\s*\d{1,2}\s*周').allMatches(text).length;
    final sectionHits = RegExp(r'第?\s*\d{1,2}\s*[-~—–至]\s*\d{1,2}\s*节')
        .allMatches(text)
        .length;
    return dayHits >= 3 &&
        (weekHits >= 2 || sectionHits >= 2 || text.contains('课表') || text.contains('课程表'));
  }

  String _loginErrorText(String html) {
    final text = parse(html).documentElement?.text ?? '';
    for (final line in text.split('\n')) {
      final t = line.trim();
      if (_loginFailRe.hasMatch(t) && t.length <= 80) return t;
    }
    if (_hasPasswordForm(html)) return '登录失败，账号或密码错误';
    return '登录失败';
  }

  List<({String value, String label, bool selected})> _parseSemesters(
      Document document) {
    const names = ['xnxq01id', 'xnxq', 'xq', 'semester'];
    for (final select in document.querySelectorAll('select')) {
      final name = select.attributes['name'] ?? select.attributes['id'] ?? '';
      if (!names.contains(name)) continue;
      final options = <({String value, String label, bool selected})>[];
      for (final opt in select.querySelectorAll('option')) {
        options.add((
          value: opt.attributes['value'] ?? opt.text.trim(),
          label: opt.text.trim().replaceAll(RegExp(r'\s+'), ' '),
          selected: opt.attributes.containsKey('selected'),
        ));
      }
      return options;
    }
    return const [];
  }

  ({String value, String label, bool selected}) _pickSemester(
      List<({String value, String label, bool selected})> options,
      String? wanted) {
    var picked = options.firstWhere((o) => o.selected, orElse: () => options.first);
    final w = (wanted ?? '').trim();
    if (w.isEmpty) return picked;
    final normalized = w.replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp(r'[—–－~]'), '-');
    for (final o in options) {
      final v = o.value.replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp(r'[—–－~]'), '-');
      final l = o.label.replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp(r'[—–－~]'), '-');
      if (v == normalized || l.contains(normalized) || normalized.contains(l)) {
        return o;
      }
    }
    return picked;
  }
}
