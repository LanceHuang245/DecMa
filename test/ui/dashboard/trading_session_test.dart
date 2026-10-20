import 'dart:async';
import 'dart:convert';

import 'package:decma/domain/models/market_snapshot.dart';
import 'package:decma/domain/models/candle.dart';
import 'package:decma/domain/models/trade_plan.dart';
import 'package:decma/domain/analysis/entry_assessment.dart';
import 'package:decma/ui/dashboard/trading_session.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../fixtures/dashboard_agent_fixtures.dart';

TradePlan candidate() => TradePlan.fromResponse(
  jsonEncode({
    'request': {'symbol': 'BTCUSDT'},
    'decision': {'type': 'LONG_SETUP', 'summary': 'test'},
    'entry_plan': {
      'entry_zone_low': 99,
      'entry_zone_high': 100,
      'maximum_chase_price': 102,
    },
    'risk_plan': {'stop_loss': 95},
    'take_profit_plan': [
      {'price': 110},
    ],
    'conditions': {
      'trigger_type': 'CLOSE_ABOVE',
      'trigger_price': 100,
      'timeframe_minutes': 5,
    },
  }),
)!;

Future<MarketSnapshot> snapshot(AnalysisBybit bybit) async {
  final now = DateTime.now().toUtc();
  return MarketSnapshot(
    snapshotId: 'test',
    symbol: 'BTCUSDT',
    buildStartedAt: now.subtract(const Duration(minutes: 1)),
    buildCompletedAt: now,
    instrument: await bybit.fetchInstrument('BTCUSDT'),
    ticker: TickerSnapshot(
      symbol: 'BTCUSDT',
      lastPrice: 100,
      markPrice: 100,
      indexPrice: 100,
      bestBid: 99.9,
      bestAsk: 100.1,
      openInterest: null,
      fundingRate: null,
      observedAt: now,
    ),
    candlesByInterval: {},
    maxSourceSkewMs: 0,
    warnings: [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  test(
    'completion refresh marks an already-realized plan and never revives it',
    () async {
      final bybit = _QuoteBybit();
      final session = TradingSession(bybit);
      addTearDown(session.dispose);
      addTearDown(bybit.dispose);
      await session.accept(candidate(), await snapshot(bybit));
      expect(session.assessment?.state, EntryState.realized);
      final reads = bybit.reads;
      bybit.price = 100;
      await session.recheck();
      expect(session.assessment?.state, EntryState.realized);
      expect(bybit.reads, reads);
      final records = await session.store.readRecords();
      expect(records.first['type'], 'plan');
      expect(records.any((r) => r['state'] == 'realized'), true);
    },
  );

  testWidgets('a transient refresh failure is retried automatically', (
    tester,
  ) async {
    final bybit = _QuoteBybit()..failOnce = true;
    final session = TradingSession(bybit);
    addTearDown(session.dispose);
    addTearDown(bybit.dispose);
    await session.accept(candidate(), await snapshot(bybit));
    expect(session.assessment?.state, EntryState.unverified);
    await tester.pump(const Duration(minutes: 1, seconds: 1));
    expect(bybit.reads, 2);
    expect(session.assessment?.state, EntryState.realized);
  });

  test(
    'live quote cost filter pauses and requires a new trigger after recovery',
    () async {
      final bybit = _EntryBybit()..price = 101;
      final session = TradingSession(bybit);
      addTearDown(session.dispose);
      addTearDown(bybit.dispose);
      await session.accept(candidate(), await snapshot(bybit));
      final start = bybit.closedStart.subtract(const Duration(minutes: 5));
      session.createdAt = start;
      session.pathStart = start;
      await session.recheck();
      expect(session.assessment?.state, EntryState.ready);
      expect(session.referenceEntry!.price, closeTo(101.1, 1e-9));
      bybit.price = 104;
      await session.recheck();
      expect(session.assessment?.state, EntryState.paused);
      expect(session.referenceEntry!.netRewardRisk, lessThan(1));
      bybit.price = 101;
      await session.recheck();
      expect(session.assessment?.state, EntryState.waiting);
      expect(session.referenceEntry!.netRewardRisk, greaterThan(1));
    },
  );
  test(
    'fresh trigger without funding schedule never approves immediate entry',
    () async {
      final bybit = _EntryBybit()
        ..price = 101
        ..missingFunding = true;
      final session = TradingSession(bybit);
      addTearDown(session.dispose);
      addTearDown(bybit.dispose);
      await session.accept(candidate(), await snapshot(bybit));
      session.createdAt = bybit.closedStart.subtract(
        const Duration(minutes: 5),
      );
      session.pathStart = session.createdAt;
      await session.recheck();
      expect(session.assessment?.state, EntryState.unverified);
      expect(session.assessment!.reason, contains('资金费'));
      expect(session.plan!.decision, 'LONG_SETUP');
    },
  );

  test(
    'clearing a pending refresh prevents the old symbol from returning',
    () async {
      final bybit = _QuoteBybit()..delayed = Completer<TickerSnapshot>();
      final session = TradingSession(bybit);
      addTearDown(session.dispose);
      addTearDown(bybit.dispose);
      final work = session.accept(candidate(), await snapshot(bybit));
      while (!session.checking) {
        await Future<void>.delayed(Duration.zero);
      }
      session.clear();
      bybit.delayed!.complete(bybit.quote());
      await work;
      expect(session.plan, isNull);
      expect(session.assessment, isNull);
      expect(session.checking, false);
    },
  );

  test(
    'stale quotes cannot declare a new opportunity already realized',
    () async {
      final bybit = _QuoteBybit()..stale = true;
      final session = TradingSession(bybit);
      addTearDown(session.dispose);
      addTearDown(bybit.dispose);
      await session.accept(candidate(), await snapshot(bybit));
      expect(session.assessment?.state, EntryState.unverified);
    },
  );
}

class _QuoteBybit extends AnalysisBybit {
  bool failOnce = false;
  double price = 111;
  int reads = 0;
  bool stale = false;
  Completer<TickerSnapshot>? delayed;
  TickerSnapshot quote() => TickerSnapshot(
    symbol: 'BTCUSDT',
    lastPrice: price,
    markPrice: price,
    indexPrice: price,
    bestBid: price - 0.1,
    bestAsk: price + 0.1,
    openInterest: 100,
    fundingRate: 0,
    observedAt: DateTime.now().toUtc().subtract(
      Duration(seconds: stale ? 10 : 0),
    ),
  );
  @override
  Future<TickerSnapshot> fetchTicker(
    String symbol, {
    CancelToken? cancelToken,
  }) async {
    reads++;
    if (failOnce) {
      failOnce = false;
      throw Exception('temporary network failure');
    }
    return delayed?.future ?? Future.value(quote());
  }
}

// A full closed trigger and contiguous minute path exercise the production session filter.
class _EntryBybit extends _QuoteBybit {
  bool missingFunding = false;
  DateTime get closedStart {
    final ms = DateTime.now().toUtc().millisecondsSinceEpoch;
    return DateTime.fromMillisecondsSinceEpoch(
      ms ~/ 300000 * 300000 - 300000,
      isUtc: true,
    );
  }

  @override
  TickerSnapshot quote() => TickerSnapshot(
    symbol: 'BTCUSDT',
    lastPrice: price,
    markPrice: price,
    indexPrice: price,
    bestBid: price - 0.1,
    bestAsk: price + 0.1,
    openInterest: 100,
    fundingRate: 0,
    nextFundingAt: missingFunding
        ? null
        : DateTime.now().toUtc().add(const Duration(hours: 4)),
    observedAt: DateTime.now().toUtc(),
  );
  @override
  Future<List<Candle>> fetchKlines({
    required String symbol,
    required String interval,
    int limit = 160,
    int? start,
    int? end,
    CancelToken? cancelToken,
  }) async {
    final now = DateTime.now().toUtc();
    if (interval == '5') {
      return [
        Candle(
          time: closedStart,
          open: 100,
          high: 102,
          low: 99,
          close: 101,
          volume: 10,
        ),
      ];
    }
    final first = closedStart.subtract(const Duration(minutes: 5));
    return List.generate(
      now.difference(first).inMinutes + 1,
      (i) => Candle(
        time: first.add(Duration(minutes: i)),
        open: 100,
        high: price > 102 ? 104 : 101.5,
        low: 99,
        close: 101,
        volume: 10,
      ),
    );
  }
}
