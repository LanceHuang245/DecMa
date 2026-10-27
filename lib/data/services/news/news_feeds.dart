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
  }) {
    final headline = _xmlValue(item, 'title')!;
    final link = _xmlValue(item, 'link');
    final rawId = _xmlValue(item, 'guid') ?? link ?? headline;
    final published = _httpDate(_xmlValue(item, 'pubDate')) ?? now;
    return NewsEvent(
      eventId: '${provider.toLowerCase().replaceAll(' ', '_')}:$rawId',
      headline: headline,
      summary: _xmlValue(item, 'description'),
      provider: provider,
      originalSource: originalSource,
      sourceTier: NewsSourceTier.primary,
      category: category,
      eventType: category.name.toUpperCase(),
      scope: scope,
      importance: NewsImportance.medium,
      assets: const [],
      directAssets: const [],
      indirectAssets: const [],
      country: 'US',
      publishedAt: published,
      receivedAt: now,
      url: link,
      verificationStatus: NewsVerificationStatus.primarySourceConfirmed,
      isBreaking: now.difference(published) < const Duration(hours: 2),
      isOfficial: true,
      rawSourceId: rawId,
      sources: [
        NewsEventSource(
          provider: provider,
          originalSource: originalSource,
          sourceTier: NewsSourceTier.primary,
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

  DateTime? _httpDate(String? value) {
    if (value == null) return null;
    try {
      return HttpDate.parse(value).toUtc();
    } catch (_) {
      return DateTime.tryParse(value)?.toUtc();
    }
  }
}
