import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../domain/models/market_snapshot.dart';
import '../../domain/models/candle.dart';
import '../../utils/network.dart';

class BybitService {
  BybitService({Dio? dio}) : _dio = dio ?? createDio(), _ownsDio = dio == null;

  final Dio _dio;
  final bool _ownsDio;

  // Read the configured account's actual maker and taker rates without trading.
  Future<Map<String, double>> fetchAccountFeeRates({
    required String symbol,
    required String apiKey,
    required String apiSecret,
    CancelToken? cancelToken,
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
        cancelToken: cancelToken,
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
    final item = (body['result']['list'] as List).single;
    return {
      'maker_fee_rate': double.parse(item['makerFeeRate']),
      'taker_fee_rate': double.parse(item['takerFeeRate']),
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
    final item = (body['result']['list'] as List).single;
    final priceFilter = item['priceFilter'];
    final lotSizeFilter = item['lotSizeFilter'];
    return InstrumentSnapshot(
      symbol: item['symbol'],
      contractType: item['contractType'],
      status: item['status'],
      tickSize: double.parse(priceFilter['tickSize']),
      quantityStep: double.parse(lotSizeFilter['qtyStep']),
      minimumOrderQuantity: double.parse(lotSizeFilter['minOrderQty']),
      maximumOrderQuantity: double.parse(lotSizeFilter['maxOrderQty']),
      minimumNotionalValue: double.parse(lotSizeFilter['minNotionalValue']),
      fundingIntervalMinutes: item['fundingInterval'],
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
    final item = (body['result']['list'] as List).single;
    final nextFunding = int.tryParse(item['nextFundingTime']);
    return TickerSnapshot(
      symbol: item['symbol'],
      lastPrice: double.parse(item['lastPrice']),
      markPrice: double.parse(item['markPrice']),
      indexPrice: double.parse(item['indexPrice']),
      bestBid: double.parse(item['bid1Price']),
      bestAsk: double.parse(item['ask1Price']),
      openInterest: double.tryParse(item['openInterest']),
      fundingRate: double.tryParse(item['fundingRate']),
      nextFundingAt: nextFunding != null && nextFunding > 0
          ? DateTime.fromMillisecondsSinceEpoch(nextFunding, isUtc: true)
          : null,
      observedAt: _responseTime(body),
    );
  });

  final _oiCache =
      <String, ({DateTime at, List<({DateTime at, double value})> points})>{};

  // Public positioning history is auxiliary, bounded, and never requires credentials.
  Future<List<({DateTime at, double value})>> fetchOpenInterestHistory(
    String symbol, {
    CancelToken? cancelToken,
  }) async {
    final key = symbol.toUpperCase();
    final cached = _oiCache[key];
    if (cached != null &&
        DateTime.now().toUtc().difference(cached.at) <
            const Duration(seconds: 60)) {
      return cached.points;
    }
    final points = await _read(() async {
      final body = _marketBody(
        await runNetworkRequest(
          'Bybit',
          () => _dio.getUri<String>(
            Uri.https('api.bybit.com', '/v5/market/open-interest', {
              'category': 'linear',
              'symbol': key,
              'intervalTime': '5min',
              'limit': '14',
            }),
            options: networkOptions(timeout: const Duration(seconds: 3)),
            cancelToken: cancelToken,
          ),
        ),
      );
      final points =
          (body['result']['list'] as List)
              .map(
                (p) => (
                  at: DateTime.fromMillisecondsSinceEpoch(
                    int.parse(p['timestamp']),
                    isUtc: true,
                  ),
                  value: double.parse(p['openInterest']),
                ),
              )
              .toList()
            ..sort((a, b) => a.at.compareTo(b.at));
      return points;
    });
    _oiCache[key] = (at: DateTime.now().toUtc(), points: points);
    return points;
  }

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
          final result = body['result'];
          for (final item in result['list']) {
            if (item['status'] == 'Trading') {
              symbols.add(item['symbol']);
            }
          }
          cursor = result['nextPageCursor'];
        } while (cursor != null && cursor.isNotEmpty);

        return symbols.toList()..sort();
      });

  // The public V5 endpoint supplies the free OHLCV data shown in the chart.
  Future<List<Candle>> fetchKlines({
    required String symbol,
    required String interval,
    int limit = 160,
    int? start,
    int? end,
    CancelToken? cancelToken,
  }) => _read(() async {
    // Single page when within Bybit's 1000 limit.
    if (limit <= 1000) {
      return _fetchKlinePage(
        symbol: symbol,
        interval: interval,
        limit: limit,
        start: start,
        end: end,
        cancelToken: cancelToken,
      );
    }
    // Paginate backwards from `end` to cover `limit` candles.
    final all = <Candle>[];
    int? cursorEnd = end;
    var remaining = limit;
    while (remaining > 0) {
      final pageLimit = remaining > 1000 ? 1000 : remaining;
      final page = await _fetchKlinePage(
        symbol: symbol,
        interval: interval,
        limit: pageLimit,
        start: start,
        end: cursorEnd,
        cancelToken: cancelToken,
      );
      if (page.isEmpty) break;
      all.addAll(page);
      if (page.length < pageLimit) break;
      final oldestMs = all
          .map((c) => c.time.millisecondsSinceEpoch)
          .reduce((a, b) => a < b ? a : b);
      cursorEnd = oldestMs - intervalMs(interval);
      if (start != null && cursorEnd < start) break;
      remaining = limit - all.length;
      if (all.length >= limit) break;
    }
    // Deduplicate by timestamp and keep chronological order.
    final byTime = <int, Candle>{
      for (final c in all) c.time.millisecondsSinceEpoch: c,
    };
    final merged = byTime.values.toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    return merged.length > limit
        ? merged.sublist(merged.length - limit)
        : merged;
  });

  // Fetch a single page of klines; Bybit returns newest first.
  Future<List<Candle>> _fetchKlinePage({
    required String symbol,
    required String interval,
    required int limit,
    int? start,
    int? end,
    CancelToken? cancelToken,
  }) async {
    final query = <String, String>{
      'category': 'linear',
      'symbol': symbol.toUpperCase(),
      'interval': interval,
      'limit': '$limit',
    };
    if (start != null) query['start'] = '$start';
    if (end != null) query['end'] = '$end';
    final body = _marketBody(
      await _get(
        Uri.https('api.bybit.com', '/v5/market/kline', query),
        cancelToken: cancelToken,
      ),
    );
    final rows = body['result']['list'] as List;
    return rows.reversed.map((row) {
      return Candle(
        time: DateTime.fromMillisecondsSinceEpoch(int.parse(row[0])),
        open: double.parse(row[1]),
        high: double.parse(row[2]),
        low: double.parse(row[3]),
        close: double.parse(row[4]),
        volume: double.parse(row[5]),
      );
    }).toList();
  }

  // Interval string to milliseconds for pagination stepping.
  static int intervalMs(String interval) => switch (interval) {
        '1' => 60 * 1000,
        '3' => 3 * 60 * 1000,
        '5' => 5 * 60 * 1000,
        '15' => 15 * 60 * 1000,
        '30' => 30 * 60 * 1000,
        '60' => 60 * 60 * 1000,
        '120' => 120 * 60 * 1000,
        '240' => 240 * 60 * 1000,
        '360' => 360 * 60 * 1000,
        '720' => 720 * 60 * 1000,
        'D' => 24 * 60 * 60 * 1000,
        'W' => 7 * 24 * 60 * 60 * 1000,
        'M' => 30 * 24 * 60 * 60 * 1000,
        _ => 15 * 60 * 1000,
      };

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
    final body = jsonDecode(response.data!) as Map<String, dynamic>;
    if (body['retCode'] != 0) {
      throw const AppFailure(kind: AppFailureKind.upstream, provider: 'Bybit');
    }
    return body;
  }

  Map<String, dynamic> _accountBody(Response<String> response) {
    requireSuccessfulResponse(response, provider: 'Bybit Account');
    final body = jsonDecode(response.data!) as Map<String, dynamic>;
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

  DateTime _responseTime(Map<String, dynamic> body) =>
      DateTime.fromMillisecondsSinceEpoch(
        body['time'],
        isUtc: true,
      );

  void dispose() { if (_ownsDio) _dio.close(force: true); }
}
