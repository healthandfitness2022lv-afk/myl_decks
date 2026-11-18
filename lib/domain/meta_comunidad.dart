// lib/domain/meta_comunidad.dart
//
// Qué se juega en la comunidad: agrega los mazos construidos en la app
// (razas, ediciones, cartas y estilo agro/control según sus habilidades).

import '../models/card_myl.dart';
import '../models/deck.dart';
import '../utils/card_utils.dart';
import 'analisis_mazo/analisis_mazo.dart';

class MetaComunidad {
  final int mazos;
  final Map<String, int> porRaza;
  final Map<String, int> porEdicion;

  /// Mazos por estilo: Agro, Medio, Control, Combo.
  final Map<String, int> porEstilo;

  /// Velocidad media (0 = control, 100 = agro); null si ningún mazo tiene
  /// cartas con habilidades programadas.
  final int? indiceMedio;

  /// Velocidad media de los mazos de cada raza (solo razas con 2 o más).
  final Map<String, int> indicePorRaza;

  /// nombre → copias totales / nº de mazos, de más a menos (sin Oros).
  final List<MapEntry<String, int>> cartasPorCopias;
  final List<MapEntry<String, int>> cartasPorMazos;

  const MetaComunidad({
    required this.mazos,
    required this.porRaza,
    required this.porEdicion,
    required this.porEstilo,
    required this.indiceMedio,
    required this.indicePorRaza,
    required this.cartasPorCopias,
    required this.cartasPorMazos,
  });
}

/// [mazos]: documentos `decks` tal como están en Firestore. Solo cuentan los
/// completos (40 cartas o más) para que los borradores no distorsionen.
MetaComunidad agregarMeta(
  Iterable<Map<String, dynamic>> mazos, {
  required CardMyL? Function(DeckCardEntry entry) resolver,
  int minimoCartas = 40,
}) {
  final porRaza = <String, int>{};
  final porEdicion = <String, int>{};
  final porEstilo = <String, int>{};
  final copias = <String, int>{};
  final enMazos = <String, int>{};
  final indicesRaza = <String, List<int>>{};
  var total = 0, conEstilo = 0, sumaIndice = 0;

  for (final data in mazos) {
    final entradas = [
      for (final raw in (data['cards'] as List? ?? const []))
        if (raw is Map) DeckCardEntry.fromMap(Map<String, dynamic>.from(raw)),
    ];
    if (entradas.fold<int>(0, (s, e) => s + e.count) < minimoCartas) continue;
    total++;
    final raza = (data['race'] ?? '').toString().trim();
    if (raza.isNotEmpty) porRaza[raza] = (porRaza[raza] ?? 0) + 1;
    final edicion = (data['edition'] ?? '').toString().trim();
    if (edicion.isNotEmpty) {
      porEdicion[edicion] = (porEdicion[edicion] ?? 0) + 1;
    }
    final vistas = <String>{};
    for (final e in entradas) {
      if (normalizeTipoLoose(e.tipo ?? '') == 'oro') continue;
      final nombre = prettyCardName(e.name);
      if (nombre.isEmpty) continue;
      copias[nombre] = (copias[nombre] ?? 0) + e.count;
      if (vistas.add(nombre)) enMazos[nombre] = (enMazos[nombre] ?? 0) + 1;
    }
    final a = analizarEntradas(entradas, resolver: resolver);
    if (a.sinRoles) continue;
    conEstilo++;
    sumaIndice += a.indice;
    porEstilo[a.perfil] = (porEstilo[a.perfil] ?? 0) + 1;
    if (raza.isNotEmpty) (indicesRaza[raza] ??= []).add(a.indice);
  }

  List<MapEntry<String, int>> orden(Map<String, int> m) =>
      m.entries.toList()..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
  return MetaComunidad(
    mazos: total,
    porRaza: porRaza,
    porEdicion: porEdicion,
    porEstilo: porEstilo,
    indiceMedio: conEstilo == 0 ? null : (sumaIndice / conEstilo).round(),
    indicePorRaza: {
      for (final e in indicesRaza.entries)
        if (e.value.length >= 2)
          e.key: (e.value.reduce((a, b) => a + b) / e.value.length).round(),
    },
    cartasPorCopias: orden(copias).take(20).toList(),
    cartasPorMazos: orden(enMazos).take(20).toList(),
  );
}

/// "Muy agro", "Agro", "Parejo", "Control" o "Muy control" según el índice.
String lecturaIndice(num indice) {
  if (indice >= 70) return 'Muy agro';
  if (indice >= corteAgro) return 'Agro';
  if (indice > corteControl) return 'Parejo';
  if (indice > 25) return 'Control';
  return 'Muy control';
}
