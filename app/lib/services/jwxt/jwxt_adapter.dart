import 'dart:typed_data';

import 'cas_urp_client.dart';
import 'generic_jwxt_client.dart';
import 'jwxt_types.dart';
import 'qz_jwxt_client.dart';
import 'zfsoft_client.dart';

/// 适配器探测登录页后的会话状态。
///
/// 具体适配器的挑战对象（[JwxtLoginChallenge] / [CasLoginChallenge] /
/// [ZfsoftChallenge]）放在 [handle] 里，UI 只关心「要不要验证码」。
class JwxtLoginState {
  const JwxtLoginState({
    required this.baseUrl,
    required this.needsCaptcha,
    required this.handle,
    this.captchaImage,
    this.systemName = '',
    this.detectedSemester,
  });

  final String baseUrl;
  final bool needsCaptcha;
  final Uint8List? captchaImage;
  final Object handle;
  final String systemName;

  /// 页面里识别到的学期（如 `2026-2027-1`），可空。
  final String? detectedSemester;
}

/// 教务系统适配器接口。
///
/// 新增一所学校 / 一个厂商 = 新增一个实现，并在 [JwxtAdapterRegistry] 里注册；
/// 页面（UI）只依赖这个接口，不再按厂商分支。
abstract class JwxtAdapter {
  /// 稳定标识：`zf` / `qz` / `cas` / `generic`。
  String get id;

  /// 下拉框里的名字。
  String get name;

  /// 一句话说明（显示在输入框下方）。
  String get hint;

  /// 根据 URL 判断是否像这个系统。
  bool matches(String url);

  /// 打开登录页，探测表单 / 验证码 / 公钥等。
  Future<JwxtLoginState> prepare(String url);

  /// 登录并抓取课表。
  Future<JwxtImportResult> login(
    JwxtLoginState state, {
    required String username,
    required String password,
    String captcha = '',
    String semester = '',
  });

  /// 重新加载验证码图片（CAS 等「提交后才知道要验证码」的系统用）。
  Future<Uint8List?> refreshCaptcha(JwxtLoginState state) async => null;

  void close();
}

/// 强智教务（jsxsd）。
class QzAdapter implements JwxtAdapter {
  final QzJwxtClient _client = QzJwxtClient();

  @override
  String get id => 'qz';

  @override
  String get name => '强智教务（jsxsd）';

  @override
  String get hint => '地址通常以 /jsxsd/ 结尾，如 https://jw.example.edu.cn/jsxsd/';

  @override
  bool matches(String url) => url.toLowerCase().contains('jsxsd');

  @override
  Future<JwxtLoginState> prepare(String url) async {
    final challenge = await _client.prepareLogin(url);
    return JwxtLoginState(
      baseUrl: challenge.baseUrl,
      needsCaptcha: challenge.captchaField != null,
      captchaImage: challenge.captchaImage,
      handle: challenge,
      systemName: QzJwxtClient.systemName,
    );
  }

  @override
  Future<JwxtImportResult> login(
    JwxtLoginState state, {
    required String username,
    required String password,
    String captcha = '',
    String semester = '',
  }) {
    return _client.loginAndImport(
      state.handle as JwxtLoginChallenge,
      username: username,
      password: password,
      captcha: captcha,
      semester: semester,
    );
  }

  @override
  Future<Uint8List?> refreshCaptcha(JwxtLoginState state) async => null;

  @override
  void close() => _client.close();
}

/// 统一身份认证（CAS）+ URP。
class CasAdapter implements JwxtAdapter {
  final CasUrpClient _client = CasUrpClient();

  @override
  String get id => 'cas';

  @override
  String get name => '统一身份认证（CAS）';

  @override
  String get hint => '地址栏里带 service= 的登录页地址，如 https://cas.example.edu.cn/authserver/login?service=…';

  @override
  bool matches(String url) => RegExp(r'authserver|/cas/|/cas\b|eams|/sso/',
          caseSensitive: false)
      .hasMatch(url);

  @override
  Future<JwxtLoginState> prepare(String url) async {
    final challenge = await _client.prepareLogin(url);
    return JwxtLoginState(
      baseUrl: challenge.serviceUrl,
      needsCaptcha: false,
      handle: challenge,
      systemName: CasUrpClient.systemName,
    );
  }

  @override
  Future<JwxtImportResult> login(
    JwxtLoginState state, {
    required String username,
    required String password,
    String captcha = '',
    String semester = '',
  }) {
    return _client.loginAndImport(
      state.handle as CasLoginChallenge,
      username: username,
      password: password,
      captcha: captcha,
    );
  }

  @override
  Future<Uint8List?> refreshCaptcha(JwxtLoginState state) async {
    final challenge = state.handle as CasLoginChallenge;
    final bytes = await _client.fetchCaptcha(challenge);
    return bytes;
  }

  @override
  void close() => _client.close();
}

/// 正方教务（jwglxt）。
class ZfsoftAdapter implements JwxtAdapter {
  final ZfsoftClient _client = ZfsoftClient();

  @override
  String get id => 'zf';

  @override
  String get name => '正方教务（jwglxt）';

  @override
  String get hint => '地址通常包含 /jwglxt，如 https://jw.example.edu.cn/jwglxt/xtgl/login_slogin.html';

  @override
  bool matches(String url) =>
      RegExp(r'jwglxt|/xtgl/|zfsoft', caseSensitive: false).hasMatch(url);

  @override
  Future<JwxtLoginState> prepare(String url) async {
    final challenge = await _client.prepareLogin(url);
    return JwxtLoginState(
      baseUrl: challenge.baseUrl,
      needsCaptcha: challenge.captchaField != null,
      captchaImage: challenge.captchaImage,
      handle: challenge,
      systemName: ZfsoftClient.systemName,
      detectedSemester: challenge.detectedSemester,
    );
  }

  @override
  Future<JwxtImportResult> login(
    JwxtLoginState state, {
    required String username,
    required String password,
    String captcha = '',
    String semester = '',
  }) {
    return _client.loginAndImport(
      state.handle as ZfsoftChallenge,
      username: username,
      password: password,
      captcha: captcha,
      semester: semester,
    );
  }

  @override
  Future<Uint8List?> refreshCaptcha(JwxtLoginState state) async => null;

  @override
  void close() => _client.close();
}

/// 通用适配器：不绑定厂商，自动识别登录表单 + 通用表格解析。
///
/// 放在最后作为兜底，[matches] 永远为 true。
class GenericAdapter implements JwxtAdapter {
  final GenericJwxtClient _client = GenericJwxtClient();

  @override
  String get id => 'generic';

  @override
  String get name => '通用（自动识别）';

  @override
  String get hint => '不确定是哪个系统时用它：自动找登录表单和课表页';

  @override
  bool matches(String url) => true;

  @override
  Future<JwxtLoginState> prepare(String url) async {
    final challenge = await _client.prepareLogin(url);
    return JwxtLoginState(
      baseUrl: challenge.baseUrl,
      needsCaptcha: challenge.captchaField != null,
      captchaImage: challenge.captchaImage,
      handle: challenge,
      systemName: GenericJwxtClient.systemName,
    );
  }

  @override
  Future<JwxtImportResult> login(
    JwxtLoginState state, {
    required String username,
    required String password,
    String captcha = '',
    String semester = '',
  }) {
    return _client.loginAndImport(
      state.handle as JwxtLoginChallenge,
      username: username,
      password: password,
      captcha: captcha,
      semester: semester,
    );
  }

  @override
  Future<Uint8List?> refreshCaptcha(JwxtLoginState state) async => null;

  @override
  void close() => _client.close();
}

/// 适配器注册表：负责「URL → 用哪个适配器」。
class JwxtAdapterRegistry {
  JwxtAdapterRegistry._();

  /// 创建一组适配器（顺序 = 自动识别的优先级）。
  static List<JwxtAdapter> create() => [
        ZfsoftAdapter(),
        QzAdapter(),
        CasAdapter(),
        GenericAdapter(),
      ];

  /// 自动识别：先按特征匹配具体厂商，都不匹配则用通用适配器。
  static JwxtAdapter detect(String url, List<JwxtAdapter> adapters) {
    final specific = adapters.where((a) => a.id != 'generic' && a.matches(url));
    if (specific.isNotEmpty) return specific.first;
    return adapters.firstWhere((a) => a.id == 'generic');
  }

  /// 按 id 取适配器。
  static JwxtAdapter? byId(String id, List<JwxtAdapter> adapters) {
    for (final adapter in adapters) {
      if (adapter.id == id) return adapter;
    }
    return null;
  }
}
