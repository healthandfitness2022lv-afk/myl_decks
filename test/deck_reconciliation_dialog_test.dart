import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/domain/collection_reconciliation.dart';
import 'package:myl_decks/widgets/deck_reconciliation_dialog.dart';

void main() {
  testWidgets('muestra conflictos de mazos y publicaciones juntos', (
    tester,
  ) async {
    const proposal = DeckReconciliationProposal(
      automaticAllocations: {},
      shortagesByDeck: {},
      conflicts: [
        DeckAllocationConflict(
          itemKey: 'card:c1',
          cardName: 'Carta compartida',
          available: 1,
          requestedByDeck: {'a': 1, 'b': 1},
        ),
      ],
      saleConflicts: [
        DeckSaleConflict(
          itemKey: 'card:c2',
          cardName: 'Carta publicada',
          reserved: 1,
          neededForDecks: 1,
        ),
      ],
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DeckReconciliationDialog(
            proposal: proposal,
            deckNames: {'a': 'Mazo A', 'b': 'Mazo B'},
          ),
        ),
      ),
    );

    expect(find.text('Revisar copias compartidas'), findsOneWidget);
    expect(find.textContaining('Carta compartida'), findsOneWidget);
    expect(find.textContaining('Carta publicada'), findsOneWidget);
    expect(find.text('Guardar decisiones'), findsOneWidget);
  });
}
