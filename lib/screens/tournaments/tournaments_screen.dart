// lib/screens/tournaments_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:myl_decks/screens/tournaments/create_tournament_screen.dart';
import './tournament_detail_screen.dart';

class TournamentsScreen extends StatefulWidget {
  const TournamentsScreen({super.key});

  @override
  State<TournamentsScreen> createState() => _TournamentsScreenState();
}

class _TournamentsScreenState extends State<TournamentsScreen> {
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Torneos')),
        body: const Center(child: Text('No estás autenticado')),
      );
    }

    final query = FirebaseFirestore.instance
        .collection('tournaments')
        .where('visibility', isEqualTo: 'open')
        .orderBy('date', descending: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Torneos abiertos')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(18.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No hay torneos abiertos en este momento.', style: TextStyle(fontSize: 16)),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreateTournamentScreen())),
                      icon: const Icon(Icons.add),
                      label: const Text('Crear torneo (abierto/invitación)'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final docSnap = docs[i];
              final d = docSnap.data();
              final id = docSnap.id;
              final name = d['name'] ?? 'Sin nombre';
              final ts = d['date'] as Timestamp?;
              final date = ts?.toDate();
              final desc = (d['description'] ?? '').toString();
              final participants = (d['participants'] as List<dynamic>?) ?? [];
              final participantsCount = participants.length;
              final rawMax = (d['maxParticipants'] as int?) ?? 0; // 0 = ilimitado
final hasCap = rawMax > 0;
final isFull = hasCap && participantsCount >= rawMax;
final counterLabel = hasCap ? '$participantsCount / $rawMax' : '$participantsCount / ∞';


              final ownerUid = (d['ownerUid'] ?? '').toString();
              final isOwner = ownerUid == uid;

              // verificar si ya está inscrito (participants puede contener maps o uids)
              final isRegistered = participants.any((p) {
                if (p is String) return p == uid;
                if (p is Map && p['uid'] != null) return p['uid'] == uid;
                return false;
              });

              return ListTile(
                leading: const Icon(Icons.emoji_events_outlined),
                title: Text(name),
                subtitle: Text(date != null ? '${date.toLocal()}'.split('.').first : desc),
                trailing: FittedBox(
  fit: BoxFit.scaleDown,
  alignment: Alignment.centerRight,
  child: Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(counterLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (isOwner) ...[
            const SizedBox(width: 8),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Editar torneo',
              icon: const Icon(Icons.edit, size: 18),
              onPressed: () => _showEditTournamentDialog(context, id, d),
            ),
          ],
        ],
      ),
      const SizedBox(height: 6),
      if (isRegistered)
        const Text('Inscrito', style: TextStyle(fontSize: 12, color: Colors.green))
      else if (isFull)
        const Text('Lleno', style: TextStyle(fontSize: 12, color: Colors.red))
      else
        FilledButton(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => _attemptRegister(context, id, d),
          child: const Text('Inscribirse'),
        ),
    ],
  ),
),


                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => TournamentDetailScreen(tournamentId: id),
                )),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreateTournamentScreen())),
        tooltip: 'Crear torneo',
        child: const Icon(Icons.add),
      ),
    );
  }


  Future<void> _showEditTournamentDialog(BuildContext context, String tournamentId, Map<String, dynamic> currentData) async {
  final nameController = TextEditingController(text: (currentData['name'] ?? '').toString());
  final descController = TextEditingController(text: (currentData['description'] ?? '').toString());
  final maxController = TextEditingController(text: ((currentData['maxParticipants'] as int?) ?? 0) > 0 ? '${currentData['maxParticipants']}' : '');

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Editar torneo'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descController,
                decoration: const InputDecoration(labelText: 'Descripción'),
                maxLines: 3,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: maxController,
                decoration: const InputDecoration(labelText: 'Máx participantes (0 = ilimitado)'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Guardar')),
        ],
      );
    },
  );

  if (result != true) return;

  final newName = nameController.text.trim();
  final newDesc = descController.text.trim();
  final rawMax = maxController.text.trim();
  int newMax = 0;
  if (rawMax.isNotEmpty) {
    newMax = int.tryParse(rawMax) ?? -1;
    if (newMax < 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Máximo inválido')));
      return;
    }
  } else {
    newMax = 0; // ilimitado
  }

  // chequeo básico: si hay inscritos y newMax >0 debe ser >= inscritos
  final participants = (currentData['participants'] as List<dynamic>?) ?? <dynamic>[];
  if (newMax > 0 && participants.length > newMax) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hay ${participants.length} inscritos — el límite debe ser >= ${participants.length}')));
    return;
  }

  try {
    final ref = FirebaseFirestore.instance.collection('tournaments').doc(tournamentId);
    await ref.update({
      if (newName.isNotEmpty) 'name': newName,
      'description': newDesc,
      'maxParticipants': newMax,
    });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Torneo actualizado')));
  } catch (e) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al actualizar: $e')));
  }
}


Future<void> _attemptRegister(
  BuildContext context, String tournamentId, Map<String, dynamic> tournamentData) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Debes iniciar sesión')));
    return;
  }

  String? displayName = FirebaseAuth.instance.currentUser?.displayName;
  if (displayName == null || displayName.isEmpty) {
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final ud = userDoc.data();
      if (ud != null) {
        displayName = (ud['displayName'] ?? ud['username'] ?? ud['name'])?.toString() ?? '';
      }
    } catch (_) {}
  }
  if (displayName != null && displayName.trim().isEmpty) displayName = null;

  final editionRestr = (tournamentData['editionRestriction'] ?? '').toString();

  final decksQuery = FirebaseFirestore.instance.collection('users').doc(uid).collection('decks');
  QuerySnapshot<Map<String, dynamic>> decksSnap;
  try {
    decksSnap = editionRestr.isNotEmpty
        ? await decksQuery.where('edition', isEqualTo: editionRestr).get()
        : await decksQuery.get();
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al leer mazos: $e')));
    return;
  }

  final completeDecks = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  for (final d in decksSnap.docs) {
    final m = d.data();
    final cards = (m['cards'] as List<dynamic>?) ?? [];
    int total = 0;
    for (final c in cards) {
      if (c is Map) {
        final maybe = c['count'] ?? c['cantidad'] ?? c['qty'] ?? c['quantity'] ?? 0;
        final v = (maybe is int) ? maybe : int.tryParse('$maybe') ?? 0;
        total += v;
      }
    }
    if (total >= 40) completeDecks.add(d);
  }

  if (completeDecks.isEmpty) {
    final msg = editionRestr.isNotEmpty
        ? 'No tienes mazos completos de la edición "$editionRestr". No puedes inscribirte.'
        : 'No tienes mazos completos. Crea o completa un mazo (>=40 cartas) antes de inscribirte.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    return;
  }

  final chosen = await showDialog<QueryDocumentSnapshot<Map<String, dynamic>>?>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text('Elegí mazo para inscribirte${editionRestr.isNotEmpty ? ' ($editionRestr)' : ''}'),
      children: completeDecks.map((doc) {
        final name = doc.data()['name'] ?? 'Mazo sin nombre';
        final cards = (doc.data()['cards'] as List<dynamic>?) ?? [];
        int total = 0;
        for (final c in cards) {
          if (c is Map) {
            final maybe = c['count'] ?? c['cantidad'] ?? c['qty'] ?? c['quantity'] ?? 0;
            final v = (maybe is int) ? maybe : int.tryParse('$maybe') ?? 0;
            total += v;
          }
        }
        return SimpleDialogOption(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Expanded(child: Text(name)), Text('$total cartas', style: const TextStyle(color: Colors.grey))],
          ),
          onPressed: () => Navigator.pop(ctx, doc),
        );
      }).toList(),
    ),
  );
  if (chosen == null) return;

  final chosenDeckId = chosen.id;
  final chosenDeckName = (chosen.data()['name'] ?? 'Mazo').toString();
  final chosenDeckData = chosen.data();

  final cardsList = (chosenDeckData['cards'] as List<dynamic>?) ?? [];
  int totalCards = 0;
  for (final c in cardsList) {
    if (c is Map) {
      final maybe = c['count'] ?? c['cantidad'] ?? c['qty'] ?? c['quantity'] ?? 0;
      final v = (maybe is int) ? maybe : int.tryParse('$maybe') ?? 0;
      totalCards += v;
    }
  }

  final deckBrief = {
    'race': (chosenDeckData['race'] ?? chosenDeckData['faction'] ?? 'unknown'),
    'edition': chosenDeckData['edition'] ?? chosenDeckData['edicion'] ?? null,
    'archetype': chosenDeckData['archetype'] ?? chosenDeckData['type'] ?? null,
    'totalCards': totalCards,
    'deckPath': chosen.reference.path,
  };

  // payload "map" para listas de maps
  final entryForTx = {
    'uid': uid,
    'name': displayName ?? FirebaseAuth.instance.currentUser?.email ?? null,
    'deckId': chosenDeckId,
    'deckName': chosenDeckName,
    'deckBrief': deckBrief,
    'registeredAt': FieldValue.serverTimestamp(),
  };

  // payloads para arrayUnion según tipo
  final entryMapForArrayUnion = {
    'uid': uid,
    'name': displayName ?? FirebaseAuth.instance.currentUser?.email ?? null,
    'deckId': chosenDeckId,
    'deckName': chosenDeckName,
    'deckBrief': deckBrief,
    'registeredAt': Timestamp.now(),
  };
  final entryStringForArrayUnion = uid; // por si la lista es de strings

  final ref = FirebaseFirestore.instance.collection('tournaments').doc(tournamentId);

  try {
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw FirebaseException(plugin: 'cloud_firestore', code: 'not-found', message: 'Torneo no existe');
      }

      final data = snap.data()!;
      final rawParticipants = data['participants'];
      final participants = (rawParticipants is List) ? List<dynamic>.from(rawParticipants) : <dynamic>[];

      // 0 = ilimitado
      final rawMax = (data['maxParticipants'] as int?) ?? 0;
      final hasCap = rawMax > 0;

      // detectar forma del array para mantener el esquema
      final listIsStringy = participants.isNotEmpty && participants.every((p) => p is String);
      final listIsMapy    = participants.isNotEmpty && participants.every((p) => p is Map);

      // ya inscrito
      final already = participants.any((p) {
        if (p is String) return p == uid;
        if (p is Map && p['uid'] != null) return p['uid'] == uid;
        return false;
      });
      if (already) {
        throw FirebaseException(plugin: 'cloud_firestore', code: 'already-registered', message: 'Ya estás inscrito');
      }

      if (hasCap && participants.length >= rawMax) {
        throw FirebaseException(plugin: 'cloud_firestore', code: 'full', message: 'Torneo lleno');
      }

      if (listIsStringy) {
        participants.add(uid);
      } else if (listIsMapy || participants.isEmpty) {
        participants.add(entryForTx);
      } else {
        participants.add(uid);
      }

      tx.update(ref, {'participants': participants});
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Inscripción exitosa')));
    return;

  } on FirebaseException catch (e) {
    // Si falla la transacción, intentamos arrayUnion respetando el esquema
    try {
      // Leemos una vez para decidir formato
      final snap = await ref.get();
      final raw = snap.data()?['participants'];
      final isStringList = raw is List && raw.isNotEmpty && raw.every((p) => p is String);
      final payload = isStringList ? entryStringForArrayUnion : entryMapForArrayUnion;

      await ref.update({'participants': FieldValue.arrayUnion([payload])});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Inscripción exitosa')));
      return;

    } catch (e2) {
      // NO tragamos el error. Lo mostramos.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo inscribir: ${e.code} ${e.message ?? ''} | $e2')),
      );
      return;
    }

  } catch (e, st) {
    debugPrint('Error inesperado al inscribir: $e\n$st');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error inesperado al inscribir: $e')));
  }
}
}