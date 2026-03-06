import 'player_state.dart';
import 'card_stub.dart';
import 'zone.dart';

class DragPayload {
  final CardStub card;
  final Zone origin;
  final PlayerState owner;
  DragPayload({required this.card, required this.origin, required this.owner});
}
