import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../utils/png_downloader.dart';

class DeckPosterShareService {
  static Future<void> sharePosterPng({
    required Uint8List posterBytes,
    required String deckName,
  }) async {
    final safeName = (deckName.isEmpty ? 'deck' : deckName)
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(' ', '_');
    final fileName = '${safeName}_poster.png';

    if (kIsWeb) {
      downloadPngBytes(posterBytes, fileName);
      return;
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}\\$fileName');
    await file.writeAsBytes(posterBytes);

    await Share.shareXFiles([
      XFile(file.path),
    ], text: 'Poster del mazo ${deckName.isEmpty ? '' : deckName}');
  }
}
