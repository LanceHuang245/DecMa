import 'dart:async';
import 'dart:convert';

import 'package:decma/models/asset_profile.dart';
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
        'entities': [
          {
            'symbol': 'CC:ONDO',
            'name': 'Ondo Finance',
            'type': 'cryptocurrency',
            'match_score': 90,
          },
        ],
      },
      profile: AssetResolver.fromSymbol('ONDOUSDT'),
      now: _now,
    )!;

    expect(event.directAssets, ['ONDO']);
    expect(event.scope, NewsScope.assetSpecific);
    expect(event.verificationStatus, NewsVerificationStatus.unverified);
  });

  test('Marketaux resolves a long-tail canonical crypto entity', () async {
    final provider = MarketauxNewsProvider(
      client: _JsonClient({
        'data': [
          {'symbol': 'CC:KAITO', 'name': 'Kaito', 'type': 'cryptocurrency'},
        ],
      }),
    );

    final profile = await provider.resolveProfile(
      profile: AssetResolver.fromSymbol('KAITOUSDT'),
      apiKey: 'test-key',
    );

    expect(profile.marketauxSymbol, 'CC:KAITO');
    expect(profile.projectName, 'Kaito');
    expect(profile.marketauxResolution, MarketauxResolution.resolved);
  });

  test('an unresolved Marketaux entity receives a future retry time', () async {
    final provider = MarketauxNewsProvider(client: _JsonClient({'data': []}));

    final profile = await provider.resolveProfile(
      profile: AssetResolver.fromSymbol('UNKNOWNUSDT'),
      apiKey: 'test-key',
    );

    expect(profile.marketauxResolution, MarketauxResolution.notFound);
    expect(profile.marketauxRetryAfter, isNotNull);
    expect(
      profile.marketauxRetryAfter!.isAfter(DateTime.now().toUtc()),
      isTrue,
    );
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

  test('distinct ONDO news within six hours remain separate events', () {
    final founderDeath = _event(
      id: 'founder',
      headline: 'Ondo founder dies',
      directAssets: const ['ONDO'],
      scope: NewsScope.assetSpecific,
      eventType: 'PROJECT_LEADERSHIP',
    );
    final ceoAppointment = _event(
      id: 'ceo',
      headline: 'Ondo appoints a new CEO',
      directAssets: const ['ONDO'],
      scope: NewsScope.assetSpecific,
      eventType: 'PROJECT_LEADERSHIP',
      publishedAt: _now.add(const Duration(hours: 2)),
    );

    expect(
      EventStore.mergeEvents([founderDeath], [ceoAppointment]),
      hasLength(2),
    );
  });

  test(
    'project leadership events receive deterministic high importance',
    () async {
      final service = NewsService(
        client: _JsonClient([
          {
            'id': 'leadership',
            'headline': 'Ondo CEO resigns after governance dispute',
            'source': 'Example News',
            'datetime': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
          },
        ]),
        store: EventStore.memory(),
        assetResolver: AssetResolver.memory(),
      );

      final events = await service.refresh(
        settings: const NewsSettings(
          useFinnhub: true,
          useMarketaux: false,
          useBls: false,
          useBea: false,
          useFederalReserve: false,
        ),
        finnhubApiKey: 'test-key',
      );

      expect(events.single.eventType, 'PROJECT_LEADERSHIP');
      expect(events.single.importance, NewsImportance.high);
      service.dispose();
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

  test('token refresh TTL survives a NewsService restart', () async {
    final store = EventStore.memory();
    final first = NewsService(
      client: _QueueJsonClient([
        {
          'data': [
            {
              'symbol': 'CC:ONDO',
              'name': 'Ondo Finance',
              'type': 'cryptocurrency',
            },
          ],
        },
        {
          'data': [
            {
              'uuid': 'ondo-cached',
              'title': 'Ondo Finance update',
              'source': 'Example News',
              'published_at': DateTime.now().toUtc().toIso8601String(),
              'entities': [
                {
                  'symbol': 'CC:ONDO',
                  'name': 'Ondo Finance',
                  'type': 'cryptocurrency',
                  'match_score': 90,
                },
              ],
            },
          ],
        },
      ]),
      store: store,
      assetResolver: AssetResolver.memory(),
    );
    await first.refreshTokenNews(
      symbol: 'ONDOUSDT',
      settings: _marketauxSettings,
      marketauxApiKey: 'test-key',
    );
    first.dispose();

    final secondClient = _CountingErrorClient();
    final second = NewsService(
      client: secondClient,
      store: store,
      assetResolver: AssetResolver.memory(),
    );
    final cached = await second.refreshTokenNews(
      symbol: 'ONDOUSDT',
      settings: _marketauxSettings,
      marketauxApiKey: 'test-key',
    );

    expect(secondClient.calls, 0);
    expect(cached.single.eventId, 'marketaux:ondo-cached');
    expect(second.statuses['Marketaux']?.state, NewsProviderState.active);
    second.dispose();
  });
}

const _marketauxSettings = NewsSettings(
  useFinnhub: false,
  useMarketaux: true,
  useBls: false,
  useBea: false,
  useFederalReserve: false,
);

class _ErrorClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(utf8.encode('{}')), 500);
}

class _JsonClient extends http.BaseClient {
  _JsonClient(this.body);

  final Object body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), 200);
}

class _QueueJsonClient extends http.BaseClient {
  _QueueJsonClient(this.responses);

  final List<Object> responses;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = responses.removeAt(0);
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      200,
    );
  }
}

class _CountingErrorClient extends http.BaseClient {
  var calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    return http.StreamedResponse(Stream.value(utf8.encode('{}')), 500);
  }
}

NewsEvent _event({
  required String id,
  String provider = 'Marketaux',
  String headline = 'Ondo update',
  String? url,
  String eventType = 'TOKEN_NEWS',
  DateTime? publishedAt,
  required List<String> directAssets,
  required NewsScope scope,
}) => NewsEvent(
  eventId: id,
  headline: headline,
  provider: provider,
  originalSource: provider,
  sourceTier: NewsSourceTier.aggregator,
  category: NewsCategory.crypto,
  eventType: eventType,
  scope: scope,
  importance: NewsImportance.low,
  assets: directAssets,
  directAssets: directAssets,
  indirectAssets: const [],
  country: null,
  publishedAt: publishedAt ?? _now,
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
