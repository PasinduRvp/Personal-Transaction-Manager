import 'package:flutter/material.dart';

/// Finora's type scale.
///
/// Deliberately uses the platform default font rather than downloading a web
/// font: the app must render correctly offline and on first launch. Monetary
/// figures use tabular-style sizing and tight letter spacing so columns of
/// numbers line up.
class AppTypography {
  const AppTypography._();

  static const String? fontFamily = null; // platform default

  static TextTheme textTheme(Color primary, Color secondary) {
    return TextTheme(
      // Display — reserved for the dashboard balance figure.
      displaySmall: TextStyle(
        fontSize: 34,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        color: primary,
      ),

      // Headlines — screen titles.
      headlineLarge: TextStyle(
        fontSize: 28,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: primary,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: primary,
      ),
      headlineSmall: TextStyle(
        fontSize: 20,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: primary,
      ),

      // Titles — card headers and list section headers.
      titleLarge: TextStyle(
        fontSize: 18,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: primary,
      ),

      // Body.
      bodyLarge: TextStyle(
        fontSize: 16,
        height: 1.5,
        fontWeight: FontWeight.w400,
        color: primary,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.45,
        fontWeight: FontWeight.w400,
        color: secondary,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        height: 1.4,
        fontWeight: FontWeight.w400,
        color: secondary,
      ),

      // Labels — buttons, chips, overlines.
      labelLarge: TextStyle(
        fontSize: 15,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: primary,
      ),
      labelMedium: TextStyle(
        fontSize: 13,
        height: 1.2,
        fontWeight: FontWeight.w500,
        color: secondary,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        color: secondary,
      ),
    );
  }

  /// The large hero amount on the dashboard.
  static TextStyle amountHero(Color color) => TextStyle(
        fontSize: 36,
        height: 1.1,
        fontWeight: FontWeight.w700,
        letterSpacing: -1,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Amount shown on a summary tile.
  static TextStyle amountLarge(Color color) => TextStyle(
        fontSize: 22,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Amount in a transaction row.
  static TextStyle amountRow(Color color) => TextStyle(
        fontSize: 15,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Small numeric label, e.g. a chart axis or a percentage.
  static TextStyle numericSmall(Color color) => TextStyle(
        fontSize: 11,
        height: 1.2,
        fontWeight: FontWeight.w500,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Section header above a group of list rows ("TODAY", "YESTERDAY").
  static TextStyle sectionHeader(Color color) => TextStyle(
        fontSize: 11,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: color,
      );

  /// Raw OCR text preview — monospaced so alignment in statements survives.
  static TextStyle monospace(Color color) => TextStyle(
        fontFamily: 'monospace',
        fontFamilyFallback: const ['Courier New', 'monospace'],
        fontSize: 12,
        height: 1.45,
        color: color,
      );
}
