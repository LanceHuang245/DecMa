/// Tracks whether a Marketaux entity lookup can be used, retried, or reviewed.
enum MarketauxResolution { unresolved, resolved, ambiguous, notFound }

/// Describes a dashboard asset without coupling it to a particular news feed.
class AssetProfile {
  const AssetProfile({
    required this.symbol,
    required this.baseAsset,
    this.projectName,
    this.aliases = const [],
    this.officialDomains = const [],
    this.keyEntities = const [],
    this.marketauxSymbol,
    this.marketauxResolution = MarketauxResolution.unresolved,
    this.marketauxResolvedAt,
    this.marketauxRetryAfter,
    this.marketauxProviderVersion,
  });

  final String symbol;
  final String baseAsset;
  final String? projectName;
  final List<String> aliases;
  final List<String> officialDomains;
  final List<String> keyEntities;
  final String? marketauxSymbol;
  final MarketauxResolution marketauxResolution;
  final DateTime? marketauxResolvedAt;
  final DateTime? marketauxRetryAfter;
  final String? marketauxProviderVersion;

  AssetProfile copyWith({
    String? projectName,
    List<String>? aliases,
    List<String>? officialDomains,
    List<String>? keyEntities,
    String? marketauxSymbol,
    bool clearMarketauxSymbol = false,
    MarketauxResolution? marketauxResolution,
    DateTime? marketauxResolvedAt,
    DateTime? marketauxRetryAfter,
    String? marketauxProviderVersion,
  }) => AssetProfile(
    symbol: symbol,
    baseAsset: baseAsset,
    projectName: projectName ?? this.projectName,
    aliases: aliases ?? this.aliases,
    officialDomains: officialDomains ?? this.officialDomains,
    keyEntities: keyEntities ?? this.keyEntities,
    marketauxSymbol: clearMarketauxSymbol
        ? null
        : marketauxSymbol ?? this.marketauxSymbol,
    marketauxResolution: marketauxResolution ?? this.marketauxResolution,
    marketauxResolvedAt: marketauxResolvedAt ?? this.marketauxResolvedAt,
    marketauxRetryAfter: marketauxRetryAfter ?? this.marketauxRetryAfter,
    marketauxProviderVersion:
        marketauxProviderVersion ?? this.marketauxProviderVersion,
  );

  Map<String, dynamic> toJson() => {
    'symbol': symbol,
    'baseAsset': baseAsset,
    'projectName': projectName,
    'aliases': aliases,
    'officialDomains': officialDomains,
    'keyEntities': keyEntities,
    'marketauxSymbol': marketauxSymbol,
    'marketauxResolution': marketauxResolution.name,
    'marketauxResolvedAt': marketauxResolvedAt?.toUtc().toIso8601String(),
    'marketauxRetryAfter': marketauxRetryAfter?.toUtc().toIso8601String(),
    'marketauxProviderVersion': marketauxProviderVersion,
  };

  factory AssetProfile.fromJson(Map<String, dynamic> json) => AssetProfile(
    symbol: json['symbol']?.toString() ?? '',
    baseAsset: json['baseAsset']?.toString() ?? '',
    projectName: json['projectName']?.toString(),
    aliases: _strings(json['aliases']),
    officialDomains: _strings(json['officialDomains']),
    keyEntities: _strings(json['keyEntities']),
    marketauxSymbol: json['marketauxSymbol']?.toString(),
    // Legacy boolean values with no entity are retried rather than cached forever.
    marketauxResolution: _marketauxResolution(json),
    marketauxResolvedAt: _date(json['marketauxResolvedAt']),
    marketauxRetryAfter: _date(json['marketauxRetryAfter']),
    marketauxProviderVersion: json['marketauxProviderVersion']?.toString(),
  );
}

List<String> _strings(Object? value) =>
    (value as List? ?? const []).map((item) => item.toString()).toList();

MarketauxResolution _marketauxResolution(Map<String, dynamic> json) {
  final saved = json['marketauxResolution']?.toString();
  for (final value in MarketauxResolution.values) {
    if (value.name == saved) return value;
  }
  return json['marketauxResolved'] == true &&
          (json['marketauxSymbol']?.toString().isNotEmpty ?? false)
      ? MarketauxResolution.resolved
      : MarketauxResolution.unresolved;
}

DateTime? _date(Object? value) =>
    DateTime.tryParse(value?.toString() ?? '')?.toUtc();
