import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeclass_core/wakeclass_core.dart';

import '../services/widget/widget_bridge.dart';

/// 作息（上课时间）状态：持久化到 shared_preferences。
///
/// 原生桌面小组件直接读取同一个键（`flutter.wakeclass_periods_v1`）来计算
/// 课程时间与倒计时，所以保存后要通知小组件刷新。
class PeriodModel extends ChangeNotifier {
  /// shared_preferences 键（原生端读取 `flutter.` 前缀的同一个键）。
  static const prefsKey = 'wakeclass_periods_v1';

  PeriodSettings _settings = PeriodSettings.defaults();
  bool _loaded = false;

  PeriodSettings get settings => _settings;
  bool get loaded => _loaded;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _settings = PeriodSettings.decode(prefs.getString(prefsKey));
    } catch (_) {
      _settings = PeriodSettings.defaults();
    }
    _loaded = true;
    notifyListeners();
  }

  /// 保存新的作息（立即生效，并刷新桌面小组件）。
  Future<void> update(PeriodSettings next) async {
    _settings = next;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, next.encode());
    } catch (_) {
      // 保存失败不影响本次会话
    }
    // 后台刷新小组件（不阻塞设置页交互）
    WidgetBridge.refresh();
  }

  /// 恢复默认作息（08:00 起，每节 45 分钟）。
  Future<void> resetToDefaults() async {
    final next = PeriodSettings.defaults();
    if (next == _settings) return;
    await update(next);
  }

  /// 第 [period] 节时间文本，如 `08:00-08:45`。
  String timeText(int period) => _settings.timeText(period);
}
