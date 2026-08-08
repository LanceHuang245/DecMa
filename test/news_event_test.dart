import 'package:decma/models/news_event.dart';
import 'package:decma/services/news/event_selector.dart';
import 'package:decma/services/news/event_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final baseTime = DateTime.utc(2026, 8, 8, 12);

  NewsEvent event({
    String id = 'event-1',
    String provider = 'Finnhub',
    String headline = 'US CPI release',
    NewsSourceTier tier = NewsSourceTier.aggregator,
    NewsVerificationStatus verification = NewsVerificationStatus.unverified,
    NewsScope scope = NewsScope.macroGlobal,
    NewsImportance importance = NewsImportance.critical,
    List<String> assets = const [],
    List<String> directAssets = const [],
    DateTime? publishedAt,
    DateTime? scheduledAt,
    String? url,
  }) => NewsEvent(
    eventId: id,
    headline: headline,
    provider: provider,
    originalSource: provider,
    sourceTier: tier,
    category: NewsCategory.macro,
    eventType: 'CPI',
    scope: scope,
    importance: importance,
    assets: assets,
    directAssets: directAssets,
    indirectAssets: const [],
    country: 'US',
    publishedAt: publishedAt ?? baseTime,
    receivedAt: baseTime,
    scheduledAt: scheduledAt,
    url: url,
    verificationStatus: verification,
    isBreaking: false,
    isOfficial: tier == NewsSourceTier.primary,
    rawSourceId: id,
    sources: [
      NewsEventSource(
        provider: provider,
        originalSource: provider,
        sourceTier: tier,
        url: url,
      ),
    ],
  );

  test('NewsEvent JSON keeps optional economic fields', () {
    final original = event(
      assets: const ['BTC'],
      directAssets: const ['BTC'],
      url: 'https://example.test/cpi',
    ).copyWith(actual: '3.1', forecast: '3.2', previous: '3.4', unit: '%');

    final restored = NewsEvent.decodeAll(
      NewsEvent.encodeAll([original]),
    ).single;

    expect(restored.eventId, original.eventId);
    expect(restored.actual, '3.1');
    expect(restored.forecast, '3.2');
    expect(restored.directAssets, ['BTC']);
  });

  test('EventStore merges duplicate coverage into one official event', () {
    final aggregated = event(url: 'https://example.test/reuters');
    final official = event(
      id: 'bls-cpi',
      provider: 'BLS',
      headline: 'Consumer prices increase in July',
      tier: NewsSourceTier.primary,
      verification: NewsVerificationStatus.primarySourceConfirmed,
      url: 'https://bls.gov/cpi',
      publishedAt: baseTime.add(const Duration(minutes: 10)),
    );

    final merged = EventStore.mergeEvents([aggregated], [official]).single;

    expect(merged.sourceTier, NewsSourceTier.primary);
    expect(
      merged.verificationStatus,
      NewsVerificationStatus.primarySourceConfirmed,
    );
    expect(merged.sources, hasLength(2));
  });

  test('EventSelector limits output to relevant current events', () {
    final selector = EventSelector();
    final snapshot = selector.select(
      now: baseTime,
      symbol: 'XRPUSDT',
      events: [
        event(
          id: 'xrp',
          headline: 'Ripple court update',
          scope: NewsScope.assetSpecific,
          importance: NewsImportance.high,
          assets: const ['XRP'],
          directAssets: const ['XRP'],
        ),
        event(
          id: 'future-fomc',
          headline: 'FOMC decision',
          scheduledAt: baseTime.add(const Duration(hours: 4)),
        ),
        event(
          id: 'stale',
          headline: 'Old market news',
          importance: NewsImportance.low,
          publishedAt: baseTime.subtract(const Duration(days: 2)),
        ),
      ],
    );

    expect(snapshot.assetSpecificEvents.map((item) => item.eventId), ['xrp']);
    expect(snapshot.upcomingCriticalEvents.map((item) => item.eventId), [
      'future-fomc',
    ]);
    expect(snapshot.macroEvents, isEmpty);
  });
}
