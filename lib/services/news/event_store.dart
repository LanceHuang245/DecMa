import 'package:shared_preferences/shared_preferences.dart';

import '../../models/news_event.dart';

class EventStore {
  EventStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  EventStore.memory() : _preferences = null;

  static const _eventsKey = 'decma.news.events.v1';
  static const _maxEvents = 500;
  static const _retention = Duration(days: 14);
  final SharedPreferencesAsync? _preferences;
  List<NewsEvent> _memory = const [];

  Future<List<NewsEvent>> read() async {
    if (_preferences == null) return [..._memory];
    final value = await _preferences.getString(_eventsKey);
    return value == null ? const [] : NewsEvent.decodeAll(value);
  }

  Future<List<NewsEvent>> upsert(List<NewsEvent> incoming) async {
    final events = mergeEvents(await read(), incoming);
    final now = DateTime.now().toUtc();
    events.removeWhere(
      (event) =>
          event.publishedAt.toUtc().isBefore(now.subtract(_retention)) &&
          (event.scheduledAt == null ||
              event.scheduledAt!.toUtc().isBefore(now.subtract(_retention))),
    );
    events.sort((left, right) => right.publishedAt.compareTo(left.publishedAt));
    if (events.length > _maxEvents) {
      events.removeRange(_maxEvents, events.length);
    }
    if (_preferences == null) {
      _memory = events;
    } else {
      await _preferences.setString(_eventsKey, NewsEvent.encodeAll(events));
    }
    return events;
  }

  // Shared merge logic is deterministic and testable without a local store.
  static List<NewsEvent> mergeEvents(
    List<NewsEvent> existing,
    List<NewsEvent> incoming,
  ) {
    final events = [...existing];
    for (final event in incoming) {
      final match = events.indexWhere((saved) => _sameEvent(saved, event));
      if (match < 0) {
        events.add(event);
      } else {
        events[match] = _merge(events[match], event);
      }
    }
    return events;
  }

  static bool _sameEvent(NewsEvent left, NewsEvent right) {
    if (left.provider == right.provider &&
        left.rawSourceId != null &&
        left.rawSourceId == right.rawSourceId) {
      return true;
    }
    if (left.url != null && left.url == right.url) return true;
    final sameTitle = _title(left.headline) == _title(right.headline);
    final sameType = left.eventType == right.eventType;
    final sameEntity =
        left.scope == NewsScope.macroGlobal ||
        left.directAssets.any(right.directAssets.contains);
    final nearTime =
        left.publishedAt.difference(right.publishedAt).abs() <
        const Duration(hours: 6);
    return nearTime &&
        left.scope == right.scope &&
        (sameTitle || (sameType && sameEntity));
  }

  // Merge repeated coverage into one event so it remains one evidence item.
  static NewsEvent _merge(NewsEvent saved, NewsEvent incoming) {
    final sources = <NewsEventSource>[...saved.sources];
    for (final source in incoming.sources) {
      if (!sources.any(
        (item) => item.url == source.url && item.provider == source.provider,
      )) {
        sources.add(source);
      }
    }
    return saved.copyWith(
      summary: saved.summary ?? incoming.summary,
      sourceTier: _higherTier(saved.sourceTier, incoming.sourceTier),
      importance: _higherImportance(saved.importance, incoming.importance),
      assets: {...saved.assets, ...incoming.assets}.toList()..sort(),
      directAssets: {...saved.directAssets, ...incoming.directAssets}.toList()
        ..sort(),
      indirectAssets: {
        ...saved.indirectAssets,
        ...incoming.indirectAssets,
      }.toList()..sort(),
      verificationStatus: _higherVerification(
        saved.verificationStatus,
        incoming.verificationStatus,
      ),
      isBreaking: saved.isBreaking || incoming.isBreaking,
      isOfficial: saved.isOfficial || incoming.isOfficial,
      sources: sources,
    );
  }

  static String _title(String title) => title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static NewsSourceTier _higherTier(
    NewsSourceTier left,
    NewsSourceTier right,
  ) => left.index <= right.index ? left : right;

  static NewsImportance _higherImportance(
    NewsImportance left,
    NewsImportance right,
  ) => left.index <= right.index ? left : right;

  static NewsVerificationStatus _higherVerification(
    NewsVerificationStatus left,
    NewsVerificationStatus right,
  ) => left.index >= right.index ? left : right;
}
