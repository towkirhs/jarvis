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

/// Accent colours the whole app can be painted in. 'default' is indigo, or mauve in Latte.
const accents = <String, Color>{
  'default': Colors.indigo,
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
      final color = accents[accent] ?? Colors.indigo;
      if (look == 'latte') return _latte(accent == 'default' ? Latte.mauve : color);
      return polish(ThemeData(
        colorSchemeSeed: color,
        brightness: look == 'dark' ? Brightness.dark : Brightness.light,
        useMaterial3: true,
      ));
    });

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


/// One set of shapes, weights and spacing for every theme, so each screen reads the same way:
/// bold titles, flat rounded cards, no shadows, and filled fields.
ThemeData polish(ThemeData t) {
  final c = t.colorScheme;
  final tt = t.textTheme;
  TextStyle? w(TextStyle? s, FontWeight weight, [double? spacing]) =>
      s?.copyWith(fontWeight: weight, letterSpacing: spacing);
  // Bricolage Grotesque for titles and big numbers: the app's voice. Body text stays the system font, which
  // reads best small and covers Bangla.
  TextStyle? display(TextStyle? s, FontWeight weight, [double? spacing]) =>
      w(s, weight, spacing)?.copyWith(fontFamily: 'Bricolage');
  RoundedRectangleBorder round(double r) => RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));
  // Material 3 shape scale: small 8 (chips), medium 12 (fields, list items), large 16 (cards, FAB),
  // extra large 28 (dialogs, sheets); buttons and the nav indicator stay fully round.
  final field = OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none);
  return t.copyWith(
    textTheme: tt.copyWith(
      displaySmall: display(tt.displaySmall, FontWeight.w800, -1),
      headlineMedium: display(tt.headlineMedium, FontWeight.w800, -0.6),
      headlineSmall: display(tt.headlineSmall, FontWeight.w700, -0.3),
      titleLarge: display(tt.titleLarge, FontWeight.w700, -0.2),
      titleMedium: w(tt.titleMedium, FontWeight.w600),
      titleSmall: w(tt.titleSmall, FontWeight.w600),
      labelLarge: w(tt.labelLarge, FontWeight.w600),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: c.surfaceContainerLow,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: round(16),
      clipBehavior: Clip.antiAlias,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      // The theme's text styles get their sizes later, so the app bar title needs its size here.
      titleTextStyle: display(tt.titleLarge, FontWeight.w700, -0.2)?.copyWith(color: c.onSurface, fontSize: 22, height: 1.27),
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
      indicatorColor: c.secondaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => tt.labelSmall?.copyWith(fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(elevation: 1, highlightElevation: 2, shape: round(16)),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: round(8)),
    dividerTheme: DividerThemeData(color: c.outlineVariant.withValues(alpha: 0.5), thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(shape: round(12)),
    chipTheme: t.chipTheme.copyWith(shape: round(8)),
    dialogTheme: DialogThemeData(shape: round(28)),
    bottomSheetTheme: const BottomSheetThemeData(
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
  );
}

/// Theme names shown in Settings.
const themeNames = {'system': 'Follow phone', 'light': 'Light', 'dark': 'Dark', 'latte': 'Catppuccin Latte'};
