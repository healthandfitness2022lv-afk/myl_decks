import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

/// Dispara la descarga de [bytes] como archivo PNG directamente al PC,
/// usando un blob + <a download> (sin pasar por el share sheet del navegador).
void downloadPngBytes(List<int> bytes, String fileName) {
  final blob = web.Blob(
    [Uint8List.fromList(bytes).toJS].toJS,
    web.BlobPropertyBag(type: 'image/png'),
  );
  final url = web.URL.createObjectURL(blob);

  final anchor =
      web.document.createElement('a') as web.HTMLAnchorElement
        ..href = url
        ..download = fileName;
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();

  web.URL.revokeObjectURL(url);
}
