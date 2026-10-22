import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' show parse;
import 'package:http/http.dart' as http;
import 'package:wakeclass_core/wakeclass_core.dart';

import 'cas_encrypt.dart';
import 'jwxt_exception.dart';
import 'jwxt_types.dart';
import 'schedule_table_parser.dart';

/// 一次 HTTP 响应摘要。
class _HttpResult {
  const _HttpResult(this.status, this.text, this.cookie, this.url,
      this.location, this.bodyBytes);

  final int status;
  final String text;
  final String cookie;
  final String url;
  final String? location;

  /// 原始字节（解码前的响应体）。
  final Uint8List bodyBytes;

  bool get isRedirect => status == 301 || status == 302 || status == 303;
}

/// CAS 登录前置信息。
class CasLoginChallenge {
  const CasLoginChallenge({
    required this.loginUrl,
    required this.execution,
    required this.pwdEncryptSalt,
    required this.lt,
    required this.cookie,
    required this.serviceUrl,
    required this.captchaUrl,
    this.captchaImage,
  });

  /// 登录提交地址（含 service 参数）。
  final String loginUrl;

  /// 金智 CAS 的 execution 令牌。
  final String execution;

  /// AES 密钥（页面隐藏字段）。
  final String pwdEncryptSalt;

  /// lt 字段（初始为空）。
  final String lt;

  /// 会话 Cookie。
  final String cookie;

  /// 目标教务系统地址（service 参数）。
  final String serviceUrl;

  /// 验证码图片地址。
  final String captchaUrl;

  /// 验证码图片字节（验证码被要求时加载）。
  final Uint8List? captchaImage;
}

/// CAS 统一认证 + URP 教务系统直连客户端。
///
/// 流程（针对沈阳建筑大学 authserver.sjzu.edu.cn 实测）：
/// 1. 探测登录页：提取 `execution` / `pwdEncryptSalt` / `lt`；
/// 2. 登录：密码按 encrypt.js 规则 AES-CBC 加密后 POST（验证码按需人工输入）；
/// 3. 跟随 302 票据跳转（authserver → eams），合并 Cookie；
/// 4. 在 URP 落地页查找课表链接 / 尝试常见课表地址；
/// 5. 解析课表 HTML（UTF-8 / GBK 自适应）。
class CasUrpClient {
  CasUrpClient(
      {http.Client? client, this.timeout = const Duration(seconds: 15)})
      : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  static const String systemName = '统一身份认证（CAS）· URP';

  /// URP 常见课表页相对路径（找不到菜单链接时逐个尝试）。
  static const _schedulePathCandidates = [
    'courseTableForStd!courseTable.action?projectId=1',
    'courseTableForStd.action',
    'teach/personalScheduleQuery.action',
    'courseTable/courseTable.action',
  ];

  // ---------- 第一步：探测登录页 ----------

  Future<CasLoginChallenge> prepareLogin(String authUrl) async {
    final uri = Uri.parse(authUrl.trim());
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const JwxtException(
          JwxtErrorKind.badUrl, '教务系统地址格式不正确', hint: '请粘贴完整的统一身份认证登录地址');
    }
    final service = uri.queryParameters['service'];
    if (service == null || service.isEmpty) {
      throw const JwxtException(JwxtErrorKind.badUrl, '登录地址缺少 service 参数',
          hint: '请粘贴浏览器地址栏里的完整登录地址');
    }
    final origin = '${uri.scheme}://${uri.authority}';
    final captchaUrl = '$origin/authserver/getCaptcha.htl';

    // 先访问教务入口：eams 会 302 回统一认证并携带「权威 service」
    // （含新生成的 ;jsessionid=，票据按该地址签发，不能简化）。
    var canonicalService = service;
    var seedCookie = '';
    try {
      final probe = await _get(service);
      final location = probe.location;
      if (probe.isRedirect && location != null) {
        final locUri =
            Uri.parse(Uri.parse(probe.url).resolve(location).toString());
        final locService = locUri.queryParameters['service'];
        if (locService != null && locService.isNotEmpty) {
          canonicalService = locService;
        }
      }
      if (probe.cookie.isNotEmpty) seedCookie = probe.cookie;
    } catch (_) {
      // 入口不可达则沿用原 service（后续登录页探测会报网络错误）。
    }

    final loginPageUrl = Uri.parse('$origin/authserver/login')
        .replace(queryParameters: {'service': canonicalService})
        .toString();
    final loginUrl = loginPageUrl;

    final _HttpResult page;
    try {
      page = await _get(loginPageUrl, cookie: seedCookie);
    } on TimeoutException {
      throw const JwxtException(JwxtErrorKind.network, '连接统一身份认证超时',
          hint: '请检查网络或学校系统是否只允许校园网访问。');
    } catch (e) {
      throw JwxtException(JwxtErrorKind.network, '无法连接统一身份认证：$e');
    }
    if (page.status >= 400) {
      throw JwxtException(JwxtErrorKind.network, '登录页返回错误（${page.status}）');
    }

    final document = parse(page.text);
    final execution =
        _fieldValue(document, 'input#execution');
    final pwdEncryptSalt = _fieldValue(document, 'input#pwdEncryptSalt');
    final lt = _fieldValue(document, 'input#lt');
    if (execution.isEmpty || pwdEncryptSalt.isEmpty) {
      throw const JwxtException(JwxtErrorKind.loginFormNotFound,
          '登录页结构无法识别（缺少 execution / 加密盐）',
          hint: '学校可能更换了认证系统，请改用截图导入。');
    }

    return CasLoginChallenge(
      loginUrl: loginUrl,
      execution: execution,
      pwdEncryptSalt: pwdEncryptSalt,
      lt: lt,
      cookie: page.cookie,
      serviceUrl: canonicalService,
      captchaUrl: captchaUrl,
    );
  }

  /// 下载验证码图片（登录被要求验证码时调用）。
  Future<Uint8List> fetchCaptcha(CasLoginChallenge challenge) async {
    final url = '${challenge.captchaUrl}?${DateTime.now().millisecondsSinceEpoch}';
    final request = http.Request('GET', Uri.parse(url));
    if (challenge.cookie.isNotEmpty) {
      request.headers['Cookie'] = challenge.cookie;
    }
    final streamed = await _client.send(request).timeout(timeout);
    if (streamed.statusCode >= 400) {
      throw const JwxtException(JwxtErrorKind.network, '验证码图片加载失败');
    }
    return streamed.stream.toBytes();
  }

  // ---------- 第二步：登录并导入课表 ----------

  Future<JwxtImportResult> loginAndImport(
    CasLoginChallenge challenge, {
    required String username,
    required String password,
    String captcha = '',
    void Function(String url, int status, bool looksSchedule)? onProbe,
    void Function(String url, String html)? onHtml,
    void Function(String url, Uint8List bytes)? onRaw,
    void Function(String url)? onLanding,
  }) async {
    final encrypted = encryptCasPassword(password, challenge.pwdEncryptSalt);
    final data = <String, String>{
      'username': username,
      'password': encrypted,
      '_eventId': 'submit',
      'cllt': 'userNameLogin',
      'dllt': 'generalLogin',
      'lt': challenge.lt,
      'execution': challenge.execution,
    };
    if (captcha.isNotEmpty) data['captcha'] = captcha;

    _HttpResult loginRes;
    try {
      loginRes = await _post(challenge.loginUrl, data,
          cookie: challenge.cookie, referer: challenge.loginUrl);
    } on TimeoutException {
      throw const JwxtException(JwxtErrorKind.network, '登录请求超时');
    } catch (e) {
      throw JwxtException(JwxtErrorKind.network, '登录请求失败：$e');
    }

    if (loginRes.isRedirect) {
      // 成功：跟随票据跳转。
      final landing = await _followRedirects(loginRes);
      if (landing == null) {
        throw const JwxtException(JwxtErrorKind.loginFailed, '登录跳转异常');
      }
      onLanding?.call(landing.url);
      return await _importFromUrp(landing, challenge.serviceUrl,
          onProbe: onProbe, onHtml: onHtml, onRaw: onRaw);
    }

    // 登录失败（200）：解析错误信息。
    final body = loginRes.text;
    if (RegExp(r'captchaError|验证码错误|请输入验证码').hasMatch(body)) {
      throw const JwxtException(JwxtErrorKind.captchaRequired, '需要输入验证码',
          hint: '请填写图片中的验证码后重新提交。');
    }
    throw JwxtException(
      JwxtErrorKind.loginFailed,
      _errorText(body),
      hint: '请核对学号与密码；如学校使用企业微信/扫码登录，请改用截图导入。',
    );
  }

  Future<JwxtImportResult> _importFromUrp(
    _HttpResult landing,
    String serviceUrl, {
    void Function(String url, int status, bool looksSchedule)? onProbe,
    void Function(String url, String html)? onHtml,
    void Function(String url, Uint8List bytes)? onRaw,
  }) async {
    final warnings = <String>[];

    // 票据落地后仍回登录页 → eams 未接受票据（多半是 service 地址不匹配）。
    if (_hasPasswordForm(landing.text)) {
      throw const JwxtException(JwxtErrorKind.loginFailed, '教务系统未接受登录票据',
          hint: '请粘贴浏览器地址栏里的完整登录地址重试（保留 ;jsessionid= 部分），'
              '或改用截图导入。');
    }

    // URP 常用 URL 重写（;jsessionid=）跟踪会话：后续请求都需携带。
    final jsid = _jsessionIdOf(landing.url) ?? _jsessionIdOf(serviceUrl);
    String withJsid(String url) => _withJsid(url, jsid);

    // 课表链接：落地页 + 框架页（URP 首页常为 frameset，菜单在子 frame 里）。
    final linkPages = <String>[
      landing.url,
      ..._frameUrls(landing.text, landing.url).take(3),
    ];
    final scheduleLinks = <String>[];
    for (final pageUrl in linkPages) {
      if (pageUrl == landing.url) {
        scheduleLinks
            .addAll(_scheduleLinks(landing.text, landing.url).map(withJsid));
      } else {
        try {
          final frame = await _get(withJsid(pageUrl),
              cookie: landing.cookie, referer: landing.url);
          if (frame.status < 400) {
            scheduleLinks
                .addAll(_scheduleLinks(frame.text, frame.url).map(withJsid));
          }
        } catch (_) {
          // 框架页不可达则跳过
        }
      }
    }

    // 广度优先走查：URP 课表页常嵌在多层 frameset 里。
    final queue = <(String, int)>[
      for (final url in {
        ...scheduleLinks,
        ..._defaultScheduleUrls(serviceUrl).map(withJsid),
      })
        (url, 0),
    ];
    final seen = <String>{};
    var fetched = 0;
    while (queue.isNotEmpty && fetched < 20) {
      final (url, depth) = queue.removeAt(0);
      if (!seen.add(url)) continue;
      fetched++;
      _HttpResult page;
      try {
        page = await _get(url, cookie: landing.cookie, referer: landing.url);
      } catch (_) {
        onProbe?.call(url, -1, false);
        continue;
      }
      final isSchedule = _looksLikeSchedule(page.text);
      onProbe?.call(url, page.status, isSchedule);
      onHtml?.call(url, page.text);
      onRaw?.call(url, page.bodyBytes);
      if (page.status >= 400) continue;

      if (isSchedule) {
        final parsed = const ScheduleTableParser()
            .parseSchedule(page.text, source: 'urp');
        if (parsed.courses.isEmpty) continue;
        warnings.addAll(parsed.warnings);
        return JwxtImportResult(
          courses: parsed.courses,
          warnings: warnings,
          systemName: systemName,
        );
      }

      // URP 标准课表壳页（courseTableForm）：按其 searchTable() JS 逻辑
      // POST 到 courseTableForStd!courseTable.action 取课表表格。
      if (page.text.contains('courseTableForm')) {
        final result = await _importUrpCourseTable(page, landing,
            onProbe: onProbe, onHtml: onHtml, onRaw: onRaw);
        if (result != null) {
          warnings.addAll(result.warnings);
          return JwxtImportResult(
            courses: result.courses,
            warnings: warnings,
            systemName: systemName,
          );
        }
      }

      // 非课表页 → 若为框架页则深入其子 frame。
      if (depth < 2) {
        for (final frameUrl in _frameUrls(page.text, page.url)) {
          queue.add((withJsid(frameUrl), depth + 1));
        }
      }
    }

    throw const JwxtException(
        JwxtErrorKind.noSchedule, '登录成功，但没有找到课表页面',
        hint: '请确认本学期已排课；如页面结构特殊，请改用截图导入。');
  }

  /// URP 标准课表查询：从壳页提取参数，POST 获取课表页。
  ///
  /// 课表页的网格由 JS 填充，真实数据在「授课信息」明细表里：
  /// 每门课一行，授课信息列为多条「第N周 星期X Y-Z节 教室」记录。
  Future<JwxtImportResult?> _importUrpCourseTable(
    _HttpResult shell,
    _HttpResult landing, {
    void Function(String url, int status, bool looksSchedule)? onProbe,
    void Function(String url, String html)? onHtml,
    void Function(String url, Uint8List bytes)? onRaw,
  }) async {
    final ids = RegExp(r'addInput\(form\s*,\s*"ids"\s*,\s*"(\d+)"\)')
            .firstMatch(shell.text)
            ?.group(1) ??
        '';
    if (ids.isEmpty) return null;
    final semesterId =
        RegExp(r'value\s*:\s*"(\d+)"').firstMatch(shell.text)?.group(1) ?? '';

    final jsid = _jsessionIdOf(shell.url) ?? _jsessionIdOf(landing.url);
    final origin = Uri.parse(shell.url);
    final eamsRoot = '${origin.scheme}://${origin.authority}/eams/';
    final target = '${eamsRoot}courseTableForStd!courseTable.action'
        '${jsid != null ? ';jsessionid=$jsid' : ''}';

    final data = <String, String>{
      'ignoreHead': '1',
      'showPrintAndExport': '1',
      'setting.kind': 'std',
      'startWeek': '',
      'project.id': '',
      'semester.id': semesterId,
      'ids': ids,
    };
    _HttpResult res;
    try {
      res = await _post(target, data, cookie: landing.cookie, referer: shell.url);
    } catch (_) {
      onProbe?.call(target, -1, false);
      return null;
    }
    onProbe?.call(target, res.status, _looksLikeSchedule(res.text));
    onHtml?.call(target, res.text);
    onRaw?.call(target, res.bodyBytes);
    if (res.status >= 400) return null;

    // 首选：页面内嵌的 TaskActivity 数据（全部课程：理论 + 实验）。
    final activityCourses = _parseUrpActivities(res.text);
    if (activityCourses.isNotEmpty) {
      return JwxtImportResult(
        courses: activityCourses,
        warnings: const [],
        systemName: systemName,
      );
    }

    // 兜底 1：实验安排明细表。
    final courses = _parseUrpTaskTable(res.text);
    if (courses.isNotEmpty) {
      return JwxtImportResult(
        courses: courses,
        warnings: const [],
        systemName: systemName,
      );
    }

    // 兜底 2：网格表格。
    final parsed = const ScheduleTableParser().parseSchedule(res.text,
        source: 'urp', cleanCellText: _cleanUrpCellText);
    if (parsed.courses.isEmpty) return null;
    return JwxtImportResult(
      courses: parsed.courses,
      warnings: parsed.warnings,
      systemName: systemName,
    );
  }

  /// 页面内嵌 TaskActivity 数据 → 课程列表。
  ///
  /// 页面结构（URP courseTableContent）：
  /// ```js
  /// var actTeachers = [{id:16672,name:"张颖",lab:false},...];
  /// activity = new TaskActivity(...,"课程名(代码)","教室(学校)","011...",...);
  /// index = 星期(0起)*unitCount+节次(0起);
  /// table0.activities[index][...] = activity;
  /// ```
  /// 周次为 53 位掩码：第 i 位为 1 表示第 i 周（第 0 位恒为 0）。
  static final _activitySplitRe =
      RegExp(r'activity\s*=\s*new TaskActivity\(');
  static final _quotedRe = RegExp(r'"((?:[^"\\]|\\.)*)"');
  static final _indexRe = RegExp(
      r'index\s*=\s*(\d+)\*unitCount\+(\d+);\s*'
      r'table0\.activities\[index\]\[table0\.activities\[index\]\.length\]=activity;');
  static final _teacherNameRe = RegExp(r'name:\s*"([^"]+)"');
  static final _weeksBitsRe = RegExp(r'^[01]{30,}$');
  static final _suffixRe = RegExp(r'\([^)]*\)$');

  List<Course> _parseUrpActivities(String html) {
    final chunks = html.split(_activitySplitRe);
    final courses = <Course>[];
    if (chunks.length < 2) return courses;

    for (var i = 1; i < chunks.length; i++) {
      final chunk = chunks[i];
      final paramsEnd = chunk.indexOf(');');
      if (paramsEnd < 0) continue;
      final params = chunk.substring(0, paramsEnd);
      final tail = chunk.substring(paramsEnd + 2);

      // 参数里的引号串：课程代码、课程名、教室号、教室名、周次掩码…
      final quoted = _quotedRe
          .allMatches(params)
          .map((m) => m.group(1)!)
          .toList();
      if (quoted.length < 2) continue;
      final courseName =
          quoted[1].replaceAll(_suffixRe, '').trim();
      if (courseName.isEmpty) continue;
      final roomName = quoted.length > 3
          ? quoted[3].replaceAll(_suffixRe, '').trim()
          : '';
      final bits = quoted.firstWhere(
        (q) => _weeksBitsRe.hasMatch(q),
        orElse: () => '',
      );

      // 教师：来自前一区块尾部的 actTeachers 数组。
      final prev = chunks[i - 1];
      final prevTail = prev.length > 2000 ? prev.substring(prev.length - 2000) : prev;
      final teachers = _teacherNameRe
          .allMatches(prevTail)
          .map((m) => m.group(1)!)
          .toSet()
          .toList();

      // 星期与节次（连续 unit 行合并为节次区间）。
      final units = <int>[];
      var day = -1;
      for (final m in _indexRe.allMatches(tail)) {
        day = int.parse(m.group(1)!);
        units.add(int.parse(m.group(2)!));
      }
      if (day < 0 || units.isEmpty) continue;

      // 周次掩码：第 i 位 = 第 i 周。
      final weeks = <int>[];
      if (bits.isNotEmpty) {
        for (var w = 1; w < bits.length; w++) {
          if (bits[w] == '1') weeks.add(w);
        }
      }

      courses.add(Course.create(
        name: courseName,
        teacher: teachers.join(','),
        location: roomName,
        weeks: weeks,
        dayOfWeek: day + 1,
        startPeriod: units.reduce((a, b) => a < b ? a : b) + 1,
        endPeriod: units.reduce((a, b) => a > b ? a : b) + 1,
        source: 'urp',
      ));
    }
    return courses;
  }

  /// 授课信息明细表 → 课程列表。
  ///
  /// 授课信息文本形如：`第9 周 星期五 1-2节 A305物理实验室`
  /// 一门课的多条记录拆成多条课程单元（各自周次/节次/教室）。
  static final _urpTaskRe = RegExp(
    r'第\s*(\d{1,2})(?:\s*[-—–~～至]\s*(\d{1,2}))?\s*周(?:\(([单双])\))?'
    r'\s*星期([一二三四五六日天])\s*(\d{1,2})\s*[-—–~～至]\s*(\d{1,2})\s*节\s*(\S+)',
  );

  List<Course> _parseUrpTaskTable(String html) {
    final document = parse(html);
    final courses = <Course>[];

    int dayOf(String s) {
      if (s == '日' || s == '天') return 7;
      return '一二三四五六'.indexOf(s) + 1;
    }

    for (final table in document.querySelectorAll('table')) {
      final text = table.text;
      if (!text.contains('授课信息') || !text.contains('教师')) continue;
      final rows = table.querySelectorAll('tr').toList();
      if (rows.length < 2) continue;

      // 表头列定位。
      final headerCells = rows.first.children;
      int? nameCol;
      int? teacherCol;
      int? infoCol;
      for (var i = 0; i < headerCells.length; i++) {
        final h = headerCells[i].text.trim();
        if (h == '课程名称' || h == '课程名') nameCol = i;
        if (h == '教师') teacherCol = i;
        if (h == '授课信息') infoCol = i;
      }
      if (nameCol == null || infoCol == null) continue;

      for (final row in rows.skip(1)) {
        final cells = row.children;
        if (cells.length <= infoCol) continue;
        final name = cells[nameCol].text.trim();
        if (name.isEmpty) continue;
        final teacher =
            teacherCol != null && cells.length > teacherCol
                ? cells[teacherCol].text.trim()
                : '';
        final info = cells[infoCol].text.replaceAll('&nbsp;', ' ');

        for (final m in _urpTaskRe.allMatches(info)) {
          final weekStart = int.parse(m.group(1)!);
          final weekEnd = m.group(2) != null ? int.parse(m.group(2)!) : weekStart;
          final parity = m.group(3);
          final day = dayOf(m.group(4)!);
          final startPeriod = int.parse(m.group(5)!);
          final endPeriod = int.parse(m.group(6)!);
          final location = m.group(7)!.replaceAll(RegExp(r'\s+'), '');

          var weeks = <int>[
            for (var w = weekStart; w <= weekEnd; w++) w,
          ];
          if (parity == '单') weeks = weeks.where((w) => w.isOdd).toList();
          if (parity == '双') weeks = weeks.where((w) => w.isEven).toList();
          if (weeks.isEmpty) continue;

          courses.add(Course.create(
            name: name,
            teacher: teacher,
            location: location,
            weeks: weeks,
            dayOfWeek: day,
            startPeriod: startPeriod,
            endPeriod: endPeriod,
            source: 'urp',
          ));
        }
      }
      if (courses.isNotEmpty) break;
    }
    return courses;
  }

  /// URP 课表单元格清洗：去掉课程代码、按钮文字等噪声行。
  static String _cleanUrpCellText(String cellText) {
    final noise = RegExp(r'授课计划|课程小结|课程简介|教师简介|教学日历|教学大纲|培养方案');
    final kept = <String>[];
    for (final line in cellText.split(RegExp(r'[\r\n]+'))) {
      final t = line.trim();
      if (t.isEmpty) continue;
      if (RegExp(r'^[A-Za-z]?\d{6,}$').hasMatch(t)) continue; // 课程代码
      if (noise.hasMatch(t)) continue;
      kept.add(t);
    }
    return kept.join('\n');
  }

  /// 从 URL 路径中提取 jsessionid（URP 的 URL 重写会话）。
  String? _jsessionIdOf(String url) {
    final m = RegExp(r';jsessionid=([A-Za-z0-9]+)', caseSensitive: false)
        .firstMatch(url);
    return m?.group(1);
  }

  /// 若 URL 尚不携带 jsessionid，则注入（保持 query 不变）。
  String _withJsid(String url, String? jsid) {
    if (jsid == null || jsid.isEmpty) return url;
    final uri = Uri.parse(url);
    if (RegExp(r';jsessionid=', caseSensitive: false).hasMatch(uri.path)) {
      return url;
    }
    return uri.replace(path: '${uri.path};jsessionid=$jsid').toString();
  }

  /// 页面中的 iframe/frame 地址。
  List<String> _frameUrls(String html, String baseUrl) {
    final document = parse(html);
    final urls = <String>[];
    for (final frame in document.querySelectorAll('iframe, frame')) {
      final src = frame.attributes['src'] ?? '';
      if (src.isEmpty || src.startsWith('#')) continue;
      try {
        urls.add(Uri.parse(baseUrl).resolve(src).toString());
      } catch (_) {
        continue;
      }
    }
    return urls;
  }

  /// 从落地页 HTML 中提取「课表」相关链接。
  List<String> _scheduleLinks(String html, String baseUrl) {
    final document = parse(html);
    final links = <String>[];
    for (final a in document.querySelectorAll('a')) {
      final text = a.text.trim();
      if (RegExp(r'课表|课程表').hasMatch(text) && text.length <= 12) {
        final href = a.attributes['href'] ?? '';
        if (href.isEmpty || href.startsWith('#')) continue;
        try {
          links.add(Uri.parse(baseUrl).resolve(href).toString());
        } catch (_) {
          continue;
        }
      }
    }
    return links.take(5).toList();
  }

  /// 按 service 地址推导 URP 根，拼出常见课表页地址。
  List<String> _defaultScheduleUrls(String serviceUrl) {
    final uri = Uri.parse(serviceUrl);
    final origin = '${uri.scheme}://${uri.authority}';
    final path = uri.path;
    final eamsRoot = path.contains('/eams/')
        ? '$origin/eams/'
        : (path.contains('/eams')
            ? '$origin/eams/'
            : origin.endsWith('/')
                ? origin
                : '$origin/');
    return [
      for (final p in _schedulePathCandidates) '$eamsRoot$p',
    ];
  }

  // ---------- 工具 ----------

  bool _hasPasswordForm(String html) =>
      RegExp('<input\\b[^>]*type\\s*=\\s*["\']?password', caseSensitive: false)
          .hasMatch(html);

  static bool _looksLikeSchedule(String html) {
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
        (weekHits >= 2 ||
            sectionHits >= 2 ||
            text.contains('课表') ||
            text.contains('课程表'));
  }

  String _errorText(String html) {
    final document = parse(html);
    for (final selector in ['#showErrorTip', '.form-error']) {
      for (final el in document.querySelectorAll(selector)) {
        final t = el.text.trim();
        if (t.isNotEmpty && t.length <= 80) return t;
      }
    }
    final text = document.documentElement?.text ?? '';
    for (final line in text.split('\n')) {
      final t = line.trim();
      if (RegExp(r'用户名|学号|密码|账号').hasMatch(t) &&
          RegExp(r'错误|不正确|失败|无效|锁定').hasMatch(t) &&
          t.length <= 80) {
        return t;
      }
    }
    // 金智 CAS 失败也可能返回 JSON。
    try {
      final map = jsonDecode(html);
      if (map is Map && map['message'] is String) {
        return map['message'] as String;
      }
    } catch (_) {
      // 非 JSON
    }
    return '登录失败';
  }

  String _fieldValue(Document document, String selector) {
    final el = document.querySelector(selector);
    return el?.attributes['value'] ?? '';
  }

  /// 常见中文词表：按命中数判断哪种解码正确（GBK 误按 UTF-8 解码时
  /// 中文全部变乱码，命中数为 0）。
  static final _chineseTokensRe = RegExp(
      r'星期一|星期二|星期三|星期四|星期五|星期六|星期日|周一|周二|周三|周四|周五|周六|周日|'
      r'第[一二三四五六七八九十\d]+节|周次|课程|课表|教师|教室|时间|学期|学生|教学|'
      r'登录|密码|验证码|账号|学号|我的|首页|地点');

  int _chineseScore(String text) => _chineseTokensRe.allMatches(text).length;

  String _decodeBody(Uint8List bytes, String? contentType) {
    const gbkLoose = GbkCodec(allowMalformed: true);
    final ct = (contentType ?? '').toLowerCase();
    if (ct.contains('gbk') || ct.contains('gb2312')) {
      return gbkLoose.decode(bytes);
    }
    // 三种候选解码：
    // 1. 纯 UTF-8；2. 纯 GBK；3. 服务端双重编码（UTF-8 文本进了 GBK 管道：
    //    GBK 解码得到乱码字符串，再按 GBK 编码回字节、按 UTF-8 解码还原）。
    final utf8Text = utf8.decode(bytes, allowMalformed: true);
    final gbkText = gbkLoose.decode(bytes);
    final recovered = utf8.decode(gbkLoose.encode(gbkText), allowMalformed: true);

    var best = utf8Text;
    var bestScore = _chineseScore(utf8Text);
    final gbkScore = _chineseScore(gbkText);
    if (gbkScore > bestScore) {
      best = gbkText;
      bestScore = gbkScore;
    }
    final recoveredScore = _chineseScore(recovered);
    if (recoveredScore > bestScore) {
      best = recovered;
      bestScore = recoveredScore;
    }
    // 兜底：UTF-8 出现替换符且无有效中文命中时，优先取还原文本。
    if (bestScore == 0 && utf8Text.contains('\uFFFD')) {
      return recoveredScore > 0 ? recovered : gbkText;
    }
    return best;
  }

  Future<_HttpResult> _get(String url,
      {String cookie = '', String referer = ''}) async {
    final request = http.Request('GET', Uri.parse(url));
    // 重定向必须手动跟随（票据跳转 / 302 Location 是流程关键信息）。
    request.followRedirects = false;
    if (cookie.isNotEmpty) request.headers['Cookie'] = cookie;
    if (referer.isNotEmpty) request.headers['Referer'] = referer;
    request.headers['User-Agent'] =
        'Mozilla/5.0 (WakeClass) AppleWebKit/537.36';
    final streamed = await _client.send(request).timeout(timeout);
    final bytes = await streamed.stream.toBytes();
    return _HttpResult(
      streamed.statusCode,
      _decodeBody(bytes, streamed.headers['content-type']),
      _mergeCookie(cookie, streamed.headers['set-cookie']),
      streamed.request?.url.toString() ?? url,
      streamed.headers['location'],
      bytes,
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
    return _HttpResult(
      streamed.statusCode,
      _decodeBody(bytes, streamed.headers['content-type']),
      _mergeCookie(cookie, streamed.headers['set-cookie']),
      streamed.request?.url.toString() ?? url,
      streamed.headers['location'],
      bytes,
    );
  }

  Future<_HttpResult?> _followRedirects(_HttpResult first) async {
    var cur = first;
    for (var i = 0; i < 8; i++) {
      if (!cur.isRedirect) return cur;
      final location = cur.location;
      if (location == null || location.isEmpty) return null;
      final target = Uri.parse(cur.url).resolve(location).toString();
      try {
        cur = await _get(target, cookie: cur.cookie, referer: cur.url);
      } catch (_) {
        return null;
      }
    }
    return cur;
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

  void close() => _client.close();
}
