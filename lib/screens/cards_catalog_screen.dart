// lib/screens/cards_catalog_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/pb_data.dart';
import '../models/card_myl.dart';
import 'card_details_screen.dart';
import 'new_card_screen.dart';

class CardsCatalogScreen extends StatefulWidget {
  const CardsCatalogScreen({super.key});

  @override
  State<CardsCatalogScreen> createState() => _CardsCatalogScreenState();
}

class _CardsCatalogScreenState extends State<CardsCatalogScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  String? _edicion; // null = todas
  String? _tipo; // null = todos
  String? _raza; // null = todas (solo si tipo == Aliado)
  final Set<String> _caracFilter = {};
  List<String> _features = [];
  static const String _ownerEmail = 'hecturnicolas@gmail.com';

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
    switch (t) {
      case 'dano directo':
      case 'daño directo':
        return 'dano directo';
      case 'generador de oro':
      case 'generador de oros':
        return 'generador de oros';
      case 'control de aliado':
      case 'control de aliados':
        return 'control de aliados';
      default:
        return t;
    }
  }

  Map<String, String> get _canon {
  return {for (final k in _features) _normalize(k): k};
}

  @override
  void initState() {
    super.initState();
    _edicion = null;
    _tipo = null;
    _raza = null;
    _searchCtrl.addListener(_onSearchChanged);
    _loadFeaturesFromFirestore();
  }

  Future<void> _loadFeaturesFromFirestore() async {
  final snap = await FirebaseFirestore.instance
      .collection('card_custom_features') // o 'features' si usas esa
      .orderBy('name')
      .get();

  final list = <String>[];
  for (final d in snap.docs) {
    final name = (d.data()['name'] ?? '').toString().trim();
    if (name.isNotEmpty) list.add(name);
  }
  if (!mounted) return;
  setState(() => _features = list);
}


  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      setState(() {}); // dispara rebuild con nuevo término
    });
  }

  bool get _esAliado => (_tipo ?? '').toLowerCase() == 'aliado';

  List<String> get _razasDeEdicion {
    final e = _edicion;
    if (e == null) return const <String>[];
    return PBData.razasPorEdicion[e] ?? const <String>[];
  }

  void _clearFilters() {
    setState(() {
      _edicion = null;
      _tipo = null;
      _raza = null;
      _caracFilter.clear();
      _searchCtrl.clear();
    });
  }

  // ========================================
  // Características desde el modelo/Firestore
  // ========================================
  /// Devuelve un mapa con conteos: { 'byEdition': {edicion: total}, 'byEditionType': {edicion: {tipo: count}}, 'total': int }
Future<Map<String, dynamic>> _fetchCounts() async {
  final snap = await FirebaseFirestore.instance.collection('cards').get();
  final Map<String, int> byEdition = {};
  final Map<String, Map<String, int>> byEditionType = {};
  var total = 0;

  for (final d in snap.docs) {
    final m = d.data();
    final ed = (m['edicion'] ?? 'Sin edición').toString();
    final tipo = (m['tipo'] ?? 'Desconocido').toString();

    // total
    total++;

    // por edición
    byEdition[ed] = (byEdition[ed] ?? 0) + 1;

    // por tipo dentro de edición
    byEditionType.putIfAbsent(ed, () => {});
    byEditionType[ed]![tipo] = (byEditionType[ed]![tipo] ?? 0) + 1;
  }

  return {
    'total': total,
    'byEdition': byEdition,
    'byEditionType': byEditionType,
  };
}

/// Muestra diálogo con los conteos (usa FutureBuilder para mostrar loading mientras carga).
void _showCountsDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: SizedBox(
        width: 520,
        height: 520,
        child: FutureBuilder<Map<String, dynamic>>(
          future: _fetchCounts(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ));
            }
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Error al calcular estadísticas', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Text('${snap.error}'),
                    const SizedBox(height: 12),
                    TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar')),
                  ],
                ),
              );
            }

            final data = snap.data!;
            final int total = data['total'] as int;
            final Map<String, int> byEdition = Map<String,int>.from(data['byEdition'] as Map);
            final Map<String, Map<String, int>> byEditionType = (data['byEditionType'] as Map).map(
              (k, v) => MapEntry(k as String, Map<String,int>.from(v as Map))
            );

            final editionsSorted = byEdition.keys.toList()
              ..sort((a,b) => byEdition[b]!.compareTo(byEdition[a]!)); // descendente

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline),
                      const SizedBox(width: 8),
                      Text('Estadísticas — Total: $total', style: const TextStyle(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    separatorBuilder: (_,__) => const SizedBox(height: 8),
                    itemCount: editionsSorted.length,
                    itemBuilder: (context, i) {
                      final ed = editionsSorted[i];
                      final edTotal = byEdition[ed] ?? 0;
                      final types = byEditionType[ed] ?? {};
                      // ordenar tipos por cantidad descendente
                      final typesList = types.keys.toList()..sort((a,b) => types[b]!.compareTo(types[a]!));

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$ed — $edTotal', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 10,
                            runSpacing: 6,
                            children: typesList.map((t) {
                              final cnt = types[t] ?? 0;
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.6),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text('$t: $cnt', style: const TextStyle(fontWeight: FontWeight.w600)),
                              );
                            }).toList(),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}


List<String> _caracteristicasDe(CardMyL c) {
    final dynamic raw = c.caracteristicasRaw;
    final Set<String> out = {};
    if (raw == null) return const [];

    if (raw is List) {
      for (final e in raw) {
        final base = _normalize(e);
        final canon = _canon[base];
        if (canon != null) out.add(canon);
        else {
          // si no es canonical, quizá sea custom
          final s = e?.toString() ?? '';
          if (s.isNotEmpty) out.add(s);
        }
      }
    } else if (raw is Map<String, dynamic>) {
      raw.forEach((k, v) {
        if (v == true) {
          final base = _normalize(k);
          final canon = _canon[base];
          if (canon != null) out.add(canon);
          else {
            final s = k.toString();
            if (s.isNotEmpty) out.add(s);
          }
        }
      });
    } else if (raw is String) {
      for (final part in raw.split(',')) {
        final base = _normalize(part);
        final canon = _canon[base];
        if (canon != null) out.add(canon);
        else {
          final s = part.toString().trim();
          if (s.isNotEmpty) out.add(s);
        }
      }
    }

    final list = out.toList()
  ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
return list;
  }

  bool _pasaCaracteristicas(CardMyL c) {
    if (_caracFilter.isEmpty) return true;
    final mine = _caracteristicasDe(c).toSet();
    for (final f in _caracFilter) {
      if (!mine.contains(f)) return false;
    }
    return true;
  }

  // ===== función para eliminar carta (solo owner) =====
  Future<void> _confirmAndDeleteCard(String cardId) async {
    final user = FirebaseAuth.instance.currentUser;
    final isOwner = (user?.email?.toLowerCase() ?? '') == _ownerEmail;
    if (!isOwner) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar carta'),
        content: Text('¿Seguro querés eliminar la carta "$cardId"? Se borrarán sus variantes también.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() {});
    final ScaffoldMessengerState sm = ScaffoldMessenger.of(context);
    try {
      final cardRef = FirebaseFirestore.instance.collection('cards').doc(cardId);

      // eliminar variantes en batch (si existen)
      final variantsSnap = await cardRef.collection('variants').get();
      final batch = FirebaseFirestore.instance.batch();
      for (final d in variantsSnap.docs) {
        batch.delete(d.reference);
      }
      // borrar doc de la carta
      batch.delete(cardRef);

      await batch.commit();
      sm.showSnackBar(const SnackBar(content: Text('Carta eliminada correctamente.')));
    } catch (e) {
      sm.showSnackBar(SnackBar(content: Text('Error al eliminar: $e')));
    } finally {
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance.collection('cards').orderBy('nombre').snapshots();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.amber.shade300,
        title: const Text('Catálogo — Primer Bloque'),
        centerTitle: true,
        actions: [
          IconButton(
  tooltip: 'Estadísticas (por edición / tipo)',
  icon: const Icon(Icons.info_outline),
  onPressed: () => _showCountsDialog(context),
),
          IconButton(
            tooltip: 'Nueva carta',
            icon: const Icon(Icons.add_card),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NewCardScreen()),
              );
            },
          ),
          Builder(
            builder: (ctx) => IconButton(
              tooltip: 'Filtrar por características',
              icon: const Icon(Icons.tune),
              onPressed: () {
                final width = MediaQuery.of(ctx).size.width;
                if (width >= 900) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('El panel de características ya está a la derecha.')),
                  );
                } else {
                  _openCaracFilterSheet(ctx);
                }
              },
            ),
          ),
          IconButton(
            tooltip: 'Limpiar filtros',
            onPressed: _clearFilters,
            icon: const Icon(Icons.filter_alt_off),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(80),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // 🔍 Buscador
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Buscar…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 📀 Edición
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String>(
                      value: _edicion,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Edición',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('Todas'),
                        ),
                        ...PBData.ediciones.map((e) => DropdownMenuItem(value: e, child: Text(e))),
                      ],
                      onChanged: (v) => setState(() {
                        _edicion = v;
                        if (_raza != null && !_razasDeEdicion.contains(_raza)) {
                          _raza = null;
                        }
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 🧾 Tipo
                  SizedBox(
                    width: 160,
                    child: DropdownButtonFormField<String>(
                      value: _tipo,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Tipo',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem<String>(value: null, child: Text('Todos')),
                        DropdownMenuItem(value: 'Aliado', child: Text('Aliado')),
                        DropdownMenuItem(value: 'Talismán', child: Text('Talismán')),
                        DropdownMenuItem(value: 'Tótem', child: Text('Tótem')),
                        DropdownMenuItem(value: 'Arma', child: Text('Arma')),
                        DropdownMenuItem(value: 'Oro', child: Text('Oro')),
                      ],
                      onChanged: (v) => setState(() {
                        _tipo = v;
                        if (!_esAliado) _raza = null;
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 🧬 Raza (si corresponde)
                  if (_esAliado && _edicion != null)
                    SizedBox(
                      width: 160,
                      child: DropdownButtonFormField<String>(
                        value: _raza,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Raza',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem<String>(value: null, child: Text('Todas')),
                          ..._razasDeEdicion.map((r) => DropdownMenuItem(value: r, child: Text(r))),
                        ],
                        onChanged: (v) => setState(() => _raza = v),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final docs = snap.data?.docs ?? [];

          // Mapeamos a modelos
          final allCards = docs.map((d) => CardMyL.fromMap(d.data(), d.id)).toList();

          // Lista canónica base (ahora incluye lo que cargamos en _customFeatures en init)
          final List<String> allCaracs = List.of(_features);

          // Filtros en cliente
          final q = _searchCtrl.text.trim().toLowerCase();
          final preCharFiltered = allCards.where((c) {
            if (q.isNotEmpty && !c.nombre.toLowerCase().contains(q)) return false;
            if (_edicion != null && c.edicion != _edicion) return false;
            if (_tipo != null && c.tipo != _tipo) return false;
            if (_raza != null) {
              if (c.tipo.toLowerCase() != 'aliado') return false;
              if ((c.raza ?? '') != _raza) return false;
            }
            return true;
          }).toList();

          // Contadores por característica (previos a aplicar _caracFilter)
          final Map<String, int> caracCounts = {for (final c in allCaracs) c: 0};
          for (final card in preCharFiltered) {
            final set = _caracteristicasDe(card).toSet();
            for (final name in allCaracs) {
              if (set.contains(name)) {
                caracCounts[name] = (caracCounts[name] ?? 0) + 1;
              }
            }
          }

          // Mostrar solo características con conteo > 0
          final List<String> visibleCaracs = allCaracs.where((c) => (caracCounts[c] ?? 0) > 0).toList();

          // Aplicar filtro por características (AND)
          final items = preCharFiltered.where(_pasaCaracteristicas).toList();

          final wide = MediaQuery.of(context).size.width >= 900;

          if (items.isEmpty) {
            return wide
                ? Row(
                    children: [
                      const Expanded(child: _EmptyResultHint()),
                      _RightPanel(
                        allCaracs: visibleCaracs,
                        caracCounts: caracCounts,
                        selected: _caracFilter,
                        onToggle: (name, v) => setState(() {
                          if (v) {
                            _caracFilter.add(name);
                          } else {
                            _caracFilter.remove(name);
                          }
                        }),
                        onClear: () => setState(_caracFilter.clear),
                      ),
                    ],
                  )
                : const _EmptyResultHint();
          }

          final user = FirebaseAuth.instance.currentUser;
          final isOwnerGlobal = (user?.email?.toLowerCase() ?? '') == _ownerEmail;

          final list = ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final card = items[i];
              final caracs = _caracteristicasDe(card);

              return ListTile(
                leading: _VariantThumbFromCard(cardId: card.id, fallbackTipo: card.tipo),
                title: Text(card.nombre),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${card.tipo}'
                      ' · ${card.edicion}'
                      ' · ${card.rareza}'
                      '${card.esAliado && card.fuerza != null ? ' · Fuerza ${card.fuerza}' : ''}'
                      ' · Coste ${card.coste}'
                      '${card.esAliado && (card.raza?.isNotEmpty ?? false) ? ' · ${card.raza}' : ''}',
                    ),
                    if (caracs.isNotEmpty) const SizedBox(height: 4),
                    if (caracs.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: -6,
                        children: caracs
                            .map((c) => Chip(
                                  label: Text(c),
                                  visualDensity: VisualDensity.compact,
                                ))
                            .toList(),
                      ),
                  ],
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => CardDetailsScreen(card: card)),
                  );
                },
                trailing: isOwnerGlobal
                    ? IconButton(
                        tooltip: 'Eliminar carta',
                        icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                        onPressed: () => _confirmAndDeleteCard(card.id),
                      )
                    : null,
              );
            },
          );

          if (!wide) {
            // Vista móvil (sin panel lateral visible)
            return Column(
              children: [
                if (_caracFilter.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: -6,
                        children: [
                          ..._caracFilter.map(
                            (c) => InputChip(
                              label: Text(c),
                              onDeleted: () => setState(() => _caracFilter.remove(c)),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => setState(_caracFilter.clear),
                            icon: const Icon(Icons.clear_all),
                            label: const Text('Limpiar características'),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(child: list),
              ],
            );
          }

          // Vista ancha con panel lateral
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: list),
              _RightPanel(
                allCaracs: visibleCaracs,
                caracCounts: caracCounts,
                selected: _caracFilter,
                onToggle: (name, v) => setState(() {
                  if (v) {
                    _caracFilter.add(name);
                  } else {
                    _caracFilter.remove(name);
                  }
                }),
                onClear: () => setState(_caracFilter.clear),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openCaracFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: false,
      builder: (ctx) {
        final stream = FirebaseFirestore.instance.collection('cards').orderBy('nombre').snapshots();

        return SafeArea(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: stream,
            builder: (context, snap) {
              final docs = snap.data?.docs ?? [];
              final allCards = docs.map((d) => CardMyL.fromMap(d.data(), d.id)).toList();
              final List<String> allCaracs = List.of(_features);

              final q = _searchCtrl.text.trim().toLowerCase();
              final preCharFiltered = allCards.where((c) {
                if (q.isNotEmpty && !c.nombre.toLowerCase().contains(q)) return false;
                if (_edicion != null && c.edicion != _edicion) return false;
                if (_tipo != null && c.tipo != _tipo) return false;
                if (_raza != null) {
                  if (c.tipo.toLowerCase() != 'aliado') return false;
                  if ((c.raza ?? '') != _raza) return false;
                }
                return true;
              }).toList();

              final Map<String, int> caracCounts = {for (final c in allCaracs) c: 0};
              for (final card in preCharFiltered) {
                final set = _caracteristicasDe(card).toSet();
                for (final name in allCaracs) {
                  if (set.contains(name)) {
                    caracCounts[name] = (caracCounts[name] ?? 0) + 1;
                  }
                }
              }

              final List<String> visibleCaracs =
                  allCaracs.where((c) => (caracCounts[c] ?? 0) > 0).toList();

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.tune),
                        const SizedBox(width: 8),
                        const Text('Filtrar por características',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () {
                            setState(_caracFilter.clear);
                            Navigator.pop(context);
                          },
                          icon: const Icon(Icons.clear_all),
                          label: const Text('Limpiar'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final name in visibleCaracs)
                            CheckboxListTile(
                              value: _caracFilter.contains(name),
                              onChanged: (bool? v) {
                                setState(() {
                                  if (v == true) {
                                    _caracFilter.add(name);
                                  } else {
                                    _caracFilter.remove(name);
                                  }
                                });
                              },
                              dense: true,
                              title: Text(name),
                              secondary: CircleAvatar(
                                radius: 12,
                                child: Text(
                                  (caracCounts[name] ?? 0).toString(),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.check),
                        label: const Text('Aplicar'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _EmptyResultHint extends StatelessWidget {
  const _EmptyResultHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 56),
            const SizedBox(height: 10),
            const Text('Sin resultados'),
            const SizedBox(height: 6),
            Text(
              'Ajusta el texto de búsqueda o quita filtros.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _RightPanel extends StatelessWidget {
  final List<String> allCaracs;
  final Map<String, int> caracCounts;
  final Set<String> selected;
  final void Function(String name, bool value) onToggle;
  final VoidCallback onClear;

  const _RightPanel({
    Key? key,
    required this.allCaracs,
    required this.caracCounts,
    required this.selected,
    required this.onToggle,
    required this.onClear,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.6),
        border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                const Icon(Icons.bolt_outlined),
                const SizedBox(width: 8),
                const Text('Características', style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.clear_all),
                  label: const Text('Limpiar'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final name in allCaracs)
                  CheckboxListTile(
                    value: selected.contains(name),
                    onChanged: (v) => onToggle(name, v ?? false),
                    dense: true,
                    title: Text(name),
                    secondary: CircleAvatar(
                      radius: 12,
                      child: Text(
                        (caracCounts[name] ?? 0).toString(),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Miniatura de una carta basada en su MEJOR variante disponible:
/// - official == true
/// - luego isBase == true
/// - luego la primera por name
class _VariantThumbFromCard extends StatelessWidget {
  final String cardId;
  final String fallbackTipo;
  const _VariantThumbFromCard({required this.cardId, required this.fallbackTipo});

  // ---- URL desde el doc principal (cards/{id}) ----
  String? _pickFromDoc(Map<String, dynamic> m) {
    // comunes en tu base (según screenshot)
    for (final key in [
      'officialImageUrl',
      'imageUrl',
      'officialImage',
      'frontUrl',
      'img',
      'url',
    ]) {
      final v = m[key];
      if (v is String && v.isNotEmpty) return v;
    }

    // anidados típicos
    final images = m['images'];
    if (images is Map) {
      for (final k in ['front', 'anverso']) {
        final v = images[k];
        if (v is String && v.isNotEmpty) return v;
      }
    }
    return null;
  }

  // ---- URL desde una variante (cards/{id}/variants/{vid}) ----
  String? _pickFromVariant(Map<String, dynamic> m) {
    final thumbs = m['thumbs'];
    if (thumbs is Map) {
      for (final k in ['56x56', '64x64', '72x72', '80x80', '96x96', 'small', 'thumb', 's']) {
        final v = thumbs[k];
        if (v is String && v.isNotEmpty) return v;
      }
      for (final v in thumbs.values) {
        if (v is String && v.isNotEmpty) return v;
      }
    }
    for (final key in [
      'thumbUrl',
      'imageFrontThumb',
      'imageFrontUrl',
      'frontUrl',
      'imageUrl',
      'officialImageUrl',
      'officialImage',
      'img',
      'url',
    ]) {
      final v = m[key];
      if (v is String && v.isNotEmpty) return v;
    }
    final images = m['images'];
    if (images is Map) {
      for (final k in ['front', 'anverso']) {
        final v = images[k];
        if (v is String && v.isNotEmpty) return v;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cardRef = FirebaseFirestore.instance.collection('cards').doc(cardId);

    // 1) Escucha el doc principal: si trae URL, úsala.
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: cardRef.snapshots(),
      builder: (context, docSnap) {
        String? topUrl;
        if (docSnap.hasData && docSnap.data!.data() != null) {
          topUrl = _pickFromDoc(docSnap.data!.data()!);
        }
        if (topUrl != null && topUrl.isNotEmpty) {
          return _CardThumb(url: topUrl, fallbackTipo: fallbackTipo);
        }

        // 2) Si no hubo URL en el doc, cae a variants.
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: cardRef
              .collection('variants')
              .orderBy('official', descending: true)
              .orderBy('isBase', descending: true)
              .orderBy('name')
              .limit(6)
              .snapshots(),
          builder: (context, varSnap) {
            String? vurl;
            if (varSnap.hasData && varSnap.data!.docs.isNotEmpty) {
              for (final d in varSnap.data!.docs) {
                vurl = _pickFromVariant(d.data());
                if (vurl != null && vurl.isNotEmpty) break;
              }
            }
            return _CardThumb(url: vurl, fallbackTipo: fallbackTipo);
          },
        );
      },
    );
  }
}

class _CardThumb extends StatelessWidget {
  final String? url;
  final String fallbackTipo;
  const _CardThumb({required this.url, required this.fallbackTipo});

  Color _colorPorTipo(String t) {
    t = t.toLowerCase();
    if (t == 'aliado') return Colors.teal;
    if (t == 'talismán' || t == 'talisman') return Colors.deepPurple;
    if (t == 'tótem' || t == 'totem') return Colors.orange;
    if (t == 'arma') return Colors.brown;
    if (t == 'oro') return Colors.amber;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    const double size = 56;

    Widget fallback() => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: _colorPorTipo(fallbackTipo).withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.image_not_supported, size: 22),
        );

    if (url == null || url!.isEmpty) return fallback();

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          url!,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          },
          errorBuilder: (_, __, ___) => fallback(),
        ),
      ),
    );
  }
}
