import 'package:quickgui/domain/catalog/version.dart';

class OperatingSystem {
  OperatingSystem(this.name, this.code) : versions = [];

  final String name;
  final String code;
  List<Version> versions;
}

Future<List<OperatingSystem>>? gOperatingSystems;
