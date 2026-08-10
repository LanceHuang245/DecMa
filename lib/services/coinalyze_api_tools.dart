import 'dart:convert';

import 'package:dio/dio.dart';

import 'mcp_types.dart';
import '../utils/network.dart';

class CoinalyzeApiTools {
  CoinalyzeApiTools({Dio? dio}) : _dio = dio ?? createDio();

  static const _baseUrl = 'api.coinalyze.net';
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
  static const _toolEndpoints = {
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
  static const _tools = [
    McpTool(
      functionName: 'Coinalyze_API_getFutureMarkets',
      serverName: 'Coinalyze API',
      name: 'getFutureMarkets',
      description:
          'Get supported futures markets and their exact Coinalyze symbols. Use this to resolve a market before querying the data tools.',
      inputSchema: {
        'type': 'object',
        'properties': {},
        'additionalProperties': false,
      },
    ),
    McpTool(
      functionName: 'Coinalyze_API_getOpenInterest',
      serverName: 'Coinalyze API',
      name: 'getOpenInterest',
      description: 'Get current futures open interest from Coinalyze.',
      inputSchema: {
        'type': 'object',
        'properties': {
          ..._symbolProperties,
          'convert_to_usd': {'type': 'boolean'},
        },
        'required': ['symbols'],
        'additionalProperties': false,
      },
    ),
    McpTool(
      functionName: 'Coinalyze_API_getOpenInterestHistory',
      serverName: 'Coinalyze API',
      name: 'getOpenInterestHistory',
      description: 'Get historical futures open interest from Coinalyze.',
      inputSchema: {
        'type': 'object',
        'properties': {
          ..._historyProperties,
          'convert_to_usd': {'type': 'boolean'},
        },
        'required': ['symbols', 'interval', 'from', 'to'],
        'additionalProperties': false,
      },
    ),
    McpTool(
      functionName: 'Coinalyze_API_getFunding',
      serverName: 'Coinalyze API',
      name: 'getFunding',
      description: 'Get current futures funding rates from Coinalyze.',
      inputSchema: {
        'type': 'object',
        'properties': _symbolProperties,
        'required': ['symbols'],
        'additionalProperties': false,
      },
    ),
    McpTool(
      functionName: 'Coinalyze_API_getFundingHistory',
      serverName: 'Coinalyze API',
      name: 'getFundingHistory',
      description: 'Get historical futures funding rates from Coinalyze.',
      inputSchema: {
        'type': 'object',
        'properties': _historyProperties,
        'required': ['symbols', 'interval', 'from', 'to'],
        'additionalProperties': false,
      },
    ),
    McpTool(
      functionName: 'Coinalyze_API_getPredictedFunding',
      serverName: 'Coinalyze API',
      name: 'getPredictedFunding',
      description:
          'Get current predicted futures funding rates from Coinalyze.',
      inputSchema: {
        'type': 'object',
        'properties': _symbolProperties,
        'required': ['symbols'],
        'additionalProperties': false,
      },
    ),
    McpTool(
      functionName: 'Coinalyze_API_getLiquidationHistory',
      serverName: 'Coinalyze API',
      name: 'getLiquidationHistory',
      description: 'Get historical long and short liquidations from Coinalyze.',
      inputSchema: {
        'type': 'object',
        'properties': {
          ..._historyProperties,
          'convert_to_usd': {'type': 'boolean'},
        },
        'required': ['symbols', 'interval', 'from', 'to'],
        'additionalProperties': false,
      },
    ),
    McpTool(
      functionName: 'Coinalyze_API_getLongShortRatioHistory',
      serverName: 'Coinalyze API',
      name: 'getLongShortRatioHistory',
      description: 'Get historical long/short ratios from Coinalyze.',
      inputSchema: {
        'type': 'object',
        'properties': _historyProperties,
        'required': ['symbols', 'interval', 'from', 'to'],
        'additionalProperties': false,
      },
    ),
    McpTool(
      functionName: 'Coinalyze_API_getOhlcvHistory',
      serverName: 'Coinalyze API',
      name: 'getOhlcvHistory',
      description: 'Get historical OHLCV data from Coinalyze.',
      inputSchema: {
        'type': 'object',
        'properties': _historyProperties,
        'required': ['symbols', 'interval', 'from', 'to'],
        'additionalProperties': false,
      },
    ),
  ];

  final Dio _dio;
  final List<String> warnings = [];
  final List<DateTime> _quotaUnits = [];
  String? _apiKey;

  List<McpTool> configure({required bool enabled, String? apiKey}) {
    warnings.clear();
    _apiKey = enabled && apiKey != null && apiKey.isNotEmpty ? apiKey : null;
    if (enabled && _apiKey == null) {
      warnings.add('Coinalyze API: API Key 未配置。');
    }
    return _apiKey == null ? const [] : _tools;
  }

  bool supports(String functionName) =>
      _toolEndpoints.containsKey(functionName);

  Future<String> call(
    String functionName,
    Map<String, dynamic> arguments,
  ) async {
    final apiKey = _apiKey;
    final endpoint = _toolEndpoints[functionName];
    if (apiKey == null || endpoint == null) {
      throw StateError('Coinalyze API tool is unavailable.');
    }
    final required = endpoint == 'future-markets'
        ? const <String>[]
        : functionName.endsWith('History')
        ? const ['symbols', 'interval', 'from', 'to']
        : const ['symbols'];
    for (final field in required) {
      if (arguments[field]?.toString().trim().isEmpty ?? true) {
        throw ArgumentError('Coinalyze API requires "$field".');
      }
    }
    _reserveQuota(arguments);
    final query = <String, String>{
      for (final entry in arguments.entries)
        if (entry.value != null) entry.key: entry.value.toString(),
    };
    final response = await runNetworkRequest(
      'Coinalyze API',
      () => _dio.getUri<String>(
        Uri.https(_baseUrl, '/v1/$endpoint', query),
        options: networkOptions(
          headers: {'Accept': 'application/json', 'api_key': apiKey},
        ),
      ),
    );
    requireSuccessfulResponse(response, provider: 'Coinalyze API');
    try {
      return jsonEncode({
        'source': 'Coinalyze API',
        'endpoint': endpoint,
        'data': jsonDecode(response.data ?? ''),
      });
    } on FormatException {
      throw const AppFailure(
        kind: AppFailureKind.invalidResponse,
        provider: 'Coinalyze API',
      );
    }
  }

  // Enforce Coinalyze's rolling quota, where every requested symbol is one unit.
  void _reserveQuota(Map<String, dynamic> arguments) {
    final now = DateTime.now().toUtc();
    _quotaUnits.removeWhere(
      (timestamp) => now.difference(timestamp) >= const Duration(minutes: 1),
    );
    final symbols = arguments['symbols']
        ?.toString()
        .split(',')
        .where((symbol) => symbol.trim().isNotEmpty)
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

  void dispose() => _dio.close(force: true);
}
