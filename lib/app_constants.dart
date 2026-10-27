/// Centralizes identifiers and versions shared across the application.
class AppConstants {
  static const appName = 'DecMa';
  static const appVersion = '1.0.0';
  static const projectUrl = 'https://github.com/LanceHuang245/DecMa';
  static const userAgent = '$appName/$appVersion (+$projectUrl)';
  static const codexClientVersion = '0.164.0';
  static const bybitMcpPackage = 'bybit-official-trading-server@latest';
  static const openWebSearchMcpPackage = 'open-websearch@latest';

  // News source endpoints.
  static const finnhubApiHost = 'finnhub.io';
  static const marketauxApiHost = 'api.marketaux.com';
  static const blsLatestRssUrl = 'https://www.bls.gov/feed/bls_latest.rss';
  static const beaRssUrl = 'https://apps.bea.gov/rss/rss.xml';
  static const federalReserveRssUrls = [
    'https://www.federalreserve.gov/feeds/press_monetary.xml',
    'https://www.federalreserve.gov/feeds/press_all.xml',
    'https://www.federalreserve.gov/feeds/speeches_and_testimony.xml',
  ];
  static const whiteHouseRssUrl =
      'https://www.whitehouse.gov/presidential-actions/feed/';
  static const secRssUrl = 'https://www.sec.gov/news/pressreleases.rss';
  static const bbcWorldRssUrl = 'https://feeds.bbci.co.uk/news/world/rss.xml';

  // Documentation links for external services used in the application.
  static const bybitAccountDocumentationUrl =
      'https://bybit-exchange.github.io/docs/v5/guide';
  static const nansenDocumentationUrl = 'https://docs.nansen.ai/';
  static const coinalyzeDocumentationUrl = 'https://api.coinalyze.net/v1/doc/';
  static const finnhubDocumentationUrl =
      'https://finnhub.io/docs/api/market-news';
  static const marketauxDocumentationUrl =
      'https://www.marketaux.com/documentation';
}
