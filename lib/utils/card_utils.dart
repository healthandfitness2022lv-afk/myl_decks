// lib/utils/card_utils.dart
// Utilidades compartidas entre múltiples pantallas y widgets.

/// Capitaliza la primera letra de cada palabra de un nombre de carta.
String prettyCardName(String s) {
  final str = s.trim();
  if (str.isEmpty) return str;
  return str
      .split(RegExp(r'\s+'))
      .map((p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}')
      .join(' ');
}

/// Transforma una URL de Cloudinary para servir un thumbnail 120×170.
/// Si la URL no contiene '/upload/' la devuelve sin cambios.
String? thumb120x170(String? url) {
  if (url == null || url.isEmpty) return url;
  if (!url.contains('/upload/')) return url;
  return url.replaceFirst(
    '/upload/',
    '/upload/f_auto,q_auto,w_120,h_170,c_fill,g_auto/',
  );
}

/// Normalización difusa del tipo de carta (coincidencia parcial):
/// tolera encoding roto y variantes ("gran aliado", "armadura", "oros"…).
/// Devuelve una de: aliado / talisman / arma / totem / oro / descendiente,
/// o el string normalizado si no coincide con ninguna.
String normalizeTipoLoose(String? t) {
  var s = (t ?? '').trim().toLowerCase();
  s = s
      .replaceAll(RegExp(r'[áàä]'), 'a')
      .replaceAll(RegExp(r'[éèë]'), 'e')
      .replaceAll(RegExp(r'[íìï]'), 'i')
      .replaceAll(RegExp(r'[óòö]'), 'o')
      .replaceAll(RegExp(r'[úùü]'), 'u')
      .replaceAll('ñ', 'n');
  if (s.contains('aliad')) return 'aliado';
  if (s.contains('talis')) return 'talisman';
  if (s.contains('arma')) return 'arma';
  if (s.contains('totem')) return 'totem';
  if (s.contains('oro')) return 'oro';
  if (s.contains('descend')) return 'descendiente';
  return s;
}

/// Normaliza el tipo de una carta de mazo para comparaciones
/// (quita acentos, mapea sinónimos: gran aliado → aliado, etc.).
String normalizeDeckType(String? t) {
  var s = (t ?? '').trim().toLowerCase();
  s = s
      .replaceAll(RegExp(r'[áàä]'), 'a')
      .replaceAll(RegExp(r'[éèë]'), 'e')
      .replaceAll(RegExp(r'[íìï]'), 'i')
      .replaceAll(RegExp(r'[óòö]'), 'o')
      .replaceAll(RegExp(r'[úùü]'), 'u')
      .replaceAll('ñ', 'n');
  if (s == 'gran aliado') return 'aliado';
  if (s == 'talisman') return 'talisman';
  if (s == 'totem' || s == 'totem de raza') return 'totem';
  if (s == 'armadura') return 'arma';
  if (s == 'oros') return 'oro';
  return s;
}
