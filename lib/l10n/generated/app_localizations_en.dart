// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get language => 'Language';

  @override
  String get save => 'Save';

  @override
  String get saving => 'Saving…';

  @override
  String get close => 'Close';

  @override
  String get notProvided => 'Not provided';

  @override
  String get encryptedKeyPlaceholder => 'Enter a new key to save it encrypted';

  @override
  String secureStorageFailed(Object error) {
    return 'Secure storage failed: $error';
  }

  @override
  String get effortLow => 'Low';

  @override
  String get effortMedium => 'Medium';

  @override
  String get effortHigh => 'High';

  @override
  String get effortXhigh => 'Extra high';

  @override
  String get effortMax => 'Max';

  @override
  String get effortUltra => 'Ultra';

  @override
  String failurePrefix(Object provider) {
    return '$provider: ';
  }

  @override
  String get failureCancelled => 'Request cancelled.';

  @override
  String get failureNetworkUnavailable => 'Network unavailable. Check your connection and try again.';

  @override
  String get failureTimeout => 'Request timed out. Please try again later.';

  @override
  String get failureAuthentication => 'Authentication failed. Check your API key or sign-in status.';

  @override
  String get failureRateLimited => 'Too many requests. Please try again later.';

  @override
  String get failureUpstream => 'Service temporarily unavailable. Please try again later.';

  @override
  String get failureInvalidResponse => 'The service returned an invalid response.';

  @override
  String get failureConfiguration => 'Service configuration is incomplete.';

  @override
  String get nodeMissingTitle => 'Node.js not detected';

  @override
  String get nodeMissingBody => 'Node.js was not detected; some features are unavailable.';

  @override
  String get openNodeSite => 'Go to the Node.js website';

  @override
  String get gotIt => 'Got it';

  @override
  String get searchTokenPlaceholder => 'Search tokens, e.g. BTC';

  @override
  String get entryZone => 'Entry zone';

  @override
  String get stopLoss => 'Stop loss';

  @override
  String get takeProfit => 'Take profit';

  @override
  String get scrollToBottom => 'Scroll to bottom';

  @override
  String get promptPlaceholder => 'Enter a token or ask a follow-up about the analysis';

  @override
  String get analyzeCurrentContract => 'Analyze current contract';

  @override
  String get stopGenerating => 'Stop generating';

  @override
  String get send => 'Send';

  @override
  String get clear => 'Clear';

  @override
  String get chartLong => 'Long';

  @override
  String get chartShort => 'Short';

  @override
  String get chartWaitZone => 'Wait zone';

  @override
  String chartEntryLevel(Object label) {
    return '$label entry';
  }

  @override
  String get ohlcOpen => 'O';

  @override
  String get ohlcHigh => 'H';

  @override
  String get ohlcLow => 'L';

  @override
  String get ohlcClose => 'C';

  @override
  String get chartCursor => 'Cursor';

  @override
  String get chartLatest => 'Last';

  @override
  String planEntryZone(Object value) {
    return 'Entry zone: $value';
  }

  @override
  String planStopLoss(Object value) {
    return 'Stop loss: $value';
  }

  @override
  String planTakeProfit(Object value) {
    return 'Take profit: $value';
  }

  @override
  String get viewFullJson => 'Click to view the full parsed JSON';

  @override
  String jsonResultTitle(Object decision) {
    return '$decision: parsed JSON';
  }

  @override
  String get fullJson => 'Full JSON';

  @override
  String get decisionLongSetup => 'Long setup';

  @override
  String get decisionShortSetup => 'Short setup';

  @override
  String get decisionWait => 'Wait';

  @override
  String get decisionNoTrade => 'No trade';

  @override
  String get decisionDataInsufficient => 'Insufficient data';

  @override
  String klineLoadFailed(Object error) {
    return 'Failed to load candles: $error';
  }

  @override
  String historyLoadFailed(Object error) {
    return 'Failed to load earlier history: $error';
  }

  @override
  String get fetchingModels => 'Fetching models…';

  @override
  String get selectModel => 'Select model';

  @override
  String get fetchingEffort => 'Fetching reasoning levels';

  @override
  String get effortUnsupported => 'This model does not support reasoning levels';

  @override
  String get effortGeneric => 'Reasoning level: generic options; actual support depends on the server';

  @override
  String get reasoningEffort => 'Reasoning level';

  @override
  String get refreshModels => 'Refresh model list';

  @override
  String get newsAll => 'All news';

  @override
  String newsRelated(Object asset) {
    return '$asset related';
  }

  @override
  String get newsCryptoMarket => 'Crypto market';

  @override
  String get updatingNews => 'Updating news';

  @override
  String get allSources => 'All sources';

  @override
  String get fetchingNews => 'Fetching news…';

  @override
  String get noRelatedNews => 'No related news';

  @override
  String get verifyUnverified => 'Unverified';

  @override
  String get verifySecondary => 'Media confirmed';

  @override
  String get verifyPrimary => 'Officially confirmed';

  @override
  String get verifyConflicted => 'Disputed';

  @override
  String get importanceCritical => 'Critical';

  @override
  String get importanceHigh => 'High';

  @override
  String get importanceMedium => 'Medium';

  @override
  String get importanceLow => 'Low';

  @override
  String get categoryMacro => 'Macro';

  @override
  String get categoryRegulation => 'Regulation';

  @override
  String get categoryCentralBank => 'Central bank';

  @override
  String get categoryExchange => 'Exchange';

  @override
  String get categorySecurity => 'Security';

  @override
  String get categoryProject => 'Project';

  @override
  String get categoryMarket => 'Market';

  @override
  String get categoryOther => 'Other';

  @override
  String get newsSettingsTitle => 'Market News settings';

  @override
  String get finnhubDocs => 'View Finnhub Market News docs';

  @override
  String get marketauxDocs => 'View Marketaux API docs';

  @override
  String get officialSources => 'Official sources';

  @override
  String get sourcesStarting => 'Starting data sources…';

  @override
  String get noNewsSources => 'No news sources enabled';

  @override
  String sourcesUnavailable(Object count) {
    return '$count sources unavailable';
  }

  @override
  String sourcesAvailable(Object count) {
    return '$count sources available';
  }

  @override
  String get noSuccessfulUpdate => 'No successful update yet';

  @override
  String lastSuccessfulUpdate(Object time) {
    return 'Last successful update: $time';
  }

  @override
  String get updatedAtNone => 'Updated —';

  @override
  String updatedAt(Object time) {
    return 'Updated $time';
  }

  @override
  String get providerActive => 'Available';

  @override
  String get providerDisabled => 'Disabled';

  @override
  String get providerError => 'Connection failed';

  @override
  String get providerRateLimited => 'Rate limited';

  @override
  String get agentSettings => 'Agent settings';

  @override
  String get bybitDocs => 'View Bybit read-only account API docs';

  @override
  String get bybitHint => 'Only used to read actual fee rates';

  @override
  String get nansenDocs => 'View Nansen MCP docs';

  @override
  String get coinalyzeDocs => 'View Coinalyze API docs';

  @override
  String get codexSignedIn => 'Signed in to ChatGPT; using your Codex subscription quota.';

  @override
  String get codexSignInHint => 'Sign in with ChatGPT to use Codex.';

  @override
  String get connecting => 'Connecting…';

  @override
  String get signInAgain => 'Sign in again';

  @override
  String get signInChatGpt => 'Sign in to ChatGPT';

  @override
  String get connectionNameEmpty => 'Profile name cannot be empty.';

  @override
  String get connectionNameExists => 'Profile name already exists.';

  @override
  String get newConnection => 'New profile';

  @override
  String get llmConnection => 'LLM connection';

  @override
  String get savedConnections => 'Saved profiles';

  @override
  String get deleteConnection => 'Delete profile';

  @override
  String get connectionName => 'Profile name';

  @override
  String get apiType => 'API type';

  @override
  String get activityThinking => '• Thinking - Analyzing…';

  @override
  String get generationStopped => '> Generation stopped; the incomplete answer was not used to update the analysis.';

  @override
  String agentRequestFailed(Object error) {
    return '> Agent request failed: $error';
  }

  @override
  String get codexNotReady => '> Sign in to OpenAI Codex and select a model in settings first.';

  @override
  String get llmNotReady => '> Fill in the LLM endpoint and model and save an API key in settings first.';

  @override
  String noCandlesToAnalyze(Object symbol) {
    return '$symbol has no candles to analyze.';
  }

  @override
  String get activityIndicatorsDone => '• Deterministic Engine - Indicators calculated';

  @override
  String get activityResultGenerating => '• Result - Generating result…';

  @override
  String get activityMarketSnapshot => '• Market Snapshot - Fetching fixed multi-timeframe market data';

  @override
  String invalidContract(Object symbol) {
    return '$symbol has an invalid contract status or type.';
  }

  @override
  String get noticeNoPlan => 'No complete price plan yet; rely on the written explanation.';

  @override
  String get noticePlanRejected => 'The price plan failed validation; these levels are not used.';

  @override
  String noticeSymbolMismatch(Object symbol) {
    return 'The analyzed symbol does not match $symbol; please analyze again.';
  }

  @override
  String noticeChartSwitched(Object active, Object symbol) {
    return 'The chart has switched to $active; chart markers for $symbol were not added.';
  }

  @override
  String dataSourceNotice(Object notices) {
    return '> Data source notes: $notices';
  }

  @override
  String quickAnalyzePrompt(Object symbol) {
    return 'Analyze whether $symbol is better suited to going long, going short, or waiting right now. Based on the current price, state directly whether an entry is possible now; if the opportunity has already played out, explain what conditions to wait for.';
  }

  @override
  String planUnknownDecision(Object decision) {
    return 'Unknown decision type $decision';
  }

  @override
  String get planInvalidWaitZone => 'Invalid candidate wait zone; price markers ignored';

  @override
  String get planWaitOnlyZone => 'WAIT keeps only the candidate wait zone; other price markers ignored';

  @override
  String get planNonSetupIgnored => 'Price markers on a non-trade setup are ignored';

  @override
  String get planSetupMissingEntry => 'Trade setup is missing a complete entry zone or stop loss';

  @override
  String get planPricesInvalid => 'Prices must be positive and finite';

  @override
  String get planEntryInverted => 'Entry zone lower bound is above the upper bound';

  @override
  String get planMissingTargets => 'Trade setup is missing take-profit targets';

  @override
  String get planTooManyTargets => 'The chart only shows the first three take-profit targets';

  @override
  String get planLongStop => 'Long stop loss must be below the entry zone';

  @override
  String get planLongTargets => 'Long take-profits must be above the entry zone';

  @override
  String get planLongTargetOrder => 'Long take-profits must be in ascending price order';

  @override
  String get planShortStop => 'Short stop loss must be above the entry zone';

  @override
  String get planShortTargets => 'Short take-profits must be below the entry zone';

  @override
  String get planShortTargetOrder => 'Short take-profits must be in descending price order';

  @override
  String get planTickMisaligned => 'Prices are not aligned to the contract tick size; for reference only, confirm precision before ordering';

  @override
  String get coinalyzeKeyMissing => 'Coinalyze API: API key not configured.';

  @override
  String get nansenKeyMissing => 'Nansen MCP: API key not configured.';

  @override
  String activityFailed(Object activity) {
    return '$activity (failed)';
  }

  @override
  String get activityTokenBackground => '• Project Background - Updating background cache';

  @override
  String get activityDiscoverTools => '• MCP - Discovering available tools';

  @override
  String get signInChatGptFirst => 'Please sign in to ChatGPT first.';

  @override
  String get oauthCallbackInvalid => 'Invalid OAuth callback; please try again.';

  @override
  String get streamEndedEarly => 'The response stream ended early without a completion signal.';

  @override
  String get codexMissingAccount => 'OpenAI Codex OAuth is missing the ChatGPT account ID; please sign in again.';

  @override
  String get codexFailedStatus => 'Codex returned a failed status.';

  @override
  String responseIncomplete(Object reason) {
    return 'Response incomplete: $reason';
  }

  @override
  String get responseNotCompleted => 'The response did not complete successfully.';

  @override
  String get responseParseFailed => 'Failed to parse the response.';

  @override
  String get llmKeyMissing => 'Save an LLM API key or sign in to OpenAI Codex in settings first.';

  @override
  String get bybitKeyPair => 'Bybit account API: API key and API secret must both be configured.';

  @override
  String get activityBybitFees => '• Bybit Account - Fetching actual fee rates';

  @override
  String sourceDisabled(Object source) {
    return 'FULL_SOURCE_ENRICHMENT: $source is disabled.';
  }

  @override
  String sourceUnavailable(Object source) {
    return 'FULL_SOURCE_ENRICHMENT: $source is currently unavailable.';
  }

  @override
  String activityLlmRetry(Object attempt) {
    return '• LLM - Response interrupted, retrying $attempt/4';
  }

  @override
  String activityFillSources(Object sources) {
    return '• Data Sources - Filling missing sources: $sources';
  }

  @override
  String get enrichmentFailed => 'FULL_SOURCE_ENRICHMENT: the follow-up request failed; the first-pass analysis was kept.';

  @override
  String enrichmentIncomplete(Object sources) {
    return 'FULL_SOURCE_ENRICHMENT incomplete: $sources available but not called; they may not apply to this asset or were skipped by the model.';
  }

  @override
  String enrichmentInvalid(Object sources) {
    return 'FULL_SOURCE_ENRICHMENT: $sources were attempted but returned no valid data.';
  }

  @override
  String get home => 'Home';

  @override
  String get settings => 'Settings';

  @override
  String get retry => 'Retry';

  @override
  String get loadingKlines => 'Loading Bybit perpetual candles…';

  @override
  String get loadingHistory => 'Loading earlier history…';

  @override
  String modelListFailed(Object error) {
    return 'Failed to fetch models: $error';
  }

  @override
  String modelSaveFailed(Object error) {
    return 'Failed to save model: $error';
  }

  @override
  String codexLoginFailed(Object error) {
    return 'OpenAI Codex sign-in failed: $error';
  }

  @override
  String get languageDescription => 'Change the display language of the app';

  @override
  String get agentSettingsDescription => 'LLM connections, MCP servers and data APIs';

  @override
  String get newsSettingsDescription => 'News providers and official data sources';

  @override
  String get theme => 'Theme';

  @override
  String get themeDescription => 'Choose light, dark or follow the system';

  @override
  String get themeSystem => 'Follow System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get newsApis => 'News APIs';

  @override
  String get newsOutlets => 'News outlets';

  @override
  String get finnhubDescription => 'Crypto, general and forex market news';

  @override
  String get marketauxDescription => 'News about the token you are viewing';

  @override
  String get bbcDescription => 'World news, including geopolitics and conflicts';

  @override
  String get bybitMcpDescription => 'Bybit market data and contract details';

  @override
  String get openWebSearchDescription => 'Web search and webpage reading';

  @override
  String get nansenDescription => 'On-chain data and smart money flows';

  @override
  String get coinalyzeDescription => 'Cross-exchange derivatives history';

  @override
  String get shortTermAnalysis => 'Short-term (intraday, hours)';

  @override
  String get swingAnalysis => 'Swing (days to two weeks)';

  @override
  String swingAnalyzePrompt(Object symbol) {
    return 'I plan a swing trade held for several days up to two weeks. Using 4H candles as the decision timeframe, 1D for the trend and 1H for the entry trigger, analyze whether $symbol is better suited to going long, going short, or waiting right now. Based on the current price, state directly whether an entry is possible now; if the opportunity has already played out, explain what conditions to wait for.';
  }
}
