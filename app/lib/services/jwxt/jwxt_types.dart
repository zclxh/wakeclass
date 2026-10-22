import 'dart:typed_data';

import 'package:wakeclass_core/wakeclass_core.dart';

/// 登录前置信息：登录页探测结果。
///
/// 若 [captchaField] 非空，说明需要验证码：UI 展示 [captchaImage]
/// （可能为 null，表示纯文本验证码），用户输入后随登录提交。
class JwxtLoginChallenge {
  const JwxtLoginChallenge({
    required this.baseUrl,
    required this.loginAction,
    required this.userField,
    required this.passwordField,
    required this.hiddenFields,
    required this.cookie,
    this.captchaField,
    this.captchaImage,
  });

  /// 归一化后的教务系统根地址（如 `https://jw.example.edu.cn/jsxsd/`）。
  final String baseUrl;

  /// 登录表单提交地址（绝对 URL）。
  final String loginAction;

  /// 学号输入框字段名。
  final String userField;

  /// 密码输入框字段名。
  final String passwordField;

  /// 隐藏字段（随登录一并提交）。
  final Map<String, String> hiddenFields;

  /// 会话 Cookie（如 `JSESSIONID=xxx`）。
  final String cookie;

  /// 验证码字段名；null 表示无需验证码。
  final String? captchaField;

  /// 验证码图片字节；null 表示纯文本验证码或无验证码。
  final Uint8List? captchaImage;
}

/// 教务直连导入结果：课程列表 + 告警/提示。
class JwxtImportResult {
  const JwxtImportResult({
    required this.courses,
    required this.warnings,
    required this.systemName,
    this.semesterLabel,
  });

  final List<Course> courses;

  /// 告警与提示（如「学期：2026-2027学年第一学期」）。
  final List<String> warnings;

  final String systemName;

  /// 实际导入的学期标签（可空）。
  final String? semesterLabel;
}
