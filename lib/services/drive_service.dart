// lib/services/drive_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class DriveFile {
  final String id;
  final String name;
  final String mimeType;
  final String? thumbnailLink;

  const DriveFile({
    required this.id,
    required this.name,
    required this.mimeType,
    this.thumbnailLink,
  });

  bool get isFolder => mimeType == 'application/vnd.google-apps.folder';

  bool get isImage =>
      mimeType.startsWith('image/') || mimeType == 'application/octet-stream';

  /// URL para guardar en Firestore. Siempre guarda el formato estándar de Drive —
  /// webSafeUrl() se encarga de convertirla al mostrar en web.
  String get viewUrl => 'https://drive.google.com/uc?export=view&id=$id';

  /// Thumbnail para preview rápido en la app.
  /// En web usa el proxy para evitar CORS.
  String get previewUrl {
    final raw =
        thumbnailLink?.replaceAll('=s220', '=s400') ??
        'https://drive.google.com/thumbnail?id=$id&sz=w400';
    return kIsWeb ? DriveService.webSafeUrl(raw) : raw;
  }

  factory DriveFile.fromJson(Map<String, dynamic> j) => DriveFile(
    id: j['id'] as String,
    name: j['name'] as String,
    mimeType: j['mimeType'] as String,
    thumbnailLink: j['thumbnailLink'] as String?,
  );
}

class DriveService {
  /// Reemplazá con tu API key de Google Cloud (Drive API habilitada).
  /// Restringila solo a "Google Drive API" en la consola.
  static const String _apiKey = 'AIzaSyDJk3yuYbW--Tj2j_XmHd-L9-5tzkCi4eU';

  /// Carpeta raíz del picker individual (cartas MYL).
  static const String rootFolderId = '1H4YzrhdiJGI_k9z4D3fzwledkdKHt1VN';

  /// Carpeta raíz para asignación masiva (Ediciones PBX).
  static const String bulkRootFolderId = '1PaxzMQMHvU7b2XzCOqShfwlNv9c4kSnJ';

  /// Carpeta raíz de wallpapers de fondo, organizada en subcarpetas por raza.
  static const String wallpaperRootFolderId =
      '1_ODODjsFLYkVnRnWXY--GTct5OFphNC8';

  static const String _baseUrl = 'https://www.googleapis.com/drive/v3/files';

  /// Lista el contenido de una carpeta (archivos e imágenes directas).
  /// Pagina automáticamente con nextPageToken hasta traer todos los archivos.
  /// Devuelve primero las carpetas, luego las imágenes, ordenadas por nombre.
  static Future<List<DriveFile>> listFolder(String folderId) async {
    const fields = 'nextPageToken,files(id,name,mimeType,thumbnailLink)';
    final q = Uri.encodeComponent("'$folderId' in parents and trashed = false");

    final allFiles = <DriveFile>[];
    String? pageToken;

    do {
      final tokenParam =
          pageToken != null
              ? '&pageToken=${Uri.encodeComponent(pageToken)}'
              : '';
      final uri = Uri.parse(
        '$_baseUrl?q=$q&fields=${Uri.encodeComponent(fields)}&key=$_apiKey'
        '&orderBy=folder,name&pageSize=1000$tokenParam',
      );

      final res = await http.get(uri);
      if (res.statusCode != 200) {
        throw Exception('Drive API error ${res.statusCode}: ${res.body}');
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final batch =
          (data['files'] as List<dynamic>? ?? [])
              .map((e) => DriveFile.fromJson(e as Map<String, dynamic>))
              .toList();
      allFiles.addAll(batch);
      pageToken = data['nextPageToken'] as String?;
    } while (pageToken != null);

    // carpetas primero, luego imágenes
    allFiles.sort((a, b) {
      if (a.isFolder && !b.isFolder) return -1;
      if (!a.isFolder && b.isFolder) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return allFiles;
  }

  /// Convierte URLs de Drive al formato correcto según la plataforma.
  /// En Android/iOS devuelve la URL original (máxima calidad).
  /// En web usa weserv.nl como proxy para evitar CORS de Google Drive.
  static String webSafeUrl(String url, {int ancho = 800}) {
    final value = url.trim();
    if (value.isEmpty || !kIsWeb) return value;
    final parsed = Uri.tryParse(value);
    final host = parsed?.host.toLowerCase();
    if (host == 'images.weserv.nl' || host == 'lh3.googleusercontent.com') {
      return value; // ya resuelta (no envolver dos veces)
    }
    // El CDN de Google (lh3) sirve el archivo de Drive con CORS abierto,
    // redimensionado y en webp: 0,4 s contra 1–2 s del proxy weserv, que
    // además le pide la imagen a Drive cada vez y Drive corta si son muchas.
    final id =
        value.contains('drive.google.com') ? _extractDriveId(value) : null;
    if (id != null) return 'https://lh3.googleusercontent.com/d/$id=w$ancho-rw';
    return proxyWeserv(value, ancho: ancho);
  }

  /// Respaldo por weserv.nl (si el CDN de Google falla para una imagen).
  static String proxyWeserv(String url, {int ancho = 800}) {
    final value = url.trim();
    if (value.isEmpty || !kIsWeb) return value;
    // Cualquier URL de Drive o de Google content → proxy
    if (value.contains('drive.google.com') ||
        value.contains('googleusercontent.com')) {
      // El endpoint uc?export=view devuelve una página HTML (o 403 por throttling),
      // no la imagen: weserv no la puede leer y responde 404. Convertimos a
      // /thumbnail?id=..., que sí entrega bytes de imagen directos.
      final id = _extractDriveId(value);
      final source =
          id != null
              ? 'https://drive.google.com/thumbnail?id=$id&sz=w$ancho'
              : value;
      final encoded = Uri.encodeComponent(source);
      return 'https://images.weserv.nl/?url=$encoded&w=$ancho&output=webp';
    }
    return value;
  }

  /// Extrae el file ID de las distintas variantes de URL de Drive
  /// (uc?export=view&id=, thumbnail?id=, /file/d/ID/).
  static String? _extractDriveId(String url) {
    final idParam = RegExp(r'[?&]id=([a-zA-Z0-9_-]+)').firstMatch(url);
    if (idParam != null) return idParam.group(1);
    final path = RegExp(r'/d/([a-zA-Z0-9_-]+)').firstMatch(url);
    if (path != null) return path.group(1);
    return null;
  }

  /// Extrae el folder ID de un link de Drive compartido.
  /// Soporta /folders/ID y /file/d/ID/view
  static String? extractId(String url) {
    final folderMatch = RegExp(r'folders/([a-zA-Z0-9_-]+)').firstMatch(url);
    if (folderMatch != null) return folderMatch.group(1);

    final fileMatch = RegExp(r'/d/([a-zA-Z0-9_-]+)').firstMatch(url);
    if (fileMatch != null) return fileMatch.group(1);

    // si ya es solo un ID (alfanumérico largo)
    if (RegExp(r'^[a-zA-Z0-9_-]{20,}$').hasMatch(url.trim())) {
      return url.trim();
    }

    return null;
  }
}
