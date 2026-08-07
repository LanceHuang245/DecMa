import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiKeyStatus {
  const ApiKeyStatus({this.hasLlmKey = false, this.hasNansenKey = false});

  final bool hasLlmKey;
  final bool hasNansenKey;
}

class ApiKeyUpdates {
  const ApiKeyUpdates({this.llmKey, this.nansenKey});

  final String? llmKey;
  final String? nansenKey;
}

class SecureKeyStore {
  SecureKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _llmKey = 'decma.llm_api_key';
  static const _nansenKey = 'decma.nansen_api_key';
  final FlutterSecureStorage _storage;

  Future<ApiKeyStatus> status() async {
    final saved = await Future.wait([
      _storage.containsKey(key: _llmKey),
      _storage.containsKey(key: _nansenKey),
    ]);
    return ApiKeyStatus(hasLlmKey: saved[0], hasNansenKey: saved[1]);
  }

  // Blank fields mean "keep existing key" so settings never need to read it back.
  Future<void> update(ApiKeyUpdates updates) async {
    if (updates.llmKey case final key?) {
      await _storage.write(key: _llmKey, value: key);
    }
    if (updates.nansenKey case final key?) {
      await _storage.write(key: _nansenKey, value: key);
    }
  }

  Future<String?> readLlmKey() => _storage.read(key: _llmKey);
  Future<String?> readNansenKey() => _storage.read(key: _nansenKey);
}
