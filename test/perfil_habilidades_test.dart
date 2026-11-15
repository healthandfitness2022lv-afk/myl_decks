import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/domain/perfil_habilidades.dart';
import 'package:myl_decks/models/card_habilidad.dart';
import 'package:myl_decks/models/card_myl.dart';
import 'package:myl_decks/models/deck.dart';

CardMyL _carta(String id, String tipo, int coste, List<Map<String, dynamic>> habs, {List<String> viejas = const []}) =>
    CardMyL(
      id: id,
      nombre: id,
      tipo: tipo,
      coste: coste,
      rareza: '',
      edicion: '',
      habilidad: '',
      caracteristicasRaw: viejas,
      habilidades: [for (final h in habs) CardHabilidad.fromMap(h)],
    );

void main() {
  final magma = _carta('Dragón de Magma', 'Aliado', 4, [
    {
      'accion': 'destruir',
      'cuando': 'al_jugar',
      'objetivo': {'quien': 'oponente', 'zona': 'en_juego', 'tipos': ['Aliado']},
    },
  ]);
  final medjay = _carta('Guerrero Medjay', 'Aliado', 2, [
    {'accion': 'imbloqueable', 'cuando': 'continua'},
    {
      'accion': 'botar',
      'cuando': 'al_atacar',
      'cantidad': 1,
      'objetivo': {'quien': 'ambos', 'zona': 'en_juego'},
    },
  ]);
  final capa = _carta('Capa', 'Talismán', 2, [
    {
      'accion': 'barajar',
      'cuando': 'oponente_juega',
      'objetivo': {'quien': 'disparadora', 'zona': 'en_juego', 'tipos': ['Aliado']},
    },
  ]);
  final vieja = _carta('Sin programar', 'Aliado', 2, const [], viejas: ['Roba cartas']);

  test('categorías desde las habilidades', () {
    expect(categoriasDeCarta(magma), {'Remoción'});
    expect(categoriasDeCarta(medjay), containsAll(['Agresión (Furia / Imbloqueable)', 'Daño directo (botar)']));
    expect(categoriasDeCarta(capa), containsAll(['Remoción', 'Respuesta']));
  });

  test('perfil del mazo y cartas sin programar', () {
    final cartas = {for (final c in [magma, medjay, capa, vieja]) c.id: c};
    final deck = Deck(
      id: 'x',
      ownerId: 'u',
      name: 'Prueba',
      cards: [
        const DeckCardEntry(cardId: 'Dragón de Magma', name: 'Dragón de Magma', count: 3, coste: 4, tipo: 'Aliado'),
        const DeckCardEntry(cardId: 'Capa', name: 'Capa', count: 2, coste: 2, tipo: 'Talismán'),
        const DeckCardEntry(cardId: 'Sin programar', name: 'Sin programar', count: 1, coste: 2, tipo: 'Aliado'),
      ],
    );
    final perfil = calcularPerfilHabilidades(deck, resolver: (e) => cartas[e.cardId]);
    expect(perfil.porCategoria['Remoción'], 5);
    expect(perfil.porCategoria['Respuesta'], 2);
    expect(perfil.sinProgramar, 1);
    expect(perfil.perfil, 'Control');
    expect(perfil.cartasPorCategoria['Remoción']!.map((e) => e.name), containsAll(['Dragón de Magma', 'Capa']));
  });
}
