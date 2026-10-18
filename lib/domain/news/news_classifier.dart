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
      ? _category(text)
      : event.category;
  final scope =
      category == NewsCategory.macro || category == NewsCategory.centralBank
      ? NewsScope.macroGlobal
      : directAssets.isNotEmpty
      ? NewsScope.assetSpecific
      : event.scope;
  final importance = _importance(text, event.importance);
  return event.copyWith(
    category: category,
    scope: scope,
    importance: importance,
    eventType: _eventType(text, category),
    directAssets: directAssets.toList()..sort(),
    assets: directAssets.toList()..sort(),
  );
}

bool _mentionsAsset(String text, AssetProfile profile) => profile.aliases.any(
  (alias) => RegExp(
    '(^|[^A-Z0-9])${RegExp.escape(alias.toUpperCase())}([^A-Z0-9]|\$)',
  ).hasMatch(text),
);

NewsCategory _category(String text) {
  if (_contains(text, ['FOMC', 'FEDERAL RESERVE', 'POWELL'])) {
    return NewsCategory.centralBank;
  }
  if (_contains(text, [
    'CPI',
    'PPI',
    'PAYROLL',
    'EMPLOYMENT',
    'JOLTS',
    'GDP',
    'PCE',
  ])) {
    return NewsCategory.macro;
  }
  if (_contains(text, ['SEC', 'REGULATION', 'LAWSUIT', 'COURT'])) {
    return NewsCategory.regulation;
  }
  if (_contains(text, ['HACK', 'EXPLOIT', 'BREACH'])) {
    return NewsCategory.security;
  }
  if (_contains(text, ['BYBIT', 'BINANCE', 'COINBASE', 'EXCHANGE'])) {
    return NewsCategory.exchange;
  }
  if (_contains(text, [
    'BITCOIN',
    'ETHEREUM',
    'RIPPLE',
    'CRYPTO',
    'BLOCKCHAIN',
  ])) {
    return NewsCategory.crypto;
  }
  return NewsCategory.market;
}

NewsImportance _importance(String text, NewsImportance current) {
  if (_contains(text, [
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
  ])) {
    return _higherImportance(current, NewsImportance.critical);
  }
  if (_contains(text, [
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
  ])) {
    return _higherImportance(current, NewsImportance.high);
  }
  return current;
}

String _eventType(String text, NewsCategory category) {
  for (final type in ['CPI', 'PPI', 'JOLTS', 'PCE', 'GDP', 'FOMC']) {
    if (text.contains(type)) return type;
  }
  if (_contains(text, ['PAYROLL', 'EMPLOYMENT SITUATION'])) {
    return 'NFP_EMPLOYMENT';
  }
  if (_contains(text, [
    'FOUNDER DIES',
    'CEO RESIGNS',
    'CEO APPOINTED',
    'LEADERSHIP TRANSITION',
  ])) {
    return 'PROJECT_LEADERSHIP';
  }
  if (_contains(text, ['GOVERNANCE', 'CONTROL DISPUTE'])) {
    return 'GOVERNANCE';
  }
  if (_contains(text, ['HACK', 'EXPLOIT', 'BREACH', 'TREASURY COMPROMISE'])) {
    return 'SECURITY';
  }
  if (_contains(text, ['SEC', 'LAWSUIT', 'COURT', 'REGULATION'])) {
    return 'LEGAL';
  }
  if (_contains(text, ['TOKEN UNLOCK', 'EMISSIONS', 'VESTING'])) {
    return 'TOKENOMICS';
  }
  if (_contains(text, ['DELISTING', 'LISTING'])) return 'EXCHANGE';
  if (_contains(text, ['PROTOCOL PAUSED', 'EMERGENCY UPGRADE', 'UPGRADE'])) {
    return 'PROTOCOL_OPERATION';
  }
  if (_contains(text, ['BANKRUPTCY', 'INSOLVENCY'])) return 'INSOLVENCY';
  if (_contains(text, ['PARTNERSHIP', 'INTEGRATION'])) return 'PARTNERSHIP';
  return category.name.toUpperCase();
}

NewsImportance _higherImportance(
  NewsImportance current,
  NewsImportance classified,
) => classified.index < current.index ? classified : current;

bool _contains(String text, List<String> terms) => terms.any(text.contains);
