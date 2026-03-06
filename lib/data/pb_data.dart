/// Datos fijos de Primer Bloque (ediciones, expansiones y razas).
class PBData {
  /// Ediciones base (label) con su expansión correspondiente.
  static const Map<String, String> edicionToExpansion = {
    'Espada Sagrada': 'Cruzadas',
    'Helénica': 'Imperio',
    'Hijos de Daana': 'Tierras Altas',
    'Dominios de Ra': 'Encrucijada',
  };

  /// Lista cómoda para dropdown (ordena por nombre).
  static List<String> get ediciones =>
      edicionToExpansion.keys.toList()..sort();

  /// Razas por edición (solo aplican a Tipo = Aliado).
  static const Map<String, List<String>> razasPorEdicion = {
    'Espada Sagrada': ['Faerie', 'Caballero', 'Dragón'],
    'Helénica': ['Héroe', 'Titán', 'Olímpico'],
    'Hijos de Daana': ['Defensor', 'Desafiante', 'Sombra'],
    'Dominios de Ra': ['Eterno', 'Sacerdote', 'Faraón'],
  };

  /// Tipos de carta más comunes en PB.
  static const List<String> tipos = [
    'Aliado',
    'Talismán',
    'Tótem',
    'Arma',
    'Oro',
  ];

  /// Rarezas típicas en PB (puedes adaptar).
  static const List<String> rarezas = [
    'Real',
    'Vasallo',
    'Cortesano',
  ];
}