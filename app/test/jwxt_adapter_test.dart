import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:wakeclass_app/services/jwxt/generic_jwxt_client.dart';
import 'package:wakeclass_app/services/jwxt/jwxt_adapter.dart';
import 'package:wakeclass_app/services/jwxt/rsa_password.dart';
import 'package:wakeclass_app/services/jwxt/zfsoft_client.dart';

void main() {
  group('自动识别系统类型', () {
    final adapters = JwxtAdapterRegistry.create();
    tearDownAll(() {
      for (final adapter in adapters) {
        adapter.close();
      }
    });

    test('正方', () {
      expect(
        JwxtAdapterRegistry.detect(
                'https://jw.example.edu.cn/jwglxt/xtgl/login_slogin.html',
                adapters)
            .id,
        'zf',
      );
    });

    test('强智', () {
      expect(
        JwxtAdapterRegistry.detect(
                'https://jw.example.edu.cn/jsxsd/framework/xsMain.jsp', adapters)
            .id,
        'qz',
      );
    });

    test('统一认证', () {
      expect(
        JwxtAdapterRegistry.detect(
                'https://cas.example.edu.cn/authserver/login?service=x', adapters)
            .id,
        'cas',
      );
    });

    test('识别不了 → 通用', () {
      expect(
        JwxtAdapterRegistry.detect('https://jw.example.edu.cn/login.jsp', adapters)
            .id,
        'generic',
      );
    });

    test('适配器 id 唯一且包含 4 种', () {
      final ids = adapters.map((a) => a.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(ids, containsAll(['zf', 'qz', 'cas', 'generic']));
    });
  });

  group('地址归一化', () {
    test('正方：登录页 / 首页 / 只给域名', () {
      expect(
        ZfsoftClient.normalizeBase(
            'https://jw.example.edu.cn/jwglxt/xtgl/login_slogin.html'),
        'https://jw.example.edu.cn/jwglxt/',
      );
      expect(ZfsoftClient.normalizeBase('https://jw.example.edu.cn/jwglxt'),
          'https://jw.example.edu.cn/jwglxt/');
      expect(ZfsoftClient.normalizeBase('https://jw.example.edu.cn'),
          'https://jw.example.edu.cn/jwglxt/');
    });

    test('通用：保留登录页所在目录', () {
      expect(
        GenericJwxtClient.normalizeBase('https://jw.example.edu.cn/gen/login.jsp'),
        'https://jw.example.edu.cn/gen/',
      );
      expect(
        GenericJwxtClient.normalizeBase('https://jw.example.edu.cn/jw/'),
        'https://jw.example.edu.cn/jw/',
      );
      expect(
        GenericJwxtClient.normalizeBase('https://jw.example.edu.cn'),
        'https://jw.example.edu.cn/',
      );
    });
  });

  group('正方 RSA 加密', () {
    test('加密结果能用私钥还原出原密码（base64，与正方前端一致）', () {
      final pair = _generateKeyPair();
      final publicKey = pair.publicKey as RSAPublicKey;
      final modulus = base64Encode(_bigIntBytes(publicKey.modulus!));
      final exponent = base64Encode(_bigIntBytes(publicKey.publicExponent!));
      final encrypted = rsaEncryptPassword(
        'zfpass!2026',
        modulusBase64: modulus,
        exponentBase64: exponent,
      );
      expect(encrypted, isNotNull);
      // 1024 位密钥 → 128 字节 → base64 172 字符
      expect(encrypted!.length, 172);
      expect(encrypted, matches(RegExp(r'^[A-Za-z0-9+/]+={0,2}$')));
      final decrypted = _decrypt(pair, base64Decode(encrypted));
      expect(utf8.decode(decrypted), 'zfpass!2026');
    });

    test('中文密码也能正确还原（UTF-8 编码与前端一致）', () {
      final pair = _generateKeyPair();
      final publicKey = pair.publicKey as RSAPublicKey;
      final modulus = base64Encode(_bigIntBytes(publicKey.modulus!));
      final exponent = base64Encode(_bigIntBytes(publicKey.publicExponent!));
      final encrypted = rsaEncryptPassword(
        '密码2026',
        modulusBase64: modulus,
        exponentBase64: exponent,
      );
      expect(encrypted, isNotNull);
      expect(utf8.decode(_decrypt(pair, base64Decode(encrypted!))), '密码2026');
    });

    test('公钥非法时返回 null（调用方回退明文）', () {
      expect(
        rsaEncryptPassword('x', modulusBase64: '!!!', exponentBase64: '???'),
        isNull,
      );
    });
  });

  group('正方课表 JSON → 课程', () {
    test('kbList 单条记录', () {
      final warnings = <String>[];
      final course = courseFromKbItem({
        'kcmc': '高等数学A',
        'xm': '张明远',
        'cdmc': '教一101',
        'xqj': '1',
        'jcs': '1-2',
        'zcd': '1-16周',
      }, warnings);
      expect(course, isNotNull);
      expect(course!.name, '高等数学A');
      expect(course.teacher, '张明远');
      expect(course.location, '教一101');
      expect(course.dayOfWeek, 1);
      expect(course.startPeriod, 1);
      expect(course.endPeriod, 2);
      expect(course.weeks.first, 1);
      expect(course.weeks.last, 16);
      expect(warnings, isEmpty);
    });

    test('单双周 / 分段周次', () {
      final course = courseFromKbItem({
        'kcmc': '体育',
        'xqj': '3',
        'jcs': '5',
        'zcd': '1-8周,10-16周',
      }, []);
      expect(course!.startPeriod, 5);
      expect(course.endPeriod, 5);
      expect(course.weeks.contains(9), isFalse);
      expect(course.weeks.contains(10), isTrue);
    });

    test('节次无法识别 → 跳过并告警', () {
      final warnings = <String>[];
      final course = courseFromKbItem({
        'kcmc': '神秘课程',
        'xqj': '2',
        'jcs': '待定',
      }, warnings);
      expect(course, isNull);
      expect(warnings.single, contains('神秘课程'));
    });
  });
}

/// 生成一对 1024 位 RSA 密钥（测试用，速度足够快）。
AsymmetricKeyPair<PublicKey, PrivateKey> _generateKeyPair() {
  final seed = Uint8List.fromList(
    List<int>.generate(32, (_) => Random.secure().nextInt(256)),
  );
  final generator = RSAKeyGenerator()
    ..init(ParametersWithRandom(
      RSAKeyGeneratorParameters(BigInt.from(65537), 1024, 25),
      SecureRandom('Fortuna')..seed(KeyParameter(seed)),
    ));
  return generator.generateKeyPair();
}

Uint8List _bigIntBytes(BigInt value) {
  var hex = value.toRadixString(16);
  if (hex.length.isOdd) hex = '0$hex';
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

Uint8List _decrypt(
  AsymmetricKeyPair<PublicKey, PrivateKey> pair,
  Uint8List cipherText,
) {
  final engine = PKCS1Encoding(RSAEngine())
    ..init(false, PrivateKeyParameter<RSAPrivateKey>(pair.privateKey as RSAPrivateKey));
  return engine.process(cipherText);
}
