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

/// 主题色状态：持久化到 shared_preferences，变更即全局重建主题。
class ThemeModel extends ChangeNotifier {
  static const _key = 'wakeclass_theme_color_index';

  int _colorIndex = 0;

  int get colorIndex => _colorIndex;
  ThemePreset get preset => themePresets[_colorIndex];
  Color get seedColor => preset.seed;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_key);
      if (saved != null && saved >= 0 && saved < themePresets.length) {
        _colorIndex = saved;
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
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key, index);
    } catch (_) {
      // 保存失败不影响本次会话
    }
  }
}
