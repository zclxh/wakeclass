import 'package:flutter/services.dart';

/// 与 Android 原生桌面小组件通信的桥接。
class WidgetBridge {
  WidgetBridge._();

  static const MethodChannel _channel = MethodChannel('wakeclass/widget');

  /// 通知原生刷新桌面小组件（数据 / 配置变更后调用）。
  static Future<void> refresh() async {
    try {
      await _channel.invokeMethod<void>('refresh');
    } catch (_) {
      // 非 Android 平台 / 测试环境
    }
  }

  /// 请求把指定尺寸的小组件直接固定到桌面（Android 8+ 的系统弹窗）。
  ///
  /// 返回 false 表示系统或桌面不支持一键添加，需要用户手动添加。
  /// 注意：部分品牌桌面（MIUI / HyperOS 等）会返回 true 但不弹窗，
  /// 调用方需要自己做兜底引导。
  static Future<bool> pinWidget(String sizeId) async {
    try {
      final ok = await _channel.invokeMethod<bool>('pinWidget', {
        'size': sizeId,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 回到系统桌面（用于引导用户长按手动添加小组件）。
  static Future<void> openHome() async {
    try {
      await _channel.invokeMethod<void>('openHome');
    } catch (_) {
      // 非 Android 平台 / 测试环境
    }
  }
}
