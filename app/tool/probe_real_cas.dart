// 真实教务系统直连诊断脚本（凭据经环境变量传入，脚本不写入、不打印密码）。
//
// 用法：
//   $env:REAL_URL='https://<学校统一认证地址>/authserver/login?service=<service>'
//   $env:REAL_USER='学号'; $env:REAL_PASS='密码'
//   dart run tool/probe_real_cas.dart
// 也可以把登录页地址作为第一个参数传入；不带凭据运行时只做登录页结构探测。
import 'dart:io';

import 'package:wakeclass_app/services/jwxt/cas_urp_client.dart';
import 'package:wakeclass_app/services/jwxt/jwxt_exception.dart';
import 'package:wakeclass_core/wakeclass_core.dart';

Future<void> main(List<String> args) async {
  final user = Platform.environment['REAL_USER'];
  final pass = Platform.environment['REAL_PASS'];
  final url = args.isNotEmpty ? args.first : Platform.environment['REAL_URL'];

  if (url == null || url.trim().isEmpty) {
    stdout.writeln('用法: dart run tool/probe_real_cas.dart <登录页完整地址>');
    stdout.writeln('  或设置环境变量 REAL_URL（登录页地址）、REAL_USER / REAL_PASS（可选）。');
    exitCode = 64;
    return;
  }

  final client = CasUrpClient();
  try {
    stdout.writeln('[1] 探测登录页 ...');
    final challenge = await client.prepareLogin(url);
    stdout.writeln('  loginUrl : ${challenge.loginUrl}');
    final exec = challenge.execution;
    stdout.writeln(
        '  execution: ${exec.length > 40 ? exec.substring(0, 40) : exec}'
        '（共 ${exec.length} 字符）');
    stdout.writeln('  salt     : ${challenge.pwdEncryptSalt}');

    if (user == null || user.isEmpty || pass == null || pass.isEmpty) {
      stdout.writeln('未提供凭据（REAL_USER / REAL_PASS），只做结构探测。');
      return;
    }

    stdout.writeln('[2] 登录并定位课表 ...');
    try {
      final result = await client.loginAndImport(
        challenge,
        username: user,
        password: pass,
        onLanding: (u) {
          final hasJsid = RegExp(r';jsessionid=', caseSensitive: false)
              .hasMatch(u);
          stdout.writeln('  落地页: jsessionid=${hasJsid ? '有' : '无'} '
              '${Uri.parse(u).replace(path: Uri.parse(u).path.split(';').first).toString()}');
        },
        onProbe: (u, status, looks) => stdout.writeln(
            '  探测: status=$status looksSchedule=$looks $u'),
        onHtml: (u, html) {
          // 落盘供本地诊断（含框架结构，不打印到控制台）。
          final dir = Directory('${Platform.environment['TEMP'] ?? '.'}/cas-probe-real');
          dir.createSync(recursive: true);
          final name = Uri.parse(u).path.replaceAll(RegExp(r'[^\w.\-]'), '_');
          File('${dir.path}/$name.html').writeAsStringSync(html);
        },
        onRaw: (u, bytes) {
          final dir = Directory('${Platform.environment['TEMP'] ?? '.'}/cas-probe-real');
          dir.createSync(recursive: true);
          final name = Uri.parse(u).path.replaceAll(RegExp(r'[^\w.\-]'), '_');
          File('${dir.path}/$name.bin').writeAsBytesSync(bytes);
        },
      );
      stdout.writeln('[3] 成功！共解析出 ${result.courses.length} 门课');
      for (final w in result.warnings) {
        stdout.writeln('  提示: $w');
      }
      for (final c in result.courses) {
        stdout.writeln('    ${c.dayText} ${c.periodText} ${c.name}'
            ' | ${c.teacher} | ${c.location} | ${formatWeeks(c.weeks)}');
      }
    } on JwxtException catch (e) {
      stdout.writeln('[3] 失败: ${e.kind.name} - ${e.message}');
      if (e.hint.isNotEmpty) stdout.writeln('    建议: ${e.hint}');
    }
  } on JwxtException catch (e) {
    stdout.writeln('[1] 探测登录页失败: ${e.kind.name} - ${e.message}');
    if (e.hint.isNotEmpty) stdout.writeln('    建议: ${e.hint}');
  } finally {
    client.close();
  }
}
