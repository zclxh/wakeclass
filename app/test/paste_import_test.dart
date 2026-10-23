import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wakeclass_app/pages/paste_schedule_page.dart';

void main() {
  const html = '''
<html><body>
<table>
  <tr><td>节次</td><td>星期一</td><td>星期二</td><td>星期三</td></tr>
  <tr><td>第1-2节</td>
      <td>高等数学A<br>张明远<br>1-16周<br>教一101</td>
      <td>&nbsp;</td><td>&nbsp;</td></tr>
  <tr><td>第3-4节</td>
      <td>&nbsp;</td><td>&nbsp;</td>
      <td>大学英语<br>李华<br>1-8周,10-16周<br>外语楼203</td></tr>
</table>
</body></html>
''';

  const kbJson = '{"kbList":['
      '{"kcmc":"数据结构","xm":"王强","cdmc":"信息楼302",'
      '"xqj":"2","jcs":"5-6","zcd":"1-12周"}'
      ']}';

  testWidgets('粘贴 HTML 表格 → 解析 → 校对页', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: PasteSchedulePage()));
    await tester.enterText(find.byType(TextField), html);
    await tester.tap(find.text('解析'));
    await tester.pumpAndSettle();

    expect(find.text('高等数学A'), findsWidgets);
    expect(find.text('大学英语'), findsWidgets);
  });

  testWidgets('粘贴正方接口 JSON → 解析 → 校对页', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: PasteSchedulePage()));
    await tester.enterText(find.byType(TextField), kbJson);
    await tester.tap(find.text('解析'));
    await tester.pumpAndSettle();

    expect(find.text('数据结构'), findsWidgets);
    expect(find.textContaining('识别出'), findsWidgets);
  });

  testWidgets('内容无法解析时给出提示', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: PasteSchedulePage()));
    await tester.enterText(find.byType(TextField), 'hello world');
    await tester.tap(find.text('解析'));
    await tester.pumpAndSettle();

    expect(find.textContaining('没有解析出课程'), findsOneWidget);
  });
}
