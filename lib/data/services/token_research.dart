import 'dart:convert';

import 'package:genkit/genkit.dart';
import 'package:schemantic/schemantic.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../repositories/asset_resolver.dart';
import '../../utils/symbol_utils.dart';

// Cache project context separately from live catalysts and price evidence.
class TokenResearch {
  TokenResearch({SharedPreferencesAsync? preferences, AssetResolver? assets})
    : _preferences = preferences ?? SharedPreferencesAsync(),
      _assets = assets ?? AssetResolver();

  final SharedPreferencesAsync _preferences;
  final AssetResolver _assets;
  String _key(String symbol) =>
      'decma.token_background.v1.${normalizeContractSymbol(symbol)}';

  Future<Map<String, dynamic>> context(
    String symbol, {
    required DateTime now,
    required bool searchAvailable,
  }) async {
    final profile = await _assets.resolve(symbol);
    Map<String, dynamic>? background;
    final saved = await _preferences.getString(_key(symbol));
    if (saved != null) {
      final data = jsonDecode(saved) as Map<String, dynamic>;
      final at = DateTime.parse(data['checked_at']);
      if (!at.isAfter(now) && now.difference(at) < const Duration(days: 7)) {
        background = data;
      }
    }
    final identity =
        '"${profile.projectName ?? profile.baseAsset}" '
        '"${profile.baseAsset}" crypto';
    final since = now.subtract(const Duration(hours: 72)).toUtc();
    final until = now.add(const Duration(days: 7)).toUtc();
    return {
      'identity': {
        'symbol': profile.symbol,
        'base_asset': profile.baseAsset,
        'project_name': profile.projectName,
        'aliases': profile.aliases,
        'official_domains': profile.officialDomains,
      },
      'as_of': now.toUtc().toIso8601String(),
      'search_available': searchAvailable,
      'background': background,
      'background_refresh_required': background == null,
      'recent_since': since.toIso8601String(),
      'upcoming_until': until.toIso8601String(),
      'search_queries': {
        if (background == null)
          'background':
              '$identity official documentation token utility value accrual',
        'recent_catalysts':
            '$identity (announcement OR upgrade OR unlock OR listing OR regulation OR exploit) '
            'after:${since.toIso8601String().substring(0, 10)}',
        // Upcoming events may have been announced before the recent-news window.
        'upcoming_catalysts':
            '$identity upcoming (unlock OR upgrade OR listing OR governance)',
      },
    };
  }

  // Source URLs must have successful page reads in this run, not just search hits.
  Tool cacheTool(
    String symbol,
    Set<String> fetchedUrls,
  ) => Tool<Map<String, dynamic>, Object?>(
    name: 'decma_cache_token_background',
    description:
        'Cache a concise identity-checked project background for this '
        'asset for seven days. Include sector, token utility and value-accrual '
        'mechanism (or explicitly unknown). Never include live catalysts, '
        'price predictions or instructions. Read the source pages with '
        'OpenWebSearch first; only those exact URLs can be saved.',
    inputSchema: SchemanticType.from(
      jsonSchema: const {
        'type': 'object',
        'properties': {
          'summary': {'type': 'string', 'minLength': 1, 'maxLength': 2000},
          'source_urls': {
            'type': 'array',
            'items': {'type': 'string'},
            'minItems': 1,
            'maxItems': 3,
          },
        },
        'required': ['summary', 'source_urls'],
        'additionalProperties': false,
      },
      parse: (value) => Map<String, dynamic>.from(value as Map),
    ),
    fn: (input, ctx) async {
      ctx.cancel?.throwIfCancelled();
      await save(
        symbol,
        summary: input['summary'] as String,
        sourceUrls: (input['source_urls'] as List).cast<String>(),
        fetchedUrls: fetchedUrls,
        now: DateTime.now().toUtc(),
      );
      return .response({'status': 'CACHED', 'symbol': symbol});
    },
  );

  Future<void> save(
    String symbol, {
    required String summary,
    required List<String> sourceUrls,
    required Set<String> fetchedUrls,
    required DateTime now,
  }) async {
    final sources = sourceUrls.toSet().toList();
    if (summary.trim().isEmpty ||
        summary.length > 2000 ||
        sources.isEmpty ||
        sources.length > 3 ||
        sources.any((url) => !fetchedUrls.contains(url))) {
      throw ArgumentError(
        'A concise background and successfully read source URLs are required.',
      );
    }
    await _preferences.setString(
      _key(symbol),
      jsonEncode({
        'summary': summary.trim(),
        'source_urls': sources,
        'checked_at': now.toUtc().toIso8601String(),
      }),
    );
  }
}
