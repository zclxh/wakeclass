# wakeclass_app

「醒课」Flutter 应用主体（Android / Web）。完整介绍、使用说明与架构说明见仓库根目录
[README](../README.md)。

## 常用命令

```bash
flutter pub get
flutter run                  # 运行
flutter test                 # 测试（端到端集成测试需先启动本地模拟教务系统，见根 README）
flutter build apk --release  # 打包 APK
flutter build web --release  # 打包 Web
```

## 目录提示

- `lib/pages/` 页面；`lib/widgets/` 周课表网格
- `lib/services/` 教务直连、OCR、导入、通知、存储、小组件桥接
- `lib/model/` 状态与持久化
- `android/` 原生壳（3 个 `AppWidgetProvider` + 每分钟刷新 + pin 请求）
- `test/` 测试与两套本地模拟教务系统
- `tool/probe_real_cas.dart` 真实教务系统诊断脚本（凭据走环境变量）
