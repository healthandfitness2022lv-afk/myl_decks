// lib/domain/analisis_mazo/analisis_mazo.dart
//
// Qué hace un mazo, calculado solo desde las habilidades programadas (las
// mismas que usa el simulador).
//
// Es el mismo cálculo que `simulator/myl_sim/perfil.py`. Los dos se prueban
// contra `test/fixtures/perfil_casos.json`: si cambias una regla o un peso
// aquí, cámbialo también allá y regenera los casos.
//
// Cada efecto (una habilidad o un "luego") aporta puntos a uno o más roles.
// Los puntos dependen de qué hace, a cuántas cartas, si se repite, cuánto
// cuesta activarlo y si tiene condición. Una carta suma como máximo
// [topeCarta] por rol; el mazo suma los puntos de cada copia.

import 'dart:math' as math;

import '../../models/card_myl.dart';
import '../../models/deck.dart';

/// Roles, en el orden en que se muestran.
const roles = <String>[
  'presion',
  'dano_directo',
  'remocion',
  'control',
  'respuesta',
  'proteccion',
  'ventaja',
  'economia',
  'recursion',
  'disrupcion',
];

const nombresRol = <String, String>{
  'presion': 'Presión',
  'dano_directo': 'Daño directo',
  'remocion': 'Remoción',
  'control': 'Control',
  'respuesta': 'Respuesta',
  'proteccion': 'Protección',
  'ventaja': 'Ventaja de cartas',
  'economia': 'Economía de Oros',
  'recursion': 'Recursión',
  'disrupcion': 'Disrupción de mano',
};

const descripcionRol = <String, String>{
  'presion':
      'Furia, imbloqueable y refuerzos de fuerza: cartas que apuran el daño.',
  'dano_directo':
      'Botan cartas del Mazo Castillo rival sin pasar por el combate.',
  'remocion':
      'Sacan del juego cartas del oponente (destruir, desterrar, barajar, subir).',
  'control':
      'Frenan al rival: quitan habilidades, impiden atacar o bloquear, bajan fuerza.',
  'respuesta': 'Actúan en el turno rival: anulan, cancelan ataques o redirigen.',
  'proteccion': 'Evitan que tus cartas sean destruidas, desterradas o anuladas.',
  'ventaja': 'Robo, filtro y búsqueda en el mazo.',
  'economia': 'Generan Oros, los buscan o abaratan costes.',
  'recursion': 'Recuperan cartas del Cementerio.',
  'disrupcion': 'Atacan la mano del rival: descarte y mirar su mano.',
};

const topeCarta = 2.0;
const manoInicial = 8;

const _rival = {'oponente', 'cualquiera', 'disparadora', 'ambos'};
const _propio = {'propio', 'esta_carta', 'proximo'};
const _enJuego = {'en_juego', 'linea_defensa', 'linea_ataque', 'linea_apoyo'};
const _propiedades = {
  'imbloqueable',
  'indestructible',
  'indesterrable',
  'noAnulable',
  'furia',
  'guardian',
  'errante',
  'retador',
  'sinLimiteArmas',
};
const _disparoRepetido = {
  'al_atacar',
  'al_hacer_dano',
  'al_inicio_fase',
  'al_bloquear',
  'propia_entra',
  'propia_sale',
  'propio_ataca',
  'propia_juega',
};
const _respuesta = {'oponente_juega', 'habilidad_oponente'};
const _protege = {'indestructible', 'indesterrable', 'inmunidad', 'noAnulable'};
const _agresivo = {'furia', 'imbloqueable', 'retador'};

// Pesos del índice de velocidad (ver [indiceVelocidad]). Calibrados contra
// el turno medio de victoria medido en el simulador (correlación -0,77):
// cada 10 puntos de índice son unos 0,6 turnos menos.
const pesoPresion = 1.0;
const pesoManejo = 1.0;
const pesoCurva = 0.4;
const escalaPresion = 0.8;
const escalaManejo = 1.3;
const curvaBaja = 1.6;
const curvaAlta = 3.2;
const corteAgro = 62;
const corteControl = 38;

int _entero(dynamic v, [int defecto = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? defecto;
}

Map<String, dynamic> _mapa(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

String _texto(dynamic v, String defecto) {
  final s = v == null ? '' : '$v';
  return s.isEmpty ? defecto : s;
}

bool _si(dynamic v) => v == true || (v is num && v != 0);

int _cantidad(Map<String, dynamic> e) =>
    e['cantidad'] == null ? 1 : _entero(e['cantidad'], 1);

double _alcance(Map<String, dynamic> e) {
  if (_mapa(e['objetivo'])['seleccion'] == 'todos') return 1.6;
  final n = _cantidad(e);
  return n <= 1 ? 1.0 : math.min(1.0 + 0.3 * (n - 1), 1.6);
}

double _factor(Map<String, dynamic> e, String cuando) {
  var f = 1.0;
  var costo = _mapa(e['costo']);
  if (_propiedades.contains('${e['accion'] ?? ''}')) {
    cuando = 'continua';
    costo = const {};
  }
  final seGasta = const [
    'destruirEstaCarta',
    'desterrarEstaCarta',
    'barajarEstaCarta',
    'fondoMazoEstaCarta',
  ].any((k) => _si(costo[k]));
  if (cuando == 'activada' && !seGasta && !_si(e['unaVez'])) {
    f *= 1.3;
  } else if (cuando == 'continua') {
    f *= 1.2;
  } else if (_disparoRepetido.contains(cuando)) {
    f *= 1.1;
  }
  f *= math.max(0.6, 1.0 - 0.1 * _entero(costo['oros']));
  final otros = const [
    'descartar',
    'destruirAliados',
    'desterrarAliados',
    'barajarMano',
  ].fold<int>(0, (s, k) => s + _entero(costo[k]));
  if (otros != 0) f *= 0.85;
  if (_texto(_mapa(e['condicion'])['tipo'], 'ninguna') != 'ninguna') f *= 0.85;
  return f;
}

/// Puntos por rol de un efecto. [cuando] es el de la habilidad que lo contiene.
Map<String, double> rolesDeEfecto(Map<String, dynamic> e, String cuando) {
  final accion = '${e['accion'] ?? ''}';
  final obj = _mapa(e['objetivo']);
  // Mismos valores por defecto que el modelo de habilidades.
  final quien = _texto(obj['quien'], 'oponente');
  final zona = _texto(obj['zona'], 'en_juego');
  final zonas = {
    zona,
    if (obj['zonas'] is List) ...(obj['zonas'] as List).map((x) => '$x'),
  };
  final tipos =
      obj['tipos'] is List
          ? (obj['tipos'] as List).map((x) => '$x').toList()
          : const <String>[];
  final modo = '${e['modo'] ?? ''}';
  final valor = _entero(e['valor']);
  final destino = '${e['zonaDestino'] ?? ''}';
  final cantidad = math.max(1, _cantidad(e));
  final rival = _rival.contains(quien);
  final propio = _propio.contains(quien);
  final enJuego = _enJuego.contains(zona);
  final out = <String, double>{};
  void suma(String rol, double puntos) => out[rol] = (out[rol] ?? 0) + puntos;

  if ((accion == 'destruir' || accion == 'desterrar') && rival && enJuego) {
    suma('remocion', 1.0 * _alcance(e));
  }
  if (accion == 'barajar' && rival && enJuego) {
    suma('remocion', 0.9 * _alcance(e));
  }
  if (accion == 'subirMano' && rival && enJuego) {
    suma('remocion', 0.6 * _alcance(e));
  }
  if (accion == 'ganarControl') {
    suma('remocion', 0.8);
    suma('presion', 0.4);
  }
  if (const {
        'perderHabilidad',
        'restriccion',
        'encarecer',
        'noAgrupar',
      }.contains(accion) &&
      !propio) {
    suma('control', 0.8 * _alcance(e));
  }
  if (accion == 'restringirCombate') {
    if (modo == 'puede_atacar_este_turno') {
      suma('presion', 0.6);
    } else if (!propio) {
      suma('control', 0.7 * _alcance(e));
    }
  }
  if (accion == 'modificarFuerza') {
    if (valor > 0 && !rival) {
      suma(
        'presion',
        math.min(0.3 + 0.15 * valor, 0.9) *
            (quien == 'propio' ? _alcance(e) : 1.0),
      );
    } else if (valor < 0 && !propio) {
      suma('control', math.min(0.3 + 0.15 * -valor, 0.9) * _alcance(e));
    }
  }
  if (accion == 'robar' && quien != 'oponente') {
    suma('ventaja', math.min(0.5 * cantidad, 1.5));
  }
  if (accion == 'mirarTope' || accion == 'mostrar') suma('ventaja', 0.5);
  if (accion == 'mirar') suma(rival ? 'disrupcion' : 'ventaja', 0.3);
  if (accion == 'botar' &&
      const {'oponente', 'ambos', 'cualquiera'}.contains(quien)) {
    suma('dano_directo', math.min(0.4 * cantidad, 2.0));
  }
  final esOro = tipos.length == 1 && tipos.first == 'Oro';
  const trae = {'buscar', 'jugarDesde', 'ponerEnJuego'};
  if (accion == 'generarOro' ||
      (trae.contains(accion) && (destino == 'reserva_oro' || esOro))) {
    suma('economia', 1.0);
  } else if (trae.contains(accion) && zonas.contains('mazo')) {
    suma('ventaja', 0.9);
  }
  if (accion == 'modificarCoste' && valor < 0) suma('economia', 0.6);
  if (accion == 'agrupar' && !rival) suma('economia', 0.5);
  if (const {
        'barajar',
        'subirMano',
        'jugarDesde',
        'buscar',
        'ponerEnJuego',
        'mover',
      }.contains(accion) &&
      propio &&
      zonas.contains('cementerio')) {
    suma('recursion', 0.9 * (accion != 'barajar' ? 1.0 : 0.6));
  }
  if (const {
        'anular',
        'cancelarAtaque',
        'cancelarHabilidad',
        'redirigir',
      }.contains(accion) ||
      _respuesta.contains(cuando)) {
    suma('respuesta', 1.0);
  }
  if (const {'prevenir', 'reducirDano', 'protegerHabilidad'}.contains(accion) ||
      _protege.contains(accion) ||
      (accion == 'otorgarPropiedad' && _protege.contains(modo))) {
    suma('proteccion', 0.7);
  }
  if (_agresivo.contains(accion) ||
      (accion == 'otorgarPropiedad' && _agresivo.contains(modo))) {
    suma('presion', 0.8);
  }
  if (accion == 'descartar' && (quien == 'oponente' || quien == 'ambos')) {
    suma('disrupcion', math.min(0.7 * cantidad, 1.6));
  }

  final f = _factor(e, cuando);
  return out.map((k, v) => MapEntry(k, v * f));
}

/// Puntos por rol de una carta (sus habilidades y sus "luego"), con tope.
Map<String, double> rolesDeHabilidades(
  Iterable<Map<String, dynamic>> habilidades,
) {
  final out = <String, double>{};
  for (final h in habilidades) {
    final cuando = '${h['cuando'] ?? ''}';
    final efectos = [
      h,
      if (h['luego'] is List)
        for (final x in h['luego'] as List)
          if (x is Map) Map<String, dynamic>.from(x),
    ];
    for (final e in efectos) {
      rolesDeEfecto(
        e,
        cuando,
      ).forEach((rol, p) => out[rol] = (out[rol] ?? 0) + p);
    }
  }
  out.removeWhere((_, v) => v <= 0);
  return out.map((k, v) => MapEntry(k, math.min(v, topeCarta)));
}

/// Roles de una carta del catálogo. Se memoriza por carta.
final _memoRoles = Expando<Map<String, double>>();
Map<String, double> rolesDeCarta(CardMyL carta) =>
    _memoRoles[carta] ??= rolesDeHabilidades(
      carta.habilidades.map((h) => h.toMap()),
    );

/// Roles de la carta, del más fuerte al más débil.
List<String> rolesOrdenados(CardMyL carta) {
  final r = rolesDeCarta(carta);
  return r.keys.toList()..sort((a, b) => r[b]!.compareTo(r[a]!));
}

/// P(al menos [minimo] éxitos) al sacar [muestra] cartas de [total] con
/// [exitos] buenas.
double hipergeometrica(int total, int exitos, int muestra, [int minimo = 1]) {
  muestra = math.min(muestra, total);
  if (minimo <= 0) return 1.0;
  if (total <= 0 || exitos <= 0) return 0.0;
  double comb(int n, int k) {
    if (k < 0 || k > n) return 0;
    k = math.min(k, n - k);
    var r = 1.0;
    for (var i = 1; i <= k; i++) {
      r = r * (n - k + i) / i;
    }
    return r;
  }

  var p = 0.0;
  final den = comb(total, muestra);
  for (var k = minimo; k <= math.min(exitos, muestra); k++) {
    p += comb(exitos, k) * comb(total - exitos, muestra - k) / den;
  }
  return math.min(1.0, p);
}

/// 0 = control, 100 = agro. [presion] y [manejo] son puntos totales del mazo.
int indiceVelocidad(
  double presion,
  double manejo,
  int noOros,
  double costeMedio,
) {
  if (noOros <= 0) return 50;
  final dp = math.min(presion / noOros / escalaPresion, 1.0);
  final dm = math.min(manejo / noOros / escalaManejo, 1.0);
  var curva = (curvaAlta - costeMedio) / (curvaAlta - curvaBaja);
  curva = curva.clamp(0.0, 1.0) * 2 - 1;
  final bruto =
      (pesoPresion * dp - pesoManejo * dm + pesoCurva * curva) /
      (math.max(pesoPresion, pesoManejo) + pesoCurva);
  return ((50 + 50 * bruto).clamp(0.0, 100.0) + 0.5).floor();
}

String perfilDe(int indice, Map<String, double> puntos, int noOros) {
  final motor =
      (puntos['ventaja'] ?? 0) +
      (puntos['economia'] ?? 0) +
      (puntos['recursion'] ?? 0);
  final resto = puntos.values.fold<double>(0, (a, b) => a + b) - motor;
  if (noOros > 0 && motor / noOros >= 0.75 && motor > resto * 1.25) {
    return 'Combo';
  }
  if (indice >= corteAgro) return 'Agro';
  if (indice <= corteControl) return 'Control';
  return 'Medio';
}

/// Una carta del mazo con sus copias, lista para analizar.
class CartaAnalisis {
  final String nombre;
  final String tipo;

  /// null = coste desconocido.
  final int? coste;
  final int fuerza;
  final int copias;
  final Map<String, double> roles;

  /// Tiene texto de habilidad pero no está programada.
  final bool sinProgramar;

  const CartaAnalisis({
    required this.nombre,
    required this.tipo,
    required this.coste,
    required this.fuerza,
    required this.copias,
    required this.roles,
    this.sinProgramar = false,
  });
}

/// Cuánto aporta una carta a un rol del mazo.
class AporteRol {
  final String nombre;
  final int copias;
  final double puntos;
  const AporteRol(this.nombre, this.copias, this.puntos);
}

class Consistencia {
  /// Probabilidad de tener N Oros en el turno N (robando una carta por turno).
  final double orosTurno2, orosTurno3, orosTurno4;

  /// Probabilidad de tener al menos una carta del rol en la mano inicial.
  final double remocionInicial, respuestaInicial, ventajaInicial;

  const Consistencia({
    required this.orosTurno2,
    required this.orosTurno3,
    required this.orosTurno4,
    required this.remocionInicial,
    required this.respuestaInicial,
    required this.ventajaInicial,
  });
}

class AnalisisMazo {
  final int total, oros, noOros;
  final double costeMedio, fuerzaMedia, fuerzaPorOro;
  final Map<int, int> curva;

  /// Copias por tipo normalizado: aliado, talisman, arma, totem, oro.
  final Map<String, int> porTipo;

  /// Puntos del mazo por rol.
  final Map<String, double> puntos;

  /// Copias con algún aporte al rol.
  final Map<String, int> copiasPorRol;

  /// Cartas que aportan a cada rol, de mayor a menor.
  final Map<String, List<AporteRol>> aportes;
  final double presion, manejo;

  /// 0 = control, 100 = agro.
  final int indice;

  /// "Agro", "Medio", "Control" o "Combo".
  final String perfil;
  final int sinProgramar;
  final Consistencia consistencia;

  const AnalisisMazo({
    required this.total,
    required this.oros,
    required this.noOros,
    required this.costeMedio,
    required this.fuerzaMedia,
    required this.fuerzaPorOro,
    required this.curva,
    required this.porTipo,
    required this.puntos,
    required this.copiasPorRol,
    required this.aportes,
    required this.presion,
    required this.manejo,
    required this.indice,
    required this.perfil,
    required this.sinProgramar,
    required this.consistencia,
  });

  bool get vacio => total == 0;

  /// true si ninguna carta aporta a ningún rol (mazo sin habilidades).
  bool get sinRoles => puntos.values.every((v) => v <= 0);

  /// Los roles con puntos, del más fuerte al más débil.
  List<String> get rolesPrincipales =>
      [
        for (final r in roles)
          if ((puntos[r] ?? 0) > 0) r,
      ]..sort((a, b) => puntos[b]!.compareTo(puntos[a]!));

  /// Por qué quedó con ese perfil, en una frase.
  String get motivo {
    final coste = costeMedio.toStringAsFixed(1);
    final p = presion.toStringAsFixed(0);
    final m = manejo.toStringAsFixed(0);
    switch (perfil) {
      case 'Agro':
        return 'Mucha presión ($p puntos) frente a $m de manejo de mesa, '
            'con curva baja (coste medio $coste).';
      case 'Control':
        return 'Mucho manejo de mesa ($m puntos) frente a $p de presión; '
            'coste medio $coste.';
      case 'Combo':
        return 'Gira en torno a robar, buscar, acelerar Oros y recuperar '
            'cartas; coste medio $coste.';
      default:
        return 'Presión ($p) y manejo de mesa ($m) parejos; '
            'coste medio $coste.';
    }
  }

  /// "Control · Remoción · Ventaja de cartas".
  String get resumen => [
    perfil,
    for (final r in rolesPrincipales.take(2)) nombresRol[r]!,
  ].join(' · ');
}

String tipoNormal(String tipo) =>
    tipo.toLowerCase().replaceAll('á', 'a').replaceAll('ó', 'o').trim();

AnalisisMazo analizarCartas(Iterable<CartaAnalisis> cartas) {
  final puntos = {for (final r in roles) r: 0.0};
  final copiasRol = {for (final r in roles) r: 0};
  final aportes = <String, List<AporteRol>>{};
  final curva = <int, int>{};
  final porTipo = <String, int>{};
  var total = 0, oros = 0, noOros = 0, conCoste = 0, sumaCoste = 0;
  var aliados = 0, fuerza = 0, costeAliados = 0, sinProgramar = 0;

  for (final c in cartas) {
    final n = c.copias;
    if (n <= 0) continue;
    total += n;
    final tipo = tipoNormal(c.tipo);
    porTipo[tipo] = (porTipo[tipo] ?? 0) + n;
    if (tipo.startsWith('oro')) {
      oros += n;
    } else {
      noOros += n;
      final coste = c.coste;
      if (coste != null && coste >= 0) {
        sumaCoste += coste * n;
        conCoste += n;
        curva[coste] = (curva[coste] ?? 0) + n;
      }
      if (tipo == 'aliado') {
        aliados += n;
        fuerza += c.fuerza * n;
        costeAliados += math.max(coste ?? 0, 0) * n;
      }
    }
    if (c.sinProgramar) sinProgramar += n;
    c.roles.forEach((rol, p) {
      if (p <= 0) return;
      puntos[rol] = (puntos[rol] ?? 0) + p * n;
      copiasRol[rol] = (copiasRol[rol] ?? 0) + n;
      (aportes[rol] ??= []).add(AporteRol(c.nombre, n, p * n));
    });
  }
  for (final lista in aportes.values) {
    lista.sort((a, b) {
      final d = b.puntos.compareTo(a.puntos);
      return d != 0 ? d : a.nombre.compareTo(b.nombre);
    });
  }
  final costeMedio = conCoste == 0 ? 0.0 : sumaCoste / conCoste;
  final presion = puntos['presion']! + puntos['dano_directo']!;
  final manejo =
      puntos['remocion']! +
      puntos['control']! +
      puntos['respuesta']! +
      0.5 * puntos['ventaja']! +
      0.5 * puntos['recursion']!;
  final indice = indiceVelocidad(presion, manejo, noOros, costeMedio);
  return AnalisisMazo(
    total: total,
    oros: oros,
    noOros: noOros,
    costeMedio: costeMedio,
    fuerzaMedia: aliados == 0 ? 0 : fuerza / aliados,
    fuerzaPorOro: costeAliados == 0 ? 0 : fuerza / costeAliados,
    curva: Map.fromEntries(
      curva.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    ),
    porTipo: porTipo,
    puntos: puntos,
    copiasPorRol: copiasRol,
    aportes: aportes,
    presion: presion,
    manejo: manejo,
    indice: indice,
    perfil: perfilDe(indice, puntos, noOros),
    sinProgramar: sinProgramar,
    consistencia: Consistencia(
      orosTurno2: hipergeometrica(total, oros, manoInicial + 1, 2),
      orosTurno3: hipergeometrica(total, oros, manoInicial + 2, 3),
      orosTurno4: hipergeometrica(total, oros, manoInicial + 3, 4),
      remocionInicial: hipergeometrica(
        total,
        copiasRol['remocion']!,
        manoInicial,
      ),
      respuestaInicial: hipergeometrica(
        total,
        copiasRol['respuesta']!,
        manoInicial,
      ),
      ventajaInicial: hipergeometrica(
        total,
        copiasRol['ventaja']!,
        manoInicial,
      ),
    ),
  );
}

/// ¿Le falta programar las habilidades? (tiene texto y ninguna habilidad).
bool cartaSinProgramar(CardMyL c) {
  if (c.habilidades.isNotEmpty || c.habilidadesRevisadas) return false;
  final texto = (c.habilidadTextoIA.isNotEmpty
          ? c.habilidadTextoIA
          : c.habilidad)
      .replaceAll(RegExp(r'^[ .]+|[ .]+$'), '');
  return texto.isNotEmpty;
}

/// Análisis de un mazo de la app. [resolver] devuelve la carta del catálogo
/// de cada entrada (o null si no está).
AnalisisMazo analizarMazo(
  Deck deck, {
  required CardMyL? Function(DeckCardEntry entry) resolver,
}) => analizarEntradas(deck.cards, resolver: resolver);

AnalisisMazo analizarEntradas(
  Iterable<DeckCardEntry> entradas, {
  required CardMyL? Function(DeckCardEntry entry) resolver,
}) {
  final cartas = <CartaAnalisis>[];
  for (final e in entradas) {
    final carta = resolver(e);
    final tipo =
        (e.tipo ?? '').trim().isNotEmpty ? e.tipo! : (carta?.tipo ?? '');
    cartas.add(
      CartaAnalisis(
        nombre: e.name,
        tipo: tipo,
        coste: e.coste ?? carta?.coste,
        fuerza: carta?.fuerza ?? 0,
        copias: e.count,
        roles: carta == null ? const {} : rolesDeCarta(carta),
        sinProgramar: carta != null && cartaSinProgramar(carta),
      ),
    );
  }
  return analizarCartas(cartas);
}
