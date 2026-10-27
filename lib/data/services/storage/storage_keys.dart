// Every key the app persists, so storage names stay unique and in one place.
abstract final class StorageKeys {
  // SharedPreferences: app and settings.
  static const localeCode = 'decma.app.locale_code';
  static const themeMode = 'decma.app.theme_mode';
  static const lastViewedSymbol = 'decma.dashboard.last_viewed_symbol';
  static const llmConnections = 'decma.llm.connections';
  static const activeLlmConnection = 'decma.llm.active_connection';
  static const bybitMcp = 'decma.mcp.bybit';
  static const nansenMcp = 'decma.mcp.nansen';
  static const openWebSearchMcp = 'decma.mcp.open_web_search';
  static const coinalyzeApi = 'decma.api.coinalyze';
  static const finnhubNews = 'decma.news.finnhub';
  static const marketauxNews = 'decma.news.marketaux';
  static const blsNews = 'decma.news.bls';
  static const beaNews = 'decma.news.bea';
  static const federalReserveNews = 'decma.news.federal_reserve';
  static const whiteHouseNews = 'decma.news.white_house';
  static const secNews = 'decma.news.sec';
  static const bbcNews = 'decma.news.bbc';

  // SharedPreferences: cached data.
  static const newsEvents = 'decma.news.events.v1';
  static const newsRefreshPrefix = 'decma.news.refresh.v1.';
  static const assetProfiles = 'decma.news.asset_profiles.v1';
  static const tokenBackgroundPrefix = 'decma.token_background.v1.';

  // Secure storage: credentials.
  static const llmApiKeyPrefix = 'decma.llm_api_key.';
  static const codexAccessToken = 'decma.codex.access_token';
  static const codexRefreshToken = 'decma.codex.refresh_token';
  static const codexAccountId = 'decma.codex.account_id';
  static const codexExpiresAt = 'decma.codex.expires_at';
  static const bybitApiKey = 'decma.bybit_api_key';
  static const bybitApiSecret = 'decma.bybit_api_secret';
  static const nansenApiKey = 'decma.nansen_api_key';
  static const coinalyzeApiKey = 'decma.coinalyze_api_key';
  static const finnhubApiKey = 'decma.finnhub_api_key';
  static const marketauxApiKey = 'decma.marketaux_api_key';
}
