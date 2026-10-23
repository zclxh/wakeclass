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

/// 统一圆角/高度，保证全 App 观感一致。
const double kCardRadius = 18;
const double kFieldRadius = 14;
const double kButtonHeight = 46;

/// 课表里课程卡片的外观（设置页可切换）。
enum CourseCardStyle {
  /// 柔和：淡色底 + 顶部课程色条 + 深色文字（默认）。
  soft('柔和', '淡色卡片 + 课程色条，字更清楚'),

  /// 鲜艳：整块课程色 + 高对比文字，一眼分课。
  vivid('鲜艳', '整块课程色，颜色最醒目');

  const CourseCardStyle(this.label, this.description);

  final String label;
  final String description;

  static CourseCardStyle byName(String? name) => values.firstWhere(
        (style) => style.name == name,
        orElse: () => CourseCardStyle.soft,
      );
}

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
  final hairline = scheme.onSurface.withValues(alpha: 0.07);
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: backgroundColor,
    canvasColor: backgroundColor,
    appBarTheme: AppBarTheme(
      backgroundColor: backgroundColor,
      surfaceTintColor: Colors.transparent,
      foregroundColor: onBackground,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCardRadius),
        side: BorderSide(color: hairline),
      ),
    ),
    dividerTheme: DividerThemeData(color: hairline, thickness: 0.8, space: 0.8),
  );
  return _applyControls(base, hairline: hairline, fieldFill: Colors.white);
}

/// 深色主题（[seedColor] 与浅色主题保持一致）。
ThemeData buildDarkTheme({Color seedColor = const Color(0xFFB0652A)}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: Brightness.dark,
  );
  final hairline = scheme.onSurface.withValues(alpha: 0.10);
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCardRadius),
        side: BorderSide(color: hairline),
      ),
    ),
    dividerTheme: DividerThemeData(color: hairline, thickness: 0.8, space: 0.8),
  );
  return _applyControls(
    base,
    hairline: hairline,
    fieldFill: scheme.surfaceContainerHigh,
  );
}

/// 按钮 / 输入框 / 提示条统一风格。
///
/// 注意：按钮的 `textStyle` 必须从主题的 labelLarge 派生，
/// 直接写 `TextStyle(fontSize: ...)` 会丢掉字体族（中文会变成方块）。
ThemeData _applyControls(
  ThemeData base, {
  required Color hairline,
  required Color fieldFill,
}) {
  final scheme = base.colorScheme;
  final label = base.textTheme.labelLarge ?? const TextStyle();
  final body = base.textTheme.bodyMedium ?? const TextStyle();
  return base.copyWith(
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, kButtonHeight),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        textStyle: label.copyWith(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, kButtonHeight),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outlineVariant),
        textStyle: label.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: label.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: fieldFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: body.copyWith(color: scheme.onSurfaceVariant),
      hintStyle: body.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kFieldRadius),
        borderSide: BorderSide(color: hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kFieldRadius),
        borderSide: BorderSide(color: hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kFieldRadius),
        borderSide: BorderSide(color: scheme.primary, width: 1.4),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
    ),
  );
}
