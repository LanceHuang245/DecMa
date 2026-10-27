import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../app_constants.dart';
import '../l10n/app_languages.dart';

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
    this.detail,
  });

  final AppFailureKind kind;
  final String? provider;
  final int? statusCode;
  final Duration? retryAfter;
  final String? detail;

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
    final l10n = appL10n;
    final prefix = provider == null ? '' : l10n.failurePrefix(provider!);
    final summary =
        prefix +
        switch (kind) {
          AppFailureKind.cancelled => l10n.failureCancelled,
          AppFailureKind.networkUnavailable => l10n.failureNetworkUnavailable,
          AppFailureKind.timeout => l10n.failureTimeout,
          AppFailureKind.authentication => l10n.failureAuthentication,
          AppFailureKind.rateLimited => l10n.failureRateLimited,
          AppFailureKind.upstream => l10n.failureUpstream,
          AppFailureKind.invalidResponse => l10n.failureInvalidResponse,
          AppFailureKind.configuration => l10n.failureConfiguration,
        };
    return detail == null ? summary : '$summary $detail';
  }

  @override
  String toString() => message;
}

const networkTimeout = Duration(seconds: 30);

// Stop awaiting cooperative work promptly; callers still clean up its transport.
Future<T> cancellable<T>(Future<T> work, Future<void>? stop) {
  if (stop == null) return work;
  return Future.any([
    work,
    stop.then<T>((_) => throw const AppFailure(kind: AppFailureKind.cancelled)),
  ]);
}

// Create identical plain-text Dio clients without logging secrets or payloads.
Dio createDio() {
  final dio = Dio(
    BaseOptions(
      connectTimeout: networkTimeout,
      sendTimeout: networkTimeout,
      receiveTimeout: networkTimeout,
      responseType: ResponseType.plain,
      validateStatus: (_) => true,
      headers: {'User-Agent': AppConstants.userAgent},
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
