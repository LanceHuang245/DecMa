import '../../models/asset_profile.dart';
import '../../utils/symbol_utils.dart';
import 'asset_profile_store.dart';

/// Resolves a Bybit perpetual symbol into reusable, conservative news metadata.
class AssetResolver {
  AssetResolver({AssetProfileStore? store})
    : _store = store ?? AssetProfileStore();

  AssetResolver.memory() : _store = null;

  final AssetProfileStore? _store;
  final Map<String, AssetProfile> _cache = {};
  bool _loaded = false;

  Future<AssetProfile> resolve(String symbol) async {
    await _load();
    final normalized = normalizeContractSymbol(symbol);
    final cached = _cache[normalized];
    if (cached != null) return cached;
    final profile = fromSymbol(normalized);
    _cache[normalized] = profile;
    await _store?.save(profile);
    return profile;
  }

  Future<void> save(AssetProfile profile) async {
    await _load();
    _cache[profile.symbol] = profile;
    await _store?.save(profile);
  }

  Future<List<AssetProfile>> all() async {
    await _load();
    return _cache.values.toList();
  }

  List<AssetProfile> get allSync => _cache.values.toList();

  // Keep only unambiguous project aliases; unknown assets fall back to ticker matching.
  static AssetProfile fromSymbol(String symbol) {
    final normalized = normalizeContractSymbol(symbol);
    final baseAsset = baseAssetFromSymbol(normalized);
    final metadata = _known[baseAsset];
    return AssetProfile(
      symbol: normalized,
      baseAsset: baseAsset,
      projectName: metadata?.projectName,
      aliases: {baseAsset, ...?metadata?.aliases}.toList(),
      officialDomains: metadata?.officialDomains ?? const [],
    );
  }

  Future<void> _load() async {
    if (_loaded) return;
    for (final asset in _known.keys) {
      final symbol = '${asset}USDT';
      _cache[symbol] = fromSymbol(symbol);
    }
    for (final profile in await _store?.readAll() ?? const <AssetProfile>[]) {
      _cache[profile.symbol] = profile;
    }
    _loaded = true;
  }

  static const _known = <String, _AssetMetadata>{
    'BTC': _AssetMetadata('Bitcoin', ['Bitcoin', 'BTC ETF']),
    'ETH': _AssetMetadata('Ethereum', ['Ethereum']),
    'XRP': _AssetMetadata('Ripple', ['Ripple', 'XRP Ledger', 'XRPL']),
    'SOL': _AssetMetadata('Solana', ['Solana']),
    'ONDO': _AssetMetadata(
      'Ondo Finance',
      ['Ondo', 'Ondo Finance'],
      officialDomains: ['ondo.finance'],
    ),
    'ENA': _AssetMetadata('Ethena', ['Ethena']),
    'PENDLE': _AssetMetadata('Pendle', ['Pendle']),
  };
}

class _AssetMetadata {
  const _AssetMetadata(
    this.projectName,
    this.aliases, {
    this.officialDomains = const [],
  });

  final String projectName;
  final List<String> aliases;
  final List<String> officialDomains;
}
