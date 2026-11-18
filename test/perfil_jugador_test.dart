import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/domain/perfil_jugador.dart';
import 'package:myl_decks/models/card_myl.dart';
import 'package:myl_decks/models/deck.dart';
import 'package:myl_decks/models/inventory.dart';
import 'package:myl_decks/models/torneo.dart';

CardMyL _carta(String id, String tipo, List<Map<String, dynamic>> habs) =>
    CardMyL.fromMap({
      'nombre': id,
      'tipo': tipo,
      'coste': 2,
      'habilidades': habs,
    }, id);

DueloDoc _duelo(
  String fase,
  int ronda,
  int mesa,
  String a,
  String? b,
  int sa,
  int sb,
) => DueloDoc.fromMap(DueloDoc.idDe(fase, ronda, mesa), {
  'phase': fase,
  'round': ronda,
  'table': mesa,
  'aUid': a,
  'aName': a,
  'bUid': b,
  'bName': b,
  'scoreA': sa,
  'scoreB': sb,
  'confirmed': true,
});

void main() {
  test('mazos: perfiles, razas, cartas frecuentes y estilo', () {
    final remocion = _carta('Rayo', 'Talismán', [
      {
        'accion': 'destruir',
        'cuando': 'al_jugar',
        'objetivo': {'quien': 'oponente', 'zona': 'en_juego'},
      },
    ]);
    final furia = _carta('Berserker', 'Aliado', [
      {'accion': 'furia', 'cuando': 'continua'},
    ]);
    final cartas = {remocion.id: remocion, furia.id: furia};
    Deck mazo(String id, String raza, String carta, int copias) => Deck(
      id: id,
      ownerId: 'u',
      name: id,
      race: raza,
      cards: [
        DeckCardEntry(
          cardId: carta,
          name: carta,
          count: copias,
          coste: carta == 'Rayo' ? 4 : 1,
          tipo: cartas[carta]!.tipo,
        ),
        const DeckCardEntry(name: 'Oro', count: 15, tipo: 'Oro'),
      ],
    );
    final r = resumirMazos([
      mazo('a', 'Dragón', 'Rayo', 30),
      mazo('b', 'Dragón', 'Rayo', 30),
      mazo('c', 'Faraón', 'Berserker', 30),
      Deck(id: 'vacio', ownerId: 'u', name: 'vacío'),
    ], resolver: (e) => cartas[e.cardId]);
    expect(r.mazos, 3, reason: 'el mazo vacío no cuenta');
    expect(r.porPerfil, {'Control': 2, 'Agro': 1});
    expect(r.razas.first.key, 'Dragón');
    expect(r.razas.first.value, 2);
    expect(r.cartasFrecuentes.first.key, 'Rayo');
    expect(r.cartasFrecuentes.any((e) => e.key == 'Oro'), isFalse);
    expect(r.estilo, 'Juegas sobre todo Control');
    expect(r.rolesFavoritos.first, 'remocion');
    expect(r.indiceMedio, inInclusiveRange(0, 100));
  });

  test('colección: copias, asignadas y por edición', () {
    final r = resumirColeccion([
      InventoryItem.fromMap('a', {
        'name': 'A',
        'edition': 'Espada Sagrada',
        'total': 5,
        'allocations': {'d1': 2},
      }),
      InventoryItem.fromMap('b', {
        'name': 'B',
        'edition': 'Helénica',
        'total': 1,
      }),
      InventoryItem.fromMap('c', {'name': 'C', 'total': 0}),
    ]);
    expect(r.copias, 6);
    expect(r.cartasDistintas, 2);
    expect(r.asignadas, 2);
    expect(r.libres, 4);
    expect(r.porEdicion.first.key, 'Espada Sagrada');
  });

  test('desafío: cuenta solo partidas terminadas, por nivel', () {
    final r = resumirDesafios([
      {
        'status': 'terminado',
        'nivel': 5,
        'resultado': {'ganadorLado': 0, 'nivelIa': 5},
      },
      {
        'status': 'terminado',
        'nivel': 5,
        'resultado': {'ganadorLado': 1},
      },
      {
        'status': 'terminado',
        'nivel': 2,
        'resultado': {'ganadorLado': 0},
      },
      {'status': 'abandonado', 'nivel': 5},
      {
        'status': 'terminado',
        'modo': 'duda',
        'resultado': {'ganadorLado': 0},
      },
    ]);
    expect(r.jugadas, 3);
    expect(r.ganadas, 2);
    expect(r.porNivel[5], (2, 1));
    expect(r.porNivel[2], (1, 1));
    expect(r.mejorNivelVencido, 5);
  });

  test('torneo: posición, récord con llave y título', () {
    final torneo = Torneo.fromMap('t', {
      'name': 'Copa',
      'ownerUid': 'org',
      'status': 'finalizado',
      'championUid': 'yo',
    });
    const inscritos = [
      Inscrito(uid: 'yo', nombre: 'Yo', deckNombre: 'Mi mazo', raza: 'Dragón'),
      Inscrito(uid: 'b', nombre: 'B'),
      Inscrito(uid: 'c', nombre: 'C'),
    ];
    final duelos = [
      _duelo('suizo', 1, 1, 'yo', 'b', 2, 0),
      _duelo('suizo', 1, 2, 'c', null, 2, 0),
      _duelo('suizo', 2, 1, 'yo', 'c', 2, 1),
      _duelo('suizo', 2, 2, 'b', null, 2, 0),
      _duelo('top', 1, 1, 'yo', 'c', 2, 1),
    ];
    final p = participacionEn(torneo, inscritos, duelos, 'yo');
    expect(p.posicion, 1);
    expect(p.jugadores, 3);
    expect((p.ganados, p.empatados, p.perdidos), (3, 0, 0));
    expect(p.campeon, isTrue);
    expect(p.raza, 'Dragón');
    // El bye no cuenta como duelo jugado.
    final c = participacionEn(torneo, inscritos, duelos, 'c');
    expect((c.ganados, c.empatados, c.perdidos), (0, 0, 2));
    expect(c.posicion, 2);
    expect(c.campeon, isFalse);

    final total =
        const RecordCompetitivo(2, 1, 0) + const RecordCompetitivo(1, 0, 3);
    expect(total.duelos, 7);
    expect(total.victorias, closeTo(3 / 7, 1e-9));
    expect(const RecordCompetitivo(0, 0, 0).victorias, isNull);
  });
}
