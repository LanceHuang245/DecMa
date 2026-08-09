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
    this.marketauxResolved = false,
  });

  final String symbol;
  final String baseAsset;
  final String? projectName;
  final List<String> aliases;
  final List<String> officialDomains;
  final List<String> keyEntities;
  final String? marketauxSymbol;
  final bool marketauxResolved;

  AssetProfile copyWith({
    String? projectName,
    List<String>? aliases,
    List<String>? officialDomains,
    List<String>? keyEntities,
    String? marketauxSymbol,
    bool? marketauxResolved,
  }) => AssetProfile(
    symbol: symbol,
    baseAsset: baseAsset,
    projectName: projectName ?? this.projectName,
    aliases: aliases ?? this.aliases,
    officialDomains: officialDomains ?? this.officialDomains,
    keyEntities: keyEntities ?? this.keyEntities,
    marketauxSymbol: marketauxSymbol ?? this.marketauxSymbol,
    marketauxResolved: marketauxResolved ?? this.marketauxResolved,
  );

  Map<String, dynamic> toJson() => {
    'symbol': symbol,
    'baseAsset': baseAsset,
    'projectName': projectName,
    'aliases': aliases,
    'officialDomains': officialDomains,
    'keyEntities': keyEntities,
    'marketauxSymbol': marketauxSymbol,
    'marketauxResolved': marketauxResolved,
  };

  factory AssetProfile.fromJson(Map<String, dynamic> json) => AssetProfile(
    symbol: json['symbol']?.toString() ?? '',
    baseAsset: json['baseAsset']?.toString() ?? '',
    projectName: json['projectName']?.toString(),
    aliases: _strings(json['aliases']),
    officialDomains: _strings(json['officialDomains']),
    keyEntities: _strings(json['keyEntities']),
    marketauxSymbol: json['marketauxSymbol']?.toString(),
    marketauxResolved: json['marketauxResolved'] == true,
  );
}

List<String> _strings(Object? value) =>
    (value as List? ?? const []).map((item) => item.toString()).toList();
