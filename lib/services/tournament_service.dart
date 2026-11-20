// lib/services/tournament_service.dart
//
// Acceso a Firestore de los torneos (`tournaments/{id}` + players + matches).
// Las reglas del juego (emparejar, tabla, llave) están en domain/torneo.
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/torneo/torneo.dart';
import '../models/deck.dart';
import '../models/torneo.dart';
import 'ban_list_service.dart';

class TorneoError implements Exception {
  final String mensaje;
  const TorneoError(this.mensaje);

  @override
  String toString() => mensaje;
}

/// Clave de formato de torneo que corresponde a un mazo.
String formatoDeMazo(Deck deck) {
  switch (deck.format) {
    case DeckFormat.racialLibre:
      return 'racial_libre';
    case DeckFormat.full:
      return 'full';
    case DeckFormat.racial:
      return 'racial_edicion';
  }
}

class TournamentService {
  TournamentService([FirebaseFirestore? db])
    : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('tournaments');

  DocumentReference<Map<String, dynamic>> ref(String id) => _col.doc(id);

  static String nuevoCodigo() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
  }

  // ── Lectura ───────────────────────────────────────────────────────────────
  List<Torneo> _lista(QuerySnapshot<Map<String, dynamic>> s) =>
      s.docs.map(Torneo.fromDoc).toList();

  /// Torneos públicos, del más próximo al más lejano.
  Stream<List<Torneo>> abiertos() => _col
      .where('visibility', isEqualTo: 'open')
      .orderBy('date')
      .snapshots()
      .map(_lista);

  Stream<List<Torneo>> queOrganizo(String uid) => _col
      .where('ownerUid', isEqualTo: uid)
      .orderBy('date')
      .snapshots()
      .map(_lista);

  Stream<List<Torneo>> dondeJuego(String uid) =>
      _col.where('playerUids', arrayContains: uid).snapshots().map(_lista);

  Future<List<Torneo>> jugadosPor(String uid) async =>
      _lista(await _col.where('playerUids', arrayContains: uid).get());

  Stream<Torneo?> torneo(String id) => ref(id).snapshots().map(
    (d) => d.exists ? Torneo.fromDoc(d) : null,
  );

  Stream<List<Inscrito>> inscritos(String id) => ref(id)
      .collection('players')
      .snapshots()
      .map(
        (s) =>
            s.docs.map((d) => Inscrito.fromMap(d.id, d.data())).toList()
              ..sort(
                (a, b) =>
                    a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
              ),
      );

  Stream<List<DueloDoc>> duelos(String id) => ref(id)
      .collection('matches')
      .snapshots()
      .map(
        (s) =>
            s.docs.map((d) => DueloDoc.fromMap(d.id, d.data())).toList()
              ..sort((a, b) => a.id.compareTo(b.id)),
      );

  Future<List<Inscrito>> leerInscritos(String id) async {
    final s = await ref(id).collection('players').get();
    return s.docs.map((d) => Inscrito.fromMap(d.id, d.data())).toList();
  }

  Future<List<DueloDoc>> leerDuelos(String id) async {
    final s = await ref(id).collection('matches').get();
    return s.docs.map((d) => DueloDoc.fromMap(d.id, d.data())).toList();
  }

  Future<Torneo?> porCodigo(String codigo) async {
    final limpio = codigo.trim().toUpperCase();
    if (limpio.isEmpty) return null;
    final s = await _col.where('inviteCode', isEqualTo: limpio).limit(1).get();
    return s.docs.isEmpty ? null : Torneo.fromDoc(s.docs.first);
  }

  // ── Crear y editar ────────────────────────────────────────────────────────
  /// Crea el torneo y congela la Ban List vigente de su formato.
  Future<String> crear({
    required String ownerUid,
    required String ownerNombre,
    required String nombre,
    required String descripcion,
    required String lugar,
    required DateTime fecha,
    required String formato,
    required String visibilidad,
    required int rondasSuizas,
    required int topCut,
    required int cupo,
  }) async {
    final ban = await BanListService.forRoundFormatKey(formato).fetchSnapshot();
    final doc = _col.doc();
    await doc.set({
      'name': nombre.trim(),
      'description': descripcion.trim(),
      'place': lugar.trim(),
      'date': Timestamp.fromDate(fecha),
      'ownerUid': ownerUid,
      'ownerName': ownerNombre,
      'visibility': visibilidad,
      'inviteCode': nuevoCodigo(),
      'format': formato,
      'bestOf': 3,
      'swissRounds': rondasSuizas,
      'topCut': topCut,
      'maxPlayers': cupo,
      'status': EstadoTorneo.inscripcion,
      'currentRound': 0,
      'topRound': 0,
      'playerUids': <String>[],
      'banListSnapshot': ban,
      'banListCapturedAt': FieldValue.serverTimestamp(),
      'banListSource': 'current',
      'banListFormat': formato,
      'banListEntryCount': ban.length,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  /// Edita los datos generales. El formato solo cambia sin inscritos (cada
  /// lista se validó contra el formato y la Ban List de ese momento).
  Future<void> editar(
    Torneo t, {
    required String nombre,
    required String descripcion,
    required String lugar,
    required DateTime fecha,
    required String formato,
    required String visibilidad,
    required int rondasSuizas,
    required int topCut,
    required int cupo,
  }) async {
    final cambiaFormato = formato != t.formato;
    if (cambiaFormato && t.playerUids.isNotEmpty) {
      throw const TorneoError(
        'No se puede cambiar el formato con jugadores inscritos.',
      );
    }
    final patch = <String, dynamic>{
      'name': nombre.trim(),
      'description': descripcion.trim(),
      'place': lugar.trim(),
      'date': Timestamp.fromDate(fecha),
      'visibility': visibilidad,
      'maxPlayers': cupo,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (t.enInscripcion) {
      patch['swissRounds'] = rondasSuizas;
      patch['topCut'] = topCut;
    }
    if (cambiaFormato) {
      final ban =
          await BanListService.forRoundFormatKey(formato).fetchSnapshot();
      patch.addAll({
        'format': formato,
        'banListSnapshot': ban,
        'banListCapturedAt': FieldValue.serverTimestamp(),
        'banListFormat': formato,
        'banListEntryCount': ban.length,
      });
    }
    await ref(t.id).update(patch);
  }

  /// Borra un torneo que no ha empezado.
  Future<void> eliminar(Torneo t) async {
    if (!t.enInscripcion) {
      throw const TorneoError('Solo se puede borrar un torneo sin empezar.');
    }
    final jugadores = await ref(t.id).collection('players').get();
    final batch = _db.batch();
    for (final d in jugadores.docs) {
      batch.delete(d.reference);
    }
    batch.delete(ref(t.id));
    await batch.commit();
  }

  // ── Inscripción ───────────────────────────────────────────────────────────
  /// Inscribe (o cambia la lista) con una copia congelada del mazo.
  Future<void> inscribir({
    required String torneoId,
    required String uid,
    required String nombre,
    required Deck deck,
  }) async {
    final t = ref(torneoId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(t);
      if (!snap.exists) throw const TorneoError('El torneo ya no existe.');
      final torneo = Torneo.fromDoc(snap);
      if (!torneo.enInscripcion) {
        throw const TorneoError('La inscripción está cerrada.');
      }
      if (!torneo.participa(uid) && torneo.lleno) {
        throw const TorneoError('El torneo ya completó su cupo.');
      }
      tx.set(t.collection('players').doc(uid), {
        'uid': uid,
        'name': nombre,
        'deckId': deck.id,
        'deckName': deck.name,
        'race': deck.race ?? '',
        'cards': deck.cards.map((e) => e.toMap()).toList(),
        'dropped': false,
        'registeredAt': FieldValue.serverTimestamp(),
      });
      tx.update(t, {
        'playerUids': FieldValue.arrayUnion([uid]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> desinscribir(String torneoId, String uid) async {
    final t = ref(torneoId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(t);
      if (!snap.exists) return;
      if (!Torneo.fromDoc(snap).enInscripcion) {
        throw const TorneoError(
          'El torneo ya empezó: pide al organizador que te retire.',
        );
      }
      tx.delete(t.collection('players').doc(uid));
      tx.update(t, {
        'playerUids': FieldValue.arrayRemove([uid]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Retira a un jugador de un torneo en curso: no se le empareja más.
  Future<void> retirar(String torneoId, String uid, {bool retirado = true}) =>
      ref(
        torneoId,
      ).collection('players').doc(uid).update({'dropped': retirado});

  // ── Rondas ────────────────────────────────────────────────────────────────
  Map<String, dynamic> _dueloMap(
    String fase,
    int ronda,
    int mesa,
    Emparejamiento p,
    Map<String, String> nombres,
  ) => {
    'phase': fase,
    'round': ronda,
    'table': mesa,
    'aUid': p.a,
    'aName': nombres[p.a] ?? 'Jugador',
    'bUid': p.b,
    'bName': p.b == null ? null : (nombres[p.b] ?? 'Jugador'),
    // El bye queda cerrado desde que se crea.
    if (p.b == null) ...{'scoreA': 2, 'scoreB': 0, 'confirmed': true},
    if (p.b != null) 'confirmed': false,
    'createdAt': FieldValue.serverTimestamp(),
  };

  Future<void> _escribirRonda(
    String torneoId,
    String fase,
    int ronda,
    List<Emparejamiento> pares,
    Map<String, String> nombres,
    Map<String, dynamic> patchTorneo,
  ) async {
    final batch = _db.batch();
    final t = ref(torneoId);
    for (var i = 0; i < pares.length; i++) {
      batch.set(
        t.collection('matches').doc(DueloDoc.idDe(fase, ronda, i + 1)),
        _dueloMap(fase, ronda, i + 1, pares[i], nombres),
      );
    }
    batch.update(t, {
      ...patchTorneo,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// Cierra la inscripción y genera la primera ronda suiza.
  Future<void> iniciar(Torneo t) async {
    if (!t.enInscripcion) throw const TorneoError('El torneo ya empezó.');
    final inscritos = await leerInscritos(t.id);
    if (inscritos.length < 2) {
      throw const TorneoError('Se necesitan al menos 2 inscritos.');
    }
    final pares = emparejarSuizo([for (final i in inscritos) i.jugador], const []);
    await _escribirRonda(
      t.id,
      'suizo',
      1,
      pares,
      {for (final i in inscritos) i.uid: i.nombre},
      {
        'status': EstadoTorneo.suizo,
        'currentRound': 1,
        'swissRounds':
            t.rondasSuizas > 0
                ? t.rondasSuizas
                : rondasSugeridas(inscritos.length),
      },
    );
  }

  /// Avanza el torneo: siguiente ronda suiza, paso al top, siguiente ronda
  /// de la llave o cierre con campeón. Exige la ronda en curso cerrada.
  Future<String> avanzar(Torneo t) async {
    if (t.enInscripcion || t.finalizado) {
      throw const TorneoError('El torneo no está en curso.');
    }
    final inscritos = await leerInscritos(t.id);
    final duelos = await leerDuelos(t.id);
    final accion = siguienteAccion(t, inscritos, duelos);
    if (accion == null) {
      throw const TorneoError('Faltan resultados por confirmar en esta ronda.');
    }
    if (accion.cierra) {
      await _finalizar(t.id, accion.campeon!);
    } else {
      await _escribirRonda(
        t.id,
        accion.fase!,
        accion.ronda,
        accion.pares,
        {for (final i in inscritos) i.uid: i.nombre},
        accion.patch,
      );
    }
    return accion.mensaje;
  }

  Future<void> _finalizar(String torneoId, JugadorTorneo campeon) =>
      ref(torneoId).update({
        'status': EstadoTorneo.finalizado,
        'championUid': campeon.id,
        'championName': campeon.nombre,
        'finishedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  // ── Resultados ────────────────────────────────────────────────────────────
  DocumentReference<Map<String, dynamic>> _duelo(String torneoId, String id) =>
      ref(torneoId).collection('matches').doc(id);

  /// Un jugador carga el marcador; queda a la espera del rival.
  /// [organizador] true lo deja confirmado de inmediato.
  Future<void> reportar({
    required String torneoId,
    required DueloDoc duelo,
    required int scoreA,
    required int scoreB,
    required String uid,
    bool organizador = false,
  }) async {
    if (duelo.esBye) throw const TorneoError('Un bye no lleva marcador.');
    if (!marcadorValido(scoreA, scoreB, permiteEmpate: duelo.fase != 'top')) {
      throw TorneoError(
        duelo.fase == 'top'
            ? 'En la llave el duelo debe terminar 2-0 o 2-1.'
            : 'Marcador inválido para un duelo al mejor de 3.',
      );
    }
    await _db.runTransaction((tx) async {
      final snap = await tx.get(_duelo(torneoId, duelo.id));
      final actual = DueloDoc.fromMap(snap.id, snap.data() ?? const {});
      if (actual.confirmado && !organizador) {
        throw const TorneoError(
          'El resultado ya está confirmado. Solo el organizador puede corregirlo.',
        );
      }
      tx.update(snap.reference, {
        'scoreA': scoreA,
        'scoreB': scoreB,
        'reportedBy': uid,
        'confirmed': organizador,
        'confirmedBy': organizador ? uid : null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// El rival de quien reportó acepta el marcador.
  Future<void> confirmar(String torneoId, DueloDoc duelo, String uid) async {
    await _db.runTransaction((tx) async {
      final snap = await tx.get(_duelo(torneoId, duelo.id));
      final actual = DueloDoc.fromMap(snap.id, snap.data() ?? const {});
      if (!actual.tieneMarcador) {
        throw const TorneoError('Aún no hay un marcador que confirmar.');
      }
      if (actual.reportadoPor == uid) {
        throw const TorneoError('Debe confirmarlo tu rival, no quien lo cargó.');
      }
      tx.update(snap.reference, {
        'confirmed': true,
        'confirmedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// El rival no está de acuerdo: se borra el marcador para cargarlo de nuevo.
  Future<void> rechazar(String torneoId, DueloDoc duelo) => _duelo(
    torneoId,
    duelo.id,
  ).update({
    'scoreA': FieldValue.delete(),
    'scoreB': FieldValue.delete(),
    'reportedBy': FieldValue.delete(),
    'confirmed': false,
    'updatedAt': FieldValue.serverTimestamp(),
  });
}
