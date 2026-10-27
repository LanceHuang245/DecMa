// Keep server-advertised capabilities alongside each model identifier.
class LlmModelInfo {
  const LlmModelInfo(this.id, {this.reasoningEfforts});

  final String id;
  // Null means unspecified; an empty list explicitly advertises no choices.
  final List<String>? reasoningEfforts;

  // Codex lists `supported_reasoning_levels`; Anthropic lists `capabilities.effort`.
  factory LlmModelInfo.fromJson(Map<String, dynamic> value) {
    final List? levels = value['supported_reasoning_levels'];
    final Map? effort = value['capabilities']?['effort'];
    return LlmModelInfo(
      value['slug'] ?? value['id'],
      reasoningEfforts: levels != null
          ? [for (final level in levels) level['effort']]
          : effort != null && effort['supported']
          ? [
              for (final entry in effort.entries)
                if (entry.value is Map && entry.value['supported']) entry.key,
            ]
          : null,
    );
  }
}
