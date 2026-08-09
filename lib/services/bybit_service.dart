import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/market_snapshot.dart';
import '../models/trading_models.dart';

class BybitService {
  BybitService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<InstrumentSnapshot> fetchInstrument(String symbol) async {
    final response = await _client.get(
      Uri.https('api.bybit.com', '/v5/market/instruments-info', {
        'category': 'linear',
        'symbol': symbol.toUpperCase(),
      }),
    );
    final body = _marketBody(response, 'instrument');
    final result = body['result'] as Map<String, dynamic>;
    final list = (result['list'] as List).whereType<Map>().toList();
    if (list.length != 1) throw Exception('Bybit instrument was not found.');
    final item = Map<String, dynamic>.from(list.single);
    final priceFilter = Map<String, dynamic>.from(item['priceFilter'] as Map);
    final lotSizeFilter = Map<String, dynamic>.from(
      item['lotSizeFilter'] as Map,
    );
    return InstrumentSnapshot(
      symbol: item['symbol'].toString(),
      contractType: item['contractType'].toString(),
      status: item['status'].toString(),
      tickSize: double.parse(priceFilter['tickSize'].toString()),
      quantityStep: double.parse(lotSizeFilter['qtyStep'].toString()),
      fundingIntervalMinutes: int.parse(item['fundingInterval'].toString()),
      observedAt: _responseTime(body),
    );
  }

  Future<TickerSnapshot> fetchTicker(String symbol) async {
    final response = await _client.get(
      Uri.https('api.bybit.com', '/v5/market/tickers', {
        'category': 'linear',
        'symbol': symbol.toUpperCase(),
      }),
    );
    final body = _marketBody(response, 'ticker');
    final result = body['result'] as Map<String, dynamic>;
    final list = (result['list'] as List).whereType<Map>().toList();
    if (list.length != 1) throw Exception('Bybit ticker was not found.');
    final item = Map<String, dynamic>.from(list.single);
    return TickerSnapshot(
      symbol: item['symbol'].toString(),
      lastPrice: double.parse(item['lastPrice'].toString()),
      markPrice: double.parse(item['markPrice'].toString()),
      indexPrice: double.parse(item['indexPrice'].toString()),
      bestBid: double.parse(item['bid1Price'].toString()),
      bestAsk: double.parse(item['ask1Price'].toString()),
      openInterest: double.tryParse(item['openInterest']?.toString() ?? ''),
      fundingRate: double.tryParse(item['fundingRate']?.toString() ?? ''),
      observedAt: _responseTime(body),
    );
  }

  // Fetch all active linear contracts once; the search box filters this list locally.
  Future<List<String>> fetchLinearSymbols() async {
    final symbols = <String>{};
    String? cursor;
    do {
      final query = <String, String>{'category': 'linear', 'limit': '1000'};
      if (cursor != null) query['cursor'] = cursor;
      final response = await _client.get(
        Uri.https('api.bybit.com', '/v5/market/instruments-info', query),
      );
      if (response.statusCode != 200) {
        throw Exception(
          'Bybit symbol request failed (${response.statusCode}).',
        );
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['retCode'] != 0) {
        throw Exception(
          body['retMsg']?.toString() ?? 'Bybit returned an error.',
        );
      }
      final result = body['result'] as Map<String, dynamic>;
      for (final item in (result['list'] as List).cast<Map>()) {
        if (item['status'] == 'Trading') symbols.add(item['symbol'].toString());
      }
      cursor = result['nextPageCursor']?.toString();
    } while (cursor != null && cursor.isNotEmpty);

    final result = symbols.toList()..sort();
    return result;
  }

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

  // Validate the shared V5 envelope before reading endpoint-specific fields.
  Map<String, dynamic> _marketBody(http.Response response, String label) {
    if (response.statusCode != 200) {
      throw Exception('Bybit $label request failed (${response.statusCode}).');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['retCode'] != 0) {
      throw Exception(body['retMsg']?.toString() ?? 'Bybit returned an error.');
    }
    return body;
  }

  DateTime _responseTime(Map<String, dynamic> body) =>
      DateTime.fromMillisecondsSinceEpoch(
        int.parse(body['time'].toString()),
        isUtc: true,
      );

  void dispose() => _client.close();
}
