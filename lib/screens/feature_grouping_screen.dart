// lib/screens/feature_grouping_screen.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─── Paleta ───────────────────────────────────────────────────────────────────
const _kBg = Color(0xFF0E1117);
const _kSurface = Color(0xFF1A1E28);
const _kCard = Color(0xFF222736);
const _kAccent = Color(0xFFF1D48B);
const _kText = Colors.white;
const _kMuted = Color(0xFF8A90A2);

// ─── MODELO ───────────────────────────────────────────────────────────────────
class FeatureDoc {
  final String id;
  final String name;
  final String normalized;
  final String? group;

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

  FeatureDoc copyWith({String? name, String? normalized, String? group}) =>
      FeatureDoc(
        id: id,
        name: name ?? this.name,
        normalized: normalized ?? this.normalized,
        group: group,
      );
}

// ─── ESTADO ───────────────────────────────────────────────────────────────────
class FeatureGroupingState extends ChangeNotifier {
  FeatureGroupingState(this._features);

  final Map<String, FeatureDoc> _features;

  Map<String, List<String>> get groups {
    final map = <String, List<String>>{};
    for (final f in _features.values) {
      final g = f.group;
      if (g == null || g.trim().isEmpty) continue;
      (map[g] ??= []).add(f.id);
    }
    for (final k in map.keys) {
      map[k]!.sort(
        (a, b) => _features[a]!.name.toLowerCase().compareTo(
          _features[b]!.name.toLowerCase(),
        ),
      );
    }
    return map;
  }

  List<FeatureDoc> get unassigned {
    final list =
        _features.values.where((f) => (f.group ?? '').isEmpty).toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  List<FeatureDoc> get all {
    final list = _features.values.toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  List<String> get groupNames {
    final s = <String>{};
    for (final f in _features.values) {
      final g = f.group;
      if (g != null && g.trim().isNotEmpty) s.add(g);
    }
    return s.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  bool containsGroup(String name) => groupNames.contains(name);

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

// ─── REPOSITORIO ──────────────────────────────────────────────────────────────
class FeatureRepo {
  const FeatureRepo();

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('card_custom_features');

  Future<Map<String, FeatureDoc>> loadAll() async {
    final snap = await _col.orderBy('name').get();
    final map = <String, FeatureDoc>{};
    for (final d in snap.docs) {
      if (d.data()['unificadaEn'] != null) continue;
      final f = FeatureDoc.fromSnap(d);
      if (f.name.trim().isEmpty) continue;
      map[f.id] = f;
    }
    return map;
  }

  Future<void> updateFeatureGroup(String id, String? group) async {
    final ref = _col.doc(id);
    if (group == null || group.trim().isEmpty) {
      await ref.update({'group': FieldValue.delete()});
    } else {
      await ref.update({'group': group});
    }
  }
}

// ─── PANTALLA ─────────────────────────────────────────────────────────────────
class FeatureGroupingScreen extends StatefulWidget {
  final Map<String, List<String>> initialGroups;

  const FeatureGroupingScreen({super.key, this.initialGroups = const {}});

  @override
  State<FeatureGroupingScreen> createState() => _FeatureGroupingScreenState();
}

class _FeatureGroupingScreenState extends State<FeatureGroupingScreen> {
  final _repo = const FeatureRepo();

  FeatureGroupingState? _state;
  bool _loading = true;

  final Set<String> _localEmptyGroups = {};
  final ValueNotifier<List<String>> _groupsNotifier =
      ValueNotifier<List<String>>([]);

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

      if (widget.initialGroups.isNotEmpty) {
        final normIndex = <String, String>{};
        for (final e in map.entries) {
          normIndex[e.value.normalized.toLowerCase()] = e.key;
          normIndex[e.value.name.toLowerCase()] = e.key;
        }
        for (final entry in widget.initialGroups.entries) {
          for (final rawFeature in entry.value) {
            final r = rawFeature.trim();
            if (r.isEmpty) continue;
            final idMatched =
                normIndex[r.toLowerCase()] ?? normIndex[_normalize(r)];
            if (idMatched != null) {
              map[idMatched] = map[idMatched]!.copyWith(group: entry.key);
            } else {
              final found = map.values.firstWhere(
                (f) =>
                    f.name.toLowerCase() == r.toLowerCase() ||
                    f.normalized.toLowerCase() == _normalize(r) ||
                    f.name.toLowerCase().contains(r.toLowerCase()),
                orElse:
                    () => FeatureDoc(
                      id: '',
                      name: '',
                      normalized: '',
                      group: null,
                    ),
              );
              if (found.id.isNotEmpty) {
                map[found.id] = found.copyWith(group: entry.key);
              }
            }
          }
        }
      }

      _state = FeatureGroupingState(Map<String, FeatureDoc>.from(map));
      _refreshGroupsNotifier();
    } catch (e, st) {
      debugPrint('[FeatureGrouping] load error: $e\n$st');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> _allGroupNames() {
    final result = <String>[];
    if (_state != null) {
      for (final g in _state!.groupNames) {
        if (g.trim().isNotEmpty &&
            !result.any((x) => x.toLowerCase() == g.toLowerCase())) {
          result.add(g);
        }
      }
    }
    for (final g in _localEmptyGroups) {
      if (g.trim().isEmpty) continue;
      if (!result.any((x) => x.toLowerCase() == g.toLowerCase())) {
        result.add(g);
      }
    }
    return result;
  }

  void _refreshGroupsNotifier() {
    _groupsNotifier.value = _allGroupNames();
  }

  Future<void> _addGroupDialog() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder:
          (_) => _DarkDialog(
            title: 'Nuevo grupo',
            content: TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(color: _kText),
              decoration: InputDecoration(
                hintText: 'Ej: Agro, Control…',
                hintStyle: const TextStyle(color: _kMuted),
                filled: true,
                fillColor: _kSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            onConfirm: () => Navigator.pop(context, ctrl.text.trim()),
            onCancel: () => Navigator.pop(context),
          ),
    );

    if (name == null) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      if (mounted) {
        _showSnack('Nombre vacío');
      }
      return;
    }
    if (_allGroupNames().any((g) => g.toLowerCase() == trimmed.toLowerCase())) {
      if (mounted) _showSnack('El grupo ya existe');
      return;
    }

    _localEmptyGroups.add(trimmed);
    _refreshGroupsNotifier();
    if (mounted) setState(() {});
  }

  Future<void> _assignAndPersist(String featureId, String group) async {
    if (_state == null) return;
    _state!.assign(featureId, group);
    _localEmptyGroups.remove(group);
    _refreshGroupsNotifier();
    setState(() {});
    try {
      await _repo.updateFeatureGroup(featureId, group);
    } catch (e) {
      _state!.unassign(featureId);
      _refreshGroupsNotifier();
      setState(() {});
      if (mounted) _showSnack('Error al asignar: $e');
    }
  }

  Future<void> _unassignAndPersist(String featureId) async {
    if (_state == null) return;
    _state!.unassign(featureId);
    _refreshGroupsNotifier();
    setState(() {});
    try {
      await _repo.updateFeatureGroup(featureId, null);
    } catch (e) {
      if (mounted) _showSnack('Error al desasignar: $e');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: _kText)),
        backgroundColor: _kCard,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kSurface,
        foregroundColor: _kText,
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.category_outlined, color: _kAccent, size: 20),
            const SizedBox(width: 10),
            const Text(
              'Agrupar características',
              style: TextStyle(
                color: _kText,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _GoldButton(
              icon: Icons.create_new_folder_outlined,
              label: 'Nuevo grupo',
              onTap: _loading ? null : _addGroupDialog,
            ),
          ),
        ],
      ),
      body:
          _loading || state == null
              ? const Center(child: CircularProgressIndicator(color: _kAccent))
              : Row(
                children: [
                  // ── IZQUIERDA: sin asignar ──
                  SizedBox(
                    width: 260,
                    child: _UnassignedPanel(
                      items: state.unassigned,
                      onUnassignFromGroup: (fid, _) => _unassignAndPersist(fid),
                    ),
                  ),
                  Container(width: 1, color: Colors.white10),
                  // ── DERECHA: grupos ──
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final twoCols = constraints.maxWidth > 860;
                        return ValueListenableBuilder<List<String>>(
                          valueListenable: _groupsNotifier,
                          builder: (context, groupNames, _) {
                            if (groupNames.isEmpty) {
                              return Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.create_new_folder_outlined,
                                      size: 56,
                                      color: _kMuted,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Crea tu primer grupo',
                                      style: TextStyle(
                                        color: _kMuted,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            final tiles =
                                groupNames.map((g) {
                                  final ids = state.groups[g] ?? <String>[];
                                  final features =
                                      ids
                                          .map((id) => state.toMap()[id]!)
                                          .toList()
                                        ..sort(
                                          (a, b) => a.name
                                              .toLowerCase()
                                              .compareTo(b.name.toLowerCase()),
                                        );
                                  final isEmptyLocal =
                                      features.isEmpty &&
                                      _localEmptyGroups.contains(g);

                                  return _GroupCard(
                                    name: g,
                                    features: features,
                                    onDropFeature:
                                        (fid) => _assignAndPersist(fid, g),
                                    onUnassign: _unassignAndPersist,
                                    onDeleteEmptyLocal:
                                        isEmptyLocal
                                            ? () {
                                              _localEmptyGroups.remove(g);
                                              _refreshGroupsNotifier();
                                              if (mounted) setState(() {});
                                            }
                                            : null,
                                  );
                                }).toList();

                            return GridView.count(
                              padding: const EdgeInsets.all(16),
                              crossAxisCount: twoCols ? 2 : 1,
                              childAspectRatio: twoCols ? 1.5 : 2.2,
                              crossAxisSpacing: 14,
                              mainAxisSpacing: 14,
                              children: tiles,
                            );
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

// ─── PANEL IZQUIERDO ──────────────────────────────────────────────────────────
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
      onWillAccept: (data) => data != null && data.fromGroup != null,
      onAccept:
          (payload) =>
              onUnassignFromGroup(payload.featureId, payload.fromGroup ?? ''),
      builder: (context, cand, _) {
        final highlight = cand.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          color:
              highlight ? _kAccent.withValues(alpha: 0.07) : Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    const Text(
                      'Sin asignar',
                      style: TextStyle(
                        color: _kText,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _kSurface,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${items.length}',
                        style: const TextStyle(color: _kMuted, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: Colors.white10),
              Expanded(
                child:
                    items.isEmpty
                        ? Center(
                          child: Text(
                            'Todo asignado ✓',
                            style: TextStyle(color: _kMuted, fontSize: 13),
                          ),
                        )
                        : SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children:
                                items
                                    .map(
                                      (f) => LongPressDraggable<_DragPayload>(
                                        data: _DragPayload(
                                          featureId: f.id,
                                          fromGroup: null,
                                        ),
                                        feedback: _Chip(
                                          label: f.name,
                                          dragging: true,
                                        ),
                                        childWhenDragging: _Chip(
                                          label: f.name,
                                          faded: true,
                                        ),
                                        child: _Chip(label: f.name),
                                      ),
                                    )
                                    .toList(),
                          ),
                        ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── TARJETA DE GRUPO ─────────────────────────────────────────────────────────
class _GroupCard extends StatelessWidget {
  final String name;
  final List<FeatureDoc> features;
  final void Function(String featureId) onDropFeature;
  final void Function(String featureId) onUnassign;
  final VoidCallback? onDeleteEmptyLocal;

  const _GroupCard({
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
      onAccept: (payload) => onDropFeature(payload.featureId),
      builder: (context, cand, _) {
        final highlight = cand.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: highlight ? _kCard.withValues(alpha: 0.9) : _kCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color:
                  highlight
                      ? _kAccent.withValues(alpha: 0.6)
                      : Colors.white.withValues(alpha: 0.07),
              width: highlight ? 1.5 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    const Icon(
                      Icons.folder_outlined,
                      color: _kAccent,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: _kText,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${features.length}',
                      style: const TextStyle(color: _kMuted, fontSize: 12),
                    ),
                    if (onDeleteEmptyLocal != null) ...[
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: onDeleteEmptyLocal,
                        borderRadius: BorderRadius.circular(8),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.close, size: 16, color: _kMuted),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Container(height: 1, color: Colors.white10),
                const SizedBox(height: 8),
                // Chips
                Expanded(
                  child:
                      features.isEmpty
                          ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.south_outlined,
                                  size: 22,
                                  color: _kMuted,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Arrastra aquí',
                                  style: TextStyle(
                                    color: _kMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          )
                          : SingleChildScrollView(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children:
                                  features
                                      .map(
                                        (f) => LongPressDraggable<_DragPayload>(
                                          data: _DragPayload(
                                            featureId: f.id,
                                            fromGroup: name,
                                            onUnassign: onUnassign,
                                          ),
                                          feedback: _Chip(
                                            label: f.name,
                                            dragging: true,
                                          ),
                                          childWhenDragging: _Chip(
                                            label: f.name,
                                            faded: true,
                                          ),
                                          child: _Chip(
                                            label: f.name,
                                            onRemove: () => onUnassign(f.id),
                                          ),
                                        ),
                                      )
                                      .toList(),
                            ),
                          ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── WIDGETS PEQUEÑOS ─────────────────────────────────────────────────────────
class _DragPayload {
  final String featureId;
  final String? fromGroup;
  final void Function(String featureId)? onUnassign;

  _DragPayload({
    required this.featureId,
    required this.fromGroup,
    this.onUnassign,
  });
}

class _Chip extends StatelessWidget {
  final String label;
  final VoidCallback? onRemove;
  final bool dragging;
  final bool faded;

  const _Chip({
    required this.label,
    this.onRemove,
    this.dragging = false,
    this.faded = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: onRemove != null ? _kAccent.withValues(alpha: 0.15) : _kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color:
              onRemove != null
                  ? _kAccent.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: onRemove != null ? _kAccent : _kText,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(10),
              child: const Icon(Icons.close, size: 13, color: _kMuted),
            ),
          ],
        ],
      ),
    );

    if (dragging) {
      return Material(
        type: MaterialType.transparency,
        child: Opacity(opacity: 0.9, child: chip),
      );
    }
    if (faded) return Opacity(opacity: 0.3, child: chip);
    return chip;
  }
}

class _GoldButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _GoldButton({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: _kAccent),
      label: Text(
        label,
        style: const TextStyle(
          color: _kAccent,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
      style: TextButton.styleFrom(
        backgroundColor: _kAccent.withValues(alpha: 0.1),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _DarkDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _DarkDialog({
    required this.title,
    required this.content,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: _kText,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            content,
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onCancel,
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: _kMuted),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: onConfirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: _kAccent,
                    foregroundColor: const Color(0xFF1A120C),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Crear',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
