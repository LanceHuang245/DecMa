part of 'dashboard_controller.dart';

// News polls independently, so a feed outage cannot interrupt Agent streaming.
extension DashboardNews on DashboardController {
  void _startNewsRefresh() {
    _newsRefreshTimer?.cancel();
    _refreshAllNews();
    _newsRefreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshAllNews(),
    );
  }

  // Let existing provider work finish rather than joining a newly cancelled run.
  void _refreshAllNews() {
    if (_macroNewsCancelToken == null) unawaited(_refreshNews());
    if (_tokenNewsCancelToken == null) {
      unawaited(_refreshTokenNews(_activeSymbol));
    }
  }

  Future<void> _loadCachedNews() async {
    final revision = _newsRevision;
    final events = await _newsService.readCached();
    if (_isDisposed || revision != _newsRevision) return;
    _publishNews(events);
  }

  void _publishNews(List<NewsEvent> events) {
    if (_isDisposed) return;
    _newsEvents = events;
    // Revoke only new, relevant and officially confirmed critical event risks.
    final created = trading.createdAt;
    if (created != null && trading.plan != null) {
      final asset = trading.plan!.symbol?.replaceFirst(RegExp(r'USDT$'), '');
      final event = events
          .where(
            (e) =>
                e.importance == NewsImportance.critical &&
                e.verificationStatus ==
                    NewsVerificationStatus.primarySourceConfirmed &&
                e.publishedAt.isAfter(created) &&
                !e.publishedAt.isAfter(DateTime.now().toUtc()) &&
                (e.scope != NewsScope.assetSpecific ||
                    e.directAssets.contains(asset)),
          )
          .firstOrNull;
      if (event != null) trading.cancel('出现已确认的重大事件，请重新分析：${event.headline}');
    }
    _newsRevision++;
    _notifyNews();
  }

  // Reject late refreshes and keep per-provider failures isolated in statuses.
  Future<void> _refreshNews() async {
    if (_isDisposed) return;
    _cancelRequest(_macroNewsCancelToken);
    final cancelToken = _macroNewsCancelToken = CancelToken();
    final revision = _newsRevision;
    var receivedEvents = false;
    bool current() =>
        !_isDisposed &&
        identical(_macroNewsCancelToken, cancelToken) &&
        !cancelToken.isCancelled;
    try {
      final events = await _newsService.refresh(
        settings: _news,
        finnhubApiKey: await _keyStore.readFinnhubKey(),
        onRefreshChanged: _handleNewsRefreshState,
        onEvents: (events) {
          if (!current()) return;
          receivedEvents = true;
          _publishNews(events);
        },
        cancelToken: cancelToken,
      );
      if (current() && !receivedEvents && revision == _newsRevision) {
        _publishNews(events);
      }
      if (current()) _notifyNews();
    } catch (error) {
      if (isRequestCancelled(error)) return;
      if (current()) _notifyNews();
    } finally {
      if (identical(_macroNewsCancelToken, cancelToken)) {
        _macroNewsCancelToken = null;
      }
    }
  }

  // Agent preparation may supply its own stop token without stopping macro news.
  Future<void> _refreshTokenNews(
    String symbol, {
    CancelToken? requestCancel,
  }) async {
    if (_isDisposed) return;
    _cancelRequest(_tokenNewsCancelToken);
    final cancelToken = _tokenNewsCancelToken = requestCancel ?? CancelToken();
    final revision = _newsRevision;
    var receivedEvents = false;
    bool current() =>
        !_isDisposed &&
        identical(_tokenNewsCancelToken, cancelToken) &&
        !cancelToken.isCancelled &&
        symbol == _activeSymbol;
    try {
      final events = await _newsService.refreshTokenNews(
        symbol: symbol,
        settings: _news,
        marketauxApiKey: await _keyStore.readMarketauxKey(),
        onRefreshChanged: _handleNewsRefreshState,
        onEvents: (events) {
          if (!current()) return;
          receivedEvents = true;
          _publishNews(events);
        },
        cancelToken: cancelToken,
      );
      if (current() && !receivedEvents && revision == _newsRevision) {
        _publishNews(events);
      }
      if (current()) _notifyNews();
    } catch (error) {
      if (isRequestCancelled(error)) return;
      if (current()) _notifyNews();
    } finally {
      if (identical(_tokenNewsCancelToken, cancelToken)) {
        _tokenNewsCancelToken = null;
      }
    }
  }

  void _handleNewsRefreshState(bool refreshing) {
    if (_isDisposed) return;
    _newsRefreshesInFlight += refreshing ? 1 : -1;
    _notifyNews();
  }
}
