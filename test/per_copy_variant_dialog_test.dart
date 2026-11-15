import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/models/card_variant.dart';
import 'package:myl_decks/widgets/per_copy_variant_dialog.dart';

void main() {
  testWidgets('muestra copias existentes y faltantes en el mismo selector', (
    tester,
  ) async {
    final variant = CardVariant(
      id: 'normal',
      name: 'Normal',
      printType: 'Normal',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PerCopyVariantDialog(
            title: 'Carta',
            subtitle: '1 de 3 declaradas',
            count: 3,
            ownedCount: 1,
            variants: [variant],
            currentSelection: const ['normal'],
            availableByVariant: const {'normal': 1},
            unidentifiedAvailable: 0,
          ),
        ),
      ),
    );

    expect(find.text('Copia 1'), findsOneWidget);
    expect(find.text('Copia 2'), findsOneWidget);
    expect(find.text('Copia 3'), findsOneWidget);
    expect(find.text('La tienes'), findsOneWidget);
    expect(find.text('No tengo versión'), findsNWidgets(4));
  });
}
