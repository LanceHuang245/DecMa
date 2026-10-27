import 'dart:convert';

import '../../l10n/app_languages.dart';

enum NewsSourceTier { primary, highQualityNews, aggregator, discovery }

enum NewsVerificationStatus {
  unverified,
  secondaryConfirmed,
  primarySourceConfirmed,
  conflicted,
}

enum NewsCategory {
  macro,
  crypto,
  regulation,
  centralBank,
  exchange,
  security,
  project,
  market,
  other,
}

enum NewsScope { assetSpecific, cryptoMarket, macroGlobal }

enum NewsImportance { critical, high, medium, low }

enum NewsProviderState { active, disabled, error, rateLimited }

extension NewsEnumLabels on NewsSourceTier {
  String get label => switch (this) {
    NewsSourceTier.primary => 'Primary',
    NewsSourceTier.highQualityNews => 'High quality news',
    NewsSourceTier.aggregator => 'Aggregator',
    NewsSourceTier.discovery => 'Discovery',
  };
}

extension NewsVerificationLabels on NewsVerificationStatus {
  String get label => switch (this) {
    NewsVerificationStatus.unverified => 'Unverified',
    NewsVerificationStatus.secondaryConfirmed => 'Confirmed',
    NewsVerificationStatus.primarySourceConfirmed => 'Official',
    NewsVerificationStatus.conflicted => 'Conflicted',
  };
}

extension NewsCategoryLabels on NewsCategory {
  String get label => switch (this) {
    NewsCategory.macro => appL10n.categoryMacro,
    NewsCategory.crypto => 'Crypto',
    NewsCategory.regulation => appL10n.categoryRegulation,
    NewsCategory.centralBank => appL10n.categoryCentralBank,
    NewsCategory.exchange => appL10n.categoryExchange,
    NewsCategory.security => appL10n.categorySecurity,
    NewsCategory.project => appL10n.categoryProject,
    NewsCategory.market => appL10n.categoryMarket,
    NewsCategory.other => appL10n.categoryOther,
  };
}

extension NewsImportanceLabels on NewsImportance {
  String get label => switch (this) {
    NewsImportance.critical => 'CRITICAL',
    NewsImportance.high => 'HIGH',
    NewsImportance.medium => 'MEDIUM',
    NewsImportance.low => 'LOW',
  };
}

class NewsEventSource {
  const NewsEventSource({
    required this.provider,
    required this.originalSource,
    required this.sourceTier,
    this.url,
  });

  final String provider;
  final String originalSource;
  final NewsSourceTier sourceTier;
  final String? url;

  Map<String, dynamic> toJson() => {
    'provider': provider,
    'originalSource': originalSource,
    'sourceTier': sourceTier.name,
    'url': url,
  };

  factory NewsEventSource.fromJson(Map<String, dynamic> json) =>
      NewsEventSource(
        provider: json['provider'],
        originalSource: json['originalSource'],
        sourceTier: NewsSourceTier.values.byName(json['sourceTier']),
        url: json['url'],
      );
}

class NewsEvent {
  const NewsEvent({
    required this.eventId,
    required this.headline,
    required this.provider,
    required this.originalSource,
    required this.sourceTier,
    required this.category,
    required this.eventType,
    required this.scope,
    required this.importance,
    required this.assets,
    required this.directAssets,
    required this.indirectAssets,
    required this.country,
    required this.publishedAt,
    required this.receivedAt,
    required this.verificationStatus,
    required this.isBreaking,
    required this.isOfficial,
    required this.sources,
    this.summary,
    this.scheduledAt,
    this.url,
    this.actual,
    this.forecast,
    this.previous,
    this.unit,
    this.rawSourceId,
  });

  final String eventId;
  final String headline;
  final String? summary;
  final String provider;
  final String originalSource;
  final NewsSourceTier sourceTier;
  final NewsCategory category;
  final String eventType;
  final NewsScope scope;
  final NewsImportance importance;
  final List<String> assets;
  final List<String> directAssets;
  final List<String> indirectAssets;
  final String? country;
  final DateTime? scheduledAt;
  final DateTime publishedAt;
  final DateTime receivedAt;
  final String? url;
  final String? actual;
  final String? forecast;
  final String? previous;
  final String? unit;
  final NewsVerificationStatus verificationStatus;
  final bool isBreaking;
  final bool isOfficial;
  final String? rawSourceId;
  final List<NewsEventSource> sources;

  NewsEvent copyWith({
    String? eventId,
    String? headline,
    String? summary,
    String? provider,
    String? originalSource,
    NewsSourceTier? sourceTier,
    NewsCategory? category,
    String? eventType,
    NewsScope? scope,
    NewsImportance? importance,
    List<String>? assets,
    List<String>? directAssets,
    List<String>? indirectAssets,
    String? country,
    DateTime? scheduledAt,
    DateTime? publishedAt,
    DateTime? receivedAt,
    String? url,
    String? actual,
    String? forecast,
    String? previous,
    String? unit,
    NewsVerificationStatus? verificationStatus,
    bool? isBreaking,
    bool? isOfficial,
    String? rawSourceId,
    List<NewsEventSource>? sources,
  }) => NewsEvent(
    eventId: eventId ?? this.eventId,
    headline: headline ?? this.headline,
    summary: summary ?? this.summary,
    provider: provider ?? this.provider,
    originalSource: originalSource ?? this.originalSource,
    sourceTier: sourceTier ?? this.sourceTier,
    category: category ?? this.category,
    eventType: eventType ?? this.eventType,
    scope: scope ?? this.scope,
    importance: importance ?? this.importance,
    assets: assets ?? this.assets,
    directAssets: directAssets ?? this.directAssets,
    indirectAssets: indirectAssets ?? this.indirectAssets,
    country: country ?? this.country,
    scheduledAt: scheduledAt ?? this.scheduledAt,
    publishedAt: publishedAt ?? this.publishedAt,
    receivedAt: receivedAt ?? this.receivedAt,
    url: url ?? this.url,
    actual: actual ?? this.actual,
    forecast: forecast ?? this.forecast,
    previous: previous ?? this.previous,
    unit: unit ?? this.unit,
    verificationStatus: verificationStatus ?? this.verificationStatus,
    isBreaking: isBreaking ?? this.isBreaking,
    isOfficial: isOfficial ?? this.isOfficial,
    rawSourceId: rawSourceId ?? this.rawSourceId,
    sources: sources ?? this.sources,
  );

  Map<String, dynamic> toJson() => {
    'eventId': eventId,
    'headline': headline,
    'summary': summary,
    'provider': provider,
    'originalSource': originalSource,
    'sourceTier': sourceTier.name,
    'category': category.name,
    'eventType': eventType,
    'scope': scope.name,
    'importance': importance.name,
    'assets': assets,
    'directAssets': directAssets,
    'indirectAssets': indirectAssets,
    'country': country,
    'scheduledAt': scheduledAt?.toUtc().toIso8601String(),
    'publishedAt': publishedAt.toUtc().toIso8601String(),
    'receivedAt': receivedAt.toUtc().toIso8601String(),
    'url': url,
    'actual': actual,
    'forecast': forecast,
    'previous': previous,
    'unit': unit,
    'verificationStatus': verificationStatus.name,
    'isBreaking': isBreaking,
    'isOfficial': isOfficial,
    'rawSourceId': rawSourceId,
    'sources': sources.map((source) => source.toJson()).toList(),
  };

  Map<String, dynamic> toSnapshotJson() => {
    'eventId': eventId,
    'headline': headline,
    'summary': summary,
    'category': category.name,
    'eventType': eventType,
    'scope': scope.name,
    'importance': importance.name,
    'assets': assets,
    'scheduledAt': scheduledAt?.toUtc().toIso8601String(),
    'publishedAt': publishedAt.toUtc().toIso8601String(),
    'source': originalSource,
    'sourceTier': sourceTier.name,
    'verificationStatus': verificationStatus.name,
    'url': url,
    'actual': actual,
    'forecast': forecast,
    'previous': previous,
  };

  factory NewsEvent.fromJson(Map<String, dynamic> json) => NewsEvent(
    eventId: json['eventId'],
    headline: json['headline'],
    summary: json['summary'],
    provider: json['provider'],
    originalSource: json['originalSource'],
    sourceTier: NewsSourceTier.values.byName(json['sourceTier']),
    category: NewsCategory.values.byName(json['category']),
    eventType: json['eventType'],
    scope: NewsScope.values.byName(json['scope']),
    importance: NewsImportance.values.byName(json['importance']),
    assets: List<String>.from(json['assets']),
    directAssets: List<String>.from(json['directAssets']),
    indirectAssets: List<String>.from(json['indirectAssets']),
    country: json['country'],
    scheduledAt: json['scheduledAt'] == null
        ? null
        : DateTime.parse(json['scheduledAt']),
    publishedAt: DateTime.parse(json['publishedAt']),
    receivedAt: DateTime.parse(json['receivedAt']),
    url: json['url'],
    actual: json['actual'],
    forecast: json['forecast'],
    previous: json['previous'],
    unit: json['unit'],
    verificationStatus: NewsVerificationStatus.values.byName(
      json['verificationStatus'],
    ),
    isBreaking: json['isBreaking'],
    isOfficial: json['isOfficial'],
    rawSourceId: json['rawSourceId'],
    sources: [
      for (final source in json['sources']) NewsEventSource.fromJson(source),
    ],
  );

  static String encodeAll(List<NewsEvent> events) =>
      jsonEncode(events.map((event) => event.toJson()).toList());

  static List<NewsEvent> decodeAll(String value) => (jsonDecode(value) as List)
      .cast<Map<String, dynamic>>()
      .map(NewsEvent.fromJson)
      .toList();
}

class EventSnapshot {
  const EventSnapshot({
    required this.snapshotAsOf,
    required this.upcomingCriticalEvents,
    required this.breakingEvents,
    required this.assetSpecificEvents,
    required this.cryptoMarketEvents,
    required this.macroEvents,
    this.tokenNewsSearchQueries = const [],
  });

  final DateTime snapshotAsOf;
  final List<NewsEvent> upcomingCriticalEvents;
  final List<NewsEvent> breakingEvents;
  final List<NewsEvent> assetSpecificEvents;
  final List<NewsEvent> cryptoMarketEvents;
  final List<NewsEvent> macroEvents;
  final List<String> tokenNewsSearchQueries;

  bool get isEmpty =>
      upcomingCriticalEvents.isEmpty &&
      breakingEvents.isEmpty &&
      assetSpecificEvents.isEmpty &&
      cryptoMarketEvents.isEmpty &&
      macroEvents.isEmpty;

  Map<String, dynamic> toJson() => {
    'snapshot_as_of': snapshotAsOf.toUtc().toIso8601String(),
    'upcoming_critical_events': upcomingCriticalEvents
        .map((event) => event.toSnapshotJson())
        .toList(),
    'breaking_events': breakingEvents
        .map((event) => event.toSnapshotJson())
        .toList(),
    'asset_specific_events': assetSpecificEvents
        .map((event) => event.toSnapshotJson())
        .toList(),
    'crypto_market_events': cryptoMarketEvents
        .map((event) => event.toSnapshotJson())
        .toList(),
    'macro_events': macroEvents.map((event) => event.toSnapshotJson()).toList(),
    'token_news_search_queries': tokenNewsSearchQueries,
  };
}
