// Conditional export: dart:html is only importable in a build actually
// targeting web, so the real implementation is picked via `dart.library.html`
// and every other target falls back to the stub (never invoked — callers
// guard with kIsWeb first).
export 'web_download_stub.dart' if (dart.library.html) 'web_download_web.dart';
