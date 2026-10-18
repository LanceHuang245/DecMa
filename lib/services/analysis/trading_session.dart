import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../models/market_snapshot.dart';
import '../../models/trading_models.dart';
import '../bybit_service.dart';
import '../trade_store.dart';
import 'entry_assessment.dart';

// Check opportunity freshness in the background; never require account configuration.
class TradingSession extends ChangeNotifier {
  TradingSession(this.bybit, {TradeStore? store})
    : store = store ?? TradeStore();
  final BybitService bybit;
  final TradeStore store;
  TradePlan? plan;
  DateTime? createdAt, pathStart;
  String? recordId;
  double? currentPrice;
  EntryAssessment? assessment;
  bool checking = false;
  Timer? _expiry;
  CancelToken? _cancel;
  int _generation = 0;
  bool _disposed = false;

  Future<void> accept(TradePlan candidate, MarketSnapshot snapshot) async {
    clear();
    plan = candidate;
    createdAt = DateTime.now().toUtc();
    pathStart = snapshot.buildStartedAt;
    recordId = '${snapshot.symbol}_${createdAt!.microsecondsSinceEpoch}';
    await _record({
      'type': 'plan',
      'at': createdAt!.toIso8601String(),
      'reference_venue': 'Bybit',
      'plan': candidate.parsedJson,
      'snapshot_id': snapshot.snapshotId,
      'path_start': pathStart!.toIso8601String(),
    });
    if (!_disposed && identical(plan, candidate) && candidate.isSetup) {
      await recheck();
    }
  }

  // Refresh completion-time prices so an old entry never looks like a new opportunity.
  Future<void> recheck() async {
    final candidate = plan;
    if (_disposed ||
        checking ||
        candidate == null ||
        assessment?.terminal == true) {
      return;
    }
    final generation = _generation;
    final token = _cancel = CancelToken();
    checking = true;
    _expiry?.cancel();
    assessment = EntryAssessment(
      EntryState.unverified,
      '正在检查最新价格',
      DateTime.now().toUtc(),
    );
    _notify();
    try {
      final results = await Future.wait<Object>([
        bybit.fetchTicker(candidate.symbol!, cancelToken: token),
        bybit.fetchKlines(
          symbol: candidate.symbol!,
          interval: '1',
          limit: math.min(
            1000,
            math.max(
              320,
              DateTime.now().toUtc().difference(pathStart!).inMinutes + 3,
            ),
          ),
          cancelToken: token,
        ),
      ]);
      if (_disposed ||
          generation != _generation ||
          assessment?.terminal == true) {
        return;
      }
      final ticker = results[0] as TickerSnapshot;
      final minutes = results[1] as List<Candle>;
      final now = DateTime.now().toUtc();
      final start = DateTime.fromMillisecondsSinceEpoch(
        pathStart!.millisecondsSinceEpoch ~/ 60000 * 60000,
        isUtc: true,
      );
      final path = minutes.where((c) => !c.time.isBefore(start)).toList();
      final quoteFresh =
          ticker.symbol == candidate.symbol &&
          ticker.lastPrice.isFinite &&
          ticker.lastPrice > 0 &&
          !now.difference(ticker.observedAt).isNegative &&
          now.difference(ticker.observedAt) <= const Duration(seconds: 5);
      final pathComplete =
          path.isNotEmpty &&
          path.first.time == start &&
          !path.last.time.isAfter(now) &&
          now.difference(path.last.time) < const Duration(minutes: 1) &&
          path.asMap().entries.every(
            (e) =>
                e.value.time == start.add(Duration(minutes: e.key)) &&
                [
                  e.value.open,
                  e.value.high,
                  e.value.low,
                  e.value.close,
                ].every((p) => p.isFinite && p > 0) &&
                e.value.low <= e.value.open &&
                e.value.high >= e.value.open &&
                e.value.low <= e.value.close &&
                e.value.high >= e.value.close,
          );
      currentPrice = quoteFresh ? ticker.lastPrice : null;
      assessment = !quoteFresh
          ? EntryAssessment(EntryState.unverified, '暂未确认最新价格，等待行情刷新', now)
          : const EntryEvaluator().evaluate(
              plan: candidate,
              createdAt: createdAt!,
              pathStart: pathStart,
              now: now,
              path: pathComplete ? minutes : const [],
              price: ticker.lastPrice,
              fresh: pathComplete,
              holding: const Duration(hours: 3),
            );
      final result = assessment!;
      await _record({
        'type': 'assessment',
        'at': result.at.toIso8601String(),
        'state': result.state.name,
        'reason': result.reason,
        'price': ticker.lastPrice,
      });
      if (_disposed || generation != _generation) return;
      final delay = result.state == EntryState.ready
          ? const Duration(seconds: 5)
          : Duration(milliseconds: 60250 - now.second * 1000 - now.millisecond);
      _expiry = Timer(delay, () {
        if (assessment?.terminal == true) return;
        unawaited(recheck());
      });
    } catch (_) {
      if (!_disposed && generation == _generation) {
        assessment = EntryAssessment(
          EntryState.unverified,
          '暂未获取到最新行情，稍后重试',
          DateTime.now().toUtc(),
        );
      }
    } finally {
      if (!_disposed && generation == _generation) {
        checking = false;
        _notify();
      }
    }
  }

  // Chart updates revoke stale opportunities, without interpreting them as real fills.
  void observe(double price) {
    final candidate = plan;
    if (candidate == null) return;
    currentPrice = price;
    if (!candidate.isSetup || assessment?.terminal == true) return;
    final result = const EntryEvaluator().evaluate(
      plan: candidate,
      createdAt: createdAt!,
      now: DateTime.now().toUtc(),
      path: const [],
      price: price,
      fresh: true,
      holding: const Duration(hours: 3),
      previous: assessment,
    );
    final long = candidate.decision == 'LONG_SETUP';
    final outside =
        candidate.maximumChasePrice != null &&
        (long
            ? price < candidate.entryLow! ||
                  price > candidate.maximumChasePrice!
            : price > candidate.entryHigh! ||
                  price < candidate.maximumChasePrice!);
    if (result.terminal ||
        result.state == EntryState.paused &&
            assessment?.state != EntryState.paused ||
        assessment?.state == EntryState.ready && outside) {
      if (result.terminal) {
        _generation++;
        _cancel?.cancel();
        checking = false;
      }
      _expiry?.cancel();
      assessment = result;
      unawaited(
        _record({
          'type': 'assessment',
          'at': result.at.toIso8601String(),
          'state': result.state.name,
          'reason': result.reason,
          'price': price,
        }),
      );
      _notify();
    }
  }

  void cancel(String reason) {
    if (plan == null || assessment?.terminal == true) return;
    _generation++;
    _cancel?.cancel();
    _expiry?.cancel();
    checking = false;
    assessment = EntryAssessment(
      EntryState.invalid,
      reason,
      DateTime.now().toUtc(),
    );
    unawaited(
      _record({
        'type': 'cancel',
        'at': assessment!.at.toIso8601String(),
        'reason': reason,
      }),
    );
    _notify();
  }

  // Evidence is saved silently; storage availability does not change market direction.
  Future<void> _record(Map<String, Object?> event) async {
    final id = recordId;
    try {
      await store.append({...event, 'id': id});
    } catch (_) {
      /* Keep analysis usable if local storage fails. */
    }
  }

  void clear() {
    _generation++;
    _cancel?.cancel();
    _expiry?.cancel();
    checking = false;
    plan = null;
    assessment = null;
    currentPrice = null;
    recordId = null;
  }

  void suspend() {
    if (plan == null || assessment?.terminal == true) return;
    _generation++;
    _cancel?.cancel();
    _expiry?.cancel();
    checking = false;
    assessment = EntryAssessment(
      EntryState.unverified,
      '返回后按最新行情重新确认',
      DateTime.now().toUtc(),
    );
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    clear();
    super.dispose();
  }
}
