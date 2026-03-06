import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';


class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _orderBy = 'createdAt';
  bool _descending = true;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Stream.empty();
    }

    final base = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('wishlist')
        .orderBy(_orderBy, descending: _descending);

    // Para búsqueda simple en cliente (denormalizamos "name" para esto)
    return base.snapshots();
  }

  Future<void> _remove(String id) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('wishlist').doc(id)
        .delete();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Eliminado de tu lista de deseos')),
    );
  }

  Future<void> _incQty(String id, int current) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('wishlist').doc(id)
        .update({'desiredQty': current + 1});
  }

  Future<void> _decQty(String id, int current) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final next = (current - 1).clamp(1, 999);
    await FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('wishlist').doc(id)
        .update({'desiredQty': next});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lista de deseos'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              setState(() {
                if (v == 'name') { _orderBy = 'name'; _descending = false; }
                if (v == 'createdAt') { _orderBy = 'createdAt'; _descending = true; }
                if (v == 'desiredQty') { _orderBy = 'desiredQty'; _descending = true; }
              });
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'createdAt', child: Text('Más recientes')),
              PopupMenuItem(value: 'name', child: Text('Por nombre (A-Z)')),
              PopupMenuItem(value: 'desiredQty', child: Text('Por cantidad deseada')),
            ],
            icon: const Icon(Icons.sort),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar en la lista…',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(.4),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _stream(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = (snap.data?.docs ?? [])
                    .where((d) {
                      if (_query.isEmpty) return true;
                      final name = (d.data()['name'] ?? '').toString().toLowerCase();
                      final edition = (d.data()['edition'] ?? '').toString().toLowerCase();
                      return name.contains(_query) || edition.contains(_query);
                    })
                    .toList();

                if (docs.isEmpty) {
                  return const Center(
                    child: Text('Tu lista de deseos está vacía.\nAgrega cartas desde el catálogo o detalle.', textAlign: TextAlign.center),
                  );
                }

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
                    final qty = (data['desiredQty'] ?? 1) as int;
                    final img = data['imageUrl'] as String?;

                    return Material(
                      color: Theme.of(context).colorScheme.surface.withOpacity(.4),
                      borderRadius: BorderRadius.circular(14),
                      child: ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: img == null || img.isEmpty
                              ? Container(
                                  color: Colors.black12,
                                  width: 44, height: 60,
                                  child: const Icon(Icons.style, size: 20),
                                )
                              : Image.network(img, width: 44, height: 60, fit: BoxFit.cover),
                        ),
                        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          [edition, printType].where((s) => s != null && s.toString().isNotEmpty).join(' • '),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Reducir',
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => _decQty(d.id, qty),
                            ),
                            Text('$qty', style: const TextStyle(fontWeight: FontWeight.w700)),
                            IconButton(
                              tooltip: 'Aumentar',
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () => _incQty(d.id, qty),
                            ),
                            IconButton(
                              tooltip: 'Quitar',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _remove(d.id),
                            ),
                          ],
                        ),
                        onTap: () {
                          // Aquí podrías navegar al detalle de carta si lo deseas.
                        },
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
