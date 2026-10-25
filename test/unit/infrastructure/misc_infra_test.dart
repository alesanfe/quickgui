import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/infrastructure/networking/quickgui_releases.dart';
import 'package:quickgui/infrastructure/settings/shared_preferences_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SharedPreferencesRepository', () {
    test('round-trips every supported type', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = SharedPreferencesRepository();
      await repo.set('s', 'text');
      await repo.set('i', 7);
      await repo.set('b', true);
      await repo.set('d', 1.5);
      await repo.set('l', <String>['a', 'b']);
      expect(await repo.get('s'), 'text');
      expect(await repo.get('i'), 7);
      expect(await repo.get('b'), true);
      expect(await repo.get('d'), 1.5);
      expect(await repo.get('l'), ['a', 'b']);
      expect(await repo.get('missing'), isNull);
    });
  });

  group('fetchLatestQuickguiRelease', () {
    test('parses tag_name from the GitHub payload', () async {
      final tag = await HttpOverrides.runZoned(
        fetchLatestQuickguiRelease,
        createHttpClient: (_) =>
            _FakeHttpClient('{"tag_name": "1.2.3", "other": 1}'),
      );
      expect(tag, '1.2.3');
    });

    test('returns empty when the payload has no tag', () async {
      final tag = await HttpOverrides.runZoned(
        fetchLatestQuickguiRelease,
        createHttpClient: (_) => _FakeHttpClient('{"name": "release"}'),
      );
      expect(tag, isEmpty);
    });

    test('returns empty when the request fails', () async {
      final tag = await HttpOverrides.runZoned(
        fetchLatestQuickguiRelease,
        createHttpClient: (_) => _FailingHttpClient(),
      );
      expect(tag, isEmpty);
    });
  });
}

class _FakeHttpClient extends Fake implements HttpClient {
  _FakeHttpClient(this._body);
  final String _body;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeRequest(_body);
}

class _FailingHttpClient extends Fake implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      throw const SocketException('offline');
}

class _FakeRequest extends Fake implements HttpClientRequest {
  _FakeRequest(this._body);
  final String _body;

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  Future<HttpClientResponse> close() async => _FakeResponse(_body);
}

class _FakeHeaders extends Fake implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _FakeResponse extends Fake implements HttpClientResponse {
  _FakeResponse(this._body);
  final String _body;
  late final Stream<List<int>> _stream = Stream.value(utf8.encode(_body));

  @override
  Stream<S> transform<S>(StreamTransformer<List<int>, S> streamTransformer) =>
      _stream.transform(streamTransformer);
}
