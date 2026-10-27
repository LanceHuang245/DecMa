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
    symbol: json['symbol'],
    baseAsset: json['baseAsset'],
    projectName: json['projectName'],
    aliases: List<String>.from(json['aliases']),
    officialDomains: List<String>.from(json['officialDomains']),
    keyEntities: List<String>.from(json['keyEntities']),
    marketauxSymbol: json['marketauxSymbol'],
    marketauxResolution: MarketauxResolution.values.byName(
      json['marketauxResolution'],
    ),
    marketauxResolvedAt: json['marketauxResolvedAt'] == null
        ? null
        : DateTime.parse(json['marketauxResolvedAt']),
    marketauxRetryAfter: json['marketauxRetryAfter'] == null
        ? null
        : DateTime.parse(json['marketauxRetryAfter']),
    marketauxProviderVersion: json['marketauxProviderVersion'],
  );
}
