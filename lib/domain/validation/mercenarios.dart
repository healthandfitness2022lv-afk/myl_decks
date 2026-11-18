/// Cartas Mercenario: las que dicen «Puedes tener más de 3 … en tu Mazo
/// Castillo» (Draco Águila). No tienen el tope de 3 copias: se permiten hasta
/// [copiasMercenario], salvo que la Ban List les fije otro límite.
///
/// Mismo criterio que `copias_maximas` del simulador
/// (`simulator/myl_sim/datos.py`).
library;

/// Copias permitidas de una carta Mercenario en un mazo (Héctor, 18-11).
const copiasMercenario = 6;

/// Copias permitidas de cualquier otra carta.
const copiasNormales = 3;

final _textoMercenario = RegExp(
  r'puedes\s+tener\s+m[áa]s\s+de\s+(?:3|tres)\b',
  caseSensitive: false,
);

/// Cartas Mercenario ya vistas en esta sesión, por id y por nombre. Varias
/// pantallas validan un mazo solo con sus entradas (sin el catálogo): con
/// este registro reconocen igual a la carta.
final _vistas = <String>{};

String _clave(String valor) => valor.trim().toLowerCase();

/// ¿El texto de habilidad la declara Mercenario?
bool textoEsMercenario(String texto) => _textoMercenario.hasMatch(texto);

/// Recuerda una carta Mercenario (la llama el modelo al leerla del catálogo).
void registrarMercenario({required String id, required String nombre}) {
  if (id.trim().isNotEmpty) _vistas.add(_clave(id));
  if (nombre.trim().isNotEmpty) _vistas.add(_clave(nombre));
}

/// ¿Es una carta Mercenario ya vista? Por id o por nombre.
bool esMercenario({String? id, String nombre = ''}) =>
    (id != null && id.trim().isNotEmpty && _vistas.contains(_clave(id))) ||
    (nombre.trim().isNotEmpty && _vistas.contains(_clave(nombre)));

/// Copias permitidas de una carta: lo que diga la Ban List (`enBanList`); si
/// no la nombra, 1 si es Única, [copiasMercenario] si es Mercenario y 3 el resto.
int limiteDeCopias({
  required int? enBanList,
  required bool unica,
  required bool mercenario,
}) {
  if (unica) return (enBanList ?? 1).clamp(0, 1);
  if (enBanList != null) {
    return enBanList.clamp(0, mercenario ? copiasMercenario : copiasNormales);
  }
  return mercenario ? copiasMercenario : copiasNormales;
}
