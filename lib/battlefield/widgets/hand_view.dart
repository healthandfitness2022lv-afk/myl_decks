import 'package:flutter/material.dart';
import '../models/player_state.dart';
import '../models/card_stub.dart';
import '../models/zone.dart';
import '../models/drag_payload.dart';
import 'card_widget.dart';

class HandView extends StatelessWidget {
  final String ownerName;
  final List<CardStub> cards;
  final void Function(CardStub) onDragStart;
  final bool readOnly;

  /// Dueño de esas cartas (quien arrastra)
  final PlayerState owner;

  const HandView({
    super.key,
    required this.ownerName,
    required this.cards,
    required this.onDragStart,
    required this.readOnly,
    required this.owner,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('Mano', style: TextStyle(fontWeight: FontWeight.bold)),
        SizedBox(
          height: 110, // alto cómodo para ver la mano
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: cards.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final card = cards[i];
              final cardView = CardWidget(card); // sin 'size' ni nada raro

              if (readOnly) return cardView;
              return Draggable<DragPayload>(
                data: DragPayload(
                  card: card,
                  origin: Zone.hand,
                  owner: owner,
                ),
                feedback: Material(color: Colors.transparent, child: cardView),
                childWhenDragging: Opacity(opacity: .3, child: cardView),
                child: cardView,
              );
            },
          ),
        ),
      ],
    );
  }
}
