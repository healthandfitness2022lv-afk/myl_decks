// lib/screens/feature_grouping_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// =====================
/// MODELO / ESTADO
/// =====================
class FeatureDoc {
  final String id;
  final String name;
  final String normalized;
  final String? group; // puede ser null => sin asignar

  FeatureDoc({
    required this.id,
    required this.name,
    required this.normalized,
    required this.group,
  });

  factory FeatureDoc.fromSnap(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    final rawGroup = (m['group'] as String?)?.trim();
    return FeatureDoc(
      id: d.id,
      name: (m['name'] ?? '').toString(),
      normalized: (m['normalized'] ?? '').toString(),
      group: (rawGroup == null || rawGroup.isEmpty) ? null : rawGroup,
    );
  }

  FeatureDoc copyWith({String? name, String? normalized, String? group}) {
    return FeatureDoc(
      id: id,
      name: name ?? this.name,
      normalized: normalized ?? this.normalized,
      group: group,
    );
  }
}

/// =====================
/// ESTADO / LÓGICA
/// =====================
/// Mantiene el universo de features y un mapa group->lista de ids.
/// La “fuente de verdad” final está en Firestore en el campo `group` de cada doc.
class FeatureGroupingState extends ChangeNotifier {
  FeatureGroupingState(this._features);

  // id -> FeatureDoc
  final Map<String, FeatureDoc> _features;

  // group -> lista de ids (derivado)
  Map<String, List<String>> get groups {
    final map = <String, List<String>>{};
    for (final f in _features.values) {
      final g = f.group;
      if (g == null || g.trim().isEmpty) continue;
      (map[g] ??= []).add(f.id);
    }
    // ordenar por nombre de feature para una UI prolija
    for (final k in map.keys) {
      map[k]!.sort((a, b) =>
          _features[a]!.name.toLowerCase().compareTo(_features[b]!.name.toLowerCase()));
    }
    return map;
  }

  // Features sin grupo (para panel izquierdo)
  List<FeatureDoc> get unassigned {
    final list = _features.values.where((f) => (f.group ?? '').isEmpty).toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  // Todos los features (por si lo necesitás)
  List<FeatureDoc> get all {
    final list = _features.values.toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  // Lista de nombres de grupos actuales (derivada)
  List<String> get groupNames {
    final s = <String>{};
    for (final f in _features.values) {
      final g = f.group;
      if (g != null && g.trim().isNotEmpty) s.add(g);
    }
    final list = s.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  bool containsGroup(String name) => groupNames.contains(name);

  // Asignar/Desasignar (solo en memoria). Persistencia la hace el repositorio.
  void assign(String featureId, String group) {
    final f = _features[featureId];
    if (f == null) return;
    _features[featureId] = f.copyWith(group: group);
    notifyListeners();
  }

  void unassign(String featureId) {
    final f = _features[featureId];
    if (f == null) return;
    _features[featureId] = f.copyWith(group: null);
    notifyListeners();
  }

  Map<String, FeatureDoc> toMap() => _features;
}

/// =====================
/// REPOSITORIO FIRESTORE
/// =====================
class FeatureRepo {
  const FeatureRepo();

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('card_custom_features');

  Future<Map<String, FeatureDoc>> loadAll() async {
    final snap = await _col.orderBy('name').get();
    final map = <String, FeatureDoc>{};
    for (final d in snap.docs) {
      final f = FeatureDoc.fromSnap(d);
      // Filtrar docs sin name por las dudas
      if (f.name.trim().isEmpty) continue;
      map[f.id] = f;
    }
    return map;
  }

  /// Actualiza el campo `group` de un solo documento (persistente, inmediato).
  Future<void> updateFeatureGroup(String id, String? group) async {
    final ref = _col.doc(id);
    if (group == null || group.trim().isEmpty) {
      // borrar campo
      await ref.update({'group': FieldValue.delete()});
    } else {
      await ref.update({'group': group});
    }
  }
}

/// =====================
/// UI PRINCIPAL (simplificada)
/// - No botones de guardar ni refrescar
/// - Al arrastrar / eliminar, se persiste inmediatamente
/// =====================
class FeatureGroupingScreen extends StatefulWidget {
  /// Mapa opcional para pre-asignaciones iniciales:
  /// { 'Grupo A': ['Característica 1', 'otra'], ... }
  final Map<String, List<String>> initialGroups;

  const FeatureGroupingScreen({
    super.key,
    this.initialGroups = const {},
  });

  @override
  State<FeatureGroupingScreen> createState() => _FeatureGroupingScreenState();
}

class _FeatureGroupingScreenState extends State<FeatureGroupingScreen> {
  final _repo = const FeatureRepo();

  FeatureGroupingState? _state;
  bool _loading = true;

  // Grupos “vacíos” creados localmente.
  final Set<String> _localEmptyGroups = {};

  // NOTIFIER para forzar la reconstrucción cuando cambian los grupos visibles.
  final ValueNotifier<List<String>> _groupsNotifier = ValueNotifier<List<String>>([]);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _groupsNotifier.dispose();
    super.dispose();
  }

  // helper de normalización ligera (coincide con lo que podrías usar en tus seeds)
  String _normalize(String s) {
    var t = s.trim().toLowerCase();
    t = t
        .replaceAll(RegExp(r'[áàä]'), 'a')
        .replaceAll(RegExp(r'[éèë]'), 'e')
        .replaceAll(RegExp(r'[íìï]'), 'i')
        .replaceAll(RegExp(r'[óòö]'), 'o')
        .replaceAll(RegExp(r'[úùü]'), 'u')
        .replaceAll('ñ', 'n')
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    return t;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final map = await _repo.loadAll();

      // aplicar initialGroups si vienen
      if (widget.initialGroups.isNotEmpty) {
        final normIndex = <String, String>{};
        for (final e in map.entries) {
          final id = e.key;
          final f = e.value;
          normIndex[f.normalized.toLowerCase()] = id;
          normIndex[f.name.toLowerCase()] = id;
        }

        for (final entry in widget.initialGroups.entries) {
          final groupName = entry.key;
          for (final rawFeature in entry.value) {
            final r = rawFeature.trim();
            if (r.isEmpty) continue;
            final idMatched = normIndex[r.toLowerCase()] ?? normIndex[_normalize(r)];
            if (idMatched != null) {
              final existing = map[idMatched]!;
              map[idMatched] = existing.copyWith(group: groupName);
            } else {
              final keyLower = r.toLowerCase();
              final found = map.values.firstWhere(
                  (f) =>
                      f.name.toLowerCase() == keyLower ||
                      f.normalized.toLowerCase() == _normalize(r) ||
                      f.name.toLowerCase().contains(keyLower),
                  orElse: () => FeatureDoc(id: '', name: '', normalized: '', group: null));
              if (found.id.isNotEmpty) {
                map[found.id] = found.copyWith(group: groupName);
              }
            }
          }
        }
      }

      _state = FeatureGroupingState(Map<String, FeatureDoc>.from(map));
      // actualizar groupsNotifier
      _refreshGroupsNotifier();
      debugPrint('[FeatureGrouping] loaded ${_state!.all.length} features');
    } catch (e, st) {
      debugPrint('[FeatureGrouping] load error: $e\n$st');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Construye lista combinada de nombres de grupos (estado + locales) sin duplicados
  List<String> _allGroupNames() {
    final result = <String>[];
    if (_state != null) {
      for (final g in _state!.groupNames) {
        if (g.trim().isNotEmpty && !result.any((x) => x.toLowerCase() == g.toLowerCase())) {
          result.add(g);
        }
      }
    }
    for (final g in _localEmptyGroups) {
      if (g.trim().isEmpty) continue;
      if (!result.any((x) => x.toLowerCase() == g.toLowerCase())) result.add(g);
    }
    return result;
  }

  // fuerza el notifier a emitir la lista actual (llamar después de cambios)
  void _refreshGroupsNotifier() {
    final names = _allGroupNames();
    debugPrint('[FeatureGrouping] groups refreshed: ${names.join(', ')}');
    _groupsNotifier.value = names;
  }

  // Dialog + lógica para crear grupo: ahora obliga update del notifier siempre
  Future<void> _addGroupDialog() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nuevo grupo'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Ej: Agro, Control...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Crear')),
        ],
      ),
    );

    if (name == null) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nombre vacío')));
      return;
    }

    // Evitar duplicados (case-insensitive)
    final exists = _allGroupNames().any((g) => g.toLowerCase() == trimmed.toLowerCase());
    if (exists) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El grupo ya existe')));
      return;
    }

    // Añadimos siempre al set local y refrescamos el notifier para que aparezca en la UI
    _localEmptyGroups.add(trimmed);
    _refreshGroupsNotifier();
    // forzar rebuild del scaffold si hace falta
    if (mounted) setState(() {});
  }

  /// Asignación persistente: actualiza la vista en memoria y persiste el cambio.
  Future<void> _assignAndPersist(String featureId, String group) async {
    if (_state == null) return;
    debugPrint('[FeatureGrouping] assign $featureId -> $group');
    _state!.assign(featureId, group);
    _localEmptyGroups.remove(group);
    _refreshGroupsNotifier();
    setState(() {});
    try {
      await _repo.updateFeatureGroup(featureId, group);
    } catch (e) {
      // revertir en memoria si falla
      debugPrint('[FeatureGrouping] error persisting assign: $e');
      _state!.unassign(featureId);
      _refreshGroupsNotifier();
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al asignar: $e')));
      }
    }
  }

  /// Desasignación persistente: actualiza la vista en memoria y persiste el borrado del campo.
  Future<void> _unassignAndPersist(String featureId) async {
    if (_state == null) return;
    debugPrint('[FeatureGrouping] unassign $featureId');
    _state!.unassign(featureId);
    _refreshGroupsNotifier();
    setState(() {});
    try {
      await _repo.updateFeatureGroup(featureId, null);
    } catch (e) {
      debugPrint('[FeatureGrouping] error persisting unassign: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al desasignar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agrupar características'),
        actions: [
          IconButton(
            tooltip: 'Nuevo grupo',
            onPressed: _loading ? null : _addGroupDialog,
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
        ],
      ),
      body: _loading || state == null
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                // ===================== IZQUIERDA: SIN ASIGNAR =====================
                Flexible(
                  flex: 5,
                  child: _UnassignedPanel(
                    items: state.unassigned,
                    onUnassignFromGroup: (featureId, fromGroup) {
                      _unassignAndPersist(featureId);
                    },
                  ),
                ),
                const VerticalDivider(width: 1),
                // ===================== DERECHA: GRUPOS =====================
                Flexible(
                  flex: 7,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final twoCols = constraints.maxWidth > 900;
                      // usamos ValueListenableBuilder para reconstruir cuando cambian los grupos
                      return ValueListenableBuilder<List<String>>(
                        valueListenable: _groupsNotifier,
                        builder: (context, groupNames, _) {
                          if (groupNames.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.create_new_folder_outlined, size: 48),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Crea tu primer grupo con el botón “Nuevo grupo”',
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                ],
                              ),
                            );
                          }

                          final tiles = groupNames.map((g) {
                            final ids = state.groups[g] ?? <String>[];
                            final features = ids.map((id) => state.toMap()[id]!).toList()
                              ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
                            final isEmptyVisual = features.isEmpty;

                            return _GroupColumn(
                              name: g,
                              features: features,
                              onDropFeature: (fid) {
                                _assignAndPersist(fid, g);
                              },
                              onUnassign: (fid) {
                                _unassignAndPersist(fid);
                              },
                              onDeleteEmptyLocal: isEmptyVisual && _localEmptyGroups.contains(g)
                                  ? () {
                                      _localEmptyGroups.remove(g);
                                      _refreshGroupsNotifier();
                                      if (mounted) setState(() {});
                                    }
                                  : null,
                            );
                          }).toList();

                          if (twoCols) {
                            return GridView.count(
                              padding: const EdgeInsets.all(12),
                              crossAxisCount: 2,
                              childAspectRatio: 1.6,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              children: tiles,
                            );
                          } else {
                            return SingleChildScrollView(
                              padding: const EdgeInsets.all(12),
                              child: Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: tiles,
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

/// =====================
/// PANEL IZQUIERDO
/// =====================
class _UnassignedPanel extends StatelessWidget {
  final List<FeatureDoc> items;
  final void Function(String featureId, String fromGroup) onUnassignFromGroup;

  const _UnassignedPanel({
    required this.items,
    required this.onUnassignFromGroup,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<_DragPayload>(
      // aceptamos drags que vienen desde un grupo (para desasignar)
      onWillAccept: (data) => data != null && data.fromGroup != null,
      onAccept: (payload) {
        onUnassignFromGroup(payload.featureId, payload.fromGroup ?? '');
      },
      builder: (context, cand, rej) {
        return Column(
          children: [
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Row(
                children: [
                  Text('Sin asignar', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  Text('${items.length}'),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('Todo asignado 🎯'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: items
                            .map(
                              (f) => LongPressDraggable<_DragPayload>(
                                data: _DragPayload(featureId: f.id, fromGroup: null),
                                feedback: _chip(f.name, dragging: true),
                                childWhenDragging: _chip(f.name, faded: true),
                                child: _chip(f.name),
                              ),
                            )
                            .toList(),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// =====================
/// COLUMNA DE GRUPO
/// =====================
/// COLUMNA DE GRUPO (REEMPLAZAR ESTA CLASE)
/// =====================
class _GroupColumn extends StatelessWidget {
  final String name;
  final List<FeatureDoc> features;
  final void Function(String featureId) onDropFeature;
  final void Function(String featureId) onUnassign;
  final VoidCallback? onDeleteEmptyLocal; // solo para grupos vacíos “locales”

  const _GroupColumn({
    required this.name,
    required this.features,
    required this.onDropFeature,
    required this.onUnassign,
    this.onDeleteEmptyLocal,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<_DragPayload>(
      onWillAccept: (data) => data != null,
      onAccept: (payload) {
        // Si viene desde otro grupo o desde sin asignar, en ambos casos asignamos
        onDropFeature(payload.featureId);
      },
      builder: (context, cand, rej) {
        final highlight = cand.isNotEmpty;
        final isEmpty = features.isEmpty;

        // Uso de ConstrainedBox con maxHeight para evitar errores de layout cuando
        // el padre es un SingleChildScrollView / Wrap (sin altura finita).
        return ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: 260,
            maxWidth: 520,
            minHeight: 180,
            // <-- IMPORTANTE: maxHeight finita para que los Expanded/Flex no fallen.
            maxHeight: 360,
          ),
          child: Card(
            elevation: highlight ? 6 : 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.folder, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(name, style: Theme.of(context).textTheme.titleMedium),
                      ),
                      if (isEmpty && onDeleteEmptyLocal != null)
                        IconButton(
                          tooltip: 'Ocultar grupo vacío',
                          onPressed: onDeleteEmptyLocal,
                          icon: const Icon(Icons.delete_outline),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Reemplazamos Expanded por SizedBox con altura controlada.
                  SizedBox(
                    height: 220, // ajusta este valor si querés más/menos alto
                    child: isEmpty
                        ? Center(
                            child: Opacity(
                              opacity: 0.6,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.call_received_outlined, size: 28),
                                  const SizedBox(height: 6),
                                  Text('Suelta aquí', style: Theme.of(context).textTheme.bodyMedium),
                                ],
                              ),
                            ),
                          )
                        : SingleChildScrollView(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: features
                                  .map(
                                    (f) => LongPressDraggable<_DragPayload>(
                                      data: _DragPayload(
                                        featureId: f.id,
                                        fromGroup: name,
                                        onUnassign: (fid) => onUnassign(fid),
                                      ),
                                      feedback: _chip(f.name, dragging: true),
                                      childWhenDragging: _chip(f.name, faded: true),
                                      child: _chip(
                                        f.name,
                                        onRemove: () => onUnassign(f.id),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text('${features.length} ítems',
                        style: Theme.of(context).textTheme.labelMedium),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}


/// =====================
/// WIDGETS AUXILIARES
/// =====================
class _DragPayload {
  final String featureId;
  final String? fromGroup; // null = venía de “sin asignar”
  final void Function(String featureId)? onUnassign;

  _DragPayload({required this.featureId, required this.fromGroup, this.onUnassign});
}

Widget _chip(String text, {VoidCallback? onRemove, bool dragging = false, bool faded = false}) {
  final child = Chip(
    label: Text(text),
    deleteIcon: onRemove == null ? null : const Icon(Icons.close),
    onDeleted: onRemove,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
  if (dragging) {
    return Material(
      type: MaterialType.transparency,
      child: Opacity(opacity: 0.9, child: child),
    );
  }
  if (faded) {
    return Opacity(opacity: 0.3, child: child);
  }
  return child;
}
