// lib/utils/text_normalize.dart
//
// Normalización de texto para búsquedas: minúsculas + sin tildes/diacríticos,
// para que buscar "orion" encuentre "Orión". Usar en el query del usuario Y
// en el campo comparado de cada lista.

String normalizeSearch(String s) {
  var t = s.trim().toLowerCase();
  t = t
      .replaceAll(RegExp(r'[áàäâ]'), 'a')
      .replaceAll(RegExp(r'[éèëê]'), 'e')
      .replaceAll(RegExp(r'[íìïî]'), 'i')
      .replaceAll(RegExp(r'[óòöô]'), 'o')
      .replaceAll(RegExp(r'[úùüû]'), 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'\s+'), ' ');
  return t;
}
