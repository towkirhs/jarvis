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

final ThemeData latteTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme(
    brightness: Brightness.light,
    primary: Latte.mauve,
    onPrimary: Latte.base,
    primaryContainer: _tint(Latte.mauve, 0.18),
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
    inversePrimary: _tint(Latte.mauve, 0.5),
  ),
  scaffoldBackgroundColor: Latte.base,
  cardTheme: const CardThemeData(color: Latte.mantle, elevation: 0),
);

final ThemeData defaultLight = ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true);
final ThemeData defaultDark = ThemeData(colorSchemeSeed: Colors.indigo, brightness: Brightness.dark, useMaterial3: true);

/// Theme names shown in Settings.
const themeNames = {'system': 'Follow phone', 'light': 'Light', 'dark': 'Dark', 'latte': 'Catppuccin Latte'};
