import 'package:decma/domain/models/candle.dart';
import 'package:decma/data/services/bybit_service.dart';
import '../../fixtures/dashboard_agent_fixtures.dart';
import 'package:decma/providers/app_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  // Leaving/remounting the page recreates UI state but keeps shared services alive.
  test(
    'Provider scope recreates the dashboard without disposing shared services',
    () async {
      final bybit = _HistoryBybit();
      final container = ProviderContainer(
        overrides: [
          appInitialSettingsProvider.overrideWithValue(
            const AppInitialSettings(nodeAvailable: false),
          ),
          bybitServiceProvider.overrideWith((ref) {
            ref.onDispose(bybit.dispose);
            return bybit;
          }),
        ],
      );
      try {
        final first = container.listen(dashboardControllerProvider, (_, _) {});
        final original = first.read();
        original.promptController.text = 'Old draft';
        first.close();
        await container.pump();
        expect(bybit.disposals, 0);
        final next = container.listen(dashboardControllerProvider, (_, _) {});
        expect(identical(next.read(), original), false);
        next.read().promptController.text = 'New draft';
        expect(next.read().promptController.text, 'New draft');
        next.close();
        await container.pump();
        expect(bybit.disposals, 0);
      } finally {
        container.dispose();
      }
      expect(bybit.disposals, 1);
    },
  );

  // A successful page must release the loading flag so another page can load.
  test(
    'successful historical pagination remains usable for a second page',
    () async {
      final bybit = _HistoryBybit();
      final controller = createDashboard(
        nodeAvailable: false,
        bybit: bybit,
      );
      controller.selectSymbol('ETHUSDT');
      await _flush();
      try {
        await controller.loadMoreHistory();
        expect(controller.loadingMore, false);
        await controller.loadMoreHistory();
        expect(bybit.pages, 2);
        expect(controller.candles, hasLength(2010));
      } finally {
        controller.dispose();
        bybit.dispose();
      }
    },
  );

  // Injected services belong to their Provider/caller rather than the dashboard.
  test('disposing a dashboard does not dispose a borrowed Bybit service', () {
    final bybit = _HistoryBybit();
    final controller = createDashboard(nodeAvailable: false, bybit: bybit);
    controller.dispose();
    expect(bybit.disposals, 0);
    bybit.dispose();
    expect(bybit.disposals, 1);
  });
}

// Replace exchange I/O with ordered pages while exercising real chart state.
class _HistoryBybit extends BybitService {
  int pages = 0;
  int disposals = 0;
  @override
  Future<List<Candle>> fetchKlines({
    required String symbol,
    required String interval,
    int limit = 160,
    int? start,
    int? end,
    CancelToken? cancelToken,
  }) async {
    if (end != null) pages++;
    final count = end == null ? 10 : 1000;
    final last = end ?? DateTime.utc(2026, 1, 1).millisecondsSinceEpoch;
    return List.generate(
      count,
      (i) => Candle(
        time: DateTime.fromMillisecondsSinceEpoch(
          last - (count - 1 - i) * 900000,
          isUtc: true,
        ),
        open: 100,
        high: 101,
        low: 99,
        close: 100,
        volume: 1,
      ),
    );
  }

  @override
  void dispose() {
    disposals++;
    super.dispose();
  }
}

Future<void> _flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
