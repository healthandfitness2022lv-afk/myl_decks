// services/match_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class MatchService {
  static Future<void> finalizeMatch({
    required String matchId,
    required List<String> results, // ej: ['A','B','A'] o ['A','A','']
  }) async {
    assert(results.length == 3);
    final db = FirebaseFirestore.instance;
    final matchRef = db.collection('matches').doc(matchId);

    await db.runTransaction((tx) async {
      final snap = await tx.get(matchRef);
      if (!snap.exists) throw StateError('Match no existe');

      final data = snap.data() as Map<String, dynamic>;
      final status = (data['status'] ?? 'pending') as String;
      if (status == 'finished') return; // evita doble conteo

      final playerA = (data['playerA'] ?? '') as String;
      final playerB = (data['playerB'] ?? '') as String;
      final deckA   = (data['deckA']   ?? '') as String;
      final deckB   = (data['deckB']   ?? '') as String;

      int aWins = 0, bWins = 0;
      for (final r in results) {
        if (r == 'A') aWins++;
        if (r == 'B') bWins++;
      }
      if (aWins < 2 && bWins < 2) {
        throw StateError('El match aún no tiene ganador (Bo3).');
      }

      final aWon = aWins > bWins;
      final winnerUid = aWon ? playerA : playerB;
      final loserUid  = aWon ? playerB : playerA;

      // 1) Cerrar match
      tx.update(matchRef, {
        'results': results,
        'aWins': aWins,
        'bWins': bWins,
        'winner': winnerUid,
        'status': 'finished',
        'date': FieldValue.serverTimestamp(),
      });

      // 2) Stats usuarios
      final winnerRef = db.collection('users').doc(winnerUid);
      final loserRef  = db.collection('users').doc(loserUid);
      tx.set(winnerRef, {
        'matchesPlayed': FieldValue.increment(1),
        'wins': FieldValue.increment(1),
      }, SetOptions(merge: true));
      tx.set(loserRef, {
        'matchesPlayed': FieldValue.increment(1),
        'losses': FieldValue.increment(1),
      }, SetOptions(merge: true));

      // 3) Stats mazos + desgloses
      Map<String, dynamic> _deckInc({
        required bool isWinner,
        required int myWins,
        required int oppWins,
      }) {
        final m = <String, dynamic>{
          'games': FieldValue.increment(1),
          'lastMatchAt': FieldValue.serverTimestamp(),
        };
        if (isWinner) {
          m['wins'] = FieldValue.increment(1);
          if (myWins == 2 && oppWins == 0) {
            m['winsBy20'] = FieldValue.increment(1);
          } else {
            m['winsBy21'] = FieldValue.increment(1);
          }
        } else {
          m['losses'] = FieldValue.increment(1);
          if (oppWins == 2 && myWins == 0) {
            m['lossesBy02'] = FieldValue.increment(1);
          } else {
            m['lossesBy12'] = FieldValue.increment(1);
          }
        }
        return m;
      }

      final aUpdate = _deckInc(isWinner: aWon, myWins: aWins, oppWins: bWins);
      final bUpdate = _deckInc(isWinner: !aWon, myWins: bWins, oppWins: aWins);

      tx.set(db.collection('decks').doc(deckA), aUpdate, SetOptions(merge: true));
      tx.set(db.collection('decks').doc(deckB), bUpdate, SetOptions(merge: true));
    });
  }
}
