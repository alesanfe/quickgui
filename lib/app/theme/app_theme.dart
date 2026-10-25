import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

/// Quickgui theme: Material 3 via FlexColorScheme, keeping the historical
/// pink brand. Desktop density and visible focus for keyboard users.
abstract final class AppTheme {
  static const FlexScheme _scheme = FlexScheme.pinkM3;

  static const _subThemes = FlexSubThemesData(
    interactionEffects: true,
    defaultRadius: 8,
    inputDecoratorBorderType: FlexInputBorderType.outline,
    inputDecoratorFocusedBorderWidth: 2,
  );

  static ThemeData light() => _neutral(
    FlexThemeData.light(
      scheme: _scheme,
      subThemesData: _subThemes,
      visualDensity: VisualDensity.standard,
    ),
    false,
  );

  static ThemeData dark() => _neutral(
    FlexThemeData.dark(
      scheme: _scheme,
      subThemesData: _subThemes,
      visualDensity: VisualDensity.standard,
    ),
    true,
  );

  static ThemeData _neutral(ThemeData theme, bool dark) {
    final surface = dark ? const Color(0xff191a1e) : const Color(0xfffafafa);
    final panel = dark ? const Color(0xff232429) : const Color(0xfff1f2f4);
    return theme.copyWith(
      scaffoldBackgroundColor: surface,
      colorScheme: theme.colorScheme.copyWith(
        surface: surface,
        surfaceContainer: panel,
        surfaceContainerLow: panel,
        surfaceContainerHigh: panel,
        surfaceContainerHighest: dark
            ? const Color(0xff303138)
            : const Color(0xffe8e9ec),
      ),
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      cardTheme: theme.cardTheme.copyWith(
        color: panel,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      navigationRailTheme: theme.navigationRailTheme.copyWith(
        backgroundColor: panel,
      ),
    );
  }
}
