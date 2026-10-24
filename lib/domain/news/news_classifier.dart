import '../models/asset_profile.dart';
import '../models/news_event.dart';

// Deterministic keyword rules avoid an LLM call for routine feed items.
NewsEvent normalizeNewsEvent(NewsEvent event, List<AssetProfile> profiles) {
  final text = '${event.headline} ${event.summary ?? ''}'.toUpperCase();
  final directAssets = <String>{...event.directAssets};
  for (final profile in profiles) {
    if (_mentionsAsset(text, profile)) directAssets.add(profile.baseAsset);
  }
  final category = event.category == NewsCategory.other
      ? _firstMatch(text, _categories) ?? NewsCategory.market
      : event.category;
  final scope =
      category == NewsCategory.macro || category == NewsCategory.centralBank
      ? NewsScope.macroGlobal
      : directAssets.isNotEmpty
      ? NewsScope.assetSpecific
      : event.scope;
  // Keywords may raise importance but never lower what the provider reported.
  final classified = _firstMatch(text, _importances);
  final importance =
      classified != null && classified.index < event.importance.index
      ? classified
      : event.importance;
  return event.copyWith(
    category: category,
    scope: scope,
    importance: importance,
    eventType: _firstMatch(text, _eventTypes) ?? category.name.toUpperCase(),
    directAssets: directAssets.toList()..sort(),
    assets: directAssets.toList()..sort(),
  );
}

bool _mentionsAsset(String text, AssetProfile profile) => profile.aliases.any(
  (alias) => RegExp(
    '(^|[^A-Z0-9])${RegExp.escape(alias.toUpperCase())}([^A-Z0-9]|\$)',
  ).hasMatch(text),
);

// Keyword groups shared by more than one table.
const _centralBank = ['FOMC', 'FEDERAL RESERVE', 'POWELL'];
const _macroData = [
  'CPI',
  'PPI',
  'PAYROLL',
  'EMPLOYMENT',
  'UNEMPLOYMENT',
  'JOLTS',
  'GDP',
  'PCE',
];
const _legal = ['SEC', 'REGULATION', 'LAWSUIT', 'COURT'];
const _security = ['HACK', 'EXPLOIT', 'BREACH'];
const _geopolitics = [
  'WAR',
  'INVASION',
  'MISSILE',
  'AIRSTRIKE',
  'CEASEFIRE',
  'SANCTION',
  'MARTIAL LAW',
  'TARIFF',
];

// Each table is ordered: the first matching keyword group decides.
const _categories = [
  (_centralBank, NewsCategory.centralBank),
  (_macroData, NewsCategory.macro),
  (_legal, NewsCategory.regulation),
  (_security, NewsCategory.security),
  (_geopolitics, NewsCategory.macro),
  (['BYBIT', 'BINANCE', 'COINBASE', 'EXCHANGE'], NewsCategory.exchange),
  (
    ['BITCOIN', 'ETHEREUM', 'RIPPLE', 'CRYPTO', 'BLOCKCHAIN'],
    NewsCategory.crypto,
  ),
];

const _eventTypes = [
  (['CPI'], 'CPI'),
  (['PPI'], 'PPI'),
  (['JOLTS'], 'JOLTS'),
  (['PCE'], 'PCE'),
  (['GDP'], 'GDP'),
  (['FOMC'], 'FOMC'),
  (['PAYROLL', 'EMPLOYMENT SITUATION'], 'NFP_EMPLOYMENT'),
  (
    ['FOUNDER DIES', 'CEO RESIGNS', 'CEO APPOINTED', 'LEADERSHIP TRANSITION'],
    'PROJECT_LEADERSHIP',
  ),
  (['GOVERNANCE', 'CONTROL DISPUTE'], 'GOVERNANCE'),
  ([..._security, 'TREASURY COMPROMISE'], 'SECURITY'),
  (_legal, 'LEGAL'),
  (['TOKEN UNLOCK', 'EMISSIONS', 'VESTING'], 'TOKENOMICS'),
  (['DELISTING', 'LISTING'], 'EXCHANGE'),
  (['PROTOCOL PAUSED', 'EMERGENCY UPGRADE', 'UPGRADE'], 'PROTOCOL_OPERATION'),
  (['BANKRUPTCY', 'INSOLVENCY'], 'INSOLVENCY'),
  (_geopolitics, 'GEOPOLITICS'),
  (['PARTNERSHIP', 'INTEGRATION'], 'PARTNERSHIP'),
];

const _importances = [
  (
    [
      'FOUNDER DIES',
      'BANKRUPTCY',
      'INSOLVENCY',
      'STABLECOIN DEPEG',
      'TREASURY COMPROMISE',
      'BRIDGE INCIDENT',
      'FOMC',
      'INTEREST RATE DECISION',
      'CPI',
      'PAYROLL',
      'EMPLOYMENT SITUATION',
    ],
    NewsImportance.critical,
  ),
  (
    [
      'CEO RESIGNS',
      'LEADERSHIP TRANSITION',
      'CONTROL DISPUTE',
      'GOVERNANCE CRISIS',
      'PROTOCOL PAUSED',
      'EMERGENCY UPGRADE',
      'TOKEN UNLOCK',
      'DELISTING',
      'PPI',
      'JOLTS',
      'GDP',
      'PCE',
      'SEC',
      'LAWSUIT',
      'HACK',
      'EXPLOIT',
      ..._geopolitics,
    ],
    NewsImportance.high,
  ),
];

T? _firstMatch<T>(String text, List<(List<String>, T)> table) {
  for (final (terms, value) in table) {
    if (terms.any((term) => _hasWord(text, term))) return value;
  }
  return null;
}

// Whole words with common inflections: SEC never matches SECOND, WAR never SOFTWARE.
bool _hasWord(String text, String term) =>
    RegExp('\\b${RegExp.escape(term)}(S|ES|D|ED|ING|ERS?)?\\b').hasMatch(text);
