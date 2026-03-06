import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import './compare_decks_screen.dart';
import '../../models/deck.dart';
import '../../models/card_myl.dart';
import '../../services/deck_service.dart';
import './create_deck_screen.dart';
import './deck_details_screen.dart';
import './deck_diff_dialog.dart';
import './overall_completeness.dart';

/// Pareja Tengo/Objetivo para pintar filas
class _DeckPair {
  Deck? tengo;
  Deck? objetivo;
}

// helper utilitario para mostrar nombres bonitos de carta (capitaliza palabras)
String prettyCardName(String s) {
  final str = s.trim();
  if (str.isEmpty) return str;
  final parts = str.split(RegExp(r'\s+'));
  return parts.map((p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}').join(' ');
}

/// Contenedor de datos globales de faltantes
class _GlobalMissingData {
  final Map<String, int> globalMissing; // cardName -> total faltante
  final Map<String, Map<String, int>> donorsPerCard; // cardName -> {donorLabel: qty}
  final Map<String, List<String>> perCardTargets; // cardName -> ["ObjetivoName (qty)", ...]

  _GlobalMissingData({
    required this.globalMissing,
    required this.donorsPerCard,
    required this.perCardTargets,
  });
}

class MyDecksScreen extends StatefulWidget {
  final bool showTargets; // controla si se muestran "Objetivo"

  const MyDecksScreen({super.key, this.showTargets = true});

  @override
  State<MyDecksScreen> createState() => _MyDecksScreenState();
}

class _MyDecksScreenState extends State<MyDecksScreen> {
  late final DeckService _deckService;
  bool _compareMode = false;
  final Set<String> _selected = {};
  List<Deck> _currentDecks = [];
  final Map<String, bool> _expandedEditions = {};
  Map<String, CardMyL> _cardsById = {};
  Map<String, CardMyL> _cardsByNameLower = {};

  // NUEVO: controlador de scroll para que no "salte" al tope
  final ScrollController _scrollCtrl = ScrollController();

  // flag que decide si mostramos objetivos (inicializado desde widget o desde Firestore)
  late bool _showTargets;

  @override
  void initState() {
    super.initState();
    _showTargets = widget.showTargets; // default desde constructor

    final uid = FirebaseAuth.instance.currentUser!.uid;
    _deckService = DeckService(uid);
    _loadCardsCatalog();

    // detección automática de rol (opcional):
    _maybeDetectRoleAndAdjust(uid);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _maybeDetectRoleAndAdjust(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data();
      if (data != null) {
        final role = (data['role'] ?? data['rol'] ?? '').toString().toLowerCase();
        if (role == 'basico' || role == 'lector') {
          if (mounted) setState(() => _showTargets = false);
        } else {
          if (mounted) setState(() => _showTargets = true);
        }
      }
    } catch (_) {
      // fall back: no cambiar _showTargets
    }
  }

  Future<void> _loadCardsCatalog() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('cards').get();
      final mById = <String, CardMyL>{};
      final mByName = <String, CardMyL>{};

      for (final d in snap.docs) {
        final card = CardMyL.fromMap(d.data(), d.id);
        mById[d.id] = card;
        mByName[card.nombre.toLowerCase()] = card;
      }

      if (mounted) {
        setState(() {
          _cardsById = mById;
          _cardsByNameLower = mByName;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _cardsById = {};
          _cardsByNameLower = {};
        });
      }
    }
  }

  Future<void> _createNewDeck() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateDeckScreen()),
    );
  }

  Future<void> _openDeckDetails(Deck deck) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DeckDetailsScreen(deck: deck)),
    );
  }

  Future<void> _editDeck(Deck deck) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CreateDeckScreen(editDeck: deck)),
    );
  }

  void _toggleCompareMode() {
    setState(() {
      _compareMode = !_compareMode;
      if (!_compareMode) _selected.clear();
    });
  }

  void _toggleSelection(String deckId) {
    setState(() {
      if (_selected.contains(deckId)) {
        _selected.remove(deckId);
      } else {
        _selected.add(deckId);
      }
    });
  }

  // Abrir comparar leyendo feature->grupo desde Firestore
  void _openCompare(List<Deck> decks, List<String> ids) async {
    final chosen = decks.where((d) => ids.contains(d.id)).toList();
    if (chosen.length < 2) return;

    try {
      final snap = await FirebaseFirestore.instance.collection('card_custom_features').get();
      final Map<String, String> featureGroupMap = {};

      for (final doc in snap.docs) {
        final data = doc.data();
        final rawName = (data['name'] ?? data['nombre'] ?? '').toString().trim();
        if (rawName.isEmpty) continue;

        final rawGroup = (data['group'] ??
                data['groupName'] ??
                data['grupo'] ??
                data['group_name'] ??
                '')
            .toString()
            .trim();

        if (rawGroup.isEmpty) {
          continue; // quedará en "Otros"
        }

        // varias formas de la key para robustez
        featureGroupMap[rawName] = rawGroup;
        featureGroupMap[rawName.toLowerCase()] = rawGroup;

        final normalized = (data['normalized'] ?? data['name_normalized'] ?? '').toString().trim();
        if (normalized.isNotEmpty) {
          featureGroupMap[normalized] = rawGroup;
          featureGroupMap[normalized.toLowerCase()] = rawGroup;
        }
      }

      debugPrint('[MyDecks] featureGroupMap size: ${featureGroupMap.length}');

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CompareDecksScreen(
            decks: chosen,
            cardsById: _cardsById,
            cardsByNameLower: _cardsByNameLower,
            featureGroupMap: featureGroupMap,
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('[MyDecks] error building featureGroupMap: $e\n$st');
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CompareDecksScreen(
            decks: chosen,
            cardsById: _cardsById,
            cardsByNameLower: _cardsByNameLower,
            featureGroupMap: const {},
          ),
        ),
      );
    }
  }

  Future<bool> _confirmDuplicate(Deck d) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Duplicar mazo'),
        content: Text('¿Quieres duplicar "${d.name.isEmpty ? 'Mazo sin nombre' : d.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Duplicar'),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  // --- Agrupar por edición
  Map<String, List<Deck>> _groupByEdition(List<Deck> decks) {
    final map = <String, List<Deck>>{};
    for (final d in decks) {
      final key = (d.edition ?? 'Sin edición').trim();
      map.putIfAbsent(key, () => []).add(d);
    }
    return map;
  }

  // --- Parear por link primero, y si no, por nombre+edición
  List<_DeckPair> _pairByLinkOrName(List<Deck> list) {
    final targetById = <String, Deck>{
      for (final d in list.where((e) => e.isTarget)) d.id: d,
    };

    final map = <String, _DeckPair>{};

    for (final d in list) {
      if (d.isTarget) {
        final key = 'obj:${d.id}';
        final pair = map.putIfAbsent(key, () => _DeckPair());
        pair.objetivo = d;
        continue;
      }

      final linked = (d.linkedDeckId ?? '').trim();

      if (linked.isNotEmpty) {
        final key = 'obj:$linked';
        final pair = map.putIfAbsent(key, () => _DeckPair());
        pair.tengo = d;
        pair.objetivo ??= targetById[linked];
        continue;
      }

      final key = 'name:${d.name.toLowerCase()}|ed:${(d.edition ?? '').toLowerCase()}';
      final pair = map.putIfAbsent(key, () => _DeckPair());
      pair.tengo = d;
    }

    return map.values.toList();
  }

  // ---------------------------
  // Helper: cuenta cartas del mazo
  // ---------------------------
  int _totalCardsInDeck(Deck d) {
    try {
      int total = 0;
      for (final c in d.cards) {
        total += c.count;
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Widget _buildPairCard(_DeckPair p) {
    final tengo = p.tengo;
    final objetivo = p.objetivo;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 520;

        final Widget leftTile = _compactDeckTile(
          deck: tengo,
          label: "Tengo",
          compareMode: _compareMode,
          isSelected: tengo != null && _selected.contains(tengo.id),
          onToggleSelect: tengo != null ? () => _toggleSelection(tengo.id) : null,
          onOpen: tengo != null ? () => _openDeckDetails(tengo) : null,
          onEdit: tengo != null ? () => _editDeck(tengo) : null,
          onDuplicate: tengo != null
              ? () async {
                  final ok = await _confirmDuplicate(tengo);
                  if (ok) await _deck_service_duplicate(tengo.id);
                }
              : null,
          cardCount: tengo != null ? _totalCardsInDeck(tengo) : 0,
        );

        final Widget rightTile = _compactDeckTile(
          deck: objetivo,
          label: "Objetivo",
          compareMode: _compareMode,
          isSelected: objetivo != null && _selected.contains(objetivo.id),
          onToggleSelect: objetivo != null ? () => _toggleSelection(objetivo.id) : null,
          onOpen: objetivo != null ? () => _openDeckDetails(objetivo) : null,
          onEdit: objetivo != null ? () => _editDeck(objetivo) : null,
          onDuplicate: objetivo != null
              ? () async {
                  final ok = await _confirmDuplicate(objetivo);
                  if (ok) await _deck_service_duplicate(objetivo.id);
                }
              : null,
          cardCount: objetivo != null ? _totalCardsInDeck(objetivo) : 0,
        );

        final infoBtn = (tengo != null && objetivo != null)
            ? IconButton(
                icon: const Icon(Icons.info_outline),
                tooltip: "Ver diferencias (y plan de préstamos con números)",
                onPressed: () => showDeckDiffDialog(context, tengo, objetivo, _currentDecks),
              )
            : const SizedBox.shrink();

        if (isNarrow) {
          // apilado vertical para móviles
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  leftTile,
                  const Divider(height: 10),
                  rightTile,
                  if (tengo != null && objetivo != null)
                    Align(alignment: Alignment.centerRight, child: infoBtn),
                ],
              ),
            ),
          );
        }

        // horizontal para pantallas anchas
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Expanded(child: leftTile),
              Expanded(child: rightTile),
              if (tengo != null && objetivo != null) infoBtn,
            ],
          ),
        );
      },
    );
  }

  // versión compacta y con padding controlado de _DeckTile para usar internamente
  Widget _compactDeckTile({
    required Deck? deck,
    required String label,
    required bool compareMode,
    required bool isSelected,
    required VoidCallback? onToggleSelect,
    required VoidCallback? onOpen,
    required VoidCallback? onEdit,
    required VoidCallback? onDuplicate,
    required int cardCount,
  }) {
    if (deck == null) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text("$label: (no definido)"),
      );
    }

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      minLeadingWidth: 24,
      leading: const Icon(Icons.layers, size: 20),
      title: Text(
        deck.name.isEmpty ? "Mazo sin nombre" : deck.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('$label • $cardCount/50', maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: compareMode ? onToggleSelect : onOpen,
      trailing: compareMode
          ? Checkbox(value: isSelected, onChanged: (_) => onToggleSelect?.call())
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: onDuplicate,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  padding: const EdgeInsets.all(8),
                  tooltip: 'Duplicar',
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: onEdit,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  padding: const EdgeInsets.all(8),
                  tooltip: 'Editar',
                ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis mazos'),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.secondary,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Estado general de completitud (%)',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showOverallCompletenessDialog(context, _currentDecks),
          ),

          // Botones de comparar solo si _showTargets == true
          if (_showTargets) ...[
            IconButton(
              tooltip: _compareMode ? 'Salir de comparar' : 'Comparar mazos',
              icon: Icon(_compareMode ? Icons.checklist_rtl : Icons.compare_arrows_rounded),
              onPressed: _toggleCompareMode,
            ),
            
          ],
        ],
      ),
      floatingActionButton: _showTargets && _compareMode
          ? FloatingActionButton.extended(
              onPressed: () {
                if (_selected.length < 2) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Selecciona al menos 2 mazos para comparar')),
                  );
                  return;
                }
                _openCompare(_currentDecks, _selected.toList());
              },
              icon: const Icon(Icons.compare_arrows_rounded),
              label: Text('Comparar (${_selected.length})'),
            )
          : null,
      body: StreamBuilder<List<Deck>>(
        stream: _deckService.watchMyDecks(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final decks = snap.data ?? const <Deck>[];
          _currentDecks = decks;

          if (decks.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.collections_bookmark_outlined, size: 48),
                    const SizedBox(height: 8),
                    const Text('Aún no tienes mazos.'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _createNewDeck,
                      icon: const Icon(Icons.add),
                      label: const Text('Crear mi primer mazo'),
                    ),
                  ],
                ),
              ),
            );
          }

          final grouped = _groupByEdition(decks);

          return ListView(
            key: const PageStorageKey('myDecksList'),
            controller: _scrollCtrl,
            padding: const EdgeInsets.only(bottom: 88),
            children: grouped.entries.map<Widget>((entry) {
              final edition = entry.key;
              final list = entry.value;

              if (!_showTargets) {
                // Vista simplificada: solo "Tengo" (no isTarget)
                final tengoDecks = list.where((d) => !(d.isTarget)).toList();
                return ExpansionTile(
                  key: PageStorageKey<String>('edition_$edition'),
                  maintainState: true,
                  initiallyExpanded: _expandedEditions[edition] ?? false,
                  onExpansionChanged: (open) => setState(() {
                    _expandedEditions[edition] = open;
                  }),
                  title: Text(
                    "$edition : ${tengoDecks.length} mazos",
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  children: tengoDecks.map<Widget>((d) {
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: _compactDeckTile(
                        deck: d,
                        label: "Tengo",
                        compareMode: _compareMode,
                        isSelected: _selected.contains(d.id),
                        onToggleSelect: () => _toggleSelection(d.id),
                        onOpen: () => _openDeckDetails(d),
                        onEdit: () => _editDeck(d),
                        onDuplicate: () async {
                          final ok = await _confirmDuplicate(d);
                          if (ok) await _deck_service_duplicate(d.id);
                        },
                        cardCount: _totalCardsInDeck(d),
                      ),
                    );
                  }).toList(),
                );
              }

              // Vista con objetivos: pareo Tengo<->Objetivo
              final List<_DeckPair> pairs = _pairByLinkOrName(list);
              final editionTitle = "$edition : ${list.where((d) => !(d.isTarget)).length} mazos";

              return ExpansionTile(
                key: PageStorageKey<String>('edition_$edition'),
                maintainState: true,
                initiallyExpanded: _expandedEditions[edition] ?? false,
                onExpansionChanged: (open) => setState(() {
                  _expandedEditions[edition] = open;
                }),
                title: Text(
                  editionTitle,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                children: pairs.map<Widget>((p) => _buildPairCard(p)).toList(),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  // pequeño helper para duplicar vía servicio
  Future<void> _deck_service_duplicate(String id) async {
    await _deckService.duplicate(id);
  }
}

/// Pantalla que muestra todas las cartas faltantes (desde el botón del diálogo)
class AllMissingCardsScreen extends StatelessWidget {
  final _GlobalMissingData data;
  const AllMissingCardsScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final entries = data.globalMissing.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value)); // mayor faltante primero

    return Scaffold(
      appBar: AppBar(
        title: const Text('Todas las cartas faltantes'),
      ),
      body: entries.isEmpty
          ? const Center(child: Text('No hay cartas faltantes.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: entries.length,
              itemBuilder: (context, idx) {
                final e = entries[idx];
                final card = e.key;
                final totalQty = e.value;
                final donorsMap = data.donorsPerCard[card] ?? {};
                final totalAportable = donorsMap.values.fold<int>(0, (p, n) => p + n);
                final donorsList =
                    donorsMap.entries.map((d) => '${d.key} (${d.value})').join(', ');
                final targets = (data.perCardTargets[card] ?? []).join(' — ');

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${prettyCardName(card)} — Faltan: $totalQty',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Text('Aportable: $totalAportable'),
                        if (donorsList.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6.0),
                            child: Text('Donantes: $donorsList',
                                style: const TextStyle(fontSize: 13)),
                          ),
                        if (targets.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6.0),
                            child: Text('Objetivos: $targets',
                                style: const TextStyle(fontSize: 13)),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
