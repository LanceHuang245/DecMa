import 'package:fluent_ui/fluent_ui.dart';
import '../../models/news_event.dart';
import '../../services/news/news_service.dart';
import '../../utils/display_formatters.dart';
import '../../utils/external_link.dart';

class NewsPanel extends StatefulWidget {
  const NewsPanel({
    super.key,
    required this.events,
    required this.providerStatuses,
    required this.onOpenSettings,
  });

  final List<NewsEvent> events;
  final Map<String, NewsProviderStatus> providerStatuses;
  final VoidCallback onOpenSettings;

  @override
  State<NewsPanel> createState() => _NewsPanelState();
}

class _NewsPanelState extends State<NewsPanel> {
  NewsCategory? _category;

  @override
  Widget build(BuildContext context) {
    final events = widget.events
        .where((event) => _category == null || event.category == _category)
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
                  textAlign: TextAlign.left,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                icon: const Icon(FluentIcons.settings),
                onPressed: widget.onOpenSettings,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              _filterButton(null, '全部'),
              _filterButton(NewsCategory.macro, '宏观'),
              _filterButton(NewsCategory.crypto, 'Crypto'),
              _filterButton(NewsCategory.regulation, '监管'),
              _filterButton(NewsCategory.exchange, '交易所'),
            ],
          ),
          const SizedBox(height: 8),
          _ProviderStatusLine(statuses: widget.providerStatuses),
          const SizedBox(height: 8),
          Expanded(
            // The panel owns its scroll view so the dashboard height stays fixed.
            child: events.isEmpty
                ? const Center(child: Text('暂无已缓存事件'))
                : ListView.separated(
                    itemCount: events.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) => _NewsItem(events[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filterButton(NewsCategory? category, String label) => ToggleButton(
    checked: _category == category,
    onChanged: (checked) {
      if (checked) setState(() => _category = category);
    },
    child: Text(label),
  );
}

class _ProviderStatusLine extends StatelessWidget {
  const _ProviderStatusLine({required this.statuses});

  final Map<String, NewsProviderStatus> statuses;

  @override
  Widget build(BuildContext context) {
    final text = statuses.values
        .map((status) => '${status.id}: ${_label(status.state)}')
        .join(' · ');
    return Text(
      text.isEmpty ? '数据源启动中…' : text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        color: FluentTheme.of(context).resources.textFillColorSecondary,
      ),
    );
  }

  String _label(NewsProviderState state) => switch (state) {
    NewsProviderState.active => 'Active',
    NewsProviderState.disabled => 'Disabled',
    NewsProviderState.error => 'Error',
    NewsProviderState.rateLimited => 'Rate limited',
  };
}

class _NewsItem extends StatelessWidget {
  const _NewsItem(this.event);

  final NewsEvent event;

  @override
  Widget build(BuildContext context) {
    final resources = FluentTheme.of(context).resources;
    final uri = _webUri(event.url);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 5,
          runSpacing: 3,
          children: [
            Text(
              formatLocalDateTime(event.publishedAt),
              style: const TextStyle(fontSize: 12),
            ),
            _badge(event.importance.label, _importanceColor(event.importance)),
            _badge(event.category.label, resources.textFillColorSecondary),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          event.headline,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.left,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          '${event.originalSource} · ${event.verificationStatus.label}',
          style: TextStyle(
            fontSize: 12,
            color: resources.textFillColorSecondary,
          ),
        ),
      ],
    );
    return Button(
      onPressed: uri == null ? null : () => openExternalLink(uri),
      style: const ButtonStyle(
        padding: WidgetStatePropertyAll(EdgeInsets.all(8)),
      ),
      // Fluent buttons center their child by default; news rows should align as a list.
      child: Align(alignment: Alignment.centerLeft, child: text),
    );
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .16),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(text, style: TextStyle(fontSize: 10, color: color)),
  );

  Color _importanceColor(NewsImportance importance) => switch (importance) {
    NewsImportance.critical => Colors.red,
    NewsImportance.high => Colors.orange,
    NewsImportance.medium => Colors.yellow,
    NewsImportance.low => Colors.grey,
  };

  // RSS feeds may expose an empty <link>; only send complete web URLs to the OS.
  Uri? _webUri(String? value) {
    final uri = value == null ? null : Uri.tryParse(value.trim());
    if (uri == null || uri.host.isEmpty) return null;
    return uri.scheme == 'https' || uri.scheme == 'http' ? uri : null;
  }
}
