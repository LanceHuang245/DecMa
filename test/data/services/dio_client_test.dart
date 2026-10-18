import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:decma/utils/dio_client.dart';
import 'package:decma/utils/network.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  // SDK JSON is already encoded and must reach Dio unchanged, even on errors.
  test(
    'Dio SDK client preserves raw bytes, headers and streaming HTTP errors',
    () async {
      final adapter = _Adapter();
      final dio = createDio()..httpClientAdapter = adapter;
      final client = DioClient(dio: dio);
      final request =
          http.Request('POST', Uri.parse('https://test.local/responses'))
            ..headers['content-type'] = 'application/json'
            ..headers['authorization'] = 'Bearer test-key'
            ..body = '{"input":"你好"}';
      try {
        final response = await client.send(request);
        expect(utf8.decode(adapter.body), '{"input":"你好"}');
        expect(adapter.options!.headers['authorization'], 'Bearer test-key');
        expect(response.statusCode, 401);
        expect(await response.stream.bytesToString(), '{"error":"bad key"}');
        expect(response.headers['content-type'], 'application/json');
        client.close();
        expect(adapter.closed, false);
      } finally {
        dio.close(force: true);
      }
    },
  );

  // Honor the SDK's request-local Abortable contract without closing shared Dio.
  test('Dio SDK client aborts a pending SDK request', () async {
    final adapter = _Adapter(stall: true);
    final dio = createDio()..httpClientAdapter = adapter;
    final client = DioClient(dio: dio);
    final abort = Completer<void>();
    final work = client.send(
      http.AbortableRequest(
        'GET',
        Uri.parse('https://test.local'),
        abortTrigger: abort.future,
      ),
    );
    final assertion = expectLater(
      work,
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.cancel,
        ),
      ),
    );
    await adapter.started.future;
    abort.complete();
    await assertion.timeout(const Duration(seconds: 2));
    adapter.release.complete(ResponseBody.fromString('', 200));
    client.close();
    expect(adapter.closed, false);
    dio.close(force: true);
  });
}

// Replace only the HTTP boundary so the real Dio stream/cancellation path runs.
class _Adapter implements HttpClientAdapter {
  _Adapter({this.stall = false});
  final bool stall;
  final started = Completer<void>();
  final release = Completer<ResponseBody>();
  RequestOptions? options;
  List<int> body = [];
  bool closed = false;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    this.options = options;
    if (requestStream != null) {
      body = await requestStream.expand((bytes) => bytes).toList();
    }
    started.complete();
    if (stall) return release.future;
    return ResponseBody.fromString(
      '{"error":"bad key"}',
      401,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }
}
