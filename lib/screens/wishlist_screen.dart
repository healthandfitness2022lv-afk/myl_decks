import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../utils/text_normalize.dart';
import '../services/wishlist_service.dart';
import '../services/inventory_service.dart';
import '../widgets/network_image.dart';

const _wishBg = Color(0xFF0B0D12);
const _wishPanel = Color(0xFF171A20);
const _wishPanelSoft = Color(0xFF201A16);
const _wishWood = Color(0xFF6E4B33);
const _wishCopper = Color(0xFFC78B55);
const _wishTextSoft = Color(0xFFD7C6B6);

/// Orden canónico de edición y tipo para listas de cartas (wishlist, etc.).
/// El catálogo central NO usa este orden — se deja tal cual está.
const List<String> _edicionOrder = [
  'Espada Sagrada',
  'Helénica',
  'Hijos de Daana',
  'Dominios de Ra',
  'Racial Libre',
  'Formato Full',
];

const List<String> _tipoOrder = ['Aliado', 'Talismán', 'Tótem', 'Arma', 'Oro'];

int _edicionRank(String edicion) {
  final i = _edicionOrder.indexOf(edicion);
  return i == -1 ? _edicionOrder.length : i;
}

int _tipoRank(String tipo) {
  final i = _tipoOrder.indexOf(tipo);
  return i == -1 ? _tipoOrder.length : i;
}

class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  final _searchCtrl = TextEditingController();

  String _query = '';

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      unawaited(
        InventoryService(uid).refreshDynamicWishlist().catchError((_) {}),
      );
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> _wishlistCol(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('wishlist');

  Stream<QuerySnapshot<Map<String, dynamic>>> _wishlistStream() {
    final uid = _uid;
    if (uid == null) return const Stream.empty();

    return _wishlistCol(uid).snapshots();
  }

  bool _matchesWishlist(Map<String, dynamic> data) {
    if (_query.isEmpty) return true;
    final name = normalizeSearch((data['name'] ?? '').toString());
    final edition = normalizeSearch((data['edition'] ?? '').toString());
    final variantName = normalizeSearch((data['variantName'] ?? '').toString());
    return name.contains(_query) ||
        edition.contains(_query) ||
        variantName.contains(_query);
  }

  Future<void> _removeWishlist(String id) async {
    final uid = _uid;
    if (uid == null) return;
    await WishlistService(uid).setManualQuantity(id, 0);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Eliminado de tu lista de deseos')),
    );
  }

  Future<void> _incQty(String id, int current) async {
    final uid = _uid;
    if (uid == null) return;
    await WishlistService(uid).setManualQuantity(id, current + 1);
  }

  Future<void> _decQty(String id, int current) async {
    final uid = _uid;
    if (uid == null) return;
    final next = (current - 1).clamp(0, 999);
    await WishlistService(uid).setManualQuantity(id, next);
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _searchCards(
    String query,
  ) async {
    final cards = FirebaseFirestore.instance.collection('cards');
    final q = normalizeSearch(query);

    if (q.isEmpty) {
      final snap = await cards.orderBy('nombre').limit(25).get();
      return snap.docs;
    }

    final snap =
        await cards
            .where('nombre_lower', isGreaterThanOrEqualTo: q)
            .where('nombre_lower', isLessThanOrEqualTo: '$q\uf8ff')
            .limit(25)
            .get();
    return snap.docs;
  }

  Widget _buildWishlistTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _wishlistStream(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs =
            (snap.data?.docs ?? [])
                .where((d) => _matchesWishlist(d.data()))
                .toList();
        docs.sort((a, b) {
          final da = a.data();
          final db = b.data();
          final aShort = (da['deckShortageQty'] as num?)?.toInt() ?? 0;
          final bShort = (db['deckShortageQty'] as num?)?.toInt() ?? 0;
          if ((aShort > 0) != (bShort > 0)) return aShort > 0 ? -1 : 1;

          final aEd = _edicionRank((da['edition'] ?? '').toString());
          final bEd = _edicionRank((db['edition'] ?? '').toString());
          if (aEd != bEd) return aEd.compareTo(bEd);

          final aTipo = _tipoRank((da['type'] ?? '').toString());
          final bTipo = _tipoRank((db['type'] ?? '').toString());
          if (aTipo != bTipo) return aTipo.compareTo(bTipo);

          return (da['name'] ?? '').toString().compareTo(
            (db['name'] ?? '').toString(),
          );
        });
        final shortageCount =
            docs
                .where(
                  (doc) =>
                      ((doc.data()['deckShortageQty'] as num?)?.toInt() ?? 0) >
                      0,
                )
                .length;

        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'Tu lista de deseos está vacía.\nAgrega cartas desde el catálogo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _wishTextSoft),
            ),
          );
        }

        final groupedMetadataReady = docs
            .where(
              (doc) =>
                  ((doc.data()['deckShortageQty'] as num?)?.toInt() ?? 0) > 0,
            )
            .every(
              (doc) =>
                  (doc.data()['deckShortages'] as List?)?.isNotEmpty == true,
            );
        if (groupedMetadataReady) return _buildGroupedWishlist(docs);

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final d = docs[i];
            final data = d.data();
            final name = data['name'] ?? 'Carta';
            final edition = data['edition'] ?? '';
            final printType = data['printType'] ?? '';
            final variantName = data['variantName'] ?? '';
            final manual =
                (data['manualQty'] as num?)?.toInt() ??
                (data['desiredQty'] as num?)?.toInt() ??
                0;
            final shortage = (data['deckShortageQty'] as num?)?.toInt() ?? 0;
            final qty = manual + shortage;
            final img = data['imageUrl'] as String?;
            final deckNames =
                (data['deckNames'] as List?)
                    ?.map((e) => e.toString())
                    .where((s) => s.isNotEmpty)
                    .toList() ??
                const <String>[];

            final tile = Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: shortage > 0 ? () => context.push('/mazos') : null,
                child: Ink(
                  decoration: BoxDecoration(
                    color: _wishPanel,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(.08)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1A000000),
                        blurRadius: 12,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ListTile(
                    leading: _ListingThumb(url: img),
                    title: Text(
                      name.toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          [
                            edition,
                            variantName,
                            printType,
                            if (manual > 0) 'Manual: $manual',
                            if (shortage > 0 && deckNames.isEmpty)
                              'Mazos: $shortage',
                          ].where((s) => s.toString().isNotEmpty).join(' • '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _wishTextSoft),
                        ),
                        if (shortage > 0 && deckNames.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Falta en: ${deckNames.join(', ')}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _wishCopper,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Reducir',
                          color: _wishCopper,
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed:
                              manual > 0 ? () => _decQty(d.id, manual) : null,
                        ),
                        Text(
                          '$qty',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Aumentar',
                          color: _wishCopper,
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => _incQty(d.id, manual),
                        ),
                        IconButton(
                          tooltip: 'Quitar',
                          color: Colors.white70,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _removeWishlist(d.id),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            final showHeader = i == 0 || i == shortageCount;
            if (!showHeader) return tile;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                  child: Text(
                    i == 0 && shortageCount > 0
                        ? 'Faltan para tus mazos'
                        : 'Deseos personales',
                    style: const TextStyle(
                      color: _wishCopper,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                tile,
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildGroupedWishlist(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final grouped =
        <String, Map<String, Map<String, List<_WishlistDeckShortageRow>>>>{};
    final manualDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final doc in docs) {
      final data = doc.data();
      final manual = (data['manualQty'] as num?)?.toInt() ?? 0;
      if (manual > 0) manualDocs.add(doc);
      for (final raw in (data['deckShortages'] as List? ?? const [])) {
        final location = Map<String, dynamic>.from(raw as Map);
        final edition = (location['deckEdition'] ?? 'Sin edición').toString();
        final race = (location['deckRace'] ?? 'Sin raza').toString();
        final deck = (location['deckName'] ?? 'Mazo').toString();
        grouped
            .putIfAbsent(
              edition,
              () => <String, Map<String, List<_WishlistDeckShortageRow>>>{},
            )
            .putIfAbsent(race, () => <String, List<_WishlistDeckShortageRow>>{})
            .putIfAbsent(deck, () => <_WishlistDeckShortageRow>[])
            .add(_WishlistDeckShortageRow(document: doc, location: location));
      }
    }

    final editions =
        grouped.keys.toList()..sort((a, b) {
          final rank = _edicionRank(a).compareTo(_edicionRank(b));
          return rank != 0 ? rank : a.toLowerCase().compareTo(b.toLowerCase());
        });
    manualDocs.sort(
      (a, b) => (a.data()['name'] ?? '').toString().compareTo(
        (b.data()['name'] ?? '').toString(),
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        for (final edition in editions) ...[
          _WishlistGroupHeader(
            label: edition,
            icon: Icons.collections_bookmark_outlined,
          ),
          for (final race
              in (grouped[edition]!.keys.toList()..sort(
                (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
              ))) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 13, 8, 6),
              child: Text(
                race,
                style: const TextStyle(
                  color: _wishCopper,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            for (final deckName
                in (grouped[edition]![race]!.keys.toList()
                  ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()))))
              _WishlistDeckGroup(
                deckName: deckName,
                rows: grouped[edition]![race]![deckName]!,
              ),
          ],
        ],
        if (manualDocs.isNotEmpty) ...[
          const _WishlistGroupHeader(
            label: 'Deseos personales',
            icon: Icons.favorite_border,
          ),
          const SizedBox(height: 8),
          for (final doc in manualDocs) ...[
            _buildManualWishlistTile(doc),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  Widget _buildManualWishlistTile(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final manual = (data['manualQty'] as num?)?.toInt() ?? 0;
    return _WishlistCardShell(
      imageUrl: data['imageUrl'] as String?,
      name: (data['name'] ?? 'Carta').toString(),
      subtitle: [
        data['edition'],
        data['variantName'],
        data['printType'],
      ].where((value) => (value ?? '').toString().isNotEmpty).join(' • '),
      onTap: null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Reducir',
            color: _wishCopper,
            onPressed: () => _decQty(doc.id, manual),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text(
            '$manual',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          IconButton(
            tooltip: 'Aumentar',
            color: _wishCopper,
            onPressed: () => _incQty(doc.id, manual),
            icon: const Icon(Icons.add_circle_outline),
          ),
          IconButton(
            tooltip: 'Quitar',
            onPressed: () => _removeWishlist(doc.id),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _wishBg,
      appBar: AppBar(
        backgroundColor: _wishBg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Wishlist'),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF14171D), _wishBg, Color(0xFF120F0D)],
          ),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  colors: [
                    _wishCopper.withOpacity(.34),
                    _wishWood.withOpacity(.12),
                  ],
                ),
              ),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Buscar en tu wishlist...',
                  hintStyle: const TextStyle(color: _wishTextSoft),
                  prefixIcon: const Icon(Icons.search, color: _wishCopper),
                  isDense: true,
                  filled: true,
                  fillColor: _wishPanel,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: _wishCopper),
                  ),
                ),
                onChanged: (v) => setState(() => _query = normalizeSearch(v)),
              ),
            ),
            Expanded(child: _buildWishlistTab()),
          ],
        ),
      ),
    );
  }
}

class _WishlistDeckShortageRow {
  final QueryDocumentSnapshot<Map<String, dynamic>> document;
  final Map<String, dynamic> location;

  const _WishlistDeckShortageRow({
    required this.document,
    required this.location,
  });
}

class _WishlistGroupHeader extends StatelessWidget {
  final String label;
  final IconData icon;

  const _WishlistGroupHeader({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
    decoration: BoxDecoration(
      color: _wishPanel,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white12),
    ),
    child: Row(
      children: [
        Icon(icon, color: _wishTextSoft, size: 19),
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

class _WishlistDeckGroup extends StatelessWidget {
  final String deckName;
  final List<_WishlistDeckShortageRow> rows;

  const _WishlistDeckGroup({required this.deckName, required this.rows});

  @override
  Widget build(BuildContext context) {
    final first = rows.first.location;
    final deckId = (first['deckId'] ?? '').toString();
    final ownerId = (first['deckOwnerId'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _wishPanel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(.08)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap:
                deckId.isEmpty || ownerId.isEmpty
                    ? null
                    : () => context.push(
                      '/mazo/${Uri.encodeComponent(ownerId)}/${Uri.encodeComponent(deckId)}',
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Text(
                    'Abrir mazo',
                    style: TextStyle(color: _wishTextSoft, fontSize: 11),
                  ),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          for (var index = 0; index < rows.length; index++) ...[
            _WishlistAutomaticCard(row: rows[index]),
            if (index != rows.length - 1) const Divider(height: 1, indent: 72),
          ],
        ],
      ),
    );
  }
}

class _WishlistAutomaticCard extends StatelessWidget {
  final _WishlistDeckShortageRow row;

  const _WishlistAutomaticCard({required this.row});

  @override
  Widget build(BuildContext context) {
    final data = row.document.data();
    final quantity = (row.location['quantity'] as num?)?.toInt() ?? 0;
    return _WishlistCardShell(
      imageUrl: data['imageUrl'] as String?,
      name: (data['name'] ?? 'Carta').toString(),
      subtitle: 'Faltan $quantity',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _wishCopper.withOpacity(.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _wishCopper.withOpacity(.6)),
        ),
        child: Text(
          '$quantity',
          style: const TextStyle(
            color: _wishCopper,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _WishlistCardShell extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  const _WishlistCardShell({
    this.imageUrl,
    required this.name,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: ListTile(
        leading: _ListingThumb(url: imageUrl),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _wishTextSoft),
        ),
        trailing: trailing,
      ),
    ),
  );
}

class _ListingThumb extends StatelessWidget {
  final String? url;
  final double width;
  final double height;

  const _ListingThumb({required this.url, this.width = 44, this.height = 60});

  @override
  Widget build(BuildContext context) {
    final safe = (url ?? '').trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child:
          safe.isEmpty
              ? Container(
                color: _wishPanelSoft,
                width: width,
                height: height,
                alignment: Alignment.center,
                child: const Icon(Icons.style, color: _wishTextSoft),
              )
              : MylNetworkImage(
                imageUrl: safe,
                width: width,
                height: height,
                fit: BoxFit.cover,
                errorWidget:
                    (_, __, ___) => Container(
                      color: _wishPanelSoft,
                      width: width,
                      height: height,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.broken_image_outlined,
                        color: _wishTextSoft,
                      ),
                    ),
              ),
    );
  }
}
