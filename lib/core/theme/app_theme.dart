import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// Builds the light and dark Material 3 themes from the design tokens.
class AppTheme {
  const AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final background = isDark ? AppColors.backgroundDark : AppColors.background;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surface;
    final surfaceAlt = isDark ? AppColors.surfaceAltDark : AppColors.surfaceAlt;
    final outline = isDark ? AppColors.outlineDark : AppColors.outline;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final textTertiary =
        isDark ? AppColors.textTertiaryDark : AppColors.textTertiary;
    final brand = isDark ? AppColors.brandLight : AppColors.brand;
    final danger = isDark ? AppColors.dangerDark : AppColors.danger;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: brand,
      onPrimary: isDark ? const Color(0xFF04231C) : Colors.white,
      primaryContainer:
          isDark ? AppColors.brandSurfaceDark : AppColors.brandSurface,
      onPrimaryContainer: isDark ? AppColors.brandLight : AppColors.brandDark,
      secondary: AppColors.accent,
      onSecondary: const Color(0xFF3B1E00),
      secondaryContainer:
          isDark ? const Color(0xFF3B2A16) : const Color(0xFFFDF0E3),
      onSecondaryContainer:
          isDark ? const Color(0xFFF7C99B) : const Color(0xFF7A4A12),
      tertiary: isDark ? AppColors.transferDark : AppColors.transfer,
      onTertiary: isDark ? const Color(0xFF04203F) : Colors.white,
      error: danger,
      onError: isDark ? const Color(0xFF3B0A06) : Colors.white,
      errorContainer: isDark ? const Color(0xFF3F1512) : const Color(0xFFFEE4E2),
      onErrorContainer:
          isDark ? const Color(0xFFFDA29B) : const Color(0xFF912018),
      surface: surface,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      surfaceContainerLowest: isDark ? const Color(0xFF0B0F14) : surface,
      surfaceContainerLow: isDark ? const Color(0xFF11181F) : background,
      surfaceContainer: surfaceAlt,
      surfaceContainerHigh:
          isDark ? const Color(0xFF222C38) : const Color(0xFFEAECF0),
      surfaceContainerHighest:
          isDark ? const Color(0xFF2A3542) : const Color(0xFFE4E7EC),
      outline: outline,
      outlineVariant: isDark ? const Color(0xFF212A35) : const Color(0xFFEAECF0),
      shadow: Colors.black,
      scrim: Colors.black54,
      inverseSurface: isDark ? AppColors.surface : AppColors.surfaceDark,
      onInverseSurface:
          isDark ? AppColors.textPrimary : AppColors.textPrimaryDark,
      inversePrimary: isDark ? AppColors.brand : AppColors.brandLight,
    );

    final textTheme = AppTypography.textTheme(textPrimary, textSecondary);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      textTheme: textTheme,
      fontFamily: AppTypography.fontFamily,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      extensions: <ThemeExtension<dynamic>>[
        isDark ? AppPalette.dark : AppPalette.light,
      ],

      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),

      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.xlAll,
          side: BorderSide.none,
        ),
      ),

      dividerTheme: DividerThemeData(
        color: outline,
        thickness: 1,
        space: 1,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.pillAll),
          textStyle: textTheme.labelLarge?.copyWith(color: null),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          elevation: 0,
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.pillAll),
          textStyle: textTheme.labelLarge,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          foregroundColor: textPrimary,
          side: BorderSide(color: isDark
              ? AppColors.outlineStrongDark
              : AppColors.outlineStrong),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.pillAll),
          textStyle: textTheme.labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brand,
          textStyle: textTheme.labelLarge?.copyWith(color: brand),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.pillAll),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? surfaceAlt : surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        alignLabelWithHint: true,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        hintStyle: textTheme.bodyMedium?.copyWith(color: textTertiary),
        labelStyle: textTheme.bodyMedium?.copyWith(color: textSecondary),
        floatingLabelStyle: textTheme.labelMedium?.copyWith(color: brand),
        helperStyle: textTheme.bodySmall?.copyWith(color: textTertiary),
        errorStyle: textTheme.bodySmall?.copyWith(color: danger),
        border: OutlineInputBorder(
          borderRadius: AppRadius.lgAll,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.lgAll,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.lgAll,
          borderSide: BorderSide(color: brand, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: danger, width: 1.6),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: outline.withValues(alpha: 0.5)),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: surfaceAlt,
        selectedColor:
            isDark ? AppColors.brandSurfaceDark : AppColors.brandSurface,
        checkmarkColor: brand,
        side: BorderSide(color: outline),
        labelStyle: textTheme.labelMedium,
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(color: brand),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.pillAll),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: surface,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: isDark
            ? AppColors.outlineStrongDark
            : AppColors.outlineStrong,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetTop),
        clipBehavior: Clip.antiAlias,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor:
            isDark ? AppColors.brandSurfaceDark : AppColors.brandSurface,
        indicatorShape:
            const RoundedRectangleBorder(borderRadius: AppRadius.pillAll),
        height: 68,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall?.copyWith(
            letterSpacing: 0.1,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? brand : textTertiary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? brand : textTertiary,
          );
        }),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: brand,
        foregroundColor: isDark ? const Color(0xFF04231C) : Colors.white,
        elevation: 2,
        highlightElevation: 4,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? AppColors.surfaceAltDark : const Color(0xFF1D2939),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        actionTextColor: AppColors.brandLight,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
      ),

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        iconColor: textSecondary,
        titleTextStyle: textTheme.titleSmall,
        subtitleTextStyle: textTheme.bodySmall,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? Colors.white : surface),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? brand : surfaceAlt),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? brand : outline),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: brand,
        linearTrackColor: surfaceAlt,
        circularTrackColor: surfaceAlt,
        linearMinHeight: 8,
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: brand,
        unselectedLabelColor: textTertiary,
        labelStyle: textTheme.titleSmall,
        unselectedLabelStyle: textTheme.titleSmall,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: outline,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: brand, width: 2.5),
        ),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll(textTheme.labelMedium),
          side: WidgetStatePropertyAll(BorderSide(color: outline)),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          ),
        ),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdAll,
          side: BorderSide(color: outline),
        ),
        textStyle: textTheme.bodyMedium?.copyWith(color: textPrimary),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceAltDark : const Color(0xFF1D2939),
          borderRadius: AppRadius.smAll,
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: Colors.white),
      ),
    );
  }
}
