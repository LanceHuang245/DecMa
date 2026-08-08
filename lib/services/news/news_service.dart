import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../models/news_event.dart';
import '../../models/trading_models.dart';
import 'event_store.dart';

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
  NewsService({http.Client? client, EventStore? store})
    : _client = client ?? http.Client(),
      _store = store ?? EventStore();

  static const _finnhubInterval = Duration(minutes: 10);
  static const _officialInterval = Duration(minutes: 30);
  static const _rateLimitBackoff = Duration(hours: 1);
  final http.Client _client;
  final EventStore _store;
  final Map<String, DateTime> _lastAttempt = {};
  final Map<String, DateTime> _retryAfter = {};
  final Map<String, NewsProviderStatus> _statuses = {};

  Map<String, NewsProviderStatus> get statuses => Map.unmodifiable(_statuses);

  Future<List<NewsEvent>> readCached() => _store.read();

  Future<List<NewsEvent>> refresh({
    required NewsSettings settings,
    required String? finnhubApiKey,
  }) async {
    final now = DateTime.now().toUtc();
    final events = <NewsEvent>[];
    await _refreshProvider(
      id: 'Finnhub',
      enabled: settings.useFinnhub,
      interval: _finnhubInterval,
      now: now,
      task: () => _finnhub(finnhubApiKey, now),
      output: events,
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
      ),
      output: events,
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
      ),
      output: events,
    );
    await _refreshProvider(
      id: 'Federal Reserve',
      enabled: settings.useFederalReserve,
      interval: _officialInterval,
      now: now,
      task: () => _federalReserve(now),
      output: events,
    );
    return events.isEmpty
        ? readCached()
        : _store.upsert(events.map(_normalize).toList());
  }

  Future<void> _refreshProvider({
    required String id,
    required bool enabled,
    required Duration interval,
    required DateTime now,
    required Future<List<NewsEvent>> Function() task,
    required List<NewsEvent> output,
  }) async {
    if (!enabled) {
      _statuses[id] = NewsProviderStatus(
        id: id,
        state: NewsProviderState.disabled,
      );
      return;
    }
    if (_retryAfter[id]?.isAfter(now) ?? false) return;
    if (_lastAttempt[id]?.add(interval).isAfter(now) ?? false) return;
    _lastAttempt[id] = now;
    try {
      output.addAll(await task());
      _statuses[id] = NewsProviderStatus(
        id: id,
        state: NewsProviderState.active,
        updatedAt: now,
      );
    } on _NewsRateLimitException {
      _retryAfter[id] = now.add(_rateLimitBackoff);
      _statuses[id] = NewsProviderStatus(
        id: id,
        state: NewsProviderState.rateLimited,
        message: 'Rate limited; retry later',
        updatedAt: now,
      );
    } catch (error) {
      _statuses[id] = NewsProviderStatus(
        id: id,
        state: NewsProviderState.error,
        message: error.toString(),
        updatedAt: now,
      );
    }
  }

  Future<List<NewsEvent>> _finnhub(String? apiKey, DateTime now) async {
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw StateError('Finnhub API Key is required');
    }
    final events = <NewsEvent>[];
    for (final category in ['crypto', 'general', 'forex']) {
      final uri = Uri.https('finnhub.io', '/api/v1/news', {
        'category': category,
        'token': apiKey,
      });
      final response = await _client.get(uri);
      _checkResponse(response);
      final data = jsonDecode(response.body);
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

  Future<List<NewsEvent>> _federalReserve(DateTime now) async {
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
  }) async {
    final response = await _client.get(Uri.parse(url));
    _checkResponse(response);
    return RegExp(r'<item\b[^>]*>(.*?)</item>', dotAll: true)
        .allMatches(response.body)
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
    for (final entry in _assetTerms.entries) {
      if (entry.value.any(text.contains)) directAssets.add(entry.key);
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

  static const _assetTerms = <String, List<String>>{
    'BTC': ['BITCOIN', ' BTC ', 'BTC ETF'],
    'ETH': ['ETHEREUM', ' ETH '],
    'XRP': ['RIPPLE', 'XRP LEDGER', 'XRPL', ' XRP '],
    'SOL': ['SOLANA', ' SOL '],
  };

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
      'FOMC',
      'INTEREST RATE DECISION',
      'CPI',
      'PAYROLL',
      'EMPLOYMENT SITUATION',
    ])) {
      return NewsImportance.critical;
    }
    if (_contains(text, [
      'PPI',
      'JOLTS',
      'GDP',
      'PCE',
      'SEC',
      'LAWSUIT',
      'HACK',
      'EXPLOIT',
    ])) {
      return NewsImportance.high;
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
    return category.name.toUpperCase();
  }

  bool _contains(String text, List<String> terms) => terms.any(text.contains);

  void _checkResponse(http.Response response) {
    if (response.statusCode == 429) {
      throw const _NewsRateLimitException();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}');
    }
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

  void dispose() => _client.close();
}

class _NewsRateLimitException implements Exception {
  const _NewsRateLimitException();
}
