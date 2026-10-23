// 真机探测：统一认证（CAS）→ 正方 SSO → 课表。
//
// 账号密码只从环境变量读，不落盘、不打印：
//   $env:JWXT_USER='...'; $env:JWXT_PASS='...'
//   dart run tool/probe_cas_zf.dart "<CAS 登录地址>"
//
// 输出只包含各跳状态码、学期与课程条数（不打印课表内容）。
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:wakeclass_app/services/jwxt/cas_zf_client.dart';
import 'package:wakeclass_app/services/jwxt/jwxt_exception.dart';

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : (Platform.environment['CAS_URL'] ?? '');
  final user = Platform.environment['JWXT_USER'] ?? '';
  final pass = Platform.environment['JWXT_PASS'] ?? '';
  if (url.isEmpty || user.isEmpty || pass.isEmpty) {
    print('用法：设置 JWXT_USER / JWXT_PASS 环境变量，并传入 CAS 登录地址');
    exit(2);
  }

  final client = CasZfClient();
  try {
    print('1) 打开登录页 …');
    final challenge = await client.prepareLogin(url);
    print('   表单提交地址 host = ${Uri.parse(challenge.loginAction).host}');
    print('   隐藏字段 = ${challenge.hiddenFields.keys.join(",")}');
    print('   service = ${challenge.serviceUrl}');
    print('   字段名 = ${challenge.userField} / ${challenge.passwordField}');

    print('2) 提交账号密码 → 跟随回跳 …');
    final result = await client.loginAndImport(
      challenge,
      username: user,
      password: pass,
    );
    print('   系统 = ${result.systemName}');
    print('   学期 = ${result.semesterLabel}');
    print('   课程数 = ${result.courses.length}');
    if (result.courses.isNotEmpty) {
      final c = result.courses.first;
      print('   首条 = ${c.name} / ${c.dayText} / ${c.periodText}');
    }
    for (final w in result.warnings.take(5)) {
      print('   提示 = $w');
    }
    print('OK');
  } on JwxtException catch (e) {
    print('失败：${e.kind.name}');
    print('   ${e.message}');
    if (e.hint.isNotEmpty) print('   建议：${e.hint}');
    exit(1);
  } catch (e) {
    print('异常：$e');
    exit(1);
  } finally {
    client.close();
  }
}
