// Lo que la app debe conservar de las cartas programadas el 2026-11-17
// (Helénica y Espada Sagrada) y la regla de copias de Draco Águila.
import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/domain/validation/deck_validator.dart';
import 'package:myl_decks/models/card_habilidad.dart';
import 'package:myl_decks/models/card_myl.dart';
import 'package:myl_decks/models/deck.dart';

CardMyL _carta(String id, String nombre, String texto) => CardMyL(
  id: id,
  nombre: nombre,
  tipo: 'Aliado',
  coste: 1,
  rareza: '',
  edicion: 'Espada Sagrada',
  habilidad: '',
  habilidadTextoIA: texto,
  raza: 'Dragón',
);

void main() {
  test('la condición conserva los campos del simulador al guardar', () {
    final mapa = {
      'featureId': 'gen_furia',
      'featureName': 'Puede atacar al entrar si controlas otro Minotauro',
      'accion': 'furia',
      'cuando': 'continua',
      'condicion': {
        'tipo': 'aliados_arquetipo',
        'op': '>=',
        'valor': 2,
        'arquetipo': 'Minotauro',
        'incluyeFuente': true,
      },
    };
    final h = CardHabilidad.fromMap(mapa);
    expect(h.condicion.extra, {'incluyeFuente': true});
    expect(h.toMap()['condicion'], mapa['condicion']);
    // Una condición que el editor no conoce (Heka: controla_nombre + nombre).
    final c = CondicionHabilidad.fromMap({
      'tipo': 'controla_nombre',
      'nombre': 'Heka',
    });
    expect(c.toMap()['nombre'], 'Heka');
  });

  test('"cuando juegas una carta" guarda el tipo que lo dispara', () {
    final mapa = {
      'featureId': 'gen_barajar',
      'featureName': 'Al jugar un Talismán',
      'accion': 'barajar',
      'cuando': 'propia_juega',
      'disparoTipos': ['Talismán'],
      'opcional': true,
      'limitePorTurno': 1,
      'objetivo': {
        'quien': 'oponente',
        'tipos': ['Aliado'],
        'coste': {'op': '<=', 'valor': 0, 'segun': 'coste_disparadora'},
      },
    };
    final back = CardHabilidad.fromMap(mapa).toMap();
    expect(back['cuando'], 'propia_juega');
    expect(back['disparoTipos'], ['Talismán']);
    expect((back['objetivo'] as Map)['coste'], {
      'op': '<=',
      'valor': 0,
      'segun': 'coste_disparadora',
    });
    expect(kCuando.any((o) => o.id == 'propia_juega'), isTrue);
    expect(kCuando.any((o) => o.id == 'al_ser_destruido'), isTrue);
    expect(kCondiciones.any((o) => o.id == 'armas_propias'), isTrue);
  });

  test('campos del simulador en habilidad, costo y "luego" sobreviven', () {
    final mapa = {
      'featureId': 'gen_desterrar',
      'featureName': 'Destierra Goblins',
      'accion': 'desterrar',
      'cuando': 'al_jugar',
      'opcional': true,
      'cantidad': 99,
      'costo': {
        'destruirPropias': 1,
        'filtro': {
          'tipos': ['Arma'],
        },
      },
      'costoAlternativo': {'destruirAliados': 1, 'incluyeEstaCarta': true},
      'objetivo': {
        'quien': 'propio',
        'zona': 'cementerio',
        'arquetipo': 'Goblin',
        'distintoNombre': true,
      },
      'oponenteEligeMano': true,
      'privado': true,
      'disparoArquetipo': 'Musa',
      'porCadaFiltros': [
        {
          'tipos': ['Arma'],
        },
      ],
      'luego': [
        {
          'relacion': 'si_se_cumplio',
          'accion': 'modificarFuerza',
          'valor': 1,
          'valorPorCada': 'carta_afectada',
          'duracion': 'hasta_fase_final',
          'cantidad': 1,
          'objetivo': {'quien': 'esta_carta'},
        },
        {
          'relacion': 'siempre',
          'accion': 'restringirCombate',
          'modo': 'entra_atacando',
          'momento': 'fase_final',
          'cantidad': 1,
          'objetivo': {'quien': 'propio', 'referencia': 'afectadas'},
        },
      ],
    };
    final back = CardHabilidad.fromMap(mapa).toMap();
    expect(back['oponenteEligeMano'], true);
    expect(back['privado'], true);
    expect(back['disparoArquetipo'], 'Musa');
    expect(back['porCadaFiltros'], mapa['porCadaFiltros']);
    expect(back['costo'], mapa['costo']);
    expect(back['costoAlternativo'], mapa['costoAlternativo']);
    expect((back['objetivo'] as Map)['distintoNombre'], true);
    final luego = back['luego'] as List;
    expect((luego[0] as Map)['valorPorCada'], 'carta_afectada');
    expect((luego[1] as Map)['modo'], 'entra_atacando');
    expect((luego[1] as Map)['momento'], 'fase_final');
  });

  group('copias de Draco Águila', () {
    final aguila = _carta(
      'draco_aguila',
      'Draco Águila',
      'Puedes tener más de 3 Draco Águila\nen tu Mazo Castillo. Imbloqueable.',
    );
    final comun = _carta('draco', 'Draco Común', 'Imbloqueable.');
    Deck mazo(String id, String nombre) => Deck(
      id: 'm',
      ownerId: 'u',
      name: 'Águilas',
      cards: [DeckCardEntry(cardId: id, name: nombre, count: 6)],
    );
    bool excede(Deck d, {Map<String, int> ban = const {}}) => validateDeck(
      deck: d,
      catalogById: {'draco_aguila': aguila, 'draco': comun},
      catalogByName: const {},
      copyLimitsByKey: ban,
    ).issues.any((i) => i.code == 'COPIES_LIMIT');

    test('la carta que lo dice no tiene el tope de 3', () {
      expect(cartaSinLimiteDeCopias(aguila), isTrue);
      expect(cartaSinLimiteDeCopias(comun), isFalse);
      expect(excede(mazo('draco_aguila', 'Draco Águila')), isFalse);
      expect(excede(mazo('draco', 'Draco Común')), isTrue);
    });

    test('la Ban List manda si le fija un límite', () {
      expect(
        excede(
          mazo('draco_aguila', 'Draco Águila'),
          ban: const {'draco_aguila': 3},
        ),
        isTrue,
      );
    });
  });
}
