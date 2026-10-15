import 'package:flutter/material.dart';

/// Every colour used in Finora. Widgets must read from here (or from
/// `Theme.of(context)` / `context.palette`) and never inline a hex value.
class AppColors {
  const AppColors._();

  // --- User Palette -----------------------------------------------------
  // #0A1931, #1A3D63, #4A7FA7, #B3CFE5, #F6FAFD
  static const Color brand = Color(0xFF1A3D63);
  static const Color brandDark = Color(0xFF0A1931);
  static const Color brandLight = Color(0xFF4A7FA7);
  static const Color brandSurface = Color(0xFFE5F0F8);
  static const Color brandSurfaceDark = Color(0xFF142942);

  static const Color accent = Color(0xFF4A7FA7);
  static const Color iceBlue = Color(0xFFB3CFE5);

  // --- Semantic, light theme -------------------------------------------
  static const Color income = Color(0xFF22C55E);
  static const Color expense = Color(0xFFFF5252);
  static const Color transfer = Color(0xFF4A7FA7);
  static const Color warning = Color(0xFFB54708);
  static const Color success = Color(0xFF067647);
  static const Color danger = Color(0xFFB42318);
  static const Color info = Color(0xFF1A3D63);

  // --- Semantic, dark theme --------------------------------------------
  static const Color incomeDark = Color(0xFF4ADE80);
  static const Color expenseDark = Color(0xFFFF8585);
  static const Color transferDark = Color(0xFFB3CFE5);
  static const Color warningDark = Color(0xFFFDB022);
  static const Color successDark = Color(0xFF47CD89);
  static const Color dangerDark = Color(0xFFF97066);
  static const Color infoDark = Color(0xFFB3CFE5);

  // --- Neutrals, light -------------------------------------------------
  static const Color background = Color(0xFFF6FAFD);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFEBF3F9);
  static const Color outline = Color(0xFFD4E3EF);
  static const Color outlineStrong = Color(0xFFB3CFE5);
  static const Color textPrimary = Color(0xFF0A1931);
  static const Color textSecondary = Color(0xFF38587A);
  static const Color textTertiary = Color(0xFF7A9BBA);

  // --- Neutrals, dark --------------------------------------------------
  static const Color backgroundDark = Color(0xFF0A1931);
  static const Color surfaceDark = Color(0xFF12243E);
  static const Color surfaceAltDark = Color(0xFF1A3252);
  static const Color outlineDark = Color(0xFF264870);
  static const Color outlineStrongDark = Color(0xFF3A6391);
  static const Color textPrimaryDark = Color(0xFFF6FAFD);
  static const Color textSecondaryDark = Color(0xFFB3CFE5);
  static const Color textTertiaryDark = Color(0xFF7A9BBA);

  /// Qualitative palette for charts and for user-chosen category colours.
  /// Ordered so that neighbouring series stay distinguishable, and chosen to
  /// hold contrast against both light and dark surfaces.
  static const List<Color> categoryPalette = [
    Color(0xFF0E7C66), // teal
    Color(0xFF2E6BE6), // blue
    Color(0xFFE6812E), // orange
    Color(0xFF9B51E0), // purple
    Color(0xFFD64550), // red
    Color(0xFF12A594), // cyan
    Color(0xFFB88A00), // gold
    Color(0xFF4F6FA8), // steel
    Color(0xFFCE5A8F), // pink
    Color(0xFF5C8A3A), // olive
    Color(0xFF7A5CE0), // indigo
    Color(0xFF8A6244), // brown
  ];

  /// Stable colour for a category or account that has no explicit colour:
  /// derived from its id so it never changes between sessions.
  static Color deterministic(String seed) {
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return categoryPalette[hash % categoryPalette.length];
  }

  /// Parses `#RRGGBB` / `RRGGBB` / `#AARRGGBB` from the database.
  static Color? tryParseHex(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    var value = hex.replaceFirst('#', '').trim();
    if (value.length == 6) value = 'FF$value';
    if (value.length != 8) return null;
    final parsed = int.tryParse(value, radix: 16);
    return parsed == null ? null : Color(parsed);
  }

  static String toHex(Color color) {
    final argb = color.toARGB32();
    return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}

/// Theme-aware semantic colours, resolved once per build via
/// `Theme.of(context).extension<AppPalette>()`.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.income,
    required this.expense,
    required this.transfer,
    required this.warning,
    required this.success,
    required this.danger,
    required this.info,
    required this.surfaceAlt,
    required this.outlineStrong,
    required this.textSecondary,
    required this.textTertiary,
    required this.brandSurface,
    required this.shimmerBase,
    required this.shimmerHighlight,
  });

  final Color income;
  final Color expense;
  final Color transfer;
  final Color warning;
  final Color success;
  final Color danger;
  final Color info;
  final Color surfaceAlt;
  final Color outlineStrong;
  final Color textSecondary;
  final Color textTertiary;
  final Color brandSurface;
  final Color shimmerBase;
  final Color shimmerHighlight;

  static const AppPalette light = AppPalette(
    income: AppColors.income,
    expense: AppColors.expense,
    transfer: AppColors.transfer,
    warning: AppColors.warning,
    success: AppColors.success,
    danger: AppColors.danger,
    info: AppColors.info,
    surfaceAlt: AppColors.surfaceAlt,
    outlineStrong: AppColors.outlineStrong,
    textSecondary: AppColors.textSecondary,
    textTertiary: AppColors.textTertiary,
    brandSurface: AppColors.brandSurface,
    shimmerBase: Color(0xFFEAECF0),
    shimmerHighlight: Color(0xFFF7F8FA),
  );

  static const AppPalette dark = AppPalette(
    income: AppColors.incomeDark,
    expense: AppColors.expenseDark,
    transfer: AppColors.transferDark,
    warning: AppColors.warningDark,
    success: AppColors.successDark,
    danger: AppColors.dangerDark,
    info: AppColors.infoDark,
    surfaceAlt: AppColors.surfaceAltDark,
    outlineStrong: AppColors.outlineStrongDark,
    textSecondary: AppColors.textSecondaryDark,
    textTertiary: AppColors.textTertiaryDark,
    brandSurface: AppColors.brandSurfaceDark,
    shimmerBase: Color(0xFF1C242E),
    shimmerHighlight: Color(0xFF263040),
  );

  @override
  AppPalette copyWith({
    Color? income,
    Color? expense,
    Color? transfer,
    Color? warning,
    Color? success,
    Color? danger,
    Color? info,
    Color? surfaceAlt,
    Color? outlineStrong,
    Color? textSecondary,
    Color? textTertiary,
    Color? brandSurface,
    Color? shimmerBase,
    Color? shimmerHighlight,
  }) {
    return AppPalette(
      income: income ?? this.income,
      expense: expense ?? this.expense,
      transfer: transfer ?? this.transfer,
      warning: warning ?? this.warning,
      success: success ?? this.success,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      outlineStrong: outlineStrong ?? this.outlineStrong,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      brandSurface: brandSurface ?? this.brandSurface,
      shimmerBase: shimmerBase ?? this.shimmerBase,
      shimmerHighlight: shimmerHighlight ?? this.shimmerHighlight,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      transfer: Color.lerp(transfer, other.transfer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      success: Color.lerp(success, other.success, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      outlineStrong: Color.lerp(outlineStrong, other.outlineStrong, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      brandSurface: Color.lerp(brandSurface, other.brandSurface, t)!,
      shimmerBase: Color.lerp(shimmerBase, other.shimmerBase, t)!,
      shimmerHighlight: Color.lerp(shimmerHighlight, other.shimmerHighlight, t)!,
    );
  }
}
