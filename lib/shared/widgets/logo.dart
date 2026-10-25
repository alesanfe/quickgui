import 'package:flutter/material.dart';

/// Quickgui brand logo, fixed height so pages can share the same header.
class Logo extends StatelessWidget {
  const Logo({this.height = 230, super.key});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset('assets/images/logo_pink.png'),
        ),
      ),
    );
  }
}
