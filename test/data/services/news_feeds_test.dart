import 'package:decma/data/services/news/news_feeds.dart';
import 'package:decma/domain/models/news_event.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Real pubDate formats: Fed (single-digit day, CDATA), BEA (EDT), SEC (-0400), White House (+0000).
  test('RSS pubDate parses every RFC 822 zone form', () async {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response<String>(
              requestOptions: options,
              statusCode: 200,
              data: '''
<rss><channel>
<item><title>Fed</title><pubDate><![CDATA[Wed, 7 Oct 2026 18:00:00 GMT]]></pubDate></item>
<item><title>BEA</title><pubDate>Tue, 06 Oct 2026 08:30:00 EDT</pubDate></item>
<item><title>SEC</title><pubDate>Fri, 23 Oct 2026 10:10:00 -0400</pubDate></item>
<item><title>White House</title><pubDate>Fri, 23 Oct 2026 19:51:09 +0000</pubDate></item>
</channel></rss>''',
            ),
          ),
        ),
      );
    addTearDown(() => dio.close(force: true));
    final events = await NewsFeeds(dio).rss(
      provider: 'BBC',
      originalSource: 'BBC News',
      url: 'https://feeds.bbci.co.uk/news/world/rss.xml',
      category: NewsCategory.other,
      scope: NewsScope.macroGlobal,
      now: DateTime.utc(2026, 10, 27),
      official: false,
    );
    expect(events.map((event) => event.publishedAt), [
      DateTime.utc(2026, 10, 7, 18),
      DateTime.utc(2026, 10, 6, 12, 30),
      DateTime.utc(2026, 10, 23, 14, 10),
      DateTime.utc(2026, 10, 23, 19, 51, 9),
    ]);
    expect(events.first.isOfficial, isFalse);
    expect(events.first.sourceTier, NewsSourceTier.highQualityNews);
  });
}
