import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/models/card_habilidad.dart';

/// Lo que programa el agente para Faraón guerrero, Dragón y Titán Minotauro
/// debe sobrevivir a abrir y guardar la carta en el editor.
void main() {
  test('campos de Dragón / Titán sobreviven fromMap → toMap', () {
    final m = {
      'featureId': 'gen_generarOro',
      'featureName': 'Generar oro',
      'accion': 'generarOro',
      'cuando': 'propia_entra',
      'fase': 'vigilia',
      'turno': 'propio',
      'condicion': {
        'tipo': 'atacantes_arquetipo',
        'op': '>=',
        'valor': 1,
        'arquetipo': 'Guerrero',
      },
      'costo': {},
      'objetivo': {
        'quien': 'oponente',
        'tipos': ['Aliado'],
        'zona': 'en_juego',
        'seleccion': 'elige',
        'combate': true,
        'coste': {
          'op': '<=',
          'valor': 0,
          'segun': 'aliados_arquetipo',
          'arquetipo': 'Minotauro',
        },
      },
      'cantidad': 1,
      'valor': 2,
      'duracion': 'instantaneo',
      'opcional': false,
      'limitePorTurno': 0,
      'disparoTipos': ['Aliado'],
      'disparoRaza': 'Dragón',
      'disparoCosteMin': 3,
      'soloParaTipos': ['Aliado'],
      'soloParaRaza': 'Dragón',
      'soloParaCosteMin': 4,
      'grupoElegir': 'luz',
      'vetaCarta': true,
      'luego': [
        {
          'accion': 'botar',
          'relacion': 'si_afectada_cumple',
          'filtroAfectada': {
            'tipos': ['Oro', 'Aliado'],
          },
          'grupoElegir': 'cuerno',
          'objetivo': {'quien': 'oponente'},
          'cantidad': 2,
        },
      ],
    };
    final h = CardHabilidad.fromMap(Map<String, dynamic>.from(m));
    final salida = h.toMap();
    expect(salida['condicion']['tipo'], 'atacantes_arquetipo');
    expect(salida['condicion']['arquetipo'], 'Guerrero');
    expect(salida['objetivo']['combate'], true);
    expect(salida['objetivo']['coste']['segun'], 'aliados_arquetipo');
    expect(salida['objetivo']['coste']['arquetipo'], 'Minotauro');
    expect(salida['disparoCosteMin'], 3);
    expect(salida['soloParaCosteMin'], 4);
    expect(salida['grupoElegir'], 'luz');
    expect(salida['vetaCarta'], true);
    final luego = salida['luego'][0] as Map;
    expect(luego['filtroAfectada']['tipos'], ['Oro', 'Aliado']);
    expect(luego['grupoElegir'], 'cuerno');
  });
}
