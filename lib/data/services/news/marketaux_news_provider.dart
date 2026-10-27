import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../domain/models/asset_profile.dart';
import '../../../app_constants.dart';
import '../../../domain/models/news_event.dart';
import '../../../utils/network.dart';

/// Fetches only the currently relevant token and normalizes it into NewsEvent.
class MarketauxNewsProvider {
  MarketauxNewsProvider({required this._dio});

  static const _providerVersion = 'v1';
  final Dio _dio;

  Future<AssetProfile> resolveProfile({
    required AssetProfile profile,
    required String apiKey,
    CancelToken? cancelToken,
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
    }, cancelToken: cancelToken);
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
                    _normalized(item['name']) ==
                    _normalized(profile.projectName!),
              )
              .toList();
    final matches = exactSymbol.isNotEmpty ? exactSymbol : exactName;
    final match = matches.length == 1 ? matches.single : null;
    final state = match != null
        ? MarketauxResolution.resolved
        : matches.isEmpty
        ? MarketauxResolution.notFound
        : MarketauxResolution.ambiguous;
    return profile.copyWith(
      projectName: profile.projectName ?? match?['name'],
      aliases: {
        ...profile.aliases,
        if (match != null) match['name'] as String,
      }.toList(),
      marketauxSymbol: match?['symbol'],
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
    CancelToken? cancelToken,
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
            cancelToken: cancelToken,
          );
    if (primary.isNotEmpty || profile.projectName == null) return primary;
    return _news(
      apiKey: apiKey,
      now: now,
      profile: profile,
      query: {'search': profile.projectName!, 'must_have_entities': 'true'},
      since: since,
      cancelToken: cancelToken,
    );
  }

  Future<List<NewsEvent>> _news({
    required String apiKey,
    required DateTime now,
    required AssetProfile profile,
    required Map<String, String> query,
    required DateTime since,
    CancelToken? cancelToken,
  }) async {
    final response = await _get('/v1/news/all', {
      'api_token': apiKey,
      ...query,
      'language': 'en',
      'limit': '3',
      'published_after': _marketauxTime(since),
    }, cancelToken: cancelToken);
    return _items(response)
        .where((item) => _matchesProfile(item, profile))
        .map((item) => normalizeArticle(item, profile: profile, now: now))
        .toList();
  }

  // Public for deterministic normalization tests; Marketaux remains an aggregator.
  static NewsEvent normalizeArticle(
    Map item, {
    required AssetProfile profile,
    required DateTime now,
  }) {
    final String url = item['url'];
    final String source = item['source'];
    final published = DateTime.parse(item['published_at']).toUtc();
    final String rawId = item['uuid'];
    return NewsEvent(
      eventId: 'marketaux:$rawId',
      headline: item['title'],
      summary: item['description'] ?? item['snippet'],
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

  Future<Object?> _get(
    String path,
    Map<String, String> parameters, {
    CancelToken? cancelToken,
  }) async {
    final response = await runNetworkRequest(
      'Marketaux',
      () => _dio.getUri<String>(
        Uri.https(AppConstants.marketauxApiHost, path, parameters),
        options: networkOptions(),
        cancelToken: cancelToken,
      ),
    );
    if (response.statusCode == 429 ||
        (response.statusCode == 403 &&
            (response.data ?? '').toLowerCase().contains('rate'))) {
      throw const AppFailure(
        kind: AppFailureKind.rateLimited,
        provider: 'Marketaux',
      );
    }
    requireSuccessfulResponse(response, provider: 'Marketaux');
    try {
      return jsonDecode(response.data ?? '');
    } on FormatException {
      throw const AppFailure(
        kind: AppFailureKind.invalidResponse,
        provider: 'Marketaux',
      );
    }
  }

  List<Map> _items(dynamic response) => List<Map>.from(response['data']);

  bool _isCryptoEntity(Map item) => item['type'] == 'cryptocurrency';

  String _entityTicker(Map item) =>
      (item['symbol'] as String).toUpperCase().split(':').last;

  // Only accept articles whose Marketaux entity data confirms the active token.
  bool _matchesProfile(Map article, AssetProfile profile) {
    return (article['entities'] as List).any((entity) {
      if (!_isCryptoEntity(entity)) return false;
      if (entity['match_score'] <= 0) return false;
      final symbolMatches =
          entity['symbol'] == profile.marketauxSymbol ||
          _entityTicker(entity) == profile.baseAsset;
      final nameMatches =
          profile.projectName != null &&
          _normalized(entity['name']) == _normalized(profile.projectName!);
      return symbolMatches || nameMatches;
    });
  }

  String _normalized(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  String _marketauxTime(DateTime value) =>
      value.toUtc().toIso8601String().split('.').first;
}
