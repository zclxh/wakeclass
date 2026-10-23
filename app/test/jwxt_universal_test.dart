import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wakeclass_app/services/jwxt/generic_jwxt_client.dart';
import 'package:wakeclass_app/services/jwxt/jwxt_exception.dart';
import 'package:wakeclass_app/services/jwxt/zfsoft_client.dart';

/// 端到端：本地模拟「正方」与「通用」两套教务系统（test/mock_jwxt_universal.cjs）。
void main() {
  const base = 'http://127.0.0.1:8791';
  var serverUp = false;

  setUpAll(() async {
    try {
      final socket = await Socket.connect('127.0.0.1', 8791,
          timeout: const Duration(milliseconds: 800));
      socket.destroy();
      serverUp = true;
    } catch (_) {
      serverUp = false;
    }
  });

  group('正方教务（jwglxt）', () {
    test('登录 → kbList JSON → 课程', () async {
      if (!serverUp) return;
      final client = ZfsoftClient();
      addTearDown(client.close);

      final challenge = await client.prepareLogin(
          '$base/jwglxt/xtgl/login_slogin.html');
      expect(challenge.baseUrl, '$base/jwglxt/');
      expect(challenge.modulus, isNotEmpty);
      expect(challenge.exponent, isNotEmpty);
      expect(challenge.csrfToken, isNotEmpty);
      // 隐藏参数写在 form 外面也要收进来（真实正方就是这样）
      expect(challenge.hiddenFields['mmsfjm'], '1');
      expect(challenge.hiddenFields['xxdm'], '14582');
      expect(challenge.hiddenFields['language'], 'zh_CN');

      final result = await client.loginAndImport(
        challenge,
        username: '2026005',
        password: 'zfpass',
      );
      expect(result.systemName, '正方教务系统');
      expect(result.courses.length, 2);

      final math = result.courses.firstWhere((c) => c.name == '高等数学A');
      expect(math.dayOfWeek, 1);
      expect(math.startPeriod, 1);
      expect(math.endPeriod, 2);
      expect(math.location, '教一101');
      expect(math.teacher, '张明远');
      expect(math.weeks.first, 1);
      expect(math.weeks.last, 16);

      final english = result.courses.firstWhere((c) => c.name == '大学英语');
      expect(english.dayOfWeek, 3);
      expect(english.weeks.contains(9), isFalse);
    });

    test('密码错误 → 登录失败（且提示可读）', () async {
      if (!serverUp) return;
      final client = ZfsoftClient();
      addTearDown(client.close);
      final challenge = await client.prepareLogin(
          '$base/jwglxt/xtgl/login_slogin.html');
      await expectLater(
        client.loginAndImport(
          challenge,
          username: '2026005',
          password: 'wrong-pass',
        ),
        throwsA(isA<JwxtException>()
            .having((e) => e.kind, 'kind', JwxtErrorKind.loginFailed)),
      );
    });
  });

  group('通用教务系统（表单 + 表格）', () {
    test('自动识别表单 → 跟随 302 → 找课表链接 → 解析表格', () async {
      if (!serverUp) return;
      final client = GenericJwxtClient();
      addTearDown(client.close);

      final challenge = await client.prepareLogin('$base/gen/login.jsp');
      expect(challenge.baseUrl, '$base/gen/');
      expect(challenge.userField, 'xh');
      expect(challenge.passwordField, 'pwd');
      expect(challenge.captchaField, isNull);
      expect(challenge.hiddenFields['token'], 'abc123');

      final result = await client.loginAndImport(
        challenge,
        username: '2026004',
        password: 'genpass',
      );
      expect(result.courses.length, 2);
      final math = result.courses.firstWhere((c) => c.name == '高等数学A');
      expect(math.dayOfWeek, 1);
      expect(math.startPeriod, 1);
      expect(math.endPeriod, 2);
      expect(math.location, '教一101');
      final english = result.courses.firstWhere((c) => c.name == '大学英语');
      expect(english.dayOfWeek, 3);
      expect(english.startPeriod, 3);
      expect(english.endPeriod, 4);
    });

    test('密码错误 → 登录失败', () async {
      if (!serverUp) return;
      final client = GenericJwxtClient();
      addTearDown(client.close);
      final challenge = await client.prepareLogin('$base/gen/login.jsp');
      await expectLater(
        client.loginAndImport(
          challenge,
          username: '2026004',
          password: 'bad',
        ),
        throwsA(isA<JwxtException>()
            .having((e) => e.kind, 'kind', JwxtErrorKind.loginFailed)),
      );
    });
  });

  group('适配器层', () {
    test('按 URL 自动选到正方 / 通用适配器', () async {
      if (!serverUp) return;
      final client = GenericJwxtClient();
      addTearDown(client.close);
      // 只是验证 normalizeBase 对真实地址的处理
      expect(GenericJwxtClient.normalizeBase('$base/gen/login.jsp'),
          '$base/gen/');
    });
  });
}
