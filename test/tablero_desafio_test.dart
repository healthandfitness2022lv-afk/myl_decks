import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/screens/simulador/tablero_desafio.dart';

void main() {
  final carta = {
    'id': '1',
    'cartaId': '__test__',
    'nombre': 'Carta de prueba',
    'tipo': 'Aliado',
    'fuerza': 2,
  };
  Map<String, dynamic> lado(String nombre, {bool humano = false}) => {
    'nombre': nombre,
    'castillo': 40,
    'manoCantidad': humano ? 1 : 3,
    'mano': humano ? [carta] : <Map>[],
    'reserva': <Map>[],
    'pagado': <Map>[],
    'defensa': <Map>[],
    'ataque': <Map>[],
    'apoyo': <Map>[],
    'cementerio': 0,
    'destierro': 0,
  };
  final estado = {
    'turno': 1,
    'fase': 'vigilia',
    'activo': 0,
    'lados': [lado('Tú', humano: true), lado('IA')],
  };
  final decision = {
    'id': '1',
    'tipo': 'jugada',
    'titulo': 'Elige tu jugada',
    'opciones': [
      {'id': '0', 'titulo': 'pasar', 'tipoJugada': 'pasar'},
      {'id': '1', 'titulo': 'jugar Carta de prueba', 'tipoJugada': 'jugar', 'cartaUid': '1', 'cartaTipo': 'Aliado'},
    ],
  };

  for (final size in [const Size(400, 760), const Size(900, 430),
      const Size(320, 568), const Size(568, 320)]) {
    testWidgets('mesa visible sin errores en $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final enviados = <dynamic>[];
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: TableroDesafio(
          estado: estado,
          decision: decision,
          enviar: (valor) async { enviados.add(valor); },
        ),
      )));
      expect(tester.takeException(), isNull);
      // Celular en vertical: la mano rival va como número en su ficha.
      final telefono = size.width < size.height && size.width < 600;
      expect(find.textContaining(telefono ? 'Mano 3' : 'Mano rival · 3'), findsOneWidget);
      expect(find.text('Tu mano'), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
      await tester.tap(find.text('Acciones 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('jugar Carta de prueba'));
      await tester.pumpAndSettle();
      expect(enviados, ['1']); // sin costo: se juega de inmediato
    });
  }

  testWidgets('celular: una sola pantalla, cartas grandes y los botones al medio', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TableroDesafio(
      estado: estado, decision: decision, enviar: (_) async {},
    ))));
    expect(tester.takeException(), isNull);
    // «Una sola pantalla, sin scroll».
    expect(find.byType(Scrollable), findsNothing);
    // «No quiero tener que acercarme para ver qué carta es».
    final enMano = find.ancestor(of: find.text('Carta de prueba').last,
        matching: find.byType(AnimatedContainer)).first;
    expect(tester.getSize(enMano).height, greaterThan(95)); // antes ~70
    expect(tester.getRect(enMano).bottom, lessThan(800));
    // La instrucción y sus botones, entre los dos campos.
    final batalla = tester.getRect(find.text('Batalla'));
    expect(batalla.top, greaterThan(tester.getRect(find.text('Defensa rival')).bottom));
    expect(batalla.bottom, lessThan(tester.getRect(find.text('Tu mano')).top));
  });

  testWidgets('celular: mesa llena en combate cabe sin desplazar', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    List<Map<String, Object>> varias(int n, String prefijo) => [
      for (var i = 0; i < n; i++)
        {'id': '$prefijo-$i', 'cartaId': '__test__', 'nombre': 'Carta $i',
          'tipo': 'Aliado', 'fuerza': 2},
    ];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TableroDesafio(
      estado: {...estado, 'lados': [
        {...lado('Tú', humano: true), 'mano': varias(8, 'm'),
          'defensa': varias(5, 'd'), 'ataque': varias(3, 't'),
          'reserva': varias(6, 'r'), 'apoyo': varias(2, 'a')},
        {...lado('IA'), 'defensa': varias(5, 'rd'), 'ataque': varias(3, 'rt'),
          'apoyo': varias(2, 'ra')},
      ]},
      decision: decision, enviar: (_) async {},
    ))));
    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable), findsNothing);
    expect(tester.getRect(find.text('Batalla')).bottom, lessThan(640));
  });

  testWidgets('cancelar pago conserva la jugada y confirmar elige Oro', (tester) async {
    tester.view.physicalSize = const Size(400, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final enviados = <dynamic>[];
    final conPago = {
      ...decision,
      'oros': [
        {'id': 'oro-1', 'cartaId': '__oro__', 'nombre': 'Oro inicial'},
      ],
      'opciones': [
        {'id': '0', 'titulo': 'pasar', 'tipoJugada': 'pasar'},
        {'id': '1', 'titulo': 'jugar Carta de prueba', 'tipoJugada': 'jugar',
          'cartaUid': '1', 'cartaTipo': 'Aliado', 'cantidadPago': 1},
      ],
    };
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TableroDesafio(
      estado: estado, decision: conPago,
      enviar: (valor) async { enviados.add(valor); },
    ))));
    await tester.tap(find.text('Acciones 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('jugar Carta de prueba').last);
    await tester.pumpAndSettle();
    expect(find.text('Cancelar'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(enviados, isEmpty);
    await tester.tap(find.text('Acciones 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('jugar Carta de prueba').last);
    await tester.pumpAndSettle();
    // El pago se confirma en la barra, con el Oro ya marcado.
    expect(find.textContaining('toca 1 Oro'), findsOneWidget);
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(enviados, [{'id': '1', 'oros': ['oro-1']}]);
  });

  testWidgets('muchas cartas siguen dentro de la mesa sin desplazamiento', (tester) async {
    tester.view.physicalSize = const Size(568, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    List<Map<String, Object>> varias(int n, String prefijo) => [
      for (var i = 0; i < n; i++)
        {'id': '$prefijo-$i', 'cartaId': '__test__', 'nombre': 'Carta $i',
          'tipo': 'Aliado', 'fuerza': 2},
    ];
    final lleno = {
      ...estado,
      'lados': [
        {...lado('Tú', humano: true), 'mano': varias(10, 'm'),
          'defensa': varias(8, 'd'), 'reserva': varias(6, 'r'),
          'apoyo': varias(5, 'a')},
        {...lado('IA'), 'manoCantidad': 8,
          'defensa': varias(8, 'rd'), 'reserva': varias(6, 'rr')},
      ],
    };
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TableroDesafio(
      estado: lleno, decision: decision, enviar: (_) async {},
    ))));
    expect(tester.takeException(), isNull);
    expect(find.byType(ListView), findsNothing);
    expect(find.text('Tu mano'), findsOneWidget);
    expect(find.textContaining('RESERVA RIVAL ·'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^PAGADO · ')), findsOneWidget);
  });

  testWidgets('Piedra Roseta y Neferite activables se pueden tocar', (tester) async {
    tester.view.physicalSize = const Size(400, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final piedra = {'id': '27', 'cartaId': '__test__',
      'nombre': 'Piedra Roseta', 'tipo': 'Oro', 'fuerza': null};
    final neferite = {'id': '55', 'cartaId': '__test__',
      'nombre': 'Neferite I', 'tipo': 'Aliado', 'fuerza': 2};
    final enviados = <dynamic>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TableroDesafio(
      estado: {...estado, 'lados': [
        {...lado('Tú', humano: true), 'reserva': [piedra],
          'defensa': [neferite], 'mano': <Map>[]},
        lado('IA'),
      ]},
      decision: {'id': 'vigilia', 'tipo': 'jugada', 'titulo': 'Elige tu jugada',
        'opciones': [
          {'id': '0', 'tipoJugada': 'pasar', 'titulo': 'pasar'},
          {'id': '1', 'tipoJugada': 'activar', 'titulo': 'activar Piedra Roseta',
            'cartaUid': '27', 'cartaTipo': 'Oro'},
          {'id': '2', 'tipoJugada': 'activar', 'titulo': 'activar Neferite I',
            'cartaUid': '55', 'cartaTipo': 'Aliado'},
        ]},
      enviar: (valor) async { enviados.add(valor); },
    ))));
    await tester.pump();
    // En el celular el nombre también va escrito al pie de la carta.
    await tester.tap(find.text('Piedra Roseta').first);
    await tester.pump();
    await tester.tap(find.text('Neferite I').first);
    expect(enviados, ['1', '2']);
  });

  testWidgets('Cementerio y Destierro abren sus cartas', (tester) async {
    tester.view.physicalSize = const Size(900, 430);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final conPilas = {...estado, 'lados': [
      {...lado('Tú', humano: true), 'cementerio': 1,
        'cementerioCartas': [carta]},
      {...lado('IA'), 'destierro': 1, 'destierroCartas': [carta]},
    ]};
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TableroDesafio(
      estado: conPilas, decision: decision, enviar: (_) async {},
    ))));
    await tester.tap(find.text('Cementerio').last);
    await tester.pumpAndSettle();
    expect(find.text('Cementerio · 1 cartas'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Destierro').first);
    await tester.pumpAndSettle();
    expect(find.text('Destierro · 1 cartas'), findsOneWidget);
  });

  testWidgets('arrastrar un Aliado a Defensa propone la jugada', (tester) async {
    tester.view.physicalSize = const Size(900, 430);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final enviados = <dynamic>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TableroDesafio(
      estado: estado,
      decision: {'id': 'drag', 'tipo': 'jugada', 'titulo': 'Elige tu jugada',
        'opciones': [
          {'id': '0', 'tipoJugada': 'pasar', 'titulo': 'pasar'},
          {'id': '1', 'tipoJugada': 'jugar', 'titulo': 'jugar Carta de prueba',
            'cartaUid': '1', 'cartaTipo': 'Aliado', 'cantidadPago': 0},
        ]},
      enviar: (valor) async { enviados.add(valor); },
    ))));
    await tester.pump(const Duration(seconds: 1));
    final desde = tester.getCenter(find.text('Carta de prueba'));
    final hasta = tester.getCenter(find.text('Tu Defensa'));
    final gesto = await tester.startGesture(desde);
    await tester.pump(const Duration(milliseconds: 600));
    await gesto.moveTo(hasta);
    await tester.pump();
    await gesto.up();
    await tester.pumpAndSettle();
    expect(enviados, ['1']);
  });

  testWidgets('arrastrar un Aliado inicia batalla y pide los demás', (tester) async {
    tester.view.physicalSize = const Size(900, 430);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final aliados = [
      {...carta, 'nombre': 'Primer atacante', 'puedeAtacar': true},
      {...carta, 'id': '2', 'nombre': 'Segundo atacante', 'puedeAtacar': true},
    ];
    final enBatalla = {...estado, 'lados': [
      {...lado('Tú', humano: true), 'mano': <Map>[], 'defensa': aliados},
      lado('IA'),
    ]};
    final enviados = <dynamic>[];
    Widget mesa(Map<String, dynamic> d) => MaterialApp(home: Scaffold(body:
      TableroDesafio(estado: enBatalla, decision: d,
        enviar: (valor) async { enviados.add(valor); })));
    await tester.pumpWidget(mesa({
      'id': 'vigilia', 'tipo': 'jugada', 'opciones': [
        {'id': '0', 'tipoJugada': 'pasar', 'titulo': 'pasar'},
      ],
    }));
    await tester.pump(const Duration(seconds: 1));
    final gesto = await tester.startGesture(tester.getCenter(find.text('Primer atacante')));
    await tester.pump(const Duration(milliseconds: 600));
    await gesto.moveTo(tester.getCenter(find.text('Tu Línea de Ataque')));
    await tester.pump();
    await gesto.up();
    await tester.pumpAndSettle();
    expect(enviados, ['0']);

    await tester.pumpWidget(mesa({
      'id': 'atacantes', 'tipo': 'atacantes', 'titulo': 'Declara tus atacantes',
      'opciones': aliados,
    }));
    await tester.pumpAndSettle();
    // vUsU T9: con uno ya elegido, la barra dice cómo bajarlo.
    expect(find.text('Toca un atacante para bajarlo'), findsOneWidget);
    expect(find.text('Atacar con 1'), findsOneWidget);
    await tester.tap(find.text('Segundo atacante'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Atacar con 2'));
    expect(enviados, ['0', ['1', '2']]);
  });

  Future<List<dynamic>> mesaCon(WidgetTester tester, Map<String, dynamic> est,
      Map<String, dynamic> d) async {
    tester.view.physicalSize = const Size(900, 430);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final enviados = <dynamic>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TableroDesafio(
      estado: est, decision: d, enviar: (valor) async { enviados.add(valor); },
    ))));
    await tester.pump(const Duration(seconds: 1));
    return enviados;
  }

  testWidgets('descartar: se tocan las cartas de la mano y se confirma en la barra', (tester) async {
    final mano = [
      {...carta, 'id': 'a', 'nombre': 'Carta A'},
      {...carta, 'id': 'b', 'nombre': 'Carta B'},
    ];
    final enviados = await mesaCon(tester,
      {...estado, 'lados': [{...lado('Tú', humano: true), 'mano': mano}, lado('IA')]},
      {'id': 'd', 'tipo': 'descartes', 'titulo': 'Elige cartas para descartar',
        'cantidad': 1, 'opciones': mano});
    expect(find.text('Elige cartas para descartar (0/1)'), findsOneWidget);
    await tester.tap(find.text('Carta B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    expect(enviados, [['b']]);
  });

  testWidgets('bloquear: tu Aliado y luego el atacante', (tester) async {
    final mio = {...carta, 'id': 'm', 'nombre': 'Mi bloqueador'};
    final suyo = {...carta, 'id': 's', 'nombre': 'Su atacante'};
    final enviados = await mesaCon(tester,
      {...estado, 'activo': 1, 'fase': 'declaracion_bloqueo', 'lados': [
        {...lado('Tú', humano: true), 'mano': <Map>[], 'defensa': [mio]},
        {...lado('IA'), 'ataque': [suyo]},
      ]},
      {'id': 'b', 'tipo': 'bloqueos', 'titulo': 'Declara tus bloqueos',
        'opciones': [{'atacante': suyo, 'bloqueadores': [mio]}]});
    expect(find.text('Sin bloqueos'), findsOneWidget);
    await tester.tap(find.text('Mi bloqueador'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Su atacante'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bloquear (1)'));
    expect(enviados, [{'s': 'm'}]);
  });

  testWidgets('Rhiannon: se ven las 3 miradas y se toma un solo modo', (tester) async {
    final vistas = [
      {...carta, 'id': '1', 'nombre': 'Aine'},
      {...carta, 'id': '2', 'nombre': 'Red de Plata', 'tipo': 'Oro', 'fuerza': null},
      {...carta, 'id': '3', 'nombre': 'Cerridwen'},
    ];
    final enviados = await mesaCon(tester,
      {...estado, 'lados': [{...lado('Tú', humano: true), 'mano': <Map>[]}, lado('IA')]},
      {'id': 'r', 'tipo': 'mirar', 'titulo': 'Rhiannon: elige qué tomar',
        'opciones': vistas, 'modos': [
          {'titulo': 'Una · Oro', 'ids': ['2'], 'maximo': 1},
          {'titulo': 'Hasta 3 · Aliado', 'ids': ['1', '3'], 'maximo': 3},
        ]});
    expect(find.text('Aine'), findsOneWidget);
    expect(find.text('Red de Plata'), findsOneWidget);
    await tester.tap(find.text('Aine'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cerridwen'));
    await tester.pumpAndSettle();
    // Tocar el Oro cambia de modo: se empieza de nuevo con él.
    await tester.tap(find.text('Red de Plata'));
    await tester.pumpAndSettle();
    expect(find.text('Tomar 1'), findsOneWidget);
    await tester.tap(find.text('Red de Plata'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aine'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cerridwen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tomar 2'));
    expect(enviados, [['1', '3']]);
  });

  testWidgets('un Talismán se juega soltándolo en la mesa (Bola de Energía)', (tester) async {
    final bola = {...carta, 'id': 'b', 'nombre': 'Bola de Energía', 'tipo': 'Talismán', 'fuerza': null};
    final enviados = await mesaCon(tester,
      {...estado, 'activo': 1, 'fase': 'declaracion_ataque', 'lados': [
        {...lado('Tú', humano: true), 'mano': [bola]}, lado('IA')]},
      {'id': 't', 'tipo': 'jugada', 'titulo': 'Elige tu jugada', 'opciones': [
        {'id': '0', 'tipoJugada': 'pasar', 'titulo': 'pasar'},
        {'id': '1', 'tipoJugada': 'jugar', 'titulo': 'jugar Bola de Energía',
          'cartaUid': 'b', 'cartaTipo': 'Talismán', 'cantidadPago': 0},
      ]});
    final gesto = await tester.startGesture(tester.getCenter(find.text('Bola de Energía')));
    await tester.pump(const Duration(milliseconds: 600));
    await gesto.moveTo(tester.getCenter(find.text('Línea de Ataque rival')));
    await tester.pump();
    await gesto.up();
    await tester.pumpAndSettle();
    expect(enviados, ['1']);
  });

  testWidgets('la franja muestra todas las cartas sin desplazar', (tester) async {
    final muchas = [
      for (var i = 0; i < 24; i++) {...carta, 'id': 'x$i', 'nombre': 'Aliado $i'},
    ];
    await mesaCon(tester,
      {...estado, 'lados': [{...lado('Tú', humano: true), 'mano': <Map>[]}, lado('IA')]},
      {'id': 'o', 'tipo': 'objetivos', 'titulo': 'Elige objetivo', 'cantidad': 1, 'opciones': muchas});
    expect(tester.takeException(), isNull);
    for (final c in muchas) {
      expect(find.text('${c['nombre']}'), findsOneWidget);
    }
    expect(find.byType(ListView), findsNothing);
  });

  testWidgets('Damarchus muestra por qué no puede activar su habilidad', (tester) async {
    final damarchus = {
      ...carta,
      'id': 'damarchus',
      'nombre': 'Damarchus',
      'sinHabilidad': true,
      'sinHabilidadPor': 'Cleopatra VII',
    };
    final usada = {
      ...carta,
      'id': 'usada',
      'nombre': 'Otra Titán',
      'usadaEsteTurno': true,
    };
    await mesaCon(
      tester,
      {
        ...estado,
        'lados': [
          {...lado('Tú', humano: true), 'mano': <Map>[], 'defensa': [damarchus, usada]},
          lado('IA'),
        ],
      },
      decision,
    );
    expect(find.textContaining('SIN HABILIDAD · Cleopatra VII'), findsOneWidget);
    expect(find.text('YA USADA ESTE TURNO'), findsOneWidget);
  });

  for (final size in [const Size(400, 760), const Size(900, 430),
      const Size(320, 568), const Size(568, 320)]) {
    testWidgets('bloqueos unidos por flecha y Aliado sin habilidad en gris en $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final atacante = {...carta, 'id': 'atk', 'nombre': 'Caturix', 'fuerza': 6};
      final bloqueador = {
        ...carta, 'id': 'blk', 'nombre': 'Damarchus', 'sinHabilidad': true, 'sinHabilidadPor': 'Cleopatra VII',
      };
      final conBloqueo = {
        ...estado,
        'fase': 'guerra_talismanes',
        'activo': 1,
        'bloqueos': {'atk': 'blk'},
        'lados': [
          {...lado('Tú', humano: true), 'mano': <Map>[], 'defensa': [bloqueador]},
          {...lado('IA'), 'ataque': [atacante]},
        ],
      };
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: TableroDesafio(
        estado: conBloqueo, decision: null, enviar: (valor) async {},
      ))));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      final flechas = find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter.runtimeType.toString() == '_FlechasBloqueo');
      expect(flechas, findsOneWidget);
      expect(find.byType(ColorFiltered), findsOneWidget); // solo el que perdió la habilidad
    });
  }
}
