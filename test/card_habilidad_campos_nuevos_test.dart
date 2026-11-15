import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/models/card_habilidad.dart';

/// Lo que programa el agente para Druida / Héroe debe sobrevivir a abrir y
/// guardar la carta en el editor.
void main() {
  test('campos nuevos sobreviven fromMap → toMap', () {
    final m = {
      'featureId': 'gen_destruir',
      'featureName': 'Destruir',
      'accion': 'destruir',
      'cuando': 'activada',
      'fase': 'vigilia',
      'turno': 'propio',
      'condicion': {
        'tipo': 'aliados_arquetipo',
        'op': '>=',
        'valor': 1,
        'arquetipo': 'Druida',
      },
      'costo': {
        'barajarEstaCarta': true,
        'moverEstaCartaAtaque': true,
        'orosSegun': 'coste_objetivo',
      },
      'objetivo': {
        'quien': 'oponente',
        'tipos': ['Aliado'],
        'zona': 'en_juego',
        'seleccion': 'mayor_fuerza',
        'arquetipo': 'Goblin',
        'excluirEstaCarta': true,
        'coste': {'op': '<=', 'valor': 0, 'segun': 'aliados_raza', 'raza': 'Héroe'},
      },
      'cantidad': 1,
      'valor': -1,
      'duracion': 'proximo_turno',
      'opcional': false,
      'limitePorTurno': 1,
      'grupoLimite': 'cathbadh',
      'valorPorCada': 'aliado_arquetipo',
      'porCadaArquetipo': 'Druida',
      'luego': [
        {
          'accion': 'barajar',
          'relacion': 'si_afectada_cumple',
          'filtroAfectada': {'arquetipo': 'Druida'},
          'objetivo': {'quien': 'propio', 'zona': 'cementerio'},
          'cantidad': 2,
          'valor': 0,
          'duracion': 'instantaneo',
        },
      ],
    };
    final h = CardHabilidad.fromMap(m).toMap();
    expect(h['condicion']['arquetipo'], 'Druida');
    expect(h['costo']['barajarEstaCarta'], true);
    expect(h['costo']['moverEstaCartaAtaque'], true);
    expect(h['costo']['orosSegun'], 'coste_objetivo');
    expect(h['objetivo']['seleccion'], 'mayor_fuerza');
    expect(h['objetivo']['arquetipo'], 'Goblin');
    expect(h['objetivo']['excluirEstaCarta'], true);
    expect(h['objetivo']['coste']['segun'], 'aliados_raza');
    expect(h['objetivo']['coste']['raza'], 'Héroe');
    expect(h['duracion'], 'proximo_turno');
    expect(h['grupoLimite'], 'cathbadh');
    expect(h['porCadaArquetipo'], 'Druida');
    expect(h['luego'][0]['filtroAfectada'], {'arquetipo': 'Druida'});
  });

  test('acción Elegir existe', () {
    expect(Accion.parse('elegir'), Accion.elegir);
  });

  test('mirar las de arriba, cambiar raza y convertir en Aliado', () {
    final mirar = CardHabilidad.fromMap({
      'accion': 'mirarTope',
      'cuando': 'al_jugar',
      'cantidad': 4,
      'valor': 1,
      'zonaDestino': 'mano',
      'restoA': 'mazo_fondo',
      'repartir': ['mano', 'cementerio', 'destierro'],
      'objetivo': {
        'quien': 'propio',
        'tipos': ['Oro', 'Aliado'],
        'arquetipo': 'Druida',
        'filtroSoloAliados': true,
      },
    }).toMap();
    expect(mirar['restoA'], 'mazo_fondo');
    expect(mirar['repartir'], ['mano', 'cementerio', 'destierro']);
    expect(mirar['objetivo']['filtroSoloAliados'], true);
    expect(mirar['zonaDestino'], 'mano');
    final alejandro = CardHabilidad.fromMap({
      'accion': 'ganarControl',
      'cuando': 'al_jugar',
      'objetivo': {'quien': 'oponente'},
      'luego': [
        {
          'accion': 'cambiarRaza',
          'relacion': 'si_se_cumplio',
          'razaNueva': 'Héroe',
          'objetivo': {'quien': 'propio', 'referencia': 'afectadas'},
        },
      ],
    }).toMap();
    expect(alejandro['luego'][0]['razaNueva'], 'Héroe');
    expect(Accion.parse('convertirEnAliado'), Accion.convertirEnAliado);
  });
}
