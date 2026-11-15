import '../utils/card_image_resolver.dart';

class CardVariant {
  final String id;
  final String name;
  final String printType;
  final String? code;
  final String? imageFrontUrl;
  final String? cloudinaryPublicId;
  final bool isBase;

  static const List<String> orderedGroupKeys = [
    'normal',
    'legendaria',
    'arte_alternativo',
    'full_art',
    'milenaria',
    'shogun',
    'foil_lluvia',
    'jo',
    'otros',
  ];

  static const Map<String, String> groupLabels = {
    'normal': 'Normal',
    'legendaria': 'Legendaria',
    'arte_alternativo': 'Arte alternativo',
    'full_art': 'Full art',
    'milenaria': 'Milenaria',
    'shogun': 'Shogun',
    'foil_lluvia': 'Foil lluvia',
    'jo': 'JO',
    'otros': 'Otras',
  };

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
      imageFrontUrl: CardImageResolver.fromMap(map),
      cloudinaryPublicId: map['cloudinaryPublicId']?.toString(),
      isBase: (map['isBase'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'printType': printType,
    if (code != null && code!.isNotEmpty) 'code': code,
    if (imageFrontUrl != null && imageFrontUrl!.isNotEmpty)
      'imageFrontUrl': imageFrontUrl,
    if (cloudinaryPublicId != null && cloudinaryPublicId!.isNotEmpty)
      'cloudinaryPublicId': cloudinaryPublicId,
    if (isBase) 'isBase': true,
  };

  String get groupKey =>
      normalizeGroup(printType.isNotEmpty ? printType : name, isBase: isBase);

  String get groupLabel {
    final key = groupKey;
    if (key == 'otros') {
      // Usar el nombre real en lugar del genérico "Otras"
      final label = printType.isNotEmpty ? printType : name;
      return label.isNotEmpty ? label : 'Otras';
    }
    return groupLabels[key] ?? name;
  }

  int get groupRank {
    final index = orderedGroupKeys.indexOf(groupKey);
    return index >= 0 ? index : orderedGroupKeys.length;
  }

  static String normalizeGroup(String raw, {bool isBase = false}) {
    if (isBase) return 'normal';

    final value = raw
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u');

    if (value.isEmpty) return 'normal';
    if (value.contains('foil lluvia') || value.contains('lluvia foil')) {
      return 'foil_lluvia';
    }
    if (value == 'jo' || value.contains(' jo ') || value.startsWith('jo ')) {
      return 'jo';
    }
    if (value.contains('shogun')) return 'shogun';
    if (value.contains('milenaria')) return 'milenaria';
    if (value.contains('full art') || value.contains('fullart')) {
      return 'full_art';
    }
    if (value.contains('arte alternativo') ||
        value.contains('art alt') ||
        value.contains('alt art') ||
        value.contains('alternativo')) {
      return 'arte_alternativo';
    }
    if (value.contains('legendaria') || value.contains('legendary')) {
      return 'legendaria';
    }
    if (value.contains('normal') ||
        value.contains('base') ||
        value.contains('clasica') ||
        value.contains('clasico')) {
      return 'normal';
    }
    return 'otros';
  }

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
