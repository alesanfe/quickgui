import 'dart:convert';
import 'dart:io';

/// Returns the latest released quickgui version tag from the upstream
/// GitHub repository, or an empty string when the check fails.
Future<String> fetchLatestQuickguiRelease() async {
  try {
    final client = HttpClient();
    final req = await client.getUrl(
      Uri.parse(
        'https://api.github.com/repos/quickemu-project/quickgui/releases/latest',
      ),
    );
    req.headers.add('User-Agent', 'quickgui');
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    return RegExp(r'"tag_name"\s*:\s*"([^"]+)"').firstMatch(body)?.group(1) ??
        '';
  } catch (_) {
    return '';
  }
}
