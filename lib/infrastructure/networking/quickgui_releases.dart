import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Classified update-check outcome (QGUI-UPD-101): the dialog tells
/// apart "no connection" from "service returned something unusable"
/// instead of one generic network blame.
typedef ReleaseCheck = ({String version, String? errorKind});

/// Returns the latest released quickgui version tag from the upstream
/// GitHub repository; on failure `errorKind` names the
/// category ('connection' | 'timeout' | 'tls' | 'service' | 'response'
/// | 'unknown').
Future<ReleaseCheck> fetchLatestQuickguiRelease() async {
  try {
    final client = HttpClient();
    final req = await client
        .getUrl(
          Uri.parse(
            'https://api.github.com/repos/quickemu-project/quickgui/releases/latest',
          ),
        )
        .timeout(const Duration(seconds: 10));
    req.headers.add('User-Agent', 'quickgui');
    final res = await req.close().timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      return (version: '', errorKind: 'service');
    }
    final body = await res.transform(utf8.decoder).join();
    final tag =
        RegExp(r'"tag_name"\s*:\s*"([^"]+)"').firstMatch(body)?.group(1) ?? '';
    return (version: tag, errorKind: tag.isEmpty ? 'response' : null);
  } on TimeoutException {
    return (version: '', errorKind: 'timeout');
  } on HandshakeException {
    return (version: '', errorKind: 'tls');
  } on SocketException {
    return (version: '', errorKind: 'connection');
  } catch (_) {
    return (version: '', errorKind: 'unknown');
  }
}
