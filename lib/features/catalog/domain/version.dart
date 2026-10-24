import 'package:quickgui/features/catalog/domain/option.dart';

class Version {
  Version(this.version) : options = [];

  final String version;
  final List<Option> options;
}
