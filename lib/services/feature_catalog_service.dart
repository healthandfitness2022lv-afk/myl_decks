// lib/services/feature_catalog_service.dart
//
// Catálogo de características (`card_custom_features`) con su significado y
// la acción que ejecuta el simulador.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/card_habilidad.dart';

class FeatureDef {
  final String id;
  final String name;
  final String group;
  final String descripcion;

  /// null = aún no se define en el glosario (se usa la sugerencia).
  final Accion? accionGuardada;

  /// Característica genérica (verbo) creada al unificar el catálogo.
  final bool generica;

  /// Nombres de las características antiguas que se unificaron en esta.
  final List<String> incluye;

  const FeatureDef({
    required this.id,
    required this.name,
    required this.group,
    required this.descripcion,
    required this.accionGuardada,
    this.generica = false,
    this.incluye = const [],
  });

  Accion get accion => accionGuardada ?? sugerirAccion(name);
  bool get definida => accionGuardada != null && descripcion.isNotEmpty;

  factory FeatureDef.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    final accion = m['accion']?.toString();
    return FeatureDef(
      id: d.id,
      name: (m['name'] ?? '').toString(),
      group: (m['group'] ?? 'Otros').toString(),
      descripcion: (m['descripcion'] ?? '').toString(),
      accionGuardada:
          accion == null || accion.isEmpty ? null : Accion.parse(accion),
      generica: m['generica'] == true,
    );
  }

  FeatureDef conIncluidas(List<String> nombres) => FeatureDef(
    id: id,
    name: name,
    group: group,
    descripcion: descripcion,
    accionGuardada: accionGuardada,
    generica: generica,
    incluye: nombres,
  );
}

/// Id de las características que no existen en el catálogo (ver
/// [FeatureCatalogService._delSimulador]); no se agregan como etiqueta.
const kPrefijoSimulador = 'accion_';

class FeatureCatalogService {
  static final _col = FirebaseFirestore.instance.collection(
    'card_custom_features',
  );

  /// Características vigentes. Las unificadas en una genérica no se listan;
  /// sus nombres quedan en [FeatureDef.incluye] de la genérica.
  static Stream<List<FeatureDef>> stream() => _col.snapshots().map((s) {
    final incluidas = <String, List<String>>{};
    for (final d in s.docs) {
      final destino = d.data()['unificadaEn']?.toString();
      final nombre = (d.data()['name'] ?? '').toString();
      if (destino != null && nombre.isNotEmpty) {
        (incluidas[destino] ??= []).add(nombre);
      }
    }
    return s.docs
        .where((d) => d.data()['unificadaEn'] == null)
        .map(FeatureDef.fromDoc)
        .where((f) => f.name.isNotEmpty)
        .map((f) => f.conIncluidas(incluidas[f.id] ?? const []))
        .toList()
      ..addAll(_delSimulador(s.docs))
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  });

  /// Acciones del simulador que ninguna característica del catálogo usa
  /// todavía: se ofrecen igual en el editor, sin crearlas en Firestore.
  static List<FeatureDef> _delSimulador(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final usadas = {
      for (final d in docs)
        if (d.data()['unificadaEn'] == null) d.data()['accion']?.toString(),
    };
    return [
      for (final a in Accion.values)
        if (a != Accion.otra && !usadas.contains(a.name))
          FeatureDef(
            id: '$kPrefijoSimulador${a.name}',
            name: a.label,
            group: 'Simulador',
            descripcion: a.descripcion,
            accionGuardada: a,
          ),
    ];
  }

  static Future<void> save(
    String id, {
    required String descripcion,
    required Accion accion,
  }) => _col.doc(id).update({
    'descripcion': descripcion.trim(),
    'accion': accion.name,
    'updatedAt': FieldValue.serverTimestamp(),
  });
}
