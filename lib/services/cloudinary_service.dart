// lib/services/cloudinary_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' show File, Platform;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

class CloudinaryService {
  static const String _cloudName = 'detliykh6'; // tu cloud correcto
  static const String _presetImage = 'myl_preset'; // unsigned imágenes (existe)
  static const String _presetVideo = 'myl_videos_unsigned'; // unsigned videos (DEBE existir)

  static const String _defaultImageFolder = 'myl_cards';
  static const String _defaultVideoFolder = 'myl_videos';

  // compresión por defecto (500 KB)
  static const int _defaultMaxImageKB = 500;

  CloudinaryService._();
  static final CloudinaryService instance = CloudinaryService._();

  // Mantén image/upload normal
  static Uri _imageUrl() => Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/image/upload');

  // ⚠️ Video: forzamos el preset en query para que JAMÁS falte
  static Uri _videoUrl() => Uri.parse(
        'https://api.cloudinary.com/v1_1/$_cloudName/auto/upload'
        '?upload_preset=$_presetVideo',
      );

  // ===============================
  // Helper: comprimir bytes (JPEG) para que queden < maxSizeKB
  // ===============================
  /// Comprime una imagen (JPEG/PNG/etc) en memoria intentando que el resultado
  /// tenga como máximo [maxSizeKB] kilobytes. Devuelve los bytes resultantes.
  ///
  /// Estrategia:
  /// 1) decodifica la imagen (paquete `image`)
  /// 2) intenta codificar JPEG con calidad decreciente (90 -> 20)
  /// 3) si no alcanza, reduce la dimensión (scale 0.9 por iteración) y repite
  static Uint8List _compressImageBytes(Uint8List input, {int maxSizeKB = _defaultMaxImageKB}) {
    final int maxBytes = maxSizeKB * 1024;
    // quick check
    if (input.lengthInBytes <= maxBytes) return input;

    final img.Image? image = img.decodeImage(input);
    if (image == null) {
      // si no se puede decodificar, devuelve original (fall back)
      return input;
    }

    // Intentar reducir calidad primero
    int quality = 90;
    Uint8List encoded = Uint8List.fromList(img.encodeJpg(image, quality: quality));
    if (encoded.lengthInBytes <= maxBytes) return encoded;

    // baja calidad progresivamente
    while (quality >= 30) {
      quality -= 10;
      encoded = Uint8List.fromList(img.encodeJpg(image, quality: quality));
      if (encoded.lengthInBytes <= maxBytes) return encoded;
    }

    // si aún no alcanza, reduce resolución por pasos
    double scale = 0.9;
    img.Image current = image;
    for (int attempt = 0; attempt < 8; attempt++) {
      final int newW = (current.width * scale).round();
      final int newH = (current.height * scale).round();
      if (newW < 40 || newH < 40) break; // no hagas miniaturas absurdas

      current = img.copyResize(current, width: newW, height: newH);
      // intenta con una calidad moderada
      encoded = Uint8List.fromList(img.encodeJpg(current, quality: 75));
      if (encoded.lengthInBytes <= maxBytes) return encoded;

      // intenta bajar calidad también
      int q = 70;
      while (q >= 30) {
        final e = Uint8List.fromList(img.encodeJpg(current, quality: q));
        if (e.lengthInBytes <= maxBytes) return e;
        q -= 10;
      }

      // reduce más la escala si aún no entra
      scale *= 0.8;
    }

    // último recurso: codificar con baja calidad
    final fallback = Uint8List.fromList(img.encodeJpg(current, quality: 25));
    return fallback.lengthInBytes <= maxBytes ? fallback : fallback;
  }

  // ========== IMÁGENES ==========
  static Future<Map<String, String>> uploadImageFromPath(
    String path, {
    String? filename,
    String? folder,
    int maxSizeKB = _defaultMaxImageKB,
  }) async {
    // Lee el archivo y pasa por la ruta de bytes para poder comprimir
    final bytes = await File(path).readAsBytes();
    return uploadImageFromBytes(bytes, filename: filename ?? path.split(Platform.pathSeparator).last, folder: folder, maxSizeKB: maxSizeKB);
  }

  static Future<Map<String, String>> uploadImageFromBytes(
    Uint8List bytes, {
    required String filename,
    String? folder,
    int maxSizeKB = _defaultMaxImageKB,
  }) async {
    // Comprimir antes de armar el multipart
    final compressed = _compressImageBytes(bytes, maxSizeKB: maxSizeKB);

    final req = http.MultipartRequest('POST', _imageUrl())
      ..fields['upload_preset'] = _presetImage
      ..fields['folder'] = folder ?? _defaultImageFolder
      ..files.add(
        http.MultipartFile.fromBytes('file', compressed, filename: filename),
      );

    final resp = await http.Response.fromStream(await req.send());
    if (resp.statusCode != 200) {
      throw Exception('Cloudinary image error ${resp.statusCode}: ${resp.body}');
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    return {'url': '${data['secure_url']}', 'publicId': '${data['public_id']}'};
  }

  // ========== VIDEOS (preset en query + en campos) ==========
  static Future<Map<String, String>> uploadVideoFromPath(
    String path, {
    String? filename,
    String? folder,
  }) async {
    final req = http.MultipartRequest('POST', _videoUrl())
      ..fields['upload_preset'] = _presetVideo // redundante a propósito
      ..fields['folder'] = folder ?? _defaultVideoFolder
      ..files.add(
        await http.MultipartFile.fromPath('file', path, filename: filename),
      );

    final resp = await http.Response.fromStream(await req.send());
    if (resp.statusCode != 200) {
      throw Exception('Cloudinary video error ${resp.statusCode}: ${resp.body}');
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    return {'url': '${data['secure_url']}', 'publicId': '${data['public_id']}'};
  }

  static Future<Map<String, String>> uploadVideoFromBytes(
    Uint8List bytes, {
    required String filename,
    String? folder,
  }) async {
    final req = http.MultipartRequest('POST', _videoUrl())
      ..fields['upload_preset'] = _presetVideo // redundante a propósito
      ..fields['folder'] = folder ?? _defaultVideoFolder
      ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );

    final resp = await http.Response.fromStream(await req.send());
    if (resp.statusCode != 200) {
      throw Exception('Cloudinary video error ${resp.statusCode}: ${resp.body}');
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    return {'url': '${data['secure_url']}', 'publicId': '${data['public_id']}'};
  }

  // ====== Alias legacy ======
  static Future<Map<String, String>> uploadFromPath(
    String path, {
    String? filename,
    String? folder,
    int maxSizeKB = _defaultMaxImageKB,
  }) =>
      uploadImageFromPath(path, filename: filename, folder: folder, maxSizeKB: maxSizeKB);

  static Future<Map<String, String>> uploadFromBytes(
    Uint8List bytes, {
    required String filename,
    String? folder,
    int maxSizeKB = _defaultMaxImageKB,
  }) =>
      uploadImageFromBytes(bytes, filename: filename, folder: folder, maxSizeKB: maxSizeKB);

  Future<Map<String, String>> uploadVideoUnsignedFile({
    required String filePath,
    String? fileName,
    String? folder,
  }) =>
      CloudinaryService.uploadVideoFromPath(
    filePath,
    filename: fileName,
    folder: folder,
  );

  Future<Map<String, String>> uploadVideoUnsignedBytes({
    required Uint8List bytes,
    required String fileName,
    String? folder,
  }) =>
      CloudinaryService.uploadVideoFromBytes(
    bytes,
    filename: fileName,
    folder: folder,
  );

  static String videoThumbnailUrl({
    required String publicId,
    int width = 480,
    int height = 270,
    String format = 'jpg',
  }) {
    // Si publicId tuviera extensión, la removemos (Cloudinary espera el ID sin .ext)
    final cleanId = publicId.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
    // Primer frame con recorte centrado y resizing
    // Alternativas válidas si prefieres: so_0, so_auto, so_1
    return 'https://res.cloudinary.com/$_cloudName/video/upload/'
        'so_1,c_fill,w_$width,h_$height/$cleanId.$format';
  }
}
