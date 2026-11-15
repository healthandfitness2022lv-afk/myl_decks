import '../services/drive_service.dart';

class CardImageResolver {
  const CardImageResolver._();

  static String normalize(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return '';
    return DriveService.webSafeUrl(value);
  }

  static String? fromMap(Map<String, dynamic> data) {
    for (final key in const [
      'officialImageUrl',
      'imageFrontUrl',
      'imageUrl',
      'frontImageUrl',
      'imagen',
      'thumbnailUrl',
    ]) {
      final resolved = normalize(data[key]?.toString());
      if (resolved.isNotEmpty) return resolved;
    }
    return null;
  }
}
