import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/trading_models.dart';

class BybitService {
  BybitService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  // The public V5 endpoint supplies the free OHLCV data shown in the chart.
  Future<List<Candle>> fetchKlines({
    required String symbol,
    required String interval,
    int limit = 160,
  }) async {
    final uri = Uri.https('api.bybit.com', '/v5/market/kline', {
      'category': 'linear',
      'symbol': symbol.toUpperCase(),
      'interval': interval,
      'limit': '$limit',
    });
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Bybit K-line request failed (${response.statusCode}).');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['retCode'] != 0) {
      throw Exception(body['retMsg']?.toString() ?? 'Bybit returned an error.');
    }
    final rows = ((body['result'] as Map<String, dynamic>)['list'] as List)
        .cast<List>();
    return rows.reversed.map((row) {
      return Candle(
        time: DateTime.fromMillisecondsSinceEpoch(int.parse(row[0].toString())),
        open: double.parse(row[1].toString()),
        high: double.parse(row[2].toString()),
        low: double.parse(row[3].toString()),
        close: double.parse(row[4].toString()),
        volume: double.parse(row[5].toString()),
      );
    }).toList();
  }

  void dispose() => _client.close();
}
