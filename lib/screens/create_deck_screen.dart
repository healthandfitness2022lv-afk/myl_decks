import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/deck.dart';
import '../../services/deck_service.dart';
import '../../services/card_service.dart';
import '../../domain/validation/deck_validator.dart';
import 'add_cards_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CreateDeckScreen extends StatefulWidget {
  final Deck? editDeck;
  const CreateDeckScreen({super.key, this.editDeck});

  @override
  State<CreateDeckScreen> createState() => _CreateDeckScreenState();
}

class _CreateDeckScreenState extends State<CreateDeckScreen> {
  late DeckService _service;
  late CardService _cardService;
  late Deck _deck;
  late bool _isNew;
  bool get isTarget => _deck.status == DeckStatus.published;
  bool? _isBasic;
  late String _uid;
  final _nameCtrl = TextEditingController();
  bool _saving = false;
  final Map<String, String?> _imgCache = {};
  static const String kOfficialImageUrlField = 'officialImageUrl';
  static const String kLegacyImageUrlField = 'imageUrl';

  static const List<String> _tabKeys = [
    'aliado',
    'talisman',
    'arma',
    'oro',
    'totem',
  ];

  bool _isInitial(DeckCardEntry e) {
    if ((_deck.initialGoldCardId ?? '').isNotEmpty) {
      return e.cardId == _deck.initialGoldCardId;
    }
    if ((_deck.initialGoldName ?? '').isNotEmpty) {
      return e.name.trim().toLowerCase() ==
          _deck.initialGoldName!.trim().toLowerCase();
    }
    return false;
  }

  Future<void> _showUpgradeDialog() async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Límite alcanzado"),
        content: const Text(
          "Tu cuenta básica permite hasta 2 mazos. Para crear más mazos, cambia a la versión Pro.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Aceptar")),
        ],
      ),
    );
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
        const superAdminEmails = <String>['hecturnicolas@gmail.com'];
        const superAdminUids = <String>[];

        if (isSuperFlag || superAdminEmails.contains(email) || superAdminUids.contains(_uid)) {
          return true;
        }
        if (isProFlag || role == 'pro' || plan == 'pro' || plan == 'premium') {
          return true;
        }
      }

      const int basicLimit = 2;
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('decks')
          .limit(basicLimit)
          .get();

      final int existing = snap.docs.length;
      if (existing >= basicLimit) {
        await _showUpgradeDialog();
        return false;
      }

      return true;
    } catch (e, st) {
      print('Error checking deck limit: $e\n$st');
      return true;
    }
  }

  Future<bool> _ensureCreatedIfNeeded() async {
    if (!_isNew) return true;
    final canCreate = await _canCreateNewDeck();
    if (!canCreate) return false;
    final name = (_deck.name.isEmpty) ? 'Mazo sin nombre' : _deck.name;
    final newId = await _service.create(name);
    _deck = _deck.copyWith(id: newId, ownerId: _uid, updatedAt: DateTime.now());
    _isNew = false;
    return true;
  }

  void _setInitialGoldFromEntry(DeckCardEntry e) {
    if ((e.tipo ?? '').toLowerCase() != 'oro') return;
    setState(() {
      _deck = _deck.copyWith(
        initialGoldCardId: e.cardId,
        initialGoldName: e.name,
        updatedAt: DateTime.now(),
      );
    });
  }

  void _clearInitialGold() {
    setState(() {
      _deck = _deck.copyWith(
        initialGoldCardId: null,
        initialGoldName: null,
        updatedAt: DateTime.now(),
      );
    });
  }

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
        return key.isEmpty ? 'Otros' : (key[0].toUpperCase() + key.substring(1));
    }
  }

  @override
  void initState() {
    super.initState();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('No hay usuario autenticado. Inicia sesión antes de usar CreateDeckScreen.');
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
              status: DeckStatus.draft,
            ))
        .copyWith(isRacial: true);

    _nameCtrl.text = _deck.name;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_isNew) return;
      final canCreate = await _canCreateNewDeck();
      if (!canCreate && mounted) {
        Navigator.pop(context);
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  int get _totalCards => _deck.cards.fold<int>(0, (s, e) => s + e.count);

  Future<void> _loadUserPlan() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(_uid).get();
      final data = doc.data() ?? <String, dynamic>{};
      final role = (data['role'] as String?)?.toLowerCase();
      final plan = (data['plan'] as String?)?.toLowerCase();
      final isProFlag = (data['isPro'] as bool?) ?? false;
      final isSuperFlag = (data['isSuperAdmin'] as bool?) ?? false;
      final email = (data['email'] as String? ?? '').toLowerCase();
      const superAdminEmails = <String>['hecturnicolas@gmail.com'];

      final isBasic = !(
        isProFlag ||
        role == 'pro' ||
        plan == 'pro' ||
        plan == 'premium' ||
        isSuperFlag ||
        superAdminEmails.contains(email)
      );

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
    const superAdminEmails = <String>['hecturnicolas@gmail.com'];

    bool isSuperAdmin = false;
    try {
      if (uid != null) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
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

    final snap = await FirebaseFirestore.instance.collection('users').doc(uid).collection('decks').get();
    final allDecks = snap.docs.map((d) => Deck.fromFirestore(d.id, d.data())).where((d) => d.id != _deck.id).toList();

    if (!mounted) return;

    final chosen = await showDialog<Deck>(
      context: context,
      builder: (ctx) => AlertDialog(
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
        _deck = _deck.copyWith(linkedDeckId: chosen.id, updatedAt: DateTime.now());
      });
      await _service.save(_deck);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Vinculado a '${chosen.name}'")));
      }
    }
  }

  void _onNameChanged(String v) {
    _deck = _deck.copyWith(name: v.trim(), updatedAt: DateTime.now());
  }

  String _keyForEntry(DeckCardEntry e) => (e.cardId ?? e.name).trim().toLowerCase();

  String? _miniThumbSquare(String? url, {int size = 56}) {
    if (url == null || url.isEmpty) return url;
    if (!url.contains('/upload/')) return url;
    return url.replaceFirst('/upload/', '/upload/f_auto,q_auto,w_$size,h_$size,c_fill,g_auto/');
  }

  Future<String?> _resolveImageUrl(DeckCardEntry e) async {
    final key = _keyForEntry(e);
    if (_imgCache.containsKey(key)) return _imgCache[key];

    Future<String?> _fromCardDoc(DocumentSnapshot<Map<String, dynamic>> doc) async {
      final data = doc.data();
      if (data == null) return null;
      final official = (data[kOfficialImageUrlField] as String?)?.trim();
      if (official != null && official.isNotEmpty) return official;
      try {
        final offSnap = await doc.reference.collection('variants').where('official', isEqualTo: true).limit(1).get();
        if (offSnap.docs.isNotEmpty) {
          final url = (offSnap.docs.first.data()['imageFrontUrl'] as String?)?.trim();
          if (url != null && url.isNotEmpty) return url;
        }
      } catch (_) {}
      final legacy = (data[kLegacyImageUrlField] as String?)?.trim();
      if (legacy != null && legacy.isNotEmpty) return legacy;
      return null;
    }

    String? url;
    try {
      if (e.cardId != null && e.cardId!.isNotEmpty) {
        final doc = await FirebaseFirestore.instance.collection('cards').doc(e.cardId!).get();
        if (doc.exists) url = await _fromCardDoc(doc);
      }
      if (url == null || url.isEmpty) {
        final nameLower = e.name.trim().toLowerCase();
        if (nameLower.isNotEmpty) {
          final q = await FirebaseFirestore.instance.collection('cards').where('nameLower', isEqualTo: nameLower).limit(1).get();
          if (q.docs.isNotEmpty) url = await _fromCardDoc(q.docs.first);
        }
      }
    } catch (_) {}
    _imgCache[key] = url;
    return url;
  }

  Future<void> _openAddCardsScreen() async {
    final editionToPass = (_deck.edition?.trim().isEmpty ?? true) ? null : _deck.edition!.trim();
    final raceToPass = (_deck.race?.trim().isEmpty ?? true) ? null : _deck.race!.trim();

    final added = await Navigator.push<List<DeckCardEntry>>(
      context,
      MaterialPageRoute(
        builder: (_) => AddCardsScreen(
          cardService: _cardService,
          currentRace: raceToPass,
          currentEdition: editionToPass,
        ),
      ),
    );

    if (added == null || added.isEmpty) return;

    if (_deck.race == null || _deck.edition == null) {
      final firstAlly = added.firstWhere(
        (e) => (e.tipo ?? '').toLowerCase() == 'aliado',
        orElse: () => DeckCardEntry(cardId: null, name: '', count: 0),
      );
      if (firstAlly.cardId != null) {
        try {
          final doc = await FirebaseFirestore.instance.collection('cards').doc(firstAlly.cardId!).get();
          if (doc.exists) {
            final data = doc.data()!;
            _deck = _deck.copyWith(
              race: (data['raza'] as String?)?.trim() ?? _deck.race,
              edition: (data['edicion'] as String?)?.trim() ?? _deck.edition,
            );
          }
        } catch (_) {}
      }
    }

    setState(() {
      final map = <String, DeckCardEntry>{for (final e in _deck.cards) (e.cardId ?? e.name).toLowerCase(): e};
      for (final e in added) {
        final key = (e.cardId ?? e.name).toLowerCase();
        if (map.containsKey(key)) {
          final current = map[key]!;
          map[key] = current.copyWith(count: (current.count + e.count).clamp(1, 3));
        } else {
          map[key] = e;
        }
      }
      _deck = _deck.copyWith(cards: map.values.toList(), updatedAt: DateTime.now());
    });
  }

  void _removeEntry(DeckCardEntry e) {
    setState(() {
      final removingInitial = _isInitial(e);
      _deck = _deck.copyWith(
        cards: _deck.cards.where((x) => !identical(x, e)).toList(),
        initialGoldCardId: removingInitial ? null : _deck.initialGoldCardId,
        initialGoldName: removingInitial ? null : _deck.initialGoldName,
        updatedAt: DateTime.now(),
      );
    });
  }

  Future<void> _saveDraft() async {
    final result = validateDeck(deck: _deck, catalogById: const {}, catalogByName: const {});
    if (!result.okForDraft) return;
    setState(() => _saving = true);
    try {
      final createdOk = await _ensureCreatedIfNeeded();
      if (!createdOk) return;
      await _service.save(_deck.copyWith(updatedAt: DateTime.now()));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mazo guardado.")));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _publish() async {
    final hasInitial = (_deck.initialGoldCardId?.isNotEmpty ?? false) || (_deck.initialGoldName?.trim().isNotEmpty ?? false);
    if (!hasInitial) {
      final firstOro = _deck.cards.firstWhere((e) => (e.tipo ?? '').toLowerCase() == 'oro', orElse: () => const DeckCardEntry(name: '', count: 0));
      if (firstOro.name.isNotEmpty) _setInitialGoldFromEntry(firstOro);
    }

    final result = validateDeck(deck: _deck, catalogById: const {}, catalogByName: const {});
    if (!result.okForPublish) {
      _showIssues(result.issues);
      return;
    }

    final createdOk = await _ensureCreatedIfNeeded();
    if (!createdOk) return;

    final now = DateTime.now();
    final savedDeck = _deck.copyWith(updatedAt: now);
    await _service.save(savedDeck);

    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mazo guardado/publicado.")));
  }

  void _setEntryCount(DeckCardEntry e, int newCount) {
    setState(() {
      if (newCount <= 0) {
        _deck = _deck.copyWith(cards: _deck.cards.where((x) => !identical(x, e)).toList(), updatedAt: DateTime.now());
      } else {
        final idx = _deck.cards.indexOf(e);
        if (idx >= 0) {
          final clamped = newCount.clamp(1, 3);
          final updated = e.copyWith(count: clamped);
          final newList = [..._deck.cards]..[idx] = updated;
          _deck = _deck.copyWith(cards: newList, updatedAt: DateTime.now());
        }
      }
    });
  }

  Future<void> _pickCount(DeckCardEntry e) async {
    final sel = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (_) => _CountPicker(title: e.name, current: e.count, max: 3, onDelete: () => Navigator.pop(context, 0)),
    );
    if (sel != null) _setEntryCount(e, sel);
  }

  void _showIssues(List<ValidationIssue> issues) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Problemas de validación"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: issues.map((i) => Align(alignment: Alignment.centerLeft, child: Text("• ${i.message}"))).toList(),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Ok"))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = validateDeck(deck: _deck, catalogById: const {}, catalogByName: const {});

    return DefaultTabController(
      length: _tabKeys.length,
      child: Scaffold(
        appBar: AppBar(title: const Text("Crear mazo racial")),
        floatingActionButton: FloatingActionButton.extended(onPressed: _openAddCardsScreen, icon: const Icon(Icons.add), label: const Text("Agregar cartas")),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(flex: 2, child: TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: "Nombre del mazo"), onChanged: _onNameChanged)),
                  const SizedBox(width: 12),
                  Expanded(flex: 1, child: _RacialField(label: "Raza", value: _deck.race)),
                  const SizedBox(width: 12),
                  Expanded(flex: 1, child: _RacialField(label: "Edición", value: _deck.edition)),
                ],
              ),
              const SizedBox(height: 4),
              Builder(builder: (context) {
                final counts = <String, int>{for (final k in _tabKeys) k: 0};
                for (final e in _deck.cards) {
                  final k = _normalizeTipo(e.tipo);
                  if (counts.containsKey(k)) counts[k] = counts[k]! + e.count;
                }
                return TabBar(isScrollable: true, tabs: _tabKeys.map((k) {
                  final label = _prettyType(k);
                  final c = counts[k] ?? 0;
                  return Tab(text: c > 0 ? "$label ($c)" : label);
                }).toList());
              }),
              const SizedBox(height: 8),
              Expanded(
                child: TabBarView(
                  children: _tabKeys.map((k) {
                    final filtered = _deck.cards.where((e) => _normalizeTipo(e.tipo) == k).toList()
                      ..sort((a, b) {
                        final byCount = b.count.compareTo(a.count);
                        if (byCount != 0) return byCount;
                        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
                      });

                    if (filtered.isEmpty) return const Center(child: Text("Sin cartas de este tipo."));

                    return ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final e = filtered[i];
                        return FutureBuilder<String?>(
                          future: _resolveImageUrl(e),
                          builder: (context, snap) {
                            final imgUrl = _miniThumbSquare(snap.data, size: 56);
                            return ListTile(
                              onLongPress: () {
                                if ((e.tipo ?? '').toLowerCase() == 'oro') {
                                  _setInitialGoldFromEntry(e);
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"${e.name}" marcado como Oro inicial.')));
                                }
                              },
                              leading: SizedBox(
                                width: 48,
                                height: 48,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: (imgUrl != null && imgUrl.isNotEmpty)
                                      ? Image.network(
                                          imgUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_outlined, size: 20),
                                          loadingBuilder: (c, w, p) => p == null ? w : const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                                        )
                                      : const Center(child: Icon(Icons.image_not_supported_outlined, size: 20)),
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(child: Text(e.name)),
                                  if (_isInitial(e))
                                    Container(
                                      margin: const EdgeInsets.only(left: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.primary.withOpacity(.12),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: const Text('Inicial', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                    ),
                                ],
                              ),
                              subtitle: Text([
                                if (e.tipo != null && e.tipo!.isNotEmpty) e.tipo!,
                                if (e.coste != null) "Coste ${e.coste}",
                              ].join(" · ")),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _QtyControl(
                                    value: e.count,
                                    onDec: () => _setEntryCount(e, e.count - 1),
                                    onInc: () => _setEntryCount(e, e.count + 1),
                                    onTapNumber: () => _pickCount(e),
                                    onLongPressDec: () => _setEntryCount(e, 1),
                                    onLongPressInc: () => _setEntryCount(e, 3),
                                    onDelete: () => _removeEntry(e),
                                  ),
                                  if ((e.tipo ?? '').toLowerCase() == 'oro')
                                    IconButton(
                                      tooltip: _isInitial(e) ? 'Quitar Oro inicial' : 'Marcar como Oro inicial',
                                      icon: Icon(_isInitial(e) ? Icons.star : Icons.star_border),
                                      onPressed: () {
                                        if (_isInitial(e)) {
                                          _clearInitialGold();
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Oro inicial quitado.')));
                                        } else {
                                          _setInitialGoldFromEntry(e);
                                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"${e.name}" marcado como Oro inicial.')));
                                        }
                                      },
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
              Row(children: [Expanded(child: Text("Total: $_totalCards/50"))]),
              const SizedBox(height: 8),
              Row(
                children: [
                  ElevatedButton.icon(onPressed: (!_saving && result.okForDraft) ? _saveDraft : null, icon: const Icon(Icons.save), label: const Text("Guardar")),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(onPressed: (!_saving && result.okForPublish) ? _publish : null, icon: const Icon(Icons.check_circle), label: const Text("Publicar")),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Builder(builder: (ctx) {
                      if (_isBasic == null) return const SizedBox.shrink();
                      if (_isBasic == true) return const SizedBox.shrink();
                      return DropdownButton<DeckStatus>(
                        isExpanded: true,
                        value: _deck.status,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: DeckStatus.draft, child: Text("Tengo")),
                          DropdownMenuItem(value: DeckStatus.published, child: Text("Objetivo")),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          if (_isBasic == true) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Disponible solo para cuentas Pro.")));
                            return;
                          }
                          setState(() {
                            _deck = _deck.copyWith(status: v, updatedAt: DateTime.now());
                          });
                        },
                      );
                    }),
                  ),
                  const SizedBox(width: 8),
                  if (_isBasic == true)
                    const SizedBox.shrink()
                  else
                    OutlinedButton.icon(onPressed: _openLinkDialog, icon: const Icon(Icons.link), label: const Text("Vincular")),
                ],
              ),
              const SizedBox(height: 8),
              if (result.issues.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Observaciones:", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    ...result.issues.map((i) => Text("• ${i.message}", style: const TextStyle(color: Colors.red))),
                  ],
                ),
            ],
          ),
        ),
      ),
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

  const _QtyControl({
    required this.value,
    required this.onDec,
    required this.onInc,
    required this.onTapNumber,
    required this.onLongPressDec,
    required this.onLongPressInc,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RoundIcon(icon: Icons.remove, tooltip: 'Disminuir (mantener para 1)', onPressed: onDec, onLongPress: onLongPressDec),
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
        _RoundIcon(icon: Icons.add, tooltip: 'Aumentar (mantener para 3)', onPressed: onInc, onLongPress: onLongPressInc),
        const SizedBox(width: 6),
        IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Eliminar carta', onPressed: onDelete, visualDensity: VisualDensity.compact),
      ],
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final VoidCallback onLongPress;
  const _RoundIcon({required this.icon, required this.tooltip, required this.onPressed, required this.onLongPress});

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
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
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

  const _CountPicker({required this.title, required this.current, this.max = 3, required this.onDelete});

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
            Container(height: 4, width: 40, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(2))),
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: List.generate(widget.max, (i) {
                final v = i + 1;
                final selected = _sel == v;
                return ChoiceChip(label: Text('$v'), selected: selected, onSelected: (_) => setState(() => _sel = v));
              }),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton.icon(onPressed: widget.onDelete, icon: const Icon(Icons.delete_outline), label: const Text('Eliminar')),
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: () => Navigator.pop<int>(context, _sel), child: const Text('Aceptar')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
