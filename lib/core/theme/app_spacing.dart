import 'package:flutter/widgets.dart';

/// A 4pt spacing scale. Layouts compose these constants instead of inventing
/// one-off padding values, which is what keeps screens visually consistent.
class AppSpacing {
  const AppSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 40;
  static const double giant = 56;

  /// Standard horizontal page gutter.
  static const double page = lg;

  static const EdgeInsets pageInsets = EdgeInsets.symmetric(horizontal: page);

  static const EdgeInsets cardInsets = EdgeInsets.all(lg);

  static const EdgeInsets listRowInsets =
      EdgeInsets.symmetric(horizontal: lg, vertical: md);

  /// Bottom padding that keeps the last list item clear of the nav bar + FAB.
  static const double bottomNavClearance = 96;

  static const SizedBox gapXs = SizedBox(height: xs);
  static const SizedBox gapSm = SizedBox(height: sm);
  static const SizedBox gapMd = SizedBox(height: md);
  static const SizedBox gapLg = SizedBox(height: lg);
  static const SizedBox gapXl = SizedBox(height: xl);
  static const SizedBox gapXxl = SizedBox(height: xxl);

  static const SizedBox hGapXs = SizedBox(width: xs);
  static const SizedBox hGapSm = SizedBox(width: sm);
  static const SizedBox hGapMd = SizedBox(width: md);
  static const SizedBox hGapLg = SizedBox(width: lg);
}

/// Corner radii. Rounded, but restrained — a finance app should read as
/// precise rather than playful.
class AppRadius {
  const AppRadius._();

  static const double xs = 6;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double pill = 999;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));

  static const BorderRadius sheetTop = BorderRadius.vertical(
    top: Radius.circular(xl),
  );
}

/// Elevation is used sparingly: cards get a hairline border plus a very soft
/// shadow rather than a heavy drop shadow.
class AppElevation {
  const AppElevation._();

  static List<BoxShadow> card(bool isDark) => isDark
      ? const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 12,
            offset: Offset(0, 2),
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x0D101828),
            blurRadius: 12,
            offset: Offset(0, 2),
          ),
        ];

  static List<BoxShadow> raised(bool isDark) => isDark
      ? const [
          BoxShadow(
            color: Color(0x4D000000),
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x14101828),
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ];
}
