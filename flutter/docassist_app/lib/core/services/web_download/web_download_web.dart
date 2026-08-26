import 'dart:typed_data';
import 'dart:html' as html;

/// Triggers a browser file download for [bytes] — the web equivalent of
/// writing to app storage and sharing on mobile/desktop. No path_provider
/// or dart:io involved, since neither exists on web.
void downloadBytes(Uint8List bytes, String filename, String mimeType) {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.document.createElement('a') as html.AnchorElement
    ..href = url
    ..style.display = 'none'
    ..download = filename;
  html.document.body!.children.add(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
