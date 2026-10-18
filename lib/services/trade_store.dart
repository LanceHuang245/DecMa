import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// Keep decision evidence in the background without adding a user workflow.
class TradeStore {
  TradeStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();
  final SharedPreferencesAsync _preferences;
  Future<void> _pending = Future.value();

  Future<List<Map<String, dynamic>>> readRecords() async {
    await _pending;
    final text = await _preferences.getString('decma.trade.records');
    return text == null
        ? []
        : (jsonDecode(text) as List)
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
  }

  // Serialize writes so chart observations cannot overwrite an analysis record.
  Future<void> append(Map<String, Object?> record) {
    final operation = _pending.then((_) async {
      final text = await _preferences.getString('decma.trade.records');
      final rows = text == null ? <dynamic>[] : jsonDecode(text) as List;
      rows.add(record);
      await _preferences.setString('decma.trade.records', jsonEncode(rows));
    });
    _pending = operation.catchError((Object _) {});
    return operation;
  }
}
