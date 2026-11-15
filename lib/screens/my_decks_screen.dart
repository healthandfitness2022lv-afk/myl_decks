import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/perfil_habilidades.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../domain/deck_coverage.dart';
import '../domain/deck_stock_groups.dart';
import '../domain/inventory_keys.dart';
import '../domain/validation/deck_validator.dart';
import '../models/card_myl.dart';
import '../models/card_variant.dart';
import '../models/deck.dart';
import '../models/inventory.dart';
import '../services/ban_list_service.dart';
import '../services/deck_service.dart';
import '../services/deck_v2_migration_service.dart';
import '../services/inventory_service.dart';
import '../services/wishlist_service.dart';
import '../widgets/card_image.dart';
import 'create_deck_screen.dart';
import 'simulador/simulador_screen.dart';
import '../utils/app_constants.dart';

class MyDecksScreen extends StatefulWidget {
  // Se conserva para no romper rutas antiguas. En v2 siempre hay una lista.
  final bool showTargets;
  const MyDecksScreen({super.key, this.showTargets = true});

  @override
  State<MyDecksScreen> createState() => _MyDecksScreenState();
}

class _MyDecksScreenState extends State<MyDecksScreen> {
  late final String _uid;
  late final DeckService _decks;
  late final InventoryService _inventory;
  Map<String, CardMyL> _catalogByName = const {};
  Map<String, CardMyL> _catalogById = const {};
  final Map<DeckFormat, Map<String, int>> _copyLimitsByFormat = {};
  final Set<DeckFormat> _loadedBanFormats = {};
  bool _showFreeFormats = false;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser!.uid;
    _decks = DeckService(_uid);
    _inventory = InventoryService(_uid);
    _loadCatalog();
    _loadBanLists();
  }

  Future<void> _loadBanLists() async {
    final services = <DeckFormat, BanListService>{
      DeckFormat.racial: BanListService(),
      DeckFormat.racialLibre: BanListService.racialLibre(),
      DeckFormat.full: BanListService.full(),
    };
    await Future.wait(
      services.entries.map((entry) async {
        try {
          final limits = await entry.value.fetchCopyLimitsByKey();
          if (!mounted) return;
          setState(() {
            _copyLimitsByFormat[entry.key] = limits;
            _loadedBanFormats.add(entry.key);
          });
        } catch (_) {
          // Sin datos no se afirma que el mazo sea legal.
        }
      }),
    );
  }

  Future<void> _loadCatalog() async {
    final snapshot = await FirebaseFirestore.instance.collection('cards').get();
    if (!mounted) return;
    final cards = snapshot.docs.map((doc) => CardMyL.fromDoc(doc)).toList();
    setState(() {
      _catalogById = {for (final card in cards) card.id: card};
      _catalogByName = {
        for (final card in cards) card.nombre.trim().toLowerCase(): card,
      };
    });
  }

  List<Deck> _ordered(List<Deck> decks) =>
      [...decks]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  String _editionGroup(Deck deck) {
    if (deck.format == DeckFormat.full ||
        deck.format == DeckFormat.racialLibre) {
      return 'formatos_libres';
    }
    final edition = (deck.edition ?? '').trim().toLowerCase();
    if (edition.contains('espada')) return 'espada';
    if (edition.contains('helen')) return 'helenica';
    if (edition.contains('daana')) return 'daana';
    if (edition.contains('dominio') || edition == 'ra') return 'ra';
    return 'otra:$edition';
  }

  String _editionGroupLabel(String key, List<Deck> decks) => switch (key) {
    'espada' => 'Espada Sagrada',
    'helenica' => 'Helénica',
    'daana' => 'Hijos de Daana',
    'ra' => 'Dominios de Ra',
    'racial_libre' => 'Racial Libre',
    'full' => 'Formato Full',
    'formatos_libres' => 'Racial Libre y Formato Full',
    _ =>
      (decks.first.edition ?? '').trim().isEmpty
          ? 'Sin edición'
          : decks.first.edition!.trim(),
  };

  Map<String, List<Deck>> _groupDecks(List<Deck> decks) {
    final grouped = <String, List<Deck>>{
      'espada': [],
      'helenica': [],
      'daana': [],
      'ra': [],
    };
    for (final deck in decks) {
      grouped.putIfAbsent(_editionGroup(deck), () => []).add(deck);
    }
    final free = grouped.remove('formatos_libres') ?? <Deck>[];
    grouped.removeWhere((_, values) => values.isEmpty);
    if (free.isNotEmpty) grouped['formatos_libres'] = free;
    return grouped;
  }

  String? _coverFor(Deck deck) {
    final explicit = deck.coverUrl?.trim() ?? '';
    if (explicit.isNotEmpty) return explicit;
    final coverCard = _catalogById[deck.coverCardId];
    final coverVariant = coverCard?.bestVariant?.imageFrontUrl?.trim() ?? '';
    if (coverVariant.isNotEmpty) return coverVariant;
    for (final entry in deck.cards) {
      final card = entry.cardId == null ? null : _catalogById[entry.cardId];
      final image = card?.bestVariant?.imageFrontUrl?.trim() ?? '';
      if (image.isNotEmpty) return image;
    }
    return null;
  }

  String? _imageForCard(DeckCardEntry entry, String? variantId) {
    final card = entry.cardId == null ? null : _catalogById[entry.cardId];
    CardVariant? variant;
    if (variantId != null && card != null) {
      for (final candidate in card.variantes) {
        if (candidate.id == variantId) {
          variant = candidate;
          break;
        }
      }
    }
    final image =
        (variant?.imageFrontUrl ?? card?.bestVariant?.imageFrontUrl)?.trim() ??
        '';
    return image.isEmpty ? null : image;
  }

  Future<void> _delete(Deck deck) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Eliminar mazo'),
            content: Text(
              'Se eliminará la configuración "${deck.name}" y sus copias volverán a Mi carpeta.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    try {
      await _decks.delete(deck.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Mazo "${deck.name}" eliminado.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo eliminar: $e')));
    }
  }

  Future<void> _importDeck() async {
    final name = TextEditingController(text: 'Mazo importado');
    final list = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Importar configuración'),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: list,
                    minLines: 8,
                    maxLines: 14,
                    decoration: const InputDecoration(
                      hintText: '3x Guerrero Bereber\n2 Ramsés II',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Importar'),
              ),
            ],
          ),
    );
    final deckName = name.text.trim();
    final raw = list.text;
    name.dispose();
    list.dispose();
    if (accepted != true || raw.trim().isEmpty) return;

    final counts = <String, int>{};
    final labels = <String, String>{};
    final pattern = RegExp(r'^\s*(?:x?(\d+)x?\s+)?(.+?)\s*$');
    for (final line in raw.split('\n')) {
      final match = pattern.firstMatch(line);
      if (match == null) continue;
      final label = (match.group(2) ?? '').trim();
      if (label.isEmpty) continue;
      final key = label.toLowerCase();
      counts[key] =
          (counts[key] ?? 0) + (int.tryParse(match.group(1) ?? '') ?? 1);
      labels[key] = label;
    }
    final entries =
        counts.entries.map((value) {
          final card = _catalogByName[value.key];
          return DeckCardEntry(
            cardId: card?.id,
            name: card?.nombre ?? labels[value.key]!,
            count: value.value,
            coste: card?.coste,
            tipo: card?.tipo,
            rareza: card?.rareza,
            edicion: card?.edicion,
            unica: card?.unica ?? false,
            soloLibre: card?.soloLibre ?? false,
          );
        }).toList();
    final id = await _decks.create(
      deckName.isEmpty ? 'Mazo importado' : deckName,
    );
    final created = await _decks.getById(id);
    if (created != null) await _decks.save(created.copyWith(cards: entries));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Volver al inicio',
          onPressed: () => context.go('/'),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Mis Mazos'),
        actions: [
          IconButton(
            tooltip: 'Importar configuración',
            onPressed: _importDeck,
            icon: const Icon(Icons.file_download_outlined),
          ),
          IconButton(
            tooltip: 'Mi carpeta',
            onPressed: () => context.push('/inventario'),
            icon: const Icon(Icons.folder_copy_outlined),
          ),
          if ((FirebaseAuth.instance.currentUser?.email ?? '').toLowerCase() ==
              AppConstants.ownerEmail)
            IconButton(
              tooltip: 'Simulador de partidas',
              onPressed:
                  () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SimuladorScreen()),
                  ),
              icon: const Icon(Icons.sports_esports_outlined),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/mazos/nuevo'),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo mazo'),
      ),
      body: StreamBuilder<List<Deck>>(
        stream: _decks.watchMyDecks(),
        builder: (context, deckSnapshot) {
          if (deckSnapshot.hasError) {
            return Center(
              child: Text('No se pudieron cargar: ${deckSnapshot.error}'),
            );
          }
          if (!deckSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return StreamBuilder<List<InventoryItem>>(
            stream: _inventory.watchInventory(),
            builder: (context, inventorySnapshot) {
              if (!inventorySnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final decks = _ordered(deckSnapshot.data!);
              final racialDecks =
                  decks
                      .where((deck) => deck.format == DeckFormat.racial)
                      .toList();
              final racialLibreDecks =
                  decks
                      .where((deck) => deck.format == DeckFormat.racialLibre)
                      .toList();
              final fullDecks =
                  decks
                      .where((deck) => deck.format == DeckFormat.full)
                      .toList();
              final visibleDecks =
                  _showFreeFormats
                      ? [...racialLibreDecks, ...fullDecks]
                      : racialDecks;
              final groupedRacialDecks = _groupDecks(racialDecks);
              final groupedDecks =
                  _showFreeFormats
                      ? <String, List<Deck>>{
                        if (racialLibreDecks.isNotEmpty)
                          'racial_libre': racialLibreDecks,
                        if (fullDecks.isNotEmpty) 'full': fullDecks,
                      }
                      : groupedRacialDecks;
              final stockTargets = deckStockTargetsById(decks);
              // El orden ya no es un ranking editable por el usuario: se usa
              // solo para sanear asignaciones legado inconsistentes de forma
              // determinista (ver inventoryCappedByDeckPriority).
              final effectiveInventory = inventoryCappedByDeckPriority(
                inventory: inventorySnapshot.data!,
                orderedDecks: decks,
              );
              final coverageByDeckId = <String, DeckCoverage>{
                for (final deck in decks)
                  deck.id: calculateDeckCoverage(
                    deck: deck,
                    inventory: effectiveInventory,
                  ),
              };
              final legacy = decks.where((deck) => !deck.isUnified).length;
              return Column(
                children: [
                  if (legacy > 0)
                    _MigrationBanner(
                      count: legacy,
                      onTap:
                          () => showDialog<void>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => _MigrationDialog(uid: _uid),
                          ),
                    ),
                  if (decks.isNotEmpty)
                    _DeckFormatSwitch(
                      showFreeFormats: _showFreeFormats,
                      onChanged:
                          (value) => setState(() => _showFreeFormats = value),
                    ),
                  if (visibleDecks.isNotEmpty && !_showFreeFormats)
                    _DecksKpiSummary(
                      decks: visibleDecks,
                      coverageByDeckId: coverageByDeckId,
                      inventory: effectiveInventory,
                    ),
                  if (visibleDecks.isNotEmpty && _showFreeFormats)
                    const _OptionalFormatsNotice(),
                  Expanded(
                    child:
                        visibleDecks.isEmpty
                            ? const Center(
                              child: Text(
                                'Crea tu primera configuración de mazo.',
                              ),
                            )
                            : ListView(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                              children: [
                                for (final groupEntry
                                    in groupedDecks.entries) ...[
                                  _DeckGroupHeader(
                                    title: _editionGroupLabel(
                                      groupEntry.key,
                                      groupEntry.value,
                                    ),
                                    count: groupEntry.value.length,
                                    isFreeFormats: _showFreeFormats,
                                  ),
                                  if (groupEntry.key == 'full')
                                    Wrap(
                                      spacing: 14,
                                      runSpacing: 14,
                                      children: [
                                        for (final deck in groupEntry.value)
                                          _buildDeckCard(
                                            deck,
                                            coverageByDeckId,
                                            stockTargets,
                                          ),
                                      ],
                                    )
                                  else
                                    SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          for (final raceEntry
                                              in _groupByRace(
                                                groupEntry.value,
                                              ).entries)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                right: 22,
                                              ),
                                              child: SizedBox(
                                                width: 220,
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    _RaceFamilyHeader(
                                                      race: raceEntry.key,
                                                      onTap:
                                                          () => _openRaceDecks(
                                                            raceEntry.key,
                                                            raceEntry.value,
                                                            coverageByDeckId,
                                                          ),
                                                    ),
                                                    _RaceDeckCollageCard(
                                                      coverUrls: [
                                                        for (final deck
                                                            in raceEntry.value)
                                                          _coverFor(deck),
                                                      ],
                                                      onTap:
                                                          () => _openRaceDecks(
                                                            raceEntry.key,
                                                            raceEntry.value,
                                                            coverageByDeckId,
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  const SizedBox(height: 20),
                                ],
                              ],
                            ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Map<String, List<Deck>> _groupByRace(List<Deck> decks) {
    final grouped = <String, List<Deck>>{};
    for (final deck in decks) {
      final race = (deck.race ?? '').trim();
      grouped.putIfAbsent(race.isEmpty ? 'Sin raza' : race, () => []).add(deck);
    }
    final entries =
        grouped.entries.toList()
          ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return Map.fromEntries(entries);
  }

  Future<void> _openRaceDecks(
    String race,
    List<Deck> decks,
    Map<String, DeckCoverage> coverageByDeckId,
  ) async {
    if (decks.length == 1) {
      context.push('/mazo/$_uid/${decks.single.id}');
      return;
    }
    final selected = await showModalBottomSheet<Deck>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (sheetContext) => FractionallySizedBox(
            heightFactor: .74,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF27221B), Color(0xFF101116)],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        margin: const EdgeInsets.only(top: 10, bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 10, 14),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.hub_outlined,
                            color: Color(0xFFD8B46A),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  race,
                                  style: Theme.of(sheetContext)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const Text(
                                  'Elige el mazo que quieres abrir',
                                  style: TextStyle(color: Colors.white54),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 270,
                              mainAxisExtent: 235,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 14,
                            ),
                        itemCount: decks.length,
                        itemBuilder: (_, index) {
                          final deck = decks[index];
                          return _RaceDeckChoiceCard(
                            deck: deck,
                            coverUrl: _coverFor(deck),
                            coverage: coverageByDeckId[deck.id]!,
                            onTap: () => Navigator.pop(sheetContext, deck),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
    if (selected != null && mounted) {
      context.push('/mazo/$_uid/${selected.id}');
    }
  }

  Widget _buildDeckCard(
    Deck deck,
    Map<String, DeckCoverage> coverageByDeckId,
    Map<String, DeckStockTarget> stockTargets,
  ) {
    final coverage = coverageByDeckId[deck.id]!;
    return _DeckConfigurationCard(
      key: ValueKey(deck.id),
      deck: deck,
      coverage: coverage,
      coverUrl: _coverFor(deck),
      legal: _legal(deck),
      perfil: _perfil(deck),
      sharedStock: false,
      onOpen: () => context.push('/mazo/$_uid/${deck.id}'),
      onEdit:
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => CreateDeckScreen(editDeck: deck)),
          ),
      onDelete: () => _delete(deck),
      onCoverage:
          () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder:
                (_) => _CoverageSheet(
                  coverage: coverage,
                  imageForCard: _imageForCard,
                ),
          ),
    );
  }

  /// Perfil del mazo según las habilidades programadas de sus cartas.
  PerfilHabilidades? _perfil(Deck deck) {
    if (_catalogById.isEmpty && _catalogByName.isEmpty) return null;
    final perfil = calcularPerfilHabilidades(
      deck,
      resolver: (entry) {
        final id = (entry.cardId ?? '').trim();
        return (id.isNotEmpty ? _catalogById[id] : null) ??
            _catalogByName[entry.name.trim().toLowerCase()] ??
            _catalogByName[entry.name];
      },
    );
    return perfil.vacio ? null : perfil;
  }

  bool? _legal(Deck deck) {
    if (!_loadedBanFormats.contains(deck.format)) return null;
    // Sin catálogo aún no se puede validar: evita falsos "No legal".
    if (_catalogById.isEmpty && _catalogByName.isEmpty) return null;
    final result = validateDeck(
      deck: deck,
      catalogById: _catalogById,
      catalogByName: _catalogByName,
      copyLimitsByKey: _copyLimitsByFormat[deck.format] ?? const {},
    );
    // El badge "No legal" solo refleja incumplimiento de la Ban List (y
    // reglas de formato/raza/edición). Que el mazo aún no tenga las 49
    // cartas es normal mientras se arma y no debe mostrarse como ilegal.
    return !result.issues.any((issue) => issue.code != 'TOTAL_NOT_49');
  }
}

class _DeckFormatSwitch extends StatelessWidget {
  final bool showFreeFormats;
  final ValueChanged<bool> onChanged;

  const _DeckFormatSwitch({
    required this.showFreeFormats,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              'Racial Edición',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: showFreeFormats ? FontWeight.w500 : FontWeight.w800,
                color:
                    showFreeFormats
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          Switch(value: showFreeFormats, onChanged: onChanged),
          Expanded(
            child: Text(
              'Libres',
              style: TextStyle(
                fontWeight: showFreeFormats ? FontWeight.w800 : FontWeight.w500,
                color:
                    showFreeFormats
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _RaceFamilyHeader extends StatelessWidget {
  final String race;
  final VoidCallback onTap;

  const _RaceFamilyHeader({required this.race, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(10),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
      child: Row(
        children: [
          const Icon(Icons.hub_outlined, size: 18, color: Color(0xFFD8B46A)),
          const SizedBox(width: 8),
          Text(
            race,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const Spacer(),
          const Icon(Icons.chevron_right, size: 20),
        ],
      ),
    ),
  );
}

class _RaceDeckCollageCard extends StatelessWidget {
  final List<String?> coverUrls;
  final VoidCallback onTap;

  const _RaceDeckCollageCard({required this.coverUrls, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final count = coverUrls.length;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1.2,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildCollage(),
                  if (count > 4)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .75),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '+${count - 4}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollage() {
    Widget image(int index) => _RaceDeckCover(url: coverUrls[index]);
    if (coverUrls.length == 1) return image(0);
    if (coverUrls.length == 2) {
      return Row(
        children: [Expanded(child: image(0)), Expanded(child: image(1))],
      );
    }
    if (coverUrls.length == 3) {
      return Row(
        children: [
          Expanded(child: image(0)),
          Expanded(
            child: Column(
              children: [Expanded(child: image(1)), Expanded(child: image(2))],
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [Expanded(child: image(0)), Expanded(child: image(1))],
          ),
        ),
        Expanded(
          child: Row(
            children: [Expanded(child: image(2)), Expanded(child: image(3))],
          ),
        ),
      ],
    );
  }
}

class _RaceDeckCover extends StatelessWidget {
  final String? url;

  const _RaceDeckCover({required this.url});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border.all(color: Colors.black.withValues(alpha: .35), width: .5),
    ),
    child: MylCardImage(
      url: url,
      fit: BoxFit.cover,
      fallback: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4B3522), Color(0xFF171A22)],
          ),
        ),
        child: const Icon(
          Icons.style_rounded,
          size: 32,
          color: Color(0xFFD8B46A),
        ),
      ),
    ),
  );
}

class _RaceDeckChoiceCard extends StatelessWidget {
  final Deck deck;
  final String? coverUrl;
  final DeckCoverage coverage;
  final VoidCallback onTap;

  const _RaceDeckChoiceCard({
    required this.deck,
    required this.coverUrl,
    required this.coverage,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final progress =
        coverage.required == 0
            ? 0.0
            : (coverage.assigned / coverage.required).clamp(0.0, 1.0);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 5,
      color: const Color(0xFF1B1B21),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color:
              coverage.isAssembled
                  ? Colors.greenAccent.withValues(alpha: .45)
                  : const Color(0x55D8B46A),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MylCardImage(
                    url: coverUrl,
                    fit: BoxFit.cover,
                    fallback: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF4B3522), Color(0xFF171A22)],
                        ),
                      ),
                      child: const Icon(
                        Icons.style_rounded,
                        size: 38,
                        color: Color(0xFFD8B46A),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Color(0xBB000000),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        coverage.isAssembled
                            ? Icons.check
                            : Icons.construction_rounded,
                        size: 16,
                        color:
                            coverage.isAssembled
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deck.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 5,
                      backgroundColor: Colors.white12,
                      color:
                          coverage.isAssembled
                              ? Colors.greenAccent
                              : const Color(0xFFD8B46A),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionalFormatsNotice extends StatelessWidget {
  const _OptionalFormatsNotice();

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white12),
    ),
    child: const Row(
      children: [
        Icon(Icons.info_outline, color: Color(0xFFD8B46A)),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Full y Racial Libre no afectan la completitud. Sus copias se asignan solo cuando tú lo decides.',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      ],
    ),
  );
}

class _DecksKpiSummary extends StatelessWidget {
  final List<Deck> decks;
  final Map<String, DeckCoverage> coverageByDeckId;
  final List<InventoryItem> inventory;

  const _DecksKpiSummary({
    required this.decks,
    required this.coverageByDeckId,
    required this.inventory,
  });

  @override
  Widget build(BuildContext context) {
    final coverages =
        decks
            .map((deck) => coverageByDeckId[deck.id])
            .whereType<DeckCoverage>()
            .toList();
    final required = coverages.fold<int>(
      0,
      (total, coverage) => total + coverage.required,
    );
    final assigned = coverages.fold<int>(
      0,
      (total, coverage) => total + coverage.assigned,
    );
    // Copias que te faltan para completar todos los mazos: como las copias
    // se comparten, por carta cuenta solo el mazo que más pide.
    final owned = {for (final item in inventory) item.key: item.total};
    final maxRequired = <String, int>{};
    for (final coverage in coverages) {
      for (final card in coverage.cards) {
        final key = entryInventoryKey(card.card);
        if (card.required > (maxRequired[key] ?? 0)) {
          maxRequired[key] = card.required;
        }
      }
    }
    final physicallyMissing = maxRequired.entries.fold<int>(
      0,
      (total, entry) =>
          total + (entry.value - (owned[entry.key] ?? 0)).clamp(0, entry.value),
    );
    final assembled =
        coverages.where((coverage) => coverage.isAssembled).length;
    final inProgress = coverages.length - assembled;
    final progress =
        required == 0 ? 0.0 : (assigned / required).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF29251E), Color(0xFF171A22)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x55D8B46A)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 620;
            final progressBlock = _DeckCompletionKpi(
              progress: progress,
              assigned: assigned,
              required: required,
            );
            final metrics = Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _DeckKpi(
                  icon: Icons.check_circle_outline,
                  label: 'Completos',
                  value: '$assembled',
                  color: Colors.greenAccent,
                ),
                _DeckKpi(
                  icon: Icons.build_circle_outlined,
                  label: 'Incompletos',
                  value: '$inProgress',
                  color: Colors.orangeAccent,
                ),
                _DeckKpi(
                  icon: Icons.remove_shopping_cart_outlined,
                  label: 'Cartas que te faltan',
                  value: '$physicallyMissing',
                  color:
                      physicallyMissing == 0
                          ? Colors.greenAccent
                          : Colors.redAccent,
                ),
              ],
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [progressBlock, const SizedBox(height: 12), metrics],
              );
            }
            return Row(
              children: [
                progressBlock,
                const SizedBox(width: 20),
                Expanded(child: metrics),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DeckCompletionKpi extends StatelessWidget {
  final double progress;
  final int assigned;
  final int required;

  const _DeckCompletionKpi({
    required this.progress,
    required this.assigned,
    required this.required,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 58,
        height: 58,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CircularProgressIndicator(
              value: progress,
              strokeWidth: 6,
              backgroundColor: Colors.white12,
              color: const Color(0xFFD8B46A),
            ),
            Center(
              child: Text(
                '${(progress * 100).round()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 12),
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Completitud',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            '$assigned/$required copias ubicadas',
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    ],
  );
}

class _DeckKpi extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _DeckKpi({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 104),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 7),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ],
        ),
      ],
    ),
  );
}

class _MigrationBanner extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _MigrationBanner({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.tertiaryContainer,
    child: ListTile(
      leading: const Icon(Icons.upgrade),
      title: Text('$count mazos usan el formato Tengo/Objetivo'),
      subtitle: const Text(
        'Revisa la unión antes de modificar cualquier dato.',
      ),
      trailing: FilledButton(onPressed: onTap, child: const Text('Revisar')),
    ),
  );
}

class _DeckGroupHeader extends StatelessWidget {
  final String title;
  final int count;
  final bool isFreeFormats;

  const _DeckGroupHeader({
    required this.title,
    required this.count,
    this.isFreeFormats = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 25,
          decoration: BoxDecoration(
            color: isFreeFormats ? Colors.blueGrey : const Color(0xFFD8B46A),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text('$count'),
        ),
      ],
    ),
  );
}

class _DeckConfigurationCard extends StatelessWidget {
  final Deck deck;
  final DeckCoverage coverage;
  final String? coverUrl;
  final bool? legal;
  final PerfilHabilidades? perfil;
  final bool sharedStock;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onCoverage;

  const _DeckConfigurationCard({
    super.key,
    required this.deck,
    required this.coverage,
    required this.coverUrl,
    required this.legal,
    this.perfil,
    this.sharedStock = false,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.onCoverage,
  });

  @override
  Widget build(BuildContext context) {
    final color = coverage.isAssembled ? Colors.green : Colors.orange;
    final edition = (deck.edition ?? '').trim();
    final race = (deck.race ?? '').trim();
    final progress =
        coverage.required == 0
            ? 1.0
            : (coverage.assigned / coverage.required).clamp(0.0, 1.0);
    return SizedBox(
      width: 220,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 4,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1.2,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MylCardImage(
                      url: coverUrl,
                      fit: BoxFit.cover,
                      fallback: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF4B3522), Color(0xFF171A22)],
                          ),
                        ),
                        child: const Icon(
                          Icons.style_rounded,
                          size: 42,
                          color: Color(0xFFD8B46A),
                        ),
                      ),
                    ),
                    if (legal == false || sharedStock)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (legal == false)
                              const _Badge(
                                label: 'No legal',
                                color: Colors.redAccent,
                              ),
                            if (sharedStock) ...[
                              if (legal == false) const SizedBox(height: 4),
                              const _Badge(
                                label: 'Stock compartido',
                                color: Colors.teal,
                              ),
                            ],
                          ],
                        ),
                      ),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Material(
                        color: Colors.black.withValues(alpha: .45),
                        shape: const CircleBorder(),
                        child: PopupMenuButton<String>(
                          icon: const Icon(
                            Icons.more_vert,
                            size: 18,
                            color: Colors.white,
                          ),
                          padding: EdgeInsets.zero,
                          onSelected: (value) {
                            if (value == 'edit') onEdit();
                            if (value == 'delete') onDelete();
                          },
                          itemBuilder:
                              (_) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Editar configuración'),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Eliminar'),
                                ),
                              ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deck.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (race.isNotEmpty || edition.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          [
                            race,
                            edition,
                          ].where((value) => value.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.white54),
                        ),
                      ),
                    if (perfil != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Tooltip(
                          message: perfil!.motivoPerfil,
                          child: Text(
                            _resumenPerfil(perfil!),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: const Color(0xFFD8B46A)),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: onCoverage,
                      child: Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 6,
                                backgroundColor: Colors.white12,
                                valueColor: AlwaysStoppedAnimation(color),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${(progress * 100).round()}%',
                            style: Theme.of(
                              context,
                            ).textTheme.labelSmall?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .85),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _CoverageSheet extends StatelessWidget {
  final DeckCoverage coverage;
  final String? Function(DeckCardEntry card, String? variantId) imageForCard;
  const _CoverageSheet({required this.coverage, required this.imageForCard});

  String _label(DeckCopyState state) => switch (state) {
    DeckCopyState.assigned => 'La tienes',
    DeckCopyState.free => 'La tienes',
    DeckCopyState.inOtherDeck => 'La tienes',
    DeckCopyState.reservedForSale => 'La tienes',
    DeckCopyState.missing => 'No la tienes',
  };

  Color _color(DeckCopyState state) => switch (state) {
    DeckCopyState.assigned => Colors.green,
    DeckCopyState.free => Colors.lightGreen,
    DeckCopyState.inOtherDeck => Colors.blueGrey,
    DeckCopyState.reservedForSale => Colors.deepOrange,
    DeckCopyState.missing => Colors.grey,
  };

  IconData _icon(DeckCopyState state) => switch (state) {
    DeckCopyState.assigned => Icons.check_circle,
    DeckCopyState.free => Icons.inventory_2_outlined,
    DeckCopyState.inOtherDeck => Icons.swap_horiz,
    DeckCopyState.reservedForSale => Icons.storefront,
    DeckCopyState.missing => Icons.remove_circle_outline,
  };

  @override
  Widget build(BuildContext context) => SafeArea(
    child: DraggableScrollableSheet(
      expand: false,
      initialChildSize: .72,
      maxChildSize: .94,
      builder:
          (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                coverage.deck.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                '${coverage.assigned} de ${coverage.required} copias ubicadas',
              ),
              const SizedBox(height: 18),
              for (final card in coverage.cards)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          card.card.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 12,
                          children: [
                            for (final copy in card.copies)
                              _CopyImage(
                                copy: copy,
                                imageUrl: imageForCard(
                                  card.card,
                                  copy.variantId,
                                ),
                                label: _label(copy.state),
                                color: _color(copy.state),
                                icon: _icon(copy.state),
                              ),
                          ],
                        ),
                        if (card.copies.any(
                          (copy) => copy.state == DeckCopyState.missing,
                        )) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                onPressed:
                                    () => _addWishlist(context, card.card),
                                icon: const Icon(Icons.favorite_border),
                                label: const Text('Wishlist'),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
    ),
  );

  Future<void> _addWishlist(BuildContext context, DeckCardEntry card) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await WishlistService(uid).addManual(card);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${card.name} agregada a Wishlist.')),
      );
    }
  }
}

class _CopyImage extends StatelessWidget {
  static const _grayscale = <double>[
    .2126,
    .7152,
    .0722,
    0,
    0,
    .2126,
    .7152,
    .0722,
    0,
    0,
    .2126,
    .7152,
    .0722,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];

  final DeckCopyCoverage copy;
  final String? imageUrl;
  final String label;
  final Color color;
  final IconData icon;

  const _CopyImage({
    required this.copy,
    required this.imageUrl,
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final assigned = copy.state == DeckCopyState.assigned;
    final image = MylCardImage(
      url: imageUrl,
      width: 92,
      height: 130,
      fit: BoxFit.cover,
      borderRadius: BorderRadius.circular(8),
      fallback: Container(
        width: 92,
        height: 130,
        color: const Color(0xFF252832),
        alignment: Alignment.center,
        child: const Icon(Icons.style_outlined, size: 34),
      ),
    );
    return Tooltip(
      message: label,
      child: SizedBox(
        width: 92,
        child: Column(
          children: [
            Stack(
              children: [
                assigned
                    ? image
                    : ColorFiltered(
                      colorFilter: const ColorFilter.matrix(_grayscale),
                      child: Opacity(opacity: .62, child: image),
                    ),
                Positioned(
                  left: 5,
                  top: 5,
                  child: CircleAvatar(
                    radius: 12,
                    backgroundColor: Colors.black87,
                    child: Text(
                      '${copy.copyNumber}',
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                    ),
                  ),
                ),
                Positioned(
                  right: 5,
                  bottom: 5,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 4),
                      ],
                    ),
                    child: Icon(icon, size: 15, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: assigned ? null : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MigrationDialog extends StatefulWidget {
  final String uid;
  const _MigrationDialog({required this.uid});

  @override
  State<_MigrationDialog> createState() => _MigrationDialogState();
}

class _MigrationDialogState extends State<_MigrationDialog> {
  late final DeckV2MigrationService _service;
  DeckMigrationPreview? _preview;
  final Map<String, DeckMigrationSelection> _selections = {};
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service = DeckV2MigrationService(widget.uid);
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await _service.preview();
      if (mounted) setState(() => _preview = value);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _migrate() async {
    final preview = _preview;
    if (preview == null) return;
    setState(() => _busy = true);
    try {
      await _service.migrate(
        preview: preview,
        selections: _selections.values.toList(),
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return AlertDialog(
      title: const Text('Unir mazos Tengo/Objetivo'),
      content: SizedBox(
        width: 620,
        child:
            preview == null
                ? Center(
                  child:
                      _error == null
                          ? const CircularProgressIndicator()
                          : Text(_error!),
                )
                : ListView(
                  shrinkWrap: true,
                  children: [
                    if (preview.blockedByActivePlans)
                      const ListTile(
                        leading: Icon(Icons.lock, color: Colors.orange),
                        title: Text('Migración bloqueada'),
                        subtitle: Text(
                          'Primero finaliza o cancela los planes de movimiento activos.',
                        ),
                      ),
                    Text(
                      '${preview.physicalDecks.length} mazos físicos, '
                      '${preview.orphanTargets.length} objetivos huérfanos y '
                      '${preview.alreadyMigrated.length} ya migrados.',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${preview.physicalDecks.where((pair) => !pair.hasConfigurationConflict && pair.suggestedTargets.isEmpty).length} '
                      'se resolverán automáticamente. Solo elige en los casos de abajo.',
                    ),
                    const SizedBox(height: 12),
                    for (final pair in preview.physicalDecks.where(
                      (pair) =>
                          pair.hasConfigurationConflict ||
                          pair.suggestedTargets.isNotEmpty,
                    ))
                      Card(
                        child: ListTile(
                          title: Text(pair.deck.name),
                          subtitle:
                              pair.hasConfigurationConflict
                                  ? DropdownButton<DeckConfigurationSource>(
                                    isExpanded: true,
                                    hint: const Text(
                                      'Elige qué configuración conservar',
                                    ),
                                    value: _selections[pair.deck.id]?.source,
                                    items: const [
                                      DropdownMenuItem(
                                        value: DeckConfigurationSource.current,
                                        child: Text(
                                          'Quedarme con la lista Tengo',
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value:
                                            DeckConfigurationSource
                                                .embeddedObjective,
                                        child: Text(
                                          'Quedarme con el Objetivo incluido',
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value:
                                            DeckConfigurationSource
                                                .linkedTarget,
                                        child: Text(
                                          'Quedarme con el Objetivo vinculado',
                                        ),
                                      ),
                                    ],
                                    onChanged: (source) {
                                      if (source == null) return;
                                      setState(() {
                                        _selections[pair
                                            .deck
                                            .id] = DeckMigrationSelection(
                                          deckId: pair.deck.id,
                                          source: source,
                                          targetDeckId: pair.linkedTarget?.id,
                                        );
                                      });
                                    },
                                  )
                                  : pair.linkedTarget == null &&
                                      pair.deck.objectiveCards.isEmpty &&
                                      pair.suggestedTargets.isNotEmpty
                                  ? DropdownButton<String>(
                                    isExpanded: true,
                                    value:
                                        _selections[pair.deck.id]
                                            ?.targetDeckId ??
                                        'current',
                                    items: [
                                      const DropdownMenuItem(
                                        value: 'current',
                                        child: Text(
                                          'Conservar su lista actual',
                                        ),
                                      ),
                                      for (final target
                                          in pair.suggestedTargets)
                                        DropdownMenuItem(
                                          value: target.id,
                                          child: Text(
                                            'Usar objetivo sugerido: ${target.name}',
                                          ),
                                        ),
                                    ],
                                    onChanged: (targetId) {
                                      if (targetId == null) return;
                                      setState(() {
                                        _selections[pair
                                            .deck
                                            .id] = DeckMigrationSelection(
                                          deckId: pair.deck.id,
                                          source:
                                              targetId == 'current'
                                                  ? DeckConfigurationSource
                                                      .current
                                                  : DeckConfigurationSource
                                                      .linkedTarget,
                                          targetDeckId:
                                              targetId == 'current'
                                                  ? null
                                                  : targetId,
                                        );
                                      });
                                    },
                                  )
                                  : Text(
                                    pair.linkedTarget != null
                                        ? 'Usará el Objetivo vinculado.'
                                        : pair.deck.objectiveCards.isNotEmpty
                                        ? 'Usará el Objetivo incluido.'
                                        : 'Su lista actual será la configuración.',
                                  ),
                          trailing:
                              pair.hasConfigurationConflict
                                  ? const Icon(
                                    Icons.warning_amber,
                                    color: Colors.orange,
                                  )
                                  : const Icon(Icons.check_circle_outline),
                        ),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                  ],
                ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cerrar sin cambiar'),
        ),
        FilledButton.icon(
          onPressed:
              _busy ||
                      preview == null ||
                      preview.blockedByActivePlans ||
                      (preview.hasConflicts &&
                          preview.physicalDecks
                              .where((pair) => pair.hasConfigurationConflict)
                              .any(
                                (pair) =>
                                    !_selections.containsKey(pair.deck.id),
                              ))
                  ? null
                  : _migrate,
          icon: const Icon(Icons.auto_fix_high),
          label:
              _busy
                  ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Text('Unir mazos'),
        ),
      ],
    );
  }
}


/// "Control · Robo 16 · Recursión 15 · Remoción 15" (las 3 categorías más altas).
String _resumenPerfil(PerfilHabilidades perfil) {
  final top =
      perfil.porCategoria.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
  final partes = [
    for (final e in top.take(3)) '${e.key.split(' (').first} ${e.value}',
  ];
  return [perfil.perfil, ...partes].join(' · ');
}
