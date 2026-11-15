// lib/screens/deck_by_id_screen.dart
// Carga un mazo por (ownerId, deckId) desde Firestore y muestra su detalle.
// Es el destino de los links compartidos /mazo/:uid/:id.
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/deck.dart';
import '../theme/app_theme.dart';
import '../widgets/skeletons.dart';
import 'deck_details_screen.dart';

class DeckByIdScreen extends StatelessWidget {
  final String ownerId;
  final String deckId;

  const DeckByIdScreen({
    super.key,
    required this.ownerId,
    required this.deckId,
  });

  @override
  Widget build(BuildContext context) {
    final future =
        FirebaseFirestore.instance
            .collection('users')
            .doc(ownerId)
            .collection('decks')
            .doc(deckId)
            .get();

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Cargando mazo…')),
            body: ListView(
              children: const [
                SizedBox(height: 8),
                SkeletonListTile(),
                SkeletonListTile(),
                SkeletonListTile(),
              ],
            ),
          );
        }

        final data = snap.data?.data();
        if (snap.hasError || data == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Mazo no encontrado')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.search_off,
                    size: 56,
                    color: AppColors.textFaint,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Este mazo no existe o fue eliminado.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed:
                        () =>
                            Navigator.of(context).canPop()
                                ? Navigator.of(context).pop()
                                : null,
                    child: const Text('Volver'),
                  ),
                ],
              ),
            ),
          );
        }

        final deck = Deck.fromFirestore(
          snap.data!.id,
          data,
        ).copyWith(ownerId: ownerId);
        return DeckDetailsScreen(deck: deck);
      },
    );
  }
}
