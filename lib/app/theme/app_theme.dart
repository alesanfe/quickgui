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

  static ThemeData light() => FlexThemeData.light(
    scheme: _scheme,
    subThemesData: _subThemes,
    visualDensity: VisualDensity.standard,
  );

  static ThemeData dark() => FlexThemeData.dark(
    scheme: _scheme,
    subThemesData: _subThemes,
    visualDensity: VisualDensity.standard,
  );
}
