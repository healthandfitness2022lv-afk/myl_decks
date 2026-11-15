// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../domain/inventory_planner.dart';
import '../domain/collection_reconciliation.dart';
import '../domain/deck_stock_groups.dart';
import '../models/card_myl.dart';
import '../models/card_variant.dart';
import '../models/deck.dart';
import '../models/inventory.dart';
import '../services/card_service.dart';
import '../services/inventory_service.dart';
import '../utils/text_normalize.dart';
import '../utils/card_image_resolver.dart';
import '../widgets/card_image.dart';

enum _CollectionView { owned, missing }

class CardInventoryScreen extends StatefulWidget {
  final List<Deck> decks;
  final List<Deck> targetDecks;
  const CardInventoryScreen({
    super.key,
    required this.decks,
    this.targetDecks = const [],
  });

  @override
  State<CardInventoryScreen> createState() => _CardInventoryScreenState();
}

class _CardInventoryScreenState extends State<CardInventoryScreen> {
  late final InventoryService _service;
  String _query = '';
  bool _migrating = true;
  _CollectionView _view = _CollectionView.owned;
  String? _typeFilter;
  String? _editionFilter;
  final Map<String, String?> _baseImageByCardId = {};
  final Map<String, _VariantVisual> _variantVisuals = {};
  final Set<String> _loadingVisuals = {};
  // Variante oficial de cada carta (o la única si el catálogo solo tiene
  // una): las copias sin variante identificada se muestran agrupadas bajo
  // esta, en vez de una etiqueta genérica "Normal" que sugiere una versión
  // que no existe.
  final Map<String, _VariantVisual?> _assumedVariantByCardId = {};

  @override
  void initState() {
    super.initState();
    _service = InventoryService(FirebaseAuth.instance.currentUser!.uid);
    _migrate();
  }

  Future<void> _migrate() async {
    try {
      // targetDecks es un subconjunto de decks; no se concatena para evitar
      // que una misma configuración participe dos veces en la migración.
      await _service.migrateFromDecksIfNeeded(widget.decks);
      // Repara en silencio items que quedaron con "Sin edición" por un bug
      // ya corregido (agregar copias desde el detalle de un mazo no
      // guardaba la edición de la carta).
      await _service.repairMissingEditions();
    } catch (error) {
      if (mounted) _snack('No se pudo preparar el inventario: $error');
    } finally {
      if (mounted) setState(() => _migrating = false);
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C10),
      appBar: AppBar(
        title: const Text('Mi colección'),
        backgroundColor: const Color(0xFF12141B),
        foregroundColor: Colors.white,
        actions: [],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCard,
        icon: const Icon(Icons.add),
        label: const Text('Agregar carta'),
      ),
      body:
          _migrating
              ? const Center(child: CircularProgressIndicator())
              : StreamBuilder<List<InventoryItem>>(
                stream: _service.watchInventory(),
                builder: (context, inventorySnapshot) {
                  if (inventorySnapshot.hasError)
                    return _ErrorState('${inventorySnapshot.error}');
                  if (!inventorySnapshot.hasData)
                    return const Center(child: CircularProgressIndicator());
                  final inventory = inventorySnapshot.data!;
                  return _buildInventory(inventory);
                },
              ),
    );
  }

  Widget _buildInventory(List<InventoryItem> items) {
    final shortages = calculateCollectionShortages(
      decks: widget.targetDecks,
      inventory: items,
    );
    _scheduleVisualLoad([
      ...items,
      for (final shortage in shortages)
        InventoryItem(
          key: shortage.itemKey,
          cardId: shortage.cardId,
          name: shortage.cardName,
          edition: shortage.edition,
          type: shortage.type,
          total: 0,
        ),
    ]);
    final query = normalizeSearch(_query);
    final types =
        items
            .map((i) => (i.type ?? '').trim())
            .where((t) => t.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final editionOptions =
        items
            .map((i) => (i.edition ?? '').trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final filtered =
        items
            .where(
              (item) =>
                  query.isEmpty ||
                  normalizeSearch(
                    '${item.name} ${item.edition ?? ''}',
                  ).contains(query),
            )
            .where(
              (item) =>
                  _typeFilter == null ||
                  (item.type ?? '').trim() == _typeFilter,
            )
            .where(
              (item) =>
                  _editionFilter == null ||
                  (item.edition ?? '').trim() == _editionFilter,
            )
            .toList();
    final entries = <_BinderEntry>[];
    for (final item in filtered) {
      // Copias sin variante identificada: se asumen como la oficial (o la
      // única del catálogo) en vez de mostrarse aparte con una etiqueta
      // genérica "Normal" que sugiere una impresión que no existe. Si esa
      // variante asumida coincide con una ya declarada, se suman en la
      // misma fila; si no, aparecen en su propia fila con ese nombre.
      final assumed = _assumedVariantByCardId[item.cardId];
      final declaredVariants =
          item.variantTotals.entries.where((entry) => entry.value > 0).toList();
      final variantCopies = declaredVariants.fold<int>(
        0,
        (sum, entry) => sum + entry.value,
      );
      final unidentified = (item.total - variantCopies).clamp(0, item.total);

      String? mergeTargetVariantId;
      if (unidentified > 0 && assumed != null) {
        mergeTargetVariantId =
            declaredVariants
                .where((entry) => entry.key == assumed.id)
                .firstOrNull
                ?.key;
      }

      for (final variant in declaredVariants) {
        final visual = _variantVisuals['${item.cardId}|${variant.key}'];
        final merged = variant.key == mergeTargetVariantId;
        final extra = merged ? unidentified : 0;
        entries.add(
          _BinderEntry(
            item: item,
            variantId: variant.key,
            variantLabel: visual?.name ?? 'Variante',
            quantity: variant.value + extra,
            imageUrl: visual?.url ?? _baseImageByCardId[item.cardId],
            includesUnidentified: merged,
          ),
        );
      }
      if (unidentified > 0 && mergeTargetVariantId == null) {
        entries.add(
          _BinderEntry(
            item: item,
            variantLabel: assumed?.name ?? 'Sin variante identificada',
            quantity: unidentified,
            imageUrl: assumed?.url ?? _baseImageByCardId[item.cardId],
          ),
        );
      }
    }
    final visibleEntries = switch (_view) {
      _CollectionView.owned => entries,
      _CollectionView.missing => <_BinderEntry>[],
    };
    // Copias compartidas entre mazos: por carta cuenta el mazo que más pide.
    final missingByKey = <String, int>{};
    for (final shortage in shortages) {
      final current = missingByKey[shortage.itemKey] ?? 0;
      if (shortage.quantity > current) {
        missingByKey[shortage.itemKey] = shortage.quantity;
      }
    }
    final missingCopies = missingByKey.values.fold<int>(0, (a, b) => a + b);
    final byEdition = <String, List<_BinderEntry>>{};
    for (final entry in visibleEntries) {
      final edition = (entry.item.edition ?? '').trim();
      byEdition
          .putIfAbsent(edition.isEmpty ? 'Sin edición' : edition, () => [])
          .add(entry);
    }
    final editions = byEdition.keys.toList()..sort();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            onChanged: (value) => setState(() => _query = value),
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration(
              'Buscar en tu colección...',
              Icons.search,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _Metric(label: 'Cartas', value: '${items.length}'),
              const SizedBox(width: 8),
              _Metric(
                label: 'Copias',
                value: '${items.fold<int>(0, (s, e) => s + e.total)}',
              ),
              const SizedBox(width: 8),
              _Metric(label: 'Me faltan', value: '$missingCopies'),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SegmentedButton<_CollectionView>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: _CollectionView.owned,
                label: Text('Mis cartas'),
              ),
              ButtonSegment(
                value: _CollectionView.missing,
                label: Text('Me faltan'),
              ),
            ],
            selected: {_view},
            onSelectionChanged: (value) => setState(() => _view = value.first),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: _FilterDropdown(
                  hint: 'Tipo',
                  value: _typeFilter,
                  options: types,
                  onChanged: (value) => setState(() => _typeFilter = value),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FilterDropdown(
                  hint: 'Edición',
                  value: _editionFilter,
                  options: editionOptions,
                  onChanged: (value) => setState(() => _editionFilter = value),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child:
              _view == _CollectionView.missing
                  ? _MissingCollectionView(
                    shortages: shortages,
                    imageByCardId: _baseImageByCardId,
                    query: query,
                    typeFilter: _typeFilter,
                    editionFilter: _editionFilter,
                  )
                  : visibleEntries.isEmpty
                  ? _EmptyState(
                    icon: Icons.style_outlined,
                    text:
                        items.isEmpty
                            ? 'Agrega las cartas físicas con las que cuentas.'
                            : 'Ninguna carta coincide con los filtros.',
                  )
                  : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                    itemCount: editions.length,
                    itemBuilder: (_, index) {
                      final edition = editions[index];
                      final editionEntries = byEdition[edition]!;
                      return _BinderSection(
                        edition: edition,
                        entries: editionEntries,
                        onOpen: _openBinderEntry,
                      );
                    },
                  ),
        ),
      ],
    );
  }

  // Cargar la colección completa de golpe cuando el inventario tiene muchas
  // cartas dispara decenas de lecturas Firestore (hasta 4 por carta) apenas
  // se abre la pantalla, aunque el usuario nunca llegue a desplazarse hasta
  // verlas. En vez de eso se resuelve en lotes chicos con una pausa entre
  // cada uno, así la grilla se puebla progresivamente sin picos de red.
  static const _visualBatchSize = 24;
  static const _visualBatchDelay = Duration(milliseconds: 220);
  bool _visualLoadRunning = false;

  void _scheduleVisualLoad(List<InventoryItem> inventory) {
    final pending =
        inventory.where((item) {
          final cardId = item.cardId?.trim() ?? '';
          if (cardId.isEmpty) return false;
          if (_loadingVisuals.contains(cardId)) return false;
          if (!_baseImageByCardId.containsKey(cardId)) return true;
          if (!_assumedVariantByCardId.containsKey(cardId)) return true;
          return item.variantTotals.keys.any(
            (variantId) => !_variantVisuals.containsKey('$cardId|$variantId'),
          );
        }).toList();
    if (pending.isEmpty || _visualLoadRunning) return;
    _visualLoadRunning = true;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _loadVisualsInBatches(pending),
    );
  }

  Future<void> _loadVisualsInBatches(List<InventoryItem> items) async {
    try {
      for (var start = 0; start < items.length; start += _visualBatchSize) {
        if (!mounted) return;
        final end = (start + _visualBatchSize).clamp(0, items.length);
        await _loadVisuals(items.sublist(start, end));
        if (end < items.length) await Future.delayed(_visualBatchDelay);
      }
    } finally {
      _visualLoadRunning = false;
    }
  }

  Future<void> _loadVisuals(List<InventoryItem> items) async {
    final db = FirebaseFirestore.instance;
    var changed = false;
    for (final item in items) {
      final cardId = item.cardId?.trim() ?? '';
      if (cardId.isEmpty || !_loadingVisuals.add(cardId)) continue;
      try {
        final cardRef = db.collection('cards').doc(cardId);
        if (!_baseImageByCardId.containsKey(cardId)) {
          final card = await cardRef.get();
          final data = card.data() ?? const <String, dynamic>{};
          String? url = _firstImage(data);
          if (url == null) {
            var variants =
                await cardRef
                    .collection('variants')
                    .where('official', isEqualTo: true)
                    .limit(1)
                    .get();
            if (variants.docs.isEmpty)
              variants =
                  await cardRef
                      .collection('variants')
                      .where('isBase', isEqualTo: true)
                      .limit(1)
                      .get();
            if (variants.docs.isEmpty)
              variants = await cardRef.collection('variants').limit(1).get();
            if (variants.docs.isNotEmpty)
              url = _firstImage(variants.docs.first.data());
          }
          _baseImageByCardId[cardId] = url;
          changed = true;
        }
        if (!_assumedVariantByCardId.containsKey(cardId)) {
          _assumedVariantByCardId[cardId] = await _resolveAssumedVariant(
            cardRef,
          );
          changed = true;
        }
        for (final variantId in item.variantTotals.keys) {
          final key = '$cardId|$variantId';
          if (_variantVisuals.containsKey(key)) continue;
          final variant =
              await cardRef.collection('variants').doc(variantId).get();
          final data = variant.data() ?? const <String, dynamic>{};
          _variantVisuals[key] = _VariantVisual(
            id: variantId,
            name: (data['printType'] ?? data['name'] ?? 'Variante').toString(),
            url: _firstImage(data),
          );
          changed = true;
        }
      } catch (_) {
        _baseImageByCardId.putIfAbsent(cardId, () => null);
      } finally {
        _loadingVisuals.remove(cardId);
      }
    }
    if (changed && mounted) setState(() {});
  }

  String? _firstImage(Map<String, dynamic> data) {
    return CardImageResolver.fromMap(data);
  }

  /// Qué variante asumir para las copias sin variante identificada: la
  /// marcada oficial, o la única del catálogo si no hay ambigüedad. Con dos
  /// o más variantes y ninguna oficial, no se asume nada (null) — ahí sí
  /// puede ser cualquiera y corresponde declararla a mano.
  Future<_VariantVisual?> _resolveAssumedVariant(
    DocumentReference<Map<String, dynamic>> cardRef,
  ) async {
    try {
      final official =
          await cardRef
              .collection('variants')
              .where('official', isEqualTo: true)
              .limit(1)
              .get();
      if (official.docs.isNotEmpty) {
        final data = official.docs.first.data();
        return _VariantVisual(
          id: official.docs.first.id,
          name: (data['printType'] ?? data['name'] ?? 'Variante').toString(),
          url: _firstImage(data),
        );
      }
      final base =
          await cardRef
              .collection('variants')
              .where('isBase', isEqualTo: true)
              .limit(1)
              .get();
      if (base.docs.isNotEmpty) {
        final data = base.docs.first.data();
        return _VariantVisual(
          id: base.docs.first.id,
          name: (data['printType'] ?? data['name'] ?? 'Variante').toString(),
          url: _firstImage(data),
        );
      }
      final all = await cardRef.collection('variants').limit(2).get();
      if (all.docs.length == 1) {
        final data = all.docs.first.data();
        return _VariantVisual(
          id: all.docs.first.id,
          name: (data['printType'] ?? data['name'] ?? 'Variante').toString(),
          url: _firstImage(data),
        );
      }
    } catch (_) {}
    return null;
  }

  void _openBinderEntry(_BinderEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF171A22),
      isScrollControlled: true,
      builder:
          (context) => _BinderDetails(
            entry: entry,
            decks: widget.decks,
            onEdit: () {
              Navigator.pop(context);
              _editTotal(entry.item);
            },
          ),
    );
  }

  /// Editar cantidad total: muestra el desglose actual por versión y, si el
  /// número cambia, pide declarar la variante de las copias que queden
  /// ambiguas — primero las que están en un mazo (una pregunta por mazo),
  /// después el resto de copias sueltas. Copias que ya tenían variante
  /// inequívoca no se vuelven a preguntar.
  Future<void> _editTotal(InventoryItem item) async {
    final controller = TextEditingController(text: '${item.total}');
    final variantNames = <String, String>{};
    for (final variantId in item.variantTotals.keys) {
      variantNames[variantId] =
          _variantVisuals['${item.cardId}|$variantId']?.name ?? 'Variante';
    }
    final value = await showDialog<int>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(item.name),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.variantTotals.isNotEmpty || item.unidentified > 0) ...[
                  const Text(
                    'Tienes registradas:',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final entry in item.variantTotals.entries)
                    if (entry.value > 0)
                      Text(
                        '${entry.value}x ${variantNames[entry.key] ?? 'Variante'}',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 13,
                        ),
                      ),
                  if (item.unidentified > 0)
                    Text(
                      '${item.unidentified}x sin variante identificada',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: InputDecoration(labelText: 'Copias totales'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed:
                    () => Navigator.pop(context, int.tryParse(controller.text)),
                child: const Text('Guardar'),
              ),
            ],
          ),
    );
    if (value == null || value == item.total) return;
    try {
      await _service.setTotal(item, value);
    } catch (error) {
      _snack('$error');
      return;
    }
  }

  Future<void> _addCard() async {
    final inventory = await _service.listInventory();
    if (!mounted) return;
    final changes = await showDialog<List<InventoryBatchChange>>(
      context: context,
      builder:
          (_) => _QuickInventoryDialog(
            inventoryByCardId: {
              for (final item in inventory)
                if ((item.cardId ?? '').isNotEmpty) item.cardId!: item,
            },
          ),
    );
    if (changes == null || changes.isEmpty || !mounted) return;
    try {
      await _service.applyInventoryBatch(changes);
      if (!mounted) return;
      _snack(
        '${changes.fold<int>(0, (sum, item) => sum + item.quantity)} copias agregadas.',
      );
    } catch (error) {
      _snack('$error');
    }
  }

  /// Tras agregar una carta al inventario, si algún mazo activo la incluye
  /// en su configuración y aún le faltan copias, ofrece asignarle el stock
  /// libre recién agregado sin tener que ir manualmente a "Editar mazo".
  Future<void> _offerAssignToNeediestDeck(CardMyL card) async {
    final key = inventoryKey(
      cardId: card.id,
      name: card.nombre,
      edition: card.edicion,
    );
    final items = await _service.listInventory();
    final item = items.where((i) => i.key == key).firstOrNull;
    if (item == null || item.free <= 0) return;

    final needy = <(Deck, int)>[];
    for (final deck in widget.targetDecks.where((d) => d.isUnified)) {
      final needed = deck.cards
          .where((entry) => entryInventoryKey(entry) == key)
          .fold<int>(0, (sum, entry) => sum + entry.count);
      if (needed <= 0) continue;
      final missing = needed - item.allocatedTo(deckStockTargetId(deck));
      if (missing > 0) needy.add((deck, missing));
    }
    if (needy.isEmpty || !mounted) return;

    needy.sort((a, b) => b.$2.compareTo(a.$2));
    final chosen = await showDialog<(Deck, int)>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('${card.nombre}: ¿asignar a un mazo?'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${needy.length == 1 ? 'Este mazo necesita' : '${needy.length} mazos necesitan'} '
                    'esta carta y tienes ${item.free} copia${item.free == 1 ? '' : 's'} libre${item.free == 1 ? '' : 's'}.',
                  ),
                  const SizedBox(height: 12),
                  for (final pair in needy)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(pair.$1.name),
                      subtitle: Text(
                        'Le faltan ${pair.$2} copia${pair.$2 == 1 ? '' : 's'}',
                      ),
                      trailing: FilledButton(
                        onPressed: () => Navigator.pop(context, pair),
                        child: const Text('Asignar'),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Ahora no'),
              ),
            ],
          ),
    );
    if (chosen == null || !mounted) return;
    final (deck, missing) = chosen;
    final assign = missing.clamp(0, item.free);
    try {
      await _service.setAllocation(
        item,
        deck,
        item.allocatedTo(deckStockTargetId(deck)) + assign,
      );
      if (mounted) {
        _snack(
          '$assign copia${assign == 1 ? '' : 's'} asignada${assign == 1 ? '' : 's'} a ${deck.name}.',
        );
      }
    } catch (error) {
      _snack('$error');
    }
  }

  Future<String?> _chooseVariant(CardMyL card) async {
    try {
      final snapshot =
          await FirebaseFirestore.instance
              .collection('cards')
              .doc(card.id)
              .collection('variants')
              .get();
      final variants =
          snapshot.docs
              .where((doc) => doc.data()['approved'] != false)
              .map((doc) => CardVariant.fromMap(doc.data(), doc.id))
              .toList()
            ..sort((a, b) => a.groupRank.compareTo(b.groupRank));
      if (!mounted) return null;
      return showDialog<String>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Elige la variación'),
              content: SizedBox(
                width: 460,
                height: 480,
                child: ListView(
                  children: [
                    ListTile(
                      leading: const SizedBox(
                        width: 52,
                        height: 72,
                        child: Icon(Icons.style_outlined),
                      ),
                      title: const Text('Normal / sin especificar'),
                      subtitle: const Text(
                        'Usará la imagen oficial de la carta',
                      ),
                      onTap: () => Navigator.pop(context, ''),
                    ),
                    ...variants.map(
                      (variant) => ListTile(
                        leading: MylCardImage(
                          url: variant.thumbUrl(),
                          width: 52,
                          height: 72,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        title: Text(variant.groupLabel),
                        subtitle:
                            variant.code == null ? null : Text(variant.code!),
                        onTap: () => Navigator.pop(context, variant.id),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
              ],
            ),
      );
    } catch (error) {
      _snack('No se pudieron cargar las variaciones: $error');
      return null;
    }
  }
}

class _QuickInventoryDialog extends StatefulWidget {
  final Map<String, InventoryItem> inventoryByCardId;

  const _QuickInventoryDialog({required this.inventoryByCardId});

  @override
  State<_QuickInventoryDialog> createState() => _QuickInventoryDialogState();
}

class _QuickInventoryDialogState extends State<_QuickInventoryDialog> {
  final _search = TextEditingController();
  final _service = CardService();
  final Map<String, (CardMyL, int)> _pending = {};
  final Map<String, String?> _selectedVariantByCardId = {};
  final Map<String, String> _variantLabelById = {};
  List<CardMyL> _results = const [];
  bool _loading = false;
  int _searchVersion = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String value) async {
    final version = ++_searchVersion;
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    final result = await _service.searchByNamePrefix(query, limit: 30);
    if (!mounted || version != _searchVersion) return;
    setState(() {
      _results = result;
      _loading = false;
    });
  }

  void _add(CardMyL card, int quantity) {
    setState(() {
      final current = _pending[card.id]?.$2 ?? 0;
      _pending[card.id] = (card, current + quantity);
    });
  }

  String? _variantFor(CardMyL card) {
    if (_selectedVariantByCardId.containsKey(card.id)) {
      final selected = _selectedVariantByCardId[card.id];
      return (selected ?? '').isEmpty ? null : selected;
    }
    return preferredVariantForQuickAdd(widget.inventoryByCardId[card.id]);
  }

  String _variantLabel(CardMyL card) {
    final variantId = _variantFor(card);
    if (variantId == null) return 'Sin variante identificada';
    return _variantLabelById[variantId] ?? 'Misma variante registrada';
  }

  Future<void> _chooseVariant(CardMyL card) async {
    final snapshot =
        await FirebaseFirestore.instance
            .collection('cards')
            .doc(card.id)
            .collection('variants')
            .get();
    final variants =
        snapshot.docs
            .where((doc) => doc.data()['approved'] != false)
            .map((doc) => CardVariant.fromMap(doc.data(), doc.id))
            .toList()
          ..sort((a, b) => a.groupRank.compareTo(b.groupRank));
    if (!mounted) return;
    final selected = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Variante de ${card.nombre}'),
            content: SizedBox(
              width: 440,
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: const Icon(Icons.help_outline),
                    title: const Text('Sin identificar'),
                    onTap: () => Navigator.pop(context, ''),
                  ),
                  for (final variant in variants)
                    ListTile(
                      leading: MylCardImage(
                        url: variant.thumbUrl(),
                        width: 42,
                        height: 58,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      title: Text(variant.groupLabel),
                      trailing:
                          widget.inventoryByCardId[card.id]?.variantTotals
                                      .containsKey(variant.id) ==
                                  true
                              ? const Icon(Icons.check_circle_outline)
                              : null,
                      onTap: () => Navigator.pop(context, variant.id),
                    ),
                ],
              ),
            ),
          ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedVariantByCardId[card.id] = selected;
      if (selected.isNotEmpty) {
        final variant =
            variants.where((item) => item.id == selected).firstOrNull;
        if (variant != null) {
          _variantLabelById[selected] = variant.groupLabel;
        }
      }
    });
  }

  void _remove(String cardId) {
    setState(() {
      final current = _pending[cardId];
      if (current == null) return;
      if (current.$2 <= 1) {
        _pending.remove(cardId);
      } else {
        _pending[cardId] = (current.$1, current.$2 - 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Carga rápida'),
    content: SizedBox(
      width: 620,
      height: 560,
      child: Column(
        children: [
          TextField(
            controller: _search,
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Busca, suma copias y continúa…',
            ),
            onChanged: _runSearch,
          ),
          if (_pending.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in _pending.values)
                    InputChip(
                      label: Text('${entry.$2}× ${entry.$1.nombre}'),
                      onDeleted: () => _remove(entry.$1.id),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child:
                _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _results.isEmpty
                    ? const Center(
                      child: Text(
                        'Escribe el nombre de una carta para comenzar.',
                      ),
                    )
                    : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final card = _results[index];
                        final quantity = _pending[card.id]?.$2 ?? 0;
                        return ListTile(
                          title: Text(card.nombre),
                          subtitle: Text(
                            '${card.edicion} · ${card.tipo}\n${_variantLabel(card)}',
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (quantity > 0) Text('$quantity'),
                              IconButton(
                                tooltip: 'Elegir variante',
                                onPressed: () => _chooseVariant(card),
                                icon: const Icon(Icons.style_outlined),
                              ),
                              TextButton(
                                onPressed: () => _add(card, 1),
                                child: const Text('+1'),
                              ),
                              TextButton(
                                onPressed: () => _add(card, 3),
                                child: const Text('+3'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
          ),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'La variante es opcional; puedes identificarla después.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed:
            _pending.isEmpty
                ? null
                : () => Navigator.pop(context, [
                  for (final entry in _pending.values)
                    InventoryBatchChange(
                      cardId: entry.$1.id,
                      name: entry.$1.nombre,
                      edition: entry.$1.edicion,
                      type: entry.$1.tipo,
                      quantity: entry.$2,
                      variantId: _variantFor(entry.$1),
                    ),
                ]),
        child: Text(
          'Agregar ${_pending.values.fold<int>(0, (a, b) => a + b.$2)}',
        ),
      ),
    ],
  );
}

class _CatalogCardDialog extends StatefulWidget {
  const _CatalogCardDialog();
  @override
  State<_CatalogCardDialog> createState() => _CatalogCardDialogState();
}

class _CatalogCardDialogState extends State<_CatalogCardDialog> {
  List<CardMyL> _results = const [];
  bool _loading = false;
  Future<void> _search(String value) async {
    if (value.trim().isEmpty) return setState(() => _results = const []);
    setState(() => _loading = true);
    final results = await CardService().searchByNamePrefix(value, limit: 30);
    if (mounted)
      setState(() {
        _results = results;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Agregar carta física'),
    content: SizedBox(
      width: 440,
      height: 420,
      child: Column(
        children: [
          TextField(
            autofocus: true,
            onChanged: _search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Nombre de la carta...',
            ),
          ),
          const SizedBox(height: 8),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (_, index) {
                final card = _results[index];
                return ListTile(
                  title: Text(card.nombre),
                  subtitle: Text('${card.edicion} · ${card.tipo}'),
                  onTap: () => Navigator.pop(context, card),
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
    ],
  );
}

class _VariantVisual {
  final String id;
  final String name;
  final String? url;
  const _VariantVisual({required this.id, required this.name, this.url});
}

class _BinderEntry {
  final InventoryItem item;
  final String? variantId;
  final String variantLabel;
  final int quantity;
  final String? imageUrl;
  // true cuando esta fila junta copias declaradas de [variantId] con copias
  // sin variante identificada que se asumen como la misma impresión (ver
  // _buildInventory).
  final bool includesUnidentified;
  int get free => item.freeForRow(
    variantId: variantId,
    includesUnidentified: includesUnidentified,
  );

  int get outsideDecks => item.outsideDecksForRow(
    variantId: variantId,
    includesUnidentified: includesUnidentified,
  );

  int get assigned {
    final unidentifiedAssigned = (item.assigned - item.variantAssignedTotal)
        .clamp(0, item.unidentified);
    if (variantId == null) return unidentifiedAssigned;
    final exact = item.variantAssigned(variantId!);
    return includesUnidentified ? exact + unidentifiedAssigned : exact;
  }

  const _BinderEntry({
    required this.item,
    this.variantId,
    required this.variantLabel,
    required this.quantity,
    this.imageUrl,
    this.includesUnidentified = false,
  });
}

class _BinderSection extends StatelessWidget {
  final String edition;
  final List<_BinderEntry> entries;
  final ValueChanged<_BinderEntry> onOpen;
  const _BinderSection({
    required this.edition,
    required this.entries,
    required this.onOpen,
  });
  int _columns(double width) {
    if (width >= 1100) return 7;
    if (width >= 760) return 5;
    if (width >= 480) return 4;
    return 3;
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.folder_rounded, color: Color(0xFFF1D48B)),
            const SizedBox(width: 8),
            Text(
              edition,
              style: const TextStyle(
                color: Color(0xFFF1D48B),
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${entries.length}',
              style: const TextStyle(color: Colors.white38),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = _columns(constraints.maxWidth);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: entries.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 9,
                mainAxisSpacing: 12,
                childAspectRatio: .59,
              ),
              itemBuilder:
                  (_, index) => _BinderCard(
                    entry: entries[index],
                    onTap: () => onOpen(entries[index]),
                  ),
            );
          },
        ),
      ],
    ),
  );
}

class _BinderCard extends StatelessWidget {
  final _BinderEntry entry;
  final VoidCallback onTap;
  const _BinderCard({required this.entry, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: 'inventory:${entry.item.key}:${entry.variantId ?? 'base'}',
                child: MylCardImage(
                  url: entry.imageUrl,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              Positioned(top: 5, left: 5, child: _CountBadge(entry.quantity)),
            ],
          ),
        ),
        const SizedBox(height: 5),
        Text(
          entry.item.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          entry.variantLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFFF1D48B), fontSize: 9),
        ),
      ],
    ),
  );
}

class _CountBadge extends StatelessWidget {
  final int count;
  const _CountBadge(this.count);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFF1D48B)),
    ),
    child: Text(
      'x$count',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _BinderDetails extends StatelessWidget {
  final _BinderEntry entry;
  final List<Deck> decks;
  final VoidCallback onEdit;
  const _BinderDetails({
    required this.entry,
    required this.decks,
    required this.onEdit,
  });

  /// Mazos que usan esta carta y cuántas copias pide cada uno.
  List<(Deck, int)> get _usedIn => [
    for (final deck in decks)
      if (deck.cards
              .where((card) => entryInventoryKey(card) == entry.item.key)
              .fold<int>(0, (sum, card) => sum + card.count)
          case final needed when needed > 0)
        (deck, needed),
  ];
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: SizedBox(
              width: 220,
              height: 308,
              child: MylCardImage(
                url: entry.imageUrl,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            entry.item.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            '${entry.variantLabel} · ${entry.item.edition ?? 'Sin edición'}',
            style: const TextStyle(color: Color(0xFFF1D48B)),
          ),
          const SizedBox(height: 12),
          _MetricChip('Tienes ${entry.item.total}'),
          if (_usedIn.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text(
              'Usada en',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            for (final (deck, needed) in _usedIn)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  entry.item.total >= needed
                      ? Icons.check_circle
                      : Icons.remove_circle_outline,
                  color:
                      entry.item.total >= needed
                          ? Colors.greenAccent
                          : Colors.orangeAccent,
                ),
                title: Text(
                  deck.name,
                  style: const TextStyle(color: Colors.white70),
                ),
                trailing: Text(
                  'pide x$needed',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Cambiar cantidad'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _MetricChip extends StatelessWidget {
  final String label;
  const _MetricChip(this.label);
  @override
  Widget build(BuildContext context) => Chip(
    label: Text(label),
    backgroundColor: const Color(0xFF252A35),
    labelStyle: const TextStyle(color: Colors.white70),
  );
}

InputDecoration _inputDecoration(String hint, IconData icon) => InputDecoration(
  hintText: hint,
  hintStyle: const TextStyle(color: Colors.white38),
  prefixIcon: Icon(icon, color: Colors.white38),
  filled: true,
  fillColor: const Color(0xFF171A22),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide.none,
  ),
);

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF171A22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFF1D48B),
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    ),
  );
}

class _FilterDropdown extends StatelessWidget {
  final String hint;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  const _FilterDropdown({
    required this.hint,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF171A22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: value != null ? const Color(0xFFF1D48B) : Colors.white10,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: value,
          isExpanded: true,
          isDense: true,
          dropdownColor: const Color(0xFF1A212C),
          hint: Text(hint, style: const TextStyle(color: Colors.white38)),
          icon: const Icon(Icons.arrow_drop_down, color: Colors.white38),
          style: TextStyle(
            color: value != null ? const Color(0xFFF1D48B) : Colors.white,
            fontSize: 13,
          ),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(
                'Todos ($hint)',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
            for (final option in options)
              DropdownMenuItem<String?>(value: option, child: Text(option)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _MissingCollectionView extends StatelessWidget {
  final List<CollectionShortage> shortages;
  final Map<String, String?> imageByCardId;
  final String query;
  final String? typeFilter;
  final String? editionFilter;

  const _MissingCollectionView({
    required this.shortages,
    required this.imageByCardId,
    required this.query,
    this.typeFilter,
    this.editionFilter,
  });

  @override
  Widget build(BuildContext context) {
    final missing =
        shortages
            .where(
              (entry) =>
                  query.isEmpty ||
                  normalizeSearch(
                    '${entry.cardName} ${entry.edition ?? ''}',
                  ).contains(query),
            )
            .where(
              (entry) =>
                  typeFilter == null || (entry.type ?? '').trim() == typeFilter,
            )
            .where(
              (entry) =>
                  editionFilter == null ||
                  (entry.edition ?? '').trim() == editionFilter,
            )
            .toList();
    if (missing.isEmpty) {
      return const _EmptyState(
        icon: Icons.check_circle_outline,
        text: 'No hay faltantes en tus mazos activos.',
      );
    }
    final byEdition =
        <String, Map<String, Map<String, List<CollectionShortage>>>>{};
    for (final entry in missing) {
      byEdition
          .putIfAbsent(
            entry.deckEdition,
            () => <String, Map<String, List<CollectionShortage>>>{},
          )
          .putIfAbsent(
            entry.deckRace,
            () => <String, List<CollectionShortage>>{},
          )
          .putIfAbsent(entry.deckName, () => <CollectionShortage>[])
          .add(entry);
    }
    final editions =
        byEdition.keys.toList()..sort((a, b) {
          final rank = _missingEditionRank(a).compareTo(_missingEditionRank(b));
          return rank != 0 ? rank : a.toLowerCase().compareTo(b.toLowerCase());
        });

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
      children: [
        for (final edition in editions) ...[
          _MissingSectionHeader(
            label: edition,
            icon: Icons.collections_bookmark,
          ),
          for (final race
              in (byEdition[edition]!.keys.toList()..sort(
                (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
              ))) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 14, 8, 7),
              child: Row(
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    size: 16,
                    color: Color(0xFFF1D48B),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    race,
                    style: const TextStyle(
                      color: Color(0xFFF1D48B),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            for (final deckName
                in (byEdition[edition]![race]!.keys.toList()
                  ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()))))
              _MissingDeckGroup(
                deckName: deckName,
                entries: byEdition[edition]![race]![deckName]!,
                imageByCardId: imageByCardId,
              ),
          ],
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  static int _missingEditionRank(String edition) {
    final normalized = normalizeSearch(edition);
    if (normalized.contains('espada')) return 0;
    if (normalized.contains('helen')) return 1;
    if (normalized.contains('daana')) return 2;
    if (normalized.contains('dominio') || normalized == 'ra') return 3;
    if (normalized.contains('racial libre')) return 4;
    if (normalized.contains('full')) return 5;
    return 6;
  }
}

class _MissingSectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;

  const _MissingSectionHeader({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
    decoration: BoxDecoration(
      color: const Color(0xFF20242E),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white12),
    ),
    child: Row(
      children: [
        Icon(icon, size: 19, color: Colors.white70),
        const SizedBox(width: 9),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _MissingDeckGroup extends StatelessWidget {
  final String deckName;
  final List<CollectionShortage> entries;
  final Map<String, String?> imageByCardId;

  const _MissingDeckGroup({
    required this.deckName,
    required this.entries,
    required this.imageByCardId,
  });

  @override
  Widget build(BuildContext context) {
    final deck = entries.first;
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF151820),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap:
                () => context.push(
                  '/mazo/${Uri.encodeComponent(deck.deckOwnerId)}/${Uri.encodeComponent(deck.deckId)}',
                ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.style_outlined, size: 17),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      deckName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const Text(
                    'Abrir mazo',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const SizedBox(width: 5),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          for (var index = 0; index < entries.length; index++) ...[
            _MissingCardRow(
              entry: entries[index],
              imageUrl: imageByCardId[entries[index].cardId],
            ),
            if (index != entries.length - 1)
              const Divider(height: 1, indent: 76),
          ],
        ],
      ),
    );
  }
}

class _MissingCardRow extends StatelessWidget {
  final CollectionShortage entry;
  final String? imageUrl;

  const _MissingCardRow({required this.entry, this.imageUrl});

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    leading: SizedBox(
      width: 52,
      height: 72,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: MylCardImage(
              url: imageUrl,
              fit: BoxFit.cover,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          Positioned(right: -6, top: -6, child: _CountBadge(entry.quantity)),
        ],
      ),
    ),
    title: Text(entry.cardName),
    subtitle: Text('Faltan ${entry.quantity}'),
  );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyState({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 52, color: Colors.white24),
        const SizedBox(height: 10),
        Text(text, style: const TextStyle(color: Colors.white54)),
      ],
    ),
  );
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState(this.message);
  @override
  Widget build(BuildContext context) => Center(
    child: Text(message, style: const TextStyle(color: Color(0xFFFF7777))),
  );
}
