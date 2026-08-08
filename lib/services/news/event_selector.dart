import '../../models/news_event.dart';

class EventSelector {
  const EventSelector();

  static const _upcomingWindow = Duration(hours: 24);
  static const _breakingWindow = Duration(hours: 2);
  static const _assetWindow = Duration(hours: 24);
  static const _cryptoWindow = Duration(hours: 12);
  static const _macroWindow = Duration(hours: 24);
  static const _maxSnapshotEvents = 12;

  // Keep only the small, relevant context window for an LLM analysis request.
  EventSnapshot select({
    required List<NewsEvent> events,
    required String symbol,
    DateTime? now,
  }) {
    final asOf = (now ?? DateTime.now()).toUtc();
    final asset = symbol.toUpperCase().replaceFirst(
      RegExp(r'(USDT|USDC|USD)$'),
      '',
    );
    final sorted = [...events]..sort(_priorityCompare);
    final used = <String>{};
    List<NewsEvent> take(Iterable<NewsEvent> values, int count) =>
        values.where((event) => used.add(event.eventId)).take(count).toList();
    final upcoming = take(
      sorted.where(
        (event) =>
            event.scheduledAt != null &&
            event.scheduledAt!.isAfter(asOf) &&
            event.scheduledAt!.isBefore(asOf.add(_upcomingWindow)) &&
            event.importance.index <= NewsImportance.high.index,
      ),
      3,
    );
    final breaking = take(
      sorted.where(
        (event) =>
            event.isBreaking &&
            event.publishedAt.isAfter(asOf.subtract(_breakingWindow)),
      ),
      2,
    );
    final assetSpecific = take(
      sorted.where(
        (event) =>
            event.directAssets.contains(asset) &&
            event.publishedAt.isAfter(asOf.subtract(_assetWindow)),
      ),
      3,
    );
    final crypto = take(
      sorted.where(
        (event) =>
            event.scope == NewsScope.cryptoMarket &&
            event.importance.index <= NewsImportance.high.index &&
            event.publishedAt.isAfter(asOf.subtract(_cryptoWindow)),
      ),
      2,
    );
    final macro = take(
      sorted.where(
        (event) =>
            event.scope == NewsScope.macroGlobal &&
            event.importance.index <= NewsImportance.high.index &&
            (event.publishedAt.isAfter(asOf.subtract(_macroWindow)) ||
                event.scheduledAt != null),
      ),
      _maxSnapshotEvents - 10,
    );
    return EventSnapshot(
      snapshotAsOf: asOf,
      upcomingCriticalEvents: upcoming,
      breakingEvents: breaking,
      assetSpecificEvents: assetSpecific,
      cryptoMarketEvents: crypto,
      macroEvents: macro,
    );
  }

  int _priorityCompare(NewsEvent left, NewsEvent right) {
    final importance = left.importance.index.compareTo(right.importance.index);
    if (importance != 0) return importance;
    final verified = right.verificationStatus.index.compareTo(
      left.verificationStatus.index,
    );
    if (verified != 0) return verified;
    return right.publishedAt.compareTo(left.publishedAt);
  }
}
