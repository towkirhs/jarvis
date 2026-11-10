import 'dart:ui' show FontFeature;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Catppuccin Latte palette (https://catppuccin.com/palette).
class Latte {
  static const mauve = Color(0xFF8839EF);
  static const blue = Color(0xFF1E66F5);
  static const teal = Color(0xFF179299);
  static const red = Color(0xFFD20F39);
  static const text = Color(0xFF4C4F69);
  static const subtext0 = Color(0xFF6C6F85);
  static const overlay0 = Color(0xFF9CA0B0);
  static const surface1 = Color(0xFFBCC0CC);
  static const surface0 = Color(0xFFCCD0DA);
  static const base = Color(0xFFEFF1F5);
  static const mantle = Color(0xFFE6E9EF);
  static const crust = Color(0xFFDCE0E8);
}

Color _tint(Color c, double a) => Color.alphaBlend(c.withValues(alpha: a), Latte.base);

/// The app's own colours, after the kingfisher: a deep teal for what you act on, and its orange for the
/// one thing that needs you now.
const kingfisher = Color(0xFF0B7285);
const _ember = Color(0xFFE8590C);

/// Accent colours the whole app can be painted in. 'default' is kingfisher teal, or mauve in Latte.
const accents = <String, Color>{
  'default': kingfisher,
  'mauve': Color(0xFF8839EF),
  'blue': Color(0xFF1E66F5),
  'sapphire': Color(0xFF209FB5),
  'teal': Color(0xFF179299),
  'green': Color(0xFF40A02B),
  'yellow': Color(0xFFDF8E1D),
  'peach': Color(0xFFFE640B),
  'red': Color(0xFFD20F39),
  'pink': Color(0xFFEA76CB),
};

final _themes = <String, ThemeData>{};

/// The theme for a look ('light', 'dark' or 'latte') in an accent, built once and reused.
ThemeData themeFor(String look, String accent) => _themes.putIfAbsent('$look/$accent', () {
      final color = accents[accent] ?? kingfisher;
      if (look == 'latte') return _latte(accent == 'default' ? Latte.mauve : color);
      return polish(ThemeData(colorScheme: _scheme(color, dark: look == 'dark', own: accent == 'default'), useMaterial3: true));
    });

/// The accent decides only what you act on. Everything behind it is the same quiet neutral in every accent:
/// a soft ground with plain cards lifted off it (white by day, graphite by night), so content reads in layers.
ColorScheme _scheme(Color accent, {required bool dark, required bool own}) {
  final seed = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: dark ? Brightness.dark : Brightness.light,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  final base = dark
      ? seed.copyWith(
          surface: const Color(0xFF0D0F14),
          onSurface: const Color(0xFFECEEF3),
          onSurfaceVariant: const Color(0xFFA3A9B8),
          surfaceContainerLowest: const Color(0xFF090B0F),
          surfaceContainerLow: const Color(0xFF171A21),
          surfaceContainer: const Color(0xFF1B1F27),
          surfaceContainerHigh: const Color(0xFF222731),
          surfaceContainerHighest: const Color(0xFF2A303C),
          outline: const Color(0xFF757B8A),
          outlineVariant: const Color(0xFF2E3440),
        )
      : seed.copyWith(
          surface: const Color(0xFFF3F4F8),
          onSurface: const Color(0xFF14161F),
          onSurfaceVariant: const Color(0xFF5F6473),
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: Colors.white,
          surfaceContainer: const Color(0xFFECEEF3),
          surfaceContainerHigh: const Color(0xFFE5E8EE),
          surfaceContainerHighest: const Color(0xFFDDE1E9),
          outline: const Color(0xFF8A8FA0),
          outlineVariant: const Color(0xFFD3D7E0),
        );
  final scheme = own ? _own(base, dark) : base;
  // Tinted fills (a marked day, a selected chip) are a soft wash of the accent with normal text on top.
  return scheme.copyWith(
    primaryContainer: Color.alphaBlend(scheme.primary.withValues(alpha: dark ? 0.24 : 0.14), scheme.surfaceContainerLow),
    onPrimaryContainer: scheme.onSurface,
  );
}

/// Kingfisher teal exactly as drawn, with its orange as the second colour.
ColorScheme _own(ColorScheme base, bool dark) {
  return dark
      ? base.copyWith(
          primary: const Color(0xFF5CC8DB),
          onPrimary: const Color(0xFF00363F),
          tertiary: const Color(0xFFFF9A62),
          onTertiary: const Color(0xFF3A1400),
          tertiaryContainer: const Color(0xFF5A2600),
          onTertiaryContainer: const Color(0xFFFFDCC8),
        )
      : base.copyWith(
          primary: kingfisher,
          onPrimary: Colors.white,
          tertiary: _ember,
          onTertiary: Colors.white,
          tertiaryContainer: const Color(0xFFFFE8DB),
          onTertiaryContainer: const Color(0xFF5A2000),
        );
}

ThemeData _latte(Color accent) => polish(ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme(
    brightness: Brightness.light,
    primary: accent,
    onPrimary: Latte.base,
    primaryContainer: _tint(accent, 0.18),
    onPrimaryContainer: Latte.text,
    secondary: Latte.blue,
    onSecondary: Latte.base,
    secondaryContainer: _tint(Latte.blue, 0.15),
    onSecondaryContainer: Latte.text,
    tertiary: Latte.teal,
    onTertiary: Latte.base,
    tertiaryContainer: _tint(Latte.teal, 0.15),
    onTertiaryContainer: Latte.text,
    error: Latte.red,
    onError: Latte.base,
    errorContainer: _tint(Latte.red, 0.15),
    onErrorContainer: Latte.text,
    surface: Latte.base,
    onSurface: Latte.text,
    onSurfaceVariant: Latte.subtext0,
    surfaceContainerLowest: Latte.base,
    surfaceContainerLow: Latte.mantle,
    surfaceContainer: Latte.mantle,
    surfaceContainerHigh: Latte.crust,
    surfaceContainerHighest: Latte.surface0,
    outline: Latte.overlay0,
    outlineVariant: Latte.surface1,
    inverseSurface: Latte.text,
    onInverseSurface: Latte.base,
    inversePrimary: _tint(accent, 0.5),
  ),
  scaffoldBackgroundColor: Latte.base,
));


/// One set of shapes, weights, spacing and motion for every theme, so each screen reads the same way:
/// bold titles, flat rounded cards, no shadows, filled fields, pill chips, and pages that slide.
ThemeData polish(ThemeData t) {
  final c = t.colorScheme;
  final tt = t.textTheme;
  TextStyle? w(TextStyle? s, FontWeight weight, [double? spacing]) =>
      s?.copyWith(fontWeight: weight, letterSpacing: spacing);
  // Digits of equal width, so amounts, times and counts line up down a list.
  const tabular = [FontFeature.tabularFigures()];
  TextStyle? nums(TextStyle? s) => s?.copyWith(fontFeatures: tabular);
  // Bricolage Grotesque for titles and big numbers: the app's voice. Body text stays the system font, which
  // reads best small and covers Bangla.
  TextStyle? display(TextStyle? s, FontWeight weight, [double? spacing]) =>
      w(s, weight, spacing)?.copyWith(fontFamily: 'Bricolage');
  RoundedRectangleBorder round(double r) => RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));
  // Shape scale: 14 (fields, buttons, list items), 20 (cards, FAB, menus), 28 (dialogs, sheets);
  // chips and the nav indicator are fully round.
  final field = OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none);
  final button = ButtonStyle(
    shape: WidgetStatePropertyAll(round(14)),
    minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
  );
  return t.copyWith(
    // Pages slide in from the side and can be swiped back from the edge.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: CupertinoPageTransitionsBuilder()},
    ),
    filledButtonTheme: FilledButtonThemeData(style: button),
    outlinedButtonTheme: OutlinedButtonThemeData(style: button),
    elevatedButtonTheme: ElevatedButtonThemeData(style: button),
    tabBarTheme: const TabBarThemeData(dividerColor: Colors.transparent),
    popupMenuTheme: PopupMenuThemeData(color: c.surfaceContainerLow, surfaceTintColor: Colors.transparent, shape: round(20)),
    textTheme: tt.copyWith(
      displaySmall: display(tt.displaySmall, FontWeight.w800, -1),
      headlineMedium: display(tt.headlineMedium, FontWeight.w800, -0.6),
      headlineSmall: display(tt.headlineSmall, FontWeight.w700, -0.3),
      titleLarge: display(tt.titleLarge, FontWeight.w700, -0.2),
      titleMedium: w(tt.titleMedium, FontWeight.w600),
      titleSmall: w(tt.titleSmall, FontWeight.w600),
      labelLarge: w(tt.labelLarge, FontWeight.w600),
      bodyLarge: nums(tt.bodyLarge),
      bodyMedium: nums(tt.bodyMedium),
      bodySmall: nums(tt.bodySmall),
      labelMedium: nums(tt.labelMedium),
      labelSmall: nums(tt.labelSmall),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: c.surfaceContainerLow,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: round(20),
      clipBehavior: Clip.antiAlias,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      // The theme's text styles get their sizes later, so the app bar title needs its size here.
      titleTextStyle: display(tt.titleLarge, FontWeight.w800, -0.5)?.copyWith(color: c.onSurface, fontSize: 26, height: 1.2),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceContainerHighest,
      border: field,
      enabledBorder: field,
      focusedBorder: field.copyWith(borderSide: BorderSide(color: c.primary, width: 1.5)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      elevation: 0,
      backgroundColor: c.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.primary.withValues(alpha: 0.14),
      // The tab you are on is in the accent; the rest stay quiet.
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? c.primary : c.onSurfaceVariant),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? tt.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: c.primary)
            : tt.labelSmall?.copyWith(fontWeight: FontWeight.w500, color: c.onSurfaceVariant),
      ),
    ),
    // The one main action on a screen is the strongest thing on it.
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 2,
      highlightElevation: 3,
      backgroundColor: c.primary,
      foregroundColor: c.onPrimary,
      shape: round(20),
    ),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: round(14)),
    dividerTheme: DividerThemeData(color: c.outlineVariant.withValues(alpha: 0.5), thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(shape: round(14)),
    chipTheme: t.chipTheme.copyWith(
      shape: const StadiumBorder(),
      side: BorderSide.none,
      backgroundColor: c.surfaceContainerHigh,
    ),
    dialogTheme: DialogThemeData(shape: round(28), backgroundColor: c.surfaceContainerLow, surfaceTintColor: Colors.transparent),
    bottomSheetTheme: BottomSheetThemeData(
      showDragHandle: true,
      backgroundColor: c.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
  );
}

/// Theme names shown in Settings.
const themeNames = {'system': 'Follow phone', 'light': 'Light', 'dark': 'Dark', 'latte': 'Catppuccin Latte'};
