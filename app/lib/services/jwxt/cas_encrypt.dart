import 'dart:convert';
import 'dart:math';

import 'package:pointycastle/export.dart';

/// 金智 CAS 统一认证的密码加密（自 authserver 的 encrypt.js 移植）。
///
/// 算法：
/// 1. 明文 = randomString(64) + password（64 字节随机前缀用于吸收未知 IV）；
/// 2. 密钥 = `pwdEncryptSalt`（登录页隐藏字段，16 字节）的 UTF-8 字节；
/// 3. IV = randomString(16) 的 UTF-8 字节；
/// 4. AES-128/256-CBC + PKCS7，输出 Base64(ciphertext)（不含 IV）。
///
/// 服务端解密时忽略首块（IV 未知导致的损坏被随机前缀吸收），
/// 从第 65 字节起读取密码。
String encryptCasPassword(
  String password,
  String pwdEncryptSalt, {
  String? iv,
  String? prefix,
}) {
  final random = Random();
  const chars = 'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678';

  String randomString(int len) =>
      String.fromCharCodes(List.generate(len, (_) => chars.codeUnitAt(random.nextInt(chars.length))));

  final plain = (prefix ?? randomString(64)) + password;
  final ivBytes = utf8.encode(iv ?? randomString(16));
  final key = utf8.encode(pwdEncryptSalt);

  final cipher = PaddedBlockCipherImpl(
    PKCS7Padding(),
    CBCBlockCipher(AESEngine()),
  );
  cipher.init(
    true,
    PaddedBlockCipherParameters(
      ParametersWithIV<KeyParameter>(KeyParameter(key), ivBytes),
      null,
    ),
  );
  final encrypted = cipher.process(utf8.encode(plain));
  return base64.encode(encrypted);
}
