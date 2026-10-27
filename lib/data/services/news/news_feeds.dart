import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../../app_constants.dart';
import '../../../domain/models/news_event.dart';
import '../../../utils/network.dart';

// Fetch and decode feeds; refresh policy and persistence belong to NewsRepository.
class NewsFeeds {
  const NewsFeeds(this._dio);
  final Dio _dio;

  Future<List<NewsEvent>> finnhub(
    String? apiKey,
    DateTime now,
    CancelToken? cancelToken,
  ) async {
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw const AppFailure(
        kind: AppFailureKind.configuration,
        provider: 'Finnhub',
      );
    }
    final events = <NewsEvent>[];
    for (final category in ['crypto', 'general', 'forex']) {
      final uri = Uri.https(AppConstants.finnhubApiHost, '/api/v1/news', {
        'category': category,
        'token': apiKey,
      });
      final response = await runNetworkRequest(
        'Finnhub',
        () => _dio.getUri<String>(
          uri,
          options: networkOptions(),
          cancelToken: cancelToken,
        ),
      );
      _checkResponse(response, provider: 'Finnhub');
      for (final item in jsonDecode(response.data!)) {
        final published = DateTime.fromMillisecondsSinceEpoch(
          item['datetime'] * 1000,
          isUtc: true,
        );
        final String source = item['source'];
        final String url = item['url'];
        events.add(
          NewsEvent(
            eventId: 'finnhub:${item['id']}',
            headline: item['headline'],
            summary: item['summary'],
            provider: 'Finnhub',
            originalSource: source,
            sourceTier: NewsSourceTier.aggregator,
            category: NewsCategory.other,
            eventType: category.toUpperCase(),
            scope: NewsScope.cryptoMarket,
            importance: NewsImportance.low,
            assets: const [],
            directAssets: const [],
            indirectAssets: const [],
            country: null,
            publishedAt: published,
            receivedAt: now,
            url: url,
            verificationStatus: NewsVerificationStatus.unverified,
            isBreaking: now.difference(published) < const Duration(hours: 2),
            isOfficial: false,
            rawSourceId: '${item['id']}',
            sources: [
              NewsEventSource(
                provider: 'Finnhub',
                originalSource: source,
                sourceTier: NewsSourceTier.aggregator,
                url: url,
              ),
            ],
          ),
        );
      }
    }
    return events;
  }

  Future<List<NewsEvent>> federalReserve(
    DateTime now,
    CancelToken? cancelToken,
  ) async {
    final events = <NewsEvent>[];
    for (final url in AppConstants.federalReserveRssUrls) {
      events.addAll(
        await rss(
          provider: 'Federal Reserve',
          originalSource: 'Federal Reserve',
          url: url,
          category: NewsCategory.centralBank,
          scope: NewsScope.macroGlobal,
          now: now,
          cancelToken: cancelToken,
        ),
      );
    }
    return events;
  }

  Future<List<NewsEvent>> rss({
    required String provider,
    required String originalSource,
    required String url,
    required NewsCategory category,
    required NewsScope scope,
    required DateTime now,
    bool official = true,
    CancelToken? cancelToken,
  }) async {
    final response = await runNetworkRequest(
      provider,
      () => _dio.getUri<String>(
        Uri.parse(url),
        options: networkOptions(),
        cancelToken: cancelToken,
      ),
    );
    _checkResponse(response, provider: provider);
    return RegExp(r'<item\b[^>]*>(.*?)</item>', dotAll: true)
        .allMatches(response.data!)
        .map((item) => item.group(1)!)
        .map(
          (item) => _rssEvent(
            provider: provider,
            originalSource: originalSource,
            item: item,
            category: category,
            scope: scope,
            now: now,
            official: official,
          ),
        )
        .toList();
  }

  NewsEvent _rssEvent({
    required String provider,
    required String originalSource,
    required String item,
    required NewsCategory category,
    required NewsScope scope,
    required DateTime now,
    required bool official,
  }) {
    final headline = _xmlValue(item, 'title')!;
    final link = _xmlValue(item, 'link');
    final rawId = _xmlValue(item, 'guid') ?? link ?? headline;
    final pubDate = _xmlValue(item, 'pubDate');
    final published = pubDate == null ? now : _rfc822Date(pubDate);
    final tier = official
        ? NewsSourceTier.primary
        : NewsSourceTier.highQualityNews;
    return NewsEvent(
      eventId: '${provider.toLowerCase().replaceAll(' ', '_')}:$rawId',
      headline: headline,
      summary: _xmlValue(item, 'description'),
      provider: provider,
      originalSource: originalSource,
      sourceTier: tier,
      category: category,
      eventType: category.name.toUpperCase(),
      scope: scope,
      importance: NewsImportance.medium,
      assets: const [],
      directAssets: const [],
      indirectAssets: const [],
      country: official ? 'US' : null,
      publishedAt: published,
      receivedAt: now,
      url: link,
      verificationStatus: official
          ? NewsVerificationStatus.primarySourceConfirmed
          : NewsVerificationStatus.unverified,
      isBreaking: now.difference(published) < const Duration(hours: 2),
      isOfficial: official,
      rawSourceId: rawId,
      sources: [
        NewsEventSource(
          provider: provider,
          originalSource: originalSource,
          sourceTier: tier,
          url: link,
        ),
      ],
    );
  }

  void _checkResponse(Response<dynamic> response, {required String provider}) {
    if (response.statusCode == 429) {
      throw AppFailure.fromResponse(response, provider: provider);
    }
    requireSuccessfulResponse(response, provider: provider);
  }

  String? _xmlValue(String item, String tag) {
    final match = RegExp(
      '<$tag\\b[^>]*>(.*?)</$tag>',
      dotAll: true,
    ).firstMatch(item);
    if (match == null) return null;
    return match
        .group(1)!
        .replaceAll('<![CDATA[', '')
        .replaceAll(']]>', '')
        .replaceAll(RegExp('<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .trim();
  }

  // RSS pubDate is RFC 822; HttpDate only accepts "GMT", but feeds also use
  // named US zones (BEA: "EDT") and numeric offsets (SEC: "-0400").
  DateTime _rfc822Date(String value) {
    final split = value.lastIndexOf(' ');
    final zone = value.substring(split + 1);
    final gmt = HttpDate.parse('${value.substring(0, split)} GMT');
    final offset =
        _rfc822Zones[zone] ??
        (zone.startsWith('-') ? -1 : 1) *
            (int.parse(zone.substring(1, 3)) * 60 +
                int.parse(zone.substring(3)));
    return gmt.subtract(Duration(minutes: offset));
  }

  // Named RFC 822 zones as minute offsets from GMT.
  static const _rfc822Zones = {
    'GMT': 0,
    'UT': 0,
    'EST': -300,
    'EDT': -240,
    'CST': -360,
    'CDT': -300,
    'MST': -420,
    'MDT': -360,
    'PST': -480,
    'PDT': -420,
  };
}
