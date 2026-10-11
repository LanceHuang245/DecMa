import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:decma/models/trading_models.dart';
import 'package:decma/utils/network.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genkit/genkit.dart';

import 'llm_fixtures.dart';
import 'agent_fixtures.dart';

void main() {
  // An actual socket must close on stop, not just stop updating the draft UI.
  for (final provider in LlmProvider.values) {
    test('$provider aborts an in-flight HTTP response', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final disconnected = Completer<void>();
      final cancel = CancellationController();
      final sockets = <Socket>[];
      final requests = server.listen((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.headers.chunkedTransferEncoding = true;
        // Observe the TCP peer closing, not HttpResponse.done awaiting close().
        final socket = await request.response.detachSocket(writeHeaders: true);
        sockets.add(socket);
        socket.listen(
          (_) {},
          onDone: () {
            if (!disconnected.isCompleted) disconnected.complete();
          },
          onError: (Object _) {
            if (!disconnected.isCompleted) disconnected.complete();
          },
        );
        final bytes = utf8.encode(firstTextEvent(provider));
        socket.write('${bytes.length.toRadixString(16)}\r\n');
        socket.add(bytes);
        socket.write('\r\n');
        await socket.flush();
      });
      try {
        await expectLater(
          generateReply(
            settings: LlmSettings(
              provider: provider,
              endpoint:
                  'http://127.0.0.1:${server.port}${provider == LlmProvider.anthropic ? '' : '/v1'}',
              model: 'test-model',
            ),
            apiKey: 'key',
            accountId: 'account-1',
            input: 'Hi',
            tools: const [],
            cancel: cancel.token,
            onText: (text) {
              if (text == 'Hello') cancel.cancel();
            },
          ),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.kind,
              'kind',
              AppFailureKind.cancelled,
            ),
          ),
        );
        await disconnected.future.timeout(const Duration(seconds: 2));
      } finally {
        for (final socket in sockets) {
          socket.destroy();
        }
        await requests.cancel();
        await server.close(force: true);
      }
    });
  }
}
