import 'dart:async';
import 'dart:io';

import 'package:decma/data/services/openai_codex_oauth.dart';
import 'package:decma/utils/network.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Closing a login view must free the real registered localhost callback port.
  test('stopping OAuth callback waiting releases port 1455', () async {
    final opened = Completer<void>();
    final cancel = CancelToken();
    final auth = OpenAiCodexAuthService(
      openBrowser: (_) async {
        opened.complete();
      },
    );
    try {
      final assertion = expectLater(
        auth.signIn(cancelToken: cancel),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.kind,
            'kind',
            AppFailureKind.cancelled,
          ),
        ),
      );
      await opened.future;
      cancel.cancel();
      await assertion.timeout(const Duration(seconds: 2));
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 1455);
      await server.close(force: true);
    } finally {
      auth.dispose();
    }
  });
}
