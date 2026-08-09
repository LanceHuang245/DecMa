import 'dart:async';
import 'dart:convert';

import 'package:decma/models/news_event.dart';
import 'package:decma/models/trading_models.dart';
import 'package:decma/services/news/asset_resolver.dart';
import 'package:decma/services/news/event_selector.dart';
import 'package:decma/services/news/event_store.dart';
import 'package:decma/services/news/marketaux_news_provider.dart';
import 'package:decma/services/news/news_service.dart';
import 'package:decma/services/news/token_news_query_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

final _now = DateTime.utc(2026, 8, 9, 12);

void main() {
  test('ONDOUSDT resolves to a cached Ondo asset profile', () async {
    final resolver = AssetResolver.memory();
    final first = await resolver.resolve('ONDOUSDT');
    final second = await resolver.resolve('ONDOUSDT');

    expect(first.baseAsset, 'ONDO');
    expect(first.projectName, 'Ondo Finance');
    expect(identical(first, second), isTrue);
  });

  test('Marketaux Ondo article is normalized as an asset-specific event', () {
    final event = MarketauxNewsProvider.normalizeArticle(
      {
        'uuid': 'ondo-1',
        'title': 'Ondo Finance announces a protocol update',
        'description': 'Update details.',
        'source': 'Example News',
        'url': 'https://example.test/ondo',
        'published_at': _now.toIso8601String(),
      },
      profile: AssetResolver.fromSymbol('ONDOUSDT'),
      now: _now,
    )!;

    expect(event.directAssets, ['ONDO']);
    expect(event.scope, NewsScope.assetSpecific);
    expect(event.verificationStatus, NewsVerificationStatus.unverified);
  });

  test('ONDO-specific events enter the ONDO EventSnapshot', () {
    final event = _event(
      id: 'ondo',
      directAssets: const ['ONDO'],
      scope: NewsScope.assetSpecific,
    );
    final snapshot = EventSelector().select(
      events: [event],
      symbol: 'ONDOUSDT',
      now: _now,
    );

    expect(snapshot.assetSpecificEvents.single.eventId, 'ondo');
  });

  test(
    'Marketaux and Finnhub coverage of the same URL merge into one event',
    () {
      final marketaux = _event(
        id: 'marketaux',
        provider: 'Marketaux',
        url: 'https://example.test/ondo',
        directAssets: const ['ONDO'],
        scope: NewsScope.assetSpecific,
      );
      final finnhub = _event(
        id: 'finnhub',
        provider: 'Finnhub',
        url: 'https://example.test/ondo',
        directAssets: const ['ONDO'],
        scope: NewsScope.assetSpecific,
      );

      expect(EventStore.mergeEvents([marketaux], [finnhub]), hasLength(1));
    },
  );

  test('Empty token coverage retains bounded discovery fallback queries', () {
    final queries = buildTokenNewsQueries(AssetResolver.fromSymbol('ONDOUSDT'));

    expect(queries, isNotEmpty);
    expect(queries.first, contains('Ondo Finance'));
  });

  test(
    'Marketaux failure leaves the existing news pipeline available',
    () async {
      final service = NewsService(
        client: _ErrorClient(),
        store: EventStore.memory(),
        assetResolver: AssetResolver.memory(),
      );
      final events = await service.refreshTokenNews(
        symbol: 'ONDOUSDT',
        settings: const NewsSettings(
          useFinnhub: false,
          useMarketaux: true,
          useBls: false,
          useBea: false,
          useFederalReserve: false,
        ),
        marketauxApiKey: 'test-key',
      );

      expect(events, isEmpty);
      expect(service.statuses['Marketaux']?.state, NewsProviderState.error);
      service.dispose();
    },
  );
}

class _ErrorClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(utf8.encode('{}')), 500);
}

NewsEvent _event({
  required String id,
  String provider = 'Marketaux',
  String? url,
  required List<String> directAssets,
  required NewsScope scope,
}) => NewsEvent(
  eventId: id,
  headline: 'Ondo update',
  provider: provider,
  originalSource: provider,
  sourceTier: NewsSourceTier.aggregator,
  category: NewsCategory.crypto,
  eventType: 'TOKEN_NEWS',
  scope: scope,
  importance: NewsImportance.low,
  assets: directAssets,
  directAssets: directAssets,
  indirectAssets: const [],
  country: null,
  publishedAt: _now,
  receivedAt: _now,
  url: url,
  verificationStatus: NewsVerificationStatus.unverified,
  isBreaking: false,
  isOfficial: false,
  rawSourceId: id,
  sources: [
    NewsEventSource(
      provider: provider,
      originalSource: provider,
      sourceTier: NewsSourceTier.aggregator,
      url: url,
    ),
  ],
);
