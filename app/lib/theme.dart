import 'package:flutter/material.dart';

/// 课程配色（20 色），索引来自 core 的 `colorIndexFor(课程名)`。
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

/// 暖色纸感浅色主题（[seedColor] 为主题色，设置页可更换）。
ThemeData buildLightTheme({Color seedColor = const Color(0xFFB0652A)}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: Brightness.light,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFFAF6F0),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFFAF6F0),
      foregroundColor: Color(0xFF3E2C1C),
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
