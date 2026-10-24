import 'package:quickgui/domain/catalog/option.dart';

class Version {
  Version(this.version) : options = [];

  final String version;
  final List<Option> options;
}
