import 'dart:typed_data';

/// Non-web platforms never call this — [DocumentExportService] only reaches
/// here behind a `kIsWeb` check. Throwing makes a wiring mistake loud instead
/// of silently no-op-ing.
void downloadBytes(Uint8List bytes, String filename, String mimeType) {
  throw UnsupportedError('downloadBytes is web-only');
}
