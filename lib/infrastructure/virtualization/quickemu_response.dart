import 'dart:convert';

/// Parses versioned JSON envelopes emitted by the backend contract.
class QuickemuResponse {
  QuickemuResponse(this.raw);
  final Map<String, dynamic> raw;

  factory QuickemuResponse.parse(String stdout) =>
      QuickemuResponse(jsonDecode(stdout) as Map<String, dynamic>);

  int? get schemaVersion => raw['schemaVersion'] as int?;
}
