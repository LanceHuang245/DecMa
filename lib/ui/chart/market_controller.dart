import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../domain/models/candle.dart';
import '../../data/services/bybit_service.dart';
import '../../utils/network.dart';
import 'candle_series.dart';
import '../../l10n/app_languages.dart';

// Own market selection, polling and pagination without analysis or news state.
class MarketController extends ChangeNotifier {
  MarketController(this._bybit, {String symbol = 'BTCUSDT'})
    : activeSymbol = symbol,
      symbolController = TextEditingController(text: symbol);

  final BybitService _bybit;
  final TextEditingController symbolController;
  final _series = CandleSeries();
  String activeSymbol;
  String interval = '15';
  List<String> symbols = [];
  String? error, historyError;
  int version = 0;
  bool loadingMore = false, showLoading = false;
  bool _hasMore = true, _disposed = false;
  int _generation = 0;
  int? _loadingGeneration;
  // Consecutive failed polls and the end of a rate-limit pause.
  int _pollFailures = 0;
  DateTime? _pausedUntil;
  Timer? _timer;
  CancelToken? _chartRequest, _historyRequest, _symbolsRequest;

  List<Candle> get candles => _series.items;
  int get totalPrepended => _series.totalPrepended;
  bool get loading => _loadingGeneration == _generation;
  bool get hasMore => _series.isNotEmpty && _hasMore;

  void initialize() {
    unawaited(_loadSymbols());
    _startRefresh();
  }

  void _startRefresh({bool immediately = true}) {
    _timer?.cancel();
    _pollFailures = 0;
    if (immediately) unawaited(_load());
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_load(latestOnly: true)),
    );
  }

  Future<void> _loadSymbols({CancelToken? cancel}) async {
    final token = _symbolsRequest = cancel ?? CancelToken();
    try {
      final result = await _bybit.fetchLinearSymbols(cancelToken: token);
      if (_disposed || token.isCancelled) return;
      symbols = result;
      _notify();
    } catch (_) {
      // Symbol discovery is optional; manually selected contracts still work.
    } finally {
      if (identical(_symbolsRequest, token)) _symbolsRequest = null;
    }
  }

  // Selection generations keep late responses away from the current chart.
  Future<List<Candle>> _load({
    bool latestOnly = false,
    CancelToken? cancel,
  }) async {
    if (_disposed || loading) return const [];
    if (latestOnly && (_pausedUntil?.isAfter(DateTime.now()) ?? false)) {
      return const [];
    }
    final generation = _generation;
    final full = !latestOnly || _series.isEmpty;
    final token = _chartRequest = cancel ?? CancelToken();
    _loadingGeneration = generation;
    if (full) {
      showLoading = true;
      _notify();
    }
    try {
      final values = await _fetch(full, token);
      if (_disposed || generation != _generation || token.isCancelled) {
        return values;
      }
      final changed = full
          ? _series.replaceAll(values)
          : _series.applyLatest(values);
      error = null;
      _pollFailures = 0;
      if (full) {
        showLoading = false;
        version++;
      }
      if (changed || full) _notify();
      return values;
    } catch (failure) {
      if (isRequestCancelled(failure)) {
        if (cancel != null) rethrow;
        return const [];
      }
      if (_disposed || generation != _generation) return const [];
      if (!full) {
        // Keep the existing chart and polling through transient poll failures.
        final wait = _rateLimitWait(failure);
        if (wait != null) _pausedUntil = DateTime.now().add(wait);
        if (wait != null || ++_pollFailures < 5) return const [];
      }
      _timer?.cancel();
      error = appL10n.klineLoadFailed(failure);
      showLoading = false;
      _notify();
      if (cancel != null) rethrow;
      return const [];
    } finally {
      if (identical(_chartRequest, token)) _chartRequest = null;
      if (!_disposed && _loadingGeneration == generation) {
        _loadingGeneration = null;
        if (cancel?.isCancelled ?? false) {
          showLoading = false;
          _startRefresh(immediately: false);
        }
        if (full) _notify();
      }
    }
  }

  // Full loads retry twice with backoff; polls rely on the next timer tick.
  Future<List<Candle>> _fetch(bool full, CancelToken token) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await _bybit.fetchKlines(
          symbol: activeSymbol,
          interval: interval,
          limit: full
              ? (interval == 'D'
                    ? 730
                    : const ['1', '5', '15'].contains(interval)
                    ? 1440
                    : 1000)
              : 2,
          cancelToken: token,
        );
      } catch (failure) {
        if (!full || attempt >= 2 || isRequestCancelled(failure)) rethrow;
        await Future<void>.delayed(
          _rateLimitWait(failure) ?? Duration(seconds: 1 << attempt),
        );
      }
    }
  }

  // Honor Retry-After on HTTP 429 instead of hammering the endpoint.
  Duration? _rateLimitWait(Object failure) =>
      failure is AppFailure && failure.kind == AppFailureKind.rateLimited
      ? failure.retryAfter ?? const Duration(seconds: 5)
      : null;

  void retry() {
    if (loading) return;
    error = null;
    _startRefresh();
  }

  Future<void> loadMore() async {
    if (_disposed || loadingMore || loading || !hasMore) return;
    final generation = _generation;
    final token = _historyRequest = CancelToken();
    loadingMore = true;
    historyError = null;
    _notify();
    try {
      final older = await _bybit.fetchKlines(
        symbol: activeSymbol,
        interval: interval,
        limit: 1000,
        end:
            _series.first.time.millisecondsSinceEpoch -
            BybitService.intervalMs(interval),
        cancelToken: token,
      );
      if (_disposed || generation != _generation || token.isCancelled) return;
      if (older.length < 1000) _hasMore = false;
      if (_series.prepend(older)) _notify();
    } catch (failure) {
      if (isRequestCancelled(failure)) return;
      if (!_disposed && generation == _generation) {
        historyError = appL10n.historyLoadFailed(failure);
      }
    } finally {
      if (identical(_historyRequest, token)) _historyRequest = null;
      if (!_disposed && generation == _generation) {
        loadingMore = false;
        _notify();
      }
    }
  }

  void selectSymbol(String value) {
    final normalized = value.toUpperCase();
    if (activeSymbol == normalized) return;
    activeSymbol = normalized;
    symbolController.text = normalized;
    _transition();
    _startRefresh();
  }

  void selectInterval(String value) {
    if (interval == value) return;
    interval = value;
    _transition();
    _startRefresh();
  }

  void _transition() {
    _chartRequest?.cancel();
    _historyRequest?.cancel();
    _generation++;
    loadingMore = false;
    _hasMore = true;
    _series.clear();
    error = historyError = null;
    showLoading = true;
    _notify();
  }

  Future<String> resolveSymbol(String prompt, CancelToken cancel) async {
    if (symbols.isEmpty) await _loadSymbols(cancel: cancel);
    final candidates = <String>{};
    final text = prompt.toUpperCase();
    void add(String value) {
      final symbol = value.endsWith('USDT') ? value : '${value}USDT';
      if (symbols.contains(symbol)) candidates.add(symbol);
    }

    for (final match in RegExp(
      r'\b([A-Z0-9]{2,20})\s*(?:[/_-]\s*)?USDT\b',
    ).allMatches(text)) {
      add(match.group(1)!);
    }
    for (final match in RegExp(r'\b([A-Z0-9]{2,20})\b').allMatches(text)) {
      add(match.group(1)!);
    }
    return candidates.length == 1 ? candidates.single : activeSymbol;
  }

  // Analysis can borrow cached candles or own a cancellable initial chart load.
  Future<List<Candle>> prepare(String symbol, CancelToken cancel) async {
    if (activeSymbol == symbol && _series.isNotEmpty) return candles;
    _timer?.cancel();
    activeSymbol = symbol;
    symbolController.text = symbol;
    _transition();
    final generation = _generation;
    final result = await _load(cancel: cancel);
    if (!_disposed && generation == _generation) {
      _startRefresh(immediately: false);
    }
    return result;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _chartRequest?.cancel();
    _historyRequest?.cancel();
    _symbolsRequest?.cancel();
    symbolController.dispose();
    super.dispose();
  }
}
