import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiKeyStatus {
  const ApiKeyStatus({
    this.hasLlmKey = false,
    this.hasCodexOAuth = false,
    this.hasNansenKey = false,
    this.hasCoinalyzeKey = false,
  });

  final bool hasLlmKey;
  final bool hasCodexOAuth;
  final bool hasNansenKey;
  final bool hasCoinalyzeKey;
}

class CodexOAuthCredentials {
  const CodexOAuthCredentials({
    required this.accessToken,
    required this.refreshToken,
    required this.accountId,
    required this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final String accountId;
  final DateTime expiresAt;
}

class ApiKeyUpdates {
  const ApiKeyUpdates({this.llmKey, this.nansenKey, this.coinalyzeKey});

  final String? llmKey;
  final String? nansenKey;
  final String? coinalyzeKey;
}

class SecureKeyStore {
  SecureKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _llmKey = 'decma.llm_api_key';
  static const _codexAccessToken = 'decma.codex.access_token';
  static const _codexRefreshToken = 'decma.codex.refresh_token';
  static const _codexAccountId = 'decma.codex.account_id';
  static const _codexExpiresAt = 'decma.codex.expires_at';
  static const _nansenKey = 'decma.nansen_api_key';
  static const _coinalyzeKey = 'decma.coinalyze_api_key';
  final FlutterSecureStorage _storage;

  Future<ApiKeyStatus> status() async {
    final saved = await Future.wait([
      _storage.containsKey(key: _llmKey),
      _storage.containsKey(key: _codexAccessToken),
      _storage.containsKey(key: _codexRefreshToken),
      _storage.containsKey(key: _codexAccountId),
      _storage.containsKey(key: _codexExpiresAt),
      _storage.containsKey(key: _nansenKey),
      _storage.containsKey(key: _coinalyzeKey),
    ]);
    return ApiKeyStatus(
      hasLlmKey: saved[0],
      hasCodexOAuth: saved[1] && saved[2] && saved[3] && saved[4],
      hasNansenKey: saved[5],
      hasCoinalyzeKey: saved[6],
    );
  }

  // Blank fields mean "keep existing key" so settings never need to read it back.
  Future<void> update(ApiKeyUpdates updates) async {
    if (updates.llmKey case final key?) {
      await _storage.write(key: _llmKey, value: key);
    }
    if (updates.nansenKey case final key?) {
      await _storage.write(key: _nansenKey, value: key);
    }
    if (updates.coinalyzeKey case final key?) {
      await _storage.write(key: _coinalyzeKey, value: key);
    }
  }

  Future<String?> readLlmKey() => _storage.read(key: _llmKey);

  Future<CodexOAuthCredentials?> readCodexOAuth() async {
    final values = await Future.wait([
      _storage.read(key: _codexAccessToken),
      _storage.read(key: _codexRefreshToken),
      _storage.read(key: _codexAccountId),
      _storage.read(key: _codexExpiresAt),
    ]);
    final expiresAt = values[3] == null ? null : DateTime.tryParse(values[3]!);
    if (values[0] == null ||
        values[1] == null ||
        values[2] == null ||
        expiresAt == null) {
      return null;
    }
    return CodexOAuthCredentials(
      accessToken: values[0]!,
      refreshToken: values[1]!,
      accountId: values[2]!,
      expiresAt: expiresAt,
    );
  }

  // OAuth credentials never leave encrypted storage between app launches.
  Future<void> saveCodexOAuth(CodexOAuthCredentials credentials) =>
      Future.wait([
        _storage.write(key: _codexAccessToken, value: credentials.accessToken),
        _storage.write(
          key: _codexRefreshToken,
          value: credentials.refreshToken,
        ),
        _storage.write(key: _codexAccountId, value: credentials.accountId),
        _storage.write(
          key: _codexExpiresAt,
          value: credentials.expiresAt.toUtc().toIso8601String(),
        ),
      ]).then((_) {});

  Future<String?> readNansenKey() => _storage.read(key: _nansenKey);
  Future<String?> readCoinalyzeKey() => _storage.read(key: _coinalyzeKey);
}
