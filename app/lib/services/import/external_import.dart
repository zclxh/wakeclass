import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 把 App 外面的课表内容送进 App 的通道（Android 原生实现）。
///
/// 解决「教务系统只能校园网访问、学校又没有 VPN」时的取数问题：
/// - 微信 / QQ 里点「用其他应用打开」课表 HTML / JSON / TXT → 直接进醒课
/// - 系统「分享」到醒课 → 同上
/// - App 内「选择文件」→ 系统文件选择器（SAF）
/// - 把一段文本分享出去（用来把「电脑端书签脚本」发到电脑）
///
/// 非 Android 平台（含单元测试）没有原生实现，所有方法安全返回 null / false。
class ExternalImport {
  ExternalImport._();

  static const MethodChannel _channel = MethodChannel('wakeclass/import');

  static final StreamController<String> _incoming =
      StreamController<String>.broadcast();

  static bool _hooked = false;

  /// 运行中从外部送进来的内容（冷启动的走 [takePending]）。
  static Stream<String> get incoming {
    ensureHooked();
    return _incoming.stream;
  }

  /// 是否可能拿到外部内容（只有 Android 原生侧实现了）。
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 注册通道回调（可重复调用，只注册一次）。
  static void ensureHooked() {
    if (_hooked) return;
    _hooked = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'incoming') return null;
      final text = call.arguments;
      if (text is String && text.trim().isNotEmpty) _incoming.add(text);
      return true;
    });
  }

  /// 取走冷启动时通过「打开 / 分享」带进来的内容（只能取一次）。
  static Future<String?> takePending() async {
    ensureHooked();
    try {
      final text = await _channel.invokeMethod<String>('takePending');
      return (text == null || text.trim().isEmpty) ? null : text;
    } catch (_) {
      return null;
    }
  }

  /// 打开系统文件选择器，返回文件文本；取消或失败返回 null。
  static Future<String?> pickFile() async {
    ensureHooked();
    try {
      final text = await _channel.invokeMethod<String>('pickFile');
      return (text == null || text.trim().isEmpty) ? null : text;
    } catch (_) {
      return null;
    }
  }

  /// 分享一段文本（微信「文件传输助手」→ 在电脑上打开复制）。
  static Future<bool> shareText(String text) async {
    ensureHooked();
    try {
      final ok = await _channel.invokeMethod<bool>('shareText', {'text': text});
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}
