// lib/domain/perfil_jugador.dart
//
// Resúmenes que muestra el perfil del jugador, sin Firestore ni UI:
// mazos y estilo, colección, Desafío contra la IA e historial de torneos.

import '../models/card_myl.dart';
import '../models/deck.dart';
import '../models/inventory.dart';
import '../models/torneo.dart';
import 'analisis_mazo/analisis_mazo.dart';
import 'torneo/torneo.dart';

// ── Mazos y estilo ───────────────────────────────────────────────────────────

class ResumenMazos {
  /// Mazos con cartas (los vacíos no cuentan).
  final int mazos;

  /// Mazos por perfil: Agro, Medio, Control, Combo.
  final Map<String, int> porPerfil;

  /// Mazos por raza, de más a menos.
  final List<MapEntry<String, int>> razas;

  /// Velocidad media de sus mazos (0 = control, 100 = agro); null sin datos.
  final int? indiceMedio;

  /// Cartas (sin Oros) presentes en más mazos: nombre → nº de mazos.
  final List<MapEntry<String, int>> cartasFrecuentes;

  /// Roles con más peso sumando todos sus mazos.
  final List<String> rolesFavoritos;

  const ResumenMazos({
    required this.mazos,
    required this.porPerfil,
    required this.razas,
    required this.indiceMedio,
    required this.cartasFrecuentes,
    required this.rolesFavoritos,
  });

  /// "Juegas sobre todo Control" / null si no hay datos.
  String? get estilo {
    if (porPerfil.isEmpty) return null;
    final orden =
        porPerfil.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    if (orden.length > 1 && orden[0].value == orden[1].value) {
      return 'Repartes entre ${orden[0].key} y ${orden[1].key}';
    }
    return 'Juegas sobre todo ${orden.first.key}';
  }
}

ResumenMazos resumirMazos(
  List<Deck> decks, {
  required CardMyL? Function(DeckCardEntry entry) resolver,
}) {
  final porPerfil = <String, int>{};
  final razas = <String, int>{};
  final enMazos = <String, int>{};
  final puntos = <String, double>{};
  var conRoles = 0, sumaIndice = 0, mazos = 0;
  for (final d in decks) {
    if (d.cards.isEmpty) continue;
    mazos++;
    final raza = (d.race ?? '').trim();
    if (raza.isNotEmpty) razas[raza] = (razas[raza] ?? 0) + 1;
    final vistas = <String>{};
    for (final e in d.cards) {
      if (tipoNormal(e.tipo ?? resolver(e)?.tipo ?? '').startsWith('oro')) {
        continue;
      }
      if (vistas.add(e.name)) enMazos[e.name] = (enMazos[e.name] ?? 0) + 1;
    }
    final a = analizarMazo(d, resolver: resolver);
    if (a.sinRoles) continue;
    conRoles++;
    sumaIndice += a.indice;
    porPerfil[a.perfil] = (porPerfil[a.perfil] ?? 0) + 1;
    a.puntos.forEach((rol, p) => puntos[rol] = (puntos[rol] ?? 0) + p);
  }
  List<MapEntry<String, int>> orden(Map<String, int> m) =>
      m.entries.toList()..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
  final rolesOrden =
      puntos.entries.where((e) => e.value > 0).toList()
        ..sort((a, b) => b.value.compareTo(a.value));
  return ResumenMazos(
    mazos: mazos,
    porPerfil: porPerfil,
    razas: orden(razas),
    indiceMedio: conRoles == 0 ? null : (sumaIndice / conRoles).round(),
    cartasFrecuentes: orden(enMazos).take(8).toList(),
    rolesFavoritos: [for (final e in rolesOrden.take(3)) e.key],
  );
}

// ── Colección ────────────────────────────────────────────────────────────────

class ResumenColeccion {
  final int copias;
  final int cartasDistintas;

  /// Copias asignadas a algún mazo.
  final int asignadas;

  /// Copias por edición, de más a menos.
  final List<MapEntry<String, int>> porEdicion;

  const ResumenColeccion({
    required this.copias,
    required this.cartasDistintas,
    required this.asignadas,
    required this.porEdicion,
  });

  int get libres => copias - asignadas;
}

ResumenColeccion resumirColeccion(List<InventoryItem> items) {
  var copias = 0, distintas = 0, asignadas = 0;
  final ediciones = <String, int>{};
  for (final i in items) {
    if (i.total <= 0) continue;
    copias += i.total;
    distintas++;
    asignadas += i.assigned.clamp(0, i.total);
    final ed = (i.edition ?? '').trim();
    final clave = ed.isEmpty ? 'Sin edición' : ed;
    ediciones[clave] = (ediciones[clave] ?? 0) + i.total;
  }
  return ResumenColeccion(
    copias: copias,
    cartasDistintas: distintas,
    asignadas: asignadas,
    porEdicion:
        ediciones.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
  );
}

// ── Desafío contra la IA ─────────────────────────────────────────────────────

class ResumenDesafio {
  /// nivel → (jugadas, ganadas).
  final Map<int, (int, int)> porNivel;

  const ResumenDesafio(this.porNivel);

  int get jugadas => porNivel.values.fold(0, (s, v) => s + v.$1);
  int get ganadas => porNivel.values.fold(0, (s, v) => s + v.$2);

  /// El nivel más alto que ha vencido (0 = ninguno).
  int get mejorNivelVencido => porNivel.entries
      .where((e) => e.value.$2 > 0)
      .fold(0, (m, e) => e.key > m ? e.key : m);
}

/// [desafios]: documentos de `ai_challenges` del jugador. Cuentan solo las
/// partidas terminadas (no las dudas ni las abandonadas).
ResumenDesafio resumirDesafios(Iterable<Map<String, dynamic>> desafios) {
  final out = <int, (int, int)>{};
  for (final d in desafios) {
    if (d['status'] != 'terminado' || d['modo'] == 'duda') continue;
    final r = d['resultado'];
    if (r is! Map) continue;
    final nivel =
        ((r['nivelIa'] ?? d['nivel'] ?? 5) as num).toInt().clamp(1, 5);
    final a = out[nivel] ?? (0, 0);
    // El humano siempre es el lado 0.
    out[nivel] = (a.$1 + 1, a.$2 + (r['ganadorLado'] == 0 ? 1 : 0));
  }
  return ResumenDesafio(out);
}

// ── Torneos ──────────────────────────────────────────────────────────────────

class ParticipacionTorneo {
  final Torneo torneo;
  final String mazo;
  final String raza;

  /// Posición en la fase suiza (1 = primero); 0 si aún no hay tabla.
  final int posicion;
  final int jugadores;
  final int ganados, empatados, perdidos;
  final bool campeon;

  const ParticipacionTorneo({
    required this.torneo,
    required this.mazo,
    required this.raza,
    required this.posicion,
    required this.jugadores,
    required this.ganados,
    required this.empatados,
    required this.perdidos,
    required this.campeon,
  });

  int get duelos => ganados + empatados + perdidos;
}

/// Mi paso por un torneo: duelos de suizo y de llave (los byes no cuentan
/// como duelo jugado) y posición en la tabla suiza.
ParticipacionTorneo participacionEn(
  Torneo torneo,
  List<Inscrito> inscritos,
  List<DueloDoc> duelos,
  String uid,
) {
  final yo = inscritos.where((i) => i.uid == uid).firstOrNull;
  final dominio = [for (final d in duelos) d.dominio];
  final tabla = calcularTabla([for (final i in inscritos) i.jugador], dominio);
  final pos = tabla.indexWhere((f) => f.jugador.id == uid);
  var g = 0, e = 0, p = 0;
  for (final d in dominio) {
    if (d.esBye || !d.cerrado || (d.a != uid && d.b != uid)) continue;
    if (d.empate) {
      e++;
    } else if (d.ganador == uid) {
      g++;
    } else {
      p++;
    }
  }
  return ParticipacionTorneo(
    torneo: torneo,
    mazo: yo?.deckNombre ?? '',
    raza: yo?.raza ?? '',
    posicion: torneo.enInscripcion || pos < 0 ? 0 : pos + 1,
    jugadores: inscritos.length,
    ganados: g,
    empatados: e,
    perdidos: p,
    campeon: torneo.finalizado && torneo.campeonUid == uid,
  );
}

class RecordCompetitivo {
  final int ganados, empatados, perdidos;
  const RecordCompetitivo(this.ganados, this.empatados, this.perdidos);

  int get duelos => ganados + empatados + perdidos;

  /// % de victorias sobre duelos jugados; null sin duelos.
  double? get victorias => duelos == 0 ? null : ganados / duelos;

  RecordCompetitivo operator +(RecordCompetitivo o) => RecordCompetitivo(
    ganados + o.ganados,
    empatados + o.empatados,
    perdidos + o.perdidos,
  );
}
