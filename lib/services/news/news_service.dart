import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../models/asset_profile.dart';
import '../../models/news_event.dart';
import '../../models/trading_models.dart';
import '../../utils/network.dart';
import 'asset_resolver.dart';
import 'event_store.dart';
import 'marketaux_news_provider.dart';
import 'token_news_query_builder.dart';

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

class NewsService {
  NewsService({Dio? dio, EventStore? store, AssetResolver? assetResolver})
    : _dio = dio ?? createDio(),
      _store = store ?? EventStore(),
      _assetResolver = assetResolver ?? AssetResolver() {
    _marketaux = MarketauxNewsProvider(dio: _dio);
  }

  static const _finnhubInterval = Duration(minutes: 10);
  static const _marketauxInterval = Duration(minutes: 15);
  static const _officialInterval = Duration(minutes: 30);
  static const _rateLimitBackoff = Duration(hours: 1);
  final Dio _dio;
  final EventStore _store;
  final AssetResolver _assetResolver;
  late final MarketauxNewsProvider _marketaux;
  final Map<String, DateTime> _lastAttempt = {};
  final Map<String, DateTime> _retryAfter = {};
  final Map<String, NewsProviderStatus> _statuses = {};

  Map<String, NewsProviderStatus> get statuses => Map.unmodifiable(_statuses);

  Future<List<NewsEvent>> readCached() => _store.read();

  Future<List<NewsEvent>> refresh({
    required NewsSettings settings,
    required String? finnhubApiKey,
    void Function(bool refreshing)? onRefreshChanged,
    CancelToken? cancelToken,
  }) async {
    await _assetResolver.all();
    final now = DateTime.now().toUtc();
    final events = <NewsEvent>[];
    await _refreshProvider(
      id: 'Finnhub',
      enabled: settings.useFinnhub,
      interval: _finnhubInterval,
      now: now,
      task: () => _finnhub(finnhubApiKey, now, cancelToken),
      output: events,
      onRefreshChanged: onRefreshChanged,
    );
    await _refreshProvider(
      id: 'BLS',
      enabled: settings.useBls,
      interval: _officialInterval,
      now: now,
      task: () => _rss(
        provider: 'BLS',
        originalSource: 'U.S. Bureau of Labor Statistics',
        url: 'https://www.bls.gov/feed/bls_latest.rss',
        category: NewsCategory.macro,
        scope: NewsScope.macroGlobal,
        now: now,
        cancelToken: cancelToken,
      ),
      output: events,
      onRefreshChanged: onRefreshChanged,
    );
    await _refreshProvider(
      id: 'BEA',
      enabled: settings.useBea,
      interval: _officialInterval,
      now: now,
      task: () => _rss(
        provider: 'BEA',
        originalSource: 'U.S. Bureau of Economic Analysis',
        url: 'https://apps.bea.gov/rss/rss.xml',
        category: NewsCategory.macro,
        scope: NewsScope.macroGlobal,
        now: now,
        cancelToken: cancelToken,
      ),
      output: events,
      onRefreshChanged: onRefreshChanged,
    );
    await _refreshProvider(
      id: 'Federal Reserve',
      enabled: settings.useFederalReserve,
      interval: _officialInterval,
      now: now,
      task: () => _federalReserve(now, cancelToken),
      output: events,
      onRefreshChanged: onRefreshChanged,
    );
    return events.isEmpty
        ? _storedOrEmpty()
        : _store.upsert(events.map(_normalize).toList());
  }

  // Token news is refreshed only for the active asset, never for every contract.
  Future<List<NewsEvent>> refreshTokenNews({
    required String symbol,
    required NewsSettings settings,
    required String? marketauxApiKey,
    void Function(bool refreshing)? onRefreshChanged,
    CancelToken? cancelToken,
  }) async {
    final now = DateTime.now().toUtc();
    final profile = await _assetResolver.resolve(symbol);
    final events = <NewsEvent>[];
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
      output: events,
      onRefreshChanged: onRefreshChanged,
    );
    return events.isEmpty
        ? _storedOrEmpty()
        : _store.upsert(events.map(_normalize).toList());
  }

  Future<List<String>> tokenNewsSearchQueries(String symbol) async =>
      buildTokenNewsQueries(await _assetResolver.resolve(symbol));

  Future<List<NewsEvent>> _storedOrEmpty() async {
    try {
      return await readCached();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _refreshProvider({
    required String id,
    String? cacheKey,
    required bool enabled,
    required Duration interval,
    required DateTime now,
    required Future<List<NewsEvent>> Function() task,
    required List<NewsEvent> output,
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
    _lastAttempt[key] = now;
    await _store.writeRefreshTime(key, now);
    // Only actual provider requests drive the UI refresh indicator.
    onRefreshChanged?.call(true);
    try {
      output.addAll(await task());
      _statuses[id] = NewsProviderStatus(
        id: id,
        state: NewsProviderState.active,
        updatedAt: now,
      );
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

  Future<List<NewsEvent>> _finnhub(
    String? apiKey,
    DateTime now,
    CancelToken? cancelToken,
  ) async {
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw const AppFailure(
        kind: AppFailureKind.configuration,
        provider: 'Finnhub',
      );
    }
    final events = <NewsEvent>[];
    for (final category in ['crypto', 'general', 'forex']) {
      final uri = Uri.https('finnhub.io', '/api/v1/news', {
        'category': category,
        'token': apiKey,
      });
      final response = await runNetworkRequest(
        'Finnhub',
        () => _dio.getUri<String>(
          uri,
          options: networkOptions(),
          cancelToken: cancelToken,
        ),
      );
      _checkResponse(response, provider: 'Finnhub');
      final data = _json(response.data ?? '', 'Finnhub');
      if (data is! List) continue;
      for (final item in data.whereType<Map>()) {
        final published = item['datetime'] is num
            ? DateTime.fromMillisecondsSinceEpoch(
                (item['datetime'] as num).toInt() * 1000,
                isUtc: true,
              )
            : now;
        final headline = item['headline']?.toString() ?? '';
        if (headline.isEmpty) continue;
        final source = item['source']?.toString() ?? 'Finnhub';
        final url = item['url']?.toString();
        events.add(
          NewsEvent(
            eventId: 'finnhub:${item['id'] ?? '$category:$headline'}',
            headline: headline,
            summary: item['summary']?.toString(),
            provider: 'Finnhub',
            originalSource: source,
            sourceTier: NewsSourceTier.aggregator,
            category: NewsCategory.other,
            eventType: category.toUpperCase(),
            scope: NewsScope.cryptoMarket,
            importance: NewsImportance.low,
            assets: const [],
            directAssets: const [],
            indirectAssets: const [],
            country: null,
            publishedAt: published,
            receivedAt: now,
            url: url,
            verificationStatus: NewsVerificationStatus.unverified,
            isBreaking: now.difference(published) < const Duration(hours: 2),
            isOfficial: false,
            rawSourceId: item['id']?.toString(),
            sources: [
              NewsEventSource(
                provider: 'Finnhub',
                originalSource: source,
                sourceTier: NewsSourceTier.aggregator,
                url: url,
              ),
            ],
          ),
        );
      }
    }
    return events;
  }

  Future<List<NewsEvent>> _federalReserve(
    DateTime now,
    CancelToken? cancelToken,
  ) async {
    final urls = [
      'https://www.federalreserve.gov/feeds/press_monetary.xml',
      'https://www.federalreserve.gov/feeds/press_all.xml',
      'https://www.federalreserve.gov/feeds/speeches_and_testimony.xml',
    ];
    final events = <NewsEvent>[];
    for (final url in urls) {
      events.addAll(
        await _rss(
          provider: 'Federal Reserve',
          originalSource: 'Federal Reserve',
          url: url,
          category: NewsCategory.centralBank,
          scope: NewsScope.macroGlobal,
          now: now,
          cancelToken: cancelToken,
        ),
      );
    }
    return events;
  }

  Future<List<NewsEvent>> _rss({
    required String provider,
    required String originalSource,
    required String url,
    required NewsCategory category,
    required NewsScope scope,
    required DateTime now,
    CancelToken? cancelToken,
  }) async {
    final response = await runNetworkRequest(
      provider,
      () => _dio.getUri<String>(
        Uri.parse(url),
        options: networkOptions(),
        cancelToken: cancelToken,
      ),
    );
    _checkResponse(response, provider: provider);
    return RegExp(r'<item\b[^>]*>(.*?)</item>', dotAll: true)
        .allMatches(response.data ?? '')
        .map((item) => item.group(1)!)
        .map(
          (item) => _rssEvent(
            provider: provider,
            originalSource: originalSource,
            item: item,
            category: category,
            scope: scope,
            now: now,
          ),
        )
        .whereType<NewsEvent>()
        .toList();
  }

  NewsEvent? _rssEvent({
    required String provider,
    required String originalSource,
    required String item,
    required NewsCategory category,
    required NewsScope scope,
    required DateTime now,
  }) {
    final headline = _xmlValue(item, 'title');
    if (headline == null || headline.isEmpty) return null;
    final link = _xmlValue(item, 'link');
    final rawId = _xmlValue(item, 'guid') ?? link ?? headline;
    final published = _httpDate(_xmlValue(item, 'pubDate')) ?? now;
    return NewsEvent(
      eventId: '${provider.toLowerCase().replaceAll(' ', '_')}:$rawId',
      headline: headline,
      summary: _xmlValue(item, 'description'),
      provider: provider,
      originalSource: originalSource,
      sourceTier: NewsSourceTier.primary,
      category: category,
      eventType: category.name.toUpperCase(),
      scope: scope,
      importance: NewsImportance.medium,
      assets: const [],
      directAssets: const [],
      indirectAssets: const [],
      country: 'US',
      publishedAt: published,
      receivedAt: now,
      url: link,
      verificationStatus: NewsVerificationStatus.primarySourceConfirmed,
      isBreaking: now.difference(published) < const Duration(hours: 2),
      isOfficial: true,
      rawSourceId: rawId,
      sources: [
        NewsEventSource(
          provider: provider,
          originalSource: originalSource,
          sourceTier: NewsSourceTier.primary,
          url: link,
        ),
      ],
    );
  }

  // Deterministic keyword rules avoid an LLM call for routine feed items.
  NewsEvent _normalize(NewsEvent event) {
    final text = '${event.headline} ${event.summary ?? ''}'.toUpperCase();
    final directAssets = <String>{...event.directAssets};
    for (final profile in _cachedProfiles) {
      if (_mentionsAsset(text, profile)) directAssets.add(profile.baseAsset);
    }
    final category = event.category == NewsCategory.other
        ? _category(text)
        : event.category;
    final scope =
        category == NewsCategory.macro || category == NewsCategory.centralBank
        ? NewsScope.macroGlobal
        : directAssets.isNotEmpty
        ? NewsScope.assetSpecific
        : event.scope;
    final importance = _importance(text, event.importance);
    return event.copyWith(
      category: category,
      scope: scope,
      importance: importance,
      eventType: _eventType(text, category),
      directAssets: directAssets.toList()..sort(),
      assets: directAssets.toList()..sort(),
    );
  }

  List<AssetProfile> get _cachedProfiles => _assetResolver.allSync;

  bool _mentionsAsset(String text, AssetProfile profile) => profile.aliases.any(
    (alias) => RegExp(
      '(^|[^A-Z0-9])${RegExp.escape(alias.toUpperCase())}([^A-Z0-9]|\$)',
    ).hasMatch(text),
  );

  NewsCategory _category(String text) {
    if (_contains(text, ['FOMC', 'FEDERAL RESERVE', 'POWELL'])) {
      return NewsCategory.centralBank;
    }
    if (_contains(text, [
      'CPI',
      'PPI',
      'PAYROLL',
      'EMPLOYMENT',
      'JOLTS',
      'GDP',
      'PCE',
    ])) {
      return NewsCategory.macro;
    }
    if (_contains(text, ['SEC', 'REGULATION', 'LAWSUIT', 'COURT'])) {
      return NewsCategory.regulation;
    }
    if (_contains(text, ['HACK', 'EXPLOIT', 'BREACH'])) {
      return NewsCategory.security;
    }
    if (_contains(text, ['BYBIT', 'BINANCE', 'COINBASE', 'EXCHANGE'])) {
      return NewsCategory.exchange;
    }
    if (_contains(text, [
      'BITCOIN',
      'ETHEREUM',
      'RIPPLE',
      'CRYPTO',
      'BLOCKCHAIN',
    ])) {
      return NewsCategory.crypto;
    }
    return NewsCategory.market;
  }

  NewsImportance _importance(String text, NewsImportance current) {
    if (_contains(text, [
      'FOUNDER DIES',
      'BANKRUPTCY',
      'INSOLVENCY',
      'STABLECOIN DEPEG',
      'TREASURY COMPROMISE',
      'BRIDGE INCIDENT',
      'FOMC',
      'INTEREST RATE DECISION',
      'CPI',
      'PAYROLL',
      'EMPLOYMENT SITUATION',
    ])) {
      return _higherImportance(current, NewsImportance.critical);
    }
    if (_contains(text, [
      'CEO RESIGNS',
      'LEADERSHIP TRANSITION',
      'CONTROL DISPUTE',
      'GOVERNANCE CRISIS',
      'PROTOCOL PAUSED',
      'EMERGENCY UPGRADE',
      'TOKEN UNLOCK',
      'DELISTING',
      'PPI',
      'JOLTS',
      'GDP',
      'PCE',
      'SEC',
      'LAWSUIT',
      'HACK',
      'EXPLOIT',
    ])) {
      return _higherImportance(current, NewsImportance.high);
    }
    return current;
  }

  String _eventType(String text, NewsCategory category) {
    for (final type in ['CPI', 'PPI', 'JOLTS', 'PCE', 'GDP', 'FOMC']) {
      if (text.contains(type)) return type;
    }
    if (_contains(text, ['PAYROLL', 'EMPLOYMENT SITUATION'])) {
      return 'NFP_EMPLOYMENT';
    }
    if (_contains(text, [
      'FOUNDER DIES',
      'CEO RESIGNS',
      'CEO APPOINTED',
      'LEADERSHIP TRANSITION',
    ])) {
      return 'PROJECT_LEADERSHIP';
    }
    if (_contains(text, ['GOVERNANCE', 'CONTROL DISPUTE'])) {
      return 'GOVERNANCE';
    }
    if (_contains(text, ['HACK', 'EXPLOIT', 'BREACH', 'TREASURY COMPROMISE'])) {
      return 'SECURITY';
    }
    if (_contains(text, ['SEC', 'LAWSUIT', 'COURT', 'REGULATION'])) {
      return 'LEGAL';
    }
    if (_contains(text, ['TOKEN UNLOCK', 'EMISSIONS', 'VESTING'])) {
      return 'TOKENOMICS';
    }
    if (_contains(text, ['DELISTING', 'LISTING'])) return 'EXCHANGE';
    if (_contains(text, ['PROTOCOL PAUSED', 'EMERGENCY UPGRADE', 'UPGRADE'])) {
      return 'PROTOCOL_OPERATION';
    }
    if (_contains(text, ['BANKRUPTCY', 'INSOLVENCY'])) return 'INSOLVENCY';
    if (_contains(text, ['PARTNERSHIP', 'INTEGRATION'])) return 'PARTNERSHIP';
    return category.name.toUpperCase();
  }

  NewsImportance _higherImportance(
    NewsImportance current,
    NewsImportance classified,
  ) => classified.index < current.index ? classified : current;

  bool _contains(String text, List<String> terms) => terms.any(text.contains);

  Object? _json(String body, String provider) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw AppFailure(
        kind: AppFailureKind.invalidResponse,
        provider: provider,
      );
    }
  }

  void _checkResponse(Response<dynamic> response, {required String provider}) {
    if (response.statusCode == 429) {
      throw AppFailure.fromResponse(response, provider: provider);
    }
    requireSuccessfulResponse(response, provider: provider);
  }

  String? _xmlValue(String item, String tag) {
    final match = RegExp(
      '<$tag\\b[^>]*>(.*?)</$tag>',
      dotAll: true,
    ).firstMatch(item);
    if (match == null) return null;
    return match
        .group(1)!
        .replaceAll('<![CDATA[', '')
        .replaceAll(']]>', '')
        .replaceAll(RegExp('<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .trim();
  }

  DateTime? _httpDate(String? value) {
    if (value == null) return null;
    try {
      return HttpDate.parse(value).toUtc();
    } catch (_) {
      return DateTime.tryParse(value)?.toUtc();
    }
  }

  void dispose() => _dio.close(force: true);
}
