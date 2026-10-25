import 'package:flutter/material.dart';

/// Centralised route construction for Navigator pushes.
PageRoute<T> appRoute<T>(Widget page) =>
    MaterialPageRoute<T>(builder: (_) => page);
