import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:myl_decks/models/card_variant.dart';

import '../domain/validation/mercenarios.dart';
import 'card_habilidad.dart';

// card_myl.dart

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
    List<CardVariant>? variantes,
    List<CardHabilidad>? habilidades,
    this.habilidadesRevisadas = false,
    this.notasSimulador = '',
  }) : variantes = variantes ?? const [],
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

  /// Lee el doc de Firestore.
  /// Nota: campos legados de imagen (imageUrl, imagePublicId, official*) se ignoran.
  factory CardMyL.fromMap(Map<String, dynamic> map, String id) {
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

    int _toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('$v') ?? 0;
    }

    // Mercenario («Puedes tener más de 3…»): se recuerda para que las
    // pantallas que validan un mazo sin el catálogo la reconozcan.
    if (textoEsMercenario(
      '${map['habilidadTextoIA'] ?? ''} ${map['habilidad'] ?? ''}',
    )) {
      registrarMercenario(id: id, nombre: '${map['nombre'] ?? ''}');
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

  Map<String, dynamic> toMap() {
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
      variantes: variantes ?? this.variantes,
      habilidades: habilidades ?? this.habilidades,
      habilidadesRevisadas: habilidadesRevisadas ?? this.habilidadesRevisadas,
      notasSimulador: notasSimulador ?? this.notasSimulador,
    );
  }
}
