import 'package:flutter/material.dart';
import 'package:quickgui/app/app.dart' show App;

/// App theme presets used by [App] — kept tiny: Material 3 defaults.
ThemeData quickguiTheme({bool dark = false, Color seed = Colors.blue}) =>
    ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      colorSchemeSeed: seed,
    );
