import 'dart:io';

class NodeRuntimeService {
  static const downloadUrl = 'https://nodejs.org/';

  // Both commands are required because the bundled MCP servers start through npx.
  static Future<bool> isAvailable() async {
    final checks = await Future.wait([_canRun('node'), _canRun('npx')]);
    return checks.every((available) => available);
  }

  static Future<bool> _canRun(String command) async {
    try {
      final result =
          await (Platform.isWindows
                  ? Process.run('cmd', ['/c', command, '--version'])
                  : Process.run(command, ['--version']))
              .timeout(const Duration(seconds: 3));
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openDownloadPage() async {
    if (Platform.isWindows) {
      await Process.start('cmd', ['/c', 'start', '', downloadUrl]);
    } else if (Platform.isMacOS) {
      await Process.start('open', [downloadUrl]);
    } else {
      await Process.start('xdg-open', [downloadUrl]);
    }
  }
}
