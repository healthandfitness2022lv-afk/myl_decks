// lib/screens/leagues/league_deck_builder_screen.dart
//
// Pantalla de armado de mazo para una fecha de liga.
// No guarda en la colección de mazos del usuario; devuelve la lista de cartas
// al llamador mediante Navigator.pop(context, List<DeckCardEntry>).
//
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/card_myl.dart';
import '../../models/deck.dart';
import '../../domain/validation/deck_validator.dart';
import '../../models/ban_list_entry.dart';
import '../../services/ban_list_service.dart';
import '../../services/drive_service.dart';
import '../../utils/text_normalize.dart';
import '../../widgets/card_image_preview.dart';
import 'models.dart';
import '../../widgets/network_image.dart';

bool leagueFormatAllowsSoloLibre(RoundFormat format) =>
    format != RoundFormat.racialEdicion;

String? leagueDeckRaceForFormat(RoundFormat format, String? race) {
  if (format == RoundFormat.full) return null;
  final normalized = race?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

/// Resultado devuelto por [LeagueDeckBuilderScreen] al guardar: las cartas del
/// mazo y la raza deducida (de la primera carta aliada), o null si aún no hay.
class LeagueDeckResult {
  final List<DeckCardEntry> cards;
  final String? race;
  const LeagueDeckResult({required this.cards, this.race});
}

class LeagueDeckBuilderScreen extends StatefulWidget {
  final String playerName;
  final RoundFormat roundFormat;
  final List<Map<String, dynamic>>? banListSnapshot;
  final List<DeckCardEntry> initialCards;
  final String? initialRace;

  const LeagueDeckBuilderScreen({
    super.key,
    required this.playerName,
    required this.roundFormat,
    this.banListSnapshot,
    this.initialCards = const [],
    this.initialRace,
  });

  @override
  State<LeagueDeckBuilderScreen> createState() =>
      _LeagueDeckBuilderScreenState();
}

class _LeagueDeckBuilderScreenState extends State<LeagueDeckBuilderScreen> {
  late final BanListService _banListService = BanListService.forRoundFormatKey(
    widget.roundFormat.firestoreKey,
  );
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  List<DeckCardEntry> _cards = [];
  List<CardMyL> _availableCards = [];
  bool _loadingAvailable = false;
  bool _loadingBanList = false;
  String _typeFilter = 'all';

  // Race/edition deducidos de la primera carta aliada
  String? _race;
  String? _edition;

  Map<String, int> _copyLimitsByKey = const {};
  final Map<String, String?> _imgCache = {};

  static const List<String> _tabKeys = [
    'aliado',
    'talisman',
    'arma',
    'oro',
    'totem',
  ];

  @override
  void initState() {
    super.initState();
    _cards = List.from(widget.initialCards);

    // Raza sembrada desde el mazo guardado (los aliados de un mazo ya armado
    // pertenecen a esa raza). Permite filtrar el catálogo correctamente al
    // reeditar sin tener que resolver la raza carta por carta.
    final seededRace = leagueDeckRaceForFormat(
      widget.roundFormat,
      widget.initialRace,
    );
    if (seededRace != null && seededRace.isNotEmpty) {
      _race = seededRace;
    }

    _loadBanList();
    _searchCtrl.addListener(_onFiltersChanged);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _refreshAvailableCards(),
    );
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onFiltersChanged);
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ── Ban list ───────────────────────────────────────────────────────────────

  Future<void> _loadBanList() async {
    setState(() => _loadingBanList = true);
    try {
      final byKey =
          widget.banListSnapshot != null
              ? BanListService.copyLimitsFromSnapshot(widget.banListSnapshot!)
              : await _banListService.fetchCopyLimitsByKey();
      if (!mounted) return;
      setState(() {
        _copyLimitsByKey = byKey;
      });
    } catch (e) {
      debugPrint('LeagueDeckBuilder: error loading ban list: $e');
    } finally {
      if (mounted) setState(() => _loadingBanList = false);
    }
  }

  int _copyLimitForCard(CardMyL card) {
    final fromBan =
        _copyLimitsByKey[normalizeBanListKey(card.id)] ??
        _copyLimitsByKey[normalizeBanListKey(card.nombre)];
    return limiteDeCopias(
      enBanList: fromBan,
      unica: card.unica,
      mercenario: cartaEsMercenario(card, id: card.id, nombre: card.nombre),
    );
  }

  int _copyLimitForEntry(DeckCardEntry entry) {
    final fromBan =
        _copyLimitsByKey[normalizeBanListKey(entry.cardId ?? '')] ??
        _copyLimitsByKey[normalizeBanListKey(entry.name)];
    final isUnique =
        entry.unica ||
        _availableCards.any((card) {
          final sameId =
              (entry.cardId ?? '').isNotEmpty && entry.cardId == card.id;
          final sameName =
              entry.name.trim().toLowerCase() ==
              card.nombre.trim().toLowerCase();
          return (sameId || sameName) && card.unica;
        });
    return limiteDeCopias(
      enBanList: fromBan,
      unica: isUnique,
      mercenario: cartaEsMercenario(
        null,
        id: entry.cardId,
        nombre: entry.name,
      ),
    );
  }

  // ── Cartas disponibles ─────────────────────────────────────────────────────

  void _onFiltersChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _refreshAvailableCards();
    });
  }

  Future<void> _refreshAvailableCards() async {
    if (mounted) setState(() => _loadingAvailable = true);

    final currentRace = _race ?? '';
    final currentEdition = _edition ?? '';
    final text = normalizeSearch(_searchCtrl.text);
    final selectedType = _typeFilter;
    final format = widget.roundFormat;

    try {
      final col = FirebaseFirestore.instance.collection('cards');
      final cards = <String, CardMyL>{};

      Future<void> runQuery(Query<Map<String, dynamic>> q) async {
        final snap = await q.get();
        for (final d in snap.docs) {
          cards[d.id] = CardMyL.fromMap(d.data(), d.id);
        }
      }

      if (format == RoundFormat.full) {
        // Full: cualquier carta sin restricción
        Query<Map<String, dynamic>> q = col;
        if (selectedType != 'all') {
          q = q.where('tipo', isEqualTo: _prettyType(selectedType));
        }
        await runQuery(q);
      } else {
        // racialEdicion / racialLibre: necesitan raza para filtrar aliados
        final isLibre = format == RoundFormat.racialLibre;

        final wantsAliado = selectedType == 'all' || selectedType == 'aliado';
        final wantsOro = selectedType == 'all' || selectedType == 'oro';
        final wantsSupport =
            selectedType == 'all' ||
            selectedType == 'talisman' ||
            selectedType == 'totem' ||
            selectedType == 'arma';

        if (currentRace.isNotEmpty) {
          if (wantsAliado) {
            if (isLibre) {
              await runQuery(
                col
                    .where('raza', isEqualTo: currentRace)
                    .where('tipo', isEqualTo: 'Aliado'),
              );
            } else if (currentEdition.isNotEmpty) {
              await runQuery(
                col
                    .where('edicion', isEqualTo: currentEdition)
                    .where('raza', isEqualTo: currentRace)
                    .where('tipo', isEqualTo: 'Aliado'),
              );
            }
          }
          if (wantsOro) {
            if (isLibre) {
              await runQuery(col.where('tipo', isEqualTo: 'Oro'));
            } else if (currentEdition.isNotEmpty) {
              await runQuery(
                col
                    .where('edicion', isEqualTo: currentEdition)
                    .where('tipo', isEqualTo: 'Oro'),
              );
            }
          }
          if (wantsSupport) {
            final supportTypes =
                selectedType == 'all'
                    ? ['Talismán', 'Tótem', 'Arma']
                    : [_prettyType(selectedType)];
            if (isLibre) {
              await runQuery(col.where('tipo', whereIn: supportTypes));
            } else if (currentEdition.isNotEmpty) {
              await runQuery(
                col
                    .where('edicion', isEqualTo: currentEdition)
                    .where('tipo', whereIn: supportTypes),
              );
            }
          }
        } else {
          // Sin raza todavía: mostrar todo para que el admin pueda elegir la primera carta
          Query<Map<String, dynamic>> q = col;
          if (selectedType != 'all') {
            q = q.where('tipo', isEqualTo: _prettyType(selectedType));
          }
          await runQuery(q);
        }
      }

      // Full incluye todo el pool, también las cartas creadas para Racial
      // Libre. Solo Racial Edición excluye las cartas `soloLibre`.
      final allowSoloLibre = leagueFormatAllowsSoloLibre(format);

      final filtered =
          cards.values.where((c) {
            // Cartas incompletas (stub): creadas rápido y sin datos completos.
            if (c.isStub) return false;
            if (!allowSoloLibre && c.soloLibre) return false;
            if (text.isNotEmpty && !normalizeSearch(c.nombre).contains(text)) {
              return false;
            }
            return true;
          }).toList();

      filtered.sort(
        (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
      );

      if (!mounted) return;
      setState(() => _availableCards = filtered);
    } catch (e) {
      if (!mounted) return;
      setState(() => _availableCards = []);
    } finally {
      if (mounted) setState(() => _loadingAvailable = false);
    }
  }

  // ── Operaciones sobre el mazo ──────────────────────────────────────────────

  int get _totalCards => _cards.fold<int>(0, (s, e) => s + e.count);
  bool get _isDeckFull => _totalCards >= 49;

  int _countInDeck(CardMyL card) {
    for (final e in _cards) {
      final sameId = (e.cardId ?? '').isNotEmpty && e.cardId == card.id;
      final sameName =
          e.name.trim().toLowerCase() == card.nombre.trim().toLowerCase();
      if (sameId || sameName) return e.count;
    }
    return 0;
  }

  void _addCard(CardMyL card) {
    final limit = _copyLimitForCard(card);
    final current = _countInDeck(card);
    if (current >= limit || _isDeckFull) return;

    final prevRace = _race;
    final prevEdition = _edition;

    setState(() {
      // Auto-populate race/edition
      if (widget.roundFormat != RoundFormat.full &&
          card.tipo.toLowerCase() == 'aliado' &&
          (_race?.isEmpty ?? true)) {
        _race = card.raza;
      }
      if (widget.roundFormat == RoundFormat.racialEdicion &&
          (_edition?.isEmpty ?? true)) {
        _edition = card.edicion;
      }

      final idx = _cards.indexWhere((e) {
        final sameId = (e.cardId ?? '').isNotEmpty && e.cardId == card.id;
        final sameName =
            e.name.trim().toLowerCase() == card.nombre.trim().toLowerCase();
        return sameId || sameName;
      });

      if (idx >= 0) {
        final cur = _cards[idx];
        _cards[idx] = cur.copyWith(count: (cur.count + 1).clamp(1, limit));
      } else {
        _cards = [
          ..._cards,
          DeckCardEntry(
            cardId: card.id,
            name: card.nombre,
            count: 1,
            coste: card.coste,
            tipo: card.tipo,
            rareza: card.rareza,
            edicion: card.edicion,
            soloLibre: card.soloLibre,
            unica: card.unica,
          ),
        ];
      }
    });

    // Solo re-consultar el catálogo si la raza/edición cambió (p.ej. el primer
    // aliado fijó la raza). Para el resto de las cartas, evitar el refresh
    // mantiene la posición de scroll y no hace parpadear la grilla.
    if (_race != prevRace || _edition != prevEdition) {
      _refreshAvailableCards();
    }
  }

  // Si el mazo ya no tiene aliados, la raza/edición deducidas dejan de aplicar
  // y el catálogo debe volver a mostrar todo. Devuelve true si limpió algo.
  bool _syncRaceEditionFromCards() {
    if (widget.roundFormat == RoundFormat.full) {
      final hadContext = _race != null || _edition != null;
      _race = null;
      _edition = null;
      return hadContext;
    }

    final hasAliado = _cards.any(
      (e) => (e.tipo ?? '').toLowerCase() == 'aliado',
    );
    if (!hasAliado && (_race != null || _edition != null)) {
      _race = null;
      _edition = null;
      return true;
    }
    return false;
  }

  void _setEntryCount(DeckCardEntry e, int newCount) {
    var raceCleared = false;
    setState(() {
      if (newCount <= 0) {
        _cards = _cards.where((x) => !identical(x, e)).toList();
      } else {
        final idx = _cards.indexOf(e);
        if (idx >= 0) {
          final max = _copyLimitForEntry(e);
          _cards[idx] = e.copyWith(count: newCount.clamp(1, max));
        }
      }
      raceCleared = _syncRaceEditionFromCards();
    });
    if (raceCleared) _refreshAvailableCards();
  }

  void _removeEntry(DeckCardEntry e) {
    var raceCleared = false;
    setState(() {
      _cards = _cards.where((x) => !identical(x, e)).toList();
      raceCleared = _syncRaceEditionFromCards();
    });
    if (raceCleared) _refreshAvailableCards();
  }

  Future<void> _pickCount(DeckCardEntry e) async {
    final max = _copyLimitForEntry(e);
    if (max <= 0) {
      _removeEntry(e);
      return;
    }
    final sel = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder:
          (_) => _CountPicker(
            title: e.name,
            current: e.count,
            max: max,
            onDelete: () => Navigator.pop(context, 0),
          ),
    );
    if (sel != null) _setEntryCount(e, sel);
  }

  // ── Imagen ─────────────────────────────────────────────────────────────────

  String _keyForEntry(DeckCardEntry e) =>
      (e.cardId ?? e.name).trim().toLowerCase();

  String? _safeImageUrl(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    final clean = url.trim();
    if (clean.contains('drive.google.com')) {
      return DriveService.webSafeUrl(clean);
    }
    return clean;
  }

  Future<String?> _resolveImage(DeckCardEntry e) async {
    final key = _keyForEntry(e);
    if (_imgCache.containsKey(key)) return _imgCache[key];

    String? pickFromDoc(Map<String, dynamic> m) {
      for (final key in [
        'officialImageUrl',
        'imageUrl',
        'officialImage',
        'frontUrl',
        'img',
        'url',
      ]) {
        final v = _safeImageUrl(m[key]?.toString());
        if (v != null && v.isNotEmpty) return v;
      }
      final images = m['images'];
      if (images is Map) {
        for (final k in ['front', 'anverso']) {
          final v = _safeImageUrl(images[k]?.toString());
          if (v != null && v.isNotEmpty) return v;
        }
      }
      return null;
    }

    String? pickFromVariant(Map<String, dynamic> m) {
      final thumbs = m['thumbs'];
      if (thumbs is Map) {
        for (final k in [
          '56x56',
          '64x64',
          '72x72',
          '80x80',
          '96x96',
          'small',
          'thumb',
          's',
        ]) {
          final v = _safeImageUrl(thumbs[k]?.toString());
          if (v != null && v.isNotEmpty) return v;
        }
      }
      for (final key in [
        'thumbUrl',
        'imageFrontUrl',
        'frontUrl',
        'imageUrl',
        'officialImageUrl',
        'officialImage',
        'img',
        'url',
      ]) {
        final v = _safeImageUrl(m[key]?.toString());
        if (v != null && v.isNotEmpty) return v;
      }
      return null;
    }

    String? url;
    try {
      if ((e.cardId ?? '').isNotEmpty) {
        final doc =
            await FirebaseFirestore.instance
                .collection('cards')
                .doc(e.cardId!)
                .get();
        if (doc.exists) {
          url = pickFromDoc(doc.data() ?? {});
          if (url == null || url.isEmpty) {
            final variants =
                await doc.reference
                    .collection('variants')
                    .orderBy('official', descending: true)
                    .orderBy('isBase', descending: true)
                    .orderBy('name')
                    .limit(6)
                    .get();
            for (final d in variants.docs) {
              url = pickFromVariant(d.data());
              if (url != null && url.isNotEmpty) break;
            }
          }
        }
      }
      if (url == null || url.isEmpty) {
        final nameLower = e.name.trim().toLowerCase();
        if (nameLower.isNotEmpty) {
          final q =
              await FirebaseFirestore.instance
                  .collection('cards')
                  .where('nombre_lower', isEqualTo: nameLower)
                  .limit(1)
                  .get();
          if (q.docs.isNotEmpty) {
            url = pickFromDoc(q.docs.first.data());
            if (url == null || url.isEmpty) {
              final variants =
                  await q.docs.first.reference
                      .collection('variants')
                      .orderBy('official', descending: true)
                      .orderBy('isBase', descending: true)
                      .orderBy('name')
                      .limit(6)
                      .get();
              for (final d in variants.docs) {
                url = pickFromVariant(d.data());
                if (url != null && url.isNotEmpty) break;
              }
            }
          }
        }
      }
    } catch (_) {}
    _imgCache[key] = url;
    return url;
  }

  Future<String?> _resolveImageForCard(CardMyL card) async {
    final key = card.id;
    if (_imgCache.containsKey(key)) return _imgCache[key];
    String? url;
    try {
      final doc =
          await FirebaseFirestore.instance
              .collection('cards')
              .doc(card.id)
              .get();
      if (doc.exists) {
        final data = doc.data() ?? {};
        for (final key in [
          'officialImageUrl',
          'imageUrl',
          'officialImage',
          'frontUrl',
          'img',
          'url',
        ]) {
          final v = _safeImageUrl(data[key]?.toString());
          if (v != null && v.isNotEmpty) {
            url = v;
            break;
          }
        }
        if (url == null || url.isEmpty) {
          final variants =
              await doc.reference
                  .collection('variants')
                  .orderBy('official', descending: true)
                  .orderBy('isBase', descending: true)
                  .orderBy('name')
                  .limit(6)
                  .get();
          for (final d in variants.docs) {
            final data2 = d.data();
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
              final v = _safeImageUrl(data2[key]?.toString());
              if (v != null && v.isNotEmpty) {
                url = v;
                break;
              }
            }
            if (url != null && url.isNotEmpty) break;
          }
        }
      }
    } catch (_) {}
    _imgCache[key] = url;
    return url;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _normalizeTipo(String? raw) {
    final t = (raw ?? '').trim().toLowerCase();
    if (t == 'aliado' || t == 'gran aliado') return 'aliado';
    if (t == 'talisman' || t == 'talismán') return 'talisman';
    if (t == 'arma' || t == 'armadura') return 'arma';
    if (t == 'oro' || t == 'oros') return 'oro';
    if (t == 'totem' || t == 'tótem' || t == 'totem de raza') return 'totem';
    return t;
  }

  String _prettyType(String key) {
    switch (key) {
      case 'aliado':
        return 'Aliado';
      case 'talisman':
        return 'Talismán';
      case 'arma':
        return 'Arma';
      case 'oro':
        return 'Oro';
      case 'totem':
        return 'Tótem';
      default:
        return key.isEmpty
            ? 'Otros'
            : (key[0].toUpperCase() + key.substring(1));
    }
  }

  List<DeckCardEntry> _sortedCards() {
    final list = List<DeckCardEntry>.from(_cards);
    list.sort((a, b) {
      final t = _tabKeys
          .indexOf(_normalizeTipo(a.tipo))
          .compareTo(_tabKeys.indexOf(_normalizeTipo(b.tipo)));
      if (t != 0) return t;
      final c = b.count.compareTo(a.count);
      if (c != 0) return c;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  Map<String, int> _countsByType() {
    final counts = <String, int>{for (final k in _tabKeys) k: 0};
    for (final e in _cards) {
      final k = _normalizeTipo(e.tipo);
      if (counts.containsKey(k)) counts[k] = counts[k]! + e.count;
    }
    return counts;
  }

  void _save() {
    final savedRace = leagueDeckRaceForFormat(widget.roundFormat, _race);
    Navigator.pop(
      context,
      LeagueDeckResult(
        cards: List<DeckCardEntry>.from(_cards),
        race: savedRace,
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final counts = _countsByType();
    final sorted = _sortedCards();

    return Scaffold(
      backgroundColor: const Color(0xFF120D09),
      appBar: AppBar(
        backgroundColor: const Color(0xFF21170F),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.playerName,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              widget.roundFormat.label,
              style: const TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(
                '$_totalCards/49',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _isDeckFull ? Colors.green.shade300 : Colors.white70,
                ),
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Guardar mazo'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD8B46A),
              foregroundColor: const Color(0xFF24180F),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1E1710), Color(0xFF120D09)],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 600;
            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 7,
                    child: _CatalogPanel(
                      availableCards: _availableCards,
                      loadingAvailable: _loadingAvailable,
                      loadingBanList: _loadingBanList,
                      typeFilter: _typeFilter,
                      searchCtrl: _searchCtrl,
                      tabKeys: _tabKeys,
                      prettyType: _prettyType,
                      countInDeck: _countInDeck,
                      copyLimitForCard: _copyLimitForCard,
                      isDeckFull: _isDeckFull,
                      onAdd: _addCard,
                      resolveImage: _resolveImageForCard,
                      onTypeFilterChanged: (v) {
                        setState(() {
                          _typeFilter = v;
                        });
                        _refreshAvailableCards();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 340,
                    child: _DeckSummaryPanel(
                      sorted: sorted,
                      counts: counts,
                      totalCards: _totalCards,
                      tabKeys: _tabKeys,
                      prettyType: _prettyType,
                      resolveImage: _resolveImage,
                      onSetCount: _setEntryCount,
                      onPickCount: _pickCount,
                      onRemove: _removeEntry,
                    ),
                  ),
                ],
              );
            }
            // Móvil: pestañas Catálogo / Mazo
            return DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  Container(
                    color: const Color(0xFF21170F),
                    child: TabBar(
                      indicatorColor: const Color(0xFFD8B46A),
                      labelColor: const Color(0xFFD8B46A),
                      unselectedLabelColor: Colors.white54,
                      tabs: [
                        const Tab(text: 'Catálogo'),
                        Tab(text: 'Mazo ($_totalCards)'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        Column(
                          children: [
                            _FilterBar(
                              typeFilter: _typeFilter,
                              searchCtrl: _searchCtrl,
                              tabKeys: _tabKeys,
                              prettyType: _prettyType,
                              onTypeFilterChanged: (v) {
                                setState(() {
                                  _typeFilter = v;
                                });
                                _refreshAvailableCards();
                              },
                            ),
                            Expanded(
                              child: _CatalogPanel(
                                availableCards: _availableCards,
                                loadingAvailable: _loadingAvailable,
                                loadingBanList: _loadingBanList,
                                typeFilter: _typeFilter,
                                searchCtrl: _searchCtrl,
                                tabKeys: _tabKeys,
                                prettyType: _prettyType,
                                countInDeck: _countInDeck,
                                copyLimitForCard: _copyLimitForCard,
                                isDeckFull: _isDeckFull,
                                onAdd: _addCard,
                                resolveImage: _resolveImageForCard,
                                onTypeFilterChanged: (v) {
                                  setState(() {
                                    _typeFilter = v;
                                  });
                                  _refreshAvailableCards();
                                },
                                hideFilterBar: true,
                              ),
                            ),
                          ],
                        ),
                        _DeckSummaryPanel(
                          sorted: sorted,
                          counts: counts,
                          totalCards: _totalCards,
                          tabKeys: _tabKeys,
                          prettyType: _prettyType,
                          resolveImage: _resolveImage,
                          onSetCount: _setEntryCount,
                          onPickCount: _pickCount,
                          onRemove: _removeEntry,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── Panel catálogo ─────────────────────────────────────────────────────────────

class _CatalogPanel extends StatelessWidget {
  final List<CardMyL> availableCards;
  final bool loadingAvailable;
  final bool loadingBanList;
  final String typeFilter;
  final TextEditingController searchCtrl;
  final List<String> tabKeys;
  final String Function(String) prettyType;
  final int Function(CardMyL) countInDeck;
  final int Function(CardMyL) copyLimitForCard;
  final bool isDeckFull;
  final void Function(CardMyL) onAdd;
  final Future<String?> Function(CardMyL) resolveImage;
  final void Function(String) onTypeFilterChanged;
  final bool hideFilterBar;

  const _CatalogPanel({
    required this.availableCards,
    required this.loadingAvailable,
    required this.loadingBanList,
    required this.typeFilter,
    required this.searchCtrl,
    required this.tabKeys,
    required this.prettyType,
    required this.countInDeck,
    required this.copyLimitForCard,
    required this.isDeckFull,
    required this.onAdd,
    required this.resolveImage,
    required this.onTypeFilterChanged,
    this.hideFilterBar = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF21170F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF9B7B45).withOpacity(.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hideFilterBar) ...[
            _FilterBar(
              typeFilter: typeFilter,
              searchCtrl: searchCtrl,
              tabKeys: tabKeys,
              prettyType: prettyType,
              onTypeFilterChanged: onTypeFilterChanged,
            ),
            const SizedBox(height: 10),
          ],
          Expanded(
            child:
                loadingAvailable
                    ? const Center(child: CircularProgressIndicator())
                    : availableCards.isEmpty
                    ? const Center(
                      child: Text(
                        'No hay cartas para este filtro.',
                        style: TextStyle(color: Colors.white60),
                      ),
                    )
                    : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 170,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: .6,
                          ),
                      itemCount: availableCards.length,
                      itemBuilder: (context, index) {
                        final card = availableCards[index];
                        final copies = countInDeck(card);
                        final limit = copyLimitForCard(card);
                        final blocked = copies >= limit;
                        return FutureBuilder<String?>(
                          future: resolveImage(card),
                          builder: (context, snap) {
                            return _AvailableCardTile(
                              card: card,
                              imageUrl: snap.data,
                              copies: copies,
                              limit: limit,
                              blocked: blocked,
                              deckFull: isDeckFull,
                              onPreview:
                                  () => showCardImagePreview(
                                    context,
                                    cardName: card.nombre,
                                    imageUrl: snap.data,
                                  ),
                              onAdd:
                                  (blocked || isDeckFull)
                                      ? null
                                      : () => onAdd(card),
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

// ── Barra de filtros ───────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final String typeFilter;
  final TextEditingController searchCtrl;
  final List<String> tabKeys;
  final String Function(String) prettyType;
  final void Function(String) onTypeFilterChanged;

  const _FilterBar({
    required this.typeFilter,
    required this.searchCtrl,
    required this.tabKeys,
    required this.prettyType,
    required this.onTypeFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 220,
          child: TextField(
            controller: searchCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Buscar carta...',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.white54),
              filled: true,
              fillColor: const Color(0xFF0F0A07),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: const Color(0xFFB58B47).withOpacity(.35),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: const Color(0xFFB58B47).withOpacity(.35),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFD7B36A)),
              ),
            ),
          ),
        ),
        ...tabKeys.map((k) {
          final selected = typeFilter == k;
          return FilterChip(
            label: Text(prettyType(k)),
            selected: selected,
            backgroundColor: const Color(0xFF2A1F14),
            selectedColor: const Color(0xFFD8B46A).withOpacity(.25),
            checkmarkColor: const Color(0xFFD8B46A),
            side: BorderSide(
              color:
                  selected
                      ? const Color(0xFFD8B46A)
                      : const Color(0xFF9B7B45).withOpacity(.35),
            ),
            labelStyle: TextStyle(
              color: selected ? const Color(0xFFD8B46A) : Colors.white70,
            ),
            onSelected: (_) => onTypeFilterChanged(selected ? 'all' : k),
          );
        }),
      ],
    );
  }
}

// ── Panel resumen mazo ─────────────────────────────────────────────────────────

class _DeckSummaryPanel extends StatelessWidget {
  final List<DeckCardEntry> sorted;
  final Map<String, int> counts;
  final int totalCards;
  final List<String> tabKeys;
  final String Function(String) prettyType;
  final Future<String?> Function(DeckCardEntry) resolveImage;
  final void Function(DeckCardEntry, int) onSetCount;
  final Future<void> Function(DeckCardEntry) onPickCount;
  final void Function(DeckCardEntry) onRemove;

  const _DeckSummaryPanel({
    required this.sorted,
    required this.counts,
    required this.totalCards,
    required this.tabKeys,
    required this.prettyType,
    required this.resolveImage,
    required this.onSetCount,
    required this.onPickCount,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF17110C),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF9B7B45).withOpacity(.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$totalCards/49 Cartas',
            style: const TextStyle(
              color: Color(0xFFF7E2A7),
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children:
                tabKeys
                    .map(
                      (k) => Text(
                        '${prettyType(k)}: ${counts[k] ?? 0}',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 12),
          if (sorted.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'Agrega cartas desde el catálogo',
                  style: TextStyle(color: Colors.white38),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: sorted.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final e = sorted[index];
                  return FutureBuilder<String?>(
                    future: resolveImage(e),
                    builder: (context, snap) {
                      final thumb = snap.data;
                      String? thumbUrl;
                      if (thumb != null &&
                          thumb.isNotEmpty &&
                          thumb.contains('/upload/')) {
                        thumbUrl = thumb.replaceFirst(
                          '/upload/',
                          '/upload/f_auto,q_auto,w_56,h_56,c_fill,g_auto/',
                        );
                      } else {
                        thumbUrl = thumb;
                      }
                      return Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(.22),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: SizedBox(
                                width: 44,
                                height: 44,
                                child:
                                    (thumbUrl != null && thumbUrl.isNotEmpty)
                                        ? MylNetworkImage(
                                          imageUrl: thumbUrl,
                                          fit: BoxFit.cover,
                                          placeholder:
                                              (_, __) => const Center(
                                                child: SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                ),
                                              ),
                                          errorWidget:
                                              (_, __, ___) => const ColoredBox(
                                                color: Color(0xFF33271D),
                                                child: Icon(
                                                  Icons
                                                      .image_not_supported_outlined,
                                                  color: Colors.white54,
                                                  size: 18,
                                                ),
                                              ),
                                        )
                                        : const ColoredBox(
                                          color: Color(0xFF33271D),
                                          child: Icon(
                                            Icons.image_not_supported_outlined,
                                            color: Colors.white54,
                                            size: 18,
                                          ),
                                        ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                e.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Ampliar carta',
                              onPressed:
                                  () => showCardImagePreview(
                                    context,
                                    cardName: e.name,
                                    imageUrl: snap.data,
                                  ),
                              icon: const Icon(
                                Icons.zoom_out_map_rounded,
                                color: Color(0xFFD6B36A),
                                size: 19,
                              ),
                            ),
                            const SizedBox(width: 6),
                            _QtyRow(
                              value: e.count,
                              onDec: () => onSetCount(e, e.count - 1),
                              onInc: () => onSetCount(e, e.count + 1),
                              onTap: () => onPickCount(e),
                              onDelete: () => onRemove(e),
                            ),
                          ],
                        ),
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

// ── Tile de carta disponible ───────────────────────────────────────────────────

class _AvailableCardTile extends StatelessWidget {
  final CardMyL card;
  final String? imageUrl;
  final int copies;
  final int limit;
  final bool blocked;
  final bool deckFull;
  final VoidCallback onPreview;
  final VoidCallback? onAdd;

  const _AvailableCardTile({
    required this.card,
    required this.imageUrl,
    required this.copies,
    required this.limit,
    required this.blocked,
    required this.deckFull,
    required this.onPreview,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final dimmed = blocked || deckFull;
    return GestureDetector(
      onTap: onAdd,
      child: Opacity(
        opacity: dimmed ? 0.45 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF2A1F14),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  blocked
                      ? Colors.green.withOpacity(.5)
                      : const Color(0xFF9B7B45).withOpacity(.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(11),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (imageUrl != null && imageUrl!.isNotEmpty)
                        MylNetworkImage(
                          imageUrl: imageUrl!,
                          fit: BoxFit.cover,
                          placeholder:
                              (_, __) => const Center(
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                          errorWidget:
                              (_, __, ___) => const Center(
                                child: Icon(
                                  Icons.image_not_supported_outlined,
                                  color: Colors.white38,
                                ),
                              ),
                        )
                      else
                        const Center(
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            color: Colors.white38,
                          ),
                        ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: IconButton(
                          tooltip: 'Ampliar carta',
                          onPressed: onPreview,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black.withOpacity(.72),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(34, 34),
                            padding: EdgeInsets.zero,
                          ),
                          icon: const Icon(
                            Icons.zoom_out_map_rounded,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.nombre,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (copies > 0)
                      Text(
                        '$copies/$limit',
                        style: TextStyle(
                          fontSize: 10,
                          color:
                              blocked ? Colors.green.shade300 : Colors.white54,
                          fontWeight: FontWeight.w700,
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

// ── Control de cantidad ────────────────────────────────────────────────────────

class _QtyRow extends StatelessWidget {
  final int value;
  final VoidCallback onDec;
  final VoidCallback onInc;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _QtyRow({
    required this.value,
    required this.onDec,
    required this.onInc,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _IconBtn(icon: Icons.remove_rounded, onPressed: onDec),
        GestureDetector(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '$value',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        _IconBtn(icon: Icons.add_rounded, onPressed: onInc),
        _IconBtn(
          icon: Icons.delete_outline_rounded,
          onPressed: onDelete,
          color: Colors.red.shade300,
        ),
      ],
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color? color;

  const _IconBtn({required this.icon, required this.onPressed, this.color});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 16, color: color ?? Colors.white70),
      ),
    );
  }
}

// ── Picker de cantidad ─────────────────────────────────────────────────────────

class _CountPicker extends StatelessWidget {
  final String title;
  final int current;
  final int max;
  final VoidCallback onDelete;

  const _CountPicker({
    required this.title,
    required this.current,
    required this.max,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 1; i <= max; i++) ...[
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor:
                          i == current
                              ? Theme.of(context).colorScheme.primary
                              : null,
                      foregroundColor: i == current ? Colors.white : null,
                    ),
                    onPressed: () => Navigator.pop(context, i),
                    child: Text('$i'),
                  ),
                  if (i < max) const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              label: const Text(
                'Quitar del mazo',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
