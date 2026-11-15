import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/card_myl.dart';
import '../../models/card_variant.dart';
import '../../data/pb_data.dart';
import '../../services/drive_service.dart';
import '../../widgets/drive_image_picker.dart';
import '../../utils/wallpaper_image.dart';
import '../../models/deck.dart';
import '../../utils/card_utils.dart';
import '../../services/deck_service.dart';
import '../../services/deck_poster_share_service.dart';
import '../../services/ban_list_service.dart';
import '../../domain/validation/deck_validator.dart';
import '../../domain/deck_coverage.dart';
import '../../domain/perfil_habilidades.dart';
import '../../domain/deck_stock_groups.dart';
import '../../domain/inventory_planner.dart';
import '../../domain/deck_statistics.dart';
import '../../models/inventory.dart';
import '../../models/ban_list_entry.dart' show normalizeBanListKey;
import '../../services/inventory_service.dart';
import '../../widgets/card_image.dart';
import '../../widgets/fill_decks_dialog.dart';
import '../../widgets/per_copy_variant_dialog.dart';
import '../../widgets/transfer_plan_checklist.dart';
import './create_deck_screen.dart';
import './deck_diff_dialog.dart' show showDeckDiffDialog, DeckVariationPair;
import './cards_catalog_screen.dart' show VariantThumbFromCard;

part 'deck_details/poster_export.dart';
part 'deck_details/stats.dart';
part 'deck_details/dialogs.dart';

class DeckDetailsScreen extends StatefulWidget {
  final Deck deck;

  const DeckDetailsScreen({super.key, required this.deck});

  @override
  State<DeckDetailsScreen> createState() => _DeckDetailsScreenState();
}

class _DeckDetailsScreenState extends State<DeckDetailsScreen> {
  Map<String, String?> _imgById = {};
  Map<String, CardMyL> _cardsById = {};
  Map<String, CardMyL> _cardsByNameLower = {};
  Map<String, String> _featureGroupMap = {};
  // variantId → imageFrontUrl (cargado lazy para variantes asignadas al mazo)
  Map<String, String> _variantImgById = {};
  // cardId -> imagen de la variante oficial (cache para el póster).
  final Map<String, String?> _officialImgById = {};
  List<InventoryItem> _inventory = const [];
  int _inventoryLoadGeneration = 0;
  late Deck _baseDeck;
  Deck? _haveDeck;
  Deck? _targetDeck;
  List<Deck> _ownerDecks = const [];
  // Variaciones de la misma raza+edición (excluyendo la actual)
  List<Deck> _raceVariants = const [];
  bool _showTarget = false;
  bool _loadingLinkedDeck = false;
  bool _uploadingCover = false;
  bool _exportingPoster = false;
  InventoryService? _inventoryService;
  late final BanListService _banListService = switch (widget.deck.format) {
    DeckFormat.racialLibre => BanListService.racialLibre(),
    DeckFormat.full => BanListService.full(),
    DeckFormat.racial => BanListService(),
  };
  Map<String, int> _copyLimitsByKey = const {};

  @override
  void initState() {
    super.initState();
    _baseDeck = widget.deck;
    _loadImgIndex();
    _loadFeatureGroupMap();
    _loadLinkedDeckContext();
    _loadBanList();
    _loadVariantImages(_baseDeck);
    _loadInventory();
  }

  Future<void> _loadBanList() async {
    try {
      final byKey = await _banListService.fetchCopyLimitsByKey();
      if (mounted) setState(() => _copyLimitsByKey = byKey);
    } catch (_) {
      // Sin ban list disponible: no se muestra aviso, no es bloqueante.
    }
  }

  /// Solo avisa (no bloquea): lista de mensajes si el mazo activo tiene
  /// cartas prohibidas o que superan el límite de copias de la Ban List.
  List<String> _banListWarnings(Deck deck) {
    if (_copyLimitsByKey.isEmpty) return const [];
    final result = validateDeck(
      deck: deck,
      catalogById: const {},
      catalogByName: const {},
      copyLimitsByKey: _copyLimitsByKey,
    );
    return result.issues
        .where((i) => i.code == 'BANNED_CARD' || i.code == 'COPIES_LIMIT')
        .map((i) => i.message)
        .toList();
  }

  Future<void> _loadImgIndex() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('cards').get();
      final mImg = <String, String?>{};
      final mCards = <String, CardMyL>{};
      final mByName = <String, CardMyL>{};

      for (final d in snap.docs) {
        // Un doc individual con datos inesperados no debe tumbar la carga
        // completa (eso vaciaba TODAS las imágenes ya mostradas de golpe).
        try {
          final data = d.data();
          final card = CardMyL.fromMap(data, d.id);
          final rawUrl =
              (data['officialImageUrl'] as String?) ??
              (data['imageUrl'] as String?);
          mImg[d.id] =
              rawUrl != null && rawUrl.trim().isNotEmpty
                  ? DriveService.webSafeUrl(rawUrl)
                  : null;
          mCards[d.id] = card;
          mByName[card.nombre.toLowerCase()] = card;
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _imgById = mImg;
        _cardsById = mCards;
        _cardsByNameLower = mByName;
      });

      // Fallback: para las cartas del mazo actual que quedaron SIN imagen oficial,
      // usar cualquier variante disponible con tal de mostrar algo.
      await _fillMissingOfficialWithVariant();
    } catch (_) {
      // Fetch completo fallido (red/timeout): mantener lo que ya estaba
      // cargado en vez de vaciar todo el catálogo de golpe.
    }
  }

  /// Para las cartas presentes en el mazo que no tienen `officialImageUrl`,
  /// busca la primera variante disponible (preferentemente la marcada como
  /// oficial) y la usa como imagen base. Así una carta sin variante asignada
  /// por copia igual muestra algo en lugar del ícono vacío.
  Future<void> _fillMissingOfficialWithVariant() async {
    final missing = <String>{};

    void collect(Deck? deck) {
      if (deck == null) return;
      for (final e in deck.cards) {
        final id = e.cardId;
        if (id == null || id.trim().isEmpty) continue;
        final existing = _imgById[id];
        if (existing == null || existing.trim().isEmpty) missing.add(id.trim());
      }
    }

    collect(_baseDeck);
    collect(_haveDeck);
    collect(_targetDeck);
    if (missing.isEmpty) return;

    final resolved = <String, String?>{};
    for (final id in missing) {
      final url = await _resolveAnyImageForCard(id);
      if (url != null) resolved[id] = url;
    }

    if (resolved.isEmpty || !mounted) return;
    setState(() => _imgById = {..._imgById, ...resolved});
  }

  Future<void> _loadVariantImages(Deck deck) async {
    // Collect all (cardId, variantId) pairs referenced in selectedVariants
    final toFetch = <String, Set<String>>{}; // cardId -> variantIds
    for (final e in deck.cards) {
      final cardId = e.cardId;
      if (cardId == null || cardId.isEmpty) continue;
      if (e.selectedVariants == null || e.selectedVariants!.isEmpty) continue;
      for (final vId in e.selectedVariants!) {
        if (vId.isEmpty || _variantImgById.containsKey(vId)) continue;
        toFetch.putIfAbsent(cardId, () => {}).add(vId);
      }
    }
    if (toFetch.isEmpty) return;

    final db = FirebaseFirestore.instance;
    final newUrls = <String, String>{};
    for (final entry in toFetch.entries) {
      final cardId = entry.key;
      for (final vId in entry.value) {
        try {
          final snap =
              await db
                  .collection('cards')
                  .doc(cardId)
                  .collection('variants')
                  .doc(vId)
                  .get();
          final url = (snap.data()?['imageFrontUrl'] as String?)?.trim();
          if (url != null && url.isNotEmpty) {
            newUrls[vId] = DriveService.webSafeUrl(url);
          }
        } catch (_) {}
      }
    }
    if (newUrls.isEmpty) return;
    if (!mounted) return;
    setState(() => _variantImgById = {..._variantImgById, ...newUrls});
  }

  Future<void> _loadInventory() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid != _baseDeck.ownerId) return;
    final generation = ++_inventoryLoadGeneration;
    try {
      final service = _inventoryService ??= InventoryService(uid);
      final inventory = await service.listInventory();
      // Una carga iniciada antes de guardar una variante no puede pisar el
      // resultado más reciente cuando termina fuera de orden.
      if (!mounted || generation != _inventoryLoadGeneration) return;
      setState(() {
        _inventory = inventory;
      });
      await _loadInventoryVariantImages(inventory);
    } catch (_) {
      // La configuración sigue visible aunque el inventario no cargue.
    }
  }

  Future<void> _loadInventoryVariantImages(
    List<InventoryItem> inventory,
  ) async {
    final db = FirebaseFirestore.instance;
    final urls = <String, String>{};
    for (final item in inventory) {
      final cardId = item.cardId;
      if (cardId == null || cardId.isEmpty) continue;
      final variantIds = <String>{
        ...item.variantAllocations.keys,
        ...item.reservations.values.map((value) => value.variantId),
      };
      for (final variantId in variantIds) {
        if (variantId.isEmpty || _variantImgById.containsKey(variantId)) {
          continue;
        }
        try {
          final snapshot =
              await db
                  .collection('cards')
                  .doc(cardId)
                  .collection('variants')
                  .doc(variantId)
                  .get();
          final url = (snapshot.data()?['imageFrontUrl'] ?? '').toString();
          if (url.trim().isNotEmpty) {
            urls[variantId] = DriveService.webSafeUrl(url);
          }
        } catch (_) {}
      }
    }
    if (mounted && urls.isNotEmpty) {
      setState(() => _variantImgById = {..._variantImgById, ...urls});
    }
  }

  Future<void> _loadFeatureGroupMap() async {
    try {
      final snap =
          await FirebaseFirestore.instance
              .collection('card_custom_features')
              .get();
      final featureGroupMap = <String, String>{};

      for (final doc in snap.docs) {
        final data = doc.data();
        final rawName =
            (data['name'] ?? data['nombre'] ?? '').toString().trim();
        if (rawName.isEmpty) continue;

        final rawGroup =
            (data['group'] ??
                    data['groupName'] ??
                    data['grupo'] ??
                    data['group_name'] ??
                    '')
                .toString()
                .trim();
        if (rawGroup.isEmpty) continue;

        featureGroupMap[rawName] = rawGroup;
        featureGroupMap[rawName.toLowerCase()] = rawGroup;

        final normalized =
            (data['normalized'] ?? data['name_normalized'] ?? '')
                .toString()
                .trim();
        if (normalized.isNotEmpty) {
          featureGroupMap[normalized] = rawGroup;
          featureGroupMap[normalized.toLowerCase()] = rawGroup;
        }
      }

      if (!mounted) return;
      setState(() {
        _featureGroupMap = featureGroupMap;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _featureGroupMap = {};
      });
    }
  }

  Future<void> _loadLinkedDeckContext() async {
    if (mounted) {
      setState(() {
        _loadingLinkedDeck = true;
      });
    }

    try {
      final ownerId = widget.deck.ownerId.trim();
      if (ownerId.isEmpty) {
        _applyLinkedDeckContext(const []);
        return;
      }

      final snap =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(ownerId)
              .collection('decks')
              .get();

      final decks =
          snap.docs
              .map((d) => Deck.fromMap({...d.data(), 'id': d.id}))
              .toList();

      _applyLinkedDeckContext(decks);
    } catch (_) {
      _applyLinkedDeckContext(const []);
    }
  }

  void _applyLinkedDeckContext(List<Deck> decks) {
    Deck? have;
    Deck? target;
    final current = _baseDeck;
    if (current.isUnified) {
      final variants =
          decks
              .where(
                (deck) =>
                    deck.isUnified &&
                    deck.id != current.id &&
                    deck.race == current.race &&
                    deck.edition == current.edition,
              )
              .toList();
      if (!mounted) return;
      setState(() {
        _ownerDecks = decks;
        _haveDeck = current;
        _targetDeck = null;
        _showTarget = false;
        _loadingLinkedDeck = false;
        _raceVariants = variants;
      });
      return;
    }
    final embeddedTarget =
        current.hasEmbeddedObjective
            ? current.copyWith(
              cards: current.objectiveCards,
              status: DeckStatus.published,
            )
            : null;

    if (current.isTarget) {
      target = current;
      for (final d in decks) {
        if (!d.isTarget &&
            (((d.linkedDeckId ?? '').trim() == current.id) ||
                _sameDeckIdentity(d, current))) {
          have = d;
          break;
        }
      }
    } else {
      have = current;
      target = embeddedTarget;
      if (target == null) {
        final linkedId = (current.linkedDeckId ?? '').trim();
        if (linkedId.isNotEmpty) {
          for (final d in decks) {
            if (d.id == linkedId) {
              target = d;
              break;
            }
          }
        }

        if (target == null) {
          for (final d in decks) {
            if (d.isTarget &&
                (_sameDeckIdentity(d, current) || d.id == linkedId)) {
              target = d;
              break;
            }
          }
        }
      }
    }

    // Detectar variaciones: mazos del mismo owner, misma raza y edición, no isTarget, id distinto al actual
    final currentRace = (current.race ?? '').trim().toLowerCase();
    final currentEdition = (current.edition ?? '').trim().toLowerCase();
    final variants =
        currentRace.isEmpty
            ? <Deck>[]
            : decks
                .where(
                  (d) =>
                      !d.isTarget &&
                      d.id != current.id &&
                      (d.race ?? '').trim().toLowerCase() == currentRace &&
                      (d.edition ?? '').trim().toLowerCase() == currentEdition,
                )
                .toList();

    if (!mounted) return;
    setState(() {
      _ownerDecks = decks;
      _haveDeck = have ?? (current.isTarget ? null : current);
      _targetDeck = target ?? (current.isTarget ? current : null);
      _showTarget = current.isTarget && _targetDeck != null;
      _loadingLinkedDeck = false;
      _raceVariants = variants;
    });
  }

  bool _sameDeckIdentity(Deck a, Deck b) {
    final aName = a.name.trim().toLowerCase();
    final bName = b.name.trim().toLowerCase();
    final aEdition = (a.edition ?? '').trim().toLowerCase();
    final bEdition = (b.edition ?? '').trim().toLowerCase();
    return aName.isNotEmpty && aName == bName && aEdition == bEdition;
  }

  Deck get _activeDeck {
    if (_showTarget && _targetDeck != null) return _targetDeck!;
    if (_haveDeck != null) return _haveDeck!;
    if (_targetDeck != null) return _targetDeck!;
    return widget.deck;
  }

  bool get _canToggleLinkedDeck => _haveDeck != null && _targetDeck != null;

  Future<void> _showPosterCardActions(_DeckVisualCard card) async {
    final deck = _activeDeck;
    final isCurrentCover =
        (deck.coverCardId ?? '').trim() == card.cardId.trim();

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF17110C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.crop_square_rounded,
                    color: Color(0xFFF1D184),
                  ),
                  title: Text(
                    isCurrentCover ? 'Cambiar portada' : 'Definir como portada',
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Se abrirá el recorte cuadrado para usar esta carta como portada.',
                    style: TextStyle(color: Colors.white60),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await _setCoverFromPosterCard(card);
                  },
                ),
                if (isCurrentCover)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.delete_outline,
                      color: Colors.white70,
                    ),
                    title: const Text(
                      'Quitar portada',
                      style: TextStyle(color: Colors.white),
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      await _clearDeckCover();
                    },
                  ),
                // Opción de variantes: solo si el usuario es dueño del mazo
                if (FirebaseAuth.instance.currentUser?.uid == deck.ownerId &&
                    card.cardId.isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.style_outlined,
                      color: Color(0xFF7EC8E3),
                    ),
                    title: const Text(
                      'Elegir versión por copia',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Solo cambia la imagen (póster y galería).',
                      style: TextStyle(color: Colors.white60),
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      await _showVariantPicker(card.cardId, card.name, deck);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Elige qué versión mostrar en cada copia (solo visual: póster y
  /// galería). No toca la colección: la versión no importa para saber si
  /// el mazo se puede completar. Copias sin versión usan la oficial.
  Future<void> _showVariantPicker(
    String cardId,
    String cardName,
    Deck deck,
  ) async {
    final entry = deck.cards.where((e) => e.cardId == cardId).firstOrNull;
    if (entry == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se encontró la carta en el mazo.')),
        );
      }
      return;
    }

    // Filtrar 'approved != false' en el cliente: isNotEqualTo excluiría
    // variantes antiguas que no tienen ese campo.
    List<CardVariant> variants = [];
    try {
      final snap =
          await FirebaseFirestore.instance
              .collection('cards')
              .doc(cardId)
              .collection('variants')
              .get();
      variants =
          snap.docs
              .where((d) => d.data()['approved'] != false)
              .map((d) => CardVariant.fromMap(d.data(), d.id))
              .toList();
    } catch (_) {}
    if (!mounted) return;
    if (variants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esta carta no tiene versiones cargadas.'),
        ),
      );
      return;
    }

    final newVariants = await showDialog<List<String?>>(
      context: context,
      builder:
          (_) => PerCopyVariantDialog(
            title: cardName,
            subtitle:
                'Elige la versión que se muestra en cada copia. '
                'Sin elegir se usa la oficial.',
            count: entry.count,
            variants: variants,
            currentSelection: entry.selectedVariants ?? const [],
            availableByVariant: {for (final v in variants) v.id: entry.count},
            unidentifiedAvailable: entry.count,
          ),
    );
    if (newVariants == null || !mounted) return;

    final updatedDeck = deck.copyWith(
      cards:
          deck.cards
              .map(
                (e) =>
                    identical(e, entry)
                        ? e.copyWith(
                          selectedVariants:
                              newVariants.map((id) => id ?? '').toList(),
                        )
                        : e,
              )
              .toList(),
      updatedAt: DateTime.now(),
    );
    try {
      await DeckService(deck.ownerId).save(updatedDeck);
      if (!mounted) return;
      _replaceLocalDeck(updatedDeck);
      await _loadVariantImages(updatedDeck);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    }
  }

  /// Se abre al tocar una copia gris (no disponible) de una carta del mazo
  /// principal o del side deck: "¿cuántas tienes y de qué versión?". Agrega
  /// esas copias al inventario, completa este mazo primero, y reparte el
  /// sobrante a otros mazos que la necesiten — sin tener que ir a
  /// /inventario y repetir el flujo de agregar + rellenar por separado.
  Future<void> _addOwnedCopiesFor({
    required String cardId,
    required String name,
    String? type,
    String? edition,
  }) async {
    final deck = _activeDeck;
    if (FirebaseAuth.instance.currentUser?.uid != deck.ownerId) return;
    if (cardId.isEmpty) return;
    // Si no vino la edición explícita, resolverla del catálogo oficial —
    // sin esto la carta quedaba guardada en el inventario como "Sin
    // edición" aunque la carta sí tuviera una definida.
    final resolvedEdition = edition ?? _cardsById[cardId]?.edicion;

    List<CardVariant> variants = [];
    try {
      final snap =
          await FirebaseFirestore.instance
              .collection('cards')
              .doc(cardId)
              .collection('variants')
              .get();
      variants =
          snap.docs
              .where((d) => d.data()['approved'] != false)
              .map((d) => CardVariant.fromMap(d.data(), d.id))
              .where((v) => (v.imageFrontUrl ?? '').isNotEmpty)
              .toList();
    } catch (_) {}
    if (!mounted) return;

    final service = _inventoryService ??= InventoryService(deck.ownerId);
    final existingItem =
        (await service.listInventory())
            .where((i) => i.key == inventoryKey(cardId: cardId, name: name))
            .firstOrNull;
    final holding = describeExistingHolding(
      item: existingItem,
      deckNames: {
        for (final d in _ownerDecks) d.id: d.name,
        deck.id: deck.name,
        ...deckStockTargetLabels([..._ownerDecks, deck]),
      },
    );
    if (!mounted) return;

    final quantityByVariant = await showDialog<Map<String, int>>(
      context: context,
      builder:
          (_) => _AddOwnedCopiesDialog(
            cardName: name,
            variants: variants,
            holding: holding,
          ),
    );
    if (quantityByVariant == null || !mounted) return;

    try {
      final result = await service.addCardsHere(
        target: deck,
        cardId: cardId,
        name: name,
        type: type,
        edition: resolvedEdition,
        quantityByVariant: quantityByVariant,
      );
      if (!mounted) return;

      if (result.ambiguous.isNotEmpty) {
        final selection = await showDialog<Map<String, List<(String, int)>>>(
          context: context,
          builder:
              (_) => FillDecksDialog(
                assignments: result.ambiguous,
                title: 'Varios mazos necesitan el sobrante',
              ),
        );
        if (selection != null && mounted) {
          await service.applyFreeStockSelection(selection);
        }
      }

      await _loadInventory();
      await _loadImgIndex();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.addedHere > 0
                  ? '${result.addedHere} copia${result.addedHere == 1 ? '' : 's'} asignada${result.addedHere == 1 ? '' : 's'} a ${deck.name}.'
                  : 'Copias agregadas a tu inventario.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo agregar: $e')));
      }
    }
  }

  /// Se abre al tocar una copia YA asignada (disponible) de una carta:
  /// "en realidad no tengo tantas". A diferencia del editor de cantidad de
  /// /inventario, esto sí puede bajar por debajo de lo asignado — le quita
  /// primero a este mazo (ver [InventoryService.correctOwnedQuantity]).
  Future<void> _correctOwnedQuantityFor({
    required String cardId,
    required String name,
  }) async {
    final deck = _activeDeck;
    if (FirebaseAuth.instance.currentUser?.uid != deck.ownerId) return;
    if (cardId.isEmpty) return;

    final service = _inventoryService ??= InventoryService(deck.ownerId);
    final key = inventoryKey(cardId: cardId, name: name);
    final item =
        (await service.listInventory()).where((i) => i.key == key).firstOrNull;
    if (!mounted) return;
    if (item == null || item.total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No hay copias registradas de $name.')),
      );
      return;
    }

    final newTotal = await showDialog<int>(
      context: context,
      builder: (_) => _CorrectQuantityDialog(cardName: name, item: item),
    );
    if (newTotal == null || newTotal == item.total || !mounted) return;

    try {
      await service.correctOwnedQuantity(
        item,
        newTotal,
        preferredDeckId: deck.id,
      );
      await _loadInventory();
      await _loadImgIndex();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$name actualizado a $newTotal copia${newTotal == 1 ? '' : 's'}.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo corregir: $e')));
      }
    }
  }

  Future<void> _correctOwnedQuantity(_DeckVisualCard card) =>
      _correctOwnedQuantityFor(cardId: card.cardId, name: card.name);

  Future<void> _setCoverFromPosterCard(_DeckVisualCard card) async {
    if (_uploadingCover) return;
    if (card.imageUrl.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se encontró imagen para esa carta.'),
          ),
        );
      }
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    final deck = _activeDeck;
    if (user == null || user.uid != deck.ownerId) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Solo puedes editar la portada de tus propios mazos.',
            ),
          ),
        );
      }
      return;
    }

    setState(() => _uploadingCover = true);
    try {
      final response = await http.get(Uri.parse(card.imageUrl));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('No se pudo descargar la imagen.');
      }

      final crop = await showDialog<_CropSelectionResult>(
        context: context,
        barrierDismissible: false,
        builder:
            (_) => _SquareCropDialog(
              sourceBytes: response.bodyBytes,
              title: 'Recortar portada',
            ),
      );

      if (crop == null || !mounted) return;

      final coverUrl = card.imageUrl;

      if (coverUrl.isEmpty) {
        throw Exception('No se pudo generar la portada.');
      }

      final updatedDeck = deck.copyWith(
        coverUrl: coverUrl,
        coverCardId: card.cardId,
        updatedAt: DateTime.now(),
      );
      await DeckService(deck.ownerId).save(updatedDeck);
      _replaceLocalDeck(updatedDeck);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Portada actualizada con "${card.name}".')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo crear la portada: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingCover = false);
      }
    }
  }

  Future<void> _clearDeckCover() async {
    final deck = _activeDeck;
    final updatedDeck = deck.copyWith(
      coverUrl: '',
      coverCardId: '',
      updatedAt: DateTime.now(),
    );
    await DeckService(deck.ownerId).save(updatedDeck);
    _replaceLocalDeck(updatedDeck);
  }

  void _replaceLocalDeck(Deck updatedDeck) {
    setState(() {
      if (_baseDeck.id == updatedDeck.id) {
        _baseDeck = updatedDeck;
      }
      _ownerDecks =
          _ownerDecks
              .map((d) => d.id == updatedDeck.id ? updatedDeck : d)
              .toList();
      if (_haveDeck?.id == updatedDeck.id) {
        _haveDeck = updatedDeck;
      }
      if (_targetDeck?.id == updatedDeck.id) {
        _targetDeck = updatedDeck;
      }
    });
  }

  // _normTipo → normalizeTipoLoose (card_utils.dart)

  int _typeSortRank(String tipo) {
    switch (tipo) {
      case 'aliado':
        return 0;
      case 'talisman':
        return 1;
      case 'arma':
        return 2;
      case 'totem':
        return 3;
      case 'oro':
        return 4;
      case 'descendiente':
        return 5;
      default:
        return 10;
    }
  }

  String? _entryId(dynamic entry) {
    try {
      final v = (entry as dynamic).cardId;
      if (v != null) return v.toString();
    } catch (_) {}
    try {
      final v = (entry as dynamic).id;
      if (v != null) return v.toString();
    } catch (_) {}
    return null;
  }

  String? _entryName(dynamic entry) {
    try {
      final v = (entry as dynamic).name;
      if (v is String && v.isNotEmpty) return v;
    } catch (_) {}
    try {
      final v = (entry as dynamic).nombre;
      if (v is String && v.isNotEmpty) return v;
    } catch (_) {}
    return null;
  }

  List<_DeckVisualCard> _visualCards(Deck deck) {
    final Map<String, _DeckVisualCard> grouped = {};
    final decksById = {for (final value in _ownerDecks) value.id: value};
    decksById.putIfAbsent(deck.id, () => deck);
    // Orden estable y determinista (no hay ranking manual): solo se usa
    // para sanear asignaciones legado inconsistentes de forma consistente,
    // ver inventoryCappedByDeckPriority.
    final orderedDecks =
        decksById.values.toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final effectiveInventory = inventoryCappedByDeckPriority(
      inventory: _inventory,
      orderedDecks: orderedDecks,
    );
    final coverage = calculateDeckCoverage(
      deck: deck,
      inventory: effectiveInventory,
    );
    final coverageByKey = {
      for (final item in coverage.cards) entryInventoryKey(item.card): item,
    };
    final consumedByKey = <String, int>{};

    for (final e in deck.cards) {
      CardMyL? card;
      final maybeId = _entryId(e);
      if (maybeId != null) {
        card = _cardsById[maybeId];
      }
      card ??= _cardsByNameLower[_entryName(e)?.toLowerCase() ?? ''];

      final cid = maybeId ?? e.name;
      final baseUrl = (maybeId != null ? _imgById[maybeId] : null) ?? '';
      final key = entryInventoryKey(e);
      final cardCoverage = coverageByKey[key];
      final consumed = consumedByKey[key] ?? 0;
      final copyCoverage =
          cardCoverage?.copies.skip(consumed).take(e.count).toList() ??
          const <DeckCopyCoverage>[];
      consumedByKey[key] = consumed + e.count;
      final copyStates = List<DeckCopyState>.generate(
        e.count,
        (index) =>
            index < copyCoverage.length
                ? copyCoverage[index].state
                : DeckCopyState.missing,
      );
      final copyNeedsIdentification = List<bool>.generate(
        e.count,
        (index) =>
            index < copyCoverage.length &&
            copyCoverage[index].needsVariantIdentification,
      );

      // Construir variantUrls: una URL por copia (index = número de copia).
      // Copia física identificada → variante elegida en el mazo → vacío
      // (sin variante definida: se usa la versión oficial, ver
      // _DeckVisualCard.fallbackUrl).
      final selected = e.selectedVariants ?? const <String>[];
      final variantUrls = List<String>.generate(e.count, (i) {
        if (i < copyCoverage.length) {
          final physicalVariant = copyCoverage[i].variantId;
          final physicalUrl = _variantImgById[physicalVariant];
          if (physicalUrl != null && physicalUrl.isNotEmpty) return physicalUrl;
        }
        if (i < selected.length) {
          final selectedUrl = _variantImgById[selected[i]];
          if (selectedUrl != null && selectedUrl.isNotEmpty) return selectedUrl;
        }
        return '';
      });

      // Imagen principal: la de la primera copia (copia frontal visible)
      final primaryUrl =
          variantUrls.isNotEmpty && variantUrls[0].isNotEmpty
              ? variantUrls[0]
              : baseUrl;

      final existing = grouped[cid];
      if (existing != null) {
        // Agregar copias (merge de entries con mismo cardId)
        grouped[cid] = _DeckVisualCard(
          cardId: existing.cardId,
          name: existing.name,
          tipo: existing.tipo,
          count: existing.count + e.count,
          cost: existing.cost,
          imageUrl: existing.imageUrl,
          fallbackUrl: existing.fallbackUrl,
          variantUrls: [...existing.variantUrls, ...variantUrls],
          copyStates: [...existing.copyStates, ...copyStates],
          copyNeedsIdentification: [
            ...existing.copyNeedsIdentification,
            ...copyNeedsIdentification,
          ],
        );
      } else {
        grouped[cid] = _DeckVisualCard(
          cardId: cid,
          name: e.name,
          tipo: normalizeTipoLoose(e.tipo ?? card?.tipo),
          count: e.count,
          cost: e.coste ?? card?.coste ?? 0,
          imageUrl: primaryUrl,
          fallbackUrl: baseUrl,
          variantUrls: variantUrls,
          copyStates: copyStates,
          copyNeedsIdentification: copyNeedsIdentification,
        );
      }
    }

    final items = grouped.values.toList();

    items.sort((a, b) {
      final typeCmp = _typeSortRank(a.tipo).compareTo(_typeSortRank(b.tipo));
      if (typeCmp != 0) return typeCmp;
      final countCmp = b.count.compareTo(a.count);
      if (countCmp != 0) return countCmp;
      final costCmp = b.cost.compareTo(a.cost);
      if (costCmp != 0) return costCmp;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return items;
  }

  String _cardEntryKey(DeckCardEntry entry) {
    final name = entry.name.trim();
    return normalizeBanListKey(name.isNotEmpty ? name : (entry.cardId ?? ''));
  }

  DeckCardEntry _entryFromCard(CardMyL card, {int count = 1}) => DeckCardEntry(
    cardId: card.id,
    name: card.nombre,
    count: count,
    coste: card.coste,
    tipo: card.tipo,
    rareza: card.rareza,
    edicion: card.edicion,
    soloLibre: card.soloLibre,
    unica: card.unica,
  );

  List<DeckCardEntry> _changeEntryCount(
    List<DeckCardEntry> entries,
    DeckCardEntry card,
    int delta,
  ) {
    final result = [...entries];
    final key = _cardEntryKey(card);
    final index = result.indexWhere((entry) => _cardEntryKey(entry) == key);
    if (index < 0) {
      if (delta > 0) result.add(card.copyWith(count: delta));
      return result;
    }
    final next = result[index].count + delta;
    if (next <= 0) {
      result.removeAt(index);
    } else {
      result[index] = result[index].copyWith(count: next);
    }
    return result;
  }

  bool _cardAllowedInSideboard(CardMyL card, Deck deck) {
    if (deck.format == DeckFormat.full) return true;
    final type = normalizeTipoLoose(card.tipo);
    if (deck.format == DeckFormat.racial) {
      if (card.soloLibre) return false;
      if ((deck.edition ?? '').trim().isNotEmpty &&
          card.edicion.trim().toLowerCase() !=
              deck.edition!.trim().toLowerCase()) {
        return false;
      }
    }
    if (type == 'aliado' && (deck.race ?? '').trim().isNotEmpty) {
      return (card.raza ?? '').trim().toLowerCase() ==
          deck.race!.trim().toLowerCase();
    }
    return true;
  }

  int _configuredCopies(Deck deck, CardMyL card) => [
        ...deck.cards,
        ...deck.sideboardCards,
      ]
      .where(
        (entry) => _cardEntryKey(entry) == _cardEntryKey(_entryFromCard(card)),
      )
      .fold(0, (sum, entry) => sum + entry.count);

  int _copyLimitForSideboard(CardMyL card) {
    final limit =
        _copyLimitsByKey[normalizeBanListKey(card.id)] ??
        _copyLimitsByKey[normalizeBanListKey(card.nombre)] ??
        3;
    return card.unica ? limit.clamp(0, 1) : limit.clamp(0, 3);
  }

  Future<bool> _saveDeckChange(Deck previous, Deck updated) async {
    _replaceLocalDeck(updated);
    try {
      await DeckService(updated.ownerId).save(updated);
      return true;
    } catch (error) {
      _replaceLocalDeck(previous);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar el side deck: $error')),
        );
      }
      return false;
    }
  }

  Future<void> _addToSideboard(CardMyL card) async {
    final deck = _activeDeck;
    if (FirebaseAuth.instance.currentUser?.uid != deck.ownerId) return;
    final sideTotal = deck.sideboardCards.fold<int>(
      0,
      (sum, entry) => sum + entry.count,
    );
    if (sideTotal >= 10 ||
        _configuredCopies(deck, card) >= _copyLimitForSideboard(card)) {
      return;
    }
    final updated = deck.copyWith(
      sideboardCards: _changeEntryCount(
        deck.sideboardCards,
        _entryFromCard(card),
        1,
      ),
      updatedAt: DateTime.now(),
    );
    await _saveDeckChange(deck, updated);
  }

  Future<void> _removeFromSideboard(DeckCardEntry card) async {
    final deck = _activeDeck;
    if (FirebaseAuth.instance.currentUser?.uid != deck.ownerId) return;
    final updated = deck.copyWith(
      sideboardCards: _changeEntryCount(deck.sideboardCards, card, -1),
      updatedAt: DateTime.now(),
    );
    await _saveDeckChange(deck, updated);
  }

  Future<void> _swapWithSideboard(
    _DeckVisualCard mainCard,
    DeckCardEntry sideCard,
  ) async {
    final deck = _activeDeck;
    if (FirebaseAuth.instance.currentUser?.uid != deck.ownerId) return;
    final mainIndex = deck.cards.indexWhere(
      (entry) =>
          ((entry.cardId ?? '').trim().isNotEmpty &&
              entry.cardId!.trim() == mainCard.cardId.trim()) ||
          entry.name.trim().toLowerCase() == mainCard.name.trim().toLowerCase(),
    );
    if (mainIndex < 0 ||
        !deck.sideboardCards.any(
          (entry) => _cardEntryKey(entry) == _cardEntryKey(sideCard),
        )) {
      return;
    }
    final outgoing = deck.cards[mainIndex];
    var main = _changeEntryCount(deck.cards, outgoing, -1);
    main = _changeEntryCount(main, sideCard, 1);
    var side = _changeEntryCount(deck.sideboardCards, sideCard, -1);
    side = _changeEntryCount(side, outgoing, 1);
    final updated = deck.copyWith(
      cards: main,
      sideboardCards: side,
      updatedAt: DateTime.now(),
    );
    await _saveDeckChange(deck, updated);
  }

  List<_SideboardVisualEntry> _sideboardVisualEntries(Deck deck) {
    return deck.sideboardCards.map((entry) {
      final card = entry.cardId == null ? null : _cardsById[entry.cardId];
      final url =
          (entry.cardId == null ? null : _imgById[entry.cardId]) ??
          card?.bestVariant?.imageFrontUrl ??
          '';
      return _SideboardVisualEntry(entry: entry, imageUrl: url);
    }).toList();
  }

  Future<void> _showSideboardCatalog() async {
    if (FirebaseAuth.instance.currentUser?.uid != _activeDeck.ownerId) return;
    final search = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF17110C),
      builder:
          (sheetContext) => StatefulBuilder(
            builder: (context, setSheetState) {
              final deck = _activeDeck;
              final query = search.text.trim().toLowerCase();
              final sideTotal = deck.sideboardCards.fold<int>(
                0,
                (sum, entry) => sum + entry.count,
              );
              final cards =
                  _cardsById.values
                      .where((card) => _cardAllowedInSideboard(card, deck))
                      .where(
                        (card) =>
                            query.isEmpty ||
                            card.nombre.toLowerCase().contains(query) ||
                            card.tipo.toLowerCase().contains(query),
                      )
                      .toList()
                    ..sort((a, b) => a.nombre.compareTo(b.nombre));
              return SafeArea(
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * .82,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Agregar al side deck · $sideTotal/10',
                                style: Theme.of(
                                  context,
                                ).textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(sheetContext),
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: search,
                          autofocus: true,
                          onChanged: (_) => setSheetState(() {}),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Buscar carta',
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.builder(
                          itemCount: cards.length,
                          itemBuilder: (context, index) {
                            final card = cards[index];
                            final configured = _configuredCopies(deck, card);
                            final limit = _copyLimitForSideboard(card);
                            final blocked =
                                sideTotal >= 10 || configured >= limit;
                            final image =
                                _imgById[card.id] ??
                                card.bestVariant?.imageFrontUrl;
                            return ListTile(
                              leading: SizedBox(
                                width: 42,
                                height: 58,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(5),
                                  child: MylCardImage(
                                    url: image,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              title: Text(
                                card.nombre,
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                '${card.tipo} · $configured/$limit configuradas',
                                style: const TextStyle(color: Colors.white60),
                              ),
                              trailing: IconButton(
                                onPressed:
                                    blocked
                                        ? null
                                        : () async {
                                          await _addToSideboard(card);
                                          if (sheetContext.mounted) {
                                            setSheetState(() {});
                                          }
                                        },
                                icon: const Icon(Icons.add_circle_outline),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
    );
    search.dispose();
  }

  Map<String, int> _countByType(Deck d) {
    final agg = <String, int>{};
    for (final e in d.cards) {
      final k = normalizeTipoLoose(e.tipo);
      agg[k] = (agg[k] ?? 0) + e.count;
    }
    return agg;
  }

  Map<int, int> _goldCurve(Deck d, {int maxCost = 5}) {
    final curve = {for (var i = 0; i <= maxCost; i++) i: 0};
    for (final e in d.cards) {
      if (normalizeTipoLoose(e.tipo) == 'oro') continue;
      final c = e.coste ?? 0;
      final bin = c < 0 ? 0 : (c > maxCost ? maxCost : c);
      curve[bin] = (curve[bin] ?? 0) + e.count;
    }
    return curve;
  }

  int _totalCards(Deck d) => d.cards.fold<int>(0, (s, e) => s + e.count);

  Future<void> _editDeck(Deck deck) async {
    final startInObjectiveMode =
        _canToggleLinkedDeck && _showTarget && _haveDeck != null;
    final updatedDeck = await Navigator.push<Deck>(
      context,
      MaterialPageRoute(
        builder:
            (_) => CreateDeckScreen(
              editDeck: _haveDeck ?? deck,
              startInObjectiveMode: startInObjectiveMode,
            ),
      ),
    );
    if (!mounted) return;
    if (updatedDeck != null) {
      _replaceLocalDeck(updatedDeck);
    } else {
      setState(() {});
    }
    await _loadLinkedDeckContext();
    await _loadImgIndex();
  }

  /// Elimina el mazo (previa confirmación) y vuelve a Mis Mazos. Las copias
  /// asignadas vuelven a quedar libres en la colección.
  Future<void> _deleteDeck() async {
    final deck = _baseDeck;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Eliminar mazo'),
            content: Text(
              'Se eliminará "${deck.name}" y sus copias volverán a tu colección. '
              'Esta acción no se puede deshacer.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await DeckService(deck.ownerId).delete(deck.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Mazo "${deck.name}" eliminado.')));
      context.go('/mazos');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo eliminar: $e')));
    }
  }

  /// Resuelve una URL de imagen para un cardId usando la misma cascada del
  /// catálogo (official → base → primera variante). Devuelve null si no hay.
  Future<String?> _resolveAnyImageForCard(String cardId) async {
    if (cardId.trim().isEmpty) return null;
    try {
      final col = FirebaseFirestore.instance
          .collection('cards')
          .doc(cardId)
          .collection('variants');
      var snap = await col.where('official', isEqualTo: true).limit(1).get();
      if (snap.docs.isEmpty) snap = await col.limit(1).get();
      if (snap.docs.isEmpty) return null;
      final raw = (snap.docs.first.data()['imageFrontUrl'] as String?)?.trim();
      if (raw == null || raw.isEmpty) return null;
      return DriveService.webSafeUrl(raw);
    } catch (_) {
      return null;
    }
  }

  /// Imagen de la variante marcada como oficial de [cardId] (con
  /// webSafeUrl aplicado). Si la carta no tiene variante oficial cae a la
  /// cascada general de [_resolveAnyImageForCard].
  Future<String?> _officialImageForCard(String cardId) async {
    final id = cardId.trim();
    if (id.isEmpty) return null;
    if (_officialImgById.containsKey(id)) return _officialImgById[id];
    String? url;
    try {
      final snap =
          await FirebaseFirestore.instance
              .collection('cards')
              .doc(id)
              .collection('variants')
              .where('official', isEqualTo: true)
              .limit(1)
              .get();
      if (snap.docs.isNotEmpty) {
        final raw =
            (snap.docs.first.data()['imageFrontUrl'] as String?)?.trim();
        if (raw != null && raw.isNotEmpty) url = DriveService.webSafeUrl(raw);
      }
    } catch (_) {}
    url ??= await _resolveAnyImageForCard(id);
    _officialImgById[id] = url;
    return url;
  }

  /// Prepara las cartas para el póster: cada copia sin variante definida
  /// (ni física ni elegida en el mazo) usa la versión oficial de la carta.
  Future<List<_DeckVisualCard>> _resolveCardsForExport(
    List<_DeckVisualCard> cards,
  ) async {
    final officials = await Future.wait(
      cards.map((c) => _officialImageForCard(c.cardId)),
    );
    final out = <_DeckVisualCard>[];
    for (var index = 0; index < cards.length; index++) {
      final c = cards[index];
      final official =
          (officials[index] ?? '').trim().isNotEmpty
              ? officials[index]!
              : (c.fallbackUrl.trim().isNotEmpty ? c.fallbackUrl : c.imageUrl);
      final copies = c.count > 0 ? c.count : 1;
      final variantUrls = List<String>.generate(copies, (i) {
        final defined = i < c.variantUrls.length ? c.variantUrls[i] : '';
        return defined.trim().isNotEmpty ? defined : official;
      });
      out.add(
        _DeckVisualCard(
          cardId: c.cardId,
          name: c.name,
          tipo: c.tipo,
          count: c.count,
          cost: c.cost,
          imageUrl: variantUrls.first,
          fallbackUrl: official,
          variantUrls: variantUrls,
          copyStates: c.copyStates,
          copyNeedsIdentification: c.copyNeedsIdentification,
        ),
      );
    }
    return out;
  }

  Future<void> _exportDeckPoster() async {
    if (_exportingPoster) return;

    final deck = _activeDeck;
    final cards = await _resolveCardsForExport(_visualCards(deck));
    final byType = _countByType(deck);
    final curve = _goldCurve(deck);
    final total = _totalCards(deck);
    final raceLabel =
        (deck.race ?? '').trim().isEmpty ? 'Sin raza' : deck.race!.trim();
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: !_exportingPoster,
        builder:
            (_) => _DeckPdfPreviewDialog(
              deckName: deck.name,
              edition: deck.edition ?? 'Sin edicion',
              raceLabel: raceLabel,
              totalCards: total,
              cards: cards,
              byType: byType,
              curve: curve,
              onExport: (posterBytes) async {
                if (!mounted) return;
                setState(() => _exportingPoster = true);
                try {
                  await DeckPosterShareService.sharePosterPng(
                    posterBytes: posterBytes,
                    deckName: deck.name,
                  );
                } finally {
                  if (mounted) {
                    setState(() => _exportingPoster = false);
                  }
                }
              },
            ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo exportar la imagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _exportingPoster = false);
    }
  }

  // ── Compartir link del mazo (#10) ─────────────────────────────────────────
  Future<void> _shareDeckLink() async {
    final deck = _activeDeck;
    final url = 'https://mylmazos.web.app/mazo/${deck.ownerId}/${deck.id}';
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('🔗 Link copiado: $url')));
  }

  // ── Copiar lista en texto (#11 export) ────────────────────────────────────
  Future<void> _copyDeckList() async {
    final deck = _activeDeck;
    final buf =
        StringBuffer()..writeln(
          '// ${deck.name} — ${deck.race ?? ''} ${deck.edition ?? ''}'.trim(),
        );
    final sorted = [...deck.cards]..sort((a, b) {
      final t = normalizeTipoLoose(
        a.tipo,
      ).compareTo(normalizeTipoLoose(b.tipo));
      if (t != 0) return t;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    for (final e in sorted) {
      buf.writeln('${e.count}x ${prettyCardName(e.name)}');
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('📋 Lista copiada al portapapeles')),
    );
  }

  // ── Simulador de mano inicial (#13) ───────────────────────────────────────
  void _showHandSimulator() {
    final deck = _activeDeck;
    // Pool: cada copia es una carta (excluimos oros del robo inicial no,
    // en MyL el mazo completo se baraja — incluimos todo).
    final pool = <MapEntry<String, String>>[]; // (nombre, url)
    for (final e in deck.cards) {
      final url =
          ((e.cardId ?? '').isNotEmpty ? _imgById[e.cardId] : null) ?? '';
      for (var i = 0; i < e.count; i++) {
        pool.add(MapEntry(e.name, url));
      }
    }
    if (pool.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('El mazo no tiene cartas')));
      return;
    }
    showDialog<void>(
      context: context,
      builder: (_) => _HandSimulatorDialog(pool: pool),
    );
  }

  // ── Registro de partidas (#14) ────────────────────────────────────────────
  Future<void> _registerMatch() async {
    final deck = _activeDeck;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid != deck.ownerId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solo el dueño puede registrar partidas')),
      );
      return;
    }

    final result = await showDialog<_MatchResult>(
      context: context,
      builder: (_) => _RegisterMatchDialog(deck: deck),
    );
    if (result == null || !mounted) return;

    final isWin = result.won;
    final deckRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('decks')
        .doc(deck.id);

    try {
      final batch = FirebaseFirestore.instance.batch();
      batch.set(deckRef, {
        'games': FieldValue.increment(1),
        'wins': FieldValue.increment(isWin ? 1 : 0),
        'losses': FieldValue.increment(isWin ? 0 : 1),
        if (result.score == '2-0') 'winsBy20': FieldValue.increment(1),
        if (result.score == '2-1') 'winsBy21': FieldValue.increment(1),
        if (result.score == '0-2') 'lossesBy02': FieldValue.increment(1),
        if (result.score == '1-2') 'lossesBy12': FieldValue.increment(1),
        'lastMatchAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
      batch.set(deckRef.collection('match_logs').doc(), {
        'result': isWin ? 'win' : 'loss',
        'score': result.score,
        'opponentRace': result.opponentRace,
        'notes': result.notes,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();

      // Refrescar el mazo local con los contadores nuevos.
      _replaceLocalDeck(
        deck.copyWith(
          games: deck.games + 1,
          wins: deck.wins + (isWin ? 1 : 0),
          losses: deck.losses + (isWin ? 0 : 1),
          lastMatchAt: DateTime.now(),
        ),
      );

      if (!mounted) return;
      final updated = _activeDeck;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isWin
                ? '🏆 Victoria registrada — ${updated.wins}W/${updated.losses}L (${updated.winRateLabel})'
                : '💀 Derrota registrada — ${updated.wins}W/${updated.losses}L (${updated.winRateLabel})',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al registrar: $e')));
    }
  }

  void _showDeckStats() {
    final stats = _DeckStatsSnapshot.fromDeck(
      _activeDeck,
      cardsById: _cardsById,
      cardsByNameLower: _cardsByNameLower,
      featureGroupMap: _featureGroupMap,
      imgById: _imgById,
    );
    showDialog<void>(
      context: context,
      builder: (_) => _DeckStatsDialog(stats: stats),
    );
  }

  void _showCardDetails(
    BuildContext context,
    _DeckVisualCard visualCard,
    String heroTag,
  ) {
    CardMyL? card = _cardsById[visualCard.cardId];
    if (card == null) {
      final norm = visualCard.name.toLowerCase().trim();
      card = _cardsByNameLower[norm];
    }

    showGeneralDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.85),
      barrierDismissible: true,
      barrierLabel: 'Cerrar',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder:
          (context, animation, secondaryAnimation) => _CardZoomDialog(
            visualCard: visualCard,
            fullCard: card,
            heroTag: heroTag,
          ),
      transitionBuilder: (context, a1, a2, child) {
        return FadeTransition(opacity: a1, child: child);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final deck = _activeDeck;
    // Cada mazo se muestra tal cual, sin combinar con variaciones (sin pool).
    final cards = _visualCards(deck);
    final byType = _countByType(deck);
    final curve = _goldCurve(deck);
    final total = _totalCards(deck);
    final stats = _DeckStatsSnapshot.fromDeck(
      deck,
      cardsById: _cardsById,
      cardsByNameLower: _cardsByNameLower,
      featureGroupMap: _featureGroupMap,
      imgById: _imgById,
    );
    final isWide = MediaQuery.of(context).size.width >= 1180;
    final raceLabel =
        (deck.race ?? '').trim().isEmpty ? 'Sin raza' : deck.race!.trim();
    final banListWarnings = _banListWarnings(deck);
    final canEditDeck = FirebaseAuth.instance.currentUser?.uid == deck.ownerId;

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/mazos');
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF060608),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: 'Volver a Mis Mazos',
            onPressed: () => context.go('/mazos'),
            icon: const Icon(Icons.arrow_back),
          ),
          backgroundColor: Colors.black.withOpacity(.35),
          title: Text(
            deck.name.isEmpty
                ? 'Viendo mazo'
                : () {
                  if (!_showTarget && _targetDeck != null) {
                    final have = cards.fold<int>(0, (s, c) => s + c.count);
                    final need = _totalCards(_targetDeck!);
                    return '${deck.name}  $have/$need';
                  }
                  return '${deck.name} ($total cartas)';
                }(),
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: 'Exportar PNG',
              onPressed: _exportingPoster ? null : _exportDeckPoster,
              icon:
                  _exportingPoster
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.image_outlined),
            ),
            IconButton(
              tooltip: 'Editar',
              onPressed: () => _editDeck(deck),
              icon: const Icon(Icons.edit_outlined),
            ),
            PopupMenuButton<String>(
              tooltip: 'Más acciones',
              icon: const Icon(Icons.more_vert),
              onSelected: (v) {
                switch (v) {
                  case 'share':
                    _shareDeckLink();
                  case 'copy':
                    _copyDeckList();
                  case 'hand':
                    _showHandSimulator();
                  case 'match':
                    _registerMatch();
                  case 'delete':
                    _deleteDeck();
                }
              },
              itemBuilder:
                  (_) => [
                    const PopupMenuItem(
                      value: 'share',
                      child: ListTile(
                        leading: Icon(Icons.link_rounded),
                        title: Text('Compartir link'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'copy',
                      child: ListTile(
                        leading: Icon(Icons.copy_all_rounded),
                        title: Text('Copiar lista'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'hand',
                      child: ListTile(
                        leading: Icon(Icons.back_hand_rounded),
                        title: Text('Mano de prueba'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'match',
                      child: ListTile(
                        leading: Icon(Icons.emoji_events_rounded),
                        title: Text('Registrar partida'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    if (FirebaseAuth.instance.currentUser?.uid ==
                        _baseDeck.ownerId) ...[
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                          ),
                          title: Text(
                            'Eliminar mazo',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ],
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: Stack(
          children: [
            const _DeckBackdrop(),
            SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (banListWarnings.isNotEmpty)
                      _BanListWarningBanner(messages: banListWarnings),
                    isWide
                        ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  _DeckGalleryPanel(
                                    title: deck.name,
                                    cards: cards,
                                    coverCardId: deck.coverCardId,
                                    onCardTap:
                                        (c, tag) =>
                                            _showCardDetails(context, c, tag),
                                    onCardLongPress: _showPosterCardActions,
                                    onSideboardDrop:
                                        canEditDeck ? _swapWithSideboard : null,
                                    // El botón "+" se retiró: declarar copias
                                    // que faltan ahora se hace desde "Asignar
                                    // variante por copia", que ofrece
                                    // agregarlas si no alcanzan.
                                    onCorrectQuantity:
                                        canEditDeck
                                            ? _correctOwnedQuantity
                                            : null,
                                    onIdentifyVariants:
                                        canEditDeck
                                            ? (card) => _showVariantPicker(
                                              card.cardId,
                                              card.name,
                                              deck,
                                            )
                                            : null,
                                  ),
                                  const SizedBox(height: 14),
                                  _SideboardPanel(
                                    cards: _sideboardVisualEntries(deck),
                                    onAdd: _showSideboardCatalog,
                                    onRemove: _removeFromSideboard,
                                    editable: canEditDeck,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            SizedBox(
                              width: 300,
                              child: _DeckSidebar(
                                deck: deck,
                                haveDeck: _haveDeck,
                                targetDeck: _targetDeck,
                                showTarget: _showTarget,
                                loadingLinkedDeck: _loadingLinkedDeck,
                                raceLabel: raceLabel,
                                byType: byType,
                                curve: curve,
                                stats: stats,
                                raceVariants: _raceVariants,
                                onShowHave:
                                    _canToggleLinkedDeck
                                        ? () =>
                                            setState(() => _showTarget = false)
                                        : null,
                                onShowTarget:
                                    _canToggleLinkedDeck
                                        ? () =>
                                            setState(() => _showTarget = true)
                                        : null,
                                onShowDiff:
                                    _canToggleLinkedDeck
                                        ? () => showDeckDiffDialog(
                                          context,
                                          _haveDeck!,
                                          _targetDeck!,
                                          _ownerDecks,
                                          cardsById: _cardsById,
                                          cardsByNameLower: _cardsByNameLower,
                                          imgByCardId: _imgById,
                                          officialImgByCardId: _imgById,
                                        )
                                        : null,
                                onShowStats: _showDeckStats,
                              ),
                            ),
                          ],
                        )
                        : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _DeckGalleryPanel(
                              title: deck.name,
                              cards: cards,
                              coverCardId: deck.coverCardId,
                              onCardTap:
                                  (c, tag) => _showCardDetails(context, c, tag),
                              onCardLongPress: _showPosterCardActions,
                              onSideboardDrop:
                                  canEditDeck ? _swapWithSideboard : null,
                              onCorrectQuantity:
                                  canEditDeck ? _correctOwnedQuantity : null,
                              onIdentifyVariants:
                                  canEditDeck
                                      ? (card) => _showVariantPicker(
                                        card.cardId,
                                        card.name,
                                        deck,
                                      )
                                      : null,
                            ),
                            const SizedBox(height: 14),
                            _SideboardPanel(
                              cards: _sideboardVisualEntries(deck),
                              onAdd: _showSideboardCatalog,
                              onRemove: _removeFromSideboard,
                              editable: canEditDeck,
                            ),
                            const SizedBox(height: 18),
                            _DeckSidebar(
                              deck: deck,
                              haveDeck: _haveDeck,
                              targetDeck: _targetDeck,
                              showTarget: _showTarget,
                              loadingLinkedDeck: _loadingLinkedDeck,
                              raceLabel: raceLabel,
                              byType: byType,
                              curve: curve,
                              stats: stats,
                              raceVariants: _raceVariants,
                              onShowHave:
                                  _canToggleLinkedDeck
                                      ? () =>
                                          setState(() => _showTarget = false)
                                      : null,
                              onShowTarget:
                                  _canToggleLinkedDeck
                                      ? () => setState(() => _showTarget = true)
                                      : null,
                              onShowDiff:
                                  _canToggleLinkedDeck
                                      ? () => showDeckDiffDialog(
                                        context,
                                        _haveDeck!,
                                        _targetDeck!,
                                        _ownerDecks,
                                        cardsById: _cardsById,
                                        cardsByNameLower: _cardsByNameLower,
                                        imgByCardId: _imgById,
                                        officialImgByCardId: _imgById,
                                      )
                                      : null,
                              onShowStats: _showDeckStats,
                            ),
                          ],
                        ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BanListWarningBanner extends StatelessWidget {
  final List<String> messages;

  const _BanListWarningBanner({required this.messages});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF3A1414),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE05C5C)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFE05C5C),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Este mazo no cumple la Ban List vigente',
                  style: TextStyle(
                    color: Color(0xFFE05C5C),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                for (final m in messages)
                  Text(
                    m,
                    style: const TextStyle(
                      color: Color(0xFFE0A0A0),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeckBackdrop extends StatelessWidget {
  const _DeckBackdrop();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A0A0E), Color(0xFF050507), Color(0xFF121014)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -100,
            left: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFD5A11E).withOpacity(.08),
              ),
            ),
          ),
          Positioned(
            right: -80,
            top: 120,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(.03),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeckGalleryPanel extends StatelessWidget {
  final String title;
  final List<_DeckVisualCard> cards;
  final String? coverCardId;
  final void Function(_DeckVisualCard, String)? onCardTap;
  final ValueChanged<_DeckVisualCard>? onCardLongPress;
  final Future<void> Function(_DeckVisualCard, DeckCardEntry)? onSideboardDrop;
  final ValueChanged<_DeckVisualCard>? onAddOwned;
  final ValueChanged<_DeckVisualCard>? onCorrectQuantity;
  final ValueChanged<_DeckVisualCard>? onIdentifyVariants;

  const _DeckGalleryPanel({
    required this.title,
    required this.cards,
    this.coverCardId,
    this.onCardTap,
    this.onCardLongPress,
    this.onSideboardDrop,
    this.onAddOwned,
    this.onCorrectQuantity,
    this.onIdentifyVariants,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.38),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withOpacity(.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.isEmpty ? 'Mazo' : title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final targetCardWidth =
                  width >= 1200
                      ? 128.0
                      : width >= 900
                      ? 118.0
                      : width >= 700
                      ? 110.0
                      : 92.0;
              final spacing = width >= 900 ? 14.0 : 10.0;

              int idx = 0;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children:
                    cards.map((card) {
                      final uniqueTag = 'hero_${card.cardId}_${idx++}';
                      return DragTarget<DeckCardEntry>(
                        onWillAcceptWithDetails: (_) => onSideboardDrop != null,
                        onAcceptWithDetails:
                            (details) =>
                                onSideboardDrop?.call(card, details.data),
                        builder:
                            (context, candidates, rejected) =>
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 120),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border:
                                        candidates.isEmpty
                                            ? null
                                            : Border.all(
                                              color: const Color(0xFFD8B46A),
                                              width: 3,
                                            ),
                                  ),
                                  child: _DeckCardTile(
                                    card: card,
                                    baseWidth: targetCardWidth,
                                    heroTag: uniqueTag,
                                    isCover:
                                        (coverCardId ?? '').trim() ==
                                        card.cardId.trim(),
                                    onZoom:
                                        onCardTap == null
                                            ? null
                                            : () => onCardTap!(card, uniqueTag),
                                    onLongPress:
                                        onCardLongPress == null
                                            ? null
                                            : () => onCardLongPress!(card),
                                    onAddOwned:
                                        onAddOwned == null
                                            ? null
                                            : () => onAddOwned!(card),
                                    onCorrectQuantity:
                                        onCorrectQuantity == null
                                            ? null
                                            : () => onCorrectQuantity!(card),
                                    onIdentifyVariants:
                                        onIdentifyVariants == null
                                            ? null
                                            : () => onIdentifyVariants!(card),
                                  ),
                                ),
                      );
                    }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SideboardVisualEntry {
  final DeckCardEntry entry;
  final String imageUrl;

  const _SideboardVisualEntry({required this.entry, required this.imageUrl});
}

class _SideboardPanel extends StatelessWidget {
  final List<_SideboardVisualEntry> cards;
  final VoidCallback onAdd;
  final ValueChanged<DeckCardEntry> onRemove;
  final bool editable;

  const _SideboardPanel({
    required this.cards,
    required this.onAdd,
    required this.onRemove,
    required this.editable,
  });

  @override
  Widget build(BuildContext context) {
    final total = cards.fold<int>(0, (sum, card) => sum + card.entry.count);
    final copies = <({_SideboardVisualEntry visual, int copyIndex})>[];
    for (final visual in cards) {
      for (var index = 0; index < visual.entry.count; index++) {
        copies.add((visual: visual, copyIndex: index));
      }
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.38),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0x55D8B46A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Side deck · $total/10',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: !editable || total >= 10 ? null : onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Agregar'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Arrastra una copia sobre una carta principal para intercambiarlas.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (copies.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  'Todavía no agregas cartas laterales.',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder:
                  (context, constraints) => Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children:
                        copies.map((copy) {
                          final face = _SideboardCardFace(
                            visual: copy.visual,
                            onRemove:
                                editable
                                    ? () => onRemove(copy.visual.entry)
                                    : null,
                          );
                          final feedback = Material(
                            color: Colors.transparent,
                            child: SizedBox(width: 94, child: face),
                          );
                          if (!editable) return face;
                          final platform = Theme.of(context).platform;
                          if (platform == TargetPlatform.android ||
                              platform == TargetPlatform.iOS) {
                            return LongPressDraggable<DeckCardEntry>(
                              data: copy.visual.entry,
                              feedback: feedback,
                              childWhenDragging: Opacity(
                                opacity: .28,
                                child: face,
                              ),
                              child: face,
                            );
                          }
                          return Draggable<DeckCardEntry>(
                            data: copy.visual.entry,
                            feedback: feedback,
                            childWhenDragging: Opacity(
                              opacity: .28,
                              child: face,
                            ),
                            child: face,
                          );
                        }).toList(),
                  ),
            ),
        ],
      ),
    );
  }
}

class _SideboardCardFace extends StatelessWidget {
  final _SideboardVisualEntry visual;
  final VoidCallback? onRemove;

  const _SideboardCardFace({required this.visual, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final image = AspectRatio(
      aspectRatio: .69,
      child: MylCardImage(url: visual.imageUrl, fit: BoxFit.cover),
    );
    return SizedBox(
      width: 94,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(8), child: image),
          if (onRemove != null)
            Positioned(
              right: -8,
              top: -8,
              child: IconButton.filled(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                padding: EdgeInsets.zero,
                tooltip: 'Quitar del side deck',
                onPressed: onRemove,
                icon: const Icon(Icons.close, size: 16),
              ),
            ),
        ],
      ),
    );
  }
}

class _DeckCardTile extends StatefulWidget {
  final _DeckVisualCard card;
  final double baseWidth;
  final bool isCover;
  final String? heroTag;

  /// Abre el zoom (doble tap, o tap simple si count == 1)
  final VoidCallback? onZoom;
  final VoidCallback? onLongPress;

  /// Toca el botón "+" que aparece sobre una copia gris (no disponible).
  final VoidCallback? onAddOwned;

  /// Toca el botón de lápiz que aparece sobre una copia disponible, para
  /// corregir la cantidad ("en realidad no tengo tantas").
  final VoidCallback? onCorrectQuantity;
  final VoidCallback? onIdentifyVariants;

  const _DeckCardTile({
    required this.card,
    required this.baseWidth,
    this.isCover = false,
    this.heroTag,
    this.onZoom,
    this.onLongPress,
    this.onAddOwned,
    this.onCorrectQuantity,
    this.onIdentifyVariants,
  });

  @override
  State<_DeckCardTile> createState() => _DeckCardTileState();
}

class _DeckCardTileState extends State<_DeckCardTile> {
  bool _expanded = false;

  void _handleTap() {
    final copies = widget.card.count.clamp(1, 3);
    if (copies == 1) {
      widget.onZoom?.call();
    } else {
      setState(() => _expanded = !_expanded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stackCopies = widget.card.count.clamp(1, 3);
    final cardWidth = widget.baseWidth;
    final cardHeight = widget.baseWidth * 1.42;

    // Posiciones animadas
    const collapsedDx = 12.0;
    const collapsedDy = 4.0;
    final expandedDx = cardWidth * 0.64;

    final totalCollapsedW = cardWidth + (stackCopies - 1) * collapsedDx;
    final totalExpandedW = cardWidth + (stackCopies - 1) * expandedDx;
    final totalW = _expanded ? totalExpandedW : totalCollapsedW;

    final totalCollapsedH = cardHeight + (stackCopies - 1) * collapsedDy;
    final totalH = totalCollapsedH; // altura fija

    return SizedBox(
      width: totalW,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: _handleTap,
            onDoubleTap: widget.onZoom,
            onLongPress: widget.onLongPress,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: totalW,
              height: totalH,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (int i = stackCopies - 1; i >= 0; i--)
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      left: _expanded ? i * expandedDx : i * collapsedDx,
                      top: _expanded ? 0 : i * collapsedDy,
                      child: AnimatedRotation(
                        duration: const Duration(milliseconds: 220),
                        turns:
                            (_expanded || i == 0)
                                ? 0
                                : (-0.02 * i) / (2 * 3.1416),
                        child: _posterCard(
                          cardWidth,
                          cardHeight,
                          url: widget.card.urlForCopy(i),
                          state: widget.card.stateForCopy(i),
                          useHero: i == 0,
                          showAddOwned:
                              (stackCopies == 1 || _expanded) &&
                              widget.onAddOwned != null,
                          showCorrectQuantity:
                              (stackCopies == 1 || _expanded) &&
                              widget.onCorrectQuantity != null,
                          needsIdentification: widget.card
                              .needsIdentificationForCopy(i),
                        ),
                      ),
                    ),
                  if (widget.isCover)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(.72),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFF1D184).withOpacity(.8),
                          ),
                        ),
                        child: const Icon(
                          Icons.crop_square_rounded,
                          size: 16,
                          color: Color(0xFFF1D184),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.card.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (widget.card.unidentifiedAssignedCount > 0) ...[
            const SizedBox(height: 5),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: widget.onIdentifyVariants,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFC857).withOpacity(.14),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFFFFC857).withOpacity(.75),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.help_outline_rounded,
                        size: 13,
                        color: Color(0xFFFFD978),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          widget.card.unidentifiedAssignedCount == 1
                              ? 'Identificar versión'
                              : 'Identificar ${widget.card.unidentifiedAssignedCount} versiones',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFFFD978),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _posterCard(
    double width,
    double height, {
    String? url,
    required DeckCopyState state,
    bool useHero = false,
    bool showAddOwned = false,
    bool showCorrectQuantity = false,
    bool needsIdentification = false,
  }) {
    final hasExplicitUrl = url != null && url.isNotEmpty;
    final rawUrl = hasExplicitUrl ? url : widget.card.imageUrl;
    final effectiveUrl = DriveService.webSafeUrl(rawUrl);
    // Si esta copia tiene una variante específica asignada, un error de red no
    // debe reemplazarla por otra imagen (oficial u otra variante): eso es lo
    // que causaba el "parpadeo" en web (Image.network falla transitoriamente
    // y el resolver genérico mostraba una carta distinta a la elegida).
    // El resolver genérico solo aplica cuando esta copia no tiene variante.
    final Widget image =
        effectiveUrl.isNotEmpty
            ? Image.network(
              effectiveUrl,
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder:
                  (_, __, ___) =>
                      (!hasExplicitUrl && widget.card.cardId.isNotEmpty)
                          ? SizedBox(
                            width: width,
                            height: height,
                            child: FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: width,
                                height: height,
                                child: VariantThumbFromCard(
                                  cardId: widget.card.cardId,
                                  fallbackTipo: widget.card.tipo,
                                  size: width,
                                ),
                              ),
                            ),
                          )
                          : _fallback(width, height),
            )
            : (widget.card.cardId.isNotEmpty)
            ? SizedBox(
              width: width,
              height: height,
              child: VariantThumbFromCard(
                cardId: widget.card.cardId,
                fallbackTipo: widget.card.tipo,
                size: width,
              ),
            )
            : _fallback(width, height);

    final rawInner = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: image,
    );
    final unavailable = state != DeckCopyState.assigned;
    final filtered =
        unavailable
            ? ColorFiltered(
              colorFilter: const ColorFilter.matrix(<double>[
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
              ]),
              child: Opacity(opacity: .58, child: rawInner),
            )
            : rawInner;
    final inner = Stack(
      children: [
        filtered,
        if (unavailable)
          Positioned(
            right: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: const BoxDecoration(
                color: Colors.black87,
                shape: BoxShape.circle,
              ),
              child: Icon(
                switch (state) {
                  DeckCopyState.inOtherDeck => Icons.swap_horiz,
                  DeckCopyState.reservedForSale => Icons.storefront,
                  DeckCopyState.free => Icons.inventory_2_outlined,
                  DeckCopyState.missing => Icons.remove_circle_outline,
                  DeckCopyState.assigned => Icons.check,
                },
                size: 17,
                color: Colors.white,
              ),
            ),
          ),
        if (unavailable && showAddOwned)
          Positioned(
            right: 6,
            top: 6,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: widget.onAddOwned,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Color(0xFF75D69C),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add, size: 15, color: Colors.black),
                ),
              ),
            ),
          ),
        if (!unavailable && showCorrectQuantity)
          Positioned(
            right: 6,
            top: 6,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: widget.onCorrectQuantity,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1D48B),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.edit_outlined,
                    size: 13,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ),
        if (needsIdentification)
          Positioned(
            left: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: const Color(0xFFFFC857),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black54),
              ),
              child: const Icon(
                Icons.question_mark_rounded,
                size: 13,
                color: Colors.black,
              ),
            ),
          ),
      ],
    );

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFD9A323).withOpacity(.7),
          width: 1.6,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.35),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child:
          useHero
              ? Hero(
                tag: widget.heroTag ?? 'deck_card_${widget.card.cardId}',
                child: inner,
              )
              : inner,
    );
  }

  Widget _fallback(double width, double height) {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFF26222A),
      alignment: Alignment.center,
      child: const Icon(Icons.style, color: Colors.white54),
    );
  }
}

class _DeckSidebar extends StatelessWidget {
  final Deck deck;
  final Deck? haveDeck;
  final Deck? targetDeck;
  final bool showTarget;
  final bool loadingLinkedDeck;
  final String raceLabel;
  final Map<String, int> byType;
  final Map<int, int> curve;
  final _DeckStatsSnapshot stats;
  final List<Deck> raceVariants;
  final VoidCallback? onShowHave;
  final VoidCallback? onShowTarget;
  final VoidCallback? onShowDiff;
  final VoidCallback onShowStats;

  const _DeckSidebar({
    required this.deck,
    required this.haveDeck,
    required this.targetDeck,
    required this.showTarget,
    required this.loadingLinkedDeck,
    required this.raceLabel,
    required this.byType,
    required this.curve,
    required this.stats,
    required this.raceVariants,
    required this.onShowHave,
    required this.onShowTarget,
    required this.onShowDiff,
    required this.onShowStats,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (haveDeck != null || targetDeck != null) ...[
          _SidebarCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Vista del Mazo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                if (haveDeck != null &&
                    targetDeck != null &&
                    onShowHave != null &&
                    onShowTarget != null)
                  _DeckVersionSwitch(
                    showTarget: showTarget,
                    onShowHave: onShowHave!,
                    onShowTarget: onShowTarget!,
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(.32),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Text(
                      loadingLinkedDeck
                          ? 'Buscando objetivo vinculado...'
                          : haveDeck?.isUnified == true
                          ? 'Configuración única · las copias físicas vienen de Mi carpeta.'
                          : 'Este mazo no tiene objetivo vinculado.',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (onShowDiff != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onShowDiff,
                      icon: const Icon(Icons.rule_folder_outlined),
                      label: const Text('Ver cartas faltantes'),
                    ),
                  ),
                ],
                if (raceVariants.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Variaciones de esta raza',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...raceVariants.map(
                    (v) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF58A6FF),
                          side: const BorderSide(color: Color(0x4458A6FF)),
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        onPressed:
                            () => context.push('/mazo/${v.ownerId}/${v.id}'),
                        icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                        label: Text(
                          v.name.isEmpty ? 'Variación sin nombre' : v.name,
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onShowStats,
                    icon: const Icon(Icons.analytics_outlined),
                    label: const Text('Ver estadísticas'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        _SidebarCard(child: _CurveMiniChart(curve: curve)),
        const SizedBox(height: 16),
        _SidebarCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  'Resumen del Mazo, Raza :\n$raceLabel',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Divider(color: Colors.white12),
              const SizedBox(height: 8),
              _SummaryRow(
                label: 'Aliados',
                value: byType['aliado'] ?? 0,
                icon: Icons.group_outlined,
              ),
              _SummaryRow(
                label: 'Oros',
                value: byType['oro'] ?? 0,
                icon: Icons.monetization_on_outlined,
              ),
              _SummaryRow(
                label: 'Talismanes',
                value: byType['talisman'] ?? 0,
                icon: Icons.auto_awesome_outlined,
              ),
              _SummaryRow(
                label: 'Armas',
                value: byType['arma'] ?? 0,
                icon: Icons.gavel_outlined,
              ),
              _SummaryRow(
                label: 'Totems',
                value: byType['totem'] ?? 0,
                icon: Icons.account_balance_outlined,
              ),
              const SizedBox(height: 12),
              const Divider(color: Colors.white12),
              const SizedBox(height: 8),
              _SummaryRow(
                label: 'Coste prom.',
                valueText:
                    stats.avgCost.isNaN
                        ? '-'
                        : stats.avgCost.toStringAsFixed(2),
                icon: Icons.bar_chart_outlined,
              ),
              _SummaryRow(
                label: 'Fuerza prom.',
                valueText:
                    stats.avgStrength.isNaN
                        ? '-'
                        : stats.avgStrength.toStringAsFixed(2),
                icon: Icons.bolt_outlined,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SquareCropDialog extends StatefulWidget {
  final Uint8List sourceBytes;
  final String title;

  const _SquareCropDialog({required this.sourceBytes, required this.title});

  @override
  State<_SquareCropDialog> createState() => _SquareCropDialogState();
}

class _SquareCropDialogState extends State<_SquareCropDialog> {
  static const double _viewportSize = 280;
  late final img.Image _decoded;
  double _zoom = 1;
  Offset _offset = Offset.zero;

  @override
  void initState() {
    super.initState();
    final decoded = img.decodeImage(widget.sourceBytes);
    if (decoded == null) {
      throw StateError('No se pudo decodificar la imagen de la carta.');
    }
    _decoded = decoded;
  }

  double get _baseScale =>
      math.max(_viewportSize / _decoded.width, _viewportSize / _decoded.height);

  double get _displayScale => _baseScale * _zoom;
  double get _displayWidth => _decoded.width * _displayScale;
  double get _displayHeight => _decoded.height * _displayScale;

  Offset _clampOffset(Offset candidate, {double? zoom}) {
    final factor = zoom ?? _zoom;
    final displayScale = _baseScale * factor;
    final displayWidth = _decoded.width * displayScale;
    final displayHeight = _decoded.height * displayScale;
    final maxDx = math.max(0, (displayWidth - _viewportSize) / 2);
    final maxDy = math.max(0, (displayHeight - _viewportSize) / 2);

    return Offset(
      candidate.dx.clamp(-maxDx, maxDx).toDouble(),
      candidate.dy.clamp(-maxDy, maxDy).toDouble(),
    );
  }

  _CropSelectionResult _buildCropResult() {
    final left = ((_viewportSize - _displayWidth) / 2) + _offset.dx;
    final top = ((_viewportSize - _displayHeight) / 2) + _offset.dy;

    final cropX = ((-left) / _displayWidth * _decoded.width).clamp(
      0,
      (_decoded.width - 1).toDouble(),
    );
    final cropY = ((-top) / _displayHeight * _decoded.height).clamp(
      0,
      (_decoded.height - 1).toDouble(),
    );
    final cropW = (_viewportSize / _displayWidth * _decoded.width).clamp(
      1,
      (_decoded.width - cropX).toDouble(),
    );
    final cropH = (_viewportSize / _displayHeight * _decoded.height).clamp(
      1,
      (_decoded.height - cropY).toDouble(),
    );

    final cropped = img.copyCrop(
      _decoded,
      x: cropX.round(),
      y: cropY.round(),
      width: cropW.round(),
      height: cropH.round(),
    );
    final square = img.copyResizeCropSquare(cropped, size: 600);
    return _CropSelectionResult(
      bytes: Uint8List.fromList(img.encodeJpg(square, quality: 92)),
      x: cropX.round(),
      y: cropY.round(),
      width: cropW.round(),
      height: cropH.round(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF130E0A),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Arrastra la imagen y ajusta el zoom para elegir la portada cuadrada.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: _viewportSize,
                  height: _viewportSize,
                  color: Colors.black,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      setState(() {
                        _offset = _clampOffset(_offset + details.delta);
                      });
                    },
                    child: Stack(
                      children: [
                        Positioned(
                          left:
                              ((_viewportSize - _displayWidth) / 2) +
                              _offset.dx,
                          top:
                              ((_viewportSize - _displayHeight) / 2) +
                              _offset.dy,
                          child: SizedBox(
                            width: _displayWidth,
                            height: _displayHeight,
                            child: Image.memory(
                              widget.sourceBytes,
                              fit: BoxFit.fill,
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: const Color(0xFFF1D184),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.zoom_in, color: Colors.white70, size: 18),
                Expanded(
                  child: Slider(
                    value: _zoom,
                    min: 1,
                    max: 3,
                    divisions: 20,
                    onChanged: (value) {
                      setState(() {
                        _zoom = value;
                        _offset = _clampOffset(_offset, zoom: value);
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _buildCropResult()),
                  child: const Text('Usar portada'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CropSelectionResult {
  final Uint8List bytes;
  final int x;
  final int y;
  final int width;
  final int height;

  const _CropSelectionResult({
    required this.bytes,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}

class _DeckVersionSwitch extends StatelessWidget {
  final bool showTarget;
  final VoidCallback onShowHave;
  final VoidCallback onShowTarget;

  const _DeckVersionSwitch({
    required this.showTarget,
    required this.onShowHave,
    required this.onShowTarget,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.34),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Expanded(
            child: _DeckVersionButton(
              label: 'Tengo',
              selected: !showTarget,
              onTap: onShowHave,
              icon: Icons.layers_outlined,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _DeckVersionButton(
              label: 'Objetivo',
              selected: showTarget,
              onTap: onShowTarget,
              icon: Icons.flag_outlined,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeckVersionButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData icon;

  const _DeckVersionButton({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color:
              selected
                  ? const Color(0xFFD8A12A).withOpacity(.18)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFFF0CC74) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? const Color(0xFFF5D98B) : Colors.white70,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarCard extends StatelessWidget {
  final Widget child;

  const _SidebarCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.42),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withOpacity(.08)),
      ),
      child: child,
    );
  }
}

class _CurveMiniChart extends StatelessWidget {
  final Map<int, int> curve;

  const _CurveMiniChart({required this.curve});

  @override
  Widget build(BuildContext context) {
    final entries =
        curve.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final maxValue = entries.fold<int>(0, (p, e) => e.value > p ? e.value : p);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Center(
          child: Text(
            'Curva de Oro',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 164,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children:
                entries.map((entry) {
                  final h =
                      maxValue == 0 ? 8.0 : (entry.value / maxValue) * 82 + 8;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            '${entry.value}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            height: h,
                            decoration: BoxDecoration(
                              color: const Color(0xFFB38319),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${entry.key}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final int? value;
  final String? valueText;
  final IconData icon;

  const _SummaryRow({
    required this.label,
    this.value,
    this.valueText,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            valueText ?? '${value ?? 0}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeckVisualCard {
  final String cardId;
  final String name;
  final String tipo;
  final int count;
  final int cost;
  final String imageUrl;
  // Imagen de la versión oficial/base, para copias sin variante definida.
  final String fallbackUrl;
  // URL por copia (index 0 = copia frontal). Vacía = copia sin variante definida.
  final List<String> variantUrls;
  final List<DeckCopyState> copyStates;
  final List<bool> copyNeedsIdentification;

  const _DeckVisualCard({
    required this.cardId,
    required this.name,
    required this.tipo,
    required this.count,
    required this.cost,
    required this.imageUrl,
    this.fallbackUrl = '',
    this.variantUrls = const [],
    this.copyStates = const [],
    this.copyNeedsIdentification = const [],
  });

  /// Devuelve la URL de la copia [i] (front=0). Sin variante definida usa la
  /// versión oficial ([fallbackUrl]) y, en último caso, [imageUrl].
  String urlForCopy(int i) {
    if (i < variantUrls.length && variantUrls[i].isNotEmpty)
      return variantUrls[i];
    if (fallbackUrl.isNotEmpty) return fallbackUrl;
    return imageUrl;
  }

  DeckCopyState stateForCopy(int i) =>
      i < copyStates.length ? copyStates[i] : DeckCopyState.missing;

  bool needsIdentificationForCopy(int i) =>
      i < copyNeedsIdentification.length && copyNeedsIdentification[i];

  int get unidentifiedAssignedCount =>
      copyNeedsIdentification.where((value) => value).length;
}
