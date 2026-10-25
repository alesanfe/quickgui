String encodeVmValue(String value) => value
    .replaceAll(r'\', r'\\')
    .replaceAll('"', r'\"')
    .replaceAll(r'$', r'\$')
    .replaceAll('`', r'\`')
    .replaceAll('\r', '')
    .replaceAll('\n', '');

String decodeVmValue(String value) =>
    value.replaceAllMapped(RegExp(r'\\([\\"$`])'), (match) => match[1]!);

List<String> parseVmArray(String value) =>
    RegExp(r'"((?:\\.|[^"\\])*)"')
        .allMatches(value)
        .map((match) => decodeVmValue(match[1]!))
        .toList();

String encodeVmArray(Iterable<String> values) =>
    '(${values.map((value) => '"${encodeVmValue(value)}"').join(' ')})';

bool validPortForward(String value) {
  final parts = value.split(':');
  if (parts.length != 2) return false;
  return parts.every((part) {
    final port = int.tryParse(part);
    return port != null && port > 0 && port <= 65535;
  });
}
