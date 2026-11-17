// lib/domain/catalogo_acciones.dart
//
// Acciones que el editor de habilidades ofrece: salen del enum `Accion`
// (lo que el simulador sabe ejecutar), no de un catálogo en Firestore.

import '../models/card_habilidad.dart';

class AccionDef {
  final String id;
  final String name;
  final Accion accion;
  final String descripcion;

  const AccionDef({
    required this.id,
    required this.name,
    required this.accion,
    required this.descripcion,
  });
}

String idDeAccion(Accion a) => 'accion_${a.name}';

/// Todas las acciones programables, ordenadas por nombre.
List<AccionDef> catalogoAcciones() => [
  for (final a in Accion.values)
    if (a != Accion.otra)
      AccionDef(
        id: idDeAccion(a),
        name: a.label,
        accion: a,
        descripcion: a.descripcion,
      ),
]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
