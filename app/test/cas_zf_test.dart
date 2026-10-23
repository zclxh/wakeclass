import 'package:flutter_test/flutter_test.dart';

import 'package:wakeclass_app/services/jwxt/jwxt_adapter.dart';
import 'package:wakeclass_app/services/jwxt/jwxt_exception.dart';

/// 「统一认证（CAS）→ 正方 SSO」链路测试。
///
/// 需要 `test/mock_jwxt_universal.cjs` 在 8791 端口运行。
void main() {
  const base = 'http://127.0.0.1:8791';
  const loginUrl = '$base/cas/login?service=$base/sso/zfiotlogin';
  const user = '2026005';
  const pass = 'zfpass';

  test('统一认证 + 正方回跳的地址识别为 cas_zf', () {
    final adapters = JwxtAdapterRegistry.create();
    final adapter = JwxtAdapterRegistry.detect(loginUrl, adapters);
    expect(adapter.id, 'cas_zf');

    // 金智 CAS（URP）的地址仍然归原来的 cas 适配器
    final urp = JwxtAdapterRegistry.detect(
      'https://cas.example.edu.cn/authserver/login?service=https://urp.example.edu.cn/eams/login.action',
      JwxtAdapterRegistry.create(),
    );
    expect(urp.id, 'cas');
  });

  test('CAS 登录 → 正方 SSO 会话 → 读到 kbList 课表', () async {
    final adapter =
        JwxtAdapterRegistry.byId('cas_zf', JwxtAdapterRegistry.create())!;
    final state = await adapter.prepare(loginUrl);
    expect(state.needsCaptcha, isFalse);
    expect(state.systemName, contains('正方'));

    final result = await adapter.login(
      state,
      username: user,
      password: pass,
    );
    expect(
      result.courses.map((c) => c.name),
      containsAll(<String>['高等数学A', '大学英语']),
    );
    adapter.close();
  });

  test('统一认证密码错误时给出登录失败', () async {
    final adapter =
        JwxtAdapterRegistry.byId('cas_zf', JwxtAdapterRegistry.create())!;
    final state = await adapter.prepare(loginUrl);

    await expectLater(
      adapter.login(state, username: user, password: 'wrong-pass'),
      throwsA(isA<JwxtException>().having(
        (e) => e.kind,
        'kind',
        JwxtErrorKind.loginFailed,
      )),
    );
    adapter.close();
  });
}
