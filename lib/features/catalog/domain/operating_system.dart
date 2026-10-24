import 'package:quickgui/features/catalog/domain/version.dart';

class OperatingSystem {
  OperatingSystem(this.name, this.code) : versions = [];

  final String name;
  final String code;
  List<Version> versions;
}

Future<List<OperatingSystem>>? gOperatingSystems;
