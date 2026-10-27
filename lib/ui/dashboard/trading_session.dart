import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/market_snapshot.dart';
import '../../domain/models/candle.dart';
import '../../domain/models/trade_plan.dart';
import '../../data/services/bybit_service.dart';
import '../../data/services/storage/trade_store.dart';
import '../../domain/analysis/entry_assessment.dart';
import '../../domain/analysis/reference_entry.dart';
import '../../domain/analysis/feature_engine.dart';
import '../../l10n/app_languages.dart';

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
  ReferenceEntry? referenceEntry;
  InstrumentSnapshot? _instrument;
  MarketFeatures? features;
  DateTime? _triggerAfter;
  EntryAssessment? assessment;
  bool checking = false;
  EntryState? _recordedState;
  Timer? _expiry;
  CancelToken? _cancel;
  int _generation = 0;
  bool _disposed = false;

  Future<void> accept(TradePlan candidate, MarketSnapshot snapshot) async {
    clear();
    plan = candidate;
    _instrument = snapshot.instrument;
    features = const FeatureEngine().calculate(snapshot);
    createdAt = DateTime.now().toUtc();
    pathStart = snapshot.buildStartedAt;
    recordId = '${snapshot.symbol}_${createdAt!.microsecondsSinceEpoch}';
    await _record({
      'type': 'plan',
      'at': createdAt!.toIso8601String(),
      'reference_venue': 'Bybit',
      'plan': candidate.parsedJson,
      'snapshot_id': snapshot.snapshotId,
      'reference_policy_version': ReferenceEntry.policyVersion,
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
    referenceEntry = null;
    _expiry?.cancel();
    assessment = EntryAssessment(
      EntryState.unverified,
      appL10n.checkingPrice,
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
              2,
              DateTime.now().toUtc().difference(pathStart!).inMinutes + 3,
            ),
          ),
          cancelToken: token,
        ),
        if (candidate.conditions.supported)
          bybit.fetchKlines(
            symbol: candidate.symbol!,
            interval: '${candidate.conditions.timeframeMinutes}',
            limit: 22,
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
          ? EntryAssessment(
              EntryState.unverified,
              appL10n.priceUnconfirmed,
              now,
            )
          : const EntryEvaluator().evaluate(
              plan: candidate,
              createdAt: createdAt!,
              pathStart: pathStart,
              now: now,
              path: pathComplete ? minutes : const [],
              triggerCandles: results.length > 2
                  ? results[2] as List<Candle>
                  : const [],
              price: ticker.lastPrice,
              fresh: pathComplete,
              triggerAfter: _triggerAfter,
              entryPrice: candidate.decision == 'LONG_SETUP'
                  ? ticker.bestAsk
                  : ticker.bestBid,
            );
      // Persist chase pauses even when a later refresh only sees a recovered quote.
      if (assessment?.state == EntryState.paused) _triggerAfter = now;
      referenceEntry =
          quoteFresh && assessment?.terminal == false && _instrument != null
          ? ReferenceEntry.calculate(candidate, ticker, _instrument!, now)
          : null;
      // Preserve terminal decisions; a cost pause requires a new post-pause trigger.
      if (assessment?.terminal == false && quoteFresh && pathComplete) {
        if (referenceEntry == null && assessment?.state == EntryState.ready) {
          assessment = EntryAssessment(
            EntryState.unverified,
            appL10n.awaitingQuotes,
            now,
          );
        } else if (referenceEntry != null &&
            (referenceEntry!.netRewardRisk < 1 ||
                (candidate.decision == 'LONG_SETUP'
                    ? referenceEntry!.price > referenceEntry!.maximumPrice
                    : referenceEntry!.price < referenceEntry!.maximumPrice))) {
          _triggerAfter = now;
          assessment = EntryAssessment(
            EntryState.paused,
            appL10n.rrTooLow,
            now,
          );
        }
      }
      final result = assessment!;
      await _recordAssessment(result, ticker.lastPrice);
      if (_disposed || generation != _generation) return;
    } catch (_) {
      if (!_disposed && generation == _generation) {
        assessment = EntryAssessment(
          EntryState.unverified,
          appL10n.marketUnavailable,
          DateTime.now().toUtc(),
        );
      }
    } finally {
      if (!_disposed && generation == _generation) {
        checking = false;
        if (assessment?.terminal != true) {
          final now = DateTime.now().toUtc();
          final delay = assessment?.state == EntryState.ready
              ? const Duration(seconds: 5)
              : Duration(
                  milliseconds: 60250 - now.second * 1000 - now.millisecond,
                );
          _expiry = Timer(delay, () => unawaited(recheck()));
        }
        _notify();
      }
    }
  }

  // Chart updates revoke stale opportunities, without interpreting them as real fills.
  void observe(double price) {
    final candidate = plan;
    if (candidate == null) return;
    final changed = currentPrice != price;
    currentPrice = price;
    if (changed && assessment?.state == EntryState.ready) {
      referenceEntry = null;
      assessment = EntryAssessment(
        EntryState.unverified,
        appL10n.priceChanged,
        DateTime.now().toUtc(),
      );
      _notify();
      unawaited(recheck());
    }
    if (!candidate.isSetup || assessment?.terminal == true) return;
    final result = const EntryEvaluator().evaluate(
      plan: candidate,
      createdAt: createdAt!,
      now: DateTime.now().toUtc(),
      path: const [],
      price: price,
      fresh: true,

      previous: assessment,
    );
    if (result.terminal ||
        result.state == EntryState.paused &&
            assessment?.state != EntryState.paused) {
      if (result.terminal) {
        _generation++;
        _cancel?.cancel();
        _expiry?.cancel();
        checking = false;
      }
      assessment = result;
      if (result.state == EntryState.paused) _triggerAfter = result.at;
      unawaited(_recordAssessment(result, price));
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

  Future<void> _recordAssessment(EntryAssessment result, double price) =>
      _record({
        'type': 'assessment',
        'at': result.at.toIso8601String(),
        'state': result.state.name,
        'reason': result.reason,
        'price': price,
        'reference_entry_price': referenceEntry?.price,
        'reference_net_rr': referenceEntry?.netRewardRisk,
        'effective_chase_price': referenceEntry?.maximumPrice,
      });

  // Evidence is saved silently; storage availability does not change market direction.
  Future<void> _record(Map<String, Object?> event) async {
    final id = recordId;
    // Persist state transitions, not every quote refresh.
    if (event['type'] == 'assessment') {
      if (_recordedState == assessment?.state) return;
      _recordedState = assessment?.state;
    }
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
    referenceEntry = null;
    _instrument = null;
    features = null;
    _triggerAfter = null;
    recordId = null;
    _recordedState = null;
  }

  void suspend() {
    if (plan == null || assessment?.terminal == true) return;
    _generation++;
    _cancel?.cancel();
    _expiry?.cancel();
    checking = false;
    assessment = EntryAssessment(
      EntryState.unverified,
      appL10n.recheckOnReturn,
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
