import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:myl_decks/models/card_variant.dart';

import 'card_habilidad.dart';

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

  /// Texto transcrito desde la imagen por el worker local. Tiene prioridad
  /// sobre el texto legado al preparar una carta para el simulador.
  final String habilidadTextoIA;
  final String? raza;

  // Reglas extra (solo semántica de juego)
  final bool unica;

  /// true → esta carta solo puede usarse en mazos de formato Racial Libre.
  final bool soloLibre;
  final Set<CardTag> tags;
  final List<String> caracteristicasRaw;
  final List<CardVariant> variantes;

  /// Habilidades parametrizadas para el simulador (ver card_habilidad.dart).
  final List<CardHabilidad> habilidades;

  /// true → todas sus habilidades están programadas y el simulador puede
  /// usarla completa.
  final bool habilidadesRevisadas;

  /// Lo que falta para simular bien esta carta (casos que el editor aún no
  /// cubre). Se revisa con el skill revisar-notas-simulador.
  final String notasSimulador;

  const CardMyL({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.coste,
    this.fuerza,
    required this.rareza,
    required this.edicion,
    required this.habilidad,
    this.habilidadTextoIA = '',
    this.raza,
    this.unica = false,
    this.soloLibre = false,
    this.isStub = false,
    Set<CardTag>? tags,
    List<String>? caracteristicasRaw,
    List<CardVariant>? variantes,
    List<CardHabilidad>? habilidades,
    this.habilidadesRevisadas = false,
    this.notasSimulador = '',
  }) : tags = tags ?? const {},
       variantes = variantes ?? const [],
       caracteristicasRaw = caracteristicasRaw ?? const [],
       habilidades = habilidades ?? const [];

  // true cuando la carta fue creada rápido y aún le falta info
  final bool isStub;

  bool get esAliado => tipo.toLowerCase() == 'aliado';
  bool get esUnica => unica;

  CardVariant? get bestVariant {
    if (variantes.isEmpty) return null;
    for (final variant in variantes) {
      if (variant.isBase) return variant;
    }
    for (final variant in variantes) {
      if (variant.imageFrontUrl?.isNotEmpty == true) return variant;
    }
    return variantes.first;
  }

  bool hasTag(CardTag t) => tags.contains(t);
  CardMyL addTag(CardTag t) => copyWith(tags: {...tags, t});
  CardMyL removeTag(CardTag t) =>
      copyWith(tags: tags.where((x) => x != t).toSet());

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

    List<CardVariant> _parseVariantes(dynamic any) {
      if (any == null) return [];
      try {
        if (any is List) {
          return any.map((x) {
            final m = Map<String, dynamic>.from(x as Map);
            return CardVariant.fromMap(m, m['id']?.toString() ?? '');
          }).toList();
        } else if (any is Map) {
          return any.entries.map((e) {
            final m = Map<String, dynamic>.from(e.value as Map);
            return CardVariant.fromMap(m, e.key.toString());
          }).toList();
        }
      } catch (e) {
        debugPrint('Error parsing variantes: \$e');
      }
      return [];
    }

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
      habilidadTextoIA: (map['habilidadTextoIA'] ?? '').toString(),
      raza: map['raza'],
      unica: (map['unica'] as bool?) ?? false,
      soloLibre: (map['soloLibre'] as bool?) ?? false,
      isStub: map['status'] == 'stub',
      tags: parsedTags,
      caracteristicasRaw: rawStrs,
      variantes: _parseVariantes(map['variants']),
      habilidades:
          (map['habilidades'] is List)
              ? (map['habilidades'] as List)
                  .whereType<Map>()
                  .map(
                    (m) => CardHabilidad.fromMap(Map<String, dynamic>.from(m)),
                  )
                  .toList()
              : const [],
      habilidadesRevisadas: map['habilidadesRevisadas'] == true,
      notasSimulador: (map['notasSimulador'] ?? '').toString(),
    );
  }

  factory CardMyL.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      CardMyL.fromMap(doc.data() ?? const <String, dynamic>{}, doc.id);

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
      if (habilidadTextoIA.isNotEmpty) 'habilidadTextoIA': habilidadTextoIA,
      if (raza != null) 'raza': raza,
      'nombre_lower': nombre.toLowerCase(),
      'unica': unica,
      if (soloLibre) 'soloLibre': true,
      // espejo por compatibilidad:
      'caracteristicasRaw': raw,
      if (variantes.isNotEmpty)
        'variants': variantes.map((x) => x.toMap()).toList(),
      if (habilidades.isNotEmpty)
        'habilidades': habilidades.map((x) => x.toMap()).toList(),
      if (habilidadesRevisadas) 'habilidadesRevisadas': true,
      if (notasSimulador.isNotEmpty) 'notasSimulador': notasSimulador,
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
    String? habilidadTextoIA,
    String? raza,
    bool? unica,
    bool? soloLibre,
    Set<CardTag>? tags,
    List<String>? caracteristicasRaw,
    List<CardVariant>? variantes,
    List<CardHabilidad>? habilidades,
    bool? habilidadesRevisadas,
    String? notasSimulador,
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
      habilidadTextoIA: habilidadTextoIA ?? this.habilidadTextoIA,
      raza: raza ?? this.raza,
      unica: unica ?? this.unica,
      soloLibre: soloLibre ?? this.soloLibre,
      tags: tags ?? this.tags,
      caracteristicasRaw: caracteristicasRaw ?? this.caracteristicasRaw,
      variantes: variantes ?? this.variantes,
      habilidades: habilidades ?? this.habilidades,
      habilidadesRevisadas: habilidadesRevisadas ?? this.habilidadesRevisadas,
      notasSimulador: notasSimulador ?? this.notasSimulador,
    );
  }
}
