/// Host capabilities as reported by the backend (--capabilities JSON).
class HostCapabilities {
  const HostCapabilities(this.raw);
  final Map<String, dynamic> raw;
  bool supports(String cap) => (raw['capabilities'] ?? <String, dynamic>{})[cap] == true;
  int? get schemaVersion => raw['schemaVersion'] as int?;
}
