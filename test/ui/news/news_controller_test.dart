import 'dart:async';

import 'package:decma/data/repositories/news_repository.dart';
import 'package:decma/data/repositories/asset_resolver.dart';
import 'package:decma/data/services/storage/event_store.dart';
import 'package:decma/data/services/storage/secure_key_store.dart';
import 'package:decma/domain/models/app_settings.dart';
import 'package:decma/domain/models/news_event.dart';
import 'package:decma/ui/news/news_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const settings = NewsSettings(
  useFinnhub: false,
  useMarketaux: true,
  useBls: false,
  useBea: false,
  useFederalReserve: false,
);

void main() {
  test(
    'switching assets rejects late news from the previous request',
    () async {
      final source = _News();
      final controller = NewsController(
        source,
        _Keys(),
        symbol: 'BTCUSDT',
        settings: settings,
      );
      addTearDown(controller.dispose);
      addTearDown(source.dispose);
      final first = controller.refreshToken('BTCUSDT');
      await Future<void>.delayed(Duration.zero);
      controller.selectSymbol('ETHUSDT');
      await Future<void>.delayed(Duration.zero);
      source.requests['ETHUSDT']!.complete([_event('ETH')]);
      await Future<void>.delayed(Duration.zero);
      source.requests['BTCUSDT']!.complete([_event('BTC')]);
      await first;
      expect(source.tokens['BTCUSDT']!.isCancelled, true);
      expect(controller.events.single.directAssets, ['ETH']);
    },
  );

  test(
    'disposing news cancels requests and suppresses late notifications',
    () async {
      final source = _News();
      final controller = NewsController(
        source,
        _Keys(),
        symbol: 'BTCUSDT',
        settings: settings,
      );
      addTearDown(source.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);
      final request = controller.refreshToken('BTCUSDT');
      await Future<void>.delayed(Duration.zero);
      controller.dispose();
      final before = notifications;
      source.requests['BTCUSDT']!.complete([_event('BTC')]);
      await request;
      expect(source.tokens['BTCUSDT']!.isCancelled, true);
      expect(notifications, before);
      expect(controller.events, isEmpty);
    },
  );
}

class _Keys extends SecureKeyStore {
  @override
  Future<String?> readMarketauxKey() async => 'test';
}

// Delay source results without making network or platform-storage requests.
class _News extends NewsRepository {
  _News()
    : super(store: EventStore.memory(), assetResolver: AssetResolver.memory());
  final requests = <String, Completer<List<NewsEvent>>>{};
  final tokens = <String, CancelToken?>{};
  @override
  Future<List<NewsEvent>> refreshTokenNews({
    required String symbol,
    required NewsSettings settings,
    required String? marketauxApiKey,
    void Function(bool)? onRefreshChanged,
    CancelToken? cancelToken,
    void Function(List<NewsEvent>)? onEvents,
  }) async {
    tokens[symbol] = cancelToken;
    onRefreshChanged?.call(true);
    try {
      final result =
          await (requests[symbol] = Completer<List<NewsEvent>>()).future;
      onEvents?.call(result);
      return result;
    } finally {
      onRefreshChanged?.call(false);
    }
  }
}

NewsEvent _event(String asset) => NewsEvent(
  eventId: asset,
  headline: '$asset update',
  provider: 'test',
  originalSource: 'test',
  sourceTier: NewsSourceTier.aggregator,
  category: NewsCategory.crypto,
  eventType: 'CRYPTO',
  scope: NewsScope.assetSpecific,
  importance: NewsImportance.low,
  assets: [asset],
  directAssets: [asset],
  indirectAssets: const [],
  country: null,
  publishedAt: DateTime.now().toUtc(),
  receivedAt: DateTime.now().toUtc(),
  verificationStatus: NewsVerificationStatus.unverified,
  isBreaking: false,
  isOfficial: false,
  sources: const [],
);
