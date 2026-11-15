import 'package:flutter/material.dart';

import '../domain/inventory_planner.dart';

/// Resumen para repartir stock libre sobrante entre mazos que lo necesitan:
/// los casos sin ambigüedad (una carta, un solo mazo candidato) vienen
/// preseleccionados; los casos con varios mazos que necesitan la misma
/// carta se muestran aparte con un stepper por mazo para que el usuario
/// reparta el stock libre él mismo — nunca se reparte parejo en automático.
/// Reutilizado por "Rellenar mazos" (/inventario) y por el flujo de tocar
/// una carta gris en el detalle de un mazo.
class FillDecksDialog extends StatefulWidget {
  final List<FreeStockAssignment> assignments;
  final String title;
  const FillDecksDialog({
    super.key,
    required this.assignments,
    this.title = 'Rellenar mazos',
  });

  @override
  State<FillDecksDialog> createState() => _FillDecksDialogState();
}

class _FillDecksDialogState extends State<FillDecksDialog> {
  // cardKey -> deckId -> cantidad elegida
  late final Map<String, Map<String, int>> _picked;

  @override
  void initState() {
    super.initState();
    _picked = {
      for (final a in widget.assignments)
        a.cardKey: {
          if (a.isUnambiguous)
            a.candidates.single.deckId: a.free.clamp(
              0,
              a.candidates.single.missing,
            ),
        },
    };
  }

  int _pickedFor(String cardKey, String deckId) =>
      _picked[cardKey]?[deckId] ?? 0;

  int _pickedTotal(String cardKey) =>
      (_picked[cardKey] ?? const {}).values.fold(0, (a, b) => a + b);

  void _setPicked(FreeStockAssignment a, FreeStockCandidate c, int value) {
    final othersPicked =
        _pickedTotal(a.cardKey) - _pickedFor(a.cardKey, c.deckId);
    final room = (a.free - othersPicked).clamp(0, a.free);
    setState(() {
      _picked.putIfAbsent(a.cardKey, () => {})[c.deckId] = value.clamp(
        0,
        room < c.missing ? room : c.missing,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final unambiguous =
        widget.assignments.where((a) => a.isUnambiguous).toList();
    final ambiguous =
        widget.assignments.where((a) => !a.isUnambiguous).toList();
    return AlertDialog(
      backgroundColor: const Color(0xFF12161D),
      title: Text(widget.title, style: const TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (unambiguous.isNotEmpty) ...[
                const Text(
                  'Se asignarán automáticamente:',
                  style: TextStyle(
                    color: Color(0xFF75D69C),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                for (final a in unambiguous)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${_pickedFor(a.cardKey, a.candidates.single.deckId)}x ${a.cardName} → ${a.candidates.single.deckName}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
              ],
              if (ambiguous.isNotEmpty) ...[
                const Text(
                  'Varios mazos necesitan estas cartas — elige cuánto va a cada uno:',
                  style: TextStyle(
                    color: Color(0xFFF1D48B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                for (final a in ambiguous) ...[
                  Text(
                    '${a.cardName} (${a.free} libres)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  for (final c in a.candidates)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${c.deckName} (le faltan ${c.missing})',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          IconButton(
                            iconSize: 18,
                            onPressed:
                                _pickedFor(a.cardKey, c.deckId) <= 0
                                    ? null
                                    : () => _setPicked(
                                      a,
                                      c,
                                      _pickedFor(a.cardKey, c.deckId) - 1,
                                    ),
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              color: Colors.white54,
                            ),
                          ),
                          Text(
                            '${_pickedFor(a.cardKey, c.deckId)}',
                            style: const TextStyle(color: Colors.white),
                          ),
                          IconButton(
                            iconSize: 18,
                            onPressed:
                                (_pickedFor(a.cardKey, c.deckId) >= c.missing ||
                                        _pickedTotal(a.cardKey) >= a.free)
                                    ? null
                                    : () => _setPicked(
                                      a,
                                      c,
                                      _pickedFor(a.cardKey, c.deckId) + 1,
                                    ),
                            icon: const Icon(
                              Icons.add_circle_outline,
                              color: Color(0xFFF1D48B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final selection = <String, List<(String, int)>>{
              for (final entry in _picked.entries)
                entry.key: [
                  for (final byDeck in entry.value.entries)
                    if (byDeck.value > 0) (byDeck.key, byDeck.value),
                ],
            }..removeWhere((_, moves) => moves.isEmpty);
            Navigator.pop(context, selection);
          },
          child: const Text('Aplicar todo'),
        ),
      ],
    );
  }
}
