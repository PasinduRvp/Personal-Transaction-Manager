import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Ergonomic shortcuts used across the UI layer.
extension BuildContextX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;

  /// Finora's semantic colours (income/expense/warning/...).
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;

  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  MediaQueryData get media => MediaQuery.of(this);
  Size get screenSize => MediaQuery.sizeOf(this);
  double get screenWidth => MediaQuery.sizeOf(this).width;
  double get screenHeight => MediaQuery.sizeOf(this).height;
  EdgeInsets get viewPadding => MediaQuery.viewPaddingOf(this);
  EdgeInsets get viewInsets => MediaQuery.viewInsetsOf(this);

  /// True on a phone-sized viewport; used to switch the OCR review screen
  /// between a stacked and a side-by-side layout.
  bool get isCompact => MediaQuery.sizeOf(this).width < 600;
  bool get isMedium => MediaQuery.sizeOf(this).width >= 600 &&
      MediaQuery.sizeOf(this).width < 1024;
  bool get isExpanded => MediaQuery.sizeOf(this).width >= 1024;

  void hideKeyboard() => FocusScope.of(this).unfocus();
}
