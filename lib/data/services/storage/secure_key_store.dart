import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../domain/models/app_settings.dart';
import 'storage_keys.dart';

class ApiKeyStatus {
  const ApiKeyStatus({
    this.hasLlmKey = false,
    this.llmKeyConnectionIds = const {},
    this.hasCodexOAuth = false,
    this.hasBybitApiKey = false,
    this.hasBybitApiSecret = false,
    this.hasNansenKey = false,
    this.hasCoinalyzeKey = false,
    this.hasFinnhubKey = false,
    this.hasMarketauxKey = false,
  });

  final bool hasLlmKey;
  final Set<String> llmKeyConnectionIds;
  final bool hasCodexOAuth;
  final bool hasBybitApiKey;
  final bool hasBybitApiSecret;
  final bool hasNansenKey;
  final bool hasCoinalyzeKey;
  final bool hasFinnhubKey;
  final bool hasMarketauxKey;

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
    this.bybitApiKey,
    this.bybitApiSecret,
    this.nansenKey,
    this.coinalyzeKey,
    this.finnhubKey,
    this.marketauxKey,
  });

  final String? llmKey;
  final String llmConnectionId;
  final String? bybitApiKey;
  final String? bybitApiSecret;
  final String? nansenKey;
  final String? coinalyzeKey;
  final String? finnhubKey;
  final String? marketauxKey;
}

class SecureKeyStore {
  SecureKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

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
      _storage.containsKey(key: StorageKeys.codexAccessToken),
      _storage.containsKey(key: StorageKeys.codexRefreshToken),
      _storage.containsKey(key: StorageKeys.codexAccountId),
      _storage.containsKey(key: StorageKeys.codexExpiresAt),
      _storage.containsKey(key: StorageKeys.bybitApiKey),
      _storage.containsKey(key: StorageKeys.bybitApiSecret),
      _storage.containsKey(key: StorageKeys.nansenApiKey),
      _storage.containsKey(key: StorageKeys.coinalyzeApiKey),
      _storage.containsKey(key: StorageKeys.finnhubApiKey),
      _storage.containsKey(key: StorageKeys.marketauxApiKey),
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
      hasBybitApiKey: saved[connectionIds.length + 4],
      hasBybitApiSecret: saved[connectionIds.length + 5],
      hasNansenKey: saved[connectionIds.length + 6],
      hasCoinalyzeKey: saved[connectionIds.length + 7],
      hasFinnhubKey: saved[connectionIds.length + 8],
      hasMarketauxKey: saved[connectionIds.length + 9],
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
    if (updates.bybitApiKey case final key?) {
      await _storage.write(key: StorageKeys.bybitApiKey, value: key);
    }
    if (updates.bybitApiSecret case final secret?) {
      await _storage.write(key: StorageKeys.bybitApiSecret, value: secret);
    }
    if (updates.nansenKey case final key?) {
      await _storage.write(key: StorageKeys.nansenApiKey, value: key);
    }
    if (updates.coinalyzeKey case final key?) {
      await _storage.write(key: StorageKeys.coinalyzeApiKey, value: key);
    }
    if (updates.finnhubKey case final key?) {
      await _storage.write(key: StorageKeys.finnhubApiKey, value: key);
    }
    if (updates.marketauxKey case final key?) {
      await _storage.write(key: StorageKeys.marketauxApiKey, value: key);
    }
  }

  Future<String?> readLlmKey({String connectionId = LlmSettings.defaultId}) =>
      _storage.read(key: _llmKeyFor(connectionId));

  String _llmKeyFor(String connectionId) =>
      '${StorageKeys.llmApiKeyPrefix}$connectionId';

  Future<bool> _hasLlmKey(String connectionId) =>
      _storage.containsKey(key: _llmKeyFor(connectionId));

  Future<CodexOAuthCredentials?> readCodexOAuth() async {
    final values = await Future.wait([
      _storage.read(key: StorageKeys.codexAccessToken),
      _storage.read(key: StorageKeys.codexRefreshToken),
      _storage.read(key: StorageKeys.codexAccountId),
      _storage.read(key: StorageKeys.codexExpiresAt),
    ]);
    if (values[0] == null) return null;
    final expiresAt = DateTime.parse(values[3]!);
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
        _storage.write(
          key: StorageKeys.codexAccessToken,
          value: credentials.accessToken,
        ),
        _storage.write(
          key: StorageKeys.codexRefreshToken,
          value: credentials.refreshToken,
        ),
        _storage.write(
          key: StorageKeys.codexAccountId,
          value: credentials.accountId,
        ),
        _storage.write(
          key: StorageKeys.codexExpiresAt,
          value: credentials.expiresAt.toUtc().toIso8601String(),
        ),
      ]).then((_) {});

  Future<String?> readNansenKey() =>
      _storage.read(key: StorageKeys.nansenApiKey);
  Future<String?> readBybitApiKey() =>
      _storage.read(key: StorageKeys.bybitApiKey);
  Future<String?> readBybitApiSecret() =>
      _storage.read(key: StorageKeys.bybitApiSecret);
  Future<String?> readCoinalyzeKey() =>
      _storage.read(key: StorageKeys.coinalyzeApiKey);
  Future<String?> readFinnhubKey() =>
      _storage.read(key: StorageKeys.finnhubApiKey);
  Future<String?> readMarketauxKey() =>
      _storage.read(key: StorageKeys.marketauxApiKey);
}
