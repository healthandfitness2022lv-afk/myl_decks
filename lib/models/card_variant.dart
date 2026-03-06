// lib/models/card_variant.dart
class CardVariant {
  final String id;
  final String name;                 // Variante (ej: Full Art 2023)
  final String printType;            // Tipo de impresión (ej: Base, Foil, Alt, etc.)
  final String? code;                // Código opcional
  final String? imageFrontUrl;       // Imagen de la variante
  final String? cloudinaryPublicId;  // opcional (para borrar en Cloudinary)
  final bool isBase;                 // true para la variante "normal" de la carta

  CardVariant({
    required this.id,
    required this.name,
    required this.printType,
    this.code,
    this.imageFrontUrl,
    this.cloudinaryPublicId,
    this.isBase = false,
  });

  factory CardVariant.fromMap(Map<String, dynamic> map, String id) {
    return CardVariant(
      id: id,
      name: (map['name'] ?? '').toString(),
      printType: (map['printType'] ?? '').toString(),
      code: map['code']?.toString(),
      imageFrontUrl: map['imageFrontUrl']?.toString(),
      cloudinaryPublicId: map['cloudinaryPublicId']?.toString(),
      isBase: (map['isBase'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'printType': printType,
        if (code != null && code!.isNotEmpty) 'code': code,
        if (imageFrontUrl != null && imageFrontUrl!.isNotEmpty) 'imageFrontUrl': imageFrontUrl,
        if (cloudinaryPublicId != null && cloudinaryPublicId!.isNotEmpty)
          'cloudinaryPublicId': cloudinaryPublicId,
        if (isBase) 'isBase': true,
      };

  // ================================
  // 👇 Helpers para URLs con Cloudinary
  // ================================
  String? thumbUrl({int w = 120, int h = 160}) {
    final url = imageFrontUrl;
    if (url == null || url.isEmpty) return null;
    if (!url.contains('res.cloudinary.com')) return url;
    return url.replaceFirst(
      '/upload/',
      '/upload/f_auto,q_auto,w_${w},h_${h},c_fill,g_auto/',
    );
  }

  String? fitPanelUrl({int w = 600, int h = 840}) {
    final url = imageFrontUrl;
    if (url == null || url.isEmpty) return null;
    if (!url.contains('res.cloudinary.com')) return url;
    return url.replaceFirst(
      '/upload/',
      '/upload/f_auto,q_auto,dpr_auto,c_fit,w_${w},h_${h}/',
    );
  }
}
