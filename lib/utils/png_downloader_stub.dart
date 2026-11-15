// Implementación no-web: no-op. En móvil/desktop el guardado se hace vía
// path_provider + share_plus dentro de deck_poster.dart.
void downloadPngBytes(List<int> bytes, String fileName) {
  throw UnsupportedError('downloadPngBytes solo está disponible en web');
}
