import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/news_event.dart';
import '../../domain/models/app_settings.dart';
import '../../data/repositories/news_repository.dart';
import '../../domain/news/event_selector.dart';
import '../../data/services/storage/secure_key_store.dart';
import '../../utils/network.dart';

// Own news requests and state independently from chart and analysis state.
class NewsController extends ChangeNotifier {
  NewsController(
    this._service,
    this._keys, {
    required this.symbol,
    required this.settings,
  });
  final NewsRepository _service;
  final SecureKeyStore _keys;
  String symbol;
  NewsSettings settings;
  List<NewsEvent> events = const [];
  Timer? _timer;
  CancelToken? _macroRequest, _tokenRequest;
  int _revision = 0, _refreshes = 0;
  bool _disposed = false;

  bool get refreshing => _refreshes > 0;
  Map<String, NewsProviderStatus> get statuses => _service.statuses;

  void initialize() {
    unawaited(_loadCached());
    refresh();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_macroRequest == null) unawaited(refreshMacro());
      if (_tokenRequest == null) unawaited(refreshToken(symbol));
    });
  }

  void selectSymbol(String value) {
    if (symbol == value) return;
    symbol = value;
    _notify();
    unawaited(refreshToken(value));
  }

  void refresh() {
    unawaited(refreshMacro());
    unawaited(refreshToken(symbol));
  }

  Future<void> _loadCached() async {
    final revision = _revision;
    final cached = await _service.readCached();
    if (!_disposed && revision == _revision) _publish(cached);
  }

  void _publish(List<NewsEvent> value) {
    if (_disposed) return;
    events = value;
    _revision++;
    _notify();
  }

  // Reject late refreshes and keep per-provider failures isolated in statuses.
  Future<void> refreshMacro() async {
    if (_disposed) return;
    _macroRequest?.cancel();
    final cancelToken = _macroRequest = CancelToken();
    final revision = _revision;
    var receivedEvents = false;
    bool current() =>
        !_disposed &&
        identical(_macroRequest, cancelToken) &&
        !cancelToken.isCancelled;
    try {
      final events = await _service.refresh(
        settings: settings,
        finnhubApiKey: await _keys.readFinnhubKey(),
        onRefreshChanged: _refreshState,
        onEvents: (events) {
          if (!current()) return;
          receivedEvents = true;
          _publish(events);
        },
        cancelToken: cancelToken,
      );
      if (current() && !receivedEvents && revision == _revision) {
        _publish(events);
      }
      if (current()) _notify();
    } catch (error) {
      if (isRequestCancelled(error)) return;
      if (current()) _notify();
    } finally {
      if (identical(_macroRequest, cancelToken)) {
        _macroRequest = null;
      }
    }
  }

  // Agent preparation may supply its own stop token without stopping macro news.
  Future<void> refreshToken(String symbol, {CancelToken? requestCancel}) async {
    if (_disposed) return;
    _tokenRequest?.cancel();
    final cancelToken = _tokenRequest = requestCancel ?? CancelToken();
    final revision = _revision;
    var receivedEvents = false;
    bool current() =>
        !_disposed &&
        identical(_tokenRequest, cancelToken) &&
        !cancelToken.isCancelled &&
        symbol == this.symbol;
    try {
      final events = await _service.refreshTokenNews(
        symbol: symbol,
        settings: settings,
        marketauxApiKey: await _keys.readMarketauxKey(),
        onRefreshChanged: _refreshState,
        onEvents: (events) {
          if (!current()) return;
          receivedEvents = true;
          _publish(events);
        },
        cancelToken: cancelToken,
      );
      if (current() && !receivedEvents && revision == _revision) {
        _publish(events);
      }
      if (current()) _notify();
    } catch (error) {
      if (isRequestCancelled(error)) return;
      if (current()) _notify();
    } finally {
      if (identical(_tokenRequest, cancelToken)) {
        _tokenRequest = null;
      }
    }
  }

  void _refreshState(bool refreshing) {
    if (_disposed) return;
    _refreshes += refreshing ? 1 : -1;
    _notify();
  }

  Future<EventSnapshot> snapshot(
    String symbol, {
    required bool abnormal,
  }) async {
    final selected = const EventSelector().select(
      events: events,
      symbol: symbol,
    );
    return EventSnapshot(
      snapshotAsOf: selected.snapshotAsOf,
      upcomingCriticalEvents: selected.upcomingCriticalEvents,
      breakingEvents: selected.breakingEvents,
      assetSpecificEvents: selected.assetSpecificEvents,
      cryptoMarketEvents: selected.cryptoMarketEvents,
      macroEvents: selected.macroEvents,
      tokenNewsSearchQueries: selected.assetSpecificEvents.isEmpty || abnormal
          ? await _service.tokenNewsSearchQueries(symbol)
          : const [],
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _macroRequest?.cancel();
    _tokenRequest?.cancel();
    super.dispose();
  }
}
