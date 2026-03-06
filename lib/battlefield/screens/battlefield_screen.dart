import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../battlefield/models/player_state.dart';
import '../../battlefield/models/zone.dart';
import '../../battlefield/models/card_stub.dart';
import '../../battlefield/data/card_repository.dart';
import '../../battlefield/widgets/widgets.dart';



class BattlefieldScreen extends StatefulWidget {
  final String matchId;                 // 👈 NUEVO: para sincronizar
  final String playerAName, playerBName, deckAName, deckBName;
  final String userIdA, deckIdA;
  final String? userIdB, deckIdB;
  final int? deckASize, deckBSize;
  final String currentUserId;
  final bool currentUserIsPlayerB;

  const BattlefieldScreen({
    super.key,
    required this.matchId,              // 👈 NUEVO
    required this.playerAName,
    required this.playerBName,
    required this.deckAName,
    required this.deckBName,
    required this.userIdA,
    required this.deckIdA,
    this.userIdB,
    this.deckIdB,
    this.deckASize,
    this.deckBSize,
    required this.currentUserId,
    this.currentUserIsPlayerB = false,
  });

  @override
  BattlefieldScreenState createState() => BattlefieldScreenState();
}

class BattlefieldScreenState extends State<BattlefieldScreen> {
  late final bool iAmB;

  late PlayerState me;
  late PlayerState rival;
  final repo = CardRepository();

  bool _loadingA = true;
  bool _loadingB = true;

  // 🔄 Sync
  late final DocumentReference<Map<String, dynamic>> _bfRef;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _bfSub;
  bool _syncStarted = false;
  bool _applyingRemote = false; // evita eco

  @override
  void initState() {
    super.initState();

    // ¿Soy B?
    if (widget.currentUserId.isNotEmpty && widget.userIdB != null && widget.currentUserId == widget.userIdB) {
      iAmB = true;
    } else if (widget.currentUserId.isNotEmpty && widget.currentUserId == widget.userIdA) {
      iAmB = false;
    } else {
      iAmB = widget.currentUserIsPlayerB;
    }

    // Identidades
    me = PlayerState(iAmB ? widget.playerBName : widget.playerAName, iAmB ? widget.deckBName : widget.deckAName);
    rival = PlayerState(iAmB ? widget.playerAName : widget.playerBName, iAmB ? widget.deckAName : widget.deckBName);

    // Ref de estado compartido
    _bfRef = FirebaseFirestore.instance
        .collection('matches')
        .doc(widget.matchId)
        .collection('battlefield')
        .doc('state');

    // Carga de mazos coherente al lado
    if (!iAmB) {
      _loadPlayerDeck(target: me, userId: widget.userIdA, deckId: widget.deckIdA, shuffleAfter: true)
          .then((_) { setState(() => _loadingA = false); _maybeStartSync(); });
      if (widget.userIdB != null && widget.deckIdB != null) {
        _loadPlayerDeck(target: rival, userId: widget.userIdB!, deckId: widget.deckIdB!, shuffleAfter: true)
            .then((_) { setState(() => _loadingB = false); _maybeStartSync(); });
      } else {
        rival.generateDeck(widget.deckBSize ?? 50, prefix: 'B'); rival.shuffle(); _loadingB = false; _maybeStartSync();
      }
    } else {
      if (widget.userIdB != null && widget.deckIdB != null) {
        _loadPlayerDeck(target: me, userId: widget.userIdB!, deckId: widget.deckIdB!, shuffleAfter: true)
            .then((_) { setState(() => _loadingB = false); _maybeStartSync(); });
      } else {
        me.generateDeck(widget.deckBSize ?? 50, prefix: 'B'); me.shuffle(); _loadingB = false; _maybeStartSync();
      }
      _loadPlayerDeck(target: rival, userId: widget.userIdA, deckId: widget.deckIdA, shuffleAfter: true)
          .then((_) { setState(() => _loadingA = false); _maybeStartSync(); });
    }
  }

  @override
  void dispose() {
    _bfSub?.cancel();
    super.dispose();
  }

  // ---------------- SYNC CORE ----------------

  void _maybeStartSync() async {
    if (_syncStarted) return;
    if (_loadingA || _loadingB) return;

    _syncStarted = true;

    final doc = await _bfRef.get();
    if (!doc.exists) {
      // Primer cliente: sube estado inicial
      await _pushFullState();
    }

    _bfSub = _bfRef.snapshots().listen((snap) {
      if (!snap.exists) return;
      final data = snap.data()!;
      // si yo fui quien subió, ignora
      if ((data['by'] ?? '') == widget.currentUserId) return;

      _applyRemoteState(data);
    });
  }

  Map<String, dynamic> _serializeCard(CardStub c) => {
        'id': c.id,
        'imageUrl': c.imageUrl,
        'tipo': c.tipo,
        'tapped': c.tapped,
      };

  CardStub _cardFromMap(Map<String, dynamic> m) => CardStub(
        (m['id'] ?? '').toString(),
        imageUrl: (m['imageUrl'] ?? '') as String?,
        tipo: (m['tipo'] ?? '') as String? ?? '',
        tapped: (m['tapped'] ?? false) as bool,
      );

  Map<String, dynamic> _serializePlayer(PlayerState p) => {
        'name': p.name,
        'deckName': p.deckName,
        'piles': {
          for (final z in Zone.values)
            z.name: p.piles[z]!.map(_serializeCard).toList(),
        }
      };

  void _loadIntoPlayer(PlayerState target, Map<String, dynamic> m) {
    final piles = (m['piles'] ?? {}) as Map<String, dynamic>;
    for (final z in Zone.values) {
      final list = (piles[z.name] as List? ?? const []);
      target.piles[z] = list.map((e) => _cardFromMap(Map<String, dynamic>.from(e as Map))).toList();
    }
  }

  void _applyRemoteState(Map<String, dynamic> data) {
    _applyingRemote = true;
    try {
      final players = Map<String, dynamic>.from(data['players'] as Map);
      final a = Map<String, dynamic>.from(players['A'] as Map);
      final b = Map<String, dynamic>.from(players['B'] as Map);

      setState(() {
        if (!iAmB) {
          // Yo soy A
          _loadIntoPlayer(me, a);
          _loadIntoPlayer(rival, b);
        } else {
          // Yo soy B
          _loadIntoPlayer(rival, a);
          _loadIntoPlayer(me, b);
        }
      });
    } finally {
      _applyingRemote = false;
    }
  }

  Future<void> _pushFullState() async {
    if (_applyingRemote) return; // evita re-subir lo que estoy aplicando
    final payload = {
      'by': widget.currentUserId,
      'ts': FieldValue.serverTimestamp(),
      'players': {
        'A': _serializePlayer(iAmB ? rival : me),
        'B': _serializePlayer(iAmB ? me : rival),
      },
    };
    await _bfRef.set(payload, SetOptions(merge: false));
  }

  /// Llamar esto DESPUÉS de cualquier cambio local
  Future<void> syncNow() => _pushFullState();

  // ---------------- Helpers de deck load (tuyos) ----------------

  int _asQty(dynamic v) {
    if (v == null) return 1;
    if (v is int) return v;
    if (v is double) return v.round();
    final s = v.toString().toLowerCase().trim();
    final m = RegExp(r'(\d+)').firstMatch(s);
    if (m != null) {
      final q = int.parse(m.group(1)!);
      return q > 0 ? q : 1;
    }
    return 1;
  }

  CardStub? _removeOneById(List<CardStub> stack, String wantedId) {
    final idx = stack.indexWhere((c) => c.id == wantedId);
    return (idx >= 0) ? stack.removeAt(idx) : null;
  }

  Future<void> _loadPlayerDeck({
    required PlayerState target,
    required String userId,
    required String deckId,
    bool shuffleAfter = false,
  }) async {
    final deckRef = FirebaseFirestore.instance.collection('users').doc(userId).collection('decks').doc(deckId);
    final doc = await deckRef.get();
    final data = doc.data() ?? {};

    String? initialGoldId = (data['initialGoldCardId'] ?? data['initialGoldId'])?.toString();
    String? initialGoldName = (data['initialGoldName'] ?? data['initialGold'])?.toString();

    final entries = <MapEntry<String, int>>[];
    final cardsArray = (data['cards'] is List) ? (data['cards'] as List) : null;

    if (cardsArray != null) {
      for (final raw in cardsArray) {
        if (raw is Map<String, dynamic>) {
          final id = (raw['id'] ?? raw['cardId'] ?? raw['codigo'] ?? '').toString().trim();
          final qty = _asQty(raw['qty'] ?? raw['quantity'] ?? raw['q'] ?? raw['copies'] ?? raw['cant'] ?? raw['count'] ?? 1);
          if (id.isNotEmpty && qty > 0) entries.add(MapEntry(id, qty));
        }
      }
    } else {
      final snap = await deckRef.collection('cards').get();
      for (final d in snap.docs) {
        final m = d.data();
        final id = (m['id'] ?? m['cardId'] ?? m['codigo'] ?? d.id).toString().trim();
        final qty = int.tryParse('${m['qty'] ?? m['quantity'] ?? 1}') ?? 1;
        if (id.isNotEmpty && qty > 0) entries.add(MapEntry(id, qty));
      }
    }

    if ((initialGoldId == null || initialGoldId.isEmpty) && (initialGoldName != null && initialGoldName.trim().isNotEmpty)) {
      initialGoldId = await repo.resolveCardIdByName(initialGoldName);
    }

    final uniqueIds = entries.map((e) => e.key).toSet().toList();
    final metaById = await repo.fetchCardMetaForIds(uniqueIds);

    final allCards = <CardStub>[];
    for (final e in entries) {
      final id = e.key;
      final qty = e.value;
      final meta = metaById[id];
      for (int i = 0; i < qty; i++) {
        allCards.add(CardStub(id, imageUrl: meta?.url, tipo: meta?.tipo ?? ''));
      }
    }

    CardStub? initialGoldCard;
    if (initialGoldId != null && initialGoldId.isNotEmpty) {
      initialGoldCard = _removeOneById(allCards, initialGoldId);
    }

    target.piles[Zone.goldPool] = [];
    if (initialGoldCard != null) {
      target.piles[Zone.goldPool]!.add(initialGoldCard);
    }
    target.piles[Zone.deck] = allCards;

    if (shuffleAfter) target.shuffle();
  }

  // ---------------- Acciones que ahora sincronizan ----------------

  void _drawN(PlayerState p, int n) {
    setState(() {
      for (int i = 0; i < n; i++) {
        p.drawOne();
      }
    });
    syncNow();
  }

  void _mill(PlayerState p, int n) {
    setState(() => p.moveFromTop(Zone.deck, Zone.grave, n));
    syncNow();
  }

  void _openDeckMenu(PlayerState p) {
    final qtyCtrl = TextEditingController(text: '1');
    showModalBottomSheet(
      context: context, showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Mazo Castillo', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(children: [
            const Text('Cantidad:'), const SizedBox(width: 8),
            SizedBox(width: 72, child: TextField(controller: qtyCtrl, keyboardType: TextInputType.number, textAlign: TextAlign.center, decoration: const InputDecoration(isDense: true, hintText: '1'))),
            const Spacer(),
            Text('Quedan: ${p.piles[Zone.deck]!.length}'),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(onPressed: () { _drawN(p, int.tryParse(qtyCtrl.text) ?? 1); Navigator.pop(context); }, child: const Text('Robar X')),
            FilledButton.tonal(onPressed: () { _mill(p, int.tryParse(qtyCtrl.text) ?? 1); Navigator.pop(context); }, child: const Text('Botar X')),
            OutlinedButton(onPressed: () { setState(() => p.shuffle()); Navigator.pop(context); syncNow(); }, child: const Text('Barajar')),
          ]),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _openGoldMenu(PlayerState p) {
    final qtyCtrl = TextEditingController(text: '1');
    showModalBottomSheet(
      context: context, showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Reserva de Oro', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(children: [
            const Text('Cantidad:'), const SizedBox(width: 8),
            SizedBox(width: 72, child: TextField(controller: qtyCtrl, keyboardType: TextInputType.number, textAlign: TextAlign.center, decoration: const InputDecoration(isDense: true, hintText: '1'))),
            const Spacer(),
            Text('En reserva: ${p.piles[Zone.goldPool]!.length}'),
          ]),
          const SizedBox(height: 12),
          FilledButton(onPressed: () {
            final q = int.tryParse(qtyCtrl.text) ?? 1;
            setState(() { p.moveFromTop(Zone.goldPool, Zone.goldPaid, q); });
            Navigator.pop(context);
            syncNow();
          }, child: const Text('Pagar oro (→ Oro pagado)')),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final isLoading = _loadingA || _loadingB;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Campo de Batalla (MVP)'),
          centerTitle: true,
          bottom: const TabBar(tabs: [Tab(text: 'Rival'), Tab(text: 'Mi tablero')]),
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(children: [
                // RIVAL
                SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(children: [
                    VsHeader(aName: me.name, bName: rival.name, deckA: me.deckName, deckB: rival.deckName),
                    const SizedBox(height: 8),
                    BoardView(
                      title: 'Tablero de ${rival.name}',
                      deckName: rival.deckName,
                      player: rival,
                      readOnly: true,
                      compact: true,
                      onDeckTap: () {}, // viewer opcional
                    ),
                  ]),
                ),

                // YO
                Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: VsHeader(aName: me.name, bName: rival.name, deckA: me.deckName, deckB: rival.deckName),
                  ),
                  const SizedBox(height: 6),
                  HandView(ownerName: me.name, cards: me.piles[Zone.hand]!, onDragStart: (_) {}, readOnly: false, owner: me),
                  const SizedBox(height: 6),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: BoardView(
                        title: 'Mi Tablero • ${me.name}',
                        deckName: me.deckName,
                        player: me,
                        readOnly: false,
                        compact: true,
                        onDeckTap: () => _openDeckMenu(me),
                        onGoldTap: () => _openGoldMenu(me),
                        onOpenGrave: () => _openGraveyardViewer(me), // si ya tenías este método
                      ),
                    ),
                  ),
                ]),
              ]),
      ),
    );
  }

  // === Si ya tienes este viewer en otro archivo, ignora este stub ===
  void _openGraveyardViewer(PlayerState p) {
    // aquí tu lógica actual; tras cualquier cambio, llama syncNow()
  }
}
