import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh')
  ];

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get saving;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @notProvided.
  ///
  /// In en, this message translates to:
  /// **'Not provided'**
  String get notProvided;

  /// No description provided for @noValue.
  ///
  /// In en, this message translates to:
  /// **'N/A'**
  String get noValue;

  /// No description provided for @encryptedKeyPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Enter a new key to save it encrypted'**
  String get encryptedKeyPlaceholder;

  /// No description provided for @secureStorageFailed.
  ///
  /// In en, this message translates to:
  /// **'Secure storage failed: {error}'**
  String secureStorageFailed(Object error);

  /// No description provided for @effortLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get effortLow;

  /// No description provided for @effortMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get effortMedium;

  /// No description provided for @effortHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get effortHigh;

  /// No description provided for @effortXhigh.
  ///
  /// In en, this message translates to:
  /// **'Extra high'**
  String get effortXhigh;

  /// No description provided for @effortMax.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get effortMax;

  /// No description provided for @effortUltra.
  ///
  /// In en, this message translates to:
  /// **'Ultra'**
  String get effortUltra;

  /// No description provided for @failurePrefix.
  ///
  /// In en, this message translates to:
  /// **'{provider}: '**
  String failurePrefix(Object provider);

  /// No description provided for @failureCancelled.
  ///
  /// In en, this message translates to:
  /// **'Request cancelled.'**
  String get failureCancelled;

  /// No description provided for @failureNetworkUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Network unavailable. Check your connection and try again.'**
  String get failureNetworkUnavailable;

  /// No description provided for @failureTimeout.
  ///
  /// In en, this message translates to:
  /// **'Request timed out. Please try again later.'**
  String get failureTimeout;

  /// No description provided for @failureAuthentication.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed. Check your API key or sign-in status.'**
  String get failureAuthentication;

  /// No description provided for @failureRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many requests. Please try again later.'**
  String get failureRateLimited;

  /// No description provided for @failureUpstream.
  ///
  /// In en, this message translates to:
  /// **'Service temporarily unavailable. Please try again later.'**
  String get failureUpstream;

  /// No description provided for @failureInvalidResponse.
  ///
  /// In en, this message translates to:
  /// **'The service returned an invalid response.'**
  String get failureInvalidResponse;

  /// No description provided for @failureConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Service configuration is incomplete.'**
  String get failureConfiguration;

  /// No description provided for @nodeMissingTitle.
  ///
  /// In en, this message translates to:
  /// **'Node.js not detected'**
  String get nodeMissingTitle;

  /// No description provided for @nodeMissingBody.
  ///
  /// In en, this message translates to:
  /// **'Node.js was not detected; some features are unavailable.'**
  String get nodeMissingBody;

  /// No description provided for @openNodeSite.
  ///
  /// In en, this message translates to:
  /// **'Go to the Node.js website'**
  String get openNodeSite;

  /// No description provided for @gotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get gotIt;

  /// No description provided for @searchTokenPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search tokens, e.g. BTC'**
  String get searchTokenPlaceholder;

  /// No description provided for @entryZone.
  ///
  /// In en, this message translates to:
  /// **'Entry zone'**
  String get entryZone;

  /// No description provided for @stopLoss.
  ///
  /// In en, this message translates to:
  /// **'Stop loss'**
  String get stopLoss;

  /// No description provided for @takeProfit.
  ///
  /// In en, this message translates to:
  /// **'Take profit'**
  String get takeProfit;

  /// No description provided for @scrollToBottom.
  ///
  /// In en, this message translates to:
  /// **'Scroll to bottom'**
  String get scrollToBottom;

  /// No description provided for @promptPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Enter a token or ask a follow-up about the analysis'**
  String get promptPlaceholder;

  /// No description provided for @analyzeCurrentContract.
  ///
  /// In en, this message translates to:
  /// **'Analyze current contract'**
  String get analyzeCurrentContract;

  /// No description provided for @stopGenerating.
  ///
  /// In en, this message translates to:
  /// **'Stop generating'**
  String get stopGenerating;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @chartLong.
  ///
  /// In en, this message translates to:
  /// **'Long'**
  String get chartLong;

  /// No description provided for @chartShort.
  ///
  /// In en, this message translates to:
  /// **'Short'**
  String get chartShort;

  /// No description provided for @chartWaitZone.
  ///
  /// In en, this message translates to:
  /// **'Wait zone'**
  String get chartWaitZone;

  /// No description provided for @chartEntryLevel.
  ///
  /// In en, this message translates to:
  /// **'{label} entry'**
  String chartEntryLevel(Object label);

  /// No description provided for @ohlcOpen.
  ///
  /// In en, this message translates to:
  /// **'O'**
  String get ohlcOpen;

  /// No description provided for @ohlcHigh.
  ///
  /// In en, this message translates to:
  /// **'H'**
  String get ohlcHigh;

  /// No description provided for @ohlcLow.
  ///
  /// In en, this message translates to:
  /// **'L'**
  String get ohlcLow;

  /// No description provided for @ohlcClose.
  ///
  /// In en, this message translates to:
  /// **'C'**
  String get ohlcClose;

  /// No description provided for @chartCursor.
  ///
  /// In en, this message translates to:
  /// **'Cursor'**
  String get chartCursor;

  /// No description provided for @chartLatest.
  ///
  /// In en, this message translates to:
  /// **'Last'**
  String get chartLatest;

  /// No description provided for @planEntryZone.
  ///
  /// In en, this message translates to:
  /// **'Entry zone: {value}'**
  String planEntryZone(Object value);

  /// No description provided for @planStopLoss.
  ///
  /// In en, this message translates to:
  /// **'Stop loss: {value}'**
  String planStopLoss(Object value);

  /// No description provided for @planTakeProfit.
  ///
  /// In en, this message translates to:
  /// **'Take profit: {value}'**
  String planTakeProfit(Object value);

  /// No description provided for @viewFullJson.
  ///
  /// In en, this message translates to:
  /// **'Click to view the full parsed JSON'**
  String get viewFullJson;

  /// No description provided for @jsonResultTitle.
  ///
  /// In en, this message translates to:
  /// **'{decision}: parsed JSON'**
  String jsonResultTitle(Object decision);

  /// No description provided for @fullJson.
  ///
  /// In en, this message translates to:
  /// **'Full JSON'**
  String get fullJson;

  /// No description provided for @decisionLongSetup.
  ///
  /// In en, this message translates to:
  /// **'Long setup'**
  String get decisionLongSetup;

  /// No description provided for @decisionShortSetup.
  ///
  /// In en, this message translates to:
  /// **'Short setup'**
  String get decisionShortSetup;

  /// No description provided for @decisionWait.
  ///
  /// In en, this message translates to:
  /// **'Wait'**
  String get decisionWait;

  /// No description provided for @decisionNoTrade.
  ///
  /// In en, this message translates to:
  /// **'No trade'**
  String get decisionNoTrade;

  /// No description provided for @decisionDataInsufficient.
  ///
  /// In en, this message translates to:
  /// **'Insufficient data'**
  String get decisionDataInsufficient;

  /// No description provided for @klineLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load candles: {error}'**
  String klineLoadFailed(Object error);

  /// No description provided for @historyLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load earlier history: {error}'**
  String historyLoadFailed(Object error);

  /// No description provided for @fetchingModels.
  ///
  /// In en, this message translates to:
  /// **'Fetching models…'**
  String get fetchingModels;

  /// No description provided for @selectModel.
  ///
  /// In en, this message translates to:
  /// **'Select model'**
  String get selectModel;

  /// No description provided for @fetchingEffort.
  ///
  /// In en, this message translates to:
  /// **'Fetching reasoning levels'**
  String get fetchingEffort;

  /// No description provided for @effortUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This model does not support reasoning levels'**
  String get effortUnsupported;

  /// No description provided for @effortGeneric.
  ///
  /// In en, this message translates to:
  /// **'Reasoning level: generic options; actual support depends on the server'**
  String get effortGeneric;

  /// No description provided for @reasoningEffort.
  ///
  /// In en, this message translates to:
  /// **'Reasoning level'**
  String get reasoningEffort;

  /// No description provided for @refreshModels.
  ///
  /// In en, this message translates to:
  /// **'Refresh model list'**
  String get refreshModels;

  /// No description provided for @newsAll.
  ///
  /// In en, this message translates to:
  /// **'All news'**
  String get newsAll;

  /// No description provided for @newsRelated.
  ///
  /// In en, this message translates to:
  /// **'{asset} related'**
  String newsRelated(Object asset);

  /// No description provided for @newsCryptoMarket.
  ///
  /// In en, this message translates to:
  /// **'Crypto market'**
  String get newsCryptoMarket;

  /// No description provided for @updatingNews.
  ///
  /// In en, this message translates to:
  /// **'Updating news'**
  String get updatingNews;

  /// No description provided for @allSources.
  ///
  /// In en, this message translates to:
  /// **'All sources'**
  String get allSources;

  /// No description provided for @fetchingNews.
  ///
  /// In en, this message translates to:
  /// **'Fetching news…'**
  String get fetchingNews;

  /// No description provided for @noRelatedNews.
  ///
  /// In en, this message translates to:
  /// **'No related news'**
  String get noRelatedNews;

  /// No description provided for @verifyUnverified.
  ///
  /// In en, this message translates to:
  /// **'Unverified'**
  String get verifyUnverified;

  /// No description provided for @verifySecondary.
  ///
  /// In en, this message translates to:
  /// **'Media confirmed'**
  String get verifySecondary;

  /// No description provided for @verifyPrimary.
  ///
  /// In en, this message translates to:
  /// **'Officially confirmed'**
  String get verifyPrimary;

  /// No description provided for @verifyConflicted.
  ///
  /// In en, this message translates to:
  /// **'Disputed'**
  String get verifyConflicted;

  /// No description provided for @importanceCritical.
  ///
  /// In en, this message translates to:
  /// **'Critical'**
  String get importanceCritical;

  /// No description provided for @importanceHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get importanceHigh;

  /// No description provided for @importanceMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get importanceMedium;

  /// No description provided for @importanceLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get importanceLow;

  /// No description provided for @categoryMacro.
  ///
  /// In en, this message translates to:
  /// **'Macro'**
  String get categoryMacro;

  /// No description provided for @categoryRegulation.
  ///
  /// In en, this message translates to:
  /// **'Regulation'**
  String get categoryRegulation;

  /// No description provided for @categoryCentralBank.
  ///
  /// In en, this message translates to:
  /// **'Central bank'**
  String get categoryCentralBank;

  /// No description provided for @categoryExchange.
  ///
  /// In en, this message translates to:
  /// **'Exchange'**
  String get categoryExchange;

  /// No description provided for @categorySecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get categorySecurity;

  /// No description provided for @categoryProject.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get categoryProject;

  /// No description provided for @categoryMarket.
  ///
  /// In en, this message translates to:
  /// **'Market'**
  String get categoryMarket;

  /// No description provided for @categoryOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get categoryOther;

  /// No description provided for @newsSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Market News settings'**
  String get newsSettingsTitle;

  /// No description provided for @finnhubDocs.
  ///
  /// In en, this message translates to:
  /// **'View Finnhub Market News docs'**
  String get finnhubDocs;

  /// No description provided for @marketauxDocs.
  ///
  /// In en, this message translates to:
  /// **'View Marketaux API docs'**
  String get marketauxDocs;

  /// No description provided for @officialSources.
  ///
  /// In en, this message translates to:
  /// **'Official sources'**
  String get officialSources;

  /// No description provided for @sourcesStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting data sources…'**
  String get sourcesStarting;

  /// No description provided for @noNewsSources.
  ///
  /// In en, this message translates to:
  /// **'No news sources enabled'**
  String get noNewsSources;

  /// No description provided for @sourcesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'{count} sources unavailable'**
  String sourcesUnavailable(Object count);

  /// No description provided for @sourcesAvailable.
  ///
  /// In en, this message translates to:
  /// **'{count} sources available'**
  String sourcesAvailable(Object count);

  /// No description provided for @noSuccessfulUpdate.
  ///
  /// In en, this message translates to:
  /// **'No successful update yet'**
  String get noSuccessfulUpdate;

  /// No description provided for @lastSuccessfulUpdate.
  ///
  /// In en, this message translates to:
  /// **'Last successful update: {time}'**
  String lastSuccessfulUpdate(Object time);

  /// No description provided for @updatedAtNone.
  ///
  /// In en, this message translates to:
  /// **'Updated —'**
  String get updatedAtNone;

  /// No description provided for @updatedAt.
  ///
  /// In en, this message translates to:
  /// **'Updated {time}'**
  String updatedAt(Object time);

  /// No description provided for @providerActive.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get providerActive;

  /// No description provided for @providerDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get providerDisabled;

  /// No description provided for @providerError.
  ///
  /// In en, this message translates to:
  /// **'Connection failed'**
  String get providerError;

  /// No description provided for @providerRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Rate limited'**
  String get providerRateLimited;

  /// No description provided for @agentSettings.
  ///
  /// In en, this message translates to:
  /// **'Agent settings'**
  String get agentSettings;

  /// No description provided for @bybitDocs.
  ///
  /// In en, this message translates to:
  /// **'View Bybit read-only account API docs'**
  String get bybitDocs;

  /// No description provided for @bybitHint.
  ///
  /// In en, this message translates to:
  /// **'Only used to read actual fee rates'**
  String get bybitHint;

  /// No description provided for @nansenDocs.
  ///
  /// In en, this message translates to:
  /// **'View Nansen MCP docs'**
  String get nansenDocs;

  /// No description provided for @coinalyzeDocs.
  ///
  /// In en, this message translates to:
  /// **'View Coinalyze API docs'**
  String get coinalyzeDocs;

  /// No description provided for @codexSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Signed in to ChatGPT; using your Codex subscription quota.'**
  String get codexSignedIn;

  /// No description provided for @codexSignInHint.
  ///
  /// In en, this message translates to:
  /// **'Sign in with ChatGPT to use Codex.'**
  String get codexSignInHint;

  /// No description provided for @connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get connecting;

  /// No description provided for @signInAgain.
  ///
  /// In en, this message translates to:
  /// **'Sign in again'**
  String get signInAgain;

  /// No description provided for @signInChatGpt.
  ///
  /// In en, this message translates to:
  /// **'Sign in to ChatGPT'**
  String get signInChatGpt;

  /// No description provided for @connectionNameEmpty.
  ///
  /// In en, this message translates to:
  /// **'Profile name cannot be empty.'**
  String get connectionNameEmpty;

  /// No description provided for @connectionNameExists.
  ///
  /// In en, this message translates to:
  /// **'Profile name already exists.'**
  String get connectionNameExists;

  /// No description provided for @newConnection.
  ///
  /// In en, this message translates to:
  /// **'New profile'**
  String get newConnection;

  /// No description provided for @llmConnection.
  ///
  /// In en, this message translates to:
  /// **'LLM connection'**
  String get llmConnection;

  /// No description provided for @savedConnections.
  ///
  /// In en, this message translates to:
  /// **'Saved profiles'**
  String get savedConnections;

  /// No description provided for @deleteConnection.
  ///
  /// In en, this message translates to:
  /// **'Delete profile'**
  String get deleteConnection;

  /// No description provided for @connectionName.
  ///
  /// In en, this message translates to:
  /// **'Profile name'**
  String get connectionName;

  /// No description provided for @apiType.
  ///
  /// In en, this message translates to:
  /// **'API type'**
  String get apiType;

  /// No description provided for @activityThinking.
  ///
  /// In en, this message translates to:
  /// **'• Thinking - Analyzing…'**
  String get activityThinking;

  /// No description provided for @generationStopped.
  ///
  /// In en, this message translates to:
  /// **'> Generation stopped; the incomplete answer was not used to update the analysis.'**
  String get generationStopped;

  /// No description provided for @agentRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'> Agent request failed: {error}'**
  String agentRequestFailed(Object error);

  /// No description provided for @codexNotReady.
  ///
  /// In en, this message translates to:
  /// **'> Sign in to OpenAI Codex and select a model in settings first.'**
  String get codexNotReady;

  /// No description provided for @llmNotReady.
  ///
  /// In en, this message translates to:
  /// **'> Fill in the LLM endpoint and model and save an API key in settings first.'**
  String get llmNotReady;

  /// No description provided for @noCandlesToAnalyze.
  ///
  /// In en, this message translates to:
  /// **'{symbol} has no candles to analyze.'**
  String noCandlesToAnalyze(Object symbol);

  /// No description provided for @activityIndicatorsDone.
  ///
  /// In en, this message translates to:
  /// **'• Deterministic Engine - Indicators calculated'**
  String get activityIndicatorsDone;

  /// No description provided for @activityResultGenerating.
  ///
  /// In en, this message translates to:
  /// **'• Result - Generating result…'**
  String get activityResultGenerating;

  /// No description provided for @activityMarketSnapshot.
  ///
  /// In en, this message translates to:
  /// **'• Market Snapshot - Fetching fixed multi-timeframe market data'**
  String get activityMarketSnapshot;

  /// No description provided for @invalidContract.
  ///
  /// In en, this message translates to:
  /// **'{symbol} has an invalid contract status or type.'**
  String invalidContract(Object symbol);

  /// No description provided for @noticeNoPlan.
  ///
  /// In en, this message translates to:
  /// **'No complete price plan yet; rely on the written explanation.'**
  String get noticeNoPlan;

  /// No description provided for @noticePlanRejected.
  ///
  /// In en, this message translates to:
  /// **'The price plan failed validation; these levels are not used.'**
  String get noticePlanRejected;

  /// No description provided for @noticeSymbolMismatch.
  ///
  /// In en, this message translates to:
  /// **'The analyzed symbol does not match {symbol}; please analyze again.'**
  String noticeSymbolMismatch(Object symbol);

  /// No description provided for @noticeChartSwitched.
  ///
  /// In en, this message translates to:
  /// **'The chart has switched to {active}; chart markers for {symbol} were not added.'**
  String noticeChartSwitched(Object active, Object symbol);

  /// No description provided for @dataSourceNotice.
  ///
  /// In en, this message translates to:
  /// **'> Data source notes: {notices}'**
  String dataSourceNotice(Object notices);

  /// No description provided for @quickAnalyzePrompt.
  ///
  /// In en, this message translates to:
  /// **'Analyze whether {symbol} is better suited to going long, going short, or waiting right now. Based on the current price, state directly whether an entry is possible now; if the opportunity has already played out, explain what conditions to wait for.'**
  String quickAnalyzePrompt(Object symbol);

  /// No description provided for @majorEventCancel.
  ///
  /// In en, this message translates to:
  /// **'A confirmed major event occurred; please analyze again: {headline}'**
  String majorEventCancel(Object headline);

  /// No description provided for @entryDetails.
  ///
  /// In en, this message translates to:
  /// **'Entry details'**
  String get entryDetails;

  /// No description provided for @planCleared.
  ///
  /// In en, this message translates to:
  /// **'The current plan has been cleared'**
  String get planCleared;

  /// No description provided for @biasLong.
  ///
  /// In en, this message translates to:
  /// **'Bullish'**
  String get biasLong;

  /// No description provided for @biasShort.
  ///
  /// In en, this message translates to:
  /// **'Bearish'**
  String get biasShort;

  /// No description provided for @actionConfirming.
  ///
  /// In en, this message translates to:
  /// **'Confirming'**
  String get actionConfirming;

  /// No description provided for @actionNoEntry.
  ///
  /// In en, this message translates to:
  /// **'No entry for now'**
  String get actionNoEntry;

  /// No description provided for @actionMissed.
  ///
  /// In en, this message translates to:
  /// **'Missed; do not chase'**
  String get actionMissed;

  /// No description provided for @actionInvalid.
  ///
  /// In en, this message translates to:
  /// **'Original plan invalidated'**
  String get actionInvalid;

  /// No description provided for @triggerCloseAbove.
  ///
  /// In en, this message translates to:
  /// **'Close above the specified price'**
  String get triggerCloseAbove;

  /// No description provided for @triggerCloseBelow.
  ///
  /// In en, this message translates to:
  /// **'Close below the specified price'**
  String get triggerCloseBelow;

  /// No description provided for @triggerBreakoutRetest.
  ///
  /// In en, this message translates to:
  /// **'Breakout holds on a retest by a later candle'**
  String get triggerBreakoutRetest;

  /// No description provided for @triggerTouchZone.
  ///
  /// In en, this message translates to:
  /// **'Touch the zone edge and close back inside'**
  String get triggerTouchZone;

  /// No description provided for @triggerVolume.
  ///
  /// In en, this message translates to:
  /// **'Price direction confirmed by rising volume'**
  String get triggerVolume;

  /// No description provided for @statusTerminal.
  ///
  /// In en, this message translates to:
  /// **'Wait · {action} (previously {side})'**
  String statusTerminal(Object action, Object side);

  /// No description provided for @refreshOpportunity.
  ///
  /// In en, this message translates to:
  /// **'Refresh current opportunity'**
  String get refreshOpportunity;

  /// No description provided for @referencePrice.
  ///
  /// In en, this message translates to:
  /// **'Reference price {price}'**
  String referencePrice(Object price);

  /// No description provided for @entrySummary.
  ///
  /// In en, this message translates to:
  /// **'Entry zone {low}–{high} · Stop loss {stop}'**
  String entrySummary(Object high, Object low, Object stop);

  /// No description provided for @validUntil.
  ///
  /// In en, this message translates to:
  /// **'Valid until {time}'**
  String validUntil(Object time);

  /// No description provided for @referenceEntry.
  ///
  /// In en, this message translates to:
  /// **'Reference entry {price} · Net R:R {rr}:1'**
  String referenceEntry(Object price, Object rr);

  /// No description provided for @chaseBoundary.
  ///
  /// In en, this message translates to:
  /// **'Post-cost chase limit {price}'**
  String chaseBoundary(Object price);

  /// No description provided for @costEstimateNote.
  ///
  /// In en, this message translates to:
  /// **'Estimated with public taker fees and a 3-hour funding scenario; position impact not estimated'**
  String get costEstimateNote;

  /// No description provided for @triggerSummary.
  ///
  /// In en, this message translates to:
  /// **'Trigger: {trigger} · {minutes} min · price {price}'**
  String triggerSummary(Object minutes, Object price, Object trigger);

  /// No description provided for @zoneEdge.
  ///
  /// In en, this message translates to:
  /// **'zone edge'**
  String get zoneEdge;

  /// No description provided for @invalidationSummary.
  ///
  /// In en, this message translates to:
  /// **'Invalidation {price} · Stop reference {stop}'**
  String invalidationSummary(Object price, Object stop);

  /// No description provided for @featureSnapshot.
  ///
  /// In en, this message translates to:
  /// **'Indicator snapshot {time}'**
  String featureSnapshot(Object time);

  /// No description provided for @reviewedAt.
  ///
  /// In en, this message translates to:
  /// **'Reviewed at {time}'**
  String reviewedAt(Object time);

  /// No description provided for @viewDetails.
  ///
  /// In en, this message translates to:
  /// **'View details'**
  String get viewDetails;

  /// No description provided for @checkingPrice.
  ///
  /// In en, this message translates to:
  /// **'Checking the latest price'**
  String get checkingPrice;

  /// No description provided for @priceUnconfirmed.
  ///
  /// In en, this message translates to:
  /// **'Latest price not yet confirmed; waiting for a market refresh'**
  String get priceUnconfirmed;

  /// No description provided for @awaitingQuotes.
  ///
  /// In en, this message translates to:
  /// **'Waiting for bid/ask quotes and funding settlement info'**
  String get awaitingQuotes;

  /// No description provided for @rrTooLow.
  ///
  /// In en, this message translates to:
  /// **'Reference net R:R is below 1:1; waiting for a better price and a new trigger'**
  String get rrTooLow;

  /// No description provided for @marketUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Latest market data unavailable; retrying shortly'**
  String get marketUnavailable;

  /// No description provided for @priceChanged.
  ///
  /// In en, this message translates to:
  /// **'Price changed; re-checking entry conditions'**
  String get priceChanged;

  /// No description provided for @recheckOnReturn.
  ///
  /// In en, this message translates to:
  /// **'Will re-check with the latest market data on return'**
  String get recheckOnReturn;

  /// No description provided for @entryWaiting.
  ///
  /// In en, this message translates to:
  /// **'Awaiting trigger'**
  String get entryWaiting;

  /// No description provided for @entryReady.
  ///
  /// In en, this message translates to:
  /// **'Entry available for reference'**
  String get entryReady;

  /// No description provided for @entryPaused.
  ///
  /// In en, this message translates to:
  /// **'Awaiting pullback'**
  String get entryPaused;

  /// No description provided for @entryRealized.
  ///
  /// In en, this message translates to:
  /// **'Opportunity realized'**
  String get entryRealized;

  /// No description provided for @entryInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalidated'**
  String get entryInvalid;

  /// No description provided for @entryUnverified.
  ///
  /// In en, this message translates to:
  /// **'Awaiting confirmation'**
  String get entryUnverified;

  /// No description provided for @entryNoPlan.
  ///
  /// In en, this message translates to:
  /// **'No entry plan to verify'**
  String get entryNoPlan;

  /// No description provided for @entryIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Prices or targets are incomplete'**
  String get entryIncomplete;

  /// No description provided for @entryAmbiguousStart.
  ///
  /// In en, this message translates to:
  /// **'Event timing within the starting minute is unclear; please analyze again'**
  String get entryAmbiguousStart;

  /// No description provided for @entryAmbiguousPath.
  ///
  /// In en, this message translates to:
  /// **'Invalidation and target were hit in the same minute; path is uncertain'**
  String get entryAmbiguousPath;

  /// No description provided for @entryInvalidBeforeEntry.
  ///
  /// In en, this message translates to:
  /// **'Structure invalidated before entry'**
  String get entryInvalidBeforeEntry;

  /// No description provided for @entryTargetReached.
  ///
  /// In en, this message translates to:
  /// **'TP1 reached without entry; a new plan is needed'**
  String get entryTargetReached;

  /// No description provided for @entryStructureInvalid.
  ///
  /// In en, this message translates to:
  /// **'Structure invalidated'**
  String get entryStructureInvalid;

  /// No description provided for @entryExpired.
  ///
  /// In en, this message translates to:
  /// **'Candidate plan expired'**
  String get entryExpired;

  /// No description provided for @entryStale.
  ///
  /// In en, this message translates to:
  /// **'Market data is stale or the price path is incomplete'**
  String get entryStale;

  /// No description provided for @entryNeedsConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Entry conditions still need confirmation; rely on the latest market data'**
  String get entryNeedsConfirmation;

  /// No description provided for @entryChaseUndefined.
  ///
  /// In en, this message translates to:
  /// **'Maximum chase price is undefined'**
  String get entryChaseUndefined;

  /// No description provided for @entryAboveChase.
  ///
  /// In en, this message translates to:
  /// **'Above the maximum chase price; waiting for a pullback and re-check'**
  String get entryAboveChase;

  /// No description provided for @entryOutsideZone.
  ///
  /// In en, this message translates to:
  /// **'Price has not entered the allowed entry zone'**
  String get entryOutsideZone;

  /// No description provided for @entryAwaitTriggerCandle.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a new complete trigger candle'**
  String get entryAwaitTriggerCandle;

  /// No description provided for @entryTriggerConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Entry trigger confirmed at the reference price; re-check after price changes'**
  String get entryTriggerConfirmed;

  /// No description provided for @planUnknownDecision.
  ///
  /// In en, this message translates to:
  /// **'Unknown decision type {decision}'**
  String planUnknownDecision(Object decision);

  /// No description provided for @planInvalidWaitZone.
  ///
  /// In en, this message translates to:
  /// **'Invalid candidate wait zone; price markers ignored'**
  String get planInvalidWaitZone;

  /// No description provided for @planWaitOnlyZone.
  ///
  /// In en, this message translates to:
  /// **'WAIT keeps only the candidate wait zone; other price markers ignored'**
  String get planWaitOnlyZone;

  /// No description provided for @planNonSetupIgnored.
  ///
  /// In en, this message translates to:
  /// **'Price markers on a non-trade setup are ignored'**
  String get planNonSetupIgnored;

  /// No description provided for @planSetupMissingEntry.
  ///
  /// In en, this message translates to:
  /// **'Trade setup is missing a complete entry zone or stop loss'**
  String get planSetupMissingEntry;

  /// No description provided for @planPricesInvalid.
  ///
  /// In en, this message translates to:
  /// **'Prices must be positive and finite'**
  String get planPricesInvalid;

  /// No description provided for @planEntryInverted.
  ///
  /// In en, this message translates to:
  /// **'Entry zone lower bound is above the upper bound'**
  String get planEntryInverted;

  /// No description provided for @planMissingTargets.
  ///
  /// In en, this message translates to:
  /// **'Trade setup is missing take-profit targets'**
  String get planMissingTargets;

  /// No description provided for @planTooManyTargets.
  ///
  /// In en, this message translates to:
  /// **'The chart only shows the first three take-profit targets'**
  String get planTooManyTargets;

  /// No description provided for @planLongStop.
  ///
  /// In en, this message translates to:
  /// **'Long stop loss must be below the entry zone'**
  String get planLongStop;

  /// No description provided for @planLongTargets.
  ///
  /// In en, this message translates to:
  /// **'Long take-profits must be above the entry zone'**
  String get planLongTargets;

  /// No description provided for @planLongTargetOrder.
  ///
  /// In en, this message translates to:
  /// **'Long take-profits must be in ascending price order'**
  String get planLongTargetOrder;

  /// No description provided for @planLongChase.
  ///
  /// In en, this message translates to:
  /// **'Long maximum chase price cannot be below the entry zone upper bound'**
  String get planLongChase;

  /// No description provided for @planShortStop.
  ///
  /// In en, this message translates to:
  /// **'Short stop loss must be above the entry zone'**
  String get planShortStop;

  /// No description provided for @planShortTargets.
  ///
  /// In en, this message translates to:
  /// **'Short take-profits must be below the entry zone'**
  String get planShortTargets;

  /// No description provided for @planShortTargetOrder.
  ///
  /// In en, this message translates to:
  /// **'Short take-profits must be in descending price order'**
  String get planShortTargetOrder;

  /// No description provided for @planShortChase.
  ///
  /// In en, this message translates to:
  /// **'Short maximum chase price cannot be above the entry zone lower bound'**
  String get planShortChase;

  /// No description provided for @planTickMisaligned.
  ///
  /// In en, this message translates to:
  /// **'Prices are not aligned to the contract tick size; for reference only, confirm precision before ordering'**
  String get planTickMisaligned;

  /// No description provided for @planAllocationInvalid.
  ///
  /// In en, this message translates to:
  /// **'Take-profit allocations are incomplete or invalid and are not used for position splitting'**
  String get planAllocationInvalid;

  /// No description provided for @planAllocationTotal.
  ///
  /// In en, this message translates to:
  /// **'Take-profit allocations do not total 100% and are not used for position splitting'**
  String get planAllocationTotal;

  /// No description provided for @planGrossRrMismatch.
  ///
  /// In en, this message translates to:
  /// **'Gross RR for take-profit {price} differs from the deterministic calculation'**
  String planGrossRrMismatch(Object price);

  /// No description provided for @planNetAboveGross.
  ///
  /// In en, this message translates to:
  /// **'Net RR for take-profit {price} is above Gross RR'**
  String planNetAboveGross(Object price);

  /// No description provided for @coinalyzeKeyMissing.
  ///
  /// In en, this message translates to:
  /// **'Coinalyze API: API key not configured.'**
  String get coinalyzeKeyMissing;

  /// No description provided for @nansenKeyMissing.
  ///
  /// In en, this message translates to:
  /// **'Nansen MCP: API key not configured.'**
  String get nansenKeyMissing;

  /// No description provided for @activityFailed.
  ///
  /// In en, this message translates to:
  /// **'{activity} (failed)'**
  String activityFailed(Object activity);

  /// No description provided for @activityTokenBackground.
  ///
  /// In en, this message translates to:
  /// **'• Project Background - Updating background cache'**
  String get activityTokenBackground;

  /// No description provided for @activityDiscoverTools.
  ///
  /// In en, this message translates to:
  /// **'• MCP - Discovering available tools'**
  String get activityDiscoverTools;

  /// No description provided for @signInChatGptFirst.
  ///
  /// In en, this message translates to:
  /// **'Please sign in to ChatGPT first.'**
  String get signInChatGptFirst;

  /// No description provided for @oauthCallbackInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid OAuth callback; please try again.'**
  String get oauthCallbackInvalid;

  /// No description provided for @streamEndedEarly.
  ///
  /// In en, this message translates to:
  /// **'The response stream ended early without a completion signal.'**
  String get streamEndedEarly;

  /// No description provided for @codexMissingAccount.
  ///
  /// In en, this message translates to:
  /// **'OpenAI Codex OAuth is missing the ChatGPT account ID; please sign in again.'**
  String get codexMissingAccount;

  /// No description provided for @codexFailedStatus.
  ///
  /// In en, this message translates to:
  /// **'Codex returned a failed status.'**
  String get codexFailedStatus;

  /// No description provided for @responseIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Response incomplete: {reason}'**
  String responseIncomplete(Object reason);

  /// No description provided for @responseNotCompleted.
  ///
  /// In en, this message translates to:
  /// **'The response did not complete successfully.'**
  String get responseNotCompleted;

  /// No description provided for @responseParseFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to parse the response.'**
  String get responseParseFailed;

  /// No description provided for @llmKeyMissing.
  ///
  /// In en, this message translates to:
  /// **'Save an LLM API key or sign in to OpenAI Codex in settings first.'**
  String get llmKeyMissing;

  /// No description provided for @bybitKeyPair.
  ///
  /// In en, this message translates to:
  /// **'Bybit account API: API key and API secret must both be configured.'**
  String get bybitKeyPair;

  /// No description provided for @activityBybitFees.
  ///
  /// In en, this message translates to:
  /// **'• Bybit Account - Fetching actual fee rates'**
  String get activityBybitFees;

  /// No description provided for @sourceDisabled.
  ///
  /// In en, this message translates to:
  /// **'FULL_SOURCE_ENRICHMENT: {source} is disabled.'**
  String sourceDisabled(Object source);

  /// No description provided for @sourceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'FULL_SOURCE_ENRICHMENT: {source} is currently unavailable.'**
  String sourceUnavailable(Object source);

  /// No description provided for @activityLlmRetry.
  ///
  /// In en, this message translates to:
  /// **'• LLM - Response interrupted, retrying {attempt}/4'**
  String activityLlmRetry(Object attempt);

  /// No description provided for @activityFillSources.
  ///
  /// In en, this message translates to:
  /// **'• Data Sources - Filling missing sources: {sources}'**
  String activityFillSources(Object sources);

  /// No description provided for @enrichmentFailed.
  ///
  /// In en, this message translates to:
  /// **'FULL_SOURCE_ENRICHMENT: the follow-up request failed; the first-pass analysis was kept.'**
  String get enrichmentFailed;

  /// No description provided for @enrichmentIncomplete.
  ///
  /// In en, this message translates to:
  /// **'FULL_SOURCE_ENRICHMENT incomplete: {sources} available but not called; they may not apply to this asset or were skipped by the model.'**
  String enrichmentIncomplete(Object sources);

  /// No description provided for @enrichmentInvalid.
  ///
  /// In en, this message translates to:
  /// **'FULL_SOURCE_ENRICHMENT: {sources} were attempted but returned no valid data.'**
  String enrichmentInvalid(Object sources);

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @loadingKlines.
  ///
  /// In en, this message translates to:
  /// **'Loading Bybit perpetual candles…'**
  String get loadingKlines;

  /// No description provided for @loadingHistory.
  ///
  /// In en, this message translates to:
  /// **'Loading earlier history…'**
  String get loadingHistory;

  /// No description provided for @modelListFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to fetch models: {error}'**
  String modelListFailed(Object error);

  /// No description provided for @modelSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save model: {error}'**
  String modelSaveFailed(Object error);

  /// No description provided for @codexLoginFailed.
  ///
  /// In en, this message translates to:
  /// **'OpenAI Codex sign-in failed: {error}'**
  String codexLoginFailed(Object error);

  /// No description provided for @planCardDecision.
  ///
  /// In en, this message translates to:
  /// **'Decision: {decision}'**
  String planCardDecision(Object decision);

  /// No description provided for @planCardEntry.
  ///
  /// In en, this message translates to:
  /// **'Entry {low} – {high}'**
  String planCardEntry(Object high, Object low);

  /// No description provided for @languageDescription.
  ///
  /// In en, this message translates to:
  /// **'Change the display language of the app'**
  String get languageDescription;

  /// No description provided for @agentSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'LLM connections, MCP servers and data APIs'**
  String get agentSettingsDescription;

  /// No description provided for @newsSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'News providers and official data sources'**
  String get newsSettingsDescription;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose light, dark or follow the system'**
  String get themeDescription;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @newsApis.
  ///
  /// In en, this message translates to:
  /// **'News APIs'**
  String get newsApis;

  /// No description provided for @newsOutlets.
  ///
  /// In en, this message translates to:
  /// **'News outlets'**
  String get newsOutlets;

  /// No description provided for @finnhubDescription.
  ///
  /// In en, this message translates to:
  /// **'Crypto, general and forex market news'**
  String get finnhubDescription;

  /// No description provided for @marketauxDescription.
  ///
  /// In en, this message translates to:
  /// **'News about the token you are viewing'**
  String get marketauxDescription;

  /// No description provided for @bbcDescription.
  ///
  /// In en, this message translates to:
  /// **'World news, including geopolitics and conflicts'**
  String get bbcDescription;

  /// No description provided for @bybitMcpDescription.
  ///
  /// In en, this message translates to:
  /// **'Bybit market data and contract details'**
  String get bybitMcpDescription;

  /// No description provided for @openWebSearchDescription.
  ///
  /// In en, this message translates to:
  /// **'Web search and webpage reading'**
  String get openWebSearchDescription;

  /// No description provided for @nansenDescription.
  ///
  /// In en, this message translates to:
  /// **'On-chain data and smart money flows'**
  String get nansenDescription;

  /// No description provided for @coinalyzeDescription.
  ///
  /// In en, this message translates to:
  /// **'Cross-exchange derivatives history'**
  String get coinalyzeDescription;

  /// No description provided for @shortTermAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Short-term (intraday, hours)'**
  String get shortTermAnalysis;

  /// No description provided for @swingAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Swing (days to two weeks)'**
  String get swingAnalysis;

  /// No description provided for @swingAnalyzePrompt.
  ///
  /// In en, this message translates to:
  /// **'I plan a swing trade held for several days up to two weeks. Using 4H candles as the decision timeframe, 1D for the trend and 1H for the entry trigger, analyze whether {symbol} is better suited to going long, going short, or waiting right now. Based on the current price, state directly whether an entry is possible now; if the opportunity has already played out, explain what conditions to wait for.'**
  String swingAnalyzePrompt(Object symbol);
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en': return AppLocalizationsEn();
    case 'zh': return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
