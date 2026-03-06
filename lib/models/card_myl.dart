// card_myl.dart

enum CardTag {
  bonificador,
  imbloqueable,
  furia,
  removal,
  baraje,
  robo,
  finalizador,
  invocador,
  buscador,
  anulacion,
  destierro,
  indestructible,
  indesterrable,
  dano_directo,
  generador_oros,
  Control_aliados,
  Cancelacion,
  inhabilitar,
  reducir_dano, // 👈 NUEVA
}

extension CardTagX on CardTag {
  String get key => name;

  static String _normalize(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[áàä]'), 'a')
        .replaceAll(RegExp(r'[éèë]'), 'e')
        .replaceAll(RegExp(r'[íìï]'), 'i')
        .replaceAll(RegExp(r'[óòö]'), 'o')
        .replaceAll(RegExp(r'[úùü]'), 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  static CardTag? parse(String? raw) {
    if (raw == null) return null;
    final k = _normalize(raw);

    for (final t in CardTag.values) {
      if (_normalize(t.name) == k) return t;
    }

    switch (k) {
      case 'reshuffle':
        return CardTag.baraje;

      case 'counter':
      case 'counterspell':
      case 'contrahechizo':
        return CardTag.anulacion;

      case 'exile':
        return CardTag.destierro;

      case 'cancelacion':
        return CardTag.Cancelacion;

      case 'control_aliados':
      case 'control_de_aliados':
        return CardTag.Control_aliados;

      case 'generador_de_oros':
        return CardTag.generador_oros;

      // Inhabilitar / silencio de habilidades
      case 'inhabilitar':
      case 'silenciar':
      case 'silencio':
      case 'silence':
      case 'blank':
      case 'quitar_habilidad':
      case 'remover_habilidad':
      case 'bloquear_habilidad':
      case 'anular_habilidad':
      case 'sin_habilidad':
      case 'deshabilitar_habilidad':
        return CardTag.inhabilitar;

      // Reducir daño (con/sin tilde)
      case 'reducir dano':
      case 'reducir daño':
        return CardTag.reducir_dano;

      default:
        return null;
    }
  }
}

class CardMyL {
  final String id;
  final String nombre;
  final String tipo;
  final int? coste;
  final int? fuerza;
  final String rareza;
  final String edicion;
  final String habilidad;
  final String? raza;

  // Reglas extra (solo semántica de juego)
  final bool unica;
  final Set<CardTag> tags;
  final List<String> caracteristicasRaw;

  const CardMyL({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.coste,
    this.fuerza,
    required this.rareza,
    required this.edicion,
    required this.habilidad,
    this.raza,
    this.unica = false,
    Set<CardTag>? tags,
    List<String>? caracteristicasRaw,
  })  : tags = tags ?? const {},
        caracteristicasRaw = caracteristicasRaw ?? const [];

  bool get esAliado => tipo.toLowerCase() == 'aliado';
  bool get esUnica => unica;

  bool hasTag(CardTag t) => tags.contains(t);
  CardMyL addTag(CardTag t) => copyWith(tags: {...tags, t});
  CardMyL removeTag(CardTag t) => copyWith(tags: tags.where((x) => x != t).toSet());

  /// Lee el doc de Firestore con tolerancia de formatos en `caracteristicasRaw`.
  /// Nota: campos legados de imagen (imageUrl, imagePublicId, official*) se ignoran.
  factory CardMyL.fromMap(Map<String, dynamic> map, String id) {
    // --- caracteristicasRaw flexible: List / Map<String,bool> / String CSV ---
    List<String> _readCaracs(dynamic any) {
      final out = <String>[];
      if (any == null) return out;

      if (any is List) {
        for (final e in any) {
          out.add('$e');
        }
      } else if (any is Map) {
        any.forEach((k, v) {
          if (v == true) out.add('$k');
        });
      } else if (any is String) {
        for (final part in any.split(',')) {
          out.add(part.trim());
        }
      }
      return out;
    }

    final rawStrs = _readCaracs(map['caracteristicasRaw']);

    final parsedTags = <CardTag>{};
    for (final s in rawStrs) {
      final t = CardTagX.parse(s);
      if (t != null) parsedTags.add(t);
    }

    int _toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('$v') ?? 0;
    }

    return CardMyL(
      id: id,
      nombre: map['nombre'] ?? '',
      tipo: map['tipo'] ?? '',
      coste: _toInt(map['coste']),
      fuerza: (map['fuerza'] as num?)?.toInt(),
      rareza: map['rareza'] ?? '',
      edicion: map['edicion'] ?? '',
      habilidad: map['habilidad'] ?? '',
      raza: map['raza'],
      unica: (map['unica'] as bool?) ?? false,
      tags: parsedTags,
      caracteristicasRaw: rawStrs,
    );
  }

  /// Serializa uniendo tags + caracteristicasRaw sin duplicados (por normalización).
  Map<String, dynamic> toMap() {
    final raw = List<String>.from(caracteristicasRaw);

    bool _containsNorm(List<String> list, String value) {
      final v = CardTagX._normalize(value);
      return list.any((s) => CardTagX._normalize(s) == v);
    }

    for (final t in tags) {
      final k = t.key;
      if (!_containsNorm(raw, k)) raw.add(k);
    }

    return {
      'nombre': nombre,
      'tipo': tipo,
      'coste': coste,
      if (fuerza != null) 'fuerza': fuerza,
      'rareza': rareza,
      'edicion': edicion,
      'habilidad': habilidad,
      if (raza != null) 'raza': raza,
      'nombre_lower': nombre.toLowerCase(),
      'unica': unica,
      // espejo por compatibilidad:
      'caracteristicasRaw': raw,
      // 🚫 ya no escribimos campos de imagen ni oficiales aquí
    };
  }

  CardMyL copyWith({
    String? nombre,
    String? tipo,
    int? coste,
    int? fuerza,
    String? rareza,
    String? edicion,
    String? habilidad,
    String? raza,
    bool? unica,
    Set<CardTag>? tags,
    List<String>? caracteristicasRaw,
  }) {
    return CardMyL(
      id: id,
      nombre: nombre ?? this.nombre,
      tipo: tipo ?? this.tipo,
      coste: coste ?? this.coste,
      fuerza: fuerza ?? this.fuerza,
      rareza: rareza ?? this.rareza,
      edicion: edicion ?? this.edicion,
      habilidad: habilidad ?? this.habilidad,
      raza: raza ?? this.raza,
      unica: unica ?? this.unica,
      tags: tags ?? this.tags,
      caracteristicasRaw: caracteristicasRaw ?? this.caracteristicasRaw,
    );
  }
}
