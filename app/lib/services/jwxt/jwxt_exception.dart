/// 教务系统直连错误类型。
enum JwxtErrorKind {
  /// 地址格式不正确。
  badUrl,

  /// 网络不可达 / 超时。
  network,

  /// 页面上没有找到登录表单。
  loginFormNotFound,

  /// 登录失败（账号密码错误或验证码错误）。
  loginFailed,

  /// 需要输入验证码（登录后仍可重新提交）。
  captchaRequired,

  /// 登录成功但没有读取到课表。
  noSchedule,

  /// 会话失效（访问课表页被重定向回登录页）。
  sessionLost,
}

/// 教务系统直连异常：携带可展示的错误类型与建议。
class JwxtException implements Exception {
  const JwxtException(this.kind, this.message, {this.hint = ''});

  final JwxtErrorKind kind;

  /// 用户可读的错误描述。
  final String message;

  /// 建议（如何解决）。
  final String hint;

  @override
  String toString() => 'JwxtException(${kind.name}: $message${hint.isEmpty ? '' : '（$hint）'})';
}
