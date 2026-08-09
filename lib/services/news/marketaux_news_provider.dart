import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../models/asset_profile.dart';
import '../../models/news_event.dart';

class MarketauxRateLimitException implements Exception {
  const MarketauxRateLimitException();
}

/// Fetches only the currently relevant token and normalizes it into NewsEvent.
class MarketauxNewsProvider {
  MarketauxNewsProvider({required this._client});

  static const _providerVersion = 'v1';
  final http.Client _client;

  Future<AssetProfile> resolveProfile({
    required AssetProfile profile,
    required String apiKey,
  }) async {
    final now = DateTime.now().toUtc();
    if (profile.marketauxResolution == MarketauxResolution.resolved &&
        profile.marketauxSymbol != null &&
        profile.marketauxProviderVersion == _providerVersion) {
      return profile;
    }
    if (profile.marketauxRetryAfter?.isAfter(now) ?? false) return profile;
    final response = await _get('/v1/entity/search', {
      'api_token': apiKey,
      'search': profile.projectName ?? profile.baseAsset,
      'types': 'cryptocurrency',
    });
    final data = _items(response);
    final candidates = data.where(_isCryptoEntity).toList();
    final exactSymbol = candidates
        .where((item) => _entityTicker(item) == profile.baseAsset)
        .toList();
    final exactName = profile.projectName == null
        ? const <Map>[]
        : candidates
              .where(
                (item) =>
                    _normalized(item['name']?.toString()) ==
                    _normalized(profile.projectName),
              )
              .toList();
    final matches = exactSymbol.isNotEmpty ? exactSymbol : exactName;
    final match = matches.length == 1 ? matches.single : null;
    final state = match != null
        ? MarketauxResolution.resolved
        : matches.isEmpty
        ? MarketauxResolution.notFound
        : MarketauxResolution.ambiguous;
    final symbol = match?['symbol']?.toString();
    return profile.copyWith(
      projectName: profile.projectName ?? match?['name']?.toString(),
      aliases: {
        ...profile.aliases,
        if (match?['name']?.toString().isNotEmpty ?? false)
          match!['name'].toString(),
      }.toList(),
      marketauxSymbol: symbol == null || symbol.isEmpty ? null : symbol,
      clearMarketauxSymbol: state != MarketauxResolution.resolved,
      marketauxResolution: state,
      marketauxResolvedAt: now,
      marketauxRetryAfter: state == MarketauxResolution.notFound
          ? now.add(const Duration(days: 1))
          : state == MarketauxResolution.ambiguous
          ? now.add(const Duration(hours: 6))
          : null,
      marketauxProviderVersion: _providerVersion,
    );
  }

  Future<List<NewsEvent>> fetch({
    required AssetProfile profile,
    required String apiKey,
    required DateTime now,
  }) async {
    final since = now.subtract(const Duration(hours: 24));
    final primary = profile.marketauxSymbol == null
        ? const <NewsEvent>[]
        : await _news(
            apiKey: apiKey,
            now: now,
            profile: profile,
            query: {
              'symbols': profile.marketauxSymbol!,
              'filter_entities': 'true',
            },
            since: since,
          );
    if (primary.isNotEmpty || profile.projectName == null) return primary;
    return _news(
      apiKey: apiKey,
      now: now,
      profile: profile,
      query: {'search': profile.projectName!, 'must_have_entities': 'true'},
      since: since,
    );
  }

  Future<List<NewsEvent>> _news({
    required String apiKey,
    required DateTime now,
    required AssetProfile profile,
    required Map<String, String> query,
    required DateTime since,
  }) async {
    final response = await _get('/v1/news/all', {
      'api_token': apiKey,
      ...query,
      'language': 'en',
      'limit': '3',
      'published_after': _marketauxTime(since),
    });
    return _items(response)
        .where((item) => _matchesProfile(item, profile))
        .map((item) => normalizeArticle(item, profile: profile, now: now))
        .whereType<NewsEvent>()
        .toList();
  }

  // Public for deterministic normalization tests; Marketaux remains an aggregator.
  static NewsEvent? normalizeArticle(
    Map item, {
    required AssetProfile profile,
    required DateTime now,
  }) {
    final headline = item['title']?.toString().trim() ?? '';
    if (headline.isEmpty) return null;
    final url = item['url']?.toString();
    final source = item['source']?.toString() ?? 'Marketaux';
    final published =
        DateTime.tryParse(item['published_at']?.toString() ?? '')?.toUtc() ??
        now;
    final rawId = item['uuid']?.toString() ?? url ?? headline;
    return NewsEvent(
      eventId: 'marketaux:$rawId',
      headline: headline,
      summary: item['description']?.toString() ?? item['snippet']?.toString(),
      provider: 'Marketaux',
      originalSource: source,
      sourceTier: NewsSourceTier.aggregator,
      category: NewsCategory.crypto,
      eventType: 'TOKEN_NEWS',
      scope: NewsScope.assetSpecific,
      importance: NewsImportance.low,
      assets: [profile.baseAsset],
      directAssets: [profile.baseAsset],
      indirectAssets: const [],
      country: null,
      publishedAt: published,
      receivedAt: now,
      url: url,
      verificationStatus: NewsVerificationStatus.unverified,
      isBreaking: now.difference(published) < const Duration(hours: 2),
      isOfficial: false,
      rawSourceId: rawId,
      sources: [
        NewsEventSource(
          provider: 'Marketaux',
          originalSource: source,
          sourceTier: NewsSourceTier.aggregator,
          url: url,
        ),
      ],
    );
  }

  Future<Object?> _get(String path, Map<String, String> parameters) async {
    final response = await _client.get(
      Uri.https('api.marketaux.com', path, parameters),
    );
    if (response.statusCode == 429 ||
        (response.statusCode == 403 &&
            response.body.toLowerCase().contains('rate'))) {
      throw const MarketauxRateLimitException();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}');
    }
    return jsonDecode(response.body);
  }

  List<Map> _items(Object? response) {
    if (response is! Map || response['data'] is! List) return const [];
    return (response['data'] as List).whereType<Map>().toList();
  }

  bool _isCryptoEntity(Map item) =>
      item['type']?.toString().toLowerCase() == 'cryptocurrency';

  String _entityTicker(Map item) =>
      item['symbol']?.toString().toUpperCase().split(':').last ?? '';

  // Only accept articles whose Marketaux entity data confirms the active token.
  bool _matchesProfile(Map article, AssetProfile profile) {
    final entities = article['entities'];
    if (entities is! List) return false;
    return entities.whereType<Map>().any((entity) {
      if (!_isCryptoEntity(entity)) return false;
      final score = entity['match_score'];
      if (score is num && score <= 0) return false;
      final symbolMatches =
          entity['symbol']?.toString() == profile.marketauxSymbol ||
          _entityTicker(entity) == profile.baseAsset;
      final nameMatches =
          profile.projectName != null &&
          _normalized(entity['name']?.toString()) ==
              _normalized(profile.projectName);
      return symbolMatches || nameMatches;
    });
  }

  String _normalized(String? value) =>
      value?.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '') ?? '';

  String _marketauxTime(DateTime value) =>
      value.toUtc().toIso8601String().split('.').first;
}
