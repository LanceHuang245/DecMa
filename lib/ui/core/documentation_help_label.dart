import 'package:fluent_ui/fluent_ui.dart';

import '../../utils/external_link.dart';

/// Keeps settings labels and their documentation links visually consistent.
class DocumentationHelpLabel extends StatelessWidget {
  const DocumentationHelpLabel({
    super.key,
    required this.label,
    required this.tooltip,
    required this.documentationUrl,
  });

  final String label;
  final String tooltip;
  final String documentationUrl;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label),
      const SizedBox(width: 2),
      Tooltip(
        message: tooltip,
        child: IconButton(
          icon: const Icon(FluentIcons.unknown),
          onPressed: () => openExternalLink(Uri.parse(documentationUrl)),
        ),
      ),
    ],
  );
}
