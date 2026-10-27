import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:genkit/genkit.dart';

import '../../utils/network.dart';
import '../../l10n/app_languages.dart';

// Observe native Genkit tools without a second dispatch loop or tool DTOs.
class AgentTools extends GenerateMiddleware {
  AgentTools({this.onActivity});
  final void Function(String)? onActivity;
  final attemptedSources = <String>{};
  final completedSources = <String>{};
  final fetchedWebUrls = <String>{};
  final _evidence = <String, List<Map<String, String>>>{};
  final _evidenceChars = <String, int>{};
  List<Map<String, String>> get evidence =>
      _evidence.values.expand((items) => items).toList();

  // Keep remote failures model-visible while propagating cancellation unchanged.
  @override
  Future<ToolResult> tool(
    ToolRequestPart request,
    ActionFnArg<void, dynamic, void> ctx,
    Future<ToolResult> Function(
      ToolRequestPart,
      ActionFnArg<void, dynamic, void>,
    )
    next,
  ) async {
    final name = request.toolRequest.name;
    final arguments = Map<String, dynamic>.from(
      request.toolRequest.input as Map,
    );
    final resolved = name == 'decma_call_mcp_tool'
        ? arguments['tool_name'] as String
        : name;
    onActivity?.call(_activity(resolved));
    ToolResult result;
    try {
      result = await cancellable(next(request, ctx), ctx.cancel?.whenCancelled);
    } catch (error, stackTrace) {
      ctx.cancel?.throwIfCancelled();
      if (isRequestCancelled(error)) rethrow;
      // Diagnose tool failures without logging request arguments or page content.
      if (kDebugMode) {
        debugPrint('[AgentTools] $resolved failed: $error\n$stackTrace');
      }
      onActivity?.call(appL10n.activityFailed(_activity(resolved)));
      result = ToolResult.response('Tool failed: $error');
    }
    ctx.cancel?.throwIfCancelled();
    if (result is! ToolResponseResult) return result;
    _track(resolved, arguments, result.output);
    final text = result.output is String
        ? result.output as String
        : jsonEncode(result.output);
    if (text.length <= 24000) return result;
    return ToolResult.response(
      '${text.substring(0, 24000)}\n[truncated]',
      parts: result.parts,
      metadata: result.metadata,
    );
  }

  // Classify raw output before truncation so large errors never count as evidence.
  void _track(String name, Map<String, dynamic> arguments, Object? output) {
    // Search snippets cannot authorize a reusable project-background cache.
    if (name.startsWith('OpenWebSearch_MCP_') &&
        name.toLowerCase().contains('fetch') &&
        _successful(name, output)) {
      final input = arguments['arguments'] as Map? ?? arguments;
      fetchedWebUrls.add(input['url']);
    }
    final source = _source(name);
    if (source == null) return;
    attemptedSources.add(source);
    if (!_successful(name, output)) return;
    completedSources.add(source);
    final encoded = jsonEncode(arguments);
    final args = encoded.length <= 2000
        ? encoded
        : '${encoded.substring(0, 2000)}\n[truncated]';
    final used = _evidenceChars[source] ?? 0;
    final remaining = 16000 - used - args.length;
    if (remaining <= 0) return;
    final raw = output is String ? output : jsonEncode(output);
    final text = raw.length <= remaining
        ? raw
        : '${raw.substring(0, remaining)}\n[truncated]';
    (_evidence[source] ??= []).add({
      'source': source,
      'tool': name,
      'arguments': args,
      'output': text,
    });
    _evidenceChars[source] = used + args.length + text.length;
  }

  // Resolve bridge sources without counting discovery/documentation as data.
  String? _source(String name) {
    if (const [
      'capabilit',
      'documentation',
      'schema',
      'supported_chains',
      'supported_networks',
    ].any(name.toLowerCase().contains)) {
      return null;
    }
    if (name.startsWith('Bybit_MCP_')) return 'Bybit MCP';
    if (name.startsWith('Nansen_MCP_')) return 'Nansen MCP';
    if (name == 'Coinalyze_API_getFutureMarkets') return null;
    if (name.startsWith('Coinalyze_API_')) return 'Coinalyze API';
    if (name.startsWith('OpenWebSearch_MCP_')) return 'OpenWebSearch MCP';
    return null;
  }

  String _activity(String name) {
    if (name == 'decma_cache_token_background') {
      return appL10n.activityTokenBackground;
    }
    if (name == 'decma_discover_mcp_tools') {
      return appL10n.activityDiscoverTools;
    }
    for (final kind in ['MCP', 'API']) {
      final marker = name.indexOf('_${kind}_');
      if (marker > 0) {
        return '• ${name.substring(0, marker)} $kind - ${name.substring(marker + kind.length + 2)}';
      }
    }
    return '• MCP - $name';
  }

  // Preserve structured MCP/Coinalyze validity rules and ordinary text results.
  bool _successful(String name, Object? output) {
    if (output is String) {
      if (output.trim().isEmpty || output.startsWith('Tool failed:')) {
        return false;
      }
      try {
        output = jsonDecode(output);
      } on FormatException {
        return true;
      }
    }
    if (output is Map) {
      if (output['isError'] == true) return false;
      if (name.startsWith('Coinalyze_API_')) return _hasPayload(output['data']);
      return _hasPayload(output['content']) ||
          _hasPayload(output['structuredContent']);
    }
    return _hasPayload(output);
  }

  bool _hasPayload(Object? value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is List) return value.any(_hasPayload);
    if (value is Map) {
      if (value.containsKey('text')) return _hasPayload(value['text']);
      if (value.containsKey('data')) return _hasPayload(value['data']);
      return value.entries
          .where((entry) => entry.key != 'type')
          .any((entry) => _hasPayload(entry.value));
    }
    return true;
  }
}
