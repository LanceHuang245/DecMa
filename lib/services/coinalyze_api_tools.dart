import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:genkit/genkit.dart';
import 'package:schemantic/schemantic.dart';

import '../utils/network.dart';

// Expose in-process API operations as native Genkit tools, not MCP descriptors.
class CoinalyzeApiTools {
  CoinalyzeApiTools({Dio? dio})
    : _dio = dio ?? createDio(),
      _ownsDio = dio == null;
  final Dio _dio;
  final bool _ownsDio;
  final List<String> warnings = [];
  final List<DateTime> _quotaUnits = [];
  String? _apiKey;
  static const _intervals = [
    '1min',
    '5min',
    '15min',
    '30min',
    '1hour',
    '2hour',
    '4hour',
    '6hour',
    '12hour',
    'daily',
  ];
  static const _symbolProperties = {
    'symbols': {
      'type': 'string',
      'description':
          'Comma-separated Coinalyze future-market symbols, maximum 20. Each market consumes one request from the 40 calls/minute API-key quota.',
    },
  };
  static const _historyProperties = {
    ..._symbolProperties,
    'interval': {'type': 'string', 'enum': _intervals},
    'from': {
      'type': 'integer',
      'description': 'Inclusive Unix timestamp in seconds.',
    },
    'to': {
      'type': 'integer',
      'description': 'Inclusive Unix timestamp in seconds.',
    },
  };
  static const _endpoints = {
    'Coinalyze_API_getFutureMarkets': 'future-markets',
    'Coinalyze_API_getOpenInterest': 'open-interest',
    'Coinalyze_API_getOpenInterestHistory': 'open-interest-history',
    'Coinalyze_API_getFunding': 'funding-rate',
    'Coinalyze_API_getFundingHistory': 'funding-rate-history',
    'Coinalyze_API_getPredictedFunding': 'predicted-funding-rate',
    'Coinalyze_API_getLiquidationHistory': 'liquidation-history',
    'Coinalyze_API_getLongShortRatioHistory': 'long-short-ratio-history',
    'Coinalyze_API_getOhlcvHistory': 'ohlcv-history',
  };

  // Reuse common schema fields while retaining the existing names and descriptions.
  static final _definitions = [
    ToolDefinition(
      name: 'Coinalyze_API_getFutureMarkets',
      description:
          'Get supported futures markets and their exact Coinalyze symbols. Use this to resolve a market before querying the data tools.',
      inputSchema: {
        'type': 'object',
        // Anthropic's SDK requires string-keyed maps even for no-argument tools.
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    ),
    for (final entry in const {
      'Coinalyze_API_getOpenInterest':
          'Get current futures open interest from Coinalyze.',
      'Coinalyze_API_getFunding':
          'Get current futures funding rates from Coinalyze.',
      'Coinalyze_API_getPredictedFunding':
          'Get current predicted futures funding rates from Coinalyze.',
    }.entries)
      ToolDefinition(
        name: entry.key,
        description: entry.value,
        inputSchema: {
          'type': 'object',
          'properties': {
            ..._symbolProperties,
            if (entry.key.endsWith('Interest'))
              'convert_to_usd': {'type': 'boolean'},
          },
          'required': ['symbols'],
          'additionalProperties': false,
        },
      ),
    for (final entry in const {
      'Coinalyze_API_getOpenInterestHistory':
          'Get historical futures open interest from Coinalyze.',
      'Coinalyze_API_getFundingHistory':
          'Get historical futures funding rates from Coinalyze.',
      'Coinalyze_API_getLiquidationHistory':
          'Get historical futures liquidations from Coinalyze.',
      'Coinalyze_API_getLongShortRatioHistory':
          'Get historical futures long/short ratios from Coinalyze.',
      'Coinalyze_API_getOhlcvHistory':
          'Get historical futures OHLCV data from Coinalyze.',
    }.entries)
      ToolDefinition(
        name: entry.key,
        description: entry.value,
        inputSchema: {
          'type': 'object',
          'properties': {
            ..._historyProperties,
            if (entry.key.endsWith('InterestHistory'))
              'convert_to_usd': {'type': 'boolean'},
          },
          'required': ['symbols', 'interval', 'from', 'to'],
          'additionalProperties': false,
        },
      ),
  ];

  // Bind cancellation from the actual Genkit tool invocation to its Dio request.
  List<Tool> configure({required bool enabled, String? apiKey}) {
    warnings.clear();
    _apiKey = enabled && apiKey?.isNotEmpty == true ? apiKey : null;
    if (enabled && _apiKey == null) warnings.add('Coinalyze API: API Key 未配置。');
    if (_apiKey == null) return const [];
    return [
      for (final definition in _definitions)
        Tool<Map<String, dynamic>, Object?>(
          name: definition.name,
          description: '[Coinalyze API] ${definition.description}',
          inputSchema: SchemanticType.from(
            jsonSchema: definition.inputSchema!,
            parse: (value) => Map<String, dynamic>.from(value as Map),
          ),
          fn: (arguments, ctx) async {
            final cancel = CancelToken();
            final unlink = ctx.cancel?.onCancel(() => cancel.cancel());
            try {
              return .response(
                await call(definition.name, arguments, cancelToken: cancel),
              );
            } finally {
              unlink?.call();
            }
          },
        ),
    ];
  }

  // Return raw structured results so evidence validation happens before truncation.
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> arguments, {
    CancelToken? cancelToken,
  }) async {
    final endpoint = _endpoints[name];
    if (_apiKey == null || endpoint == null) {
      throw StateError('Coinalyze API tool is unavailable.');
    }
    final required = endpoint == 'future-markets'
        ? const <String>[]
        : name.endsWith('History')
        ? const ['symbols', 'interval', 'from', 'to']
        : const ['symbols'];
    for (final field in required) {
      if (arguments[field]?.toString().trim().isEmpty ?? true) {
        throw ArgumentError('Coinalyze API requires "$field".');
      }
    }
    _reserveQuota(arguments);
    final response = await runNetworkRequest(
      'Coinalyze API',
      () => _dio.getUri<String>(
        Uri.https('api.coinalyze.net', '/v1/$endpoint', {
          for (final entry in arguments.entries)
            if (entry.value != null) entry.key: entry.value.toString(),
        }),
        cancelToken: cancelToken,
        options: networkOptions(
          headers: {'Accept': 'application/json', 'api_key': _apiKey},
        ),
      ),
    );
    requireSuccessfulResponse(response, provider: 'Coinalyze API');
    try {
      return {
        'source': 'Coinalyze API',
        'endpoint': endpoint,
        'data': jsonDecode(response.data ?? ''),
      };
    } on FormatException {
      throw const AppFailure(
        kind: AppFailureKind.invalidResponse,
        provider: 'Coinalyze API',
      );
    }
  }

  // Keep the existing rolling quota where each requested symbol consumes one unit.
  void _reserveQuota(Map<String, dynamic> arguments) {
    final now = DateTime.now().toUtc();
    _quotaUnits.removeWhere(
      (time) => now.difference(time) >= const Duration(minutes: 1),
    );
    final symbols = arguments['symbols']
        ?.toString()
        .split(',')
        .where((s) => s.trim().isNotEmpty)
        .length;
    final units = symbols == null || symbols == 0 ? 1 : symbols;
    if (_quotaUnits.length + units > 40) {
      throw StateError(
        'Coinalyze API local quota guard: 40 calls/minute would be exceeded.',
      );
    }
    _quotaUnits.addAll(List.filled(units, now));
  }

  void clear() => _apiKey = null;
  void dispose() {
    if (_ownsDio) _dio.close(force: true);
  }
}
