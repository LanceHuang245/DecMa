import 'dart:async';
import 'dart:isolate';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../domain/models/news_event.dart';
import 'storage_keys.dart';

class EventStore {
  EventStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  EventStore.memory() : _preferences = null;

  static const _maxEvents = 500;
  static const _retention = Duration(days: 14);
  final SharedPreferencesAsync? _preferences;
  List<NewsEvent> _memory = const [];
  Future<void> _pendingUpsert = Future.value();
  final Map<String, DateTime> _memoryRefreshTimes = {};

  Future<List<NewsEvent>> read() async {
    if (_preferences == null) return [..._memory];
    final value = await _preferences.getString(StorageKeys.newsEvents);
    return value == null ? const [] : NewsEvent.decodeAll(value);
  }

  Future<List<NewsEvent>> upsert(List<NewsEvent> incoming) {
    final result = Completer<List<NewsEvent>>();
    _pendingUpsert = _pendingUpsert.then((_) async {
      try {
        final existing = await read();
        final merged = await _computeUpsert(existing, incoming);
        if (_preferences == null) {
          _memory = merged.events;
        } else {
          await _preferences.setString(StorageKeys.newsEvents, merged.encoded);
        }
        result.complete(merged.events);
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  static Future<({List<NewsEvent> events, String encoded})> _computeUpsert(
    List<NewsEvent> existing,
    List<NewsEvent> incoming,
  ) => Isolate.run(() => _prepareUpsert(existing, incoming));

  static ({List<NewsEvent> events, String encoded}) _prepareUpsert(
    List<NewsEvent> existing,
    List<NewsEvent> incoming,
  ) {
    final events = mergeEvents(existing, incoming);
    final cutoff = DateTime.now().toUtc().subtract(_retention);
    events.removeWhere(
      (event) =>
          event.publishedAt.toUtc().isBefore(cutoff) &&
          (event.scheduledAt == null ||
              event.scheduledAt!.toUtc().isBefore(cutoff)),
    );
    events.sort((left, right) => right.publishedAt.compareTo(left.publishedAt));
    if (events.length > _maxEvents) {
      events.removeRange(_maxEvents, events.length);
    }
    return (events: events, encoded: NewsEvent.encodeAll(events));
  }

  Future<DateTime?> readRefreshTime(String providerKey) async {
    if (_preferences == null) return _memoryRefreshTimes[providerKey];
    final value = await _preferences.getString(
      '${StorageKeys.newsRefreshPrefix}$providerKey',
    );
    return value == null ? null : DateTime.parse(value);
  }

  // Persist provider freshness separately from cached event publication times.
  Future<void> writeRefreshTime(String providerKey, DateTime value) async {
    if (_preferences == null) {
      _memoryRefreshTimes[providerKey] = value.toUtc();
      return;
    }
    await _preferences.setString(
      '${StorageKeys.newsRefreshPrefix}$providerKey',
      value.toUtc().toIso8601String(),
    );
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
    final leftUrl = _canonicalUrl(left.url);
    if (leftUrl != null && leftUrl == _canonicalUrl(right.url)) {
      return true;
    }
    // Similar topics are not proof of the same event or of official confirmation.
    final title = _title(left.headline);
    return title.isNotEmpty &&
        title == _title(right.headline) &&
        left.scope == right.scope &&
        left.publishedAt.difference(right.publishedAt).abs() <
            const Duration(hours: 6);
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
      .replaceAll(RegExp(r'[^\p{L}\p{N} ]', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String? _canonicalUrl(String? value) {
    if (value == null || value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) return value;
    final query = Map<String, String>.from(uri.queryParameters)
      ..removeWhere((key, _) => key.toLowerCase().startsWith('utm_'));
    final path = uri.path.length > 1 && uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return Uri(
      scheme: uri.scheme.toLowerCase(),
      host: uri.host.toLowerCase(),
      path: path,
      queryParameters: query.isEmpty ? null : query,
    ).toString();
  }

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
