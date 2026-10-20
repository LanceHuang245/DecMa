// Keep server-advertised capabilities alongside each model identifier.
class LlmModelInfo {
  const LlmModelInfo(this.id, {this.reasoningEfforts});

  final String id;
  // Null means unspecified; an empty list explicitly advertises no choices.
  final List<String>? reasoningEfforts;

  factory LlmModelInfo.fromJson(Map value) {
    final efforts = <String>{};
    final levels = value['supported_reasoning_levels'];
    if (levels is List) {
      for (final level in levels.whereType<Map>()) {
        if (level['effort'] case final String effort) efforts.add(effort);
      }
    }
    final capabilities = value['capabilities'];
    final effort = capabilities is Map ? capabilities['effort'] : null;
    if (effort is Map && effort['supported'] != false) {
      for (final entry in effort.entries) {
        if (entry.value is Map && entry.value['supported'] == true) {
          efforts.add(entry.key as String);
        }
      }
    }
    return LlmModelInfo(
      (value['slug'] ?? value['id'] ?? value['model']) as String,
      reasoningEfforts: levels is List || effort is Map
          ? efforts.toList()
          : null,
    );
  }
}
