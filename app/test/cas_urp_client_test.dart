import 'dart:convert';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wakeclass_app/services/jwxt/cas_encrypt.dart';
import 'package:wakeclass_app/services/jwxt/cas_urp_client.dart';
import 'package:wakeclass_app/services/jwxt/jwxt_exception.dart';

/// 本地模拟 CAS + URP 教务系统（app/test/mock_cas_urp.cjs，默认端口 8790）。
/// 测试账号：2026003 / caspass；captchauser 触发验证码流程（验证码 1234）。
const mockBase = 'http://127.0.0.1:8790';
const loginUrl = '$mockBase/authserver/login'
    '?service=http%3A%2F%2F127.0.0.1%3A8790%2Feams%2FhomeExt.action';

Future<bool> _mockServerUp() async {
  final client = http.Client();
  try {
    final res = await client
        .get(Uri.parse('$mockBase/authserver/login'))
        .timeout(const Duration(seconds: 3));
    return res.statusCode == 200;
  } catch (_) {
    return false;
  } finally {
    client.close();
  }
}

void main() {
  group('encryptCasPassword', () {
    test('与 Node crypto 参考向量一致（固定 iv 与前缀）', () {
      final out = encryptCasPassword(
        'secret123',
        'VambL0PEjllx5yfC',
        iv: 'ABCDEFGHJKLMNPQR',
        prefix: List.filled(64, 'A').join(),
      );
      expect(
        out,
        'T/Ogo5wBVJs1o+60Al4VvlwL7uk4X4fJKiTMHhRpiWTnPrjeUZmigHkXmq5u0ER'
        'C4oy5duapQJRjbMUNjc2w6+3guH+TReM7hcWDWozc0iI=',
      );
    });

    test('输出为 Base64 且密文长度为 16 的倍数（64 前缀 + PKCS7）', () {
      final out = encryptCasPassword('pwd', 'VambL0PEjllx5yfC');
      final bytes = base64.decode(out);
      expect(bytes.length % 16, 0);
      expect(bytes.length, 80); // 64 + 3 → 填充到 80
    });
  });

  group('GBK 解码（URP 页面常见编码）', () {
    test('GBK 编解码往返', () {
      final encoded = gbk.encode('高等数学 教一101 张明远');
      expect(gbk.decode(encoded), '高等数学 教一101 张明远');
    });
  });

  group('CasUrpClient（本地模拟 CAS+URP）', () {
    setUpAll(() async {
      if (!await _mockServerUp()) {
        markTestSkipped('本地模拟 CAS+URP 服务器未启动：'
            '运行 node app/test/mock_cas_urp.cjs 后重跑');
      }
    });

    test('端到端：CAS 登录 → URP 课表 → 14 门课', () async {
      final client = CasUrpClient();
      try {
        final challenge = await client.prepareLogin(loginUrl);
        expect(challenge.execution, 'mock-execution-abc123');
        expect(challenge.pwdEncryptSalt, 'VambL0PEjllx5yfC');

        final result = await client.loginAndImport(
          challenge,
          username: '2026003',
          password: 'caspass',
        );
        expect(result.systemName, contains('CAS'));
        expect(result.courses, hasLength(14));
        expect(result.courses.first.source, 'urp');
        final math = result.courses.firstWhere(
            (c) => c.name == '高等数学A' && c.dayOfWeek == 1);
        expect(math.startPeriod, 1);
        expect(math.endPeriod, 2);
      } finally {
        client.close();
      }
    });

    test('密码错误 → loginFailed', () async {
      final client = CasUrpClient();
      try {
        final challenge = await client.prepareLogin(loginUrl);
        await expectLater(
          client.loginAndImport(
            challenge,
            username: '2026003',
            password: 'wrong-password',
          ),
          throwsA(isA<JwxtException>()
              .having((e) => e.kind, 'kind', JwxtErrorKind.loginFailed)),
        );
      } finally {
        client.close();
      }
    });

    test('验证码流程：captchaRequired → 取图 → 重提成功', () async {
      final client = CasUrpClient();
      try {
        final challenge = await client.prepareLogin(loginUrl);
        await expectLater(
          client.loginAndImport(
            challenge,
            username: 'captchauser',
            password: 'whatever',
          ),
          throwsA(isA<JwxtException>().having(
              (e) => e.kind, 'kind', JwxtErrorKind.captchaRequired)),
        );

        final image = await client.fetchCaptcha(challenge);
        expect(image, isNotEmpty);

        final result = await client.loginAndImport(
          challenge,
          username: 'captchauser',
          password: 'whatever',
          captcha: '1234',
        );
        expect(result.courses, hasLength(14));
      } finally {
        client.close();
      }
    });
  });
}
