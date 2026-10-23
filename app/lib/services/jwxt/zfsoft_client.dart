import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart';
import 'package:html/parser.dart' show parse;
import 'package:http/http.dart' as http;
import 'package:wakeclass_core/wakeclass_core.dart';

import 'jwxt_exception.dart';
import 'jwxt_types.dart';
import 'jwxt_url.dart';
import 'rsa_password.dart';
import 'schedule_table_parser.dart';

/// 一次 HTTP 响应的摘要。
class _HttpResult {
  const _HttpResult(this.status, this.text, this.cookie, this.url,
      {this.location});

  final int status;
  final String text;
  final String cookie;
  final String url;

  /// 302 的 Location（相对地址也会原样保留）。
  final String? location;
}

/// 正方教务（jwglxt 新版）登录挑战。
class ZfsoftChallenge {
  const ZfsoftChallenge({
    required this.baseUrl,
    required this.loginAction,
    required this.cookie,
    required this.csrfToken,
    required this.modulus,
    required this.exponent,
    this.hiddenFields = const {},
    this.captchaField,
    this.captchaImage,
    this.detectedSemester,
  });

  /// 教务根地址，如 `https://jw.example.edu.cn/jwglxt/`。
  final String baseUrl;

  /// 登录提交地址。
  final String loginAction;

  /// 会话 Cookie。
  final String cookie;

  /// csrftoken（隐藏字段或 Cookie）。
  final String csrfToken;

  /// RSA 公钥模数（base64）。
  final String modulus;

  /// RSA 公钥指数（base64）。
  final String exponent;

  /// 登录表单的其它隐藏字段。
  final Map<String, String> hiddenFields;

  /// 验证码字段名（多数学校没有）。
  final String? captchaField;

  /// 验证码图片。
  final Uint8List? captchaImage;

  /// 登录页里已经选中的学年/学期（如 `2026-2027-1`）。
  final String? detectedSemester;
}

/// 正方教务系统（jwglxt）直连客户端。
///
/// 覆盖绝大多数 2018 年后的正方新版教务：
/// 1. `xtgl/login_slogin.html` 登录页 → `csrftoken` + 隐藏字段；
/// 2. `xtgl/login_getPublicKey.html` → RSA 公钥，密码按学校同样的规则
///    PKCS#1 v1.5 加密后提交（见 [rsaEncryptPasswordHex]）；
/// 3. `kbcx/xskbcx_cxXsKb.html?gnmkdm=N2151` → 课表 JSON（`kbList`）；
/// 4. JSON 解析失败时回退到 HTML 表格解析。
class ZfsoftClient {
  ZfsoftClient({http.Client? client, this.timeout = const Duration(seconds: 15)})
      : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  static const String systemName = '正方教务系统';

  static final _loginFailRe = RegExp(
      r'用户名或密码|密码错误|账号或密码|用户不存在|验证码错误|登录失败|用户被锁定');

  /// 归一化教务地址：支持直接粘贴登录页 / 首页 / 只到域名 / WebVPN 地址。
  ///
  /// WebVPN 前缀会被保留（例：`https://webvpn.x.edu.cn/https/<token>/jwglxt/`），
  /// 这样后续的 `/xtgl/...`、`/kbcx/...` 请求也会走同一个 WebVPN 入口。
  static String normalizeBase(String raw) {
    final trimmed = raw.trim();
    Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (_) {
      throw const JwxtException(
          JwxtErrorKind.badUrl, '教务系统地址格式不正确', hint: '示例：https://jw.example.edu.cn/jwglxt');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const JwxtException(
          JwxtErrorKind.badUrl, '只支持 http / https 地址');
    }
    final origin = '${uri.scheme}://${uri.authority}';
    final prefix = webVpnPrefix(uri.path);
    // 已经在 /jwglxt/ 下就原样保留；否则补上 /jwglxt/（WebVPN 前缀仍然带上）。
    if (uri.path.toLowerCase().contains('/jwglxt')) {
      return siteRoot(trimmed);
    }
    return '$origin$prefix/jwglxt/';
  }

  /// 访问登录页，解析表单、csrftoken 与 RSA 公钥。
  Future<ZfsoftChallenge> prepareLogin(String inputUrl) async {
    final base = normalizeBase(inputUrl);
    final loginUrl = '${base}xtgl/login_slogin.html';
    _HttpResult page;
    try {
      page = await _get(loginUrl);
    } on TimeoutException {
      throw JwxtException(
        JwxtErrorKind.network,
        '连接教务系统超时',
        hint: networkHint(inputUrl) ??
            '请检查网络；如果学校教务只能在校园网 / VPN 内访问，请先连上 VPN 或校园 Wi-Fi。',
      );
    } catch (e) {
      throw JwxtException(
        JwxtErrorKind.network,
        '无法连接教务系统：$e',
        hint: networkHint(inputUrl) ??
            '请检查地址是否正确；若学校要求 VPN / 校园网，请连上后再试。',
      );
    }
    if (!_hasPasswordForm(page.text)) {
      throw const JwxtException(
        JwxtErrorKind.loginFormNotFound,
        '没有找到正方登录表单',
        hint: '请确认地址指向正方教务系统（通常包含 /jwglxt）。',
      );
    }
    final document = parse(page.text);
    final form = _findLoginForm(document);
    final action = _absolute(form?.attributes['action'], page.url, loginUrl);

    var csrf = '';
    final hidden = <String, String>{};
    // 正方的隐藏参数（xxdm / mmsfjm / yzcskz …）大多写在 <form> 外面，
    // 所以这里扫描整页：属于登录表单的、以及不属于任何表单的 hidden 都收。
    for (final input in document.querySelectorAll('input')) {
      if ((input.attributes['type'] ?? '').toLowerCase() != 'hidden') continue;
      final name = input.attributes['name'];
      if (name == null || name.isEmpty) continue;
      final owner = _owningForm(input);
      if (owner != null && form != null && owner != form) continue;
      final value = input.attributes['value'] ?? '';
      hidden.putIfAbsent(name, () => value);
      if (name.toLowerCase().contains('csrf')) csrf = value;
    }
    if (csrf.isEmpty) {
      final match = RegExp(r'csrftoken=([^;\s]+)').firstMatch(page.cookie);
      if (match != null) csrf = match.group(1)!;
    }

    // 公钥。
    var modulus = '';
    var exponent = '';
    try {
      final keyRes = await _get(
        '${base}xtgl/login_getPublicKey.html?time=${DateTime.now().millisecondsSinceEpoch}',
        cookie: page.cookie,
        referer: loginUrl,
      );
      final key = jsonDecode(keyRes.text);
      if (key is Map) {
        modulus = (key['modulus'] ?? '').toString();
        exponent = (key['exponent'] ?? '').toString();
      }
    } catch (_) {
      // 取不到公钥时按明文提交（部分学校确实使用明文密码）
    }

    // 验证码（少数学校开启）。
    String? captchaField;
    Uint8List? captchaImage;
    if (form != null) {
      for (final input in form.querySelectorAll('input')) {
        final name = (input.attributes['name'] ?? '').toLowerCase();
        final id = (input.attributes['id'] ?? '').toLowerCase();
        if (RegExp(r'(yzm|captcha|checkcode|verify)').hasMatch('$name $id')) {
          captchaField = input.attributes['name'] ?? input.attributes['id'];
          break;
        }
      }
      if (captchaField != null) {
        for (final img in document.querySelectorAll('img')) {
          final src = img.attributes['src'] ?? '';
          if (!RegExp(r'(captcha|yzm|verify|checkcode)', caseSensitive: false)
              .hasMatch(src)) {
            continue;
          }
          final url = _absolute(src, page.url, base);
          try {
            final request = http.Request('GET', Uri.parse(url));
            if (page.cookie.isNotEmpty) request.headers['Cookie'] = page.cookie;
            final streamed = await _client.send(request).timeout(timeout);
            if (streamed.statusCode < 400) {
              captchaImage = await streamed.stream.toBytes();
            }
          } catch (_) {
            // 忽略验证码图片失败
          }
          break;
        }
      }
    }

    return ZfsoftChallenge(
      baseUrl: base,
      loginAction: action,
      cookie: page.cookie,
      csrfToken: csrf,
      modulus: modulus,
      exponent: exponent,
      hiddenFields: hidden,
      captchaField: captchaField,
      captchaImage: captchaImage,
      detectedSemester: _detectSemester(document),
    );
  }

  /// 登录并导入课表。
  Future<JwxtImportResult> loginAndImport(
    ZfsoftChallenge challenge, {
    required String username,
    required String password,
    String captcha = '',
    String semester = '',
  }) async {
    final warnings = <String>[];
    // 与正方前端一致：mm = base64(RSA(PKCS#1 v1.5, 密码))；
    // 取不到公钥 / 加密失败时回退明文（少数学校 mmsfjm=0）。
    final encrypted = challenge.modulus.isEmpty
        ? password
        : (rsaEncryptPassword(
              password,
              modulusBase64: challenge.modulus,
              exponentBase64: challenge.exponent,
            ) ??
            password);

    final data = <String, String>{
      ...challenge.hiddenFields,
      'language': 'zh_CN',
      'yhm': username,
      'mm': encrypted,
    };
    if (challenge.csrfToken.isNotEmpty) data['csrftoken'] = challenge.csrfToken;
    if (challenge.captchaField != null && captcha.isNotEmpty) {
      data[challenge.captchaField!] = captcha;
    }

    _HttpResult loginRes;
    try {
      loginRes = await _post(
        challenge.loginAction,
        data,
        cookie: challenge.cookie,
        referer: '${challenge.baseUrl}xtgl/login_slogin.html',
      );
    } on TimeoutException {
      throw const JwxtException(JwxtErrorKind.network, '登录请求超时',
          hint: '请检查网络后重试。');
    } catch (e) {
      throw JwxtException(JwxtErrorKind.network, '登录请求失败：$e');
    }

    if (_loginFailRe.hasMatch(loginRes.text) || _hasPasswordForm(loginRes.text)) {
      throw JwxtException(
        JwxtErrorKind.loginFailed,
        _loginErrorText(loginRes.text),
        hint: '请核对账号密码；如学校启用了验证码 / 统一认证，请改用截图导入。',
      );
    }

    var cookie = loginRes.cookie;
    // 跟随登录后的跳转，拿到 index 页（顺带刷新 Cookie）。
    var landing = loginRes;
    if (loginRes.status >= 300 && loginRes.status < 400) {
      final location = _locationOf(loginRes);
      if (location != null) {
        landing = await _get(location, cookie: cookie, referer: loginRes.url);
        cookie = landing.cookie;
      }
    }
    if (_hasPasswordForm(landing.text)) {
      throw const JwxtException(JwxtErrorKind.loginFailed, '登录失败，账号或密码错误');
    }

    // 课表页：先取学年学期下拉框的当前值。
    final schedulePageUrl = '${challenge.baseUrl}kbcx/xskbcx_cxXsKb.html?gnmkdm=N2151';
    final page = await _get(schedulePageUrl, cookie: cookie, referer: landing.url);
    if (_hasPasswordForm(page.text)) {
      throw const JwxtException(JwxtErrorKind.sessionLost, '登录后访问课表页时登录状态失效');
    }
    final document = parse(page.text);
    final pageSemester = _detectSemester(document);
    final resolved =
        _resolveSemester(semester, pageSemester ?? challenge.detectedSemester, warnings);

    final body = <String, String>{
      'xnm': resolved.year,
      'xqm': resolved.term,
      'kzlx': 'ck',
    };
    final jsonRes = await _post(
      schedulePageUrl,
      body,
      cookie: cookie,
      referer: schedulePageUrl,
      accept: 'application/json, text/javascript, */*; q=0.01',
      xhr: true,
    );

    final parsedJson = _tryDecodeJson(jsonRes.text);
    if (parsedJson != null) {
      final list = parsedJson['kbList'];
      if (list is List) {
        final courses = <Course>[];
        for (final item in list) {
          if (item is! Map) continue;
          final course = _courseFromJson(item, warnings);
          if (course != null) courses.add(course);
        }
        if (courses.isNotEmpty) {
          warnings.add('学期：${resolved.label}');
          return JwxtImportResult(
            courses: courses,
            warnings: warnings,
            systemName: systemName,
            semesterLabel: resolved.label,
          );
        }
      }
    }

    // 回退：按 HTML 表格解析。
    final html = jsonRes.text.isNotEmpty ? jsonRes.text : page.text;
    const parser = ScheduleTableParser();
    final parsed = parser.parseSchedule(html, source: 'jwxt');
    if (parsed.courses.isEmpty) {
      throw const JwxtException(
        JwxtErrorKind.noSchedule,
        '登录成功，但没有读取到课表',
        hint: '多半是学期不对：在「学期」里填 2026-2027-1（或 2026-2027-2）再试；'
            '也可以导入后手动改开学日，或改用截图导入。',
      );
    }
    warnings.addAll(parsed.warnings);
    warnings.add('学期：${resolved.label}');
    return JwxtImportResult(
      courses: parsed.courses,
      warnings: warnings,
      systemName: systemName,
      semesterLabel: resolved.label,
    );
  }

  void close() => _client.close();

  // ---------- JSON → Course ----------

  Course? _courseFromJson(Map item, List<String> warnings) =>
      courseFromKbItem(item, warnings);

  // ---------- 学年学期 ----------

  ({String year, String term, String label}) _resolveSemester(
    String input,
    String? detected,
    List<String> warnings,
  ) {
    final text = input.trim().isNotEmpty ? input.trim() : (detected ?? '');
    final match = RegExp(r'(20\d{2})').firstMatch(text);
    final year = match?.group(1) ?? _guessYear();
    var term = '3';
    if (RegExp(r'[-—–]\s*2\s*$').hasMatch(text) || text.contains('二学期')) {
      term = '12';
    } else if (text.contains('三学期') || text.contains('短学期')) {
      term = '16';
    } else if (RegExp(r'[-—–]\s*1\s*$').hasMatch(text) || text.contains('一学期')) {
      term = '3';
    }
    final yearNumber = int.tryParse(year) ?? DateTime.now().year;
    if (yearNumber < 2000 || yearNumber > 2100) {
      warnings.add('学年无法识别，已按当前学年查询');
    }
    final label = '$yearNumber-${yearNumber + 1}-${term == '12' ? 2 : (term == '16' ? 3 : 1)}';
    return (year: year, term: term, label: label);
  }

  String _guessYear() {
    final now = DateTime.now();
    return '${now.month >= 8 ? now.year : now.year - 1}';
  }

  /// 从页面下拉框里读当前选中的学年 / 学期。
  String? _detectSemester(Document document) {
    String? selectedText(Element select) {
      for (final option in select.querySelectorAll('option')) {
        if (option.attributes.containsKey('selected')) return option.text.trim();
      }
      return null;
    }

    final xnm = document.querySelector('select#xnm');
    final xqm = document.querySelector('select#xqm');
    final yearText = xnm == null ? null : selectedText(xnm);
    final termText = xqm == null ? null : selectedText(xqm);
    if (yearText == null && termText == null) return null;
    if (yearText == null) return termText;
    if (termText == null) return yearText;
    final termNumber = termText.contains('2') ? 2 : (termText.contains('3') ? 3 : 1);
    return '$yearText-$termNumber';
  }

  // ---------- HTTP ----------

  /// 学校前置的 WAF / 负载均衡会对同一地址**间歇性返回 404**
  /// （实测同一 URL、同一 UA：200,200,200,404），所以 404 / 5xx 时自动重试。
  Future<_HttpResult> _get(String url,
      {String cookie = '', String referer = ''}) async {
    for (var attempt = 0;; attempt++) {
      final result = await _getOnce(url, cookie: cookie, referer: referer);
      final transient = result.status == 404 || result.status >= 500;
      if (!transient || attempt >= 2) return result;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  Future<_HttpResult> _getOnce(String url,
      {String cookie = '', String referer = ''}) async {
    final request = http.Request('GET', Uri.parse(url));
    request.followRedirects = false;
    if (cookie.isNotEmpty) request.headers['Cookie'] = cookie;
    if (referer.isNotEmpty) request.headers['Referer'] = referer;
    request.headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';
    final streamed = await _client.send(request).timeout(timeout);
    final bytes = await streamed.stream.toBytes();
    return _HttpResult(
      streamed.statusCode,
      utf8.decode(bytes, allowMalformed: true),
      _mergeCookie(cookie, streamed.headers['set-cookie']),
      streamed.request?.url.toString() ?? url,
      location: streamed.headers['location'],
    );
  }

  Future<_HttpResult> _post(
    String url,
    Map<String, String> data, {
    String cookie = '',
    String referer = '',
    String? accept,
    bool xhr = false,
  }) async {
    final request = http.Request('POST', Uri.parse(url));
    request.followRedirects = false;
    if (cookie.isNotEmpty) request.headers['Cookie'] = cookie;
    if (referer.isNotEmpty) {
      request.headers['Referer'] = referer;
      try {
        request.headers['Origin'] = Uri.parse(referer).origin;
      } catch (_) {
        // 忽略非法 referer
      }
    }
    request.headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';
    if (accept != null) request.headers['Accept'] = accept;
    if (xhr) request.headers['X-Requested-With'] = 'XMLHttpRequest';
    request.bodyFields = data;
    final streamed = await _client.send(request).timeout(timeout);
    final bytes = await streamed.stream.toBytes();
    return _HttpResult(
      streamed.statusCode,
      utf8.decode(bytes, allowMalformed: true),
      _mergeCookie(cookie, streamed.headers['set-cookie']),
      streamed.request?.url.toString() ?? url,
      location: streamed.headers['location'],
    );
  }

  Map<String, dynamic>? _tryDecodeJson(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final start = trimmed.indexOf('{');
    if (start < 0) return null;
    try {
      final decoded = jsonDecode(trimmed.substring(start));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String? _locationOf(_HttpResult result) {
    final raw = result.location;
    if (raw == null || raw.isEmpty) return null;
    try {
      return Uri.parse(result.url).resolve(raw).toString();
    } catch (_) {
      return null;
    }
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

  bool _hasPasswordForm(String html) =>
      RegExp('<input\\b[^>]*type\\s*=\\s*["\']?password', caseSensitive: false)
          .hasMatch(html);

  Element? _findLoginForm(Document document) {
    for (final form in document.querySelectorAll('form')) {
      for (final input in form.querySelectorAll('input')) {
        if ((input.attributes['type'] ?? '').toLowerCase() == 'password') {
          return form;
        }
      }
    }
    return null;
  }

  /// 向上找最近的 <form>（没有则返回 null）。
  Element? _owningForm(Element element) {
    Element? node = element.parent;
    while (node != null) {
      if (node.localName == 'form') return node;
      node = node.parent;
    }
    return null;
  }

  String _absolute(String? value, String baseUrl, String fallback) {
    if (value == null || value.isEmpty) return fallback;
    if (value.startsWith('javascript')) return fallback;
    try {
      return Uri.parse(baseUrl).resolve(value).toString();
    } catch (_) {
      return fallback;
    }
  }

  String _loginErrorText(String html) {
    final text = parse(html).documentElement?.text ?? '';
    for (final line in text.split('\n')) {
      final t = line.trim();
      if (_loginFailRe.hasMatch(t) && t.length <= 80) return t;
    }
    return '登录失败，账号或密码错误';
  }
}

final _kbPeriodsRe = RegExp(r'^(\d{1,2})(?:\s*[-—–~～,，]\s*(\d{1,2}))?');

/// 正方课表 JSON 里的单条记录 → [Course]。
///
/// 供正方适配器与通用适配器（遇到 `kbList` 结构时）共用。
Course? courseFromKbItem(Map item, List<String> warnings) {
  final name = (item['kcmc'] ?? item['courseName'] ?? '').toString().trim();
  if (name.isEmpty) return null;
  final day = int.tryParse((item['xqj'] ?? '').toString().trim()) ?? 0;
  if (day < 1 || day > 7) return null;
  final jcs = (item['jcs'] ?? item['jc'] ?? '').toString().trim();
  final m = _kbPeriodsRe.firstMatch(jcs);
  final start = m == null ? 0 : (int.tryParse(m.group(1)!) ?? 0);
  final end = m == null ? start : (int.tryParse(m.group(2) ?? '') ?? start);
  if (start <= 0) {
    warnings.add('「$name」节次无法识别（$jcs），已跳过');
    return null;
  }
  final zcd = (item['zcd'] ?? item['week'] ?? '').toString().trim();
  final weeks = parseWeeks(zcd.isEmpty ? null : zcd, totalWeeks: 30).weeks;
  return Course.create(
    name: name,
    teacher: (item['xm'] ?? item['teacher'] ?? '').toString().trim(),
    location: (item['cdmc'] ?? item['location'] ?? '').toString().trim(),
    weeks: weeks,
    dayOfWeek: day,
    startPeriod: start,
    endPeriod: end < start ? start : end,
    source: 'jwxt',
  );
}

