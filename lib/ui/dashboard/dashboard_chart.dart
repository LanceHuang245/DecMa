part of 'dashboard_controller.dart';

// Keep chart loading and history transitions separate from Agent streaming.
extension DashboardChart on DashboardController {
  void _startChartRefresh({bool loadImmediately = true}) {
    _chartRefreshTimer?.cancel();
    if (loadImmediately) unawaited(_loadChart());
    _chartRefreshTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_loadChart(latestOnly: true)),
    );
  }

  Future<void> _loadSymbols({CancelToken? cancelToken}) async {
    final token = _symbolListCancelToken = cancelToken ?? CancelToken();
    try {
      final symbols = await _bybit.fetchLinearSymbols(cancelToken: token);
      if (_isDisposed || token.isCancelled) return;
      _symbols = symbols;
      _notify();
    } catch (error) {
      if (isRequestCancelled(error)) return;
      // Symbol discovery is optional; the current chart can still be analyzed.
    } finally {
      if (identical(_symbolListCancelToken, token)) {
        _symbolListCancelToken = null;
      }
    }
  }

  // A stale response must never update a newer chart selection.
  Future<void> _loadChart({bool latestOnly = false}) async {
    if (_isDisposed) return;
    final generation = _chartLoadGeneration;
    if (_loadingChartGeneration == generation) return;
    final symbol = _activeSymbol;
    final interval = _interval;
    final fullLoad = !latestOnly || _candleSeries.isEmpty;
    final cancelToken = _chartCancelToken = CancelToken();
    _loadingChartGeneration = generation;
    if (fullLoad) {
      _showChartLoading = true;
      _notify();
    }
    try {
      final candles = await _bybit.fetchKlines(
        symbol: symbol,
        interval: interval,
        limit: fullLoad ? _limitForInterval(interval) : 2,
        cancelToken: cancelToken,
      );
      if (_isDisposed ||
          generation != _chartLoadGeneration ||
          symbol != _activeSymbol ||
          interval != _interval) {
        return;
      }
      final changed = fullLoad
          ? _candleSeries.replaceAll(candles)
          : _candleSeries.applyLatest(candles);
      _chartError = null;
      if (fullLoad) {
        _showChartLoading = false;
        _chartVersion++;
      }
      if (candles.isNotEmpty && trading.plan?.symbol == symbol) {
        trading.observe(candles.last.close);
      }
      if (changed || fullLoad) _notify();
    } catch (error) {
      if (isRequestCancelled(error)) return;
      if (_isDisposed ||
          generation != _chartLoadGeneration ||
          symbol != _activeSymbol ||
          interval != _interval) {
        return;
      }
      _chartRefreshTimer?.cancel();
      _chartError = 'K 线加载失败：$error';
      _showChartLoading = false;
      _notify();
    } finally {
      if (identical(_chartCancelToken, cancelToken)) _chartCancelToken = null;
      if (!_isDisposed && _loadingChartGeneration == generation) {
        _loadingChartGeneration = null;
        if (fullLoad) _notify();
      }
    }
  }

  void _retryChart() {
    if (loadingChart) return;
    _chartError = null;
    _showChartLoading = true;
    _notify();
    _startChartRefresh();
  }

  // Page older candles in memory until the exchange runs out of history.
  Future<void> _loadMoreHistory() async {
    if (_isDisposed ||
        _loadingOlder ||
        _candleSeries.isEmpty ||
        loadingChart ||
        !_hasMoreHistory) {
      return;
    }
    final generation = _chartLoadGeneration;
    final interval = _interval;
    final symbol = _activeSymbol;
    final oldestMs = _candleSeries.first.time.millisecondsSinceEpoch;
    final end = oldestMs - BybitService.intervalMs(interval);
    const fetchLimit = 1000;
    final cancelToken = _historyCancelToken = CancelToken();
    _loadingOlder = true;
    _historyError = null;
    _notify();
    try {
      final older = await _bybit.fetchKlines(
        symbol: symbol,
        interval: interval,
        limit: fetchLimit,
        end: end,
        cancelToken: cancelToken,
      );
      if (_isDisposed ||
          generation != _chartLoadGeneration ||
          symbol != _activeSymbol ||
          interval != _interval) {
        return;
      }
      if (older.isEmpty) {
        _hasMoreHistory = false;
        return;
      }
      if (older.length < fetchLimit) _hasMoreHistory = false;
      if (_candleSeries.prepend(older)) _notify();
    } catch (error) {
      if (isRequestCancelled(error)) return;
      if (!_isDisposed && generation == _chartLoadGeneration) {
        _historyError = '更早历史加载失败：$error';
        _notify();
      }
    } finally {
      if (identical(_historyCancelToken, cancelToken)) {
        _historyCancelToken = null;
      }
      if (!_isDisposed && generation == _chartLoadGeneration) {
        _loadingOlder = false;
        _notify();
      }
    }
  }

  // Invalidate chart work while keeping the independent Agent request intact.
  void _selectSymbol(String symbol) {
    final normalized = symbol.toUpperCase();
    if (normalized == _activeSymbol) return;
    _activeSymbol = normalized;
    _symbol.text = _activeSymbol;
    _beginChartTransition();
    _notify();
    _notifyNews();
    _startChartRefresh();
    unawaited(_llmSettingsStore.saveLastViewedSymbol(_activeSymbol));
    unawaited(_refreshTokenNews(_activeSymbol));
  }

  void _selectInterval(String interval) {
    if (interval == _interval) return;
    _interval = interval;
    _beginChartTransition();
    _notify();
    _startChartRefresh();
  }

  void _beginChartTransition() {
    _cancelRequest(_chartCancelToken);
    _cancelRequest(_historyCancelToken);
    _historyCancelToken = null;
    _chartCancelToken = null;
    _chartLoadGeneration++;
    trading.clear();
    _loadingOlder = false;
    _hasMoreHistory = true;
    _candleSeries.clear();
    _plan = null;
    _chartPlan = null;
    _showWaitZone = false;
    _chartError = null;
    _historyError = null;
    _showChartLoading = true;
  }

  // Resolve a requested contract and bind preparation to the Agent's stop token.
  Future<String> _resolveAnalysisSymbol(
    String prompt,
    CancelToken cancel,
  ) async {
    if (_symbols.isEmpty) await _loadSymbols(cancelToken: cancel);
    return _requestedSymbol(prompt) ?? _activeSymbol;
  }

  Future<List<Candle>> _prepareAnalysisChart(
    String symbol,
    CancelToken cancel,
  ) async {
    if (symbol == _activeSymbol && _candleSeries.isNotEmpty) {
      return _candleSeries.items;
    }
    _chartRefreshTimer?.cancel();
    _recordActivity('• Chart - 加载 $symbol');
    _activeSymbol = symbol;
    _symbol.text = symbol;
    unawaited(_llmSettingsStore.saveLastViewedSymbol(symbol));
    _beginChartTransition();
    final generation = _chartLoadGeneration;
    _loadingChartGeneration = generation;
    _notify();
    try {
      final candles = await _bybit.fetchKlines(
        symbol: symbol,
        interval: _interval,
        limit: _limitForInterval(_interval),
        cancelToken: cancel,
      );
      if (_isDisposed ||
          cancel.isCancelled ||
          generation != _chartLoadGeneration ||
          _activeSymbol != symbol) {
        return candles;
      }
      _candleSeries.replaceAll(candles);
      _showChartLoading = false;
      _chartVersion++;
      _notify();
      _startChartRefresh(loadImmediately: false);
      return candles;
    } catch (error) {
      if (isRequestCancelled(error)) rethrow;
      if (!_isDisposed &&
          generation == _chartLoadGeneration &&
          _activeSymbol == symbol) {
        _chartError = 'K 线加载失败：$error';
        _showChartLoading = false;
        _notify();
      }
      throw Exception('无法加载 $symbol 的 K 线：$error');
    } finally {
      if (!_isDisposed && _loadingChartGeneration == generation) {
        _loadingChartGeneration = null;
        // Resume independent chart polling when Agent preparation is stopped.
        if (cancel.isCancelled) {
          _showChartLoading = false;
          _startChartRefresh(loadImmediately: false);
        }
        _notify();
      }
    }
  }

  String? _requestedSymbol(String prompt) {
    if (_symbols.isEmpty) return null;
    final candidates = <String>{};
    final normalized = prompt.toUpperCase();
    void addCandidate(String value) {
      final symbol = value.endsWith('USDT') ? value : '${value}USDT';
      if (_symbols.contains(symbol)) candidates.add(symbol);
    }

    for (final match in RegExp(
      r'\b([A-Z0-9]{2,20})\s*(?:[/_-]\s*)?USDT\b',
    ).allMatches(normalized)) {
      addCandidate(match.group(1)!);
    }
    for (final match in RegExp(
      r'\b([A-Z0-9]{2,20})\b',
    ).allMatches(normalized)) {
      addCandidate(match.group(1)!);
    }
    return candidates.length == 1 ? candidates.single : null;
  }
}

// Preserve existing per-interval coverage limits.
int _limitForInterval(String interval) =>
    const {
      '1': 1440,
      '5': 1440,
      '15': 1440,
      '60': 1000,
      '240': 1000,
      'D': 730,
    }[interval] ??
    1000;
