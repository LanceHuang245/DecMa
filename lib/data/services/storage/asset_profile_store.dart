import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../domain/models/asset_profile.dart';

/// Persists resolved asset metadata so provider lookups are not repeated.
class AssetProfileStore {
  AssetProfileStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _profilesKey = 'decma.news.asset_profiles.v1';
  final SharedPreferencesAsync _preferences;

  Future<List<AssetProfile>> readAll() async {
    final value = await _preferences.getString(_profilesKey);
    if (value == null) return const [];
    return (jsonDecode(value) as List)
        .cast<Map<String, dynamic>>()
        .map(AssetProfile.fromJson)
        .toList();
  }

  Future<void> save(AssetProfile profile) async {
    // readAll may return a const empty list before the first saved profile.
    final profiles = [...await readAll()];
    final index = profiles.indexWhere((item) => item.symbol == profile.symbol);
    if (index < 0) {
      profiles.add(profile);
    } else {
      profiles[index] = profile;
    }
    await _preferences.setString(
      _profilesKey,
      jsonEncode(profiles.map((item) => item.toJson()).toList()),
    );
  }
}
