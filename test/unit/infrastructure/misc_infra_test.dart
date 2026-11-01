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
      final r = await HttpOverrides.runZoned(
        fetchLatestQuickguiRelease,
        createHttpClient: (_) =>
            _FakeHttpClient('{"tag_name": "1.2.3", "other": 1}'),
      );
      expect(r.version, '1.2.3');
      expect(r.errorKind, isNull);
    });

    test('flags a "response" error when the payload has no tag', () async {
      final r = await HttpOverrides.runZoned(
        fetchLatestQuickguiRelease,
        createHttpClient: (_) => _FakeHttpClient('{"name": "release"}'),
      );
      expect(r.version, isEmpty);
      expect(r.errorKind, 'response');
    });

    test('flags a "service" error on non-200 HTTP status', () async {
      final r = await HttpOverrides.runZoned(
        fetchLatestQuickguiRelease,
        createHttpClient: (_) =>
            _FakeHttpClient('rate limited', statusCode: 429),
      );
      expect(r.version, isEmpty);
      expect(r.errorKind, 'service');
    });

    test('flags a "connection" error when the request fails', () async {
      final r = await HttpOverrides.runZoned(
        fetchLatestQuickguiRelease,
        createHttpClient: (_) => _FailingHttpClient(),
      );
      expect(r.version, isEmpty);
      expect(r.errorKind, 'connection');
    });
  });
}

class _FakeHttpClient extends Fake implements HttpClient {
  _FakeHttpClient(this._body, {this.statusCode = 200});
  final String _body;
  final int statusCode;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _FakeRequest(_body, statusCode);
}

class _FailingHttpClient extends Fake implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      throw const SocketException('offline');
}

class _FakeRequest extends Fake implements HttpClientRequest {
  _FakeRequest(this._body, this._statusCode);
  final String _body;
  final int _statusCode;

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  Future<HttpClientResponse> close() async => _FakeResponse(_body, _statusCode);
}

class _FakeHeaders extends Fake implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _FakeResponse extends Fake implements HttpClientResponse {
  _FakeResponse(this._body, this._statusCode);
  final String _body;
  final int _statusCode;
  late final Stream<List<int>> _stream = Stream.value(utf8.encode(_body));

  @override
  int get statusCode => _statusCode;

  @override
  Stream<S> transform<S>(StreamTransformer<List<int>, S> streamTransformer) =>
      _stream.transform(streamTransformer);
}
