import 'package:flutter/material.dart';

/// 课程配色（20 色），索引来自 core 的 `colorIndexFor(课程名)`。
///
/// **顺序必须与 Android 端 `CourseWidgetProvider.COURSE_COLORS` 保持一致**，
/// 桌面小组件按 `color_index` 取色画课程色条。
const List<Color> coursePalette = [
  Color(0xFFEF5350), // 红
  Color(0xFFEC407A), // 粉
  Color(0xFFAB47BC), // 紫
  Color(0xFF7E57C2), // 深紫
  Color(0xFF5C6BC0), // 靛蓝
  Color(0xFF42A5F5), // 蓝
  Color(0xFF29B6F6), // 浅蓝
  Color(0xFF26C6DA), // 青
  Color(0xFF26A69A), // 青绿
  Color(0xFF66BB6A), // 绿
  Color(0xFF9CCC65), // 浅绿
  Color(0xFFD4E157), // 黄绿
  Color(0xFFFFCA28), // 黄
  Color(0xFFFFA726), // 橙
  Color(0xFFFF7043), // 深橙
  Color(0xFF8D6E63), // 棕
  Color(0xFF78909C), // 蓝灰
  Color(0xFF90A4AE), // 灰蓝
  Color(0xFFB0BEC5), // 浅灰蓝
  Color(0xFFA1887F), // 暖棕
];

/// 取课程配色（越界时取模）。
Color courseColor(int colorIndex) =>
    coursePalette[colorIndex.abs() % coursePalette.length];

/// 课程配色名（用于取色面板的无障碍标签）。
const List<String> courseColorNames = [
  '红', '粉', '紫', '深紫', '靛蓝', '蓝', '浅蓝', '青', '青绿', '绿',
  '浅绿', '黄绿', '黄', '橙', '深橙', '棕', '蓝灰', '灰蓝', '浅灰蓝', '暖棕',
];

/// 暖色纸感浅色主题。
///
/// [seedColor] 为主题色（设置页可更换），[backgroundColor] 为页面背景色
/// （设置页可单独更换，默认纸感米白）。
ThemeData buildLightTheme({
  Color seedColor = const Color(0xFFB0652A),
  Color backgroundColor = const Color(0xFFFAF6F0),
}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: Brightness.light,
  );
  final onBackground = backgroundColor.computeLuminance() > 0.5
      ? const Color(0xFF3E2C1C)
      : Colors.white;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: backgroundColor,
    canvasColor: backgroundColor,
    appBarTheme: AppBarTheme(
      backgroundColor: backgroundColor,
      foregroundColor: onBackground,
      elevation: 0,
      centerTitle: true,
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 1,
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
    ),
  );
}

/// 深色主题（[seedColor] 与浅色主题保持一致）。
ThemeData buildDarkTheme({Color seedColor = const Color(0xFFB0652A)}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: Brightness.dark,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      centerTitle: true,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerHighest,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
    ),
  );
}
