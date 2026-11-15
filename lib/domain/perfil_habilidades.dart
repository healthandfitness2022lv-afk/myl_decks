// lib/domain/perfil_habilidades.dart
//
// Estadísticas del mazo a partir de las habilidades programadas (las mismas
// que usa el simulador), en vez de las características cargadas a mano.
// Cada carta suma una vez por copia en cada categoría que cumpla.

import '../models/card_habilidad.dart';
import '../models/card_myl.dart';
import '../models/deck.dart';

/// Orden y nombre de las categorías que se muestran.
const categoriasHabilidad = <String>[
  'Remoción',
  'Control',
  'Respuesta',
  'Protección',
  'Robo / filtro',
  'Búsqueda en el mazo',
  'Aceleración de Oros',
  'Recursión (Cementerio)',
  'Agresión (Furia / Imbloqueable)',
  'Refuerzo de fuerza',
  'Daño directo (botar)',
  'Disrupción de mano',
];

const _remocion = {'destruir', 'desterrar'};

/// Categorías de un efecto (una habilidad o un "luego").
Set<String> categoriasDeEfecto({
  required String accion,
  required String cuando,
  required ObjetivoHabilidad objetivo,
  required String zonaDestino,
  required String modo,
  required int valor,
}) {
  final quien = objetivo.quien;
  final zona = objetivo.zona;
  final zonas = {zona, ...objetivo.zonas};
  final tipos = objetivo.tipos;
  final out = <String>{};

  if (_remocion.contains(accion) &&
      (quien == 'oponente' || quien == 'cualquiera') &&
      zona == 'en_juego') {
    out.add('Remoción');
  }
  if ((accion == 'barajar' || accion == 'subirMano') &&
      (quien == 'oponente' || quien == 'disparadora') &&
      zona == 'en_juego') {
    out.add('Remoción');
  }
  if ((accion == 'perderHabilidad' || accion == 'restriccion') && quien != 'propio') {
    out.add('Control');
  }
  if (accion == 'restringirCombate') {
    if (modo == 'puede_atacar_este_turno') {
      out.add('Agresión (Furia / Imbloqueable)');
    } else if (quien != 'propio') {
      out.add('Control');
    }
  }
  if (accion == 'modificarFuerza') {
    if (valor > 0) out.add('Refuerzo de fuerza');
    if (valor < 0 && quien != 'propio') out.add('Control');
  }
  if ((accion == 'robar' && quien != 'oponente') ||
      accion == 'mirarTope' ||
      accion == 'mirar') {
    out.add('Robo / filtro');
  }
  if (accion == 'botar' && (quien == 'oponente' || quien == 'ambos')) {
    out.add('Daño directo (botar)');
  }
  final esOro = tipos.contains('Oro');
  if ((accion == 'buscar' && (zonaDestino == 'reserva_oro' || esOro)) ||
      accion == 'generarOro') {
    out.add('Aceleración de Oros');
  } else if ((accion == 'buscar' || accion == 'jugarDesde') &&
      zonas.contains('mazo')) {
    out.add('Búsqueda en el mazo');
  }
  if ((accion == 'barajar' || accion == 'subirMano' || accion == 'jugarDesde') &&
      (quien == 'propio' || quien == 'esta_carta') &&
      zonas.contains('cementerio')) {
    out.add('Recursión (Cementerio)');
  }
  if (accion == 'anular' ||
      accion == 'redirigir' ||
      accion == 'cancelarAtaque' ||
      cuando == 'oponente_juega') {
    out.add('Respuesta');
  }
  if (accion == 'prevenir' ||
      accion == 'reducirDano' ||
      accion == 'indestructible' ||
      accion == 'indesterrable' ||
      (accion == 'otorgarPropiedad' &&
          (modo == 'indestructible' || modo == 'indesterrable'))) {
    out.add('Protección');
  }
  if (accion == 'furia' ||
      accion == 'imbloqueable' ||
      (accion == 'otorgarPropiedad' && (modo == 'furia' || modo == 'imbloqueable'))) {
    out.add('Agresión (Furia / Imbloqueable)');
  }
  if (accion == 'descartar' && quien == 'oponente') {
    out.add('Disrupción de mano');
  }
  return out;
}

/// Todas las categorías de una carta (sus habilidades y sus "luego").
Set<String> categoriasDeCarta(CardMyL carta) {
  final out = <String>{};
  for (final h in carta.habilidades) {
    out.addAll(categoriasDeEfecto(
      accion: h.accion.name,
      cuando: h.cuando,
      objetivo: h.objetivo,
      zonaDestino: h.zonaDestino,
      modo: h.modo,
      valor: h.valor,
    ));
    for (final e in h.luego) {
      out.addAll(categoriasDeEfecto(
        accion: e.accion.name,
        cuando: h.cuando,
        objetivo: e.objetivo,
        zonaDestino: e.zonaDestino,
        modo: e.modo,
        valor: e.valor,
      ));
    }
  }
  return out;
}

/// Cuándo actúa una habilidad, en palabras del jugador.
String momentoDeHabilidad(CardHabilidad h) {
  switch (h.cuando) {
    case 'al_jugar':
      return 'Al entrar / jugarse';
    case 'activada':
      return 'Activada';
    case 'continua':
      return 'Continua';
    case 'oponente_juega':
      return 'En respuesta';
    default:
      return 'En combate o en fases';
  }
}

class PerfilHabilidades {
  /// Copias por categoría.
  final Map<String, int> porCategoria;

  /// Cartas (nombre y copias) por categoría.
  final Map<String, List<DeckCardEntry>> cartasPorCategoria;

  /// Habilidades (por copia) según cuándo actúan.
  final Map<String, int> porMomento;

  /// Copias sin habilidades programadas (usan las características antiguas).
  final int sinProgramar;

  /// "Agro", "Control" o "Intermedio".
  final String perfil;
  final String motivoPerfil;

  const PerfilHabilidades({
    required this.porCategoria,
    required this.cartasPorCategoria,
    required this.porMomento,
    required this.sinProgramar,
    required this.perfil,
    required this.motivoPerfil,
  });

  bool get vacio => porCategoria.isEmpty;
}

PerfilHabilidades calcularPerfilHabilidades(
  Deck deck, {
  required CardMyL? Function(DeckCardEntry entry) resolver,
}) {
  final porCategoria = <String, int>{};
  final cartas = <String, List<DeckCardEntry>>{};
  final porMomento = <String, int>{};
  var sinProgramar = 0;
  var costeTotal = 0;
  var copiasConCoste = 0;

  for (final entry in deck.cards) {
    final carta = resolver(entry);
    final tipo = (entry.tipo ?? carta?.tipo ?? '').toLowerCase();
    if (!tipo.startsWith('oro') && entry.coste != null) {
      costeTotal += entry.coste! * entry.count;
      copiasConCoste += entry.count;
    }
    if (carta == null || carta.habilidades.isEmpty) {
      sinProgramar += entry.count;
      continue;
    }
    for (final cat in categoriasDeCarta(carta)) {
      porCategoria[cat] = (porCategoria[cat] ?? 0) + entry.count;
      cartas.putIfAbsent(cat, () => []).add(entry);
    }
    for (final h in carta.habilidades) {
      final m = momentoDeHabilidad(h);
      porMomento[m] = (porMomento[m] ?? 0) + entry.count;
    }
  }

  int c(String k) => porCategoria[k] ?? 0;
  final agro = c('Agresión (Furia / Imbloqueable)') + c('Refuerzo de fuerza') + c('Daño directo (botar)');
  final control = c('Remoción') + c('Control') + c('Recursión (Cementerio)') + c('Respuesta');
  final costeProm = copiasConCoste == 0 ? 0.0 : costeTotal / copiasConCoste;
  String perfil;
  String motivo;
  if (agro >= control * 1.4 && costeProm <= 2.6) {
    perfil = 'Agro';
    motivo = 'Mucha presión (agresión, refuerzo y daño directo: $agro) y curva baja '
        '(coste promedio ${costeProm.toStringAsFixed(1)}).';
  } else if (control >= agro * 1.4) {
    perfil = 'Control';
    motivo = 'Mucho manejo de mesa (remoción, control, recursión y respuestas: $control) '
        'frente a $agro de presión; coste promedio ${costeProm.toStringAsFixed(1)}.';
  } else {
    perfil = 'Intermedio';
    motivo = 'Presión ($agro) y manejo de mesa ($control) parejos; '
        'coste promedio ${costeProm.toStringAsFixed(1)}.';
  }

  return PerfilHabilidades(
    porCategoria: porCategoria,
    cartasPorCategoria: cartas,
    porMomento: porMomento,
    sinProgramar: sinProgramar,
    perfil: perfil,
    motivoPerfil: motivo,
  );
}
