// lib/screens/submissions_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/card_myl.dart';
import 'new_card_screen.dart';

/// Botón compacto que muestra badge y abre SubmissionsScreen.
/// - Si userRole == 'administrador' abre la vista admin.
/// - Si no, abre la vista de notificaciones del usuario.
class NotificationsButton extends StatelessWidget {
  final String? currentUid;
  final String? userRole;

  const NotificationsButton({super.key, this.currentUid, this.userRole});

  @override
  Widget build(BuildContext context) {
    // Stream para contar items: pendings (admin) o notificaciones sin leer (user)
    final stream = (userRole == 'administrador')
        ? FirebaseFirestore.instance
            .collection('card_submissions')
            .where('status', isEqualTo: 'pending')
            .snapshots()
        : (currentUid == null)
            ? const Stream<QuerySnapshot<Map<String, dynamic>>>.empty()
            : FirebaseFirestore.instance
                .collection('notifications')
                .where('toUid', isEqualTo: currentUid)
                .where('read', isEqualTo: false)
                .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        final count = (snap.data?.docs.length ?? 0);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            InkResponse(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SubmissionsScreen(currentUid: currentUid, userRole: userRole),
                  ),
                );
              },
              radius: 22,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.notifications, color: Colors.white),
              ),
            ),
            if (count > 0)
              Positioned(
                right: -6,
                top: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
                  ),
                  constraints: const BoxConstraints(minWidth: 20),
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Pantalla única para:
/// - ADMIN: ver propuestas pendientes / aprobadas, abrir editor precargado (incl. imagen),
///          aprobar/rechazar y notificar al usuario.
/// - USER: pestañas -> Notificaciones / Mis propuestas (estado).
class SubmissionsScreen extends StatefulWidget {
  final String? currentUid;
  final String? userRole; // 'administrador' | 'pro' | 'basico' | null

  const SubmissionsScreen({super.key, this.currentUid, this.userRole});

  @override
  State<SubmissionsScreen> createState() => _SubmissionsScreenState();
}

class _SubmissionsScreenState extends State<SubmissionsScreen> {
  final _db = FirebaseFirestore.instance;
  bool _busy = false;

  String _normalize(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[áàä]'), 'a')
        .replaceAll(RegExp(r'[éèë]'), 'e')
        .replaceAll(RegExp(r'[íìï]'), 'i')
        .replaceAll(RegExp(r'[óòö]'), 'o')
        .replaceAll(RegExp(r'[úùü]'), 'u')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  CardMyL _cardFromSubmission(Map<String, dynamic> submission) {
    final title = (submission['title'] ?? '') as String;
    final cardData = (submission['cardData'] ?? {}) as Map<String, dynamic>;
    final edicion = (cardData['edicion'] ?? '') as String;
    final tipo = (cardData['tipo'] ?? '') as String;
    final raza = (cardData['raza'] ?? '') as String;
    final coste = cardData['coste'];
    final fuerza = cardData['fuerza'];
    final rareza = (cardData['rareza'] ?? '') as String;
    final habilidad = (cardData['habilidad'] ?? '') as String;
    final unica = (cardData['unica'] == true);

    final id = '${_normalize(edicion)}_${_normalize(title)}';

    List<String> caracteristicas = [];
    try {
      final raw = cardData['caracteristicas'];
      if (raw is Iterable) {
        caracteristicas = raw.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
      }
    } catch (_) {}

    final Set<CardTag> tags = <CardTag>{};

    return CardMyL(
      id: id,
      nombre: title,
      tipo: tipo,
      coste: (coste is num) ? coste.toInt() : int.tryParse('$coste'),
      fuerza: (fuerza is num) ? fuerza.toInt() : int.tryParse('$fuerza'),
      rareza: rareza,
      edicion: edicion,
      habilidad: habilidad,
      raza: raza,
      unica: unica,
      tags: tags,
      caracteristicasRaw: caracteristicas,
    );
  }

  /// Abre el editor (NewCardScreen) precargado con la info de la submission.
  /// Espera `true` como resultado si el admin publicó/guardó la carta.
  Future<void> _openEditorForSubmission(String submissionId, Map<String, dynamic> data) async {
    final card = _cardFromSubmission(data);
    final imageUrl = (data['imageUrl'] as String?)?.trim();

    // El NewCardScreen debe aceptar `initialImageUrl` (ver nota abajo).
    final result = await Navigator.of(context).push<bool?>(
      MaterialPageRoute(
        builder: (_) => NewCardScreen(initial: card, initialImageUrl: imageUrl),
      ),
    );

    if (result == true) {
      // El editor devolvió true -> asumimos que se publicó.
      setState(() => _busy = true);
      try {
        final adminUid = FirebaseAuth.instance.currentUser?.uid;
        await _db.collection('card_submissions').doc(submissionId).update({
          'status': 'approved',
          'reviewedBy': adminUid,
          'reviewedAt': FieldValue.serverTimestamp(),
          'publishedCardId': card.id,
          'publishedAt': FieldValue.serverTimestamp(),
        });

        // Notificar al autor si tenemos uid
        final submittedByUid = (data['submittedBy'] as String?)?.trim();
        final submittedByEmail = (data['submittedByEmail'] as String?)?.trim();
        final title = (data['title'] ?? '(sin título)') as String;

        if (submittedByUid != null && submittedByUid.isNotEmpty) {
          await _db.collection('notifications').add({
            'toUid': submittedByUid,
            'title': 'Tu propuesta fue aprobada',
            'body': 'La propuesta "$title" fue aprobada y publicada.',
            'linkType': 'card',
            'linkId': card.id,
            'read': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
        } else if (submittedByEmail != null && submittedByEmail.isNotEmpty) {
          await _db.collection('notifications_email').add({
            'email': submittedByEmail,
            'title': 'Tu propuesta fue aprobada',
            'body': 'La propuesta "$title" fue aprobada y publicada.',
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Propuesta aprobada y usuario notificado.')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al actualizar: $e')));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  Future<void> _confirmReject(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rechazar propuesta'),
        content: const Text('¿Seguro que quieres rechazar esta propuesta?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await _db.collection('card_submissions').doc(id).update({
        'status': 'rejected',
        'reviewedBy': FirebaseAuth.instance.currentUser?.uid,
        'reviewedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Propuesta rechazada')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Muestra preview grande de la submission con opciones: Abrir editor / Aprobar ahora / Rechazar
  Future<void> _showSubmissionPreview(String submissionId, Map<String, dynamic> data) async {
    final title = (data['title'] ?? '(sin título)') as String;
    final desc = (data['description'] ?? '') as String;
    final imageUrl = (data['imageUrl'] as String?)?.trim();

    // dialog modal: muestra imagen grande + acciones
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (imageUrl != null && imageUrl.isNotEmpty)
              SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.6,
                child: InteractiveViewer(
                  child: Image.network(imageUrl, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 56)),
                ),
              )
            else
              const SizedBox(height: 120, child: Center(child: Icon(Icons.image_not_supported, size: 48))),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 8),
                  Text(desc, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.of(ctx).pop('editor'),
                          child: const Text('Abrir editor y publicar'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: () => Navigator.of(ctx).pop('approve'),
                          child: const Text('Aprobar ahora'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop('reject'),
                    child: const Text('Rechazar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (action == null) return;

    if (action == 'editor') {
      // Usa tu flujo existente que abre el editor y espera true
      await _openEditorForSubmission(submissionId, data);
      return;
    }

    if (action == 'reject') {
      await _confirmReject(submissionId);
      return;
    }

    if (action == 'approve') {
      // publica directamente (sin pasar por editor)
      await _publishSubmissionDirect(submissionId, data);
      return;
    }
  }

  /// Publica la submission directamente: crea doc en 'cards' (si no existe) y agrega variante 'Oficial' con la imagen.
  Future<void> _publishSubmissionDirect(String submissionId, Map<String, dynamic> data) async {
    setState(() => _busy = true);
    try {
      final card = _cardFromSubmission(data);
      final imageUrl = (data['imageUrl'] as String?)?.trim();

      final cardRef = _db.collection('cards').doc(card.id);

      // Transacción: no duplicar si ya existe
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(cardRef);
        if (snap.exists) {
          // Ya existe: solo actualizamos metadatos si queremos, y marcamos la submission como approved
          return;
        }

        // Crear el documento base de la carta
        tx.set(cardRef, card.toMap());

        // Si hay imagen, creamos una variante "Oficial" y la marcamos
        if (imageUrl != null && imageUrl.isNotEmpty) {
          final variantsCol = cardRef.collection('variants');
          final newVarRef = variantsCol.doc(); // id nueva
          tx.set(newVarRef, {
            'name': 'Oficial',
            'imageFrontUrl': imageUrl,
            'official': true,
            'createdAt': FieldValue.serverTimestamp(),
            'approved': true,
            'status': 'approved',
          });
          // denormalizar officialVariantId y officialImageUrl
          tx.set(cardRef, {
            'officialVariantId': newVarRef.id,
            'officialImageUrl': imageUrl,
            'officialUpdatedAt': FieldValue.serverTimestamp(),
            'nombre_lower': card.nombre.toLowerCase(),
          }, SetOptions(merge: true));
        } else {
          tx.set(cardRef, {'nombre_lower': card.nombre.toLowerCase()}, SetOptions(merge: true));
        }
      });

      // Actualizar submission (fuera de transacción para no complicar)
      final adminUid = FirebaseAuth.instance.currentUser?.uid;
      await _db.collection('card_submissions').doc(submissionId).update({
        'status': 'approved',
        'reviewedBy': adminUid,
        'reviewedAt': FieldValue.serverTimestamp(),
        'publishedCardId': card.id,
        'publishedAt': FieldValue.serverTimestamp(),
      });

      // Notificar al autor (uid o email)
      final submittedByUid = (data['submittedBy'] as String?)?.trim();
      final submittedByEmail = (data['submittedByEmail'] as String?)?.trim();
      final title = (data['title'] ?? '(sin título)') as String;

      if (submittedByUid != null && submittedByUid.isNotEmpty) {
        await _db.collection('notifications').add({
          'toUid': submittedByUid,
          'title': 'Tu propuesta fue aprobada',
          'body': 'La propuesta "$title" fue aprobada y publicada por el equipo.',
          'linkType': 'card',
          'linkId': card.id,
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else if (submittedByEmail != null && submittedByEmail.isNotEmpty) {
        await _db.collection('notifications_email').add({
          'email': submittedByEmail,
          'title': 'Tu propuesta fue aprobada',
          'body': 'La propuesta "$title" fue aprobada y publicada.',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Propuesta aprobada y publicada. Autor notificado.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al publicar: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.userRole == 'administrador';

    return Scaffold(
      appBar: AppBar(
        title: Text(isAdmin ? 'Propuestas (Admin)' : 'Notificaciones / Propuestas'),
      ),
      body: isAdmin ? _buildAdminTabs() : _buildUserView(),
    );
  }

  // Admin: pestañas Pendientes / Aprobadas
  // Reemplaza tu método _buildAdminTabs() por esto
Widget _buildAdminTabs() {
  return DefaultTabController(
    length: 3,
    child: Column(
      children: [
        Material(
          color: Theme.of(context).appBarTheme.backgroundColor,
          child: const TabBar(
            tabs: [
              Tab(text: 'Pendientes'),
              Tab(text: 'Variantes'),
              Tab(text: 'Aprobadas'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            children: [
              _buildAdminPendingList(),
              _buildAdminPendingVariants(),
              _buildAdminApprovedList(),
            ],
          ),
        ),
      ],
    ),
  );
}

// Lista de variantes pendientes (para admins)
Widget _buildAdminPendingVariants() {
  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collectionGroup('variants')
        .where('approved', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .snapshots(),
    builder: (context, snap) {
      if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final docs = snap.data!.docs;
      if (docs.isEmpty) return const Center(child: Text('No hay variantes pendientes.'));

      return ListView.separated(
        padding: const EdgeInsets.all(12),
        separatorBuilder: (_, __) => const Divider(),
        itemCount: docs.length,
        itemBuilder: (context, i) {
          final d = docs[i];
          final m = d.data();
          final name = (m['name'] ?? '(sin nombre)').toString();
          final imageUrl = (m['imageFrontUrl'] as String?)?.trim();
          final submittedBy = (m['submittedByEmail'] ?? m['submittedBy'])?.toString() ?? '(desconocido)';

          // cardRef = parent.parent de la variante
          final cardRef = d.reference.parent.parent;
          final cardId = cardRef?.id ?? '(desconocido)';

          return ListTile(
            leading: imageUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(imageUrl, width: 64, height: 64, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
                  )
                : const Icon(Icons.image_not_supported),
            title: Text(name),
            subtitle: Text('Carta: $cardId\nEnviado por: $submittedBy'),
            isThreeLine: true,
            onTap: () => _showVariantPreview(d),
          );
        },
      );
    },
  );
}

/// Muestra preview grande + acciones para una variante (docSnapshot de variant)
Future<void> _showVariantPreview(QueryDocumentSnapshot<Map<String, dynamic>> variantDoc) async {
  final m = variantDoc.data();
  final name = (m['name'] ?? '(sin nombre)').toString();
  final imageUrl = (m['imageFrontUrl'] as String?)?.trim();
  final submittedByUid = (m['submittedBy'] as String?)?.trim();
  final cardRef = variantDoc.reference.parent.parent;
  final cardId = cardRef?.id ?? '(desconocido)';

  bool markOfficial = false;

  final action = await showDialog<String>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (imageUrl != null && imageUrl.isNotEmpty)
            SizedBox(height: MediaQuery.of(ctx).size.height * 0.6, child: InteractiveViewer(child: Image.network(imageUrl, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 56))))
          else
            const SizedBox(height: 120, child: Center(child: Icon(Icons.image_not_supported, size: 48))),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 8),
                Text('Carta: $cardId', style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(ctx).pop('approve'),
                        child: const Text('Aprobar'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () => Navigator.of(ctx).pop('reject'),
                        child: const Text('Rechazar'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Checkbox(
                      value: markOfficial,
                      onChanged: (v) {
                        markOfficial = v ?? false;
                        // actualizar visual no necesario en dialog simple; si querés, rehacer con StatefulBuilder
                      },
                    ),
                    const SizedBox(width: 6),
                    const Text('Marcar como oficial (si apruebo)'),
                  ],
                ),
                const SizedBox(height: 6),
                TextButton(onPressed: () => Navigator.of(ctx).pop('cancel'), child: const Text('Cancelar')),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  if (action == null || action == 'cancel') return;

  if (action == 'reject') {
    // Marcar rechazada
    try {
      await variantDoc.reference.update({
        'approved': false,
        'status': 'rejected',
        'reviewedBy': FirebaseAuth.instance.currentUser?.uid,
        'reviewedAt': FieldValue.serverTimestamp(),
      });
      // notificar al autor
      if (submittedByUid != null && submittedByUid.isNotEmpty) {
        await FirebaseFirestore.instance.collection('notifications').add({
          'toUid': submittedByUid,
          'title': 'Tu variante fue rechazada',
          'body': 'La variante "$name" de la carta $cardId fue rechazada por el equipo.',
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Variante rechazada. Autor notificado.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al rechazar: $e')));
    }
    return;
  }

  if (action == 'approve') {
    setState(() => _busy = true);
    try {
      final adminUid = FirebaseAuth.instance.currentUser?.uid;
      // 1) marcar la variante aprobada
      await variantDoc.reference.update({
        'approved': true,
        'status': 'approved',
        'reviewedBy': adminUid,
        'reviewedAt': FieldValue.serverTimestamp(),
      });

      // 2) si se pidió marcar como oficial, actualizar otras variantes y el documento card
      if (markOfficial && cardRef != null) {
        final col = cardRef.collection('variants');
        final snap = await col.get();
        final batch = FirebaseFirestore.instance.batch();
        for (final d in snap.docs) {
          if (d.id == variantDoc.id) {
            batch.set(d.reference, {'official': true}, SetOptions(merge: true));
          } else {
            batch.set(d.reference, {'official': false}, SetOptions(merge: true));
          }
        }
        // denormalizar en la carta
        batch.set(cardRef, {
          'officialVariantId': variantDoc.id,
          'officialImageUrl': imageUrl ?? FieldValue.delete(),
          'officialUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        await batch.commit();
      }

      // 3) notificar al autor
      if (submittedByUid != null && submittedByUid.isNotEmpty) {
        await FirebaseFirestore.instance.collection('notifications').add({
          'toUid': submittedByUid,
          'title': 'Tu variante fue aprobada',
          'body': 'La variante "$name" de la carta $cardId fue aprobada por el equipo.',
          'linkType': 'card',
          'linkId': cardRef?.id ?? '',
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Variante aprobada y autor notificado.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al aprobar variante: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}



  Widget _buildAdminPendingList() {
    return Stack(
      children: [
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _db
              .collection('card_submissions')
              .where('status', isEqualTo: 'pending')
              .orderBy('createdAt', descending: false)
              .snapshots(),
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snap.data!.docs;
            if (docs.isEmpty) return const Center(child: Text('No hay propuestas pendientes.'));

            return ListView.separated(
              padding: const EdgeInsets.all(12),
              separatorBuilder: (_, __) => const Divider(),
              itemCount: docs.length,
              itemBuilder: (context, i) {
                final d = docs[i];
                final data = d.data();
                final title = data['title'] ?? '(sin título)';
                final desc = data['description'] ?? '';
                final imageUrl = data['imageUrl'] as String?;
                final edicion = (data['cardData']?['edicion'] ?? '') as String;
                final normalizedId = '${_normalize(edicion)}_${_normalize(title)}';

                // Stream que dice si la carta ya existe (publicada)
                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _db.collection('cards').doc(normalizedId).snapshots(),
                  builder: (context, cardSnap) {
                    final docSnapshot = cardSnap.data;
                    final published = docSnapshot != null && docSnapshot.exists;

                    // publishedAt safe extract
                    DateTime? publishedAtDt;
                    if (published) {
                      final cardMap = docSnapshot.data();
                      final pa = cardMap?['publishedAt'];
                      if (pa is Timestamp) {
                        publishedAtDt = pa.toDate();
                      } else if (pa is int) {
                        publishedAtDt = DateTime.fromMillisecondsSinceEpoch(pa);
                      } else if (pa is String) {
                        publishedAtDt = DateTime.tryParse(pa);
                      }
                    }
                    String? publishedAtText;
                    if (publishedAtDt != null) publishedAtText = publishedAtDt.toLocal().toString().split('.').first;

                    return ListTile(
                      leading: imageUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(imageUrl, width: 64, height: 64, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
                            )
                          : const Icon(Icons.image_not_supported),
                      title: Row(
                        children: [
                          Expanded(child: Text(title)),
                          if (published) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.greenAccent.withOpacity(0.9)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.check_circle, size: 16, color: Colors.greenAccent),
                                  const SizedBox(width: 6),
                                  const Text('Publicado',
                                      style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        [desc, if (publishedAtText != null) 'Publicado: $publishedAtText']
                            .where((s) => s != null && s.toString().isNotEmpty)
                            .join('\n'),
                      ),
                      isThreeLine: true,

                      // Si ya está publicado NO hacer nada al tocar (onTap == null)
onTap: published ? null : () => _showSubmissionPreview(d.id, data),

                      trailing: SizedBox(
                        width: 150,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.redAccent),
                              tooltip: 'Rechazar',
                              onPressed: _busy ? null : () => _confirmReject(d.id),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              icon: const Icon(Icons.check, color: Colors.greenAccent),
                              tooltip: published ? 'Ya publicada' : 'Abrir en editor y aprobar',
                              onPressed: (_busy || published) ? null : () => _showSubmissionPreview(d.id, data),

                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
        if (_busy)
          const Positioned.fill(
            child: ColoredBox(
              color: Color.fromRGBO(0, 0, 0, 0.25),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }

  Widget _buildAdminApprovedList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db
          .collection('card_submissions')
          .where('status', isEqualTo: 'approved')
          .orderBy('publishedAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('No hay propuestas aprobadas.'));

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          separatorBuilder: (_, __) => const Divider(),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i];
            final data = d.data();
            final title = data['title'] ?? '(sin título)';
            final imageUrl = data['imageUrl'] as String?;
            final submittedBy = data['submittedByEmail'] ?? data['submittedBy'];
            final pa = data['publishedAt'];
            String? publishedAtText;
            if (pa is Timestamp) {
              publishedAtText = pa.toDate().toLocal().toString().split('.').first;
            } else if (pa is int) {
              publishedAtText = DateTime.fromMillisecondsSinceEpoch(pa).toLocal().toString().split('.').first;
            } else if (pa is String) {
              final dt = DateTime.tryParse(pa);
              if (dt != null) publishedAtText = dt.toLocal().toString().split('.').first;
            }

            return ListTile(
              leading: imageUrl != null
                  ? ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(imageUrl, width: 64, height: 64, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)))
                  : const Icon(Icons.image_not_supported),
              title: Text(title),
              subtitle: Text(['Enviado por: $submittedBy', if (publishedAtText != null) 'Publicado: $publishedAtText'].join('\n')),
              isThreeLine: true,
              // en aprobadas no hacemos nada al tocar (solo info), podrías abrir detalle si quieres
              onTap: null,
            );
          },
        );
      },
    );
  }

  // User view: Notificaciones | Mis propuestas
  Widget _buildUserView() {
    // Pestañas: Notificaciones | Mis propuestas
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).appBarTheme.backgroundColor,
            child: const TabBar(
              tabs: [
                Tab(text: 'Notificaciones'),
                Tab(text: 'Mis propuestas'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildUserNotificationsList(),
                _buildUserSubmissionsList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserNotificationsList() {
    final uid = widget.currentUid;
    if (uid == null) return const Center(child: Text('Debes iniciar sesión para ver notificaciones.'));
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db.collection('notifications').where('toUid', isEqualTo: uid).orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('No tienes notificaciones.'));

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          separatorBuilder: (_, __) => const Divider(),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i];
            final data = d.data();
            final title = data['title'] ?? '(sin título)';
            final body = data['body'] ?? '';
            final read = data['read'] == true;
            final linkType = data['linkType'] as String?;
            final linkId = data['linkId'] as String?;
            return ListTile(
              leading: Icon(read ? Icons.notifications_none : Icons.notifications_active, color: read ? Colors.white54 : Colors.amberAccent),
              title: Text(title),
              subtitle: Text(body),
              trailing: TextButton(
                onPressed: () async {
                  await d.reference.update({'read': true});
                  if (linkType == 'card' && linkId != null && linkId.isNotEmpty) {
                    // abrir vista de carta si tienes pantalla para eso
                    // Navigator.of(context).push(MaterialPageRoute(builder: (_) => CardDetailScreen(cardId: linkId)));
                  }
                },
                child: const Text('Marcar leído'),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildUserSubmissionsList() {
    final uid = widget.currentUid;
    if (uid == null) return const Center(child: Text('Debes iniciar sesión para ver tus propuestas.'));
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db.collection('card_submissions').where('submittedBy', isEqualTo: uid).orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('No has enviado propuestas.'));

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          separatorBuilder: (_, __) => const Divider(),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i];
            final data = d.data();
            final title = data['title'] ?? '(sin título)';
            final status = data['status'] ?? 'pending';
            final imageUrl = data['imageUrl'] as String?;
            return ListTile(
              leading: imageUrl != null
                  ? ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(imageUrl, width: 56, height: 56, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)))
                  : const Icon(Icons.image_not_supported),
              title: Text(title),
              subtitle: Text('Estado: $status'),
              trailing: TextButton(
                onPressed: () {
                  // opcional: ver detalles
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(title),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (imageUrl != null) Image.network(imageUrl, height: 140, fit: BoxFit.contain),
                          const SizedBox(height: 8),
                          Text('Estado: $status'),
                          const SizedBox(height: 8),
                          Text('Detalles:\n${(data['cardData'] ?? {}).toString()}'),
                        ],
                      ),
                      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
                    ),
                  );
                },
                child: const Text('Ver'),
              ),
            );
          },
        );
      },
    );
  }
}
