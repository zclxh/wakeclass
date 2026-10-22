/// 课前提醒服务：按平台导出真实实现或 Web 占位实现。
///
/// Web 构建时 `dart.library.js_interop` 为真，选择占位实现，
/// 避免编译 flutter_local_notifications（无 Web 支持）。
library;

export 'course_reminder_service.dart'
    if (dart.library.js_interop) 'course_reminder_service_stub.dart';
