import 'package:fluent_ui/fluent_ui.dart';

// Windows 11 settings group: a bold title over rows separated by dividers.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: FluentTheme.of(context).typography.bodyStrong),
      const SizedBox(height: 4),
      for (final (index, row) in rows.indexed) ...[
        if (index > 0) const Divider(),
        row,
      ],
    ],
  );
}

// Name and description on the left, switch on the right; details show only while enabled.
class SettingsToggleRow extends StatelessWidget {
  const SettingsToggleRow({
    super.key,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
    this.details,
  });

  final Widget title;
  final String description;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? details;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    Text(
                      description,
                      style: theme.typography.caption?.copyWith(
                        color: theme.resources.textFillColorSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              ToggleSwitch(checked: value, onChanged: onChanged),
            ],
          ),
          if (value && details != null) ...[
            const SizedBox(height: 8),
            details!,
          ],
        ],
      ),
    );
  }
}
