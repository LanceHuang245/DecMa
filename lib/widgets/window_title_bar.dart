import 'package:fluent_ui/fluent_ui.dart';
import 'package:window_manager/window_manager.dart';

class WindowTitleBar extends StatelessWidget {
  const WindowTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          Expanded(
            // Keep the title area separate from caption buttons for native behavior.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 14),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    'DecMa',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: theme.resources.textFillColorPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 138,
            height: 36,
            child: WindowCaption(
              brightness: theme.brightness,
              backgroundColor: Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }
}
