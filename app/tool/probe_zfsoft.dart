// 正方教务系统连通性探针（真实学校）。
//
// 用法（在 app/ 目录）：
//   dart run tool/probe_zfsoft.dart                     # 默认探测示例学校地址
//   dart run tool/probe_zfsoft.dart <登录页地址> [学号] [密码]
//
// 不带账号时只用假账号验证「登录页解析 + RSA 加密 + 提交」链路是否打通，
// 不会真的登录成功；带账号时会尝试真实登录并打印课程数量（不会写入任何存储）。
//
// ignore_for_file: avoid_print

import 'package:http/http.dart' as http;
import 'package:wakeclass_app/services/jwxt/jwxt_exception.dart';
import 'package:wakeclass_app/services/jwxt/zfsoft_client.dart';

Future<void> main(List<String> args) async {
  final loginUrl = args.isNotEmpty
      ? args[0]
      : 'https://jwxt.ztwzy.cn/jwglxt/xtgl/login_slogin.html';
  final username = args.length > 1 ? args[1] : 'probe-not-exist';
  final password = args.length > 2 ? args[2] : 'probe-wrong-password';

  // 先用裸 HTTP 看一眼登录页返回什么（状态码 / 跳转 / 长度 / 是否有密码框）。
  try {
    final req = http.Request('GET', Uri.parse(loginUrl))..followRedirects = false;
    req.headers['User-Agent'] = 'Mozilla/5.0 (WakeClass) AppleWebKit/537.36';
    final res = await http.Client().send(req);
    final body = await res.stream.bytesToString();
    print('== 裸请求：status=${res.statusCode} length=${body.length}');
    if (res.headers['location'] != null) {
      print('   location=${res.headers['location']}');
    }
    print('   set-cookie=${res.headers['set-cookie']}');
    print('   含密码框=${RegExp('<input[^>]*type\\s*=\\s*["\']?password').hasMatch(body)}');
  } catch (e) {
    print('== 裸请求失败：$e');
  }

  final client = ZfsoftClient();
  try {
    print('== 探测登录页：$loginUrl');
    final challenge = await client.prepareLogin(loginUrl);
    print('   baseUrl       = ${challenge.baseUrl}');
    print('   loginAction   = ${challenge.loginAction}');
    print('   csrfToken     = ${_mask(challenge.csrfToken)}');
    print('   公钥 modulus  = ${challenge.modulus.length} 字符');
    print('   公钥 exponent = ${challenge.exponent}');
    print('   验证码字段    = ${challenge.captchaField ?? '（无）'}');
    print('   页面学期      = ${challenge.detectedSemester ?? '（未识别）'}');
    print('   隐藏字段      = ${challenge.hiddenFields.keys.toList()}');

    print('== 提交登录（账号 $username）');
    final result = await client.loginAndImport(
      challenge,
      username: username,
      password: password,
    );
    print('   登录成功：${result.systemName}');
    print('   学期：${result.semesterLabel}');
    print('   课程数：${result.courses.length}');
    for (final course in result.courses.take(10)) {
      print('   - ${course.dayText} ${course.periodText} ${course.name}'
          '${course.location.isEmpty ? '' : ' @${course.location}'}');
    }
    if (result.warnings.isNotEmpty) {
      print('   提示：${result.warnings.take(6).join(' / ')}');
    }
  } on JwxtException catch (e) {
    print('   失败：kind=${e.kind} message=${e.message}');
    if (e.hint.isNotEmpty) print('   提示：${e.hint}');
  } catch (e) {
    print('   异常：$e');
  } finally {
    client.close();
  }
}

String _mask(String value) {
  if (value.isEmpty) return '（空）';
  if (value.length <= 10) return value;
  return '${value.substring(0, 8)}…(${value.length})';
}
