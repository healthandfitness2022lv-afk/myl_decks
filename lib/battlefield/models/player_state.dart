import 'dart:math';
import './zone.dart';
import './card_stub.dart';
class PlayerState {
  final String name;
  final String deckName;
  final Map<Zone, List<CardStub>> piles = {
    Zone.deck: [], Zone.hand: [], Zone.grave: [], Zone.exile: [],
    Zone.goldPool: [], Zone.goldPaid: [], Zone.attack: [], Zone.defense: [], Zone.support: [],
  };

  PlayerState(this.name, this.deckName);

  void generateDeck(int n, {String prefix = 'C'}) {
    piles[Zone.deck] = List.generate(n, (i) => CardStub('$prefix${i + 1}'));
  }

  void shuffle() => piles[Zone.deck]!.shuffle(Random());

  CardStub? drawOne() {
    if (piles[Zone.deck]!.isEmpty) return null;
    final c = piles[Zone.deck]!.removeLast();
    piles[Zone.hand]!.add(c);
    return c;
  }

  List<CardStub> moveFromTop(Zone from, Zone to, int qty) {
    final src = piles[from]!;
    final moved = <CardStub>[];
    for (int i = 0; i < qty && src.isNotEmpty; i++) {
      moved.add(src.removeLast());
    }
    piles[to]!.addAll(moved);
    return moved;
  }
}
