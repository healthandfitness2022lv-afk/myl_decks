// lib/models/torneo.dart
//
// Torneo suizo con top cut. Vive en `tournaments/{id}` con dos subcolecciones:
//   players/{uid}   inscritos, con la copia congelada de su lista
//   matches/{id}    un documento por duelo (id = fase + ronda + mesa)
import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/torneo/torneo.dart';
import 'deck.dart';

/// Estados del torneo, en orden.
abstract class EstadoTorneo {
  static const inscripcion = 'inscripcion';
  static const suizo = 'suizo';
  static const top = 'top';
  static const finalizado = 'finalizado';

  static String etiqueta(String estado) {
    switch (estado) {
      case suizo:
        return 'Rondas suizas';
      case top:
        return 'Eliminación';
      case finalizado:
        return 'Finalizado';
      default:
        return 'Inscripción abierta';
    }
  }
}

DateTime? _fecha(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  if (v is String) return DateTime.tryParse(v);
  return null;
}

int _entero(dynamic v, [int defecto = 0]) => v is num ? v.toInt() : defecto;

class Torneo {
  final String id;
  final String nombre;
  final String descripcion;
  final String lugar;
  final DateTime? fecha;
  final String ownerUid;
  final String ownerNombre;

  /// 'open' (aparece en la lista) o 'invite' (solo con código).
  final String visibilidad;
  final String codigo;

  /// Clave de formato de fecha: racial_edicion | racial_libre | full.
  final String formato;
  final int mejorDe;

  /// 0 = según la cantidad de inscritos al iniciar.
  final int rondasSuizas;

  /// 0 (sin top), 2, 4 u 8.
  final int topCut;

  /// 0 = sin cupo.
  final int cupo;
  final String estado;
  final int rondaActual;
  final int rondaTop;
  final List<String> playerUids;
  final String campeonUid;
  final String campeonNombre;

  /// Documento completo (incluye la Ban List congelada).
  final Map<String, dynamic> data;

  const Torneo({
    required this.id,
    required this.nombre,
    this.descripcion = '',
    this.lugar = '',
    this.fecha,
    required this.ownerUid,
    this.ownerNombre = '',
    this.visibilidad = 'open',
    this.codigo = '',
    this.formato = 'racial_edicion',
    this.mejorDe = 3,
    this.rondasSuizas = 0,
    this.topCut = 0,
    this.cupo = 0,
    this.estado = EstadoTorneo.inscripcion,
    this.rondaActual = 0,
    this.rondaTop = 0,
    this.playerUids = const [],
    this.campeonUid = '',
    this.campeonNombre = '',
    this.data = const {},
  });

  factory Torneo.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      Torneo.fromMap(doc.id, doc.data() ?? const {});

  factory Torneo.fromMap(String id, Map<String, dynamic> m) => Torneo(
    id: id,
    nombre: (m['name'] ?? 'Torneo').toString(),
    descripcion: (m['description'] ?? '').toString(),
    lugar: (m['place'] ?? '').toString(),
    fecha: _fecha(m['date']),
    ownerUid: (m['ownerUid'] ?? '').toString(),
    ownerNombre: (m['ownerName'] ?? '').toString(),
    visibilidad: (m['visibility'] ?? 'open').toString(),
    codigo: (m['inviteCode'] ?? '').toString(),
    formato: (m['format'] ?? 'racial_edicion').toString(),
    mejorDe: _entero(m['bestOf'], 3),
    rondasSuizas: _entero(m['swissRounds']),
    topCut: _entero(m['topCut']),
    cupo: _entero(m['maxPlayers']),
    estado: (m['status'] ?? EstadoTorneo.inscripcion).toString(),
    rondaActual: _entero(m['currentRound']),
    rondaTop: _entero(m['topRound']),
    playerUids:
        m['playerUids'] is List
            ? (m['playerUids'] as List).map((e) => '$e').toList()
            : const [],
    campeonUid: (m['championUid'] ?? '').toString(),
    campeonNombre: (m['championName'] ?? '').toString(),
    data: m,
  );

  bool get enInscripcion => estado == EstadoTorneo.inscripcion;
  bool get finalizado => estado == EstadoTorneo.finalizado;
  bool get lleno => cupo > 0 && playerUids.length >= cupo;
  bool esOrganizador(String? uid) => uid != null && uid == ownerUid;
  bool participa(String? uid) => uid != null && playerUids.contains(uid);
}

class Inscrito {
  final String uid;
  final String nombre;
  final String deckId;
  final String deckNombre;
  final String raza;
  final List<DeckCardEntry> cartas;
  final bool retirado;

  const Inscrito({
    required this.uid,
    required this.nombre,
    this.deckId = '',
    this.deckNombre = '',
    this.raza = '',
    this.cartas = const [],
    this.retirado = false,
  });

  factory Inscrito.fromMap(String uid, Map<String, dynamic> m) => Inscrito(
    uid: uid,
    nombre: (m['name'] ?? 'Jugador').toString(),
    deckId: (m['deckId'] ?? '').toString(),
    deckNombre: (m['deckName'] ?? '').toString(),
    raza: (m['race'] ?? '').toString(),
    cartas:
        m['cards'] is List
            ? (m['cards'] as List)
                .whereType<Map>()
                .map((e) => DeckCardEntry.fromMap(Map<String, dynamic>.from(e)))
                .toList()
            : const [],
    retirado: m['dropped'] == true,
  );

  JugadorTorneo get jugador =>
      JugadorTorneo(id: uid, nombre: nombre, retirado: retirado);
}

class DueloDoc {
  final String id;
  final String fase;
  final int ronda;
  final int mesa;
  final String aUid;
  final String aNombre;
  final String? bUid;
  final String? bNombre;
  final int? scoreA;
  final int? scoreB;

  /// Quién cargó el marcador que está a la espera de confirmación.
  final String reportadoPor;
  final bool confirmado;

  const DueloDoc({
    required this.id,
    required this.fase,
    required this.ronda,
    required this.mesa,
    required this.aUid,
    required this.aNombre,
    this.bUid,
    this.bNombre,
    this.scoreA,
    this.scoreB,
    this.reportadoPor = '',
    this.confirmado = false,
  });

  static String idDe(String fase, int ronda, int mesa) =>
      '${fase == 'top' ? 't' : 's'}${ronda.toString().padLeft(2, '0')}_'
      '${mesa.toString().padLeft(3, '0')}';

  factory DueloDoc.fromMap(String id, Map<String, dynamic> m) => DueloDoc(
    id: id,
    fase: (m['phase'] ?? 'suizo').toString(),
    ronda: _entero(m['round'], 1),
    mesa: _entero(m['table'], 1),
    aUid: (m['aUid'] ?? '').toString(),
    aNombre: (m['aName'] ?? '').toString(),
    bUid: m['bUid'] as String?,
    bNombre: m['bName'] as String?,
    scoreA: (m['scoreA'] as num?)?.toInt(),
    scoreB: (m['scoreB'] as num?)?.toInt(),
    reportadoPor: (m['reportedBy'] ?? '').toString(),
    confirmado: m['confirmed'] == true,
  );

  bool get esBye => bUid == null;
  bool get tieneMarcador => scoreA != null && scoreB != null;
  bool juega(String? uid) => uid != null && (uid == aUid || uid == bUid);

  /// Tiene un marcador cargado que el rival aún no confirma.
  bool get esperaConfirmacion => !esBye && tieneMarcador && !confirmado;

  DueloTorneo get dominio => DueloTorneo(
    fase: fase,
    ronda: ronda,
    mesa: mesa,
    a: aUid,
    b: bUid,
    scoreA: scoreA,
    scoreB: scoreB,
    confirmado: confirmado,
  );
}

/// Qué puede hacer el organizador ahora, según el estado y los duelos.
class PasoTorneo {
  /// Duelos de la ronda en curso (suiza o de llave).
  final List<DueloDoc> rondaEnCurso;

  /// Todos los duelos de la ronda en curso están cerrados.
  final bool rondaCerrada;

  /// Rondas suizas que se jugarán en total.
  final int rondasSuizas;

  /// Tamaño real del top (0 si no hay o no alcanzan los jugadores).
  final int top;

  const PasoTorneo({
    required this.rondaEnCurso,
    required this.rondaCerrada,
    required this.rondasSuizas,
    required this.top,
  });

  factory PasoTorneo.de(
    Torneo t,
    List<Inscrito> inscritos,
    List<DueloDoc> duelos,
  ) {
    final enTop = t.estado == EstadoTorneo.top;
    final ronda = enTop ? t.rondaTop : t.rondaActual;
    final actual =
        duelos
            .where((d) => d.fase == (enTop ? 'top' : 'suizo') && d.ronda == ronda)
            .toList()
          ..sort((a, b) => a.mesa.compareTo(b.mesa));
    final activos = inscritos.where((i) => !i.retirado).length;
    var top = t.topCut;
    while (top > 1 && top > activos) {
      top ~/= 2;
    }
    return PasoTorneo(
      rondaEnCurso: actual,
      rondaCerrada: actual.isNotEmpty && actual.every((d) => d.dominio.cerrado),
      rondasSuizas:
          t.rondasSuizas > 0 ? t.rondasSuizas : rondasSugeridas(inscritos.length),
      top: top < 2 ? 0 : top,
    );
  }
}

/// El siguiente paso de un torneo en curso, ya decidido: qué duelos crear y
/// qué cambia en el documento del torneo.
class AccionTorneo {
  /// Fase y número de la ronda que se crea ('suizo' o 'top'); null al cerrar.
  final String? fase;
  final int ronda;
  final List<Emparejamiento> pares;

  /// Campos del torneo que cambian.
  final Map<String, dynamic> patch;

  /// Campeón, cuando el paso cierra el torneo.
  final JugadorTorneo? campeon;
  final String mensaje;

  const AccionTorneo({
    this.fase,
    this.ronda = 0,
    this.pares = const [],
    this.patch = const {},
    this.campeon,
    required this.mensaje,
  });

  bool get cierra => campeon != null;
}

/// Decide el siguiente paso con la ronda en curso cerrada: otra ronda suiza,
/// el paso a la llave, la siguiente ronda de la llave o el cierre.
/// Devuelve null si faltan resultados o el torneo no está en curso.
AccionTorneo? siguienteAccion(
  Torneo t,
  List<Inscrito> inscritos,
  List<DueloDoc> duelos,
) {
  final paso = PasoTorneo.de(t, inscritos, duelos);
  if (!paso.rondaCerrada) return null;
  final nombres = {for (final i in inscritos) i.uid: i.nombre};
  final jugadores = [for (final i in inscritos) i.jugador];
  final dominio = [for (final d in duelos) d.dominio];

  if (t.estado == EstadoTorneo.suizo) {
    if (t.rondaActual < paso.rondasSuizas) {
      final ronda = t.rondaActual + 1;
      return AccionTorneo(
        fase: 'suizo',
        ronda: ronda,
        pares: emparejarSuizo(jugadores, dominio),
        patch: {'currentRound': ronda},
        mensaje: 'Ronda $ronda generada',
      );
    }
    final tabla = calcularTabla(jugadores, dominio);
    if (paso.top == 0) {
      return AccionTorneo(
        campeon: tabla.first.jugador,
        mensaje: 'Torneo finalizado',
      );
    }
    return AccionTorneo(
      fase: 'top',
      ronda: 1,
      pares: llaveInicial([
        for (final f in tabla.where((f) => !f.jugador.retirado).take(paso.top))
          f.jugador.id,
      ]),
      patch: {'status': EstadoTorneo.top, 'topRound': 1, 'topCut': paso.top},
      mensaje: 'Top ${paso.top} generado',
    );
  }

  if (t.estado == EstadoTorneo.top) {
    final ronda = [for (final d in paso.rondaEnCurso) d.dominio];
    final siguiente = siguienteLlave(ronda);
    if (siguiente.isEmpty) {
      final campeon = ronda.single.ganador!;
      return AccionTorneo(
        campeon: JugadorTorneo(
          id: campeon,
          nombre: nombres[campeon] ?? 'Jugador',
        ),
        mensaje: 'Torneo finalizado',
      );
    }
    final n = t.rondaTop + 1;
    return AccionTorneo(
      fase: 'top',
      ronda: n,
      pares: siguiente,
      patch: {'topRound': n},
      mensaje: '${nombreRondaTop(siguiente.length)} generada',
    );
  }
  return null;
}
