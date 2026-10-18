import 'package:fluent_ui/fluent_ui.dart';

import '../../domain/models/news_event.dart';
import '../../data/repositories/news_repository.dart';
import '../../utils/display_formatters.dart';

class NewsSourceStatus extends StatelessWidget {
  const NewsSourceStatus({super.key, required this.statuses});

  final Map<String, NewsProviderStatus> statuses;

  @override
  Widget build(BuildContext context) {
    final enabled = statuses.values.where(
      (s) => s.state != NewsProviderState.disabled,
    );
    final errors = enabled
        .where((s) => s.state != NewsProviderState.active)
        .length;
    final label = statuses.isEmpty
        ? '数据源启动中…'
        : enabled.isEmpty
        ? '未启用新闻源'
        : errors > 0
        ? '$errors 个来源暂不可用'
        : '${enabled.length} 个来源可用';
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
                        '${status.id}：${_label(status.state)}${status.message == null ? '' : '\n${status.message}'}',
                  )
                  .join('\n'),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: updatedAt == null
                ? '暂无成功更新时间'
                : '最近成功更新：${formatLocalDateTime(updatedAt)}',
            child: Text(
              updatedAt == null ? '更新于 —' : '更新于 ${formatLocalTime(updatedAt)}',
            ),
          ),
        ],
      ),
    );
  }

  String _label(NewsProviderState state) => switch (state) {
    NewsProviderState.active => '可用',
    NewsProviderState.disabled => '未启用',
    NewsProviderState.error => '连接失败',
    NewsProviderState.rateLimited => '请求受限',
  };
}
