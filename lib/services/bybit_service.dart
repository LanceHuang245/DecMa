import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../models/market_snapshot.dart';
import '../models/trading_models.dart';
import '../utils/network.dart';

class BybitService {
  BybitService({Dio? dio}) : _dio = dio ?? createDio();

  final Dio _dio;

  // Read the configured account's actual maker and taker rates without trading.
  Future<Map<String, double>> fetchAccountFeeRates({
    required String symbol,
    required String apiKey,
    required String apiSecret,
  }) => _read(() async {
    final normalized = symbol.trim().toUpperCase();
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    const recvWindow = '5000';
    final query = 'category=linear&symbol=$normalized';
    final signature = accountSignature(
      timestamp: timestamp,
      apiKey: apiKey,
      recvWindow: recvWindow,
      query: query,
      apiSecret: apiSecret,
    );
    final response = await runNetworkRequest(
      'Bybit Account',
      () => _dio.getUri<String>(
        Uri.https('api.bybit.com', '/v5/account/fee-rate', {
          'category': 'linear',
          'symbol': normalized,
        }),
        options: networkOptions(
          headers: {
            'X-BAPI-API-KEY': apiKey,
            'X-BAPI-TIMESTAMP': '$timestamp',
            'X-BAPI-RECV-WINDOW': recvWindow,
            'X-BAPI-SIGN': signature,
          },
        ),
      ),
    );
    final body = _accountBody(response);
    final list = (_map(body['result'])['list'] as List)
        .whereType<Map>()
        .toList();
    if (list.length != 1) {
      throw const AppFailure(
        kind: AppFailureKind.invalidResponse,
        provider: 'Bybit Account',
      );
    }
    final item = Map<String, dynamic>.from(list.single);
    return {
      'maker_fee_rate': double.parse(item['makerFeeRate'].toString()),
      'taker_fee_rate': double.parse(item['takerFeeRate'].toString()),
    };
  });

  // Sign the exact GET payload required by Bybit's authenticated V5 endpoints.
  static String accountSignature({
    required int timestamp,
    required String apiKey,
    required String recvWindow,
    required String query,
    required String apiSecret,
  }) => Hmac(
    sha256,
    utf8.encode(apiSecret),
  ).convert(utf8.encode('$timestamp$apiKey$recvWindow$query')).toString();

  Future<InstrumentSnapshot> fetchInstrument(
    String symbol, {
    CancelToken? cancelToken,
  }) => _read(() async {
    final response = await _get(
      Uri.https('api.bybit.com', '/v5/market/instruments-info', {
        'category': 'linear',
        'symbol': symbol.toUpperCase(),
      }),
      cancelToken: cancelToken,
    );
    final body = _marketBody(response);
    final list = (_map(body['result'])['list'] as List)
        .whereType<Map>()
        .toList();
    if (list.length != 1) {
      throw const AppFailure(
        kind: AppFailureKind.invalidResponse,
        provider: 'Bybit',
      );
    }
    final item = Map<String, dynamic>.from(list.single);
    final priceFilter = _map(item['priceFilter']);
    final lotSizeFilter = _map(item['lotSizeFilter']);
    return InstrumentSnapshot(
      symbol: item['symbol'].toString(),
      contractType: item['contractType'].toString(),
      status: item['status'].toString(),
      tickSize: double.parse(priceFilter['tickSize'].toString()),
      quantityStep: double.parse(lotSizeFilter['qtyStep'].toString()),
      fundingIntervalMinutes: int.parse(item['fundingInterval'].toString()),
      observedAt: _responseTime(body),
    );
  });

  Future<TickerSnapshot> fetchTicker(
    String symbol, {
    CancelToken? cancelToken,
  }) => _read(() async {
    final response = await _get(
      Uri.https('api.bybit.com', '/v5/market/tickers', {
        'category': 'linear',
        'symbol': symbol.toUpperCase(),
      }),
      cancelToken: cancelToken,
    );
    final body = _marketBody(response);
    final list = (_map(body['result'])['list'] as List)
        .whereType<Map>()
        .toList();
    if (list.length != 1) {
      throw const AppFailure(
        kind: AppFailureKind.invalidResponse,
        provider: 'Bybit',
      );
    }
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
  });

  // Fetch all active linear contracts once; the search box filters this list locally.
  Future<List<String>> fetchLinearSymbols({CancelToken? cancelToken}) =>
      _read(() async {
        final symbols = <String>{};
        String? cursor;
        do {
          final query = <String, String>{'category': 'linear', 'limit': '1000'};
          if (cursor != null) query['cursor'] = cursor;
          final body = _marketBody(
            await _get(
              Uri.https('api.bybit.com', '/v5/market/instruments-info', query),
              cancelToken: cancelToken,
            ),
          );
          final result = _map(body['result']);
          for (final item in (result['list'] as List).cast<Map>()) {
            if (item['status'] == 'Trading') {
              symbols.add(item['symbol'].toString());
            }
          }
          cursor = result['nextPageCursor']?.toString();
        } while (cursor != null && cursor.isNotEmpty);

        return symbols.toList()..sort();
      });

  // The public V5 endpoint supplies the free OHLCV data shown in the chart.
  Future<List<Candle>> fetchKlines({
    required String symbol,
    required String interval,
    int limit = 160,
    CancelToken? cancelToken,
  }) => _read(() async {
    final body = _marketBody(
      await _get(
        Uri.https('api.bybit.com', '/v5/market/kline', {
          'category': 'linear',
          'symbol': symbol.toUpperCase(),
          'interval': interval,
          'limit': '$limit',
        }),
        cancelToken: cancelToken,
      ),
    );
    final rows = (_map(body['result'])['list'] as List).cast<List>();
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
  });

  Future<Response<String>> _get(Uri uri, {CancelToken? cancelToken}) =>
      runNetworkRequest(
        'Bybit',
        () => _dio.getUri<String>(
          uri,
          options: networkOptions(),
          cancelToken: cancelToken,
        ),
      );

  // Convert malformed provider data into one safe, user-facing failure.
  Future<T> _read<T>(Future<T> Function() task) async {
    try {
      return await task();
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const AppFailure(
        kind: AppFailureKind.invalidResponse,
        provider: 'Bybit',
      );
    }
  }

  Map<String, dynamic> _marketBody(Response<String> response) {
    requireSuccessfulResponse(response, provider: 'Bybit');
    final body = _map(jsonDecode(response.data ?? ''));
    if (body['retCode'] != 0) {
      throw const AppFailure(kind: AppFailureKind.upstream, provider: 'Bybit');
    }
    return body;
  }

  Map<String, dynamic> _accountBody(Response<String> response) {
    requireSuccessfulResponse(response, provider: 'Bybit Account');
    final body = _map(jsonDecode(response.data ?? ''));
    if (body['retCode'] != 0) {
      final code = body['retCode'];
      throw AppFailure(
        kind: const [10003, 10004, 10005, 10007, 10010].contains(code)
            ? AppFailureKind.authentication
            : AppFailureKind.upstream,
        provider: 'Bybit Account',
      );
    }
    return body;
  }

  Map<String, dynamic> _map(Object? value) =>
      Map<String, dynamic>.from(value as Map);

  DateTime _responseTime(Map<String, dynamic> body) =>
      DateTime.fromMillisecondsSinceEpoch(
        int.parse(body['time'].toString()),
        isUtc: true,
      );

  void dispose() => _dio.close(force: true);
}
