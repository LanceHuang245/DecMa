import 'package:url_launcher/url_launcher.dart';

// Opens a verified HTTP(S) link with the operating system's default browser.
Future<void> openExternalLink(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);
