import 'package:fluent_ui/fluent_ui.dart';

import '../../domain/models/news_event.dart';
import '../../data/repositories/news_repository.dart';
import '../../utils/display_formatters.dart';
import '../../l10n/generated/app_localizations.dart';

class NewsSourceStatus extends StatelessWidget {
  const NewsSourceStatus({super.key, required this.statuses});

  final Map<String, NewsProviderStatus> statuses;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final enabled = statuses.values.where(
      (s) => s.state != NewsProviderState.disabled,
    );
    final errors = enabled
        .where((s) => s.state != NewsProviderState.active)
        .length;
    final label = statuses.isEmpty
        ? loc.sourcesStarting
        : enabled.isEmpty
        ? loc.noNewsSources
        : errors > 0
        ? loc.sourcesUnavailable(errors)
        : loc.sourcesAvailable(enabled.length);
    // Failed attempts must not appear as successful news updates.
    final updates =
        enabled
            .where((s) => s.state == NewsProviderState.active)
            .map((s) => s.updatedAt)
            .whereType<DateTime>()
            .toList()
          ..sort((a, b) => b.compareTo(a));
    final updatedAt = updates.firstOrNull;
    return DefaultTextStyle.merge(
      style: TextStyle(
        fontSize: 12,
        color: FluentTheme.of(context).resources.textFillColorSecondary,
      ),
      child: Row(
        children: [
          // Keep provider diagnostics accessible without status badges.
          Expanded(
            child: Tooltip(
              message: statuses.values
                  .map(
                    (status) =>
                        '${status.id}：${_label(loc, status.state)}${status.message == null ? '' : '\n${status.message}'}',
                  )
                  .join('\n'),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: updatedAt == null
                ? loc.noSuccessfulUpdate
                : loc.lastSuccessfulUpdate(formatLocalDateTime(updatedAt)),
            child: Text(
              updatedAt == null
                  ? loc.updatedAtNone
                  : loc.updatedAt(formatLocalTime(updatedAt)),
            ),
          ),
        ],
      ),
    );
  }

  String _label(AppLocalizations loc, NewsProviderState state) =>
      switch (state) {
        NewsProviderState.active => loc.providerActive,
        NewsProviderState.disabled => loc.providerDisabled,
        NewsProviderState.error => loc.providerError,
        NewsProviderState.rateLimited => loc.providerRateLimited,
      };
}
