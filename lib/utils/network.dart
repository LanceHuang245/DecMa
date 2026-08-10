import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

enum AppFailureKind {
  cancelled,
  networkUnavailable,
  timeout,
  authentication,
  rateLimited,
  upstream,
  invalidResponse,
  configuration,
}

class AppFailure implements Exception {
  const AppFailure({
    required this.kind,
    this.provider,
    this.statusCode,
    this.retryAfter,
  });

  final AppFailureKind kind;
  final String? provider;
  final int? statusCode;
  final Duration? retryAfter;

  factory AppFailure.fromDio(DioException error, {required String provider}) {
    if (error.type == DioExceptionType.cancel) {
      return AppFailure(kind: AppFailureKind.cancelled, provider: provider);
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return AppFailure(kind: AppFailureKind.timeout, provider: provider);
    }
    if (error.response != null) {
      return AppFailure.fromResponse(error.response!, provider: provider);
    }
    return AppFailure(
      kind:
          error.type == DioExceptionType.connectionError ||
              error.type == DioExceptionType.badCertificate
          ? AppFailureKind.networkUnavailable
          : AppFailureKind.upstream,
      provider: provider,
    );
  }

  factory AppFailure.fromResponse(
    Response<dynamic> response, {
    required String provider,
  }) {
    final statusCode = response.statusCode;
    final retryAfter = _retryAfter(response.headers.value('retry-after'));
    return AppFailure(
      kind: switch (statusCode) {
        401 || 403 => AppFailureKind.authentication,
        408 || 504 => AppFailureKind.timeout,
        429 => AppFailureKind.rateLimited,
        final value when value != null && value >= 500 =>
          AppFailureKind.upstream,
        _ => AppFailureKind.invalidResponse,
      },
      provider: provider,
      statusCode: statusCode,
      retryAfter: retryAfter,
    );
  }

  static Duration? _retryAfter(String? value) {
    final seconds = int.tryParse(value ?? '');
    return seconds == null ? null : Duration(seconds: seconds);
  }

  String get message {
    final prefix = provider == null ? '' : '$provider：';
    return switch (kind) {
      AppFailureKind.cancelled => '$prefix请求已取消。',
      AppFailureKind.networkUnavailable => '$prefix网络不可用，请检查连接后重试。',
      AppFailureKind.timeout => '$prefix请求超时，请稍后重试。',
      AppFailureKind.authentication => '$prefix认证失败，请检查 API Key 或登录状态。',
      AppFailureKind.rateLimited => '$prefix请求过于频繁，请稍后重试。',
      AppFailureKind.upstream => '$prefix服务暂时不可用，请稍后重试。',
      AppFailureKind.invalidResponse => '$prefix服务返回了无效响应。',
      AppFailureKind.configuration => '$prefix服务配置不完整。',
    };
  }

  @override
  String toString() => message;
}

const networkTimeout = Duration(seconds: 30);

// Create identical plain-text Dio clients without logging secrets or payloads.
Dio createDio() {
  final dio = Dio(
    BaseOptions(
      connectTimeout: networkTimeout,
      sendTimeout: networkTimeout,
      receiveTimeout: networkTimeout,
      responseType: ResponseType.plain,
      validateStatus: (_) => true,
    ),
  );
  if (kDebugMode) dio.interceptors.add(_DebugNetworkInterceptor());
  return dio;
}

Options networkOptions({
  Duration timeout = networkTimeout,
  Map<String, dynamic>? headers,
  String? contentType,
}) => Options(
  connectTimeout: timeout,
  sendTimeout: timeout,
  receiveTimeout: timeout,
  responseType: ResponseType.plain,
  headers: headers,
  contentType: contentType,
);

Future<T> runNetworkRequest<T>(
  String provider,
  Future<T> Function() request,
) async {
  try {
    return await request();
  } on DioException catch (error) {
    throw AppFailure.fromDio(error, provider: provider);
  }
}

void requireSuccessfulResponse(
  Response<dynamic> response, {
  required String provider,
}) {
  final statusCode = response.statusCode ?? 0;
  if (statusCode < 200 || statusCode >= 300) {
    throw AppFailure.fromResponse(response, provider: provider);
  }
}

bool isRequestCancelled(Object error) =>
    error is AppFailure && error.kind == AppFailureKind.cancelled;

class _DebugNetworkInterceptor extends Interceptor {
  static const _startedAt = '_networkStartedAt';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startedAt] = DateTime.now();
    if (kDebugMode) debugPrint('[HTTP] ${_requestLabel(options)}');
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _logResult(response.requestOptions, response.statusCode);
    handler.next(response);
  }

  @override
  void onError(DioException error, ErrorInterceptorHandler handler) {
    _logResult(error.requestOptions, error.response?.statusCode);
    handler.next(error);
  }

  // Never include query parameters because several providers put API keys there.
  String _requestLabel(RequestOptions options) =>
      '${options.method} ${options.uri.replace(query: '')}';

  void _logResult(RequestOptions options, int? statusCode) {
    final startedAt = options.extra[_startedAt] as DateTime?;
    final elapsed = startedAt == null
        ? ''
        : ' ${DateTime.now().difference(startedAt).inMilliseconds}ms';
    if (kDebugMode) {
      debugPrint(
        '[HTTP] ${_requestLabel(options)} -> ${statusCode ?? 'error'}$elapsed',
      );
    }
  }
}
