import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 预设主题色。
class ThemePreset {
  const ThemePreset(this.name, this.seed);

  final String name;
  final Color seed;
}

/// 预设色板（选中后全局换色，深浅色模式同步生效）。
const themePresets = <ThemePreset>[
  ThemePreset('暖棕', Color(0xFFB0652A)),
  ThemePreset('海蓝', Color(0xFF1565C0)),
  ThemePreset('青绿', Color(0xFF00897B)),
  ThemePreset('森林绿', Color(0xFF43A047)),
  ThemePreset('紫罗兰', Color(0xFF7B1FA2)),
  ThemePreset('绯红', Color(0xFFC62828)),
  ThemePreset('玫瑰粉', Color(0xFFC2185B)),
  ThemePreset('琥珀橙', Color(0xFFEF6C00)),
  ThemePreset('靛蓝', Color(0xFF3949AB)),
  ThemePreset('石墨', Color(0xFF546E7A)),
];

/// 页面背景色预设（都是浅色，保证深色文字可读）。
class BackgroundPreset {
  const BackgroundPreset(this.name, this.color);

  final String name;
  final Color color;
}

/// 背景色预设（第一个是默认的纸感米白）。
const backgroundPresets = <BackgroundPreset>[
  BackgroundPreset('纸感米白', Color(0xFFFAF6F0)),
  BackgroundPreset('纯白', Color(0xFFFDFDFD)),
  BackgroundPreset('暖沙', Color(0xFFF6EEE1)),
  BackgroundPreset('浅灰', Color(0xFFF1F3F5)),
  BackgroundPreset('薄荷', Color(0xFFEAF5EF)),
  BackgroundPreset('天蓝', Color(0xFFEAF1FB)),
  BackgroundPreset('粉樱', Color(0xFFFBEEF3)),
  BackgroundPreset('淡紫', Color(0xFFF2EEFB)),
  BackgroundPreset('柠檬', Color(0xFFFAF6DE)),
  BackgroundPreset('青瓷', Color(0xFFE7F3F5)),
  BackgroundPreset('咖啡', Color(0xFFF2ECE6)),
  BackgroundPreset('浅藕', Color(0xFFF5EDF0)),
];

/// 主题色 + 背景色状态：持久化到 shared_preferences，变更即全局重建主题。
class ThemeModel extends ChangeNotifier {
  static const _colorKey = 'wakeclass_theme_color_index';
  static const _backgroundKey = 'wakeclass_background_index';

  int _colorIndex = 0;
  int _backgroundIndex = 0;

  int get colorIndex => _colorIndex;
  ThemePreset get preset => themePresets[_colorIndex];
  Color get seedColor => preset.seed;

  int get backgroundIndex => _backgroundIndex;
  BackgroundPreset get backgroundPreset =>
      backgroundPresets[_backgroundIndex.clamp(0, backgroundPresets.length - 1)];
  Color get backgroundColor => backgroundPreset.color;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_colorKey);
      if (saved != null && saved >= 0 && saved < themePresets.length) {
        _colorIndex = saved;
      }
      final background = prefs.getInt(_backgroundKey);
      if (background != null &&
          background >= 0 &&
          background < backgroundPresets.length) {
        _backgroundIndex = background;
      }
    } catch (_) {
      // 读取失败则用默认色
    }
    notifyListeners();
  }

  Future<void> setColorIndex(int index) async {
    if (index < 0 || index >= themePresets.length) return;
    if (index == _colorIndex) return;
    _colorIndex = index;
    notifyListeners();
    await _persist(_colorKey, index);
  }

  Future<void> setBackgroundIndex(int index) async {
    if (index < 0 || index >= backgroundPresets.length) return;
    if (index == _backgroundIndex) return;
    _backgroundIndex = index;
    notifyListeners();
    await _persist(_backgroundKey, index);
  }

  Future<void> _persist(String key, int value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(key, value);
    } catch (_) {
      // 保存失败不影响本次会话
    }
  }
}
