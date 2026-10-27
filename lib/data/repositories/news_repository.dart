import 'package:dio/dio.dart';

import '../../app_constants.dart';
import '../../domain/models/news_event.dart';
import '../../domain/models/app_settings.dart';
import '../../utils/network.dart';
import 'asset_resolver.dart';
import '../services/storage/event_store.dart';
import '../services/news/marketaux_news_provider.dart';
import '../services/news/news_feeds.dart';
import '../../domain/news/news_classifier.dart';

class NewsProviderStatus {
  const NewsProviderStatus({
    required this.id,
    required this.state,
    this.message,
    this.updatedAt,
  });

  final String id;
  final NewsProviderState state;
  final String? message;
  final DateTime? updatedAt;
}

class NewsRepository {
  NewsRepository({Dio? dio, EventStore? store, AssetResolver? assetResolver})
    : _dio = dio ?? createDio(),
      _store = store ?? EventStore(),
      _assetResolver = assetResolver ?? AssetResolver() {
    _marketaux = MarketauxNewsProvider(dio: _dio);
    _feeds = NewsFeeds(_dio);
  }

  static const _finnhubInterval = Duration(minutes: 10);
  static const _marketauxInterval = Duration(minutes: 15);
  static const _officialInterval = Duration(minutes: 30);
  static const _rateLimitBackoff = Duration(hours: 1);
  final Dio _dio;
  final EventStore _store;
  final AssetResolver _assetResolver;
  late final MarketauxNewsProvider _marketaux;
  late final NewsFeeds _feeds;
  final Map<String, DateTime> _lastAttempt = {};
  final Map<String, DateTime> _retryAfter = {};
  final Map<String, NewsProviderStatus> _statuses = {};
  final Map<String, ({Future<void> future, CancelToken? token})> _inFlight = {};

  Map<String, NewsProviderStatus> get statuses => Map.unmodifiable(_statuses);

  Future<List<NewsEvent>> readCached() => _store.read();

  Future<List<NewsEvent>> refresh({
    required NewsSettings settings,
    required String? finnhubApiKey,
    void Function(bool refreshing)? onRefreshChanged,
    CancelToken? cancelToken,
    void Function(List<NewsEvent>)? onEvents,
  }) async {
    await _assetResolver.all();
    final now = DateTime.now().toUtc();
    await Future.wait<void>([
      _refreshProvider(
        id: 'Finnhub',
        enabled: settings.useFinnhub,
        interval: _finnhubInterval,
        now: now,
        task: () => _feeds.finnhub(finnhubApiKey, now, cancelToken),
        onEvents: onEvents,
        onRefreshChanged: onRefreshChanged,
        cancelToken: cancelToken,
      ),
      _refreshProvider(
        id: 'BLS',
        enabled: settings.useBls,
        interval: _officialInterval,
        now: now,
        task: () => _feeds.rss(
          provider: 'BLS',
          originalSource: 'U.S. Bureau of Labor Statistics',
          url: AppConstants.blsLatestRssUrl,
          category: NewsCategory.macro,
          scope: NewsScope.macroGlobal,
          now: now,
          cancelToken: cancelToken,
        ),
        onEvents: onEvents,
        onRefreshChanged: onRefreshChanged,
        cancelToken: cancelToken,
      ),
      _refreshProvider(
        id: 'BEA',
        enabled: settings.useBea,
        interval: _officialInterval,
        now: now,
        task: () => _feeds.rss(
          provider: 'BEA',
          originalSource: 'U.S. Bureau of Economic Analysis',
          url: AppConstants.beaRssUrl,
          category: NewsCategory.macro,
          scope: NewsScope.macroGlobal,
          now: now,
          cancelToken: cancelToken,
        ),
        onEvents: onEvents,
        onRefreshChanged: onRefreshChanged,
        cancelToken: cancelToken,
      ),
      _refreshProvider(
        id: 'Federal Reserve',
        enabled: settings.useFederalReserve,
        interval: _officialInterval,
        now: now,
        task: () => _feeds.federalReserve(now, cancelToken),
        onEvents: onEvents,
        onRefreshChanged: onRefreshChanged,
        cancelToken: cancelToken,
      ),
    ]);
    return readCached();
  }

  // Token news is refreshed only for the active asset, never for every contract.
  Future<List<NewsEvent>> refreshTokenNews({
    required String symbol,
    required NewsSettings settings,
    required String? marketauxApiKey,
    void Function(bool refreshing)? onRefreshChanged,
    CancelToken? cancelToken,
    void Function(List<NewsEvent>)? onEvents,
  }) async {
    final now = DateTime.now().toUtc();
    final profile = await _assetResolver.resolve(symbol);
    await _refreshProvider(
      id: 'Marketaux',
      cacheKey: 'Marketaux:${profile.symbol}',
      enabled: settings.useMarketaux,
      interval: _marketauxInterval,
      now: now,
      task: () async {
        if (marketauxApiKey == null || marketauxApiKey.trim().isEmpty) {
          throw const AppFailure(
            kind: AppFailureKind.configuration,
            provider: 'Marketaux',
          );
        }
        final resolved = await _marketaux.resolveProfile(
          profile: profile,
          apiKey: marketauxApiKey,
          cancelToken: cancelToken,
        );
        if (resolved != profile) await _assetResolver.save(resolved);
        return _marketaux.fetch(
          profile: resolved,
          apiKey: marketauxApiKey,
          now: now,
          cancelToken: cancelToken,
        );
      },
      onEvents: onEvents,
      onRefreshChanged: onRefreshChanged,
      cancelToken: cancelToken,
    );
    return readCached();
  }

  // Build discovery queries from the resolved asset profile.
  Future<List<String>> tokenNewsSearchQueries(String symbol) async {
    final profile = await _assetResolver.resolve(symbol);
    final name = profile.projectName ?? profile.baseAsset;
    return [
      '"$name" latest news',
      '"${profile.baseAsset}" crypto news',
      '"$name" governance security regulation',
      if (profile.officialDomains.isNotEmpty)
        'site:${profile.officialDomains.first} $name',
    ];
  }

  Future<void> _refreshProvider({
    required String id,
    String? cacheKey,
    required bool enabled,
    required Duration interval,
    required DateTime now,
    required Future<List<NewsEvent>> Function() task,
    CancelToken? cancelToken,
    void Function(List<NewsEvent>)? onEvents,
    void Function(bool refreshing)? onRefreshChanged,
  }) async {
    final key = cacheKey ?? id;
    if (!enabled) {
      _statuses[id] = NewsProviderStatus(
        id: id,
        state: NewsProviderState.disabled,
      );
      return;
    }
    // Joining an already running request avoids treating it as a fresh cache hit
    // or cancelling the request owned by another refresh batch.
    final running = _inFlight[key];
    if (running != null && !(running.token?.isCancelled ?? false)) {
      await running.future;
      return;
    }
    final request = _runProvider(
      id: id,
      key: key,
      interval: interval,
      now: now,
      task: task,
      cancelToken: cancelToken,
      onEvents: onEvents,
      onRefreshChanged: onRefreshChanged,
    );
    _inFlight[key] = (future: request, token: cancelToken);
    try {
      await request;
    } finally {
      if (identical(_inFlight[key]?.future, request)) _inFlight.remove(key);
    }
  }

  Future<void> _runProvider({
    required String id,
    required String key,
    required Duration interval,
    required DateTime now,
    required Future<List<NewsEvent>> Function() task,
    CancelToken? cancelToken,
    void Function(List<NewsEvent>)? onEvents,
    void Function(bool refreshing)? onRefreshChanged,
  }) async {
    if (_retryAfter[key]?.isAfter(now) ?? false) return;
    final lastAttempt = _lastAttempt[key] ?? await _store.readRefreshTime(key);
    if (lastAttempt?.add(interval).isAfter(now) ?? false) {
      _statuses[id] = NewsProviderStatus(
        id: id,
        state: NewsProviderState.active,
        message: 'Using cached data',
        updatedAt: lastAttempt,
      );
      return;
    }
    if (cancelToken?.isCancelled ?? false) return;
    onRefreshChanged?.call(true);
    try {
      final events = await task();
      if (cancelToken?.isCancelled ?? false) return;
      final snapshot = events.isEmpty
          ? null
          : await _store.upsert(
              events
                  .map((e) => normalizeNewsEvent(e, _assetResolver.allSync))
                  .toList(),
            );
      if (cancelToken?.isCancelled ?? false) return;
      _lastAttempt[key] = now;
      await _store.writeRefreshTime(key, now);
      _statuses[id] = NewsProviderStatus(
        id: id,
        state: NewsProviderState.active,
        updatedAt: now,
      );
      if (snapshot != null) onEvents?.call(snapshot);
    } catch (error) {
      if (isRequestCancelled(error)) rethrow;
      if (error is AppFailure && error.kind == AppFailureKind.rateLimited) {
        _retryAfter[key] = now.add(error.retryAfter ?? _rateLimitBackoff);
        _statuses[id] = NewsProviderStatus(
          id: id,
          state: NewsProviderState.rateLimited,
          message: 'Rate limited; retry later',
          updatedAt: now,
        );
        return;
      }
      _statuses[id] = NewsProviderStatus(
        id: id,
        state: NewsProviderState.error,
        message: error.toString(),
        updatedAt: now,
      );
    } finally {
      onRefreshChanged?.call(false);
    }
  }

  void dispose() => _dio.close(force: true);
}
