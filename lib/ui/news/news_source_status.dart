import 'package:fluent_ui/fluent_ui.dart';

import '../../domain/models/news_event.dart';
import '../../data/repositories/news_repository.dart';
import '../../utils/display_formatters.dart';
import '../../l10n/generated/app_localizations.dart';

class NewsSourceStatus extends StatefulWidget {
  const NewsSourceStatus({super.key, required this.statuses});

  final Map<String, NewsProviderStatus> statuses;

  @override
  State<NewsSourceStatus> createState() => _NewsSourceStatusState();
}

class _NewsSourceStatusState extends State<NewsSourceStatus> {
  final _flyout = FlyoutController();

  Map<String, NewsProviderStatus> get statuses => widget.statuses;

  @override
  void dispose() {
    _flyout.dispose();
    super.dispose();
  }

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
          // Hovering the summary opens a flyout listing every provider's state.
          Expanded(
            child: FlyoutTarget(
              controller: _flyout,
              child: MouseRegion(
                onEnter: (_) => _flyout.showFlyout(
                  dismissOnPointerMoveAway: true,
                  placementMode: FlyoutPlacementMode.topLeft,
                  builder: (context) => FlyoutContent(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final status in statuses.values)
                          _ProviderRow(
                            status: status,
                            label: _label(loc, status.state),
                          ),
                      ],
                    ),
                  ),
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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

// One provider: state icon, name and state, with the failure message underneath.
class _ProviderRow extends StatelessWidget {
  const _ProviderRow({required this.status, required this.label});

  final NewsProviderStatus status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final resources = FluentTheme.of(context).resources;
    final (icon, color) = switch (status.state) {
      NewsProviderState.active => (
        FluentIcons.completed_solid,
        Colors.successPrimaryColor,
      ),
      NewsProviderState.disabled => (
        FluentIcons.circle_ring,
        resources.textFillColorDisabled,
      ),
      NewsProviderState.rateLimited => (
        FluentIcons.warning,
        Colors.warningPrimaryColor,
      ),
      NewsProviderState.error => (
        FluentIcons.error_badge,
        Colors.errorPrimaryColor,
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(icon, size: 12, color: color),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${status.id} · $label'),
              if (status.message case final message?)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(
                    message,
                    style: TextStyle(
                      fontSize: 12,
                      color: resources.textFillColorSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
