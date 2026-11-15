import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import '../../models/deck.dart';
import '../../models/card_myl.dart';
import '../../models/ban_list_entry.dart';
import '../../services/deck_service.dart';
import '../../services/card_service.dart';
import '../../services/ban_list_service.dart';
import '../../services/drive_service.dart';
import '../../domain/validation/deck_validator.dart';
import 'add_cards_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/app_constants.dart';
import '../../utils/text_normalize.dart';
import 'package:myl_decks/widgets/card_image_preview.dart';
import '../widgets/network_image.dart';

String? safeImageUrl(String? url) {
  if (url == null || url.trim().isEmpty) return null;
  final clean = url.trim();
  if (clean.contains('drive.google.com')) return DriveService.webSafeUrl(clean);
  return clean;
}

class CreateDeckScreen extends StatefulWidget {
  final Deck? editDeck;
  final bool startInObjectiveMode;
  /// Permite reutilizar el constructor para snapshots externos (p. ej. listas
  /// notables) sin crear un mazo personal ni tocar inventario.
  final Future<void> Function(Deck deck)? onSave;

  const CreateDeckScreen({
    super.key,
    this.editDeck,
    this.startInObjectiveMode = false,
    this.onSave,
  });

  @override
  State<CreateDeckScreen> createState() => _CreateDeckScreenState();
}

class _CreateDeckScreenState extends State<CreateDeckScreen> {
  late DeckService _service;
  late CardService _cardService;
  late Deck _deck;
  late bool _isNew;
  bool? _isBasic;
  int _deckLimit = 3;
  late String _uid;
  final _nameCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  bool _saving = false;
  bool _loadingAvailable = false;
  bool _loadingBanList = false;
  bool _uploadingCover = false;
  final Map<String, String?> _imgCache = {};
  // La ban list depende del formato del mazo (Racial vs. Racial Libre son
  // colecciones independientes) — no puede ser final, se recrea al cambiar
  // _deck.format y dispara una recarga vía _loadBanList().
  BanListService _banListService = BanListService();
  static const String kOfficialImageUrlField = 'officialImageUrl';
  static const String kLegacyImageUrlField = 'imageUrl';
  String _typeFilter = 'all';
  List<CardMyL> _availableCards = [];
  Map<String, int> _copyLimitsByKey = const {};
  Map<String, int> _copyLimitsByCardId = const {};

  static const List<String> _tabKeys = [
    'aliado',
    'talisman',
    'arma',
    'oro',
    'totem',
  ];

  Future<void> _showUpgradeDialog() async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text("Límite alcanzado"),
            content: Text(
              "Tu cuenta básica permite hasta $_deckLimit mazos. Para crear más mazos, cambia a la versión Pro.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Aceptar"),
              ),
            ],
          ),
    );
  }

  int _resolveDeckLimit(Map<String, dynamic> data) {
    final configured = data['maxDecks'];
    if (configured is num && configured.toInt() > 0) {
      return configured.toInt();
    }
    return 3;
  }

  Future<bool> _canCreateNewDeck() async {
    if (!_isNew) return true;
    try {
      final userRef = FirebaseFirestore.instance.collection('users').doc(_uid);
      final userDoc = await userRef.get();

      if (userDoc.exists) {
        final data = userDoc.data()!;
        final email = (data['email'] as String? ?? '').toLowerCase();
        final role = (data['role'] as String? ?? '').toLowerCase();
        final plan = (data['plan'] as String? ?? '').toLowerCase();
        final isProFlag = data['isPro'] as bool? ?? false;
        final isSuperFlag = data['isSuperAdmin'] as bool? ?? false;
        _deckLimit = _resolveDeckLimit(data);
        const superAdminEmails = <String>[AppConstants.ownerEmail];
        const superAdminUids = AppConstants.superAdminUids;

        if (isSuperFlag ||
            superAdminEmails.contains(email) ||
            superAdminUids.contains(_uid)) {
          return true;
        }
        if (isProFlag ||
            role == 'pro' ||
            role == 'administrador' ||
            plan == 'pro' ||
            plan == 'premium') {
          return true;
        }
      }

      final snap =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(_uid)
              .collection('decks')
              .limit(_deckLimit)
              .get();

      final int existing = snap.docs.length;
      if (existing >= _deckLimit) {
        await _showUpgradeDialog();
        return false;
      }

      return true;
    } catch (e, st) {
      debugPrint('Error checking deck limit: $e\n$st');
      return true;
    }
  }

  Future<bool> _ensureCreatedIfNeeded() async {
    if (!_isNew) return true;
    if (widget.onSave != null) {
      _isNew = false;
      return true;
    }
    final canCreate = await _canCreateNewDeck();
    if (!canCreate) return false;
    final name = (_deck.name.isEmpty) ? 'Mazo sin nombre' : _deck.name;
    final newId = await _service.create(name);
    _deck = _deck.copyWith(id: newId, ownerId: _uid, updatedAt: DateTime.now());
    _isNew = false;
    return true;
  }

  Future<void> _persist(Deck deck) =>
      widget.onSave?.call(deck) ?? _service.save(deck);

  String _normalizeTipo(String? raw) {
    final t = (raw ?? '').trim().toLowerCase();
    if (t.isEmpty) return '';
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

  @override
  void initState() {
    super.initState();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError(
        'No hay usuario autenticado. Inicia sesión antes de usar CreateDeckScreen.',
      );
    }
    _uid = user.uid;

    _service = DeckService(_uid);
    _cardService = CardService();
    _loadUserPlan();
    _isNew = widget.editDeck == null;
    _deck = (widget.editDeck ??
            Deck(
              id: const Uuid().v4(),
              ownerId: _uid,
              name: "",
              isRacial: true,
              schemaVersion: 2,
              assemblyEnabled: true,
            ))
        .copyWith(isRacial: true);
    _banListService = _banListServiceFor(_deck.format);
    _loadBanList();

    _nameCtrl.text = _deck.name;
    _searchCtrl.addListener(_onAvailableFiltersChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_isNew || widget.onSave != null) return;
      final canCreate = await _canCreateNewDeck();
      if (!canCreate && mounted) {
        Navigator.pop(context);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _refreshAvailableCards(),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _searchCtrl.removeListener(_onAvailableFiltersChanged);
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  List<DeckCardEntry> get _activeCards => _deck.cards;

  int get _totalCards => _activeCards.fold<int>(0, (s, e) => s + e.count);

  String get _activeModeLabel => 'Configuración';

  Deck _copyDeckWithActiveCards(List<DeckCardEntry> cards) {
    return _deck.copyWith(
      schemaVersion: 2,
      cards: cards,
      sideboardCards: _sideSinExceso(cards),
      updatedAt: DateTime.now(),
    );
  }

  /// El límite de copias suma mazo y side deck: si una carta del mazo lo
  /// supera, se quitan del side las copias que sobran (y se avisa).
  List<DeckCardEntry> _sideSinExceso(List<DeckCardEntry> cards) {
    bool misma(DeckCardEntry a, DeckCardEntry b) {
      final ida = (a.cardId ?? '').trim();
      if (ida.isNotEmpty && ida == (b.cardId ?? '').trim()) return true;
      return a.name.trim().toLowerCase() == b.name.trim().toLowerCase();
    }

    final side = [..._deck.sideboardCards];
    final quitadas = <String, int>{};
    for (final e in cards) {
      final enMazo = cards.where((x) => misma(x, e)).fold<int>(0, (s, x) => s + x.count);
      final limite = _copyLimitForEntry(e);
      var exceso = enMazo +
          side.where((x) => misma(x, e)).fold<int>(0, (s, x) => s + x.count) -
          limite;
      for (var i = side.length - 1; i >= 0 && exceso > 0; i--) {
        if (!misma(side[i], e)) continue;
        final quita = exceso < side[i].count ? exceso : side[i].count;
        quitadas[e.name] = (quitadas[e.name] ?? 0) + quita;
        exceso -= quita;
        final queda = side[i].count - quita;
        if (queda <= 0) {
          side.removeAt(i);
        } else {
          side[i] = side[i].copyWith(count: queda);
        }
      }
    }
    if (quitadas.isNotEmpty) {
      final texto = quitadas.entries
          .map((q) => '${q.value} ${q.key}')
          .join(', ');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Se quitó del side deck: $texto (límite de copias entre mazo y side).')),
        );
      });
    }
    return side;
  }

  void _onFormatChanged(DeckFormat f) {
    setState(() {
      _deck = _deck.copyWith(
        format: f,
        edition: f == DeckFormat.racial ? _deck.edition : null,
        race: f == DeckFormat.full ? null : _deck.race,
      );
      _banListService = _banListServiceFor(f);
    });
    _loadBanList();
    _refreshAvailableCards();
  }

  BanListService _banListServiceFor(DeckFormat format) {
    switch (format) {
      case DeckFormat.racialLibre:
        return BanListService.racialLibre();
      case DeckFormat.full:
        return BanListService.full();
      case DeckFormat.racial:
        return BanListService();
    }
  }

  Future<void> _loadBanList() async {
    if (mounted) {
      setState(() => _loadingBanList = true);
    }
    try {
      final byKey = await _banListService.fetchCopyLimitsByKey();
      final byCardId = await _banListService.fetchCopyLimitsByCardId();
      if (!mounted) return;
      setState(() {
        _copyLimitsByKey = byKey;
        _copyLimitsByCardId = byCardId;
      });
    } catch (e) {
      debugPrint('Error loading ban list: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingBanList = false);
      }
    }
  }

  int _copyLimitForCard(CardMyL card) {
    final fromBan =
        _copyLimitsByKey[normalizeBanListKey(card.id)] ??
        _copyLimitsByKey[normalizeBanListKey(card.nombre)] ??
        3;
    if (card.unica) return fromBan.clamp(0, 1);
    return fromBan.clamp(0, 3);
  }

  int _copyLimitForEntry(DeckCardEntry entry) {
    final fromBan =
        _copyLimitsByKey[normalizeBanListKey(entry.cardId ?? '')] ??
        _copyLimitsByKey[normalizeBanListKey(entry.name)] ??
        3;
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
    if (isUnique) return fromBan.clamp(0, 1);
    return fromBan.clamp(0, 3);
  }

  ValidationResult _validationResult() {
    return validateDeck(
      deck: _deck,
      catalogById: const {},
      catalogByName: const {},
      copyLimitsByKey: _copyLimitsByKey,
    );
  }

  Future<void> _loadUserPlan() async {
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(_uid).get();
      final data = doc.data() ?? <String, dynamic>{};
      final role = (data['role'] as String?)?.toLowerCase();
      final plan = (data['plan'] as String?)?.toLowerCase();
      final isProFlag = (data['isPro'] as bool?) ?? false;
      final isSuperFlag = (data['isSuperAdmin'] as bool?) ?? false;
      final email = (data['email'] as String? ?? '').toLowerCase();
      const superAdminEmails = <String>[AppConstants.ownerEmail];
      _deckLimit = _resolveDeckLimit(data);

      final isBasic =
          !(isProFlag ||
              role == 'pro' ||
              role == 'administrador' ||
              plan == 'pro' ||
              plan == 'premium' ||
              isSuperFlag ||
              superAdminEmails.contains(email));

      if (mounted) setState(() => _isBasic = isBasic);
    } catch (e) {
      debugPrint('Error loading user plan: $e');
      if (mounted) setState(() => _isBasic = false);
    }
  }

  Future<void> _openLinkDialog() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    final email = (user?.email ?? '').toLowerCase();
    const superAdminEmails = <String>[AppConstants.ownerEmail];

    bool isSuperAdmin = false;
    try {
      if (uid != null) {
        final doc =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (doc.exists) {
          final data = doc.data()!;
          isSuperAdmin = (data['isSuperAdmin'] as bool?) ?? false;
        }
      }
    } catch (e) {
      debugPrint('Error checking super admin flag: $e');
    }

    final bypassForSuper = isSuperAdmin || superAdminEmails.contains(email);

    if (_isBasic == true && !bypassForSuper) {
      await _showUpgradeDialog();
      return;
    }

    final snap =
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('decks')
            .get();
    final allDecks =
        snap.docs
            .map((d) => Deck.fromFirestore(d.id, d.data()))
            .where((d) => d.id != _deck.id)
            .toList();

    if (!mounted) return;

    final chosen = await showDialog<Deck>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text("Vincular mazo"),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: allDecks.length,
                itemBuilder: (_, i) {
                  final d = allDecks[i];
                  return ListTile(
                    title: Text(d.name.isEmpty ? "Mazo sin nombre" : d.name),
                    subtitle: Text(d.edition ?? "-"),
                    onTap: () => Navigator.pop(ctx, d),
                  );
                },
              ),
            ),
          ),
    );

    if (chosen != null) {
      setState(() {
        _deck = _deck.copyWith(
          linkedDeckId: chosen.id,
          updatedAt: DateTime.now(),
        );
      });
      await _persist(_deck);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Vinculado a '${chosen.name}'")));
      }
    }
  }

  void _onNameChanged(String v) {
    _deck = _deck.copyWith(name: v.trim(), updatedAt: DateTime.now());
  }

  void _onAvailableFiltersChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _refreshAvailableCards();
    });
  }

  Future<void> _refreshAvailableCards() async {
    final currentEdition = (_deck.edition ?? '').trim();
    final currentRace = (_deck.race ?? '').trim();
    final text = normalizeSearch(_searchCtrl.text);
    final selectedType = _typeFilter;

    if (mounted) {
      setState(() => _loadingAvailable = true);
    }

    try {
      final col = FirebaseFirestore.instance.collection('cards');
      final cards = <String, CardMyL>{};

      Future<void> runQuery(Query<Map<String, dynamic>> q) async {
        final snap = await q.get();
        for (final d in snap.docs) {
          final card = CardMyL.fromMap(d.data(), d.id);
          cards[d.id] = card;
        }
      }

      final wantsAliado = selectedType == 'all' || selectedType == 'aliado';
      final wantsOro = selectedType == 'all' || selectedType == 'oro';
      final wantsSupport =
          selectedType == 'all' ||
          selectedType == 'talisman' ||
          selectedType == 'totem' ||
          selectedType == 'arma';

      final isLibre = _deck.format == DeckFormat.racialLibre;
      final isFull = _deck.format == DeckFormat.full;

      if (isFull) {
        // Formato Libre: cualquier carta, sin restricción de raza/edición.
        Query<Map<String, dynamic>> q = col;
        if (selectedType != 'all') {
          q = q.where('tipo', isEqualTo: _prettyType(selectedType));
        }
        await runQuery(q);
      } else if (currentRace.isNotEmpty) {
        if (wantsAliado) {
          if (isLibre) {
            // Libre: aliados de la raza de cualquier edición
            await runQuery(
              col
                  .where('raza', isEqualTo: currentRace)
                  .where('tipo', isEqualTo: 'Aliado'),
            );
          } else if (currentEdition.isNotEmpty) {
            // Clásico: aliados de la raza y de la edición del mazo
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
        // Sin raza definida aún: mostrar todo sin filtrar
        Query<Map<String, dynamic>> q = col;
        if (selectedType != 'all') {
          q = q.where('tipo', isEqualTo: _prettyType(selectedType));
        }
        await runQuery(q);
      }

      // Filtro de texto client-side (Firestore no permite range + whereIn en la misma query)
      final filtered =
          text.isEmpty
              ? cards.values.toList()
              : cards.values
                  .where((c) => normalizeSearch(c.nombre).contains(text))
                  .toList();

      final ordered =
          filtered..sort((a, b) {
            final typeCmp = _tabKeys
                .indexOf(_normalizeTipo(a.tipo))
                .compareTo(_tabKeys.indexOf(_normalizeTipo(b.tipo)));
            if (typeCmp != 0) return typeCmp;
            final costCmp = (b.coste ?? 0).compareTo(a.coste ?? 0);
            if (costCmp != 0) return costCmp;
            return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
          });

      if (!mounted) return;
      setState(() => _availableCards = ordered);
    } catch (_) {
      if (!mounted) return;
      setState(() => _availableCards = []);
    } finally {
      if (mounted) {
        setState(() => _loadingAvailable = false);
      }
    }
  }

  int _countInDeck(CardMyL card) {
    for (final e in _activeCards) {
      final sameId = (e.cardId ?? '').isNotEmpty && e.cardId == card.id;
      final sameName =
          e.name.trim().toLowerCase() == card.nombre.trim().toLowerCase();
      if (sameId || sameName) return e.count;
    }
    return 0;
  }

  bool _isBlockedAvailableCard(CardMyL card) {
    final count = _countInDeck(card);
    final maxCopies = _copyLimitForCard(card);
    if (count >= maxCopies) return true;
    return false;
  }

  bool _isDeckFull() => _totalCards >= 49;

  void _addAvailableCard(CardMyL card) {
    if (_isBlockedAvailableCard(card) || _isDeckFull()) return;

    final idx = _activeCards.indexWhere((e) {
      final sameId = (e.cardId ?? '').isNotEmpty && e.cardId == card.id;
      final sameName =
          e.name.trim().toLowerCase() == card.nombre.trim().toLowerCase();
      return sameId || sameName;
    });

    setState(() {
      // Auto-populate race/edition if they are missing (no aplica en Formato
      // Libre: ese formato no tiene raza ni edición asociadas al mazo).
      if (_deck.format != DeckFormat.full) {
        String? newRace = _deck.race;
        String? newEdition = _deck.edition;

        final isLibre = _deck.format == DeckFormat.racialLibre;
        if (!isLibre && (newEdition ?? '').trim().isEmpty) {
          newEdition = card.edicion;
        }
        if ((card.tipo ?? '').toLowerCase() == 'aliado' &&
            (newRace ?? '').trim().isEmpty) {
          newRace = card.raza;
        }

        if (newRace != _deck.race || newEdition != _deck.edition) {
          _deck = _deck.copyWith(race: newRace, edition: newEdition);
        }
      }

      if (idx >= 0) {
        final current = _activeCards[idx];
        final updated = current.copyWith(
          count: (current.count + 1).clamp(1, _copyLimitForCard(card)),
        );
        final newList = [..._activeCards]..[idx] = updated;
        _deck = _copyDeckWithActiveCards(newList);
      } else {
        final newEntry = DeckCardEntry(
          cardId: card.id,
          name: card.nombre,
          count: 1,
          coste: card.coste,
          tipo: card.tipo,
          rareza: card.rareza,
          edicion: card.edicion,
          unica: card.unica,
        );
        _deck = _copyDeckWithActiveCards([..._activeCards, newEntry]);
      }
    });
  }

  Future<void> _showVariantSelector(
    CardMyL card, {
    DeckCardEntry? existingEntry,
  }) async {
    final maxAllowed = _copyLimitForCard(card);
    int currentTotalCount = existingEntry?.count ?? 0;

    // Map of variantId to count
    // Use 'default' for the regular artwork
    final Map<String, int> selectedCounts = {};

    if (existingEntry != null && existingEntry.selectedVariants != null) {
      for (final vId in existingEntry.selectedVariants!) {
        selectedCounts[vId] = (selectedCounts[vId] ?? 0) + 1;
      }
    }

    // Fill in 'default' if the count is greater than the variants we have
    int knownVariantsCount = selectedCounts.values.fold(
      0,
      (sum, val) => sum + val,
    );
    if (currentTotalCount > knownVariantsCount) {
      selectedCounts['default'] =
          (selectedCounts['default'] ?? 0) +
          (currentTotalCount - knownVariantsCount);
    }

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (stCtx, stSetState) {
            int currentSum = selectedCounts.values.fold(
              0,
              (sum, val) => sum + val,
            );

            Widget buildVariantRow(
              String variantId,
              String name,
              String? imageUrl,
            ) {
              final count = selectedCounts[variantId] ?? 0;
              return ListTile(
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2118),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFFB58B47).withOpacity(0.3),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child:
                        (imageUrl != null && imageUrl.isNotEmpty)
                            ? MylNetworkImage(
                              imageUrl: safeImageUrl(imageUrl) ?? '',
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
                                  (_, __, ___) =>
                                      const Icon(Icons.broken_image, size: 20),
                            )
                            : const Icon(
                              Icons.image_not_supported_outlined,
                              size: 20,
                              color: Colors.white54,
                            ),
                  ),
                ),
                title: Text(name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed:
                          count > 0
                              ? () {
                                stSetState(() {
                                  selectedCounts[variantId] = count - 1;
                                });
                              }
                              : null,
                    ),
                    Text(
                      '$count',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed:
                          currentSum < maxAllowed
                              ? () {
                                stSetState(() {
                                  selectedCounts[variantId] = count + 1;
                                });
                              }
                              : null,
                    ),
                  ],
                ),
              );
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF21170F),
              title: const Text(
                'Seleccionar Variantes',
                style: TextStyle(color: Color(0xFFD8B46A)),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Text(
                          'Copias totales: $currentSum / $maxAllowed\n(Las copias regulares se completarán automáticamente al jugar o ver en detalle si no eliges suficientes variantes)',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      // The regular card artwork
                      FutureBuilder<String?>(
                        future: _resolveImageUrl(
                          DeckCardEntry(
                            cardId: card.id,
                            name: card.nombre,
                            count: 1,
                            coste: card.coste,
                            tipo: card.tipo,
                          ),
                        ),
                        builder: (ctx, snap) {
                          return buildVariantRow(
                            'default',
                            'Regular',
                            snap.data,
                          );
                        },
                      ),
                      const Divider(color: Colors.white24),
                      // The variants
                      ...card.variantes.map(
                        (v) => buildVariantRow(
                          v.id,
                          v.groupLabel,
                          v.imageFrontUrl,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);

                    // Apply the new counts to the deck
                    final newTotal = selectedCounts.values.fold(
                      0,
                      (sum, val) => sum + val,
                    );

                    if (newTotal == 0) {
                      // Remove entry completely
                      if (existingEntry != null) {
                        _removeEntry(existingEntry);
                      }
                      return;
                    }

                    // Build selectedVariants list
                    List<String> newVariants = [];
                    selectedCounts.forEach((vId, vCount) {
                      if (vId != 'default') {
                        for (int i = 0; i < vCount; i++) {
                          newVariants.add(vId);
                        }
                      }
                    });

                    setState(() {
                      final idx = _activeCards.indexWhere(
                        (e) =>
                            (e.cardId ?? '').isNotEmpty &&
                                e.cardId == card.id ||
                            e.name.trim().toLowerCase() ==
                                card.nombre.trim().toLowerCase(),
                      );

                      if (idx >= 0) {
                        final current = _activeCards[idx];
                        final updated = current.copyWith(
                          count: newTotal,
                          selectedVariants:
                              newVariants.isEmpty ? null : newVariants,
                        );
                        final newList = [..._activeCards]..[idx] = updated;
                        _deck = _copyDeckWithActiveCards(newList);
                      } else {
                        // We are adding it for the first time via the variant dialog
                        final newEntry = DeckCardEntry(
                          cardId: card.id,
                          name: card.nombre,
                          count: newTotal,
                          coste: card.coste,
                          tipo: card.tipo,
                          rareza: card.rareza,
                          edicion: card.edicion,
                          selectedVariants:
                              newVariants.isEmpty ? null : newVariants,
                        );
                        _deck = _copyDeckWithActiveCards([
                          ..._activeCards,
                          newEntry,
                        ]);
                      }
                    });
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFD8B46A),
                    foregroundColor: const Color(0xFF24180F),
                  ),
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _keyForEntry(DeckCardEntry e) =>
      (e.cardId ?? e.name).trim().toLowerCase();

  String? _miniThumbSquare(String? url, {int size = 56}) {
    if (url == null || url.isEmpty) return url;
    if (!url.contains('/upload/')) return url;
    return url.replaceFirst(
      '/upload/',
      '/upload/f_auto,q_auto,w_$size,h_$size,c_fill,g_auto/',
    );
  }

  Future<String?> _resolveImageUrl(DeckCardEntry e) async {
    final key = _keyForEntry(e);
    if (_imgCache.containsKey(key)) return _imgCache[key];

    String? _pickFromDoc(Map<String, dynamic> m) {
      for (final key in [
        kOfficialImageUrlField,
        kLegacyImageUrlField,
        'officialImage',
        'frontUrl',
        'img',
        'url',
      ]) {
        final v = safeImageUrl(m[key]?.toString());
        if (v != null && v.isNotEmpty) return v;
      }
      final images = m['images'];
      if (images is Map) {
        for (final k in ['front', 'anverso']) {
          final v = safeImageUrl(images[k]?.toString());
          if (v != null && v.isNotEmpty) return v;
        }
      }
      return null;
    }

    String? _pickFromVariant(Map<String, dynamic> m) {
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
          final v = safeImageUrl(thumbs[k]?.toString());
          if (v != null && v.isNotEmpty) return v;
        }
        for (final v in thumbs.values) {
          final s = safeImageUrl(v?.toString());
          if (s != null && s.isNotEmpty) return s;
        }
      }
      for (final key in [
        'thumbUrl',
        'imageFrontThumb',
        'imageFrontUrl',
        'frontUrl',
        'imageUrl',
        kOfficialImageUrlField,
        'officialImage',
        'img',
        'url',
      ]) {
        final v = safeImageUrl(m[key]?.toString());
        if (v != null && v.isNotEmpty) return v;
      }
      final images = m['images'];
      if (images is Map) {
        for (final k in ['front', 'anverso']) {
          final v = safeImageUrl(images[k]?.toString());
          if (v != null && v.isNotEmpty) return v;
        }
      }
      return null;
    }

    String? url;
    try {
      if (e.cardId != null && e.cardId!.isNotEmpty) {
        final doc =
            await FirebaseFirestore.instance
                .collection('cards')
                .doc(e.cardId!)
                .get();
        if (doc.exists) {
          url = _pickFromDoc(doc.data() ?? {});
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
            url = _pickFromVariant(d.data());
            if (url != null && url.isNotEmpty) break;
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
            url = _pickFromDoc(q.docs.first.data());
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
                url = _pickFromVariant(d.data());
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

  Future<void> _setCoverFromEntry(DeckCardEntry entry) async {
    if (_uploadingCover) return;

    final imageUrl = await _resolveImageUrl(entry);
    if (imageUrl == null || imageUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se encontró imagen para esa carta.'),
          ),
        );
      }
      return;
    }

    final createdOk = await _ensureCreatedIfNeeded();
    if (!createdOk || !mounted) return;

    setState(() => _uploadingCover = true);
    try {
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('No se pudo descargar la imagen.');
      }

      final croppedBytes = await showDialog<Uint8List>(
        context: context,
        barrierDismissible: false,
        builder:
            (_) => _SquareCropDialog(
              sourceBytes: response.bodyBytes,
              title: 'Recortar portada',
            ),
      );

      if (croppedBytes == null || croppedBytes.isEmpty || !mounted) return;

      final coverUrl = imageUrl;

      final updatedDeck = _deck.copyWith(
        coverUrl: coverUrl,
        coverCardId: entry.cardId,
        updatedAt: DateTime.now(),
      );

      setState(() => _deck = updatedDeck);
      await _persist(updatedDeck);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Portada actualizada con "${entry.name}".')),
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

  Future<void> _clearCover() async {
    final updatedDeck = _deck.copyWith(
      coverUrl: '',
      coverCardId: '',
      updatedAt: DateTime.now(),
    );

    setState(() => _deck = updatedDeck);
    await _persist(updatedDeck);
  }

  Future<void> _showEntryActions(DeckCardEntry entry) async {
    final isCurrentCover = (_deck.coverCardId ?? '') == (entry.cardId ?? '');

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
                  entry.name,
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
                    'Abrirá el recorte cuadrado para la portada del mazo.',
                    style: TextStyle(color: Colors.white60),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await _setCoverFromEntry(entry);
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
                      await _clearCover();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openAddCardsScreen() async {
    final editionToPass =
        (_deck.edition?.trim().isEmpty ?? true) ? null : _deck.edition!.trim();
    final raceToPass =
        (_deck.race?.trim().isEmpty ?? true) ? null : _deck.race!.trim();
    final added = await Navigator.push<List<DeckCardEntry>>(
      context,
      MaterialPageRoute(
        builder:
            (_) => AddCardsScreen(
              cardService: _cardService,
              currentRace: raceToPass,
              currentEdition: editionToPass,
              isLibre: _deck.format == DeckFormat.racialLibre,
              copyLimitsByCardId: _copyLimitsByCardId,
            ),
      ),
    );

    if (added == null || added.isEmpty) return;

    // Si alguna carta agregada es "soloLibre" (solo válida en Racial Libre o
    // Formato Libre), el mazo debe pasar a Racial Libre automáticamente si no
    // está ya en un formato que la permita: de lo contrario quedaría en
    // formato Racial con una edición arbitraria tomada de otra carta del
    // lote, que es inconsistente con lo que la propia carta permite.
    if (_deck.format == DeckFormat.racial && added.any((e) => e.soloLibre)) {
      _deck = _deck.copyWith(format: DeckFormat.racialLibre, edition: null);
      _banListService = _banListServiceFor(_deck.format);
      _loadBanList();
    }

    // Auto-populate race/edition if they are missing (no aplica en Formato
    // Libre: ese formato no tiene raza ni edición asociadas al mazo).
    final deckRaceEmpty = (_deck.race ?? '').trim().isEmpty;
    final deckEditionEmpty = (_deck.edition ?? '').trim().isEmpty;
    final isLibreFormat = _deck.format == DeckFormat.racialLibre;
    final isFullFormat = _deck.format == DeckFormat.full;

    if (!isFullFormat &&
        (deckRaceEmpty || (!isLibreFormat && deckEditionEmpty))) {
      if (!isLibreFormat && deckEditionEmpty) {
        // Try to find the first card that HAS an edition
        final withEd = added.firstWhere(
          (e) => (e.edicion ?? '').trim().isNotEmpty,
          orElse: () => added.first,
        );
        _deck = _deck.copyWith(edition: withEd.edicion);
      }

      if (deckRaceEmpty) {
        // Try to find the first Ally that HAS a race
        // Note: added.firstWhere for Allies is already done below, but we'll fetch its race
        final firstAlly = added.firstWhere(
          (e) => (e.tipo ?? '').toLowerCase() == 'aliado',
          orElse: () => DeckCardEntry(cardId: null, name: '', count: 0),
        );
        if (firstAlly.cardId != null) {
          try {
            final doc =
                await FirebaseFirestore.instance
                    .collection('cards')
                    .doc(firstAlly.cardId!)
                    .get();
            if (doc.exists) {
              final data = doc.data()!;
              _deck = _deck.copyWith(
                race: (data['raza'] as String?)?.trim() ?? _deck.race,
                edition:
                    (!isLibreFormat && (_deck.edition ?? '').trim().isEmpty)
                        ? (data['edicion'] as String?)?.trim()
                        : _deck.edition,
              );
            }
          } catch (_) {}
        }
      }
    }

    setState(() {
      final map = <String, DeckCardEntry>{
        for (final e in _activeCards) (e.cardId ?? e.name).toLowerCase(): e,
      };
      for (final e in added) {
        final key = (e.cardId ?? e.name).toLowerCase();
        final maxCopies = _copyLimitForEntry(e);
        if (maxCopies <= 0) continue;
        if (map.containsKey(key)) {
          final current = map[key]!;
          map[key] = current.copyWith(
            count: (current.count + e.count).clamp(1, maxCopies),
          );
        } else {
          map[key] = e.copyWith(count: e.count.clamp(1, maxCopies));
        }
      }
      _deck = _copyDeckWithActiveCards(map.values.toList());
    });
    _refreshAvailableCards();
  }

  void _removeEntry(DeckCardEntry e) {
    setState(() {
      _deck = _copyDeckWithActiveCards(
        _activeCards.where((x) => !identical(x, e)).toList(),
      );
    });
  }

  Future<void> _saveDraft() async {
    final result = _validationResult();
    if (!result.okForDraft) return;
    setState(() => _saving = true);
    try {
      final createdOk = await _ensureCreatedIfNeeded();
      if (!createdOk) return;
      // Se conservan las versiones elegidas por copia (solo visuales). Las
      // copias se comparten entre mazos, así que no hay conflictos de
      // reparto que revisar al guardar.
      final savedDeck = _deck.copyWith(updatedAt: DateTime.now());
      _deck = savedDeck;
      await _persist(savedDeck);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Mazo guardado.")));
      Navigator.pop(context, savedDeck);
    } catch (error, stackTrace) {
      debugPrint('Error guardando mazo: $error\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar el mazo: $error'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _setEntryCount(DeckCardEntry e, int newCount) {
    setState(() {
      if (newCount <= 0) {
        _deck = _copyDeckWithActiveCards(
          _activeCards.where((x) => !identical(x, e)).toList(),
        );
      } else {
        final idx = _activeCards.indexOf(e);
        if (idx >= 0) {
          final maxCopies = _copyLimitForEntry(e);
          if (maxCopies <= 0) {
            _deck = _copyDeckWithActiveCards(
              _activeCards.where((x) => !identical(x, e)).toList(),
            );
            return;
          }
          final clamped = newCount.clamp(1, maxCopies);
          final updated = e.copyWith(count: clamped);
          final newList = [..._activeCards]..[idx] = updated;
          _deck = _copyDeckWithActiveCards(newList);
        }
      }
    });
  }

  Future<void> _pickCount(DeckCardEntry e) async {
    final maxCopies = _copyLimitForEntry(e);
    if (maxCopies <= 0) {
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
            max: maxCopies,
            onDelete: () => Navigator.pop(context, 0),
          ),
    );
    if (sel != null) _setEntryCount(e, sel);
  }

  void _showIssues(List<ValidationIssue> issues) {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text("Problemas de validación"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children:
                  issues
                      .map(
                        (i) => Align(
                          alignment: Alignment.centerLeft,
                          child: Text("• ${i.message}"),
                        ),
                      )
                      .toList(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Ok"),
              ),
            ],
          ),
    );
  }

  void _closeEditor() {
    Navigator.pop(context, _deck);
  }

  List<DeckCardEntry> _sortedDeckCards([Iterable<DeckCardEntry>? source]) {
    final list = (source ?? _activeCards).toList();
    list.sort((a, b) {
      final typeCmp = _tabKeys
          .indexOf(_normalizeTipo(a.tipo))
          .compareTo(_tabKeys.indexOf(_normalizeTipo(b.tipo)));
      if (typeCmp != 0) return typeCmp;
      final countCmp = b.count.compareTo(a.count);
      if (countCmp != 0) return countCmp;
      final costCmp = (b.coste ?? 0).compareTo(a.coste ?? 0);
      if (costCmp != 0) return costCmp;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  Map<String, int> _countsByType() {
    final counts = <String, int>{for (final k in _tabKeys) k: 0};
    for (final e in _activeCards) {
      final k = _normalizeTipo(e.tipo);
      if (counts.containsKey(k)) counts[k] = counts[k]! + e.count;
    }
    return counts;
  }

  List<DeckCardEntry> _visibleCards() {
    final query = normalizeSearch(_searchCtrl.text);
    final cards = _sortedDeckCards().where((e) {
      final matchesType =
          _typeFilter == 'all' || _normalizeTipo(e.tipo) == _typeFilter;
      final matchesQuery =
          query.isEmpty ||
          normalizeSearch(e.name).contains(query) ||
          normalizeSearch(e.tipo ?? '').contains(query);
      return matchesType && matchesQuery;
    });
    return cards.toList();
  }

  @override
  Widget build(BuildContext context) {
    final result = _validationResult();
    final counts = _countsByType();
    final visibleCards = _visibleCards();

    return WillPopScope(
      onWillPop: () async {
        _closeEditor();
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF120D09),
        appBar: AppBar(
          backgroundColor: const Color(0xFF17110C),
          elevation: 0,
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            tooltip: 'Volver',
            onPressed: _closeEditor,
          ),
          title: const Text('Crear mazo'),
          titleTextStyle: const TextStyle(
            color: Color(0xFFF7E2A7),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
          iconTheme: const IconThemeData(color: Color(0xFFF7E2A7)),
        ),
        floatingActionButton:
            (MediaQuery.of(context).size.width < 600)
                ? FloatingActionButton.extended(
                  onPressed:
                      (!_saving && result.okForDraft) ? _saveDraft : null,
                  backgroundColor: const Color(0xFFD8B46A),
                  foregroundColor: const Color(0xFF24180F),
                  icon:
                      _saving
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF24180F),
                            ),
                          )
                          : const Icon(Icons.save_outlined),
                  label: const Text(
                    'Guardar Mazo',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                )
                : null,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1E1710), Color(0xFF120D09)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final screenWidth = MediaQuery.of(context).size.width;
                  final isMobile = screenWidth < 600;
                  final isWide = constraints.maxWidth >= 1120;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTopBar(context, result: result, counts: counts),
                      if (isMobile)
                        const SizedBox(height: 8)
                      else
                        const SizedBox(height: 14),
                      Expanded(
                        child:
                            isWide
                                ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 8,
                                      child: _buildEditorPanel(
                                        context,
                                        visibleCards: visibleCards,
                                        counts: counts,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    SizedBox(
                                      width: 380,
                                      child: _buildSummaryPanel(
                                        context,
                                        visibleCards: visibleCards,
                                        result: result,
                                        counts: counts,
                                      ),
                                    ),
                                  ],
                                )
                                : DefaultTabController(
                                  length: 2,
                                  child: Column(
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF21170F),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: const Color(
                                              0xFF9B7B45,
                                            ).withOpacity(.3),
                                          ),
                                        ),
                                        child: TabBar(
                                          indicatorColor: const Color(
                                            0xFFD8B46A,
                                          ),
                                          dividerColor: Colors.transparent,
                                          labelColor: const Color(0xFFD8B46A),
                                          unselectedLabelColor: Colors.white54,
                                          overlayColor: WidgetStateProperty.all(
                                            const Color(
                                              0xFFD8B46A,
                                            ).withOpacity(.08),
                                          ),
                                          labelStyle: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                          tabs: [
                                            const Tab(text: 'Catálogo'),
                                            Tab(text: 'Mazo (${_totalCards})'),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Expanded(
                                        child: TabBarView(
                                          children: [
                                            Column(
                                              children: [
                                                _buildFilterBar(context),
                                                const SizedBox(height: 10),
                                                Expanded(
                                                  child: _buildEditorPanel(
                                                    context,
                                                    visibleCards: visibleCards,
                                                    counts: counts,
                                                    hideFilters: true,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            _buildSummaryPanel(
                                              context,
                                              visibleCards: visibleCards,
                                              result: result,
                                              counts: counts,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    return DefaultTabController(
      length: _tabKeys.length,
      child: Scaffold(
        appBar: AppBar(title: const Text("Crear mazo racial")),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openAddCardsScreen,
          icon: const Icon(Icons.add),
          label: const Text("Agregar cartas"),
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: "Nombre del mazo",
                      ),
                      onChanged: _onNameChanged,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: _RacialField(label: "Raza", value: _deck.race),
                  ),
                  if (!_deck.isRacialLibre) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: _RacialField(
                        label: "Edición",
                        value: _deck.edition,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Builder(
                builder: (context) {
                  final counts = <String, int>{for (final k in _tabKeys) k: 0};
                  for (final e in _deck.cards) {
                    final k = _normalizeTipo(e.tipo);
                    if (counts.containsKey(k)) counts[k] = counts[k]! + e.count;
                  }
                  return TabBar(
                    isScrollable: true,
                    tabs:
                        _tabKeys.map((k) {
                          final label = _prettyType(k);
                          final c = counts[k] ?? 0;
                          return Tab(text: c > 0 ? "$label ($c)" : label);
                        }).toList(),
                  );
                },
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TabBarView(
                  children:
                      _tabKeys.map((k) {
                        final filtered =
                            _deck.cards
                                .where((e) => _normalizeTipo(e.tipo) == k)
                                .toList()
                              ..sort((a, b) {
                                final byCount = b.count.compareTo(a.count);
                                if (byCount != 0) return byCount;
                                return a.name.toLowerCase().compareTo(
                                  b.name.toLowerCase(),
                                );
                              });

                        if (filtered.isEmpty)
                          return const Center(
                            child: Text("Sin cartas de este tipo."),
                          );

                        return ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final e = filtered[i];
                            return FutureBuilder<String?>(
                              future: _resolveImageUrl(e),
                              builder: (context, snap) {
                                final imgUrl = _miniThumbSquare(
                                  snap.data,
                                  size: 56,
                                );
                                return ListTile(
                                  leading: SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child:
                                          (imgUrl != null && imgUrl.isNotEmpty)
                                              ? MylNetworkImage(
                                                imageUrl: imgUrl,
                                                fit: BoxFit.cover,
                                                placeholder:
                                                    (_, __) => const Center(
                                                      child: SizedBox(
                                                        width: 20,
                                                        height: 20,
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                            ),
                                                      ),
                                                    ),
                                                errorWidget:
                                                    (_, __, ___) => const Icon(
                                                      Icons
                                                          .image_not_supported_outlined,
                                                      size: 20,
                                                    ),
                                              )
                                              : const Center(
                                                child: Icon(
                                                  Icons
                                                      .image_not_supported_outlined,
                                                  size: 20,
                                                ),
                                              ),
                                    ),
                                  ),
                                  title: Row(
                                    children: [Expanded(child: Text(e.name))],
                                  ),
                                  subtitle: Text(
                                    [
                                      if (e.tipo != null && e.tipo!.isNotEmpty)
                                        e.tipo!,
                                      if (e.coste != null) "Coste ${e.coste}",
                                    ].join(" · "),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _QtyControl(
                                        value: e.count,
                                        onDec:
                                            () =>
                                                _setEntryCount(e, e.count - 1),
                                        onInc:
                                            () =>
                                                _setEntryCount(e, e.count + 1),
                                        onTapNumber: () => _pickCount(e),
                                        onLongPressDec:
                                            () => _setEntryCount(e, 1),
                                        onLongPressInc:
                                            () => _setEntryCount(e, 3),
                                        onDelete: () => _removeEntry(e),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        );
                      }).toList(),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [Expanded(child: Text("Total: $_totalCards/49"))]),
              const SizedBox(height: 8),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed:
                        (!_saving && result.okForDraft) ? _saveDraft : null,
                    icon: const Icon(Icons.save),
                    label: const Text("Guardar"),
                  ),
                  const SizedBox(width: 8),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Las copias disponibles se asignarán desde Mi carpeta al guardar.',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (result.issues.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Observaciones:",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    ...result.issues.map(
                      (i) => Text(
                        "• ${i.message}",
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on _CreateDeckScreenState {
  Widget _buildTopBar(
    BuildContext context, {
    required dynamic result,
    required Map<String, int> counts,
  }) {
    final title = _isNew ? 'Creando Mazo' : 'Editando Mazo';
    final hasIssues = result.issues.isNotEmpty;

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Container(
      padding: EdgeInsets.all(isMobile ? 10 : 12),
      decoration: BoxDecoration(
        color: const Color(0xFF21170F),
        borderRadius: BorderRadius.circular(isMobile ? 18 : 24),
        border: Border.all(color: const Color(0xFF9B7B45).withOpacity(.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isMobile) ...[
            TextField(
              controller: _nameCtrl,
              onChanged: _onNameChanged,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
              decoration: _deckInputDecoration(
                label: '$title:',
                hint: 'Nombre del mazo',
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (_deck.format != DeckFormat.full) ...[
                    _InfoChip(label: 'Raza', value: _deck.race ?? '-'),
                    const SizedBox(width: 8),
                  ],
                  if (_deck.format == DeckFormat.racial) ...[
                    _InfoChip(label: 'Edición', value: _deck.edition ?? '-'),
                    const SizedBox(width: 8),
                  ],
                  _FormatToggleChip(
                    format: _deck.format,
                    onChanged: _onFormatChanged,
                  ),
                  const SizedBox(width: 8),
                  _InfoChip(label: 'Cartas', value: '$_totalCards/49'),
                ],
              ),
            ),
          ] else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 280,
                  child: TextField(
                    controller: _nameCtrl,
                    onChanged: _onNameChanged,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                    decoration: _deckInputDecoration(
                      label: '$title:',
                      hint: 'Nombre del mazo',
                    ),
                  ),
                ),
                if (_deck.format != DeckFormat.full)
                  _InfoChip(label: 'Raza', value: _deck.race ?? '-'),
                if (_deck.format == DeckFormat.racial)
                  _InfoChip(label: 'Edición', value: _deck.edition ?? '-'),
                _FormatToggleChip(
                  format: _deck.format,
                  onChanged: _onFormatChanged,
                ),
                _InfoChip(label: 'Cartas', value: '$_totalCards/49'),
              ],
            ),
          if (hasIssues) ...[
            const SizedBox(height: 8),
            Text(
              result.issues.map((i) => i.message).join('  |  '),
              style: const TextStyle(color: Color(0xFFFF8E8E), fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: isMobile ? availableWidth : 260,
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: Colors.white),
                decoration: _deckInputDecoration(
                  hint: 'Buscar carta...',
                  prefixIcon: const Icon(Icons.search, color: Colors.white54),
                ),
              ),
            ),
            SizedBox(
              width: isMobile ? availableWidth : 200,
              child: DropdownButtonFormField<String>(
                value: _typeFilter,
                dropdownColor: const Color(0xFF24180F),
                style: const TextStyle(color: Colors.white),
                decoration: _deckInputDecoration(label: 'Tipo'),
                items: [
                  const DropdownMenuItem(
                    value: 'all',
                    child: Text('Todo tipo'),
                  ),
                  ..._CreateDeckScreenState._tabKeys.map(
                    (k) =>
                        DropdownMenuItem(value: k, child: Text(_prettyType(k))),
                  ),
                ],
                onChanged: (v) {
                  setState(() {
                    _typeFilter = v ?? 'all';
                  });
                  _refreshAvailableCards();
                },
              ),
            ),
            if (!isMobile)
              FilledButton.icon(
                onPressed:
                    (!_saving && _validationResult().okForDraft)
                        ? _saveDraft
                        : null,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Guardar'),
              ),
          ],
        );
      },
    );
  }

  Widget _buildEditorPanel(
    BuildContext context, {
    required List<DeckCardEntry> visibleCards,
    required Map<String, int> counts,
    bool hideFilters = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF21170F),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF9B7B45).withOpacity(.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hideFilters) ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final filters = Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children:
                      _CreateDeckScreenState._tabKeys.map((k) {
                        final selected = _typeFilter == k;
                        return FilterChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(_prettyType(k)),
                          selected: selected,
                          onSelected: (_) {
                            setState(() => _typeFilter = selected ? 'all' : k);
                            _refreshAvailableCards();
                          },
                        );
                      }).toList(),
                );

                final search = TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(color: Colors.white),
                  decoration: _deckInputDecoration(
                    hint: 'Buscar carta...',
                    prefixIcon: const Icon(Icons.search, color: Colors.white54),
                    isDense: true,
                  ),
                );

                if (compact) {
                  return Column(
                    children: [
                      search,
                      const SizedBox(height: 8),
                      Align(alignment: Alignment.centerLeft, child: filters),
                    ],
                  );
                }

                return Row(
                  children: [
                    SizedBox(width: 240, child: search),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: filters,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed:
                          (!_saving && _validationResult().okForDraft)
                              ? _saveDraft
                              : null,
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text('Guardar'),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
          ],
          Expanded(
            child:
                _loadingAvailable
                    ? const Center(child: CircularProgressIndicator())
                    : _availableCards.isEmpty
                    ? const Center(
                      child: Text(
                        'No hay cartas usables para este filtro.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                    : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 190,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: .58,
                          ),
                      itemCount: _availableCards.length,
                      itemBuilder: (context, index) {
                        final card = _availableCards[index];
                        final blocked = _isBlockedAvailableCard(card);
                        final deckFull = _isDeckFull();
                        return FutureBuilder<String?>(
                          future: _resolveImageUrl(
                            DeckCardEntry(
                              cardId: card.id,
                              name: card.nombre,
                              count: 1,
                              coste: card.coste,
                              tipo: card.tipo,
                            ),
                          ),
                          builder: (context, snap) {
                            return _AvailableCardTile(
                              card: card,
                              imageUrl: snap.data,
                              copiesInDeck: _countInDeck(card),
                              blocked: blocked,
                              maxCopies: _copyLimitForCard(card),
                              onAdd:
                                  (blocked || deckFull)
                                      ? null
                                      : () => _addAvailableCard(card),
                              onPreview:
                                  () => showCardImagePreview(
                                    context,
                                    cardName: card.nombre,
                                    imageUrl: snap.data,
                                  ),
                              deckFull: deckFull,
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

  Widget _buildSummaryPanel(
    BuildContext context, {
    required List<DeckCardEntry> visibleCards,
    required dynamic result,
    required Map<String, int> counts,
  }) {
    final ordered = _sortedDeckCards();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF17110C),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF9B7B45).withOpacity(.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$_totalCards/49 Cartas',
            style: const TextStyle(
              color: Color(0xFFF7E2A7),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          if ((_deck.coverUrl ?? '').isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(.18),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: MylNetworkImage(
                        imageUrl: safeImageUrl(_deck.coverUrl!) ?? '',
                        fit: BoxFit.cover,
                        placeholder:
                            (_, __) => const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                        errorWidget:
                            (_, __, ___) => const ColoredBox(
                              color: Color(0xFF33271D),
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                color: Colors.white54,
                              ),
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Portada actual del mazo',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _uploadingCover ? null : _clearCover,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Quitar'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 18,
            runSpacing: 10,
            children:
                _CreateDeckScreenState._tabKeys
                    .map(
                      (k) => Text(
                        '${_prettyType(k)}: ${counts[k] ?? 0}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: ordered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final e = ordered[index];
                return FutureBuilder<String?>(
                  future: _resolveImageUrl(e),
                  builder: (context, snap) {
                    final thumb = _miniThumbSquare(snap.data, size: 56);
                    final isCurrentCover =
                        (_deck.coverCardId ?? '') == (e.cardId ?? '');
                    return Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(.22),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color:
                              isCurrentCover
                                  ? const Color(0xFFF1D184).withOpacity(.7)
                                  : Colors.white10,
                        ),
                      ),
                      child: Row(
                        children: [
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: _DeckCardImage(
                                    cardId: e.cardId,
                                    fallbackTipo: e.tipo,
                                    initialUrl: thumb,
                                    fit: BoxFit.cover,
                                    width: 48,
                                    height: 48,
                                  ),
                                ),
                              ),
                              if (isCurrentCover)
                                Positioned(
                                  right: 2,
                                  bottom: 2,
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF20160D),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.crop_square_rounded,
                                      size: 14,
                                      color: Color(0xFFF1D184),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              e.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Ampliar carta',
                            onPressed:
                                () => showCardImagePreview(
                                  context,
                                  cardName: e.name,
                                  imageUrl: snap.data,
                                ),
                            icon: const Icon(Icons.zoom_out_map_rounded),
                            color: const Color(0xFFD8B46A),
                            visualDensity: VisualDensity.compact,
                          ),
                          _SummaryQtyControl(
                            value: e.count,
                            onDec: () => _setEntryCount(e, e.count - 1),
                            onInc: () => _setEntryCount(e, e.count + 1),
                            onTapNumber: () => _pickCount(e),
                            onDelete: () => _removeEntry(e),
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

  InputDecoration _deckInputDecoration({
    String? label,
    String? hint,
    Widget? prefixIcon,
    bool isDense = false,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon,
      isDense: isDense,
      contentPadding:
          isDense
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
              : null,
      filled: true,
      fillColor: const Color(0xFF0F0A07),
      labelStyle: const TextStyle(color: Colors.white70),
      hintStyle: const TextStyle(color: Colors.white38),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: const Color(0xFFB58B47).withOpacity(.35)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: const Color(0xFFB58B47).withOpacity(.35)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFD7B36A)),
      ),
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

  Uint8List _buildCropBytes() {
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
    return Uint8List.fromList(img.encodeJpg(square, quality: 92));
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
                  onPressed: () => Navigator.pop(context, _buildCropBytes()),
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

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(color: Colors.white60),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormatToggleChip extends StatelessWidget {
  final DeckFormat format;
  final ValueChanged<DeckFormat> onChanged;

  const _FormatToggleChip({required this.format, required this.onChanged});

  static const _gold = Color(0xFFD8B46A);

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<DeckFormat>(
      segments: const [
        ButtonSegment(
          value: DeckFormat.racial,
          label: Text('Racial'),
          icon: Icon(Icons.shield_outlined),
        ),
        ButtonSegment(
          value: DeckFormat.racialLibre,
          label: Text('Racial Libre'),
          icon: Icon(Icons.public_outlined),
        ),
        ButtonSegment(
          value: DeckFormat.full,
          label: Text('Formato Libre'),
          icon: Icon(Icons.all_inclusive_rounded),
        ),
      ],
      selected: {format},
      onSelectionChanged: (s) => onChanged(s.first),
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return _gold.withOpacity(.2);
          }
          return Colors.black.withOpacity(.18);
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return _gold;
          return Colors.white70;
        }),
        side: WidgetStateProperty.resolveWith((states) {
          return BorderSide(
            color:
                states.contains(WidgetState.selected) ? _gold : Colors.white10,
          );
        }),
      ),
    );
  }
}

class _DeckCardImage extends StatelessWidget {
  final String? cardId;
  final String? fallbackTipo;
  final String? initialUrl;
  final BoxFit fit;
  final double? width;
  final double? height;

  const _DeckCardImage({
    this.cardId,
    this.fallbackTipo,
    this.initialUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  static String? _safe(String? url) {
    if (url == null || url!.isEmpty) return null;
    if (url.contains('drive.google.com')) return DriveService.webSafeUrl(url);
    return url;
  }

  String? _pickFromDoc(Map<String, dynamic> m) {
    for (final key in [
      'officialImageUrl',
      'imageUrl',
      'officialImage',
      'frontUrl',
      'img',
      'url',
    ]) {
      final v = _safe(m[key]?.toString());
      if (v != null && v.isNotEmpty) return v;
    }
    final images = m['images'];
    if (images is Map) {
      for (final k in ['front', 'anverso']) {
        final v = _safe(images[k]?.toString());
        if (v != null && v.isNotEmpty) return v;
      }
    }
    return null;
  }

  String? _pickFromVariant(Map<String, dynamic> m) {
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
        final v = _safe(thumbs[k]?.toString());
        if (v != null && v.isNotEmpty) return v;
      }
      for (final v in thumbs.values) {
        final s = _safe(v?.toString());
        if (s != null && s.isNotEmpty) return s;
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
      final v = _safe(m[key]?.toString());
      if (v != null && v.isNotEmpty) return v;
    }
    final images = m['images'];
    if (images is Map) {
      for (final k in ['front', 'anverso']) {
        final v = _safe(images[k]?.toString());
        if (v != null && v.isNotEmpty) return v;
      }
    }
    return null;
  }

  Widget _fallback() {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFF2A2118),
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_not_supported_outlined,
        color: Colors.white54,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveWidth = width;
    final effectiveHeight = height;
    final hasCardId = (cardId ?? '').isNotEmpty;

    if (!hasCardId) {
      final url = initialUrl;
      if (url != null && url.isNotEmpty) {
        return SizedBox(
          width: effectiveWidth,
          height: effectiveHeight,
          child: MylNetworkImage(
            imageUrl: safeImageUrl(url) ?? '',
            fit: fit,
            placeholder: (_, __) => _fallback(),
            errorWidget: (_, __, ___) => _fallback(),
          ),
        );
      }
      return _fallback();
    }

    final cardRef = FirebaseFirestore.instance.collection('cards').doc(cardId!);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: cardRef.snapshots(),
      builder: (context, docSnap) {
        String? topUrl;
        if (docSnap.hasData &&
            docSnap.data != null &&
            docSnap.data!.data() != null) {
          topUrl = _pickFromDoc(docSnap.data!.data()!);
        }
        if (topUrl != null && topUrl.isNotEmpty) {
          return SizedBox(
            width: effectiveWidth,
            height: effectiveHeight,
            child: MylNetworkImage(
              imageUrl: topUrl,
              fit: fit,
              placeholder: (_, __) => _fallback(),
              errorWidget: (_, __, ___) => _fallback(),
            ),
          );
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream:
              cardRef
                  .collection('variants')
                  .orderBy('official', descending: true)
                  .orderBy('isBase', descending: true)
                  .orderBy('name')
                  .snapshots(),
          builder: (context, variantsSnap) {
            String? url;
            if (variantsSnap.hasData) {
              for (final d in variantsSnap.data!.docs) {
                url = _pickFromVariant(d.data());
                if (url != null && url.isNotEmpty) break;
              }
            }
            if (url != null && url.isNotEmpty) {
              return SizedBox(
                width: effectiveWidth,
                height: effectiveHeight,
                child: MylNetworkImage(
                  imageUrl: url,
                  fit: fit,
                  placeholder: (_, __) => _fallback(),
                  errorWidget: (_, __, ___) => _fallback(),
                ),
              );
            }
            if (initialUrl != null && initialUrl!.isNotEmpty) {
              return SizedBox(
                width: effectiveWidth,
                height: effectiveHeight,
                child: MylNetworkImage(
                  imageUrl: safeImageUrl(initialUrl!) ?? '',
                  fit: fit,
                  placeholder: (_, __) => _fallback(),
                  errorWidget: (_, __, ___) => _fallback(),
                ),
              );
            }
            return _fallback();
          },
        );
      },
    );
  }
}

class _DeckEditorCard extends StatelessWidget {
  final DeckCardEntry entry;
  final String? imageUrl;
  final VoidCallback onDec;
  final VoidCallback onInc;
  final VoidCallback onPickCount;
  final VoidCallback onDelete;

  const _DeckEditorCard({
    required this.entry,
    required this.imageUrl,
    required this.onDec,
    required this.onInc,
    required this.onPickCount,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF18110C),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFB58B47).withOpacity(.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _DeckCardImage(
                    cardId: entry.cardId,
                    fallbackTipo: entry.tipo,
                    initialUrl: imageUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: _SmallBadge(
                      label: entry.coste?.toString() ?? '-',
                      filled: true,
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: _SmallBadge(label: 'x${entry.count}', filled: true),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if ((entry.tipo ?? '').isNotEmpty) entry.tipo!,
                    if (entry.coste != null) 'Coste ${entry.coste}',
                  ].join(' • '),
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _RoundMiniAction(icon: Icons.remove, onTap: onDec),
                    Expanded(
                      child: Center(
                        child: TextButton(
                          onPressed: onPickCount,
                          child: Text('x${entry.count}'),
                        ),
                      ),
                    ),
                    _RoundMiniAction(icon: Icons.add, onTap: onInc),
                    const SizedBox(width: 6),
                    _RoundMiniAction(
                      icon: Icons.delete_outline,
                      onTap: onDelete,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailableCardTile extends StatelessWidget {
  final CardMyL card;
  final String? imageUrl;
  final int copiesInDeck;
  final bool blocked;
  final int maxCopies;
  final bool deckFull;
  final VoidCallback? onAdd;
  final VoidCallback onPreview;
  final VoidCallback? onTapVariants;

  const _AvailableCardTile({
    required this.card,
    required this.imageUrl,
    required this.copiesInDeck,
    required this.blocked,
    required this.maxCopies,
    required this.deckFull,
    required this.onAdd,
    required this.onPreview,
    this.onTapVariants,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: blocked ? .45 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF18110C),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                blocked
                    ? Colors.grey.withOpacity(.45)
                    : const Color(0xFFB58B47).withOpacity(.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        color: const Color(0xFF2A2118),
                        child: _DeckCardImage(
                          cardId: card.id,
                          fallbackTipo: card.tipo,
                          initialUrl: imageUrl,
                          fit: BoxFit.contain,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      ),
                      if (card.unica)
                        const Positioned(
                          top: 8,
                          right: 8,
                          child: _SmallBadge(label: 'Unica'),
                        ),
                      if (blocked)
                        const Center(
                          child: Icon(
                            Icons.block_rounded,
                            color: Colors.white70,
                            size: 30,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    copiesInDeck > 0 ? 'En mazo: x$copiesInDeck' : 'Disponible',
                    style: TextStyle(
                      color: blocked ? Colors.white54 : const Color(0xFFF1D184),
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                  if (maxCopies < 3) ...[
                    const SizedBox(height: 3),
                    Text(
                      maxCopies <= 0
                          ? 'Limitada a 0 copias'
                          : 'Limitada a $maxCopies copias',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFFF6B6B),
                        fontWeight: FontWeight.w800,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: onAdd,
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                blocked
                                    ? Colors.grey.shade700
                                    : const Color(0xFFD8B46A),
                            foregroundColor: const Color(0xFF24180F),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            minimumSize: const Size(0, 32),
                          ),
                          child: Text(
                            blocked
                                ? 'No valida'
                                : (deckFull ? 'Mazo lleno' : 'Agregar'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: onPreview,
                        icon: const Icon(Icons.zoom_out_map_rounded, size: 20),
                        color: const Color(0xFFD8B46A),
                        tooltip: 'Ampliar carta',
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF24180F),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: const Color(0xFFB58B47).withOpacity(0.5),
                            ),
                          ),
                          minimumSize: const Size(32, 32),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                      if (card.variantes.isNotEmpty &&
                          onTapVariants != null) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: onTapVariants,
                          icon: const Icon(Icons.palette_outlined, size: 20),
                          color: const Color(0xFFD8B46A),
                          tooltip: 'Seleccionar variante',
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFF24180F),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: const Color(0xFFB58B47).withOpacity(0.5),
                              ),
                            ),
                            minimumSize: const Size(32, 32),
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ],
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

class _SmallBadge extends StatelessWidget {
  final String label;
  final bool filled;

  const _SmallBadge({required this.label, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? Colors.black.withOpacity(.68) : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFF1D184).withOpacity(.8)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _RoundMiniAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundMiniAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white12),
          color: Colors.black.withOpacity(.18),
        ),
        child: Icon(icon, size: 18, color: Colors.white70),
      ),
    );
  }
}

class _SummaryQtyControl extends StatelessWidget {
  final int value;
  final VoidCallback onDec;
  final VoidCallback onInc;
  final VoidCallback onTapNumber;
  final VoidCallback onDelete;

  const _SummaryQtyControl({
    required this.value,
    required this.onDec,
    required this.onInc,
    required this.onTapNumber,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RoundMiniAction(icon: Icons.remove, onTap: onDec),
        InkWell(
          onTap: onTapNumber,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: Text(
              'x$value',
              style: const TextStyle(
                color: Color(0xFFF1D184),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        _RoundMiniAction(icon: Icons.add, onTap: onInc),
        const SizedBox(width: 4),
        _RoundMiniAction(icon: Icons.delete_outline, onTap: onDelete),
      ],
    );
  }
}

class _RacialField extends StatelessWidget {
  final String label;
  final String? value;
  const _RacialField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: TextEditingController(text: value ?? "-"),
      readOnly: true,
      decoration: InputDecoration(labelText: label),
    );
  }
}

class _QtyControl extends StatelessWidget {
  final int value;
  final VoidCallback onDec;
  final VoidCallback onInc;
  final VoidCallback onTapNumber;
  final VoidCallback onLongPressDec;
  final VoidCallback onLongPressInc;
  final VoidCallback onDelete;
  final VoidCallback? onTapVariants;

  const _QtyControl({
    required this.value,
    required this.onDec,
    required this.onInc,
    required this.onTapNumber,
    required this.onLongPressDec,
    required this.onLongPressInc,
    required this.onDelete,
    this.onTapVariants,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RoundIcon(
          icon: Icons.remove,
          tooltip: 'Disminuir (mantener para 1)',
          onPressed: onDec,
          onLongPress: onLongPressDec,
        ),
        InkWell(
          onTap: onTapNumber,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Text('x$value', style: theme.textTheme.bodyMedium),
          ),
        ),
        _RoundIcon(
          icon: Icons.add,
          tooltip: 'Aumentar (mantener para 3)',
          onPressed: onInc,
          onLongPress: onLongPressInc,
        ),
        const SizedBox(width: 6),
        if (onTapVariants != null) ...[
          IconButton(
            icon: const Icon(Icons.palette_outlined, color: Color(0xFFD8B46A)),
            tooltip: 'Seleccionar variantes',
            onPressed: onTapVariants,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          const SizedBox(width: 2),
        ],
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Eliminar carta',
          onPressed: onDelete,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final VoidCallback onLongPress;
  const _RoundIcon({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        onLongPress: onLongPress,
        customBorder: const CircleBorder(),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Icon(icon, size: 18),
        ),
      ),
    );
  }
}

class _CountPicker extends StatefulWidget {
  final String title;
  final int current;
  final int max;
  final VoidCallback onDelete;

  const _CountPicker({
    required this.title,
    required this.current,
    this.max = 3,
    required this.onDelete,
  });

  @override
  State<_CountPicker> createState() => _CountPickerState();
}

class _CountPickerState extends State<_CountPicker> {
  late int _sel;

  @override
  void initState() {
    super.initState();
    _sel = widget.current.clamp(1, widget.max);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 4,
              width: 40,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: List.generate(widget.max, (i) {
                final v = i + 1;
                final selected = _sel == v;
                return ChoiceChip(
                  label: Text('$v'),
                  selected: selected,
                  onSelected: (_) => setState(() => _sel = v),
                );
              }),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton.icon(
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Eliminar'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.pop<int>(context, _sel),
                  child: const Text('Aceptar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
