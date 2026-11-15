import 'package:flutter/material.dart';

import '../domain/collection_reconciliation.dart';

class DeckReconciliationDialog extends StatefulWidget {
  final DeckReconciliationProposal proposal;
  final Map<String, String> deckNames;

  const DeckReconciliationDialog({
    super.key,
    required this.proposal,
    required this.deckNames,
  });

  @override
  State<DeckReconciliationDialog> createState() =>
      _DeckReconciliationDialogState();
}

class _DeckReconciliationDialogState extends State<DeckReconciliationDialog> {
  late final Map<String, String?> _selections = {
    for (final conflict in widget.proposal.conflicts) conflict.itemKey: null,
    for (final conflict in widget.proposal.saleConflicts)
      'sale:${conflict.itemKey}': null,
  };

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Revisar copias compartidas'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Resuelve sólo las copias que tienen más de un destino o están publicadas. Nada se moverá en silencio.',
            ),
            const SizedBox(height: 12),
            for (final conflict in widget.proposal.saleConflicts) ...[
              Text(
                '${conflict.cardName} · ${conflict.neededForDecks} reservada${conflict.neededForDecks == 1 ? '' : 's'} que necesita un mazo',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                value: _selections['sale:${conflict.itemKey}'],
                decoration: const InputDecoration(
                  labelText: 'Resolver publicación',
                ),
                items: const [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Mantener venta y dejar mazo incompleto'),
                  ),
                  DropdownMenuItem<String?>(
                    value: '__release_sale__',
                    child: Text('Pausar publicaciones de esta carta'),
                  ),
                ],
                onChanged:
                    (value) => setState(
                      () => _selections['sale:${conflict.itemKey}'] = value,
                    ),
              ),
              const SizedBox(height: 14),
            ],
            for (final conflict in widget.proposal.conflicts) ...[
              Text(
                '${conflict.cardName} · ${conflict.available} disponible${conflict.available == 1 ? '' : 's'}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                value: _selections[conflict.itemKey],
                decoration: const InputDecoration(labelText: 'Asignar a'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Dejar sin asignar'),
                  ),
                  for (final candidate in conflict.requestedByDeck.entries)
                    DropdownMenuItem<String?>(
                      value: candidate.key,
                      child: Text(
                        '${widget.deckNames[candidate.key] ?? 'Mazo'} · necesita ${candidate.value}',
                      ),
                    ),
                ],
                onChanged:
                    (value) =>
                        setState(() => _selections[conflict.itemKey] = value),
              ),
              const SizedBox(height: 14),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar guardado'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _selections),
        child: const Text('Guardar decisiones'),
      ),
    ],
  );
}
