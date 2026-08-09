import '../../models/asset_profile.dart';

/// Produces a small bounded set of discovery queries when token coverage is empty.
List<String> buildTokenNewsQueries(AssetProfile profile) {
  final name = profile.projectName ?? profile.baseAsset;
  return [
    '"$name" latest news',
    '"${profile.baseAsset}" crypto news',
    '"$name" governance security regulation',
    if (profile.officialDomains.isNotEmpty)
      'site:${profile.officialDomains.first} $name',
  ];
}
