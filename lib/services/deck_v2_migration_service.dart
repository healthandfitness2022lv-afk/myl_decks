import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/deck.dart';
import '../models/inventory.dart';

enum DeckConfigurationSource { current, embeddedObjective, linkedTarget }

class DeckMigrationPair {
  final Deck deck;
  final Deck? linkedTarget;
  final bool hasConfigurationConflict;
  final List<Deck> suggestedTargets;

  const DeckMigrationPair({
    required this.deck,
    this.linkedTarget,
    this.hasConfigurationConflict = false,
    this.suggestedTargets = const [],
  });
}

class DeckMigrationPreview {
  final List<Deck> alreadyMigrated;
  final List<DeckMigrationPair> physicalDecks;
  final List<Deck> orphanTargets;
  final bool blockedByActivePlans;

  const DeckMigrationPreview({
    required this.alreadyMigrated,
    required this.physicalDecks,
    required this.orphanTargets,
    required this.blockedByActivePlans,
  });

  bool get hasConflicts =>
      physicalDecks.any((pair) => pair.hasConfigurationConflict);
}

class DeckMigrationSelection {
  final String deckId;
  final DeckConfigurationSource source;
  final String? targetDeckId;

  const DeckMigrationSelection({
    required this.deckId,
    required this.source,
    this.targetDeckId,
  });
}

class DeckV2MigrationService {
  final String uid;
  final FirebaseFirestore db;

  DeckV2MigrationService(this.uid, [FirebaseFirestore? firestore])
    : db = firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _user =>
      db.collection('users').doc(uid);
  CollectionReference<Map<String, dynamic>> get _decks =>
      _user.collection('decks');
  CollectionReference<Map<String, dynamic>> get _plans =>
      _user.collection('transfer_plans');
  Future<Map<String, dynamic>> _migrationState() async {
    final user = await _user.get();
    final state = user.data()?['deckMigrationV2'];
    return state is Map ? Map<String, dynamic>.from(state) : {};
  }

  Future<void> _writeMigrationState(Map<String, dynamic> state) =>
      _user.set({'deckMigrationV2': state}, SetOptions(merge: true));

  Future<DeckMigrationPreview> preview() async {
    final results = await Future.wait([_decks.get(), _plans.get()]);
    final deckSnapshot = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final planSnapshot = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final decks =
        deckSnapshot.docs
            .map((doc) => Deck.fromFirestore(doc.id, doc.data()))
            .toList();
    final migrated = decks.where((deck) => deck.isUnified).toList();
    final physical =
        decks.where((deck) => !deck.isUnified && !deck.isTarget).toList();
    final targets =
        decks.where((deck) => !deck.isUnified && deck.isTarget).toList();
    final targetById = {for (final target in targets) target.id: target};
    final claimedTargets = <String>{};
    final pairs = <DeckMigrationPair>[];

    for (final deck in physical) {
      Deck? explicit;
      final linkedId = deck.linkedDeckId;
      if (linkedId != null && linkedId.isNotEmpty) {
        explicit = targetById[linkedId];
      }
      explicit ??= targets.cast<Deck?>().firstWhere(
        (target) => target?.linkedDeckId == deck.id,
        orElse: () => null,
      );
      if (explicit != null) claimedTargets.add(explicit.id);
      final embedded = deck.objectiveCards.isNotEmpty;
      final conflict =
          embedded &&
          explicit != null &&
          !_sameConfiguration(deck.objectiveCards, explicit.cards);
      final suggestions =
          targets
              .where(
                (target) =>
                    target.id != explicit?.id &&
                    !claimedTargets.contains(target.id) &&
                    target.race == deck.race &&
                    target.edition == deck.edition,
              )
              .toList();
      pairs.add(
        DeckMigrationPair(
          deck: deck,
          linkedTarget: explicit,
          hasConfigurationConflict: conflict,
          suggestedTargets: suggestions,
        ),
      );
    }
    final active = planSnapshot.docs.any((doc) {
      final status = TransferPlan.fromMap(doc.id, doc.data()).status;
      return status == TransferPlanStatus.active ||
          status == TransferPlanStatus.readyToReturn;
    });
    return DeckMigrationPreview(
      alreadyMigrated: migrated,
      physicalDecks: pairs,
      orphanTargets:
          targets
              .where((target) => !claimedTargets.contains(target.id))
              .toList(),
      blockedByActivePlans: active,
    );
  }

  Future<void> migrate({
    required DeckMigrationPreview preview,
    required List<DeckMigrationSelection> selections,
  }) async {
    final fresh = await this.preview();
    if (fresh.blockedByActivePlans) {
      throw StateError('Hay un plan de movimiento activo. Finalízalo primero.');
    }
    final previousState = await _migrationState();
    if (previousState['phase'] == 'writing') {
      final survivors = List<String>.from(
        previousState['survivorIds'] ?? const [],
      );
      final duplicates = List<String>.from(
        previousState['duplicateIds'] ?? const [],
      );
      if (survivors.isNotEmpty && duplicates.isNotEmpty) {
        var allSurvivorsMigrated = true;
        for (final id in survivors) {
          final document = await _decks.doc(id).get();
          if (!document.exists ||
              (document.data()?['schemaVersion'] ?? 0) != 2) {
            allSurvivorsMigrated = false;
            break;
          }
        }
        if (allSurvivorsMigrated) {
          final cleanup = db.batch();
          for (final id in duplicates) {
            cleanup.delete(_decks.doc(id));
          }
          await cleanup.commit();
          await _writeMigrationState({
            ...previousState,
            'phase': 'complete',
            'completedAt': FieldValue.serverTimestamp(),
            'deletedDuplicateIds': duplicates,
          });
          return;
        }
        // El intento anterior se detuvo antes de confirmar el batch. Los
        // documentos siguen legacy, así que es seguro repetir la escritura.
      }
    }
    final selectionByDeck = {
      for (final value in selections) value.deckId: value,
    };
    if (fresh.physicalDecks.any(
      (pair) =>
          pair.hasConfigurationConflict &&
          !selectionByDeck.containsKey(pair.deck.id),
    )) {
      throw StateError('Aún hay configuraciones en conflicto sin resolver.');
    }

    await _writeMigrationState({
      'version': 2,
      'phase': 'writing',
      'startedAt': FieldValue.serverTimestamp(),
    });

    final duplicateIds = <String>{};
    final batch = db.batch();
    final userSnapshot = await _user.get();
    final priorityData = userSnapshot.data()?['deckPriority'];
    final orderedIds = List<String>.from(
      priorityData is Map
          ? priorityData['orderedDeckIds'] ?? const []
          : const [],
    );
    final migrationOrder = [
      ...fresh.physicalDecks.map((pair) => pair.deck.id),
      ...fresh.orphanTargets.map((deck) => deck.id),
    ];
    for (final id in migrationOrder) {
      if (!orderedIds.contains(id)) orderedIds.add(id);
    }
    for (final pair in fresh.physicalDecks) {
      final selection = selectionByDeck[pair.deck.id];
      if (pair.linkedTarget != null) duplicateIds.add(pair.linkedTarget!.id);
      final source =
          selection?.source ??
          (pair.linkedTarget != null
              ? DeckConfigurationSource.linkedTarget
              : pair.deck.objectiveCards.isNotEmpty
              ? DeckConfigurationSource.embeddedObjective
              : DeckConfigurationSource.current);
      Deck chosen = pair.deck;
      List<DeckCardEntry> configuration = pair.deck.cards;
      if (source == DeckConfigurationSource.embeddedObjective) {
        configuration = pair.deck.objectiveCards;
      } else if (source == DeckConfigurationSource.linkedTarget) {
        final targetId = selection?.targetDeckId ?? pair.linkedTarget?.id;
        Deck? target;
        for (final candidate in fresh.orphanTargets.followedBy(
          fresh.physicalDecks
              .map((value) => value.linkedTarget)
              .whereType<Deck>(),
        )) {
          if (candidate.id == targetId) {
            target = candidate;
            break;
          }
        }
        if (target == null) {
          throw StateError('No se encontró la configuración elegida.');
        }
        configuration = target.cards;
        duplicateIds.add(target.id);
      }
      chosen = chosen.copyWith(
        schemaVersion: 2,
        assemblyEnabled: true,
        cards: configuration,
        objectiveCards: const [],
        linkedDeckId: null,
      );
      batch.set(_decks.doc(chosen.id), {
        ...chosen.toMap(),
        'status': FieldValue.delete(),
        'objectiveCards': FieldValue.delete(),
        'linkedDeckId': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    for (final orphan in fresh.orphanTargets.where(
      (target) => !duplicateIds.contains(target.id),
    )) {
      final unified = orphan.copyWith(
        schemaVersion: 2,
        assemblyEnabled: false,
        objectiveCards: const [],
        linkedDeckId: null,
      );
      batch.set(_decks.doc(orphan.id), {
        ...unified.toMap(),
        'status': FieldValue.delete(),
        'objectiveCards': FieldValue.delete(),
        'linkedDeckId': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await _writeMigrationState({
      'version': 2,
      'phase': 'writing',
      'startedAt': previousState['startedAt'] ?? FieldValue.serverTimestamp(),
      'survivorIds': fresh.physicalDecks.map((pair) => pair.deck.id).toList(),
      'duplicateIds': duplicateIds.toList(),
    });
    batch.set(_user, {
      'deckPriority': {
        'orderedDeckIds':
            orderedIds.where((id) => !duplicateIds.contains(id)).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));
    await batch.commit();

    // Verifica la fase escrita antes de borrar cada documento duplicado.
    for (final pair in fresh.physicalDecks) {
      final document = await _decks.doc(pair.deck.id).get();
      if (!document.exists || (document.data()?['schemaVersion'] ?? 0) != 2) {
        throw StateError('La verificación falló; no se borraron duplicados.');
      }
    }
    final deleteBatch = db.batch();
    for (final id in duplicateIds) {
      deleteBatch.delete(_decks.doc(id));
    }
    await deleteBatch.commit();
    await _writeMigrationState({
      'version': 2,
      'phase': 'complete',
      'completedAt': FieldValue.serverTimestamp(),
      'survivorIds': fresh.physicalDecks.map((pair) => pair.deck.id).toList(),
      'duplicateIds': duplicateIds.toList(),
      'deletedDuplicateIds': duplicateIds.toList(),
    });
  }

  bool _sameConfiguration(List<DeckCardEntry> a, List<DeckCardEntry> b) {
    Map<String, int> counts(List<DeckCardEntry> entries) {
      final result = <String, int>{};
      for (final entry in entries) {
        final key =
            entry.cardId?.trim().isNotEmpty == true
                ? 'card:${entry.cardId}'
                : '${entry.name.toLowerCase()}|${entry.edicion?.toLowerCase() ?? ''}';
        result[key] = (result[key] ?? 0) + entry.count;
      }
      return result;
    }

    final left = counts(a);
    final right = counts(b);
    if (left.length != right.length) return false;
    return left.entries.every((entry) => right[entry.key] == entry.value);
  }
}
