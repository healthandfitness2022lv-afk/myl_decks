// lib/models/card_habilidad.dart
//
// Habilidades parametrizadas, programadas a mano.
//
// Cada carta guarda en `habilidades` una lista de [CardHabilidad]: qué
// acción ejecuta el simulador (ver [Accion]) y con qué parámetros (cuándo,
// fase, condición, costo,
// objetivo, cantidad, duración…). El simulador Python lee exactamente estos
// mapas, así que los nombres de campo son el contrato entre ambos.
//
// `habilidadesRevisadas: true` en la carta marca que todas sus habilidades
// están programadas; si no, el simulador la juega sin habilidad y lo avisa.

/// Verbos que el motor sabe ejecutar. `otra` = aún no soportado por el motor.
enum Accion {
  robar('Robar', 'Roba N cartas de tu Mazo Castillo.'),
  botar(
    'Botar (daño directo)',
    'El jugador objetivo Bota N cartas de su Mazo Castillo al Cementerio.',
  ),
  descartar('Descartar', 'El jugador objetivo descarta N cartas de su mano.'),
  destruir('Destruir', 'Envía cartas en juego al Cementerio de su dueño.'),
  desterrar('Desterrar', 'Envía cartas a la Zona de Destierro.'),
  subirMano(
    'Subir a la mano',
    'Devuelve cartas en juego (o del Cementerio) a la mano de su dueño.',
  ),
  barajar(
    'Barajar en el mazo',
    'Baraja cartas en el Mazo Castillo de su dueño.',
  ),
  buscar(
    'Buscar',
    'Busca cartas en el Mazo, Cementerio o Destierro y las pone en la zona destino.',
  ),
  ponerEnJuego(
    'Poner en juego',
    'Pone en juego cartas desde la zona de origen sin jugarlas.',
  ),
  anular(
    'Anular',
    'La carta que juega el oponente va al Cementerio sin efecto.',
  ),
  generarOro(
    'Generar oro',
    'Agrega N Oros virtuales que duran solo este turno.',
  ),
  modificarFuerza(
    'Modificar fuerza',
    'Aumenta, disminuye, duplica o fija la Fuerza de Aliados.',
  ),
  modificarCoste('Modificar coste', 'Aumenta o reduce el coste de cartas.'),
  perderHabilidad(
    'Perder habilidad',
    'Las cartas objetivo pierden su habilidad.',
  ),
  prevenir('Prevenir', 'Evita que una carta sea Destruida o Desterrada.'),
  imbloqueable('Imbloqueable', 'Este Aliado no puede ser bloqueado.'),
  indestructible(
    'Indestructible',
    'No puede ser Destruida por efectos ni en combate.',
  ),
  indesterrable('Indesterrable', 'No puede ser Desterrada.'),
  noAnulable('No anulable', 'Esta carta no puede ser anulada.'),
  furia(
    'Puede atacar al entrar',
    'Puede atacar el turno en que entra en juego.',
  ),
  mover(
    'Mover',
    'Traslada cartas a otra zona o línea sin destruirlas (tope o fondo del Mazo, Línea de Ataque, Cementerio…).',
  ),
  jugarDesde(
    'Jugar desde otra zona',
    'Juega una carta desde una zona distinta de la mano, pagando o sin pagar su coste. Cuenta como jugarla.',
  ),
  ganarControl(
    'Ganar control',
    'Tomas el control de una carta oponente hasta cuando indique la carta.',
  ),
  mirar('Mirar', 'Miras la mano del oponente o cartas de un Mazo Castillo.'),
  mostrar(
    'Mostrar una carta',
    'Revela una carta de tu mano que cumpla los filtros indicados.',
  ),
  restringirCombate(
    'Restringir combate',
    'Un Aliado no puede bloquear, no puede atacar, no puede ser bloqueado o puede bloquear imbloqueables.',
  ),
  cancelarAtaque(
    'Cancelar ataque o bloqueo',
    'Cancela el ataque (o el de un Aliado) o un bloqueo.',
  ),
  reducirDano(
    'Reducir daño',
    'El daño que recibirías queda en 0 o se reduce en N, o un Aliado no hace daño este turno.',
  ),
  agrupar('Agrupar', 'Agrupa Aliados y/u Oros fuera de la Fase de Agrupación.'),
  noAgrupar(
    'No agrupar',
    'Un jugador no agrupa Aliados y/u Oros en su próxima Agrupación.',
  ),
  restriccion(
    'Restricción',
    'Mientras esta carta esté en la zona indicada, nadie (o un jugador) puede realizar cierta acción.',
  ),
  inmunidad('Inmunidad', 'No puede ser afectada por cierto tipo de cartas.'),
  guardian('Guardián', 'No puede atacar.'),
  errante('Errante', 'Solo puedes tener una copia de esta carta en juego.'),
  retador('Retador', 'Al atacar, obliga a un Aliado oponente a bloquearlo.'),
  sinLimiteArmas('Sin límite de armas', 'Puede portar más de un Arma.'),
  otorgarPropiedad(
    'Otorgar propiedad',
    'Las cartas objetivo ganan una propiedad (Indestructible, Imbloqueable…) por un tiempo.',
  ),
  protegerHabilidad(
    'No pueden perder su habilidad',
    'Las cartas indicadas no pueden perder su habilidad.',
  ),
  encarecer(
    'Encarecer al afectarla',
    'Las cartas oponentes del tipo indicado pagan N oros más para afectar a esta carta.',
  ),
  obligarBloqueo(
    'Obligar a bloquear',
    'Eliges un Aliado oponente que debe bloquear a este Aliado.',
  ),
  requisitoPortador(
    'Requisito del portador',
    'Qué Aliados pueden portar esta Arma: raza, coste o fuerza, y si pueden ser del oponente.',
  ),
  redirigir(
    'Redirigir',
    'En respuesta a un efecto oponente que afecte una de tus cartas, cambia su objetivo a otra carta válida.',
  ),
  elegir(
    'Elegir (referencia)',
    'Eliges una carta sin afectarla, para que un efecto "luego" la use (p. ej. bota tantas como su fuerza).',
  ),
  mirarTope(
    'Mirar las de arriba y repartir',
    'Miras las N primeras de un Mazo: tomas las que cumplan el filtro y el resto va a otra zona (o repartes una a cada zona).',
  ),
  cambiarRaza(
    'Cambiar raza',
    'Las cartas afectadas se consideran de otra raza mientras estén en juego.',
  ),
  convertirEnAliado(
    'Convertir en Aliado',
    'Esta carta (un Oro) se convierte en un Aliado de coste y fuerza N por un tiempo.',
  ),
  cancelarHabilidad(
    'Cancelar habilidad',
    'En respuesta a una habilidad oponente que se activa o dispara: no se '
        'resuelve (la carta conserva su habilidad).',
  ),
  copiarHabilidad(
    'Copiar habilidad',
    'Esta carta copia la habilidad de otra carta en juego hasta la Fase Final.',
  ),
  convertirEnCopia(
    'Convertirse en copia',
    'Esta carta se convierte en una copia exacta de otra hasta la Fase Final.',
  ),
  otra(
    'Otra (sin motor)',
    'Aún no la ejecuta el simulador: se registra pero no hace nada.',
  );

  final String label;
  final String descripcion;
  const Accion(this.label, this.descripcion);

  static Accion parse(String? id) =>
      Accion.values.where((a) => a.name == id).firstOrNull ?? Accion.otra;

  /// Propiedades estáticas: no necesitan cuándo/costo/objetivo.
  bool get esPropiedad => const {
    Accion.imbloqueable,
    Accion.indestructible,
    Accion.indesterrable,
    Accion.noAnulable,
    Accion.furia,
    Accion.guardian,
    Accion.errante,
    Accion.retador,
    Accion.sinLimiteArmas,
  }.contains(this);

  /// Usa un objetivo de cartas (vs. un jugador o nada).
  bool get usaObjetivoCartas => const {
    Accion.destruir,
    Accion.desterrar,
    Accion.subirMano,
    Accion.barajar,
    Accion.buscar,
    Accion.ponerEnJuego,
    Accion.modificarFuerza,
    Accion.modificarCoste,
    Accion.perderHabilidad,
    Accion.prevenir,
    Accion.anular,
    Accion.mover,
    Accion.jugarDesde,
    Accion.ganarControl,
    Accion.restringirCombate,
    Accion.inmunidad,
    Accion.requisitoPortador,
    Accion.encarecer,
    Accion.obligarBloqueo,
    Accion.otorgarPropiedad,
    Accion.protegerHabilidad,
    Accion.elegir,
    Accion.mirarTope,
    Accion.mostrar,
    Accion.cambiarRaza,
    Accion.cancelarHabilidad,
    Accion.copiarHabilidad,
    Accion.convertirEnCopia,
  }.contains(this);

  bool get usaZonaDestino =>
      this == Accion.buscar ||
      this == Accion.ponerEnJuego ||
      this == Accion.mover ||
      this == Accion.mirarTope;

  bool get usaModoFuerza => this == Accion.modificarFuerza;
}

/// Opciones con id estable (lo que se guarda) y etiqueta visible.
class Opcion {
  final String id;
  final String label;
  const Opcion(this.id, this.label);
}

const kCuando = [
  Opcion('continua', 'Continua (mientras está en juego)'),
  Opcion('al_jugar', 'Al jugarse / entrar en juego'),
  Opcion('activada', 'Activada (el jugador decide usarla)'),
  Opcion('al_atacar', 'Al ser declarado atacante'),
  Opcion('al_bloquear', 'Al ser declarado bloqueador'),
  Opcion('al_ser_bloqueado', 'Al ser bloqueado'),
  Opcion('al_salir_del_juego', 'Al salir del juego (destruido, desterrado…)'),
  Opcion('al_inicio_fase', 'Al comienzo de la fase indicada'),
  Opcion('oponente_juega', 'Cuando el oponente juega una carta'),
  Opcion('al_hacer_dano', 'Cuando hace daño al Mazo Castillo oponente'),
  Opcion('propia_entra', 'Cuando una carta tuya entra en juego'),
  Opcion('propia_sale', 'Cuando una carta tuya sale del juego'),
  Opcion(
    'al_botar_por_oponente',
    'Cuando botas cartas por una habilidad oponente',
  ),
  Opcion('propio_ataca', 'Cuando declaras tu ataque'),
  Opcion(
    'habilidad_oponente',
    'En respuesta a una habilidad oponente que se activa o dispara',
  ),
  Opcion('afectada_por_oponente', 'Cuando una habilidad oponente la afecta'),
  Opcion('al_pagar_aliado', 'Cuando lo usas para pagar un Aliado (Oros)'),
];

/// Disparadores que tienen sentido según el tipo de carta. Los Talismanes no
/// entran en juego: solo se juegan y se resuelven. Los Oros actúan desde la
/// Reserva (continua, o activada pagando el Oro).
/// Propiedades propias de un Aliado. En un Arma se aplican a su portador.
const kPropiedadesDeAliado = {
  Accion.imbloqueable,
  Accion.furia,
  Accion.guardian,
  Accion.retador,
  Accion.sinLimiteArmas,
};

/// ¿Esta acción tiene sentido para este tipo de carta? El editor solo ofrece
/// las características permitidas.
bool accionPermitida(Accion a, String tipoCarta) {
  final t = tipoCarta.toLowerCase();
  final esTalisman = t.startsWith('talism');
  final esArma = t == 'arma';
  final esAliado = t == 'aliado';
  if (a == Accion.requisitoPortador) return esArma;
  // Talismán en respuesta, o una carta en juego que se paga (Flidais).
  if (a == Accion.cancelarHabilidad) return true;
  if (a == Accion.obligarBloqueo) return esAliado || esArma;
  if (a == Accion.encarecer || a == Accion.protegerHabilidad) {
    return !esTalisman;
  }
  if (kPropiedadesDeAliado.contains(a)) return esAliado || esArma;
  if (esTalisman) {
    // Un Talismán nunca está en juego: sin propiedades de permanencia ni
    // efectos continuos.
    return !const {
      Accion.inmunidad,
      Accion.restriccion,
      Accion.indestructible,
      Accion.indesterrable,
      Accion.errante,
      Accion.modificarCoste,
      Accion.prevenir,
    }.contains(a);
  }
  if (a == Accion.redirigir) return false; // solo Talismanes en respuesta
  return true;
}

/// "¿Sobre qué cartas?" según el tipo de la carta que tiene la habilidad.
List<Opcion> quienPara(String tipoCarta, Accion accion, {String cuando = ''}) {
  final t = tipoCarta.toLowerCase();
  // "La carta que activó el disparador" solo existe con esos disparadores.
  final conDisparadora = const {
    'propia_entra',
    'propia_sale',
    'oponente_juega',
  }.contains(cuando);
  final base =
      kQuien.where((o) => o.id != 'disparadora' || conDisparadora).toList();
  if (t == 'arma') {
    return [
      const Opcion('esta_carta', 'Su portador'),
      ...base.where((o) => o.id != 'esta_carta'),
    ];
  }
  if (t.startsWith('talism') && accion != Accion.jugarDesde) {
    // El Talismán no está en juego: no puede ser su propio objetivo.
    return base.where((o) => o.id != 'esta_carta').toList();
  }
  return base;
}

/// Tipos de carta que pueden ser objetivo de esta acción en estas zonas.
/// Un Talismán nunca está en juego: no se destruye, no se controla, etc.
List<String> tiposPara(Accion accion, List<String> zonas) {
  const enJuego = {
    'en_juego',
    'linea_defensa',
    'linea_ataque',
    'linea_apoyo',
    'reserva_oro',
  };
  if (accion == Accion.modificarFuerza ||
      accion == Accion.restringirCombate ||
      accion == Accion.requisitoPortador ||
      accion == Accion.obligarBloqueo) {
    return const ['Aliado'];
  }
  // Anular (la carta que se está jugando), Inmunidad (de qué cartas) y
  // Restricción (qué no se puede jugar) no miran zonas: valen todos los
  // tipos, incluidos los Talismanes.
  if (const {
    Accion.anular,
    Accion.inmunidad,
    Accion.restriccion,
    Accion.redirigir,
    Accion.encarecer,
    Accion.cancelarHabilidad,
  }.contains(accion)) {
    return kTiposCarta;
  }
  if (zonas.isNotEmpty && zonas.every(enJuego.contains)) {
    final tipos = <String>{};
    for (final z in zonas) {
      tipos.addAll(switch (z) {
        'linea_defensa' || 'linea_ataque' => const ['Aliado'],
        'linea_apoyo' => const ['Tótem', 'Arma'],
        'reserva_oro' => const ['Oro'],
        _ => const ['Aliado', 'Arma', 'Tótem', 'Oro'],
      });
    }
    return kTiposCarta.where(tipos.contains).toList();
  }
  const nuncaTalisman = {
    Accion.destruir,
    Accion.ganarControl,
    Accion.perderHabilidad,
    Accion.ponerEnJuego,
  };
  if (nuncaTalisman.contains(accion)) {
    return kTiposCarta.where((t) => t != 'Talismán').toList();
  }
  return kTiposCarta;
}

/// Costos de "esta carta" que tienen sentido según el tipo: un Talismán no
/// se destruye ni se destierra (nunca está en juego); solo un Oro se paga.
bool costoPermitido(String costo, String tipoCarta) {
  final t = tipoCarta.toLowerCase();
  return switch (costo) {
    'destruirEstaCarta' ||
    'desterrarEstaCarta' ||
    'barajarEstaCarta' ||
    'fondoMazoEstaCarta' => !t.startsWith('talism'),
    'pagarEstaCarta' => t == 'oro',
    'moverEstaCartaAtaque' => t == 'aliado',
    _ => true,
  };
}

/// Propiedades de un Arma: ¿a quién aplican?
const kAplicaArma = [
  Opcion('esta_carta', 'A su portador'),
  Opcion('el_arma', 'Al Arma misma'),
];

/// A quién aplica por defecto una propiedad de Arma.
String aplicaPorDefecto(Accion a) =>
    kPropiedadesDeAliado.contains(a) ? 'esta_carta' : 'el_arma';

List<Opcion> cuandoPara(String tipoCarta) {
  final t = tipoCarta.toLowerCase();
  if (t.startsWith('talism')) {
    return const [
      Opcion('al_jugar', 'Al jugarse'),
      Opcion(
        'oponente_juega',
        'En respuesta a que el oponente juegue una carta',
      ),
      Opcion(
        'habilidad_oponente',
        'En respuesta a una habilidad oponente que se activa o dispara',
      ),
    ];
  }
  if (t == 'arma') {
    return const [
      Opcion('continua', 'Continua (mientras esté cargada)'),
      Opcion('al_jugar', 'Al cargarse en un Aliado'),
      Opcion('activada', 'Activada (el jugador decide usarla)'),
      Opcion('al_atacar', 'Cuando su portador es declarado atacante'),
      Opcion('al_bloquear', 'Cuando su portador bloquea'),
      Opcion('al_ser_bloqueado', 'Cuando su portador es bloqueado'),
      Opcion('al_salir_del_juego', 'Al salir del juego (con su portador)'),
      Opcion('al_hacer_dano', 'Cuando su portador hace daño al Mazo Castillo'),
      Opcion('propia_entra', 'Cuando una carta tuya entra en juego'),
      Opcion('propia_sale', 'Cuando una carta tuya sale del juego'),
      Opcion('al_inicio_fase', 'Al comienzo de la fase indicada'),
      Opcion('oponente_juega', 'Cuando el oponente juega una carta'),
      Opcion(
        'al_botar_por_oponente',
        'Cuando botas cartas por una habilidad oponente',
      ),
    ];
  }
  if (t == 'oro') {
    return const [
      Opcion('activada', 'Activada (p. ej. pagando este Oro)'),
      Opcion('continua', 'Continua (mientras está en la Reserva de Oro)'),
      Opcion('al_jugar', 'Al jugarse en la Reserva'),
      Opcion('propia_entra', 'Cuando una carta tuya entra en juego'),
      Opcion('propia_sale', 'Cuando una carta tuya sale del juego'),
      Opcion('al_inicio_fase', 'Al comienzo de la fase indicada'),
      Opcion('oponente_juega', 'Cuando el oponente juega una carta'),
      Opcion(
        'al_botar_por_oponente',
        'Cuando botas cartas por una habilidad oponente',
      ),
    ];
  }
  if (t.startsWith('t')) {
    // Tótem: está en la Línea de Apoyo; no ataca ni bloquea.
    return kCuando
        .where(
          (o) =>
              !const {
                'al_atacar',
                'al_bloquear',
                'al_ser_bloqueado',
                'al_hacer_dano',
              }.contains(o.id),
        )
        .toList();
  }
  return kCuando;
}

const kFases = [
  Opcion('cualquiera', 'Cualquiera'),
  Opcion('agrupacion', 'Agrupación'),
  Opcion('vigilia', 'Vigilia'),
  Opcion('declaracion_ataque', 'Declaración de ataque'),
  Opcion('declaracion_bloqueo', 'Declaración de bloqueo'),
  Opcion('guerra_talismanes', 'Guerra de Talismanes'),
  Opcion('asignacion_dano', 'Asignación de daño'),
  Opcion('final', 'Fase Final'),
];

const kTurno = [
  Opcion('cualquiera', 'En cualquier turno'),
  Opcion('propio', 'Solo en tu turno'),
  Opcion('oponente', 'Solo en el turno oponente'),
];

const kCondiciones = [
  Opcion('ninguna', 'Sin condición'),
  Opcion('aliados_propios', 'Cantidad de Aliados que controlas'),
  Opcion('aliados_oponente', 'Cantidad de Aliados del oponente'),
  Opcion('oros_reserva', 'Oros en tu Reserva'),
  Opcion('cartas_mano', 'Cartas en tu mano'),
  Opcion('cartas_mazo', 'Cartas en tu Mazo Castillo'),
  Opcion('cartas_cementerio', 'Cartas en tu Cementerio'),
  Opcion('aliados_raza', 'Aliados propios de la raza indicada'),
  Opcion('oros_en_juego', 'Oros que controlas (Reserva + pagados)'),
  Opcion(
    'oros_vs_oponente',
    'Tus Oros menos los del oponente (≤ 0 = igual o menos que él)',
  ),
  Opcion('aliados_arquetipo', 'Aliados propios del arquetipo indicado'),
  Opcion(
    'aliados_no_raza',
    'Aliados propios que NO son de la raza indicada (= 0: todos lo son)',
  ),
  Opcion('aliados_misma_raza', 'Máximo de Aliados propios de una misma raza'),
  Opcion(
    'aliados_vs_oponente',
    'Tus Aliados menos los del oponente (< 0 = tienes menos)',
  ),
  Opcion('mano_arquetipo', 'Cartas en tu mano del arquetipo indicado'),
  Opcion('mano_raza', 'Cartas en tu mano de la raza indicada'),
  Opcion('esta_carta_ataco', 'Esta carta fue declarada atacante este turno'),
  Opcion(
    'atacantes_arquetipo',
    'Aliados tuyos del arquetipo indicado declarados atacantes este turno',
  ),
  Opcion(
    'esta_carta_no_ataco',
    'Esta carta NO fue declarada atacante este turno',
  ),
  Opcion('bloquea_imbloqueable', 'Esta carta bloquea a un Aliado Imbloqueable'),
  Opcion('porta_armas', 'Armas que porta esta carta'),
  Opcion('primer_turno', 'Es tu primer turno (1 = sí)'),
  Opcion('hizo_dano', 'Esta carta hizo daño este turno (1 = sí)'),
  Opcion('atacantes_raza', 'Aliados de la raza indicada en tu Línea de Ataque'),
  Opcion(
    'destierro_vs_oponente',
    'Tus cartas desterradas menos las del oponente (> 0 = tienes más)',
  ),
];

/// Valor multiplicado "por cada…" (Djoser: +2 por cada Arma que porta).
const kPorCada = [
  Opcion('', 'Valor fijo'),
  Opcion('arma_portada', 'Por cada Arma que porta'),
  Opcion('aliado_propio', 'Por cada Aliado que controlas'),
  Opcion('oro_en_juego', 'Por cada Oro que controlas'),
  Opcion('aliado_arquetipo', 'Por cada Aliado propio del arquetipo indicado'),
  Opcion('aliado_raza', 'Por cada otro Aliado en juego de la raza indicada'),
  Opcion('otro_en_ataque', 'Por cada otro Aliado en tu Línea de Ataque'),
  Opcion('carta_arquetipo', 'Por cada otra carta tuya en juego del arquetipo'),
];

/// Quién puede usar una habilidad activada.
const kUsaQuien = [
  Opcion('controlador', 'Tú (quien la controla)'),
  Opcion('oponente', 'Tu oponente'),
  Opcion('ambos', 'Cualquier jugador'),
];

/// "¿Cuántas?": un número fijo o "tantas como…".
const kCantidadSegun = [
  Opcion('fijo', 'Un número fijo'),
  Opcion('oros_que_controla', 'Tantas como Oros controle ese jugador'),
  Opcion(
    'fuerza_mayor_aliado_oponente',
    'Tantas como la fuerza del Aliado de mayor fuerza del oponente',
  ),
  Opcion('coste_afectada', 'Tantas como el coste de la carta afectada'),
  Opcion('fuerza_afectada', 'Tantas como la fuerza de la carta afectada'),
  Opcion('dano_hecho', 'Tantas como el daño que hizo (al hacer daño)'),
  Opcion('num_afectadas', 'Tantas como las cartas afectadas'),
  Opcion('fuerza_esta_carta', 'Tantas como la fuerza de esta carta'),
  Opcion('cartas_botadas', 'Tantas como las cartas que botaste'),
  Opcion('num_atacantes', 'Tantas como tus Aliados atacantes'),
  Opcion('aliados_propios', 'Tantas como Aliados tengas en juego'),
  Opcion('aliados_arquetipo', 'Tantas como tus Aliados del arquetipo indicado'),
  Opcion('coste_disparadora', 'Tantas como el coste de la carta que disparó'),
];

/// Condición "Oros vs oponente" (Kawit) en palabras: el operador compara
/// (tus Oros − los del oponente) con 0.
const kOrosVsOponente = [
  Opcion('<=', 'Tienes igual o menos Oros que el oponente'),
  Opcion('<', 'Tienes menos Oros que el oponente'),
  Opcion('==', 'Tienes los mismos Oros que el oponente'),
  Opcion('>=', 'Tienes igual o más Oros que el oponente'),
  Opcion('>', 'Tienes más Oros que el oponente'),
];

const kOperadores = [
  Opcion('>=', '≥'),
  Opcion('<=', '≤'),
  Opcion('==', '='),
  Opcion('>', '>'),
  Opcion('<', '<'),
];

const kQuien = [
  Opcion('esta_carta', 'Esta misma carta'),
  Opcion('propio', 'Tuyas'),
  Opcion('oponente', 'Del oponente'),
  Opcion('cualquiera', 'De cualquier jugador'),
  Opcion('ambos', 'Cada jugador, de las suyas (cada uno elige)'),
  Opcion('disparadora', 'La carta que activó el disparador'),
  Opcion('proximo', 'El próximo Aliado que juegues este turno'),
];

const kJugadorObjetivo = [
  Opcion('propio', 'Tú'),
  Opcion('oponente', 'Tu oponente'),
  Opcion('ambos', 'Ambos jugadores'),
];

const kTiposCarta = ['Aliado', 'Arma', 'Talismán', 'Tótem', 'Oro'];

const kZonas = [
  Opcion('en_juego', 'En juego (cualquier línea)'),
  Opcion('linea_defensa', 'Línea de Defensa'),
  Opcion('linea_ataque', 'Línea de Ataque'),
  Opcion('linea_apoyo', 'Línea de Apoyo'),
  Opcion('reserva_oro', 'Reserva de Oro'),
  Opcion('mano', 'Mano'),
  Opcion('mazo', 'Mazo Castillo'),
  Opcion('cementerio', 'Cementerio'),
  Opcion('destierro', 'Zona de Destierro'),
];

const kSeleccion = [
  Opcion('elige', 'El jugador elige'),
  Opcion('todos', 'Todas las que cumplan'),
  Opcion('azar', 'Al azar'),
  Opcion('tope', 'Las de arriba (desde el tope del Mazo)'),
  Opcion('mayor_fuerza', 'La de mayor fuerza (si empatan, elige)'),
];

/// Mirar las de arriba: a dónde va lo que no se toma.
const kRestoA = [
  Opcion('mazo_tope', 'Se quedan arriba del Mazo'),
  Opcion('mazo_fondo', 'Al fondo del Mazo'),
  Opcion('cementerio', 'Al Cementerio'),
  Opcion('elegir_tope_fondo', 'El jugador elige: arriba o al fondo'),
  Opcion('barajar', 'Se barajan en el Mazo'),
];

/// Mirar las de arriba: zonas para repartir una carta a cada una (La Odisea).
const kRepartir = [
  Opcion('mano', 'Mano'),
  Opcion('cementerio', 'Cementerio'),
  Opcion('destierro', 'Destierro'),
];

/// Destinos para Mover / Buscar / Poner en juego.
const kDestinos = [
  Opcion('mano', 'A la mano'),
  Opcion('mazo_tope', 'Al tope del Mazo Castillo'),
  Opcion('mazo_fondo', 'Al fondo del Mazo Castillo'),
  Opcion('linea_ataque', 'A la Línea de Ataque'),
  Opcion('linea_defensa', 'A la Línea de Defensa'),
  Opcion('en_juego', 'Al juego (su zona normal)'),
  Opcion('reserva_oro', 'A la Reserva de Oro'),
  Opcion('cementerio', 'Al Cementerio'),
  Opcion('destierro', 'A la Zona de Destierro'),
];

/// Dónde debe estar esta carta para usar la habilidad.
const kZonaActivacion = [
  Opcion('en_juego', 'En juego'),
  Opcion('reserva_oro', 'En la Reserva de Oro (Oros)'),
  Opcion('reserva_o_pagado', 'En la Reserva u Oro Pagado (Oros)'),
  Opcion('cementerio', 'En el Cementerio'),
  Opcion('mano', 'En la mano'),
];

/// Opciones de `modo` según la acción. Vacío = la acción no usa modo.
const kModos = <Accion, List<Opcion>>{
  Accion.prevenir: [
    Opcion(
      'destruir_desterrar',
      'Que sea destruida o desterrada (cualquier causa)',
    ),
    Opcion(
      'por_habilidad_oponente',
      'Que sea destruida o desterrada por una habilidad oponente',
    ),
    Opcion('afectada', 'Que sea afectada por una habilidad oponente'),
    Opcion('barajar_en_vez', 'Si fuera a ser destruida, se baraja en el Mazo'),
    Opcion(
      'barajar_en_vez_oponente',
      'Si la destruye una carta oponente, se baraja en el Mazo',
    ),
  ],
  Accion.otorgarPropiedad: [
    Opcion('indestructible', 'Indestructible'),
    Opcion('indesterrable', 'Indesterrable'),
    Opcion('imbloqueable', 'Imbloqueable'),
    Opcion('furia', 'Puede atacar el turno que entra'),
    Opcion('noAnulable', 'No anulable'),
    Opcion('quitarGuardian', 'Pierde "no puede ser declarado atacante"'),
  ],
  Accion.robar: [
    Opcion('tope', 'Desde arriba del Mazo (normal)'),
    Opcion('fondo', 'Desde el fondo del Mazo'),
  ],
  Accion.restringirCombate: [
    Opcion('no_puede_bloquear', 'No puede bloquear'),
    Opcion('no_puede_atacar', 'No puede atacar'),
    Opcion('no_puede_ser_bloqueado', 'No puede ser bloqueado'),
    Opcion('puede_bloquear_imbloqueables', 'Puede bloquear imbloqueables'),
    Opcion('puede_atacar_este_turno', 'Puede atacar este turno'),
    Opcion('debe_bloquear', 'Debe ser declarado bloqueador este turno'),
    Opcion(
      'no_bloqueable_por_fuerza',
      'No la bloquean Aliados de fuerza N o más (N = valor)',
    ),
  ],
  Accion.cancelarAtaque: [
    Opcion(
      'todo_el_ataque',
      'Todo el ataque (vuelven a defensa y pasa a Fase Final)',
    ),
    Opcion('un_atacante', 'El ataque de un Aliado'),
    Opcion('un_bloqueo', 'Un bloqueo'),
    Opcion(
      'ataque_o_bloqueo',
      'El ataque o el bloqueo oponente (según el turno)',
    ),
  ],
  Accion.reducirDano: [
    Opcion('dano_a_cero', 'El daño que recibirías queda en 0'),
    Opcion('reducir_en_n', 'El daño que recibirías se reduce en N'),
    Opcion('aliado_sin_dano', 'Un Aliado no hace daño este turno'),
  ],
  Accion.agrupar: [
    Opcion('ambos', 'Aliados y Oros'),
    Opcion('aliados', 'Solo Aliados'),
    Opcion('oros', 'Solo Oros'),
  ],
  Accion.noAgrupar: [
    Opcion('ambos', 'Aliados y Oros'),
    Opcion('aliados', 'Solo Aliados'),
    Opcion('oros', 'Solo Oros'),
  ],
  Accion.restriccion: [
    Opcion('barajar', 'No se pueden barajar cartas'),
    Opcion(
      'barajar_cementerio',
      'No se pueden barajar cartas del Cementerio en el Mazo',
    ),
    Opcion(
      'desterrar_cementerio',
      'No se pueden desterrar cartas del Cementerio',
    ),
    Opcion('desterrar', 'No se pueden desterrar cartas'),
    Opcion('destruir', 'No se pueden destruir cartas'),
    Opcion('jugar_tipo', 'No se pueden jugar cartas del tipo indicado'),
    Opcion('robar_extra', 'No se pueden robar cartas extra'),
    Opcion('declarar_ataque', 'No se puede declarar ataque'),
    Opcion('requisito_jugar', 'Solo se puede jugar si se cumple la condición'),
    Opcion('ataque_total', 'Si ataca, deben atacar todos tus Aliados'),
    Opcion('anulable_pagando', 'El oponente puede anularla pagando N Oros'),
    Opcion('atacante_libre_fuerza_1', 'Atacante no bloqueado tiene fuerza 1'),
    Opcion('dano_destierra', 'Su daño de combate se destierra'),
    Opcion(
      'bloqueo_obligatorio',
      'El oponente debe bloquear con al menos un Aliado cada turno',
    ),
  ],
  Accion.mirar: [
    Opcion('mano_oponente', 'La mano del oponente'),
    Opcion('mazo_propio', 'Cartas del tope de tu Mazo'),
    Opcion('mazo_oponente', 'Cartas del tope del Mazo oponente'),
  ],
  Accion.jugarDesde: [
    Opcion('sin_pagar', 'Sin pagar su coste'),
    Opcion('pagando', 'Pagando su coste'),
  ],
};

/// Duraciones típicas de Ganar control.
const kDuracionControl = [
  Opcion('hasta_fase_final', 'Hasta la Fase Final'),
  Opcion('mientras_en_juego', 'Mientras esta carta esté en juego'),
  Opcion('permanente', 'Hasta que la carta controlada salga del juego'),
];

/// Para efectos "Luego…": sobre qué cartas actúa respecto del efecto anterior.
const kReferencia = [
  Opcion('ninguna', 'Cartas nuevas (según el filtro)'),
  Opcion('afectadas', 'Las mismas cartas afectadas antes'),
  Opcion('copias', 'Las copias de las cartas afectadas'),
  Opcion('mismo_tipo', 'Otras cartas del mismo tipo que las afectadas'),
];

const kRelacion = [
  Opcion('si_se_cumplio', 'Solo si el efecto anterior se cumplió'),
  Opcion('siempre', 'Siempre'),
  Opcion(
    'si_afectada_hizo_dano',
    'Si la carta afectada hizo daño al Mazo Castillo oponente este turno',
  ),
  Opcion('si_no_se_cumplio', 'Solo si el efecto anterior NO se cumplió'),
  Opcion(
    'si_afectada_cumple',
    'Si la carta afectada cumple un filtro (raza o arquetipo)',
  ),
];

/// Cuándo se resuelve un efecto "Luego…".
const kMomento = [
  Opcion('inmediato', 'En el momento'),
  Opcion('fase_final', 'En la Fase Final de este turno'),
];

const kModoFuerza = [
  Opcion('sumar', 'Sumar (+N / -N)'),
  Opcion('fijar', 'Fijar en N'),
  Opcion('duplicar', 'Duplicar'),
  Opcion('base', 'Volver a su fuerza impresa (cancela bonificaciones)'),
];

const kDuracion = [
  Opcion('instantaneo', 'Instantáneo'),
  Opcion('hasta_fase_final', 'Hasta la Fase Final'),
  Opcion('hasta_vigilia', 'Hasta tu próxima Vigilia'),
  Opcion('mientras_en_juego', 'Mientras esta carta esté en juego'),
  Opcion('permanente', 'Permanente (resto del juego)'),
  Opcion('proximo_turno', 'Durante tu próximo turno'),
];

/// Campos de un mapa que este editor no conoce: se conservan tal cual al
/// guardar (los agrega el agente para el simulador).
Map<String, dynamic> _extra(Map m, Set<String> conocidas) => {
  for (final e in m.entries)
    if (!conocidas.contains('${e.key}')) '${e.key}': e.value,
};

const _clavesObjetivo = {
  'quien',
  'tipos',
  'zona',
  'coste',
  'fuerza',
  'raza',
  'seleccion',
  'referencia',
  'zonas',
  'nombrarRaza',
  'excluirRazas',
  'nombrarCarta',
  'arquetipo',
  'excluirEstaCarta',
  'filtroSoloAliados',
  'combate',
};
const _clavesCosto = {
  'oros',
  'descartar',
  'botar',
  'destruirEstaCarta',
  'desterrarEstaCarta',
  'pagarEstaCarta',
  'fondoMazoEstaCarta',
  'desterrarCementerio',
  'desterrarCementerioSegun',
  'desterrarAliados',
  'destruirAliados',
  'barajarMano',
  'barajarEstaCarta',
  'moverEstaCartaAtaque',
  'orosSegun',
};
const _clavesLuego = {
  'accion',
  'relacion',
  'momento',
  'modo',
  'objetivo',
  'cantidad',
  'valor',
  'modoFuerza',
  'zonaDestino',
  'duracion',
  'cantidadSegun',
  'condicion',
  'opcional',
  'costo',
  'filtroAfectada',
  'razaNueva',
  'grupoElegir',
};
const _clavesHabilidad = {
  'featureId',
  'featureName',
  'accion',
  'cuando',
  'fase',
  'turno',
  'condicion',
  'costo',
  'objetivo',
  'cantidad',
  'valor',
  'modoFuerza',
  'zonaDestino',
  'duracion',
  'opcional',
  'limitePorTurno',
  'cantidadSegun',
  'talismanVaA',
  'valorPorCada',
  'disparoTipos',
  'usaQuien',
  'costoAlternativo',
  'limitePorNombre',
  'disparoRaza',
  'luego',
  'modo',
  'soloParaTipos',
  'soloParaRaza',
  'zonaActivacion',
  'grupoLimite',
  'porCadaArquetipo',
  'restoA',
  'repartir',
  'razaNueva',
  'grupoElegir',
  'soloParaCosteMin',
  'disparoCosteMin',
  'vetaCarta',
  // Obsoleto: se descarta al guardar (las notas van en la carta).
  'notas',
};

String labelDe(List<Opcion> opciones, String? id) =>
    opciones.where((o) => o.id == id).firstOrNull?.label ?? (id ?? '');

/// Comparación numérica opcional: "coste ≤ 2", "fuerza ≥ 3"…
class Comparacion {
  final String op;
  final int valor;

  /// Valor dinámico: '' = [valor] fijo; 'aliados_raza' = cantidad de Aliados
  /// propios de [raza] (Ganimedes: coste ≤ tus Aliados Héroe).
  final String segun;
  final String raza;

  /// Con `segun: 'aliados_arquetipo'` (Minotauro Colosal: coste ≤ tus
  /// Minotauros): el arquetipo que se cuenta.
  final String arquetipo;
  const Comparacion(
    this.op,
    this.valor, {
    this.segun = '',
    this.raza = '',
    this.arquetipo = '',
  });

  static Comparacion? fromMap(dynamic m) {
    if (m is! Map) return null;
    final segun = (m['segun'] ?? '').toString();
    if (m['valor'] is! num && segun.isEmpty) return null;
    return Comparacion(
      (m['op'] ?? '<=').toString(),
      (m['valor'] is num) ? (m['valor'] as num).toInt() : 0,
      segun: segun,
      raza: (m['raza'] ?? '').toString(),
      arquetipo: (m['arquetipo'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'op': op,
    'valor': valor,
    if (segun.isNotEmpty) 'segun': segun,
    if (segun.isNotEmpty && raza.isNotEmpty) 'raza': raza,
    if (segun.isNotEmpty && arquetipo.isNotEmpty) 'arquetipo': arquetipo,
  };

  @override
  String toString() =>
      segun == 'aliados_raza'
          ? '${labelDe(kOperadores, op)} tus Aliados $raza'
          : segun == 'aliados_arquetipo'
          ? '${labelDe(kOperadores, op)} tus Aliados $arquetipo'
          : '${labelDe(kOperadores, op)} $valor';
}

class ObjetivoHabilidad {
  /// Para acciones sobre cartas: esta_carta | propio | oponente | cualquiera.
  /// Para acciones sobre jugadores (robar, botar, descartar…): propio |
  /// oponente | ambos.
  final String quien;
  final List<String> tipos;
  final String zona;
  final Comparacion? coste;
  final Comparacion? fuerza;
  final String raza;
  final String seleccion;

  /// Solo en efectos "Luego…" (ver [kReferencia]).
  final String referencia;

  /// Varias zonas de origen (p. ej. Cementerio o Mazo). Vacío = solo [zona].
  final List<String> zonas;

  /// La raza la nombra el jugador cuando la carta entra en juego (Cleopatra
  /// VII), salvo [excluirRazas].
  final bool nombrarRaza;
  final List<String> excluirRazas;

  /// La carta la nombra el jugador al entrar en juego; afecta a todas sus
  /// copias (Takelot).
  final bool nombrarCarta;

  /// Arquetipo (Druida, Goblin, Minotauro…): va en el nombre de la carta,
  /// no en su raza.
  final String arquetipo;

  /// "Tus demás Aliados", "que no sea Amergin": excluye esta carta y sus
  /// copias.
  final bool excluirEstaCarta;

  /// Raza y arquetipo se exigen solo a los Aliados ("un Oro o un Aliado
  /// Druida", Tadg el Druida).
  final bool filtroSoloAliados;

  /// Solo Aliados declarados atacantes o bloqueadores este turno (Toque de
  /// Pérsival).
  final bool combate;

  /// Campos que este editor no conoce (se conservan al guardar).
  final Map<String, dynamic> extra;

  List<String> get todasLasZonas => zonas.isEmpty ? [zona] : zonas;

  const ObjetivoHabilidad({
    this.quien = 'oponente',
    this.tipos = const [],
    this.zona = 'en_juego',
    this.coste,
    this.fuerza,
    this.raza = '',
    this.seleccion = 'elige',
    this.referencia = 'ninguna',
    this.zonas = const [],
    this.nombrarRaza = false,
    this.excluirRazas = const [],
    this.nombrarCarta = false,
    this.arquetipo = '',
    this.excluirEstaCarta = false,
    this.filtroSoloAliados = false,
    this.combate = false,
    this.extra = const {},
  });

  factory ObjetivoHabilidad.fromMap(dynamic m) {
    if (m is! Map) return const ObjetivoHabilidad();
    return ObjetivoHabilidad(
      quien: (m['quien'] ?? 'oponente').toString(),
      tipos:
          (m['tipos'] is List)
              ? (m['tipos'] as List).map((e) => '$e').toList()
              : const [],
      zona: (m['zona'] ?? 'en_juego').toString(),
      coste: Comparacion.fromMap(m['coste']),
      fuerza: Comparacion.fromMap(m['fuerza']),
      raza: (m['raza'] ?? '').toString(),
      seleccion: (m['seleccion'] ?? 'elige').toString(),
      referencia: (m['referencia'] ?? 'ninguna').toString(),
      zonas:
          (m['zonas'] is List)
              ? (m['zonas'] as List).map((e) => '$e').toList()
              : const [],
      nombrarRaza: m['nombrarRaza'] == true,
      excluirRazas:
          (m['excluirRazas'] is List)
              ? (m['excluirRazas'] as List).map((e) => '$e').toList()
              : const [],
      nombrarCarta: m['nombrarCarta'] == true,
      arquetipo: (m['arquetipo'] ?? '').toString(),
      excluirEstaCarta: m['excluirEstaCarta'] == true,
      filtroSoloAliados: m['filtroSoloAliados'] == true,
      combate: m['combate'] == true,
      extra: _extra(m, _clavesObjetivo),
    );
  }

  Map<String, dynamic> toMap() => {
    ...extra,
    'quien': quien,
    'tipos': tipos,
    'zona': zona,
    if (coste != null) 'coste': coste!.toMap(),
    if (fuerza != null) 'fuerza': fuerza!.toMap(),
    if (raza.isNotEmpty) 'raza': raza,
    'seleccion': seleccion,
    if (referencia != 'ninguna') 'referencia': referencia,
    if (zonas.length > 1) 'zonas': zonas,
    if (nombrarRaza) 'nombrarRaza': true,
    if (nombrarRaza && excluirRazas.isNotEmpty) 'excluirRazas': excluirRazas,
    if (nombrarCarta) 'nombrarCarta': true,
    if (arquetipo.isNotEmpty) 'arquetipo': arquetipo,
    if (excluirEstaCarta) 'excluirEstaCarta': true,
    if (filtroSoloAliados) 'filtroSoloAliados': true,
    if (combate) 'combate': true,
  };

  ObjetivoHabilidad copyWith({
    String? quien,
    List<String>? tipos,
    String? zona,
    Comparacion? Function()? coste,
    Comparacion? Function()? fuerza,
    String? raza,
    String? seleccion,
    String? referencia,
    List<String>? zonas,
    bool? nombrarRaza,
    List<String>? excluirRazas,
    bool? nombrarCarta,
    String? arquetipo,
    bool? excluirEstaCarta,
    bool? filtroSoloAliados,
    bool? combate,
  }) => ObjetivoHabilidad(
    quien: quien ?? this.quien,
    tipos: tipos ?? this.tipos,
    zona: zona ?? this.zona,
    coste: coste != null ? coste() : this.coste,
    fuerza: fuerza != null ? fuerza() : this.fuerza,
    raza: raza ?? this.raza,
    seleccion: seleccion ?? this.seleccion,
    referencia: referencia ?? this.referencia,
    zonas: zonas ?? this.zonas,
    nombrarRaza: nombrarRaza ?? this.nombrarRaza,
    excluirRazas: excluirRazas ?? this.excluirRazas,
    nombrarCarta: nombrarCarta ?? this.nombrarCarta,
    arquetipo: arquetipo ?? this.arquetipo,
    excluirEstaCarta: excluirEstaCarta ?? this.excluirEstaCarta,
    filtroSoloAliados: filtroSoloAliados ?? this.filtroSoloAliados,
    combate: combate ?? this.combate,
    extra: extra,
  );
}

/// Texto del efecto: "Desterrar 1 Aliado/Tótem del oponente en juego".
String describirEfecto({
  required Accion accion,
  required ObjetivoHabilidad objetivo,
  required int cantidad,
  required int valor,
  required String modoFuerza,
  required String duracion,
  String cantidadSegun = 'fijo',
}) {
  final o = objetivo;
  final partes = <String>[accion.label];
  final variable = cantidadSegun != 'fijo';
  final cuantas =
      variable
          ? labelDe(kCantidadSegun, cantidadSegun).toLowerCase()
          : '$cantidad';
  if (accion.usaObjetivoCartas) {
    if (o.referencia == 'afectadas') {
      partes.add('las mismas cartas');
    } else {
      partes.add(o.seleccion == 'todos' ? 'todas las' : cuantas);
      partes.add(
        o.referencia == 'copias'
            ? 'copias de las afectadas'
            : (o.tipos.isEmpty ? 'cartas' : o.tipos.join('/')),
      );
      partes.add(labelDe(kQuien, o.quien).toLowerCase());
      if (o.coste != null) partes.add('coste ${o.coste}');
      if (o.fuerza != null) partes.add('fuerza ${o.fuerza}');
      if (o.nombrarCarta)
        partes.add('(la carta nombrada al entrar y sus copias)');
      if (o.nombrarRaza) {
        partes.add(
          'de la raza nombrada al entrar'
          '${o.excluirRazas.isEmpty ? '' : ' (no ${o.excluirRazas.join('/')})'}',
        );
      } else if (o.raza.isNotEmpty) {
        partes.add('raza ${o.raza}');
      }
      partes.add(
        'en ${o.todasLasZonas.map((z) => labelDe(kZonas, z).toLowerCase()).join(' o ')}',
      );
    }
  } else {
    if ((cantidad > 0 || variable) && accion != Accion.generarOro) {
      partes.add(cuantas);
    }
    if (accion == Accion.generarOro) partes.add('$valor');
    partes.add('(${labelDe(kJugadorObjetivo, o.quien).toLowerCase()})');
  }
  if (accion.usaModoFuerza) {
    partes.add(
      modoFuerza == 'duplicar'
          ? 'x2'
          : modoFuerza == 'fijar'
          ? '= $valor'
          : (valor >= 0 ? '+$valor' : '$valor'),
    );
  }
  if (duracion != 'instantaneo') {
    partes.add(labelDe(kDuracion, duracion).toLowerCase());
  }
  return partes.join(' ');
}

/// Efecto que se resuelve después del principal ("…luego, destierra…").
class EfectoLuego {
  final Accion accion;

  /// Ver [kRelacion].
  final String relacion;

  /// inmediato | fase_final (ver [kMomento]).
  final String momento;

  /// Variante de la acción (ver [kModos]): "No puede ser bloqueado",
  /// "Indesterrable"…
  final String modo;
  final ObjetivoHabilidad objetivo;
  final int cantidad;
  final int valor;
  final String modoFuerza;
  final String zonaDestino;
  final String duracion;
  final String cantidadSegun;
  final CondicionHabilidad condicion;
  final bool opcional;
  final CostoHabilidad costo;

  /// Con relación 'si_afectada_cumple': la carta afectada debe ser de esta
  /// raza o arquetipo (Druida Sanador: "si ese Aliado es un Druida").
  final String filtroRaza;
  final String filtroArquetipo;

  /// Con relación 'si_afectada_cumple': la afectada debe ser de alguno de
  /// estos tipos (Ramsés IX: "si entre esas cartas hay un Oro o un Aliado").
  final List<String> filtroTipos;

  /// Con 'cambiarRaza': la raza que pasan a tener.
  final String razaNueva;

  /// Efectos "luego" con el mismo grupo: se resuelve solo uno ("elige").
  final String grupoElegir;

  /// Campos que este editor no conoce, y los del filtro de la afectada
  /// (p. ej. "combate": atacó o bloqueó).
  final Map<String, dynamic> extra;
  final Map<String, dynamic> filtroExtra;

  const EfectoLuego({
    required this.accion,
    this.relacion = 'si_se_cumplio',
    this.momento = 'inmediato',
    this.modo = '',
    this.objetivo = const ObjetivoHabilidad(),
    this.cantidad = 1,
    this.valor = 0,
    this.modoFuerza = 'sumar',
    this.zonaDestino = 'mano',
    this.duracion = 'instantaneo',
    this.cantidadSegun = 'fijo',
    this.condicion = const CondicionHabilidad(),
    this.opcional = false,
    this.costo = const CostoHabilidad(),
    this.filtroRaza = '',
    this.filtroArquetipo = '',
    this.filtroTipos = const [],
    this.razaNueva = '',
    this.grupoElegir = '',
    this.extra = const {},
    this.filtroExtra = const {},
  });

  factory EfectoLuego.fromMap(Map<String, dynamic> m) => EfectoLuego(
    accion: Accion.parse(m['accion']?.toString()),
    relacion: (m['relacion'] ?? 'si_se_cumplio').toString(),
    momento: (m['momento'] ?? 'inmediato').toString(),
    modo: (m['modo'] ?? '').toString(),
    objetivo: ObjetivoHabilidad.fromMap(m['objetivo']),
    cantidad: (m['cantidad'] as num?)?.toInt() ?? 1,
    valor: (m['valor'] as num?)?.toInt() ?? 0,
    modoFuerza: (m['modoFuerza'] ?? 'sumar').toString(),
    zonaDestino: (m['zonaDestino'] ?? 'mano').toString(),
    duracion: (m['duracion'] ?? 'instantaneo').toString(),
    cantidadSegun: (m['cantidadSegun'] ?? 'fijo').toString(),
    condicion: CondicionHabilidad.fromMap(m['condicion']),
    opcional: m['opcional'] == true,
    costo: CostoHabilidad.fromMap(m['costo']),
    filtroRaza: '${(m['filtroAfectada'] as Map?)?['raza'] ?? ''}',
    filtroArquetipo: '${(m['filtroAfectada'] as Map?)?['arquetipo'] ?? ''}',
    filtroTipos:
        ((m['filtroAfectada'] as Map?)?['tipos'] is List)
            ? ((m['filtroAfectada'] as Map)['tipos'] as List)
                .map((e) => '$e')
                .toList()
            : const [],
    razaNueva: (m['razaNueva'] ?? '').toString(),
    grupoElegir: (m['grupoElegir'] ?? '').toString(),
    extra: _extra(m, _clavesLuego),
    filtroExtra:
        (m['filtroAfectada'] is Map)
            ? _extra(m['filtroAfectada'] as Map, const {
              'raza',
              'arquetipo',
              'tipos',
            })
            : const {},
  );

  Map<String, dynamic> toMap() => {
    ...extra,
    'accion': accion.name,
    'relacion': relacion,
    if (accion == Accion.cambiarRaza && razaNueva.isNotEmpty)
      'razaNueva': razaNueva,
    if (relacion == 'si_afectada_cumple')
      'filtroAfectada': {
        ...filtroExtra,
        if (filtroRaza.isNotEmpty) 'raza': filtroRaza,
        if (filtroArquetipo.isNotEmpty) 'arquetipo': filtroArquetipo,
        if (filtroTipos.isNotEmpty) 'tipos': filtroTipos,
      },
    if (grupoElegir.isNotEmpty) 'grupoElegir': grupoElegir,
    if (cantidadSegun != 'fijo') 'cantidadSegun': cantidadSegun,
    if (!condicion.esNinguna) 'condicion': condicion.toMap(),
    if (opcional) 'opcional': true,
    if (!costo.esGratis) 'costo': costo.toMap(),
    if (momento != 'inmediato') 'momento': momento,
    if (modo.isNotEmpty) 'modo': modo,
    'objetivo': objetivo.toMap(),
    'cantidad': cantidad,
    'valor': valor,
    if (accion.usaModoFuerza) 'modoFuerza': modoFuerza,
    if (accion.usaZonaDestino) 'zonaDestino': zonaDestino,
    'duracion': duracion,
  };

  EfectoLuego copyWith({
    Accion? accion,
    String? relacion,
    String? momento,
    String? modo,
    ObjetivoHabilidad? objetivo,
    int? cantidad,
    int? valor,
    String? modoFuerza,
    String? zonaDestino,
    String? duracion,
    String? cantidadSegun,
    CondicionHabilidad? condicion,
    bool? opcional,
    CostoHabilidad? costo,
    String? filtroRaza,
    String? filtroArquetipo,
    List<String>? filtroTipos,
    String? razaNueva,
    String? grupoElegir,
  }) => EfectoLuego(
    accion: accion ?? this.accion,
    relacion: relacion ?? this.relacion,
    momento: momento ?? this.momento,
    modo: modo ?? this.modo,
    objetivo: objetivo ?? this.objetivo,
    cantidad: cantidad ?? this.cantidad,
    valor: valor ?? this.valor,
    modoFuerza: modoFuerza ?? this.modoFuerza,
    zonaDestino: zonaDestino ?? this.zonaDestino,
    duracion: duracion ?? this.duracion,
    cantidadSegun: cantidadSegun ?? this.cantidadSegun,
    condicion: condicion ?? this.condicion,
    opcional: opcional ?? this.opcional,
    costo: costo ?? this.costo,
    filtroRaza: filtroRaza ?? this.filtroRaza,
    filtroArquetipo: filtroArquetipo ?? this.filtroArquetipo,
    filtroTipos: filtroTipos ?? this.filtroTipos,
    razaNueva: razaNueva ?? this.razaNueva,
    grupoElegir: grupoElegir ?? this.grupoElegir,
    extra: extra,
    filtroExtra: filtroExtra,
  );

  String get resumen {
    final cond = [
      if (relacion == 'si_se_cumplio') 'si se cumplió',
      if (relacion == 'si_no_se_cumplio') 'si NO se cumplió',
      if (relacion == 'si_afectada_cumple')
        'si la afectada es ${[filtroRaza, filtroArquetipo, ...filtroTipos].where((x) => x.isNotEmpty).join(' / ')}',
      if (relacion == 'si_afectada_hizo_dano') 'si la afectada hizo daño',
      if (momento == 'fase_final') 'en la Fase Final',
      if (!condicion.esNinguna) condicion.toString(),
      if (!costo.esGratis) costo.toString(),
      if (opcional) 'opcional',
    ];
    final condTxt = cond.isEmpty ? '' : ' (${cond.join(', ')})';
    final efecto = describirEfecto(
      accion: accion,
      objetivo: objetivo,
      cantidad: cantidad,
      valor: valor,
      modoFuerza: modoFuerza,
      duracion: duracion,
      cantidadSegun: cantidadSegun,
    );
    final modos = kModos[accion];
    final modoTxt =
        modos != null && modo.isNotEmpty
            ? ' (${labelDe(modos, modo).toLowerCase()})'
            : '';
    return 'Luego$condTxt: $efecto$modoTxt';
  }
}

class CostoHabilidad {
  final int oros;
  final int descartar;
  final int botar;
  final bool destruirEstaCarta;
  final bool desterrarEstaCarta;

  /// Oros: moverlo de la Reserva a la Zona de Oro Pagado.
  final bool pagarEstaCarta;

  /// Poner esta carta al fondo de tu Mazo Castillo (Ritón Aqueménida).
  final bool fondoMazoEstaCarta;

  /// Desterrar N cartas de tu Cementerio; con `coste_objetivo`, N es el coste
  /// de la carta objetivo (p. ej. Nephre-Ka).
  final int desterrarCementerio;
  final String desterrarCementerioSegun;

  /// Desterrar / destruir N de tus otros Aliados (no esta carta), p. ej. Ay.
  final int desterrarAliados;
  final int destruirAliados;

  /// Barajar N cartas de tu mano en tu Mazo Castillo (Piedra Roseta).
  final int barajarMano;

  /// Barajar esta carta en tu Mazo Castillo (Trono Dorado).
  final bool barajarEstaCarta;

  /// Mover este Aliado de la Línea de Defensa a la de Ataque (Achall).
  final bool moverEstaCartaAtaque;

  /// 'coste_objetivo': pagar tantos Oros como el coste de la carta objetivo
  /// (Ceangal An Fhanaigh).
  final String orosSegun;

  /// Costos que este editor no conoce (desterrar de la mano, filtro…).
  final Map<String, dynamic> extra;

  const CostoHabilidad({
    this.oros = 0,
    this.descartar = 0,
    this.botar = 0,
    this.destruirEstaCarta = false,
    this.desterrarEstaCarta = false,
    this.pagarEstaCarta = false,
    this.fondoMazoEstaCarta = false,
    this.desterrarCementerio = 0,
    this.desterrarCementerioSegun = 'fijo',
    this.desterrarAliados = 0,
    this.destruirAliados = 0,
    this.barajarMano = 0,
    this.barajarEstaCarta = false,
    this.moverEstaCartaAtaque = false,
    this.orosSegun = 'fijo',
    this.extra = const {},
  });

  bool get desterraDelCementerio =>
      desterrarCementerio > 0 || desterrarCementerioSegun == 'coste_objetivo';

  bool get esGratis =>
      oros == 0 &&
      descartar == 0 &&
      botar == 0 &&
      !destruirEstaCarta &&
      !desterrarEstaCarta &&
      !pagarEstaCarta &&
      !fondoMazoEstaCarta &&
      !desterraDelCementerio &&
      desterrarAliados == 0 &&
      destruirAliados == 0 &&
      barajarMano == 0 &&
      !barajarEstaCarta &&
      !moverEstaCartaAtaque &&
      orosSegun == 'fijo' &&
      !extra.keys.any((k) => k != 'filtro');

  factory CostoHabilidad.fromMap(dynamic m) {
    if (m is! Map) return const CostoHabilidad();
    int n(String k) => (m[k] as num?)?.toInt() ?? 0;
    return CostoHabilidad(
      oros: n('oros'),
      descartar: n('descartar'),
      botar: n('botar'),
      destruirEstaCarta: m['destruirEstaCarta'] == true,
      desterrarEstaCarta: m['desterrarEstaCarta'] == true,
      pagarEstaCarta: m['pagarEstaCarta'] == true,
      fondoMazoEstaCarta: m['fondoMazoEstaCarta'] == true,
      desterrarCementerio: n('desterrarCementerio'),
      desterrarCementerioSegun:
          (m['desterrarCementerioSegun'] ?? 'fijo').toString(),
      desterrarAliados: n('desterrarAliados'),
      destruirAliados: n('destruirAliados'),
      barajarMano: n('barajarMano'),
      barajarEstaCarta: m['barajarEstaCarta'] == true,
      moverEstaCartaAtaque: m['moverEstaCartaAtaque'] == true,
      orosSegun: (m['orosSegun'] ?? 'fijo').toString(),
      extra: _extra(m, _clavesCosto),
    );
  }

  Map<String, dynamic> toMap() => {
    ...extra,
    if (oros > 0) 'oros': oros,
    if (descartar > 0) 'descartar': descartar,
    if (botar > 0) 'botar': botar,
    if (destruirEstaCarta) 'destruirEstaCarta': true,
    if (desterrarEstaCarta) 'desterrarEstaCarta': true,
    if (pagarEstaCarta) 'pagarEstaCarta': true,
    if (fondoMazoEstaCarta) 'fondoMazoEstaCarta': true,
    if (desterrarCementerio > 0) 'desterrarCementerio': desterrarCementerio,
    if (desterrarCementerioSegun != 'fijo')
      'desterrarCementerioSegun': desterrarCementerioSegun,
    if (desterrarAliados > 0) 'desterrarAliados': desterrarAliados,
    if (destruirAliados > 0) 'destruirAliados': destruirAliados,
    if (barajarMano > 0) 'barajarMano': barajarMano,
    if (barajarEstaCarta) 'barajarEstaCarta': true,
    if (moverEstaCartaAtaque) 'moverEstaCartaAtaque': true,
    if (orosSegun != 'fijo') 'orosSegun': orosSegun,
  };

  @override
  String toString() => [
    if (oros > 0) 'pagar $oros oro${oros == 1 ? '' : 's'}',
    if (descartar > 0) 'descartar $descartar',
    if (botar > 0) 'botar $botar',
    if (destruirEstaCarta) 'destruir esta carta',
    if (desterrarEstaCarta) 'desterrar esta carta',
    if (pagarEstaCarta) 'pagar este Oro',
    if (fondoMazoEstaCarta) 'poner esta carta al fondo de tu Mazo',
    if (desterrarCementerioSegun == 'coste_objetivo')
      'desterrar de tu Cementerio tantas como el coste del objetivo'
    else if (desterrarCementerio > 0)
      'desterrar $desterrarCementerio de tu Cementerio',
    if (desterrarAliados > 0)
      'desterrar $desterrarAliados de tus otros Aliados',
    if (destruirAliados > 0) 'destruir $destruirAliados de tus otros Aliados',
    if (barajarMano > 0) 'barajar $barajarMano de tu mano',
    if (barajarEstaCarta) 'barajar esta carta en tu Mazo',
    if (moverEstaCartaAtaque) 'mover este Aliado a la Línea de Ataque',
    if (orosSegun == 'coste_objetivo') 'pagar Oros igual al coste del objetivo',
  ].join(' + ');

  CostoHabilidad copyWith({
    int? oros,
    int? descartar,
    int? botar,
    bool? destruirEstaCarta,
    bool? desterrarEstaCarta,
    bool? pagarEstaCarta,
    bool? fondoMazoEstaCarta,
    int? desterrarCementerio,
    String? desterrarCementerioSegun,
    int? desterrarAliados,
    int? destruirAliados,
    int? barajarMano,
    bool? barajarEstaCarta,
    bool? moverEstaCartaAtaque,
    String? orosSegun,
  }) => CostoHabilidad(
    oros: oros ?? this.oros,
    descartar: descartar ?? this.descartar,
    botar: botar ?? this.botar,
    destruirEstaCarta: destruirEstaCarta ?? this.destruirEstaCarta,
    desterrarEstaCarta: desterrarEstaCarta ?? this.desterrarEstaCarta,
    pagarEstaCarta: pagarEstaCarta ?? this.pagarEstaCarta,
    fondoMazoEstaCarta: fondoMazoEstaCarta ?? this.fondoMazoEstaCarta,
    desterrarCementerio: desterrarCementerio ?? this.desterrarCementerio,
    desterrarCementerioSegun:
        desterrarCementerioSegun ?? this.desterrarCementerioSegun,
    desterrarAliados: desterrarAliados ?? this.desterrarAliados,
    destruirAliados: destruirAliados ?? this.destruirAliados,
    barajarMano: barajarMano ?? this.barajarMano,
    barajarEstaCarta: barajarEstaCarta ?? this.barajarEstaCarta,
    moverEstaCartaAtaque: moverEstaCartaAtaque ?? this.moverEstaCartaAtaque,
    orosSegun: orosSegun ?? this.orosSegun,
    extra: extra,
  );
}

class CondicionHabilidad {
  final String tipo;
  final String op;
  final int valor;
  final String raza;

  /// Para 'aliados_arquetipo' y 'mano_arquetipo' (Druida, Goblin…).
  final String arquetipo;

  const CondicionHabilidad({
    this.tipo = 'ninguna',
    this.op = '>=',
    this.valor = 1,
    this.raza = '',
    this.arquetipo = '',
  });

  bool get esNinguna => tipo == 'ninguna';

  factory CondicionHabilidad.fromMap(dynamic m) {
    if (m is! Map) return const CondicionHabilidad();
    return CondicionHabilidad(
      tipo: (m['tipo'] ?? 'ninguna').toString(),
      op: (m['op'] ?? '>=').toString(),
      valor: (m['valor'] as num?)?.toInt() ?? 1,
      raza: (m['raza'] ?? '').toString(),
      arquetipo: (m['arquetipo'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() =>
      esNinguna
          ? {'tipo': 'ninguna'}
          : {
            'tipo': tipo,
            'op': op,
            'valor': valor,
            if (raza.isNotEmpty) 'raza': raza,
            if (arquetipo.isNotEmpty) 'arquetipo': arquetipo,
          };

  @override
  String toString() =>
      esNinguna
          ? ''
          : tipo == 'oros_vs_oponente'
          ? 'si ${labelDe(kOrosVsOponente, op).toLowerCase()}'
          : 'si ${labelDe(kCondiciones, tipo).toLowerCase()}'
              '${raza.isEmpty ? '' : ' ($raza)'}${arquetipo.isEmpty ? '' : ' ($arquetipo)'}'
              ' ${labelDe(kOperadores, op)} $valor';
}

class CardHabilidad {
  final String featureId;
  final String featureName;
  final Accion accion;
  final String cuando;
  final String fase;
  final String turno;
  final CondicionHabilidad condicion;
  final CostoHabilidad costo;
  final ObjetivoHabilidad objetivo;
  final int cantidad;

  /// Valor de la acción: +N/-N o N de fuerza, oros generados, etc.
  final int valor;
  final String modoFuerza;

  /// Zona a la que van las cartas en buscar / poner en juego.
  final String zonaDestino;
  final String duracion;
  final bool opcional;

  /// 0 = sin límite.
  final int limitePorTurno;

  /// "¿Cuántas?" variable (ver [kCantidadSegun]); `fijo` usa [cantidad].
  final String cantidadSegun;

  /// Solo Talismanes: a dónde va después de resolverse (Cementerio o
  /// Destierro, p. ej. Gran Guardián).
  final String talismanVaA;

  /// Valor × cantidad (ver [kPorCada]); vacío = valor fijo.
  final String valorPorCada;

  /// "Cuando una carta tuya entra en juego": de qué tipos (vacío = cualquiera).
  final List<String> disparoTipos;

  /// Activadas: quién puede usarla (Nudo de Isis: tu oponente).
  final String usaQuien;

  /// "O en su lugar": otro costo que se puede pagar (vacío = no hay).
  final CostoHabilidad costoAlternativo;

  /// El límite por turno cuenta para todas sus copias (Grandes Faraones).
  final bool limitePorNombre;

  /// "Cuando una carta tuya entra/sale": raza de esa carta (vacío = cualquiera).
  final String disparoRaza;

  /// Efectos que se resuelven después del principal, en orden.
  final List<EfectoLuego> luego;

  /// Variante de la acción (ver [kModos]).
  final String modo;

  /// Generar oro: los oros solo sirven para pagar estos tipos / esta raza.
  final List<String> soloParaTipos;
  final String soloParaRaza;

  /// Dónde debe estar esta carta para usar la habilidad (ver [kZonaActivacion]).
  final String zonaActivacion;

  /// Habilidades con el mismo grupo comparten el límite por turno (Cathbadh:
  /// "+1 o −1 a la fuerza", una vez por turno entre las dos).
  final String grupoLimite;

  /// Con [valorPorCada] 'aliado_arquetipo': el arquetipo que se cuenta.
  final String porCadaArquetipo;

  /// Mirar las de arriba: a dónde va el resto (ver [kRestoA]) y, si no está
  /// vacío, una carta a cada zona en este orden (ver [kRepartir]).
  final String restoA;
  final List<String> repartir;

  /// Cambiar raza: la raza que pasan a tener.
  final String razaNueva;

  /// Habilidades de la misma carta con el mismo grupo: se usa solo una
  /// ("elige entre…", Luz de Prometeo).
  final String grupoElegir;

  /// Generar oro: coste mínimo de lo que pagan esos oros (Dragones: coste 4
  /// o más). 0 = cualquiera.
  final int soloParaCosteMin;

  /// "Cuando una carta tuya entra/sale": coste mínimo de esa carta (Monte
  /// Killgharrah: coste 3 o más). 0 = cualquiera.
  final int disparoCosteMin;

  /// Barajar: mientras esta carta esté en juego, el oponente no puede jugar
  /// la carta barajada (Titán Gorila).
  final bool vetaCarta;

  /// Campos que este editor no conoce (los agrega el agente): se conservan.
  final Map<String, dynamic> extra;

  const CardHabilidad({
    required this.featureId,
    required this.featureName,
    required this.accion,
    this.cuando = 'al_jugar',
    this.fase = 'cualquiera',
    this.turno = 'cualquiera',
    this.condicion = const CondicionHabilidad(),
    this.costo = const CostoHabilidad(),
    this.objetivo = const ObjetivoHabilidad(),
    this.cantidad = 1,
    this.valor = 0,
    this.modoFuerza = 'sumar',
    this.zonaDestino = 'mano',
    this.duracion = 'instantaneo',
    this.opcional = false,
    this.limitePorTurno = 0,
    this.cantidadSegun = 'fijo',
    this.talismanVaA = 'cementerio',
    this.valorPorCada = '',
    this.disparoTipos = const [],
    this.usaQuien = 'controlador',
    this.costoAlternativo = const CostoHabilidad(),
    this.limitePorNombre = false,
    this.disparoRaza = '',
    this.luego = const [],
    this.modo = '',
    this.soloParaTipos = const [],
    this.soloParaRaza = '',
    this.zonaActivacion = 'en_juego',
    this.grupoLimite = '',
    this.porCadaArquetipo = '',
    this.restoA = 'mazo_tope',
    this.repartir = const [],
    this.razaNueva = '',
    this.grupoElegir = '',
    this.soloParaCosteMin = 0,
    this.disparoCosteMin = 0,
    this.vetaCarta = false,
    this.extra = const {},
  });

  factory CardHabilidad.fromMap(Map<String, dynamic> m) => CardHabilidad(
    featureId: (m['featureId'] ?? '').toString(),
    featureName: (m['featureName'] ?? '').toString(),
    accion: Accion.parse(m['accion']?.toString()),
    cuando: (m['cuando'] ?? 'al_jugar').toString(),
    fase: (m['fase'] ?? 'cualquiera').toString(),
    turno: (m['turno'] ?? 'cualquiera').toString(),
    condicion: CondicionHabilidad.fromMap(m['condicion']),
    costo: CostoHabilidad.fromMap(m['costo']),
    objetivo: ObjetivoHabilidad.fromMap(m['objetivo']),
    cantidad: (m['cantidad'] as num?)?.toInt() ?? 1,
    valor: (m['valor'] as num?)?.toInt() ?? 0,
    modoFuerza: (m['modoFuerza'] ?? 'sumar').toString(),
    zonaDestino: (m['zonaDestino'] ?? 'mano').toString(),
    duracion: (m['duracion'] ?? 'instantaneo').toString(),
    opcional: m['opcional'] == true,
    limitePorTurno: (m['limitePorTurno'] as num?)?.toInt() ?? 0,
    cantidadSegun: (m['cantidadSegun'] ?? 'fijo').toString(),
    talismanVaA: (m['talismanVaA'] ?? 'cementerio').toString(),
    valorPorCada: (m['valorPorCada'] ?? '').toString(),
    disparoTipos:
        (m['disparoTipos'] is List)
            ? (m['disparoTipos'] as List).map((e) => '$e').toList()
            : const [],
    usaQuien: (m['usaQuien'] ?? 'controlador').toString(),
    costoAlternativo: CostoHabilidad.fromMap(m['costoAlternativo']),
    limitePorNombre: m['limitePorNombre'] == true,
    disparoRaza: (m['disparoRaza'] ?? '').toString(),
    luego:
        (m['luego'] is List)
            ? (m['luego'] as List)
                .whereType<Map>()
                .map((x) => EfectoLuego.fromMap(Map<String, dynamic>.from(x)))
                .toList()
            : const [],
    modo: (m['modo'] ?? '').toString(),
    soloParaTipos:
        (m['soloParaTipos'] is List)
            ? (m['soloParaTipos'] as List).map((e) => '$e').toList()
            : const [],
    soloParaRaza: (m['soloParaRaza'] ?? '').toString(),
    zonaActivacion: (m['zonaActivacion'] ?? 'en_juego').toString(),
    grupoLimite: (m['grupoLimite'] ?? '').toString(),
    porCadaArquetipo: (m['porCadaArquetipo'] ?? '').toString(),
    restoA: (m['restoA'] ?? 'mazo_tope').toString(),
    repartir:
        (m['repartir'] is List)
            ? (m['repartir'] as List).map((e) => '$e').toList()
            : const [],
    razaNueva: (m['razaNueva'] ?? '').toString(),
    grupoElegir: (m['grupoElegir'] ?? '').toString(),
    soloParaCosteMin: (m['soloParaCosteMin'] as num?)?.toInt() ?? 0,
    disparoCosteMin: (m['disparoCosteMin'] as num?)?.toInt() ?? 0,
    vetaCarta: m['vetaCarta'] == true,
    extra: _extra(m, _clavesHabilidad),
  );

  Map<String, dynamic> toMap() => {
    ...extra,
    'featureId': featureId,
    'featureName': featureName,
    'accion': accion.name,
    'cuando': accion.esPropiedad ? 'continua' : cuando,
    // Propiedad condicional: "no puede ser anulada si…", "imbloqueable en tu
    // turno"…
    if (accion.esPropiedad && !condicion.esNinguna)
      'condicion': condicion.toMap(),
    if (accion.esPropiedad && turno != 'cualquiera') 'turno': turno,
    // Armas: la propiedad aplica a su portador o al Arma misma.
    if (accion.esPropiedad &&
        const {'esta_carta', 'el_arma'}.contains(objetivo.quien))
      'objetivo': {'quien': objetivo.quien},
    if (!accion.esPropiedad) ...{
      'fase': fase,
      'turno': turno,
      'condicion': condicion.toMap(),
      'costo': costo.toMap(),
      'objetivo': objetivo.toMap(),
      'cantidad': cantidad,
      'valor': valor,
      if (accion.usaModoFuerza) 'modoFuerza': modoFuerza,
      if (accion.usaZonaDestino) 'zonaDestino': zonaDestino,
      'duracion': duracion,
      'opcional': opcional,
      'limitePorTurno': limitePorTurno,
      if (cantidadSegun != 'fijo') 'cantidadSegun': cantidadSegun,
      if (talismanVaA != 'cementerio') 'talismanVaA': talismanVaA,
      if (valorPorCada.isNotEmpty) 'valorPorCada': valorPorCada,
      if (const {
            'propia_entra',
            'propia_sale',
            'oponente_juega',
          }.contains(cuando) &&
          disparoTipos.isNotEmpty)
        'disparoTipos': disparoTipos,
      if (cuando == 'activada' && usaQuien != 'controlador')
        'usaQuien': usaQuien,
      if (!costoAlternativo.esGratis)
        'costoAlternativo': costoAlternativo.toMap(),
      if (limitePorNombre && limitePorTurno > 0) 'limitePorNombre': true,
      if (disparoRaza.isNotEmpty) 'disparoRaza': disparoRaza,
      if (luego.isNotEmpty) 'luego': luego.map((e) => e.toMap()).toList(),
      if (modo.isNotEmpty) 'modo': modo,
      if (soloParaTipos.isNotEmpty) 'soloParaTipos': soloParaTipos,
      if (soloParaRaza.isNotEmpty) 'soloParaRaza': soloParaRaza,
      if (zonaActivacion != 'en_juego') 'zonaActivacion': zonaActivacion,
      if (grupoLimite.isNotEmpty) 'grupoLimite': grupoLimite,
      if (valorPorCada == 'aliado_arquetipo' && porCadaArquetipo.isNotEmpty)
        'porCadaArquetipo': porCadaArquetipo,
      if (accion == Accion.mirarTope && restoA != 'mazo_tope') 'restoA': restoA,
      if (accion == Accion.mirarTope && repartir.isNotEmpty)
        'repartir': repartir,
      if (accion == Accion.cambiarRaza && razaNueva.isNotEmpty)
        'razaNueva': razaNueva,
      if (grupoElegir.isNotEmpty) 'grupoElegir': grupoElegir,
      if (soloParaCosteMin > 0) 'soloParaCosteMin': soloParaCosteMin,
      if (disparoCosteMin > 0) 'disparoCosteMin': disparoCosteMin,
      if (vetaCarta) 'vetaCarta': true,
    },
  };

  CardHabilidad copyWith({
    String? featureId,
    String? featureName,
    Accion? accion,
    String? cuando,
    String? fase,
    String? turno,
    CondicionHabilidad? condicion,
    CostoHabilidad? costo,
    ObjetivoHabilidad? objetivo,
    int? cantidad,
    int? valor,
    String? modoFuerza,
    String? zonaDestino,
    String? duracion,
    bool? opcional,
    int? limitePorTurno,
    String? cantidadSegun,
    String? talismanVaA,
    String? valorPorCada,
    List<String>? disparoTipos,
    String? usaQuien,
    CostoHabilidad? costoAlternativo,
    bool? limitePorNombre,
    String? disparoRaza,
    List<EfectoLuego>? luego,
    String? modo,
    List<String>? soloParaTipos,
    String? soloParaRaza,
    String? zonaActivacion,
    String? grupoLimite,
    String? porCadaArquetipo,
    String? restoA,
    List<String>? repartir,
    String? razaNueva,
    String? grupoElegir,
    int? soloParaCosteMin,
    int? disparoCosteMin,
    bool? vetaCarta,
  }) => CardHabilidad(
    featureId: featureId ?? this.featureId,
    featureName: featureName ?? this.featureName,
    accion: accion ?? this.accion,
    cuando: cuando ?? this.cuando,
    fase: fase ?? this.fase,
    turno: turno ?? this.turno,
    condicion: condicion ?? this.condicion,
    costo: costo ?? this.costo,
    objetivo: objetivo ?? this.objetivo,
    cantidad: cantidad ?? this.cantidad,
    valor: valor ?? this.valor,
    modoFuerza: modoFuerza ?? this.modoFuerza,
    zonaDestino: zonaDestino ?? this.zonaDestino,
    duracion: duracion ?? this.duracion,
    opcional: opcional ?? this.opcional,
    limitePorTurno: limitePorTurno ?? this.limitePorTurno,
    cantidadSegun: cantidadSegun ?? this.cantidadSegun,
    talismanVaA: talismanVaA ?? this.talismanVaA,
    valorPorCada: valorPorCada ?? this.valorPorCada,
    disparoTipos: disparoTipos ?? this.disparoTipos,
    usaQuien: usaQuien ?? this.usaQuien,
    costoAlternativo: costoAlternativo ?? this.costoAlternativo,
    limitePorNombre: limitePorNombre ?? this.limitePorNombre,
    disparoRaza: disparoRaza ?? this.disparoRaza,
    luego: luego ?? this.luego,
    modo: modo ?? this.modo,
    soloParaTipos: soloParaTipos ?? this.soloParaTipos,
    soloParaRaza: soloParaRaza ?? this.soloParaRaza,
    zonaActivacion: zonaActivacion ?? this.zonaActivacion,
    grupoLimite: grupoLimite ?? this.grupoLimite,
    porCadaArquetipo: porCadaArquetipo ?? this.porCadaArquetipo,
    restoA: restoA ?? this.restoA,
    repartir: repartir ?? this.repartir,
    razaNueva: razaNueva ?? this.razaNueva,
    grupoElegir: grupoElegir ?? this.grupoElegir,
    soloParaCosteMin: soloParaCosteMin ?? this.soloParaCosteMin,
    disparoCosteMin: disparoCosteMin ?? this.disparoCosteMin,
    vetaCarta: vetaCarta ?? this.vetaCarta,
    extra: extra,
  );

  /// Lectura en una línea, p. ej. "Vigilia · pagar 2 oros → Destruir 1
  /// Aliado del oponente con coste ≤ 2".
  String get resumen {
    if (accion.esPropiedad) {
      final cond = [
        if (turno != 'cualquiera') labelDe(kTurno, turno).toLowerCase(),
        if (!condicion.esNinguna) condicion.toString(),
      ];
      return cond.isEmpty
          ? accion.label
          : '${accion.label} (${cond.join(', ')})';
    }
    final partes = <String>[
      if (zonaActivacion != 'en_juego')
        'desde ${labelDe(kZonaActivacion, zonaActivacion).toLowerCase()}',
      labelDe(kCuando, cuando),
      if (fase != 'cualquiera') labelDe(kFases, fase),
      if (!condicion.esNinguna) condicion.toString(),
      if (!costo.esGratis)
        costoAlternativo.esGratis
            ? costo.toString()
            : '${costo.toString()} o ${costoAlternativo.toString()}',
      if (usaQuien == 'oponente') 'la usa tu oponente',
      if (usaQuien == 'ambos') 'la puede usar cualquier jugador',
      if (cuando == 'propia_entra' && disparoTipos.isNotEmpty)
        '(${disparoTipos.join('/')})',
      if (valorPorCada.isNotEmpty)
        labelDe(kPorCada, valorPorCada).toLowerCase(),
    ];
    final que = describirEfecto(
      accion: accion,
      objetivo: objetivo,
      cantidad: cantidad,
      valor: valor,
      modoFuerza: modoFuerza,
      duracion: duracion,
      cantidadSegun: cantidadSegun,
    );
    final modos = kModos[accion];
    final detalle = [
      if (modos != null && modo.isNotEmpty) labelDe(modos, modo).toLowerCase(),
      if (soloParaTipos.isNotEmpty || soloParaRaza.isNotEmpty)
        'solo para pagar ${[...soloParaTipos, if (soloParaRaza.isNotEmpty) 'raza $soloParaRaza'].join('/')}',
    ].join(', ');
    return '${partes.where((p) => p.isNotEmpty).join(' · ')} → $que'
        '${detalle.isEmpty ? '' : ' ($detalle)'}'
        '${opcional ? ' (opcional)' : ''}'
        '${luego.map((e) => ' → ${e.resumen}').join()}';
  }
}
