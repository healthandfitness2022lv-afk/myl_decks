import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/models/card_habilidad.dart';
import 'package:myl_decks/models/card_myl.dart';

void main() {
  const destruir = CardHabilidad(
    featureId: 'f1',
    featureName: 'Destruir Aliado',
    accion: Accion.destruir,
    cuando: 'activada',
    fase: 'vigilia',
    condicion: CondicionHabilidad(tipo: 'aliados_propios', op: '>=', valor: 2),
    costo: CostoHabilidad(oros: 2),
    objetivo: ObjetivoHabilidad(
      quien: 'oponente',
      tipos: ['Aliado'],
      zona: 'linea_defensa',
      coste: Comparacion('<=', 2),
    ),
    limitePorTurno: 1,
  );

  test('ida y vuelta conserva todos los parámetros', () {
    final back = CardHabilidad.fromMap(destruir.toMap());
    expect(back.toMap(), destruir.toMap());
    expect(back.objetivo.coste.toString(), '≤ 2');
    expect(back.costo.oros, 2);
  });

  test('las propiedades guardan solo lo mínimo', () {
    const imb = CardHabilidad(
      featureId: 'f2',
      featureName: 'Imbloqueable',
      accion: Accion.imbloqueable,
    );
    expect(imb.toMap(), {
      'featureId': 'f2',
      'featureName': 'Imbloqueable',
      'accion': 'imbloqueable',
      'cuando': 'continua',
    });
  });

  test('acción desconocida se lee como otra', () {
    expect(Accion.parse('volar'), Accion.otra);
  });

  test('CardMyL lee y escribe habilidades', () {
    final card = CardMyL.fromMap({
      'nombre': 'Prueba',
      'tipo': 'Aliado',
      'coste': 2,
      'habilidades': [destruir.toMap()],
      'habilidadesRevisadas': true,
    }, 'c1');
    expect(card.habilidades.single.accion, Accion.destruir);
    expect(card.habilidadesRevisadas, isTrue);
    expect(card.toMap()['habilidades'], [destruir.toMap()]);
  });

  test('efectos luego: ida y vuelta y resumen (Abhartach)', () {
    const abhartach = CardHabilidad(
      featureId: 'f3',
      featureName: 'Desterrar Aliado',
      accion: Accion.desterrar,
      opcional: true,
      objetivo: ObjetivoHabilidad(
        quien: 'oponente',
        tipos: ['Aliado', 'Tótem'],
      ),
      luego: [
        EfectoLuego(
          accion: Accion.desterrar,
          objetivo: ObjetivoHabilidad(
            quien: 'oponente',
            zona: 'mazo',
            seleccion: 'todos',
            referencia: 'copias',
          ),
        ),
      ],
    );
    final back = CardHabilidad.fromMap(abhartach.toMap());
    expect(back.toMap(), abhartach.toMap());
    expect(back.luego.single.objetivo.referencia, 'copias');
    expect(back.resumen, contains('Luego (si se cumplió)'));
    expect(back.resumen, contains('copias de las afectadas'));
  });

  test('las notas por habilidad ya no se guardan', () {
    final h = CardHabilidad.fromMap({
      'featureId': 'x',
      'featureName': 'X',
      'accion': 'robar',
      'notas': 'vieja',
    });
    expect(h.toMap().containsKey('notas'), isFalse);
  });

  test('luego diferido a la Fase Final (Forma de Lince)', () {
    const lince = CardHabilidad(
      featureId: 'gen_mod_fuerza',
      featureName: 'Modificar fuerza',
      accion: Accion.modificarFuerza,
      valor: 3,
      duracion: 'hasta_fase_final',
      objetivo: ObjetivoHabilidad(quien: 'propio'),
      luego: [
        EfectoLuego(
          accion: Accion.robar,
          relacion: 'si_afectada_hizo_dano',
          momento: 'fase_final',
          objetivo: ObjetivoHabilidad(quien: 'propio'),
        ),
      ],
    );
    final back = CardHabilidad.fromMap(lince.toMap());
    expect(back.toMap(), lince.toMap());
    expect(back.luego.single.momento, 'fase_final');
    expect(
      back.resumen,
      contains('Luego (si la afectada hizo daño, en la Fase Final)'),
    );
  });

  test('disparadores según tipo de carta y costo pagar este Oro', () {
    final talisman = cuandoPara('Talismán').map((o) => o.id);
    expect(talisman, isNot(contains('continua')));
    expect(talisman, isNot(contains('al_salir_del_juego')));
    expect(cuandoPara('Oro').first.id, 'activada');
    const costo = CostoHabilidad(pagarEstaCarta: true);
    expect(CostoHabilidad.fromMap(costo.toMap()).pagarEstaCarta, isTrue);
    expect(costo.esGratis, isFalse);
    expect(costo.toString(), 'pagar este Oro');
  });

  test('propiedad con condición se guarda y se resume', () {
    const noAnulable = CardHabilidad(
      featureId: 'x',
      featureName: 'No Anulable',
      accion: Accion.noAnulable,
      turno: 'propio',
      condicion: CondicionHabilidad(
        tipo: 'aliados_propios',
        op: '>=',
        valor: 2,
      ),
    );
    final m = noAnulable.toMap();
    expect(m['turno'], 'propio');
    expect((m['condicion'] as Map)['valor'], 2);
    expect(CardHabilidad.fromMap(m).toMap(), m);
    expect(noAnulable.resumen, startsWith('No anulable (solo en tu turno'));
    // Sin condición sigue guardando lo mínimo.
    const simple = CardHabilidad(
      featureId: 'y',
      featureName: 'Imbloqueable',
      accion: Accion.imbloqueable,
    );
    expect(simple.toMap().containsKey('condicion'), isFalse);
  });

  test('campos para las notas de cartas (2026-11-08)', () {
    const nephre = CardHabilidad(
      featureId: 'gen_destruir',
      featureName: 'Destruir',
      accion: Accion.destruir,
      costo: CostoHabilidad(desterrarCementerioSegun: 'coste_objetivo'),
      objetivo: ObjetivoHabilidad(
        quien: 'oponente',
        tipos: ['Aliado'],
        zona: 'cementerio',
        zonas: ['cementerio', 'mazo'],
      ),
      cantidadSegun: 'oros_que_controla',
      luego: [
        EfectoLuego(
          accion: Accion.robar,
          opcional: true,
          condicion: CondicionHabilidad(
            tipo: 'oros_vs_oponente',
            op: '<=',
            valor: 0,
          ),
          costo: CostoHabilidad(pagarEstaCarta: true),
          cantidadSegun: 'coste_afectada',
          objetivo: ObjetivoHabilidad(quien: 'propio'),
        ),
      ],
    );
    final back = CardHabilidad.fromMap(nephre.toMap());
    expect(back.toMap(), nephre.toMap());
    expect(back.objetivo.todasLasZonas, ['cementerio', 'mazo']);
    expect(back.costo.esGratis, isFalse);
    expect(back.luego.single.condicion.tipo, 'oros_vs_oponente');
    expect(back.resumen, contains('tantas como oros controle ese jugador'));
    expect(Accion.parse('redirigir'), Accion.redirigir);
    expect(
      cuandoPara('Arma').map((o) => o.label),
      contains('Cuando su portador es declarado atacante'),
    );
  });

  test('el tipo de carta define qué se puede armar', () {
    // Talismán: nunca en juego.
    expect(accionPermitida(Accion.inmunidad, 'Talismán'), isFalse);
    expect(accionPermitida(Accion.imbloqueable, 'Talismán'), isFalse);
    expect(accionPermitida(Accion.botar, 'Talismán'), isTrue);
    expect(
      quienPara('Talismán', Accion.destruir).map((o) => o.id),
      isNot(contains('esta_carta')),
    );
    expect(
      quienPara('Talismán', Accion.jugarDesde).map((o) => o.id),
      contains('esta_carta'),
    );
    // Arma: "esta carta" es su portador; propiedades de Aliado al portador.
    expect(
      quienPara('Arma', Accion.modificarFuerza).first.label,
      'Su portador',
    );
    expect(accionPermitida(Accion.requisitoPortador, 'Arma'), isTrue);
    expect(accionPermitida(Accion.requisitoPortador, 'Aliado'), isFalse);
    expect(aplicaPorDefecto(Accion.imbloqueable), 'esta_carta');
    expect(aplicaPorDefecto(Accion.indestructible), 'el_arma');
    // Oro/Tótem: sin propiedades de Aliado.
    expect(accionPermitida(Accion.furia, 'Oro'), isFalse);
    expect(accionPermitida(Accion.guardian, 'Tótem'), isFalse);
    // Propiedad de Arma guarda a quién aplica.
    const capa = CardHabilidad(
      featureId: 'i',
      featureName: 'Imbloqueable',
      accion: Accion.imbloqueable,
      objetivo: ObjetivoHabilidad(quien: 'esta_carta'),
    );
    expect(capa.toMap()['objetivo'], {'quien': 'esta_carta'});
  });

  test(
    'tipos de objetivo según acción y zona (no se destruyen Talismanes)',
    () {
      expect(
        tiposPara(Accion.destruir, ['en_juego']),
        isNot(contains('Talismán')),
      );
      expect(
        tiposPara(Accion.destruir, ['cementerio']),
        isNot(contains('Talismán')),
      );
      expect(tiposPara(Accion.desterrar, ['cementerio']), contains('Talismán'));
      expect(tiposPara(Accion.buscar, ['mazo']), contains('Talismán'));
      expect(
        tiposPara(Accion.ponerEnJuego, ['mazo']),
        isNot(contains('Talismán')),
      );
      expect(tiposPara(Accion.desterrar, ['linea_defensa']), ['Aliado']);
      expect(tiposPara(Accion.destruir, ['linea_apoyo']), ['Arma', 'Tótem']);
      expect(tiposPara(Accion.destruir, ['reserva_oro']), ['Oro']);
    },
  );

  test('costos de "esta carta" según el tipo', () {
    expect(costoPermitido('destruirEstaCarta', 'Talismán'), isFalse);
    expect(costoPermitido('desterrarEstaCarta', 'Talismán'), isFalse);
    expect(costoPermitido('destruirEstaCarta', 'Oro'), isTrue);
    expect(costoPermitido('pagarEstaCarta', 'Aliado'), isFalse);
    expect(costoPermitido('pagarEstaCarta', 'Oro'), isTrue);
  });

  test('campos de la 2ª tanda de notas', () {
    const cleopatra = CardHabilidad(
      featureId: 'gen_perder_habilidad',
      featureName: 'Perder habilidad',
      accion: Accion.perderHabilidad,
      cuando: 'continua',
      objetivo: ObjetivoHabilidad(
        quien: 'cualquiera',
        tipos: ['Aliado'],
        seleccion: 'todos',
        nombrarRaza: true,
        excluirRazas: ['Faraón'],
      ),
    );
    final back = CardHabilidad.fromMap(cleopatra.toMap());
    expect(back.toMap(), cleopatra.toMap());
    expect(back.resumen, contains('raza nombrada al entrar (no Faraón)'));

    const ay = CostoHabilidad(desterrarAliados: 1);
    expect(CostoHabilidad.fromMap(ay.toMap()).desterrarAliados, 1);
    expect(ay.esGratis, isFalse);
    expect(ay.toString(), 'desterrar 1 de tus otros Aliados');

    const gran = CardHabilidad(
      featureId: 'a',
      featureName: 'Anulación',
      accion: Accion.anular,
      talismanVaA: 'destierro',
    );
    expect(CardHabilidad.fromMap(gran.toMap()).talismanVaA, 'destierro');

    expect(kModos[Accion.robar]!.map((o) => o.id), contains('fondo'));
    expect(cuandoPara('Arma').map((o) => o.id), contains('al_hacer_dano'));
    expect(
      cuandoPara('Oro').map((o) => o.id),
      contains('al_botar_por_oponente'),
    );
    expect(cuandoPara('Tótem').map((o) => o.id), isNot(contains('al_atacar')));
  });

  test('anular, inmunidad y restricción ofrecen Talismán', () {
    for (final a in [Accion.anular, Accion.inmunidad, Accion.restriccion]) {
      expect(tiposPara(a, ['en_juego']), contains('Talismán'));
    }
  });

  test('buscar en Cementerio o Mazo incluye Talismanes', () {
    expect(tiposPara(Accion.buscar, ['mazo']), contains('Talismán'));
    expect(tiposPara(Accion.buscar, ['cementerio']), contains('Talismán'));
    expect(
      tiposPara(Accion.buscar, ['mazo', 'cementerio']),
      contains('Talismán'),
    );
  });

  test('campos de la 3ª tanda de notas', () {
    const djoser = CardHabilidad(
      featureId: 'gen_mod_fuerza',
      featureName: 'Modificar fuerza',
      accion: Accion.modificarFuerza,
      cuando: 'continua',
      valor: 2,
      valorPorCada: 'arma_portada',
      objetivo: ObjetivoHabilidad(quien: 'esta_carta'),
    );
    expect(CardHabilidad.fromMap(djoser.toMap()).toMap(), djoser.toMap());
    expect(djoser.resumen, contains('por cada arma que porta'));

    const entra = CardHabilidad(
      featureId: 'gen_destruir',
      featureName: 'Destruir',
      accion: Accion.destruir,
      cuando: 'propia_entra',
      disparoTipos: ['Arma'],
    );
    expect(CardHabilidad.fromMap(entra.toMap()).disparoTipos, ['Arma']);

    const nudo = CardHabilidad(
      featureId: 'gen_perder_habilidad',
      featureName: 'Perder habilidad',
      accion: Accion.perderHabilidad,
      cuando: 'activada',
      usaQuien: 'oponente',
      costo: CostoHabilidad(oros: 2),
      costoAlternativo: CostoHabilidad(botar: 3),
    );
    final back = CardHabilidad.fromMap(nudo.toMap());
    expect(back.usaQuien, 'oponente');
    expect(back.costoAlternativo.botar, 3);
    expect(back.resumen, contains('pagar 2 oros o botar 3'));

    const roseta = CostoHabilidad(barajarMano: 1);
    expect(CostoHabilidad.fromMap(roseta.toMap()).barajarMano, 1);

    expect(accionPermitida(Accion.encarecer, 'Talismán'), isFalse);
    expect(accionPermitida(Accion.obligarBloqueo, 'Aliado'), isTrue);
    expect(accionPermitida(Accion.obligarBloqueo, 'Oro'), isFalse);
    expect(tiposPara(Accion.encarecer, ['en_juego']), contains('Talismán'));
    expect(
      kModos[Accion.restriccion]!.map((o) => o.id),
      contains('barajar_cementerio'),
    );
  });

  test('los luego guardan el modo (imbloqueable, indesterrable…)', () {
    const e = EfectoLuego(
      accion: Accion.otorgarPropiedad,
      modo: 'indesterrable',
      objetivo: ObjetivoHabilidad(referencia: 'afectadas'),
    );
    final back = EfectoLuego.fromMap(e.toMap());
    expect(back.modo, 'indesterrable');
    expect(back.resumen, contains('(indesterrable)'));
  });

  test('Kawit: "Oros vs oponente" se lee en palabras', () {
    const c = CondicionHabilidad(tipo: 'oros_vs_oponente', op: '<=', valor: 0);
    expect(c.toString(), 'si tienes igual o menos oros que el oponente');
    expect(CondicionHabilidad.fromMap(c.toMap()).op, '<=');
  });
}
