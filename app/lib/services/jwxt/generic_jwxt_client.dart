import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' show parse;
import 'package:http/http.dart' as http;
import 'package:wakeclass_core/wakeclass_core.dart';

import 'jwxt_exception.dart';
import 'jwxt_types.dart';
import 'qz_jwxt_client.dart' show QzJwxtClient;
import 'schedule_table_parser.dart';
import 'zfsoft_client.dart' show courseFromKbItem;

/// 带解码信息的响应。
class _Response {
  const _Response(this.status, this.text, this.cookie, this.url,
      {this.location, this.bytes});

  final int status;
  final String text;
  final String cookie;
  final String url;
  final String? location;
  final Uint8List? bytes;
}

/// 通用教务系统客户端：不绑定具体厂商。
///
/// 适用面：表单登录 + 课表是「表格」或「正方 kbList JSON」的绝大多数教务系统。
///
/// 流程：
/// 1. 打开用户粘贴的地址 → 自动找登录表单（学号/密码字段、hidden 字段、验证码图片）；
/// 2. 提交表单（校验码人工输入，不绕过任何风控）；
/// 3. 登录成功后依次尝试：当前页 → 页面里的「课表」链接 → 常见课表路径；
/// 4. 解析：正方 `kbList` JSON 或 HTML 表格（[ScheduleTableParser] 已做通用化：
///    表头找「周一..周日」、行首找节次、单元格交给 `parseCellText`）。
class GenericJwxtClient {
  GenericJwxtClient(
      {http.Client? client, this.timeout = const Duration(seconds: 15)})
      : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  static const String systemName = '通用教务系统';

  static final _loginFailRe =
      RegExp(r'用户名或密码|密码错误|账号或密码|用户不存在|登录失败|验证码错误|账号不存在');
  static final _captchaNameRe = RegExp(
      r'^(?:yzm|randcode|randomcode|checkcode|validatecode|captcha|verifycode|vcode|jcaptcha|checkCode)$',
      caseSensitive: false);
  static final _captchaImgRe = RegExp(
      r'(?:yzm|captcha|verify|checkcode|randcode|validate)',
      caseSensitive: false);
  static final _scheduleLinkRe =
      RegExp(r'课表|课程表|我的课表|学生课表|班级课表|课表查询|课程安排|本学期课程');
  static final _ssoRe =
      RegExp(r'authserver|/cas/|/sso/|oauth|saml|openid|统一身份认证', caseSensitive: false);

  /// 常见课表页相对路径（找不到链接时逐个尝试）。
  static const _scheduleCandidates = [
    'xskb/xskb_list.do',
    'xskb/xskb_list.do?Ves632DSdyV=NEW',
    'kbcx/xskbcx_cxXsKb.html',
    'xsxkb/xskb.jsp',
    'xskbcx/xskbcx.jsp',
  ];

  static final _credFieldPatterns = [
    RegExp(
        r'(?:^|_)(?:yhm|useraccount|username|userid|user_name|account|loginname|login_name|loginid|xh|studentid|studentno|uid|uname|accountname|xh_id)(?:$|_)',
        caseSensitive: false),
    RegExp(r'学号|账号|帐号|用户名|工号'),
  ];

  // ---------- 第一步：探测登录页 ----------

  /// 归一化地址：粘贴登录页 / 首页 / 域名都可以。
  static String normalizeBase(String raw) {
    final trimmed = raw.trim();
    Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (_) {
      throw const JwxtException(
          JwxtErrorKind.badUrl, '教务系统地址格式不正确', hint: '示例：https://jw.example.edu.cn/jwglxt/xtgl/login_slogin.html');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const JwxtException(
          JwxtErrorKind.badUrl, '只支持 http / https 地址');
    }
    final path = uri.path;
    final lastSegment = path.split('/').last;
    final looksLikePage = RegExp(r'\.(?:html?|jsp|do|action|php|aspx?)$',
            caseSensitive: false)
        .hasMatch(lastSegment);
    final dir = looksLikePage
        ? path.substring(0, path.length - lastSegment.length)
        : (path.endsWith('/') ? path : '$path/');
    return '${uri.scheme}://${uri.authority}$dir';
  }

  Future<JwxtLoginChallenge> prepareLogin(String inputUrl) async {
    final base = normalizeBase(inputUrl);
    final entry = inputUrl.trim();

    final page = await _get(entry.isEmpty ? base : entry);
    final document = parse(page.text);
    final form = _findLoginForm(document);
    if (form == null) {
      if (_ssoRe.hasMatch('$entry ${page.text.substring(0, page.text.length.clamp(0, 4000))}')) {
        throw const JwxtException(
          JwxtErrorKind.loginFormNotFound,
          '这个地址是统一身份认证（CAS/SSO）页，不是教务系统登录页',
          hint: '请把系统类型改成「统一认证（CAS）」再试；或直接粘贴教务系统自己的登录页地址。',
        );
      }
      throw const JwxtException(
        JwxtErrorKind.loginFormNotFound,
        '没有找到登录表单',
        hint: '请粘贴教务系统「登录页」的地址（带账号密码输入框的那个页面）。',
      );
    }

    final (userField, passwordField) = _findCredentialFields(form);
    final hidden = <String, String>{};
    // 有些系统的隐藏参数写在 <form> 外面（比如正方把 xxdm / mmsfjm 放在表单前），
    // 所以整页扫描：登录表单里的 + 不属于任何表单的 hidden 都收。
    for (final input in document.querySelectorAll('input')) {
      final name = input.attributes['name'];
      if (name == null || name.isEmpty) continue;
      final type = _typeOf(input);
      if (type != 'hidden' && type != 'submit') continue;
      final owner = _owningForm(input);
      if (owner != null && owner != form) continue;
      hidden.putIfAbsent(name, () => input.attributes['value'] ?? '');
    }

    String? captchaField;
    final candidates = <String>[];
    for (final input in form.querySelectorAll('input')) {
      final type = _typeOf(input);
      if (type != 'text' && type != '' && type != 'number') continue;
      final name = input.attributes['name'] ?? input.attributes['id'] ?? '';
      final placeholder = input.attributes['placeholder'] ?? '';
      if (_captchaNameRe.hasMatch(name) || placeholder.contains('验证码')) {
        candidates.add(name);
      }
    }
    if (candidates.isNotEmpty) captchaField = candidates.first;

    Uint8List? captchaImage;
    if (captchaField != null) {
      captchaImage = await _fetchCaptchaImage(document, page, base);
    }

    return JwxtLoginChallenge(
      baseUrl: base,
      loginAction: _absolute(form.attributes['action'], page.url, entry.isEmpty ? base : entry),
      userField: userField,
      passwordField: passwordField,
      hiddenFields: hidden,
      cookie: page.cookie,
      captchaField: captchaField,
      captchaImage: captchaImage,
    );
  }

  // ---------- 第二步：登录 + 找课表 ----------

  Future<JwxtImportResult> loginAndImport(
    JwxtLoginChallenge challenge, {
    required String username,
    required String password,
    String captcha = '',
    String semester = '',
  }) async {
    final data = <String, String>{...challenge.hiddenFields};
    data[challenge.userField] = username;
    data[challenge.passwordField] = password;
    if (challenge.captchaField != null) data[challenge.captchaField!] = captcha;

    _Response res;
    try {
      res = await _post(
        challenge.loginAction,
        data,
        cookie: challenge.cookie,
        referer: challenge.loginAction,
      );
    } on TimeoutException {
      throw const JwxtException(
          JwxtErrorKind.network, '登录请求超时', hint: '请检查网络后重试。');
    } catch (e) {
      throw JwxtException(JwxtErrorKind.network, '登录请求失败：$e');
    }

    if (_loginFailRe.hasMatch(res.text) || _hasPasswordForm(res.text)) {
      throw JwxtException(
        JwxtErrorKind.loginFailed,
        _loginErrorText(res.text),
        hint: '请核对账号密码与验证码；如学校使用微信扫码 / 短信验证，请改用截图导入。',
      );
    }
    var cookie = res.cookie;

    // 登录成功通常返回 302：跟随一次，拿到落地页（首页 / 菜单页）。
    var landingRes = res;
    if (res.status >= 300 && res.status < 400 &&
        (res.location ?? '').isNotEmpty) {
      try {
        landingRes = await _get(
          _absolute(res.location, res.url, challenge.baseUrl),
          cookie: cookie,
          referer: challenge.loginAction,
        );
        cookie = landingRes.cookie;
      } catch (_) {
        landingRes = res;
      }
      if (_hasPasswordForm(landingRes.text)) {
        throw const JwxtException(
          JwxtErrorKind.loginFailed,
          '登录失败，账号或密码错误',
          hint: '请核对账号密码与验证码。',
        );
      }
    }

    final warnings = <String>[];
    // 1) 登录响应本身就是课表。
    if (QzJwxtClient.looksLikeSchedule(landingRes.text)) {
      return _parseAndReturn(landingRes.text, warnings);
    }

    // 2) 落地页里的「课表」链接。
    final landing = parse(landingRes.text);
    final link = _findScheduleLink(landing, landingRes.url);
    if (link != null) {
      final page = await _get(link, cookie: cookie, referer: landingRes.url);
      cookie = page.cookie;
      final parsed = await _handleSchedulePage(page, cookie, semester, warnings);
      if (parsed != null) return parsed;
    }

    // 3) 常见课表路径。
    for (final path in _scheduleCandidates) {
      final url = '${challenge.baseUrl}$path';
      try {
        final page = await _get(url, cookie: cookie, referer: landingRes.url);
        if (_hasPasswordForm(page.text)) continue;
        final parsed = await _handleSchedulePage(page, cookie, semester, warnings);
        if (parsed != null) return parsed;
      } catch (_) {
        // 该路径不存在：继续尝试下一个
      }
    }

    throw const JwxtException(
      JwxtErrorKind.noSchedule,
      '登录成功，但没有找到课表页面',
      hint: '可以登录后手动打开课表页，把地址复制下来，用「粘贴页面地址」再试；或直接截图导入。',
    );
  }

  /// 处理可能是课表的页面：JSON（正方 kbList）或 HTML 表格。
  Future<JwxtImportResult?> _handleSchedulePage(
    _Response page,
    String cookie,
    String semester,
    List<String> warnings,
  ) async {
    if (_hasPasswordForm(page.text)) return null;

    final json = _tryDecodeJson(page.text);
    if (json != null && json['kbList'] is List) {
      final courses = <Course>[];
      for (final item in json['kbList'] as List) {
        if (item is! Map) continue;
        final c = courseFromKbItem(item, warnings);
        if (c != null) courses.add(c);
      }
      if (courses.isNotEmpty) {
        return JwxtImportResult(
          courses: courses,
          warnings: warnings,
          systemName: systemName,
        );
      }
    }

    if (!QzJwxtClient.looksLikeSchedule(page.text)) return null;

    // 学期切换（如果页面里有学期下拉框）。
    var html = page.text;
    final document = parse(html);
    final select = _findSemesterSelect(document);
    if (select != null) {
      final options = select.querySelectorAll('option');
      if (options.isNotEmpty) {
        final picked = _pickOption(options, semester);
        if (picked != null) {
          try {
            final selected = await _post(
              page.url,
              {select.attributes['name'] ?? select.attributes['id'] ?? 'xnxq01id': picked.$1},
              cookie: cookie,
              referer: page.url,
            );
            if (QzJwxtClient.looksLikeSchedule(selected.text)) {
              html = selected.text;
            }
          } catch (_) {
            warnings.add('切换学期时网络异常，已导入默认学期课表。');
          }
        }
      }
    }

    const parser = ScheduleTableParser();
    final parsed = parser.parseSchedule(html, source: 'jwxt');
    warnings.addAll(parsed.warnings);
    if (parsed.courses.isEmpty) return null;
    return JwxtImportResult(
      courses: parsed.courses,
      warnings: warnings,
      systemName: systemName,
    );
  }

  JwxtImportResult _parseAndReturn(String html, List<String> warnings) {
    const parser = ScheduleTableParser();
    final parsed = parser.parseSchedule(html, source: 'jwxt');
    warnings.addAll(parsed.warnings);
    if (parsed.courses.isEmpty) {
      throw const JwxtException(
        JwxtErrorKind.noSchedule,
        '页面看起来像课表，但没有解析出课程',
        hint: '请使用截图导入，或换一个课表页地址再试。',
      );
    }
    return JwxtImportResult(
      courses: parsed.courses,
      warnings: warnings,
      systemName: systemName,
    );
  }

  void close() => _client.close();

  // ---------- 页面解析辅助 ----------

  Element? _findLoginForm(Document document) {
    for (final form in document.querySelectorAll('form')) {
      for (final input in form.querySelectorAll('input')) {
        if (_typeOf(input) == 'password') return form;
      }
    }
    // 有些系统密码框不在 form 内（AJAX 登录）：退化为整页查找。
    if (document.querySelectorAll('input[type=password]').isNotEmpty) {
      return document.querySelector('form') ?? document.documentElement;
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

  (String, String) _findCredentialFields(Element form) {
    final inputs = form.querySelectorAll('input');
    String? passwordField;
    final textFields = <Element>[];
    for (final input in inputs) {
      final type = _typeOf(input);
      final name = input.attributes['name'] ?? input.attributes['id'] ?? '';
      if (type == 'password' && passwordField == null && name.isNotEmpty) {
        passwordField = name;
      }
      if ((type == 'text' || type == 'email' || type == 'number' || type.isEmpty) &&
          name.isNotEmpty) {
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

  String? _findScheduleLink(Document document, String baseUrl) {
    for (final anchor in document.querySelectorAll('a')) {
      final text = anchor.text.trim();
      final href = anchor.attributes['href'] ?? '';
      if (href.isEmpty || href.startsWith('javascript') || href == '#') continue;
      if (!_scheduleLinkRe.hasMatch(text) && !_scheduleLinkRe.hasMatch(href)) {
        continue;
      }
      return _absolute(href, baseUrl, baseUrl);
    }
    return null;
  }

  Element? _findSemesterSelect(Document document) {
    const names = ['xnxq01id', 'xnxq', 'xq', 'semester', 'xqid'];
    for (final select in document.querySelectorAll('select')) {
      final name = select.attributes['name'] ?? select.attributes['id'] ?? '';
      if (names.contains(name)) return select;
    }
    return null;
  }

  (String, String)? _pickOption(List<Element> options, String wanted) {
    Element? picked;
    for (final option in options) {
      if (option.attributes.containsKey('selected')) {
        picked = option;
        break;
      }
    }
    final w = wanted.trim();
    if (w.isNotEmpty) {
      for (final option in options) {
        final label = option.text.trim();
        if (label.contains(w) || (option.attributes['value'] ?? '') == w) {
          picked = option;
          break;
        }
      }
    }
    picked ??= options.first;
    final value = picked.attributes['value'] ?? picked.text.trim();
    return (value, picked.text.trim());
  }

  /// 验证码图片。
  Future<Uint8List?> _fetchCaptchaImage(
      Document document, _Response page, String base) async {
    for (final img in document.querySelectorAll('img')) {
      final src = img.attributes['src'] ?? '';
      if (src.isEmpty || !_captchaImgRe.hasMatch(src)) continue;
      final url = _absolute(src, page.url, base);
      if (!url.startsWith('http')) continue;
      try {
        final request = http.Request('GET', Uri.parse(url));
        if (page.cookie.isNotEmpty) request.headers['Cookie'] = page.cookie;
        final streamed = await _client.send(request).timeout(timeout);
        if (streamed.statusCode >= 400) return null;
        return await streamed.stream.toBytes();
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  // ---------- HTTP ----------

  Future<_Response> _get(String url,
      {String cookie = '', String referer = ''}) async {
    final request = http.Request('GET', Uri.parse(url));
    request.followRedirects = false;
    if (cookie.isNotEmpty) request.headers['Cookie'] = cookie;
    if (referer.isNotEmpty) request.headers['Referer'] = referer;
    request.headers['User-Agent'] = 'Mozilla/5.0 (WakeClass) AppleWebKit/537.36';
    request.headers['Accept-Language'] = 'zh-CN,zh;q=0.9';
    final streamed = await _client.send(request).timeout(timeout);
    final bytes = await streamed.stream.toBytes();
    return _Response(
      streamed.statusCode,
      _decode(bytes, streamed.headers['content-type']),
      _mergeCookie(cookie, streamed.headers['set-cookie']),
      streamed.request?.url.toString() ?? url,
      location: streamed.headers['location'],
      bytes: bytes,
    );
  }

  Future<_Response> _post(
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
      try {
        request.headers['Origin'] = Uri.parse(referer).origin;
      } catch (_) {
        // 忽略非法 referer
      }
    }
    request.headers['User-Agent'] = 'Mozilla/5.0 (WakeClass) AppleWebKit/537.36';
    request.headers['Accept-Language'] = 'zh-CN,zh;q=0.9';
    request.bodyFields = data;
    final streamed = await _client.send(request).timeout(timeout);
    final bytes = await streamed.stream.toBytes();
    return _Response(
      streamed.statusCode,
      _decode(bytes, streamed.headers['content-type']),
      _mergeCookie(cookie, streamed.headers['set-cookie']),
      streamed.request?.url.toString() ?? url,
      location: streamed.headers['location'],
      bytes: bytes,
    );
  }

  /// UTF-8 / GBK 自适应解码。
  String _decode(Uint8List bytes, String? contentType) {
    final ct = (contentType ?? '').toLowerCase();
    if (ct.contains('gbk') || ct.contains('gb2312')) {
      try {
        return const GbkCodec(allowMalformed: true).decode(bytes);
      } catch (_) {
        // 落到下面的自动判断
      }
    }
    final utf8Text = utf8.decode(bytes, allowMalformed: true);
    if (!utf8Text.contains('\uFFFD')) return utf8Text;
    try {
      final gbkText = const GbkCodec(allowMalformed: true).decode(bytes);
      final utf8Score = _cjkCount(utf8Text);
      final gbkScore = _cjkCount(gbkText);
      if (gbkScore > utf8Score) return gbkText;
    } catch (_) {
      // 保持 UTF-8 结果
    }
    return utf8Text;
  }

  int _cjkCount(String text) {
    var count = 0;
    for (final rune in text.runes) {
      if (rune >= 0x4E00 && rune <= 0x9FFF) count++;
    }
    return count;
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

  String _typeOf(Element e) => (e.attributes['type'] ?? 'text').toLowerCase();

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
    if (_hasPasswordForm(html)) return '登录失败，账号或密码错误';
    return '登录失败';
  }
}
