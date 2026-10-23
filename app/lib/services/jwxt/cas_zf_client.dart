import 'dart:async';
import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:wakeclass_core/wakeclass_core.dart';

import 'jwxt_exception.dart';
import 'jwxt_types.dart';
import 'zfsoft_client.dart' show courseFromKbItem;

/// 「统一认证（CAS）→ 正方 SSO」登录。
///
/// 有些学校的教务入口只有统一认证，例如：
/// `https://tyrz.example.cn:8243/cas/login?service=https://jwxt.example.cn:443/sso/zfiotlogin`
///
/// 链路：
///   1. CAS 登录表单（Apereo：`execution` / `_eventId=submit`）
///   2. 登录成功 302 → `…/sso/zfiotlogin?ticket=ST-…`
///   3. 正方校验 ticket、下发自己的 `JSESSIONID`，再 302 → `/jwglxt/xtgl/index_initMenu.html`
///   4. 用这个会话调 `kbcx/xskbcx_cxXsKb.html` 拿 `kbList`
///
/// 这里把 2~4 步串起来。ticket 只要没带上/过期，正方不会跳登录页，
/// 而是直接回 404 —— 所以错误提示里专门区分了「会话没建立」这种情况。
class CasZfChallenge {
  const CasZfChallenge({
    required this.loginAction,
    required this.cookie,
    required this.hiddenFields,
    required this.serviceUrl,
    required this.userField,
    required this.passwordField,
  });

  /// 表单提交地址（绝对 URL，保留 `service` 查询参数）。
  final String loginAction;

  /// 登录页下发的 Cookie。
  final String cookie;

  /// 表单隐藏字段（`execution` 等）。
  final Map<String, String> hiddenFields;

  /// `service` 参数（登录成功后的回跳地址）。
  final String serviceUrl;

  final String userField;
  final String passwordField;
}

class _Res {
  const _Res({
    required this.status,
    required this.text,
    required this.url,
    required this.cookie,
    this.location,
    this.setCookie = '',
  });

  final int status;
  final String text;
  final String url;
  final String cookie;
  final String? location;
  final String setCookie;

  bool get isRedirect =>
      status >= 300 && status < 400 && (location ?? '').isNotEmpty;
}

class CasZfClient {
  CasZfClient({http.Client? client, this.timeout = const Duration(seconds: 25)})
      : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  static const String systemName = '统一认证（CAS）· 正方';

  static final _loginFailRe = RegExp(
    r'用户名或密码|密码错误|认证失败|Invalid credentials|登录失败|Account is locked',
    caseSensitive: false,
  );

  // ---------- 登录页 ----------

  Future<CasZfChallenge> prepareLogin(String inputUrl) async {
    final url = inputUrl.trim();
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const JwxtException(JwxtErrorKind.badUrl, '登录地址格式不正确',
          hint: '请粘贴浏览器地址栏里的完整地址（https:// 开头）');
    }
    if (uri.queryParameters['service'] == null) {
      throw const JwxtException(
          JwxtErrorKind.badUrl, '这是统一认证地址，但后面少了 service 参数',
          hint: '请连同 `?service=…` 一起复制，否则登录完不知道该回到哪个教务系统');
    }

    final page = await _request('GET', url);
    if (page.status != 200) {
      throw JwxtException(JwxtErrorKind.network, '登录页打不开（HTTP ${page.status}）',
          hint: '确认地址能在浏览器里打开；学校可能限制校外访问');
    }
    final doc = html_parser.parse(page.text);
    final form = _findLoginForm(doc);

    // 字段名：各校自研的统一认证经常把真正的密码框做成「无 name 的 ppassword
    // + 一个 name=password 的隐藏式 text」，还有手机号登录表单混在一起，
    // 所以按已知写法逐个试，最后才回退到第一个密码框。
    final userField = _pickUserField(doc);
    final passField = _pickPasswordField(doc);
    if (userField == null || passField == null) {
      throw const JwxtException(
          JwxtErrorKind.loginFormNotFound, '这个页面里没有找到账号 / 密码输入框',
          hint: '确认打开的是统一认证登录页（页面上有「账号登录」和密码框）');
    }

    final hidden = <String, String>{};
    for (final input in doc.querySelectorAll('input')) {
      final name = input.attributes['name'];
      if (name == null || name.isEmpty) continue;
      if ((input.attributes['type'] ?? '').toLowerCase() == 'hidden') {
        hidden[name] = input.attributes['value'] ?? '';
      }
    }
    hidden.putIfAbsent('_eventId', () => 'submit');

    // 提交地址：表单 action 有时只是 `login?v=…`（丢了 service），
    // 这时直接提交到带 service 的原始地址。
    var action = _absolute(form?.attributes['action'], page.url) ?? page.url;
    final actionUri = Uri.tryParse(action);
    if (actionUri != null && !actionUri.queryParameters.containsKey('service')) {
      action = page.url;
    }

    return CasZfChallenge(
      loginAction: action,
      cookie: page.cookie,
      hiddenFields: hidden,
      serviceUrl: uri.queryParameters['service'] ?? '',
      userField: userField,
      passwordField: passField,
    );
  }

  /// 账号字段名。
  static String? _pickUserField(Document doc) {
    for (final input in doc.querySelectorAll('input')) {
      final type = (input.attributes['type'] ?? 'text').toLowerCase();
      if (type == 'hidden' || type == 'password' || type == 'checkbox') continue;
      final name = input.attributes['name'] ?? '';
      final id = input.attributes['id'] ?? '';
      if (name == 'username' ||
          name == 'userName' ||
          name == 'j_username' ||
          id == 'username') {
        return name.isNotEmpty ? name : 'username';
      }
    }
    return null;
  }

  /// 密码字段名：优先 `name=password`（防自动填充页面常有的隐藏 text），
  /// 再试「无 name 的密码框」，最后才取第一个带 name 的密码框。
  static String? _pickPasswordField(Document doc) {
    final inputs = doc.querySelectorAll('input');
    for (final input in inputs) {
      if ((input.attributes['name'] ?? '') == 'password') return 'password';
    }
    for (final input in inputs) {
      final id = input.attributes['id'] ?? '';
      if (id == 'ppassword' || id == 'password') {
        final name = input.attributes['name'] ?? '';
        return name.isNotEmpty ? name : 'password';
      }
    }
    for (final input in inputs) {
      if ((input.attributes['type'] ?? '').toLowerCase() != 'password') continue;
      final name = input.attributes['name'] ?? '';
      if (name.isEmpty) return 'password';
      final lower = name.toLowerCase();
      if (lower.contains('mobile') || lower.contains('sms') || lower == 'code') {
        continue; // 手机号 / 短信验证码登录框
      }
      return name;
    }
    return null;
  }

  // ---------- 登录 + 导入 ----------

  Future<JwxtImportResult> loginAndImport(
    CasZfChallenge challenge, {
    required String username,
    required String password,
  }) async {
    final fields = <String, String>{
      ...challenge.hiddenFields,
      challenge.userField: username,
      challenge.passwordField: password,
    };
    final loginRes = await _request(
      'POST',
      challenge.loginAction,
      form: fields,
      cookie: challenge.cookie,
    );

    if (!loginRes.isRedirect) {
      final text = loginRes.text;
      if (_loginFailRe.hasMatch(text) || _hasPasswordForm(text)) {
        throw const JwxtException(
          JwxtErrorKind.loginFailed,
          '账号或密码不正确',
          hint: '确认学号与统一认证密码；如果学校开了验证码 / 扫码 / 短信二次验证，'
              '请改用「截图导入」或「粘贴导入」',
        );
      }
      throw JwxtException(
        JwxtErrorKind.loginFailed,
        '登录没有跳转（HTTP ${loginRes.status}）',
        hint: '学校可能要求滑块或短信验证，改成截图导入更稳',
      );
    }

    final landing = await _followRedirects(loginRes);
    if (_hasPasswordForm(landing.text)) {
      throw const JwxtException(
        JwxtErrorKind.loginFailed,
        '统一认证没有把登录票据交给教务系统',
        hint: '多半是 service 地址和学校登记的不一致：请原样复制浏览器地址栏里的完整地址'
            '（注意里面可能写死了 :443 之类的端口，不要手改）',
      );
    }
    return _importFromZfsoft(landing);
  }

  /// 跟随 302 直到落地（带上每一跳下发的 Cookie）。
  Future<_Res> _followRedirects(_Res start, {int maxHops = 12}) async {
    var current = start;
    var cookie = start.cookie;
    for (var i = 0; i < maxHops && current.isRedirect; i++) {
      final next = _absolute(current.location!, current.url);
      if (next == null) break;
      current = await _request('GET', next, cookie: cookie);
      cookie = current.cookie;
    }
    return current;
  }

  /// 落地页已经在正方里：调课表接口。
  Future<JwxtImportResult> _importFromZfsoft(_Res landing) async {
    final uri = Uri.parse(landing.url);
    final origin = '${uri.scheme}://${uri.authority}';
    final path = uri.path;
    final zfIndex = path.indexOf('/jwglxt');
    final prefix = zfIndex >= 0 ? path.substring(0, zfIndex + 7) : '/jwglxt';

    final warnings = <String>[];
    final pageUrl = '$origin$prefix/kbcx/xskbcx_cxXsKb.html';
    final page = await _request('GET', pageUrl, cookie: landing.cookie);

    if (page.status == 404) {
      throw const JwxtException(
        JwxtErrorKind.sessionLost,
        '正方没有认这次登录（课表页 404）',
        hint: '票据没建立会话：确认登录地址里的 service 参数没被改动/去端口；'
            '也可以改用正方登录页直接登录',
      );
    }
    if (page.status >= 500) {
      throw JwxtException(
        JwxtErrorKind.sessionLost,
        '正方拒绝了这次登录（HTTP ${page.status}）',
        hint: '票据可能已过期：重新打开统一认证登录页，复制最新的完整地址再试',
      );
    }
    if (_hasPasswordForm(page.text)) {
      throw const JwxtException(
        JwxtErrorKind.sessionLost,
        '登录后又被踢回登录页',
        hint: '会话没有建立成功，请重新打开统一认证登录页后复制地址重试',
      );
    }

    final doc = html_parser.parse(page.text);
    final xnm = _selectedOption(doc, 'xnm') ?? _guessYear();
    final xqm = _selectedOption(doc, 'xqm') ?? _guessTerm();

    final kbUrl = '$origin$prefix/kbcx/xskbcx_cxXsKb.html?gnmkdm=N2151';
    final kb = await _request(
      'POST',
      kbUrl,
      form: {'xnm': xnm, 'xqm': xqm, 'kzlx': 'ck'},
      cookie: landing.cookie,
    );

    final courses = <Course>[];
    try {
      final decoded = jsonDecode(kb.text);
      final list = decoded is Map ? decoded['kbList'] : null;
      if (list is List) {
        for (final item in list) {
          if (item is! Map) continue;
          final course = courseFromKbItem(item, warnings);
          if (course != null) courses.add(course);
        }
      }
    } catch (_) {
      // 落到下面统一报错
    }

    if (courses.isEmpty) {
      throw JwxtException(
        JwxtErrorKind.noSchedule,
        '登录成功，但没读到课表（学期 $xnm 第 $xqm 学期）',
        hint: '可能这学期还没排课，或学期参数不对；换个学期再试，或改用截图导入',
      );
    }

    return JwxtImportResult(
      courses: courses,
      warnings: warnings,
      systemName: systemName,
      semesterLabel: '$xnm 学年第 $xqm 学期',
    );
  }

  // ---------- HTTP ----------

  Future<_Res> _request(
    String method,
    String url, {
    Map<String, String>? form,
    String cookie = '',
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      throw JwxtException(JwxtErrorKind.badUrl, '地址无法解析：$url');
    }
    final request = http.Request(method, uri)
      ..followRedirects = false
      ..headers['User-Agent'] =
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36'
      ..headers['Accept'] =
          'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8'
      ..headers['Accept-Language'] = 'zh-CN,zh;q=0.9';
    final jar = _cookieMap(cookie);
    if (jar.isNotEmpty) request.headers['Cookie'] = _cookieHeader(jar);
    if (method == 'POST') {
      request.headers['Content-Type'] =
          'application/x-www-form-urlencoded; charset=UTF-8';
      request.bodyFields = form ?? const {};
    }

    http.Response response;
    try {
      final streamed = await _client.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const JwxtException(JwxtErrorKind.network, '连接统一认证超时',
          hint: '检查网络；校外访问可能需要 VPN 或只能在校内网使用');
    } catch (e) {
      throw JwxtException(JwxtErrorKind.network, '连接失败：$e',
          hint: '检查网络；校外访问可能需要 VPN 或只能在校内网使用');
    }

    final setCookie = _setCookiesOf(response);
    for (final pair in _cookieMap(setCookie).entries) {
      jar[pair.key] = pair.value;
    }

    final resolved = response.request?.url.toString() ?? url;
    return _Res(
      status: response.statusCode,
      text: _decodeText(response),
      url: resolved,
      cookie: _cookieHeader(jar),
      location: response.headers['location'],
      setCookie: setCookie,
    );
  }

  /// 分号拼接的 Cookie。
  static Map<String, String> _cookieMap(String raw) {
    final map = <String, String>{};
    for (final part in raw.split(';')) {
      final text = part.trim();
      if (text.isEmpty) continue;
      final eq = text.indexOf('=');
      if (eq <= 0) continue;
      map[text.substring(0, eq).trim()] = text.substring(eq + 1).trim();
    }
    return map;
  }

  static String _cookieHeader(Map<String, String> jar) =>
      jar.entries.map((e) => '${e.key}=${e.value}').join('; ');

  /// 多个 Set-Cookie 只取 `name=value` 部分。
  static String _setCookiesOf(http.Response response) {
    final values = response.headers['set-cookie'];
    if (values == null || values.isEmpty) return '';
    return values
        .split(',')
        .map((v) => v.split(';').first.trim())
        .where((v) => v.contains('='))
        .join('; ');
  }

  static String _decodeText(http.Response response) {
    try {
      return response.body;
    } catch (_) {
      return '';
    }
  }

  static String? _absolute(String? raw, String base) {
    if (raw == null || raw.trim().isEmpty) return base;
    final trimmed = raw.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme) return uri.toString();
    return Uri.parse(base).resolve(trimmed).toString();
  }

  // ---------- 页面解析 ----------

  static Element? _findLoginForm(Document doc) {
    for (final form in doc.querySelectorAll('form')) {
      if (form.querySelector('input[type="password"]') != null) return form;
    }
    return null;
  }

  static bool _hasPasswordForm(String html) {
    if (html.isEmpty) return false;
    final doc = html_parser.parse(html);
    return doc.querySelector('input[type="password"]') != null;
  }

  static String? _selectedOption(Document doc, String id) {
    for (final select in doc.querySelectorAll('select')) {
      if (select.id != id) continue;
      for (final option in select.querySelectorAll('option')) {
        if (option.attributes.containsKey('selected')) {
          return option.attributes['value'];
        }
      }
      return select.querySelector('option')?.attributes['value'];
    }
    return null;
  }

  /// 学年，如 `2026-2027`（9 月开学）。
  static String _guessYear() {
    final now = DateTime.now();
    final start = now.month >= 9 ? now.year : now.year - 1;
    return '$start-${start + 1}';
  }

  /// 学期代码：3 = 第一学期，12 = 第二学期。
  static String _guessTerm() {
    final month = DateTime.now().month;
    return (month >= 9 || month <= 1) ? '3' : '12';
  }

  void close() => _client.close();
}
