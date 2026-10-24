import 'package:decma/domain/models/news_event.dart';
import 'package:decma/domain/news/event_selector.dart';
import 'package:decma/domain/news/news_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 8, 12);

  // Mirror how Finnhub general items arrive before normalization.
  NewsEvent feedItem(String headline) => NewsEvent(
    eventId: headline,
    headline: headline,
    provider: 'Finnhub',
    originalSource: 'Reuters',
    sourceTier: NewsSourceTier.aggregator,
    category: NewsCategory.other,
    eventType: 'GENERAL',
    scope: NewsScope.cryptoMarket,
    importance: NewsImportance.low,
    assets: const [],
    directAssets: const [],
    indirectAssets: const [],
    country: null,
    publishedAt: now.subtract(const Duration(hours: 6)),
    receivedAt: now,
    verificationStatus: NewsVerificationStatus.unverified,
    isBreaking: false,
    isOfficial: false,
    sources: const [],
  );

  test('geopolitical headlines become high-importance macro events', () {
    final event = normalizeNewsEvent(
      feedItem('Missile attack hits Kyiv as ceasefire talks stall'),
      const [],
    );

    expect(event.category, NewsCategory.macro);
    expect(event.scope, NewsScope.macroGlobal);
    expect(event.importance, NewsImportance.high);
    expect(event.eventType, 'GEOPOLITICS');

    final snapshot = const EventSelector().select(
      events: [event],
      symbol: 'BTCUSDT',
      now: now,
    );
    expect(snapshot.macroEvents.map((e) => e.eventId), [event.eventId]);
  });

  test('keywords only match whole words', () {
    for (final headline in [
      'Software maker issues profit warning',
      'Second-quarter revenue beats estimates',
    ]) {
      final event = normalizeNewsEvent(feedItem(headline), const []);
      expect(event.category, NewsCategory.market, reason: headline);
      expect(event.importance, NewsImportance.low, reason: headline);
    }
  });

  test('inflected keywords still match', () {
    final event = normalizeNewsEvent(
      feedItem('Exchange wallet hacked after exploits'),
      const [],
    );

    expect(event.eventType, 'SECURITY');
    expect(event.importance, NewsImportance.high);
  });
}
