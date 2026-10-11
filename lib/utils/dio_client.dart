import 'dart:async';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

import 'network.dart';

// Keep package:http only at the SDK boundary; Dio performs all actual I/O.
class DioClient extends http.BaseClient {
  DioClient({Dio? dio, this.cancel, this.timeout = networkTimeout})
    : _dio = dio ?? createDio(),
      _ownsDio = dio == null;
  final Dio _dio;
  final bool _ownsDio;
  final CancelToken? cancel;
  final Duration timeout;
  final _pending = <CancelToken>{};
  bool _closed = false;

  // Preserve encoded bytes and non-2xx responses for the SDK's own decoders.
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw http.ClientException('Client is closed', request.url);
    final token = CancelToken();
    _pending.add(token);
    if (cancel?.isCancelled ?? false) token.cancel();
    cancel?.whenCancel.then((_) => token.cancel());
    if (request is http.Abortable) {
      request.abortTrigger?.then((_) => token.cancel());
    }
    try {
      final bytes = await request.finalize().toBytes();
      final response = await _dio.requestUri<ResponseBody>(
        request.url,
        data: bytes.isEmpty ? null : bytes,
        cancelToken: token,
        options: Options(
          method: request.method,
          headers: request.headers,
          responseType: ResponseType.stream,
          validateStatus: (_) => true,
          followRedirects: request.followRedirects,
          maxRedirects: request.maxRedirects,
          sendTimeout: timeout,
          receiveTimeout: timeout,
        ),
      );
      return http.StreamedResponse(
        _stream(response.data!, token),
        response.statusCode!,
        request: request,
        reasonPhrase: response.statusMessage,
        isRedirect: response.isRedirect,
        headers: response.headers.map.map(
          (name, values) => MapEntry(name, values.join(',')),
        ),
      );
    } catch (_) {
      _pending.remove(token);
      rethrow;
    }
  }

  // Cancelling a response subscription must abort its socket as well.
  Stream<List<int>> _stream(ResponseBody body, CancelToken token) async* {
    var completed = false;
    try {
      yield* body.stream;
      completed = true;
    } finally {
      _pending.remove(token);
      if (!completed) token.cancel();
    }
  }

  // SDK clients may close their adapter, but never a caller-owned shared Dio.
  @override
  void close() {
    _closed = true;
    for (final token in _pending.toList()) {
      token.cancel();
    }
    _pending.clear();
    if (_ownsDio) _dio.close(force: true);
  }
}

// Scope SDK-created clients (including MCP) without globally replacing networking.
T withDioClient<T>(T Function() work, {Dio? dio, CancelToken? cancel}) =>
    http.runWithClient(work, () => DioClient(dio: dio, cancel: cancel));
