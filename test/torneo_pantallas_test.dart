import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/domain/torneo/torneo.dart';
import 'package:myl_decks/models/deck.dart';
import 'package:myl_decks/models/torneo.dart';
import 'package:myl_decks/screens/tournaments/tournament_widgets.dart';

DueloDoc _duelo(
  String fase,
  int ronda,
  int mesa,
  String a,
  String? b, {
  int? sa,
  int? sb,
  bool confirmado = false,
  String reportadoPor = '',
}) => DueloDoc.fromMap(DueloDoc.idDe(fase, ronda, mesa), {
  'phase': fase,
  'round': ronda,
  'table': mesa,
  'aUid': a,
  'aName': 'Jugador $a',
  'bUid': b,
  'bName': b == null ? null : 'Jugador $b',
  if (sa != null) 'scoreA': sa,
  if (sb != null) 'scoreB': sb,
  'confirmed': confirmado || b == null,
  'reportedBy': reportadoPor,
});

Torneo _torneo(Map<String, dynamic> extra) => Torneo.fromMap('t1', {
  'name': 'Torneo de prueba',
  'ownerUid': 'org',
  'format': 'racial_edicion',
  'topCut': 4,
  ...extra,
});

List<Inscrito> _inscritos(int n) => [
  for (var i = 1; i <= n; i++) Inscrito(uid: 'u$i', nombre: 'Jugador u$i'),
];

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  test('ids de duelo ordenan por fase, ronda y mesa', () {
    final ids = [
      DueloDoc.idDe('top', 1, 1),
      DueloDoc.idDe('suizo', 10, 2),
      DueloDoc.idDe('suizo', 2, 11),
      DueloDoc.idDe('suizo', 2, 3),
    ]..sort();
    expect(ids, ['s02_003', 's02_011', 's10_002', 't01_001']);
  });

  test('el bye nace cerrado y un marcador sin confirmar no cierra', () {
    expect(_duelo('suizo', 1, 3, 'u5', null).dominio.cerrado, isTrue);
    final pendiente = _duelo('suizo', 1, 1, 'u1', 'u2', sa: 2, sb: 0);
    expect(pendiente.esperaConfirmacion, isTrue);
    expect(pendiente.dominio.cerrado, isFalse);
    expect(pendiente.dominio.ganador, isNull);
    final listo = _duelo(
      'suizo',
      1,
      1,
      'u1',
      'u2',
      sa: 2,
      sb: 0,
      confirmado: true,
    );
    expect(listo.dominio.ganador, 'u1');
  });

  test('paso del torneo: ronda en curso, rondas y tamaño del top', () {
    final inscritos = _inscritos(5);
    final duelos = [
      _duelo('suizo', 1, 1, 'u1', 'u2', sa: 2, sb: 1, confirmado: true),
      _duelo('suizo', 1, 2, 'u3', 'u4', sa: 1, sb: 1),
      _duelo('suizo', 1, 3, 'u5', null),
    ];
    final t = _torneo({'status': 'suizo', 'currentRound': 1, 'swissRounds': 3});
    final paso = PasoTorneo.de(t, inscritos, duelos);
    expect(paso.rondaEnCurso.length, 3);
    expect(paso.rondaCerrada, isFalse, reason: 'falta confirmar la mesa 2');
    expect(paso.rondasSuizas, 3);
    expect(paso.top, 4);

    final cerrada = PasoTorneo.de(t, inscritos, [
      duelos[0],
      _duelo('suizo', 1, 2, 'u3', 'u4', sa: 1, sb: 1, confirmado: true),
      duelos[2],
    ]);
    expect(cerrada.rondaCerrada, isTrue);

    // Con 3 jugadores un top 4 se reduce a top 2.
    expect(PasoTorneo.de(t, _inscritos(3), duelos).top, 2);
    // Rondas automáticas según inscritos mientras no se haya iniciado.
    final auto = PasoTorneo.de(_torneo({}), _inscritos(9), const []);
    expect(auto.rondasSuizas, rondasSugeridas(9));
    expect(auto.rondaCerrada, isFalse);
  });

  test('qué mazos sirven para cada formato', () {
    Deck mazo(DeckFormat f) =>
        Deck(id: 'd', ownerId: 'u', name: 'm', format: f);
    expect(
      mazoSirveParaFormato(mazo(DeckFormat.racial), 'racial_edicion'),
      isTrue,
    );
    expect(
      mazoSirveParaFormato(mazo(DeckFormat.racialLibre), 'racial_edicion'),
      isFalse,
    );
    expect(
      mazoSirveParaFormato(mazo(DeckFormat.racial), 'racial_libre'),
      isTrue,
    );
    expect(mazoSirveParaFormato(mazo(DeckFormat.full), 'racial_libre'), isFalse);
    expect(mazoSirveParaFormato(mazo(DeckFormat.full), 'full'), isTrue);
    expect(mazoSirveParaFormato(mazo(DeckFormat.racial), 'full'), isTrue);
  });

  testWidgets('rondas: el jugador carga su duelo, no el ajeno', (tester) async {
    final duelos = [
      _duelo('suizo', 1, 1, 'u1', 'u2'),
      _duelo('suizo', 1, 2, 'u3', 'u4', sa: 2, sb: 0, confirmado: true),
      _duelo('suizo', 1, 3, 'u5', null),
    ];
    final tocados = <String>[];
    await tester.pumpWidget(
      _app(
        RondasTab(
          torneo: _torneo({'status': 'suizo', 'currentRound': 1}),
          duelos: duelos,
          uid: 'u1',
          organizo: false,
          onReportar: (d) => tocados.add(d.id),
        ),
      ),
    );
    expect(find.text('Ronda 1'), findsOneWidget);
    expect(find.text('Por jugar'), findsOneWidget);
    expect(find.text('2 - 0'), findsOneWidget);
    expect(find.text('Bye'), findsOneWidget);
    await tester.tap(find.text('Jugador u3'));
    await tester.tap(find.text('Jugador u5'));
    expect(tocados, isEmpty);
    await tester.tap(find.text('Jugador u1'));
    expect(tocados, ['s01_001']);
  });

  testWidgets('rondas: el organizador corrige un duelo confirmado', (
    tester,
  ) async {
    final tocados = <String>[];
    await tester.pumpWidget(
      _app(
        RondasTab(
          torneo: _torneo({'status': 'suizo', 'currentRound': 1}),
          duelos: [
            _duelo('suizo', 1, 1, 'u3', 'u4', sa: 2, sb: 0, confirmado: true),
          ],
          uid: 'org',
          organizo: true,
          onReportar: (d) => tocados.add(d.id),
        ),
      ),
    );
    await tester.tap(find.text('Jugador u3'));
    expect(tocados, ['s01_001']);
  });

  testWidgets('tabla: posiciones, puntos y récord', (tester) async {
    final jugadores = [for (final i in _inscritos(4)) i.jugador];
    final tabla = calcularTabla(jugadores, [
      _duelo('suizo', 1, 1, 'u1', 'u2', sa: 2, sb: 0, confirmado: true).dominio,
      _duelo('suizo', 1, 2, 'u3', 'u4', sa: 1, sb: 1, confirmado: true).dominio,
    ]);
    await tester.pumpWidget(_app(TablaTab(tabla: tabla, uid: 'u1', top: 2)));
    expect(find.text('Jugador u1'), findsOneWidget);
    expect(find.text('1-0-0'), findsOneWidget);
    expect(find.text('0-1-0'), findsNWidgets(2));
    expect(find.text('0-0-1'), findsOneWidget);
    expect(find.textContaining('los 2 que pasan a la llave'), findsOneWidget);
  });

  testWidgets('llave: cada ronda con su nombre', (tester) async {
    await tester.pumpWidget(
      _app(
        LlaveTab(
          duelos: [
            _duelo('top', 1, 1, 'u1', 'u4', sa: 2, sb: 0, confirmado: true),
            _duelo('top', 1, 2, 'u2', 'u3', sa: 1, sb: 2, confirmado: true),
            _duelo('top', 2, 1, 'u1', 'u3'),
          ],
        ),
      ),
    );
    expect(find.text('Semifinal'), findsOneWidget);
    expect(find.text('Final'), findsOneWidget);
    expect(find.text('Jugador u3'), findsNWidgets(2));
  });

  testWidgets('marcador: no deja guardar un resultado imposible', (
    tester,
  ) async {
    (int, int)? resultado;
    final duelo = _duelo('top', 1, 1, 'u1', 'u2');
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => TextButton(
                onPressed: () async {
                  resultado = await pedirMarcador(
                    context,
                    duelo: duelo,
                    permiteEmpate: false,
                  );
                },
                child: const Text('abrir'),
              ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    FilledButton guardar() =>
        tester.widget(find.widgetWithText(FilledButton, 'Guardar'));
    expect(guardar().onPressed, isNull, reason: '0-0 no vale');
    // 1 para A: en la llave no existe el 1-0.
    await tester.tap(find.text('1').first);
    await tester.pumpAndSettle();
    expect(guardar().onPressed, isNull);
    await tester.tap(find.text('2').first);
    await tester.pumpAndSettle();
    expect(guardar().onPressed, isNotNull);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(resultado, (2, 0));
  });
}
