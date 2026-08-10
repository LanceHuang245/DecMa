import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../app_constants.dart';
import '../utils/network.dart';
import 'secure_key_store.dart';

class OpenAiCodexAuthService {
  OpenAiCodexAuthService({
    SecureKeyStore? keyStore,
    Dio? dio,
    Future<void> Function(Uri uri)? openBrowser,
  }) : _keyStore = keyStore ?? SecureKeyStore(),
       _dio = dio ?? createDio(),
       _openBrowser = openBrowser ?? _openSystemBrowser;

  static const _clientId = 'app_EMoamEEZ73f0CkXaXp7hrann';
  static const _redirectUri = 'http://localhost:1455/auth/callback';
  static const _issuer = 'https://auth.openai.com';
  static const _codexBase = 'https://chatgpt.com/backend-api/codex';
  final SecureKeyStore _keyStore;
  final Dio _dio;
  final Future<void> Function(Uri uri) _openBrowser;

  Future<CodexOAuthCredentials> currentCredentials() async {
    final saved = await _keyStore.readCodexOAuth();
    if (saved == null) throw Exception('请先登录 ChatGPT。');
    if (saved.expiresAt.isAfter(
      DateTime.now().add(const Duration(minutes: 5)),
    )) {
      return saved;
    }
    return _refresh(saved);
  }

  Future<List<String>> signIn() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 1455);
    final verifier = _randomUrlSafe(64);
    final challenge = base64UrlEncode(
      sha256.convert(utf8.encode(verifier)).bytes,
    ).replaceAll('=', '');
    final state = _randomUrlSafe(32);
    try {
      final authorize = Uri.parse('$_issuer/oauth/authorize').replace(
        queryParameters: {
          'response_type': 'code',
          'client_id': _clientId,
          'redirect_uri': _redirectUri,
          'scope':
              'openid profile email offline_access '
              'api.connectors.read api.connectors.invoke',
          'audience': 'https://api.openai.com/v1',
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
          'state': state,
          'codex_cli_simplified_flow': 'true',
          'id_token_add_organizations': 'true',
        },
      );
      // OAuth uses the system browser so credentials are entered only on OpenAI.
      await _openBrowser(authorize);
      final request = await server.first.timeout(const Duration(minutes: 3));
      final values = request.uri.queryParameters;
      final matchesState = values['state'] == state;
      final code = values['code'];
      final error = values['error_description'] ?? values['error'];
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        matchesState && code != null
            ? '<h2>OpenAI Codex connected</h2><p>You can return to ${AppConstants.appName}.</p>'
            : '<h2>OpenAI Codex sign-in failed</h2><p>You can close this page.</p>',
      );
      await request.response.close();
      if (!matchesState || code == null) {
        throw Exception(error ?? 'OAuth 回调无效，请重试。');
      }
      final credentials = await _exchangeCode(code, verifier);
      await _keyStore.saveCodexOAuth(credentials);
      return _fetchModels(credentials);
    } finally {
      await server.close(force: true);
    }
  }

  Future<List<String>> fetchModels() async =>
      _fetchModels(await currentCredentials());

  Future<CodexOAuthCredentials> _exchangeCode(String code, String verifier) =>
      _requestTokens({
        'grant_type': 'authorization_code',
        'client_id': _clientId,
        'code': code,
        'redirect_uri': _redirectUri,
        'code_verifier': verifier,
      });

  Future<CodexOAuthCredentials> _refresh(CodexOAuthCredentials saved) async {
    final refreshed = await _requestTokens({
      'grant_type': 'refresh_token',
      'client_id': _clientId,
      'refresh_token': saved.refreshToken,
    }, fallbackRefreshToken: saved.refreshToken);
    await _keyStore.saveCodexOAuth(refreshed);
    return refreshed;
  }

  Future<CodexOAuthCredentials> _requestTokens(
    Map<String, String> body, {
    String? fallbackRefreshToken,
  }) async {
    final response = await runNetworkRequest(
      'OpenAI Codex',
      () => _dio.postUri<String>(
        Uri.parse('$_issuer/oauth/token'),
        data: body,
        options: networkOptions(
          headers: {'Content-Type': Headers.formUrlEncodedContentType},
          contentType: Headers.formUrlEncodedContentType,
        ),
      ),
    );
    requireSuccessfulResponse(response, provider: 'OpenAI Codex');
    final values = _json(response.data ?? '');
    final accessToken = values['access_token']?.toString();
    final refreshToken =
        values['refresh_token']?.toString() ?? fallbackRefreshToken;
    final accountId = _accountId(
      values['id_token']?.toString() ?? accessToken ?? '',
    );
    if (accessToken == null || refreshToken == null || accountId == null) {
      throw const AppFailure(
        kind: AppFailureKind.invalidResponse,
        provider: 'OpenAI Codex',
      );
    }
    final seconds =
        int.tryParse(values['expires_in']?.toString() ?? '') ?? 3600;
    return CodexOAuthCredentials(
      accessToken: accessToken,
      refreshToken: refreshToken,
      accountId: accountId,
      expiresAt: DateTime.now().add(Duration(seconds: seconds)),
    );
  }

  Future<List<String>> _fetchModels(CodexOAuthCredentials credentials) async {
    final response = await runNetworkRequest(
      'OpenAI Codex',
      () => _dio.getUri<String>(
        Uri.parse('$_codexBase/models').replace(
          queryParameters: {'client_version': AppConstants.codexClientVersion},
        ),
        options: networkOptions(headers: _headers(credentials)),
      ),
    );
    requireSuccessfulResponse(response, provider: 'OpenAI Codex');
    final values = _json(response.data ?? '');
    final models = <String>{};
    for (final list in [values['models'], values['data']]) {
      if (list is! List) continue;
      for (final item in list.whereType<Map>()) {
        final model = item['slug'] ?? item['id'] ?? item['model'];
        if (model is String && model.isNotEmpty) models.add(model);
      }
    }
    return models.toList()..sort();
  }

  Map<String, String> _headers(CodexOAuthCredentials credentials) => {
    'Authorization': 'Bearer ${credentials.accessToken}',
    'ChatGPT-Account-Id': credentials.accountId,
    'OpenAI-Beta': 'responses=experimental',
    'originator': 'codex_cli_rs',
    'Accept': 'application/json',
  };

  String? _accountId(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = _json(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final auth = payload['https://api.openai.com/auth'];
      final organizations = payload['organizations'];
      final firstOrganization =
          organizations is List && organizations.isNotEmpty
          ? organizations.first
          : null;
      return (auth is Map ? auth['chatgpt_account_id'] : null)?.toString() ??
          payload['chatgpt_account_id']?.toString() ??
          (firstOrganization is Map ? firstOrganization['id'] : null)
              ?.toString();
    } catch (_) {
      return null;
    }
  }

  String _randomUrlSafe(int length) {
    const characters =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => characters[random.nextInt(characters.length)],
    ).join();
  }

  Map<String, dynamic> _json(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map
          ? decoded.map((key, value) => MapEntry(key.toString(), value))
          : const {};
    } catch (_) {
      return const {};
    }
  }

  static Future<void> _openSystemBrowser(Uri uri) async {
    if (Platform.isWindows) {
      await Process.start('rundll32', [
        'url.dll,FileProtocolHandler',
        uri.toString(),
      ], mode: ProcessStartMode.detached);
      return;
    }
    if (Platform.isMacOS) {
      await Process.start('open', [
        uri.toString(),
      ], mode: ProcessStartMode.detached);
      return;
    }
    await Process.start('xdg-open', [
      uri.toString(),
    ], mode: ProcessStartMode.detached);
  }
}
