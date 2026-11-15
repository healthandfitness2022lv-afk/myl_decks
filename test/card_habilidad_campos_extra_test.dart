import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/models/card_habilidad.dart';

/// Lo que programa el agente con campos que el editor no conoce debe
/// sobrevivir a abrir y guardar la carta.
void main() {
  test('campos desconocidos sobreviven fromMap → toMap', () {
    final m = {
      'featureId': 'gen_cambiarRaza',
      'featureName': 'Cambiar raza',
      'accion': 'cambiarRaza',
      'cuando': 'al_jugar',
      'arquetipoNuevo': 'Drácula',
      'porCadaRaza': 'Faerie',
      'costo': {
        'desterrarMano': 1,
        'filtro': {
          'tipos': ['Arma'],
        },
      },
      'objetivo': {'quien': 'propio', 'mismoValor': 'coste'},
      'luego': [
        {
          'accion': 'modificarFuerza',
          'relacion': 'si_afectada_cumple',
          'filtroAfectada': {'combate': true},
          'anulaAnulacion': true,
        },
      ],
    };
    final h = CardHabilidad.fromMap(Map<String, dynamic>.from(m)).toMap();
    expect(h['arquetipoNuevo'], 'Drácula');
    expect(h['porCadaRaza'], 'Faerie');
    expect(h['costo']['desterrarMano'], 1);
    expect(h['costo']['filtro'], {
      'tipos': ['Arma'],
    });
    expect(h['objetivo']['mismoValor'], 'coste');
    final luego = (h['luego'] as List).first as Map;
    expect(luego['filtroAfectada'], {'combate': true});
    expect(luego['anulaAnulacion'], true);
    expect(CostoHabilidad.fromMap(m['costo']).esGratis, isFalse);
  });

  test('acciones nuevas se leen y se escriben', () {
    for (final a in ['copiarHabilidad', 'convertirEnCopia', 'cancelarHabilidad']) {
      expect(Accion.parse(a).name, a);
    }
  });
}
