import 'package:fluent_ui/fluent_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../domain/models/news_event.dart';
import '../../data/repositories/news_repository.dart';
import '../../utils/display_formatters.dart';
import '../../utils/symbol_utils.dart';
import 'news_source_status.dart';
import '../../l10n/generated/app_localizations.dart';

enum _NewsView { all, currentAsset, macro, crypto, regulation, exchange }

class NewsPanel extends StatefulWidget {
  const NewsPanel({
    super.key,
    required this.events,
    required this.currentSymbol,
    required this.providerStatuses,
    required this.isRefreshing,
  });

  final List<NewsEvent> events;
  final String currentSymbol;
  final Map<String, NewsProviderStatus> providerStatuses;
  final bool isRefreshing;

  @override
  State<NewsPanel> createState() => _NewsPanelState();
}

class _NewsPanelState extends State<NewsPanel> {
  _NewsView _view = _NewsView.all;
  String _provider = '';

  @override
  void didUpdateWidget(covariant NewsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A disappearing source must not leave an invalid dropdown selection.
    if (!widget.events.any((event) => event.provider == _provider)) {
      _provider = '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final resources = FluentTheme.of(context).resources;
    final providers =
        widget.events.map((event) => event.provider).toSet().toList()..sort();
    final currentAsset = baseAssetFromSymbol(widget.currentSymbol);
    final labels = [
      loc.newsAll,
      loc.newsRelated(currentAsset),
      loc.categoryMacro,
      loc.newsCryptoMarket,
      loc.categoryRegulation,
      loc.categoryExchange,
    ];
    final events = widget.events
        .where(
          (event) =>
              _matchesView(event, currentAsset) &&
              (_provider.isEmpty || event.provider == _provider),
        )
        .toList();
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Market News',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              if (widget.isRefreshing)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Tooltip(
                    message: loc.updatingNews,
                    child: const SizedBox(
                      width: 14,
                      height: 14,
                      child: ProgressRing(),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Native selectors leave the narrow column available for headlines.
          Row(
            children: [
              Expanded(
                child: ComboBox<_NewsView>(
                  value: _view,
                  isExpanded: true,
                  items: [
                    for (final view in _NewsView.values)
                      ComboBoxItem(
                        value: view,
                        child: Text(
                          labels[view.index],
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _view = value ?? _NewsView.all),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ComboBox<String>(
                  value: _provider,
                  isExpanded: true,
                  items: [
                    ComboBoxItem(value: '', child: Text(loc.allSources)),
                    for (final provider in providers)
                      ComboBoxItem(
                        value: provider,
                        child: Text(provider, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (value) => setState(() => _provider = value ?? ''),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            // The panel owns its scroll view so the dashboard height stays fixed.
            child: events.isEmpty
                ? Center(
                    child: Text(
                      widget.isRefreshing
                          ? loc.fetchingNews
                          : loc.noRelatedNews,
                      style: TextStyle(color: resources.textFillColorSecondary),
                    ),
                  )
                : ListView.separated(
                    itemCount: events.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, index) => _NewsItem(events[index]),
                  ),
          ),
          const SizedBox(height: 8),
          NewsSourceStatus(statuses: widget.providerStatuses),
        ],
      ),
    );
  }

  bool _matchesView(NewsEvent event, String currentAsset) => switch (_view) {
    _NewsView.all => true,
    _NewsView.currentAsset => event.directAssets.contains(currentAsset),
    _NewsView.macro => event.category == NewsCategory.macro,
    _NewsView.crypto => event.category == NewsCategory.crypto,
    _NewsView.regulation => event.category == NewsCategory.regulation,
    _NewsView.exchange => event.category == NewsCategory.exchange,
  };
}

class _NewsItem extends StatelessWidget {
  const _NewsItem(this.event);

  final NewsEvent event;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final resources = FluentTheme.of(context).resources;
    final uri = _webUri(event.url);
    // Truncate by visible characters so names cannot crowd out the timestamp.
    final source = event.originalSource.characters;
    final sourceLabel = source.length > 8
        ? '${source.take(8)}...'
        : event.originalSource;
    final verification = switch (event.verificationStatus) {
      NewsVerificationStatus.unverified => loc.verifyUnverified,
      NewsVerificationStatus.secondaryConfirmed => loc.verifySecondary,
      NewsVerificationStatus.primarySourceConfirmed => loc.verifyPrimary,
      NewsVerificationStatus.conflicted => loc.verifyConflicted,
    };
    final (importance, importanceColor) = switch (event.importance) {
      NewsImportance.critical => (loc.importanceCritical, Colors.red),
      NewsImportance.high => (loc.importanceHigh, Colors.orange),
      NewsImportance.medium => (loc.importanceMedium, Colors.yellow),
      NewsImportance.low => (loc.importanceLow, resources.textFillColorPrimary),
    };
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          event.headline,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.left,
          style: TextStyle(
            fontSize: 14,
            height: 1.45,
            fontWeight: FontWeight.w600,
            color: resources.textFillColorPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$sourceLabel · ${formatLocalDate(event.publishedAt)} ${formatLocalTime(event.publishedAt)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            height: 1.4,
            color: resources.textFillColorSecondary,
          ),
        ),
        const SizedBox(height: 6),
        // Show every importance level beside verification, below the metadata.
        Wrap(
          spacing: 5,
          runSpacing: 3,
          children: [
            _badge(importance, importanceColor),
            _badge(verification, resources.textFillColorSecondary),
          ],
        ),
      ],
    );
    return Tooltip(
      message:
          '${event.headline}\n${event.originalSource} · ${event.category.label} · ${event.provider} · $verification\n${formatLocalDateTime(event.publishedAt)}',
      child: Button(
        onPressed: uri == null
            ? null
            : () => launchUrl(uri, mode: LaunchMode.externalApplication),
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          ),
          shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.isHovered || states.isPressed
                ? resources.subtleFillColorSecondary
                : Colors.transparent,
          ),
        ),
        // Fluent buttons center their child by default; news rows should align as a list.
        child: Align(alignment: Alignment.centerLeft, child: text),
      ),
    );
  }

  // Match the original compact rectangular news badges.
  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .16),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(label, style: TextStyle(fontSize: 10, color: color)),
  );

  // RSS feeds may expose an empty <link>; only send complete web URLs to the OS.
  Uri? _webUri(String? value) {
    final uri = value == null ? null : Uri.tryParse(value.trim());
    if (uri == null || uri.host.isEmpty) return null;
    return uri.scheme == 'https' || uri.scheme == 'http' ? uri : null;
  }
}
