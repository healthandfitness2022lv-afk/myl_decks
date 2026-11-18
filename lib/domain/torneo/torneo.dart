// lib/domain/torneo/torneo.dart
//
// Reglas de un torneo suizo con top cut, sin Firestore ni UI:
// emparejamientos, tabla con desempates y llave de eliminación.
//
// Puntos: victoria 3, empate 1, derrota 0. El bye cuenta como victoria 2-0.
// Desempates, en orden: % de duelos de los rivales, % de partidas propias,
// % de partidas de los rivales (cada porcentaje con piso de 33%, como es
// habitual en torneos suizos para que un rival que abandona no hunda a nadie).

import 'dart:math' as math;

const puntosVictoria = 3;
const puntosEmpate = 1;
const pisoPorcentaje = 1 / 3;

class JugadorTorneo {
  final String id;
  final String nombre;

  /// Se retiró: no se le empareja más, pero sus duelos jugados cuentan.
  final bool retirado;

  const JugadorTorneo({
    required this.id,
    required this.nombre,
    this.retirado = false,
  });
}

/// Un duelo ya jugado o por jugar. [b] null = bye de [a].
class DueloTorneo {
  /// 'suizo' o 'top'.
  final String fase;
  final int ronda;
  final int mesa;
  final String a;
  final String? b;
  final int? scoreA;
  final int? scoreB;

  /// El resultado está confirmado (por el rival o el organizador).
  final bool confirmado;

  const DueloTorneo({
    required this.fase,
    required this.ronda,
    required this.mesa,
    required this.a,
    this.b,
    this.scoreA,
    this.scoreB,
    this.confirmado = false,
  });

  bool get esBye => b == null;
  bool get cerrado => esBye || (confirmado && scoreA != null && scoreB != null);

  /// Id del ganador; null si no está cerrado o fue empate.
  String? get ganador {
    if (esBye) return a;
    if (!cerrado || scoreA == scoreB) return null;
    return scoreA! > scoreB! ? a : b;
  }

  String? get perdedor {
    final g = ganador;
    if (g == null || esBye) return null;
    return g == a ? b : a;
  }

  bool get empate => !esBye && cerrado && scoreA == scoreB;
}

class Emparejamiento {
  final String a;
  final String? b;
  const Emparejamiento(this.a, [this.b]);

  @override
  String toString() => '$a vs ${b ?? 'bye'}';
}

class FilaTabla {
  final JugadorTorneo jugador;
  int puntos = 0;
  int jugados = 0;
  int ganados = 0;
  int empatados = 0;
  int perdidos = 0;
  int partidasGanadas = 0;
  int partidasPerdidas = 0;
  int byes = 0;

  /// Rivales enfrentados (sin contar byes).
  final List<String> rivales = [];

  /// % de duelos de los rivales.
  double rivalesDuelos = 0;

  /// % de partidas de los rivales.
  double rivalesPartidas = 0;

  FilaTabla(this.jugador);

  /// % de duelos propios (puntos sobre el máximo), con piso.
  double get porcentajeDuelos =>
      jugados == 0
          ? pisoPorcentaje
          : math.max(pisoPorcentaje, puntos / (puntosVictoria * jugados));

  /// % de partidas propias, con piso.
  double get porcentajePartidas {
    final total = partidasGanadas + partidasPerdidas;
    return total == 0
        ? pisoPorcentaje
        : math.max(pisoPorcentaje, partidasGanadas / total);
  }
}

/// Rondas suizas recomendadas según la cantidad de inscritos.
int rondasSugeridas(int jugadores) {
  if (jugadores <= 2) return 1;
  return math.min(8, (math.log(jugadores) / math.ln2).ceil());
}

/// Tamaño de top cut recomendado (0 = sin top).
int topSugerido(int jugadores) {
  if (jugadores < 6) return 0;
  if (jugadores <= 16) return 4;
  return 8;
}

/// Tabla de la fase suiza con los duelos cerrados, ordenada por posición.
List<FilaTabla> calcularTabla(
  List<JugadorTorneo> jugadores,
  Iterable<DueloTorneo> duelos,
) {
  final filas = {for (final j in jugadores) j.id: FilaTabla(j)};
  for (final d in duelos) {
    if (d.fase != 'suizo' || !d.cerrado) continue;
    final fa = filas[d.a];
    if (fa == null) continue;
    if (d.esBye) {
      fa
        ..jugados += 1
        ..ganados += 1
        ..byes += 1
        ..puntos += puntosVictoria
        ..partidasGanadas += 2;
      continue;
    }
    final fb = filas[d.b];
    if (fb == null) continue;
    fa.jugados += 1;
    fb.jugados += 1;
    fa.partidasGanadas += d.scoreA!;
    fa.partidasPerdidas += d.scoreB!;
    fb.partidasGanadas += d.scoreB!;
    fb.partidasPerdidas += d.scoreA!;
    fa.rivales.add(fb.jugador.id);
    fb.rivales.add(fa.jugador.id);
    if (d.empate) {
      fa
        ..empatados += 1
        ..puntos += puntosEmpate;
      fb
        ..empatados += 1
        ..puntos += puntosEmpate;
    } else {
      final gana = d.ganador == d.a ? fa : fb;
      final pierde = identical(gana, fa) ? fb : fa;
      gana
        ..ganados += 1
        ..puntos += puntosVictoria;
      pierde.perdidos += 1;
    }
  }
  for (final f in filas.values) {
    if (f.rivales.isEmpty) continue;
    var duelosRival = 0.0, partidasRival = 0.0;
    for (final r in f.rivales) {
      duelosRival += filas[r]!.porcentajeDuelos;
      partidasRival += filas[r]!.porcentajePartidas;
    }
    f.rivalesDuelos = duelosRival / f.rivales.length;
    f.rivalesPartidas = partidasRival / f.rivales.length;
  }
  final lista = filas.values.toList();
  lista.sort(compararFilas);
  return lista;
}

/// Orden de la tabla: puntos y luego los desempates. Al final, el nombre
/// (solo para que el orden sea estable).
int compararFilas(FilaTabla a, FilaTabla b) {
  var c = b.puntos.compareTo(a.puntos);
  if (c != 0) return c;
  c = b.rivalesDuelos.compareTo(a.rivalesDuelos);
  if (c != 0) return c;
  c = b.porcentajePartidas.compareTo(a.porcentajePartidas);
  if (c != 0) return c;
  c = b.rivalesPartidas.compareTo(a.rivalesPartidas);
  if (c != 0) return c;
  return a.jugador.nombre.toLowerCase().compareTo(
    b.jugador.nombre.toLowerCase(),
  );
}

/// Emparejamientos de la siguiente ronda suiza.
///
/// - Primera ronda (sin duelos previos): al azar.
/// - Después: por posición en la tabla, sin repetir rival mientras se pueda.
/// - Con jugadores impares, el bye va al peor ubicado que aún no lo recibió.
/// - Los retirados no se emparejan.
List<Emparejamiento> emparejarSuizo(
  List<JugadorTorneo> jugadores,
  Iterable<DueloTorneo> duelosPrevios, {
  math.Random? azar,
}) {
  final previos = duelosPrevios.where((d) => d.fase == 'suizo').toList();
  final activos = jugadores.where((j) => !j.retirado).toList();
  if (activos.isEmpty) return const [];

  List<String> orden;
  if (previos.isEmpty) {
    orden = [for (final j in activos) j.id]..shuffle(azar ?? math.Random());
  } else {
    final ids = {for (final j in activos) j.id};
    orden = [
      for (final f in calcularTabla(jugadores, previos))
        if (ids.contains(f.jugador.id)) f.jugador.id,
    ];
  }

  final enfrentados = <String, Set<String>>{};
  final conBye = <String>{};
  for (final d in previos) {
    if (d.esBye) {
      conBye.add(d.a);
    } else {
      (enfrentados[d.a] ??= {}).add(d.b!);
      (enfrentados[d.b!] ??= {}).add(d.a);
    }
  }

  String? bye;
  if (orden.length.isOdd) {
    bye = orden.lastWhere((id) => !conBye.contains(id), orElse: () => orden.last);
    orden = [...orden]..remove(bye);
  }

  bool yaJugaron(String x, String y) => enfrentados[x]?.contains(y) ?? false;

  // Búsqueda con retroceso: el primero libre contra el mejor ubicado posible.
  List<Emparejamiento>? armar(List<String> libres, bool permitirRepetir) {
    if (libres.isEmpty) return [];
    final a = libres.first;
    for (var i = 1; i < libres.length; i++) {
      final b = libres[i];
      if (!permitirRepetir && yaJugaron(a, b)) continue;
      final resto = [...libres]..removeAt(i)..removeAt(0);
      final sub = armar(resto, permitirRepetir);
      if (sub != null) return [Emparejamiento(a, b), ...sub];
    }
    return null;
  }

  final pares =
      armar(orden, false) ?? armar(orden, true) ?? const <Emparejamiento>[];
  return [...pares, if (bye != null) Emparejamiento(bye)];
}

/// Primera ronda de la llave: [clasificados] en orden de siembra (1º, 2º…).
/// Devuelve los cruces en orden de llave, de modo que los ganadores de las
/// mesas 1-2 y 3-4 se enfrentan en la ronda siguiente (1º y 2º solo se
/// pueden cruzar en la final).
List<Emparejamiento> llaveInicial(List<String> clasificados) {
  final n = clasificados.length;
  if (n < 2 || (n & (n - 1)) != 0) {
    throw ArgumentError('El top debe ser una potencia de 2 (2, 4, 8…): $n');
  }
  // Orden de siembras por mesa: [1,2] → [1,4,2,3] → [1,8,4,5,2,7,3,6]…
  var siembras = [1, 2];
  while (siembras.length < n) {
    final total = siembras.length * 2 + 1;
    siembras = [
      for (final s in siembras) ...[s, total - s],
    ];
  }
  return [
    for (var i = 0; i < n; i += 2)
      Emparejamiento(
        clasificados[siembras[i] - 1],
        clasificados[siembras[i + 1] - 1],
      ),
  ];
}

/// Siguiente ronda de la llave a partir de la anterior (ordenada por mesa):
/// ganador de la mesa 1 contra el de la 2, el de la 3 contra el de la 4…
/// Devuelve vacío si la ronda anterior era la final o no está cerrada.
List<Emparejamiento> siguienteLlave(List<DueloTorneo> rondaAnterior) {
  final orden = [...rondaAnterior]..sort((a, b) => a.mesa.compareTo(b.mesa));
  if (orden.length < 2 || orden.any((d) => d.ganador == null)) return const [];
  return [
    for (var i = 0; i + 1 < orden.length; i += 2)
      Emparejamiento(orden[i].ganador!, orden[i + 1].ganador!),
  ];
}

/// Nombre de una ronda de la llave según cuántos duelos tiene.
String nombreRondaTop(int duelos) {
  switch (duelos) {
    case 1:
      return 'Final';
    case 2:
      return 'Semifinal';
    case 4:
      return 'Cuartos de final';
    default:
      return 'Top ${duelos * 2}';
  }
}

/// ¿El marcador es válido para un duelo al mejor de [mejorDe]?
/// En suizo se acepta el empate (1-1 por tiempo); en el top no.
bool marcadorValido(int a, int b, {int mejorDe = 3, required bool permiteEmpate}) {
  if (a < 0 || b < 0) return false;
  final necesarias = mejorDe ~/ 2 + 1;
  if (a > necesarias || b > necesarias) return false;
  if (a == b) return permiteEmpate && a + b > 0 && a < necesarias;
  return math.max(a, b) == necesarias ||
      // Duelo cortado por tiempo con ventaja (1-0): vale en suizo.
      (permiteEmpate && a + b < mejorDe);
}
