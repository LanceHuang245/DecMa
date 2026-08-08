import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/trading_models.dart';

class ApiKeyStatus {
  const ApiKeyStatus({
    this.hasLlmKey = false,
    this.llmKeyConnectionIds = const {},
    this.hasCodexOAuth = false,
    this.hasNansenKey = false,
    this.hasCoinalyzeKey = false,
    this.hasFinnhubKey = false,
  });

  final bool hasLlmKey;
  final Set<String> llmKeyConnectionIds;
  final bool hasCodexOAuth;
  final bool hasNansenKey;
  final bool hasCoinalyzeKey;
  final bool hasFinnhubKey;

  bool hasLlmKeyFor(String connectionId) =>
      llmKeyConnectionIds.contains(connectionId);
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
  const ApiKeyUpdates({
    this.llmKey,
    this.llmConnectionId = LlmSettings.defaultId,
    this.nansenKey,
    this.coinalyzeKey,
    this.finnhubKey,
  });

  final String? llmKey;
  final String llmConnectionId;
  final String? nansenKey;
  final String? coinalyzeKey;
  final String? finnhubKey;
}

class SecureKeyStore {
  SecureKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _legacyLlmKey = 'decma.llm_api_key';
  static const _codexAccessToken = 'decma.codex.access_token';
  static const _codexRefreshToken = 'decma.codex.refresh_token';
  static const _codexAccountId = 'decma.codex.account_id';
  static const _codexExpiresAt = 'decma.codex.expires_at';
  static const _nansenKey = 'decma.nansen_api_key';
  static const _coinalyzeKey = 'decma.coinalyze_api_key';
  static const _finnhubKey = 'decma.finnhub_api_key';
  final FlutterSecureStorage _storage;

  Future<ApiKeyStatus> status({
    Iterable<String> llmConnectionIds = const [LlmSettings.defaultId],
  }) async {
    final connectionIds = llmConnectionIds.toSet();
    if (connectionIds.isEmpty) {
      connectionIds.add(LlmSettings.defaultId);
    }
    final saved = await Future.wait<bool>([
      for (final id in connectionIds) _hasLlmKey(id),
      _storage.containsKey(key: _codexAccessToken),
      _storage.containsKey(key: _codexRefreshToken),
      _storage.containsKey(key: _codexAccountId),
      _storage.containsKey(key: _codexExpiresAt),
      _storage.containsKey(key: _nansenKey),
      _storage.containsKey(key: _coinalyzeKey),
      _storage.containsKey(key: _finnhubKey),
    ]);
    final keyedConnections = <String>{};
    for (var index = 0; index < connectionIds.length; index++) {
      if (saved[index]) {
        keyedConnections.add(connectionIds.elementAt(index));
      }
    }
    return ApiKeyStatus(
      hasLlmKey: keyedConnections.isNotEmpty,
      llmKeyConnectionIds: keyedConnections,
      hasCodexOAuth:
          saved[connectionIds.length] &&
          saved[connectionIds.length + 1] &&
          saved[connectionIds.length + 2] &&
          saved[connectionIds.length + 3],
      hasNansenKey: saved[connectionIds.length + 4],
      hasCoinalyzeKey: saved[connectionIds.length + 5],
      hasFinnhubKey: saved[connectionIds.length + 6],
    );
  }

  // Blank fields mean "keep existing key" so settings never need to read it back.
  Future<void> update(ApiKeyUpdates updates) async {
    if (updates.llmKey case final key?) {
      await _storage.write(
        key: _llmKeyFor(updates.llmConnectionId),
        value: key,
      );
    }
    if (updates.nansenKey case final key?) {
      await _storage.write(key: _nansenKey, value: key);
    }
    if (updates.coinalyzeKey case final key?) {
      await _storage.write(key: _coinalyzeKey, value: key);
    }
    if (updates.finnhubKey case final key?) {
      await _storage.write(key: _finnhubKey, value: key);
    }
  }

  Future<String?> readLlmKey({
    String connectionId = LlmSettings.defaultId,
  }) async {
    final saved = await _storage.read(key: _llmKeyFor(connectionId));
    if (saved != null || connectionId != LlmSettings.defaultId) return saved;
    return _storage.read(key: _legacyLlmKey);
  }

  String _llmKeyFor(String connectionId) => 'decma.llm_api_key.$connectionId';

  Future<bool> _hasLlmKey(String connectionId) async =>
      await _storage.containsKey(key: _llmKeyFor(connectionId)) ||
      (connectionId == LlmSettings.defaultId &&
          await _storage.containsKey(key: _legacyLlmKey));

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
  Future<String?> readFinnhubKey() => _storage.read(key: _finnhubKey);
}
