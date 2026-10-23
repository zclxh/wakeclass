import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// 正方教务（jwglxt）登录用的 RSA 加密。
///
/// 正方的登录页会请求 `xtgl/login_getPublicKey.html`，拿到 base64 的
/// `modulus` / `exponent`，然后在前端执行（login.js）：
///
/// ```js
/// var rsaKey = new RSAKey();
/// rsaKey.setPublic(b64tohex(modulus), b64tohex(exponent));
/// var enPassword = hex2b64(rsaKey.encrypt($("#mm").val()));
/// $("#mm").val(enPassword);
/// ```
///
/// 也就是说提交的 `mm` 是 **RSA(PKCS#1 v1.5) 结果的 base64**，不是十六进制。
/// 这里用 pointycastle 在端上做同样的计算。
///
/// 只用于「把用户自己的密码按学校前端同样的规则加密后提交」，
/// 不涉及任何破解或绕过。
String? rsaEncryptPassword(
  String password, {
  required String modulusBase64,
  required String exponentBase64,
}) {
  try {
    final modulus = _bytesToBigInt(base64.decode(modulusBase64));
    final exponent = _bytesToBigInt(base64.decode(exponentBase64));
    if (modulus.bitLength < 256 || exponent <= BigInt.zero) return null;
    final engine = PKCS1Encoding(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(RSAPublicKey(modulus, exponent)));
    final input = Uint8List.fromList(utf8.encode(password));
    final encrypted = engine.process(input);
    return base64.encode(encrypted);
  } catch (_) {
    return null;
  }
}

/// 兼容旧名（返回 base64）。
@Deprecated('用 rsaEncryptPassword（返回 base64，与正方前端一致）')
String? rsaEncryptPasswordHex(
  String password, {
  required String modulusBase64,
  required String exponentBase64,
}) =>
    rsaEncryptPassword(
      password,
      modulusBase64: modulusBase64,
      exponentBase64: exponentBase64,
    );

BigInt _bytesToBigInt(List<int> bytes) {
  var result = BigInt.zero;
  for (final byte in bytes) {
    result = (result << 8) | BigInt.from(byte & 0xff);
  }
  return result;
}

/// 把十六进制串转回字节（测试用）。
Uint8List hexToBytes(String hex) {
  final normalized = hex.length.isOdd ? '0$hex' : hex;
  final out = Uint8List(normalized.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(normalized.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
