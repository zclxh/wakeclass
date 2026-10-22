import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wakeclass_app/services/jwxt/jwxt_exception.dart';
import 'package:wakeclass_app/services/jwxt/qz_jwxt_client.dart';

/// 本地模拟强智教务系统（wakeclass/test/mock-jwxt.mjs，默认端口 8788）。
/// 测试账号：2026002 / qzpass。
const mockBase = 'http://127.0.0.1:8788';

Future<bool> _mockServerUp() async {
  final client = http.Client();
  try {
    final res = await client
        .get(Uri.parse('$mockBase/jsxsd/'))
        .timeout(const Duration(seconds: 3));
    return res.statusCode == 200;
  } catch (_) {
    return false;
  } finally {
    client.close();
  }
}

void main() {
  group('QzJwxtClient（本地模拟教务系统）', () {
    setUpAll(() async {
      if (!await _mockServerUp()) {
        markTestSkipped('本地模拟教务系统未启动：'
            '运行 node wakeclass/test/mock-jwxt.mjs 后重跑');
      }
    });

    test('normalizeBase 归一化强智根地址', () {
      expect(QzJwxtClient.normalizeBase('https://jw.example.edu.cn'),
          'https://jw.example.edu.cn/jsxsd/');
      expect(QzJwxtClient.normalizeBase('http://jw.example.edu.cn/jsxsd'),
          'http://jw.example.edu.cn/jsxsd/');
      expect(QzJwxtClient.normalizeBase(mockBase),
          '$mockBase/jsxsd/');
      expect(
        () => QzJwxtClient.normalizeBase('不是地址'),
        throwsA(isA<JwxtException>()
            .having((e) => e.kind, 'kind', JwxtErrorKind.badUrl)),
      );
    });

    test('端到端：登录 → 课表 → 14 门课', () async {
      final client = QzJwxtClient();
      try {
        final challenge = await client.prepareLogin(mockBase);
        // 模拟系统登录表单无验证码。
        expect(challenge.captchaField, isNull);
        expect(challenge.userField, 'userAccount');
        expect(challenge.passwordField, 'userPassword');

        final result = await client.loginAndImport(
          challenge,
          username: '2026002',
          password: 'qzpass',
        );
        expect(result.systemName, '强智教务系统');
        expect(result.semesterLabel, '2026-2027学年第一学期');
        expect(result.courses, hasLength(14));
        expect(result.warnings, contains(startsWith('学期：')));

        final math = result.courses.firstWhere(
            (c) => c.name == '高等数学A' && c.dayOfWeek == 1);
        expect(math.startPeriod, 1);
        expect(math.endPeriod, 2);
        expect(math.source, 'jwxt');
      } finally {
        client.close();
      }
    });

    test('密码错误 → loginFailed', () async {
      final client = QzJwxtClient();
      try {
        final challenge = await client.prepareLogin(mockBase);
        await expectLater(
          client.loginAndImport(
            challenge,
            username: '2026002',
            password: 'wrong-password',
          ),
          throwsA(isA<JwxtException>()
              .having((e) => e.kind, 'kind', JwxtErrorKind.loginFailed)),
        );
      } finally {
        client.close();
      }
    });

    test('looksLikeSchedule 判定', () {
      final fixture = File('test/fixtures/zf.html').readAsStringSync();
      expect(QzJwxtClient.looksLikeSchedule(fixture), isTrue);
      expect(
        QzJwxtClient.looksLikeSchedule(
            '<html><form><input type="password"></form></html>'),
        isFalse,
      );
    });
  });
}
