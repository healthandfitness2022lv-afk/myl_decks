// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/inventory_planner.dart';
import '../domain/collection_reconciliation.dart';
import '../domain/deck_stock_groups.dart';
import '../models/deck.dart';
import '../models/inventory.dart';
import '../utils/text_normalize.dart';
import 'wishlist_service.dart';

class InventoryException implements Exception {
  final String message;
  const InventoryException(this.message);
  @override
  String toString() => message;
}

/// Variante puntual de [InventoryException] lanzada por
/// [InventoryService.setDeckCopyVariants] cuando falta stock de una
/// variante concreta. Permite a la UI ofrecer "agregar las que faltan y
/// asignarlas" sin tener que parsear el mensaje de error.
class VariantShortageException extends InventoryException {
  final String variantId;
  final int missing;
  const VariantShortageException(super.message, this.variantId, this.missing);
}

class InventoryService {
  final String uid;
  final FirebaseFirestore db;
  InventoryService(this.uid, [FirebaseFirestore? firestore])
    : db = firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _user =>
      db.collection('users').doc(uid);
  CollectionReference<Map<String, dynamic>> get _inventory =>
      _user.collection('inventory');
  CollectionReference<Map<String, dynamic>> get _plans =>
      _user.collection('transfer_plans');
  CollectionReference<Map<String, dynamic>> get _decks =>
      _user.collection('decks');

  Stream<List<InventoryItem>> watchInventory() => _inventory.snapshots().map(
    (snapshot) =>
        snapshot.docs
            .map((doc) => InventoryItem.fromMap(doc.id, doc.data()))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name)),
  );

  Stream<List<TransferPlan>> watchPlans() => _plans
      .orderBy('updatedAt', descending: true)
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.docs
                .map((doc) => TransferPlan.fromMap(doc.id, doc.data()))
                .toList(),
      );

  /// Mazos del usuario marcados "vendible": sus copias asignadas cuentan
  /// como disponibles para publicar en el marketplace sin desarmar el mazo.
  /// Punto único de esta consulta — la usan tanto el marketplace como las
  /// correcciones de cantidad, para no duplicar el criterio.
  /// El marketplace fue retirado de la app, así que ya no hay mazos
  /// vendibles; se conserva la firma para no tocar las correcciones.
  Future<Set<String>> sellableDeckIds() async => const <String>{};

  Future<List<InventoryItem>> listInventory() async {
    final snapshot = await _inventory.get();
    return snapshot.docs
        .map((doc) => InventoryItem.fromMap(doc.id, doc.data()))
        .toList();
  }

  Future<DeckReconciliationProposal> previewDeckReconciliation(
    Deck candidate,
  ) async {
    if (!countsTowardCollectionCompleteness(candidate)) {
      return const DeckReconciliationProposal(
        automaticAllocations: {},
        conflicts: [],
        shortagesByDeck: {},
      );
    }
    final snapshot = await _decks.get();
    final storedDecks =
        snapshot.docs
            .map((doc) => Deck.fromFirestore(doc.id, doc.data()))
            .toList();
    final previous =
        storedDecks.where((deck) => deck.id == candidate.id).firstOrNull;
    final relevantKeys = _changedEntryKeys(previous, candidate);
    if (relevantKeys.isEmpty) {
      return const DeckReconciliationProposal(
        automaticAllocations: {},
        conflicts: [],
        shortagesByDeck: {},
      );
    }
    final decks = [
      for (final deck in storedDecks.where((deck) => deck.id != candidate.id))
        _onlyCards(deck, relevantKeys),
      _onlyCards(candidate, relevantKeys),
    ];
    return buildDeckReconciliation(
      inventory: await _listInventoryByKeys(relevantKeys),
      decks: decks,
    );
  }

  Set<String> _changedEntryKeys(Deck? previous, Deck candidate) {
    final oldCounts = _entryCounts(previous?.cards ?? const []);
    final newCounts = _entryCounts(candidate.cards);
    final allKeys = {...oldCounts.keys, ...newCounts.keys};
    if (previous == null ||
        deckStockTargetId(previous) != deckStockTargetId(candidate) ||
        previous.assemblyEnabled != candidate.assemblyEnabled) {
      return allKeys;
    }
    return {
      for (final key in allKeys)
        if ((oldCounts[key] ?? 0) != (newCounts[key] ?? 0)) key,
    };
  }

  Deck _onlyCards(Deck deck, Set<String> keys) => deck.copyWith(
    cards:
        deck.cards
            .where((card) => keys.contains(entryInventoryKey(card)))
            .toList(),
  );

  Future<List<InventoryItem>> _listInventoryByKeys(Set<String> keys) async {
    if (keys.isEmpty) return const [];
    final snapshots = await Future.wait([
      for (final key in keys) _inventory.doc(key).get(),
    ]);
    return [
      for (var index = 0; index < snapshots.length; index++)
        if (snapshots[index].exists)
          InventoryItem.fromMap(
            keys.elementAt(index),
            snapshots[index].data()!,
          ),
    ];
  }

  /// Agrega varias cartas en una única confirmación. Las entradas repetidas
  /// se consolidan antes de escribir para evitar diálogos y escrituras extra.
  Future<void> applyInventoryBatch(List<InventoryBatchChange> changes) async {
    final grouped = <String, List<InventoryBatchChange>>{};
    for (final change in changes.where((change) => change.quantity > 0)) {
      final key = inventoryKey(
        cardId: change.cardId,
        name: change.name,
        edition: change.edition,
      );
      grouped.putIfAbsent(key, () => []).add(change);
    }
    if (grouped.isEmpty) return;
    await db.runTransaction((tx) async {
      final refs = {for (final key in grouped.keys) key: _inventory.doc(key)};
      final snapshots = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final entry in refs.entries) {
        snapshots[entry.key] = await tx.get(entry.value);
      }
      for (final entry in grouped.entries) {
        final sample = entry.value.first;
        final snapshot = snapshots[entry.key]!;
        final current =
            snapshot.exists
                ? InventoryItem.fromMap(entry.key, snapshot.data()!)
                : InventoryItem(
                  key: entry.key,
                  cardId: sample.cardId,
                  name: sample.name,
                  edition: sample.edition,
                  type: sample.type,
                  total: 0,
                );
        final variants = Map<String, int>.from(current.variantTotals);
        var added = 0;
        for (final change in entry.value) {
          added += change.quantity;
          final variantId = change.variantId?.trim() ?? '';
          if (variantId.isNotEmpty) {
            variants[variantId] = (variants[variantId] ?? 0) + change.quantity;
          }
        }
        final next = current.copyWith(
          total: current.total + added,
          variantTotals: variants,
        );
        tx.set(refs[entry.key]!, {
          ...next.toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
    await refreshDynamicWishlist();
  }

  /// Libera publicaciones de cartas elegidas explícitamente durante la
  /// reconciliación. Las filas permanecen visibles en la tienda con stock 0.
  Future<void> releaseMarketplaceReservations(Set<String> itemKeys) async {
    for (final key in itemKeys) {
      final itemRef = _inventory.doc(key);
      await db.runTransaction((tx) async {
        final snapshot = await tx.get(itemRef);
        if (!snapshot.exists) return;
        final item = InventoryItem.fromMap(key, snapshot.data()!);
        final listingRefs = [
          for (final reservation in item.reservations.values)
            _user
                .collection('marketplace_folders')
                .doc(reservation.folderId)
                .collection('listings')
                .doc(reservation.listingId),
        ];
        final listingSnapshots =
            <
              DocumentReference<Map<String, dynamic>>,
              DocumentSnapshot<Map<String, dynamic>>
            >{};
        for (final ref in listingRefs) {
          listingSnapshots[ref] = await tx.get(ref);
        }
        tx.update(itemRef, {
          'reservations': <String, dynamic>{},
          'updatedAt': FieldValue.serverTimestamp(),
        });
        for (final ref in listingRefs) {
          if (listingSnapshots[ref]?.exists == true) {
            tx.update(ref, {
              'stock': 0,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }
      });
    }
    await refreshDynamicWishlist();
  }

  /// Repara items del inventario que quedaron sin `edition` guardada por un
  /// bug (agregar copias desde el detalle de un mazo no propagaba la
  /// edición de la carta): busca la edición real en el catálogo y la
  /// completa. No toca items que ya tienen edición o que no tienen cardId
  /// (no hay de dónde resolverla). Devuelve cuántos se repararon.
  Future<int> repairMissingEditions() async {
    final items = await listInventory();
    final pending =
        items
            .where(
              (item) =>
                  (item.edition ?? '').trim().isEmpty &&
                  (item.cardId ?? '').trim().isNotEmpty,
            )
            .toList();
    if (pending.isEmpty) return 0;
    var fixed = 0;
    for (final item in pending) {
      final cardId = item.cardId!.trim();
      final cardDoc = await db.collection('cards').doc(cardId).get();
      final edition = (cardDoc.data()?['edicion'] ?? '').toString().trim();
      if (edition.isEmpty) continue;
      await _inventory.doc(item.key).update({
        'edition': edition,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      fixed++;
    }
    return fixed;
  }

  Future<void> migrateFromDecksIfNeeded(List<Deck> decks) async {
    final user = await _user.get();
    final version =
        ((user.data()?['inventoryMigrationVersion'] as num?)?.toInt() ?? 0);
    if (version >= 4) return;
    if (version >= 2) {
      await _migrateStockTargetsV3(decks);
      return;
    }

    // v2 resuelve entradas antiguas sin cardId contra el catálogo. La v1 podía
    // guardar "legacy:nombre|edición" mientras el objetivo usaba "card:id",
    // haciendo que una colección existente pareciera tener disponibilidad cero.
    final catalogSnapshot = await db.collection('cards').get();
    final cardIdBySignature = <String, String>{};
    final idsByName = <String, Set<String>>{};
    for (final doc in catalogSnapshot.docs) {
      final data = doc.data();
      final name = (data['nombre'] ?? '').toString();
      final edition = (data['edicion'] ?? '').toString();
      if (name.trim().isEmpty) continue;
      cardIdBySignature[_cardSignature(name, edition)] = doc.id;
      idsByName
          .putIfAbsent(normalizeSearch(name), () => <String>{})
          .add(doc.id);
    }

    String? resolveCardId(String? cardId, String name, String? edition) {
      final explicit = cardId?.trim() ?? '';
      if (explicit.isNotEmpty) return explicit;
      final exact = cardIdBySignature[_cardSignature(name, edition)];
      if (exact != null) return exact;
      final byName = idsByName[normalizeSearch(name)] ?? const <String>{};
      return byName.length == 1 ? byName.single : null;
    }

    final grouped = <String, InventoryItem>{};
    for (final deck in decks.where(
      (deck) => !deck.isUnified && !deck.isTarget,
    )) {
      for (final entry in deck.cards) {
        final resolvedId = resolveCardId(
          entry.cardId,
          entry.name,
          entry.edicion,
        );
        final key = inventoryKey(
          cardId: resolvedId,
          name: entry.name,
          edition: entry.edicion,
        );
        final current = grouped[key];
        final allocations = {...?current?.allocations};
        allocations[deck.id] = (allocations[deck.id] ?? 0) + entry.count;
        final variants = {...?current?.variantTotals};
        final variantAllocations = <String, Map<String, int>>{
          for (final variant
              in (current?.variantAllocations ?? const {}).entries)
            variant.key: Map<String, int>.from(variant.value),
        };
        for (final variant in entry.selectedVariants ?? const <String>[]) {
          if (variant.isNotEmpty) {
            variants[variant] = (variants[variant] ?? 0) + 1;
            final byDeck = variantAllocations.putIfAbsent(
              variant,
              () => <String, int>{},
            );
            byDeck[deck.id] = (byDeck[deck.id] ?? 0) + 1;
          }
        }
        grouped[key] = InventoryItem(
          key: key,
          cardId: resolvedId ?? current?.cardId,
          name: entry.name.isNotEmpty ? entry.name : (current?.name ?? key),
          edition: entry.edicion ?? current?.edition,
          type: entry.tipo ?? current?.type,
          total: (current?.total ?? 0) + entry.count,
          allocations: allocations,
          variantTotals: variants,
          variantAllocations: variantAllocations,
          reservations: current?.reservations ?? const {},
        );
      }
    }

    final existingSnapshot = await _inventory.get();
    final legacyRefsToDelete = <DocumentReference<Map<String, dynamic>>>[];
    for (final doc in existingSnapshot.docs) {
      final existing = InventoryItem.fromMap(doc.id, doc.data());
      final resolvedId = resolveCardId(
        existing.cardId,
        existing.name,
        existing.edition,
      );
      final canonicalKey = inventoryKey(
        cardId: resolvedId,
        name: existing.name,
        edition: existing.edition,
      );
      final migrated = grouped[canonicalKey];
      if (migrated != null) {
        final variants = Map<String, int>.from(migrated.variantTotals);
        existing.variantTotals.forEach((id, variantCount) {
          if ((variants[id] ?? 0) < variantCount) variants[id] = variantCount;
        });
        grouped[canonicalKey] = InventoryItem(
          key: canonicalKey,
          cardId: resolvedId ?? migrated.cardId,
          name: migrated.name,
          edition: migrated.edition ?? existing.edition,
          type: migrated.type ?? existing.type,
          total:
              migrated.total +
              (existing.total - existing.assigned).clamp(0, 999999),
          allocations: migrated.allocations,
          variantTotals: variants,
          variantAllocations: existing.variantAllocations,
          reservations: existing.reservations,
        );
        if (doc.id != canonicalKey) legacyRefsToDelete.add(doc.reference);
      } else if (doc.id != canonicalKey && existing.assigned == 0) {
        // Carta agregada manualmente antes de v2: conserva todas sus copias
        // libres, pero muévela a la identidad canónica del catálogo.
        grouped[canonicalKey] = InventoryItem(
          key: canonicalKey,
          cardId: resolvedId,
          name: existing.name,
          edition: existing.edition,
          type: existing.type,
          total: existing.total,
          variantTotals: existing.variantTotals,
          variantAllocations: existing.variantAllocations,
          reservations: existing.reservations,
        );
        legacyRefsToDelete.add(doc.reference);
      }
    }

    final items = grouped.values.toList();
    final operations = <void Function(WriteBatch)>[
      for (final item in items)
        (batch) => batch.set(_inventory.doc(item.key), item.toMap()),
      for (final ref in legacyRefsToDelete) (batch) => batch.delete(ref),
    ];
    for (var start = 0; start < operations.length; start += 450) {
      final itemBatch = db.batch();
      final end = (start + 450).clamp(0, operations.length);
      for (final operation in operations.sublist(start, end)) {
        operation(itemBatch);
      }
      await itemBatch.commit();
    }
    final batch = db.batch();
    batch.set(_user, {
      'inventoryMigrationVersion': 2,
      'inventoryMigratedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
    await _migrateStockTargetsV3(decks);
  }

  Future<void> _migrateStockTargetsV3(List<Deck> decks) async {
    final targets = buildDeckStockTargets(decks)..sort((a, b) {
      final aCounts = a.members.any(countsTowardCollectionCompleteness);
      final bCounts = b.members.any(countsTowardCollectionCompleteness);
      if (aCounts != bCounts) return aCounts ? -1 : 1;
      final aCreated = a.members
          .map((deck) => deck.createdAt)
          .reduce((x, y) => x.isBefore(y) ? x : y);
      final bCreated = b.members
          .map((deck) => deck.createdAt)
          .reduce((x, y) => x.isBefore(y) ? x : y);
      final byDate = aCreated.compareTo(bCreated);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
    final snapshot = await _inventory.get();
    final operations = <void Function(WriteBatch)>[];

    for (final doc in snapshot.docs) {
      final item = InventoryItem.fromMap(doc.id, doc.data());
      // Algunos inventarios legacy pueden tener totales inconsistentes
      // (por ejemplo, más copias sumadas en variantTotals que en total, o un
      // total negativo). La migración debe poder sanear sus asignaciones sin
      // fallar antes de escribir el resultado.
      final safeVariantTotals = <String, int>{
        for (final entry in item.variantTotals.entries)
          entry.key: entry.value < 0 ? 0 : entry.value,
      };
      final declaredVariantTotal = safeVariantTotals.values.fold<int>(
        0,
        (total, value) => total + value,
      );
      final safeReserved = item.reserved < 0 ? 0 : item.reserved;
      var normalizedTotal = item.total < 0 ? 0 : item.total;
      if (declaredVariantTotal > normalizedTotal) {
        normalizedTotal = declaredVariantTotal;
      }
      if (safeReserved > normalizedTotal) normalizedTotal = safeReserved;
      var remaining = (normalizedTotal - safeReserved).clamp(
        0,
        normalizedTotal,
      );
      final allocations = <String, int>{};
      for (final target in targets) {
        final required = target.cards
            .where((entry) => entryInventoryKey(entry) == item.key)
            .fold<int>(0, (sum, entry) => sum + entry.count);
        if (required <= 0) continue;
        final pooled = item.allocatedTo(target.id);
        final legacyMaximum = target.members
            .map((deck) => item.allocatedTo(deck.id))
            .fold<int>(
              0,
              (largest, value) => value > largest ? value : largest,
            );
        final wanted = (pooled > legacyMaximum ? pooled : legacyMaximum).clamp(
          0,
          required,
        );
        final accepted = wanted.clamp(0, remaining);
        if (accepted > 0) allocations[target.id] = accepted;
        remaining -= accepted;
      }
      final variants = _variantsForAllocations(
        item: item,
        allocations: allocations,
      );
      operations.add(
        (batch) => batch.update(doc.reference, {
          'total': normalizedTotal,
          'variantTotals': safeVariantTotals,
          'allocations': allocations,
          'variantAllocations': variants,
          'updatedAt': FieldValue.serverTimestamp(),
        }),
      );
    }

    for (var start = 0; start < operations.length; start += 450) {
      final batch = db.batch();
      final end = (start + 450).clamp(0, operations.length);
      for (final operation in operations.sublist(start, end)) {
        operation(batch);
      }
      await batch.commit();
    }
    await _user.set({
      // v4 conserva el pool familiar de v3 y prioriza Racial Edición sobre
      // las asignaciones opcionales de Full/Racial Libre.
      'inventoryMigrationVersion': 4,
      'inventoryMigratedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String _cardSignature(String name, String? edition) =>
      '${normalizeSearch(name)}|${normalizeSearch(edition ?? '')}';

  Future<void> setTotal(InventoryItem item, int total) async {
    await correctOwnedQuantity(item, total);
  }

  /// Corrige a la baja el total de una carta cuando el inventario dice más
  /// copias de las que realmente tienes (ej. "dice 3, en realidad tengo
  /// 2"). Si hace falta, puede quitarle copias a mazos: primero le quita a
  /// [preferredDeckId] (el mazo desde el que se corrigió, normalmente el que
  /// se estaba viendo) y, si no alcanza, sigue quitando de otros mazos hasta
  /// llegar al nuevo total. Nunca toca copias reservadas para venta — si
  /// [newTotal] no alcanza ni quitando todo lo asignado, falla en vez de
  /// tocar una reserva activa.
  Future<void> correctOwnedQuantity(
    InventoryItem item,
    int newTotal, {
    String? preferredDeckId,
  }) async {
    if (newTotal < 0) {
      throw const InventoryException('La cantidad no puede ser negativa.');
    }
    final sellable = await sellableDeckIds();
    final itemRef = _inventory.doc(item.key);
    // La tienda depende del inventario, no al revés: si al bajar el total
    // ya no alcanza para cubrir lo publicado, se recorta el stock de esas
    // publicaciones para que coincidan con lo que de verdad queda — no se
    // bloquea la corrección pidiendo cancelar publicaciones a mano.
    await db.runTransaction((tx) async {
      final snap = await tx.get(itemRef);
      if (!snap.exists) {
        throw const InventoryException('La carta ya no existe.');
      }
      final live = InventoryItem.fromMap(itemRef.id, snap.data()!);

      final reservations = Map<String, InventoryReservation>.from(
        live.reservations,
      );
      var reservedExcess = live.reserved - newTotal;
      final cuts = <InventoryReservation>[];
      if (reservedExcess > 0) {
        for (final id in reservations.keys.toList()) {
          if (reservedExcess <= 0) break;
          final reservation = reservations[id]!;
          final cut = reservation.quantity.clamp(0, reservedExcess);
          if (cut <= 0) continue;
          final nextQuantity = reservation.quantity - cut;
          final updatedReservation = InventoryReservation(
            folderId: reservation.folderId,
            listingId: reservation.listingId,
            variantId: reservation.variantId,
            quantity: nextQuantity,
          );
          if (nextQuantity == 0) {
            reservations.remove(id);
          } else {
            reservations[id] = updatedReservation;
          }
          cuts.add(updatedReservation);
          reservedExcess -= cut;
        }
      }
      // Recortar en la misma transacción el stock publicado de cada
      // listing afectado, para que la tienda nunca quede mostrando más
      // copias de las que realmente hay.
      for (final cut in cuts) {
        final listingRef = _user
            .collection('marketplace_folders')
            .doc(cut.folderId)
            .collection('listings')
            .doc(cut.listingId);
        if (cut.quantity == 0) {
          tx.delete(listingRef);
        } else {
          tx.update(listingRef, {
            'stock': cut.quantity,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      // Cuánto queda reservado después de recortar publicaciones arriba —
      // ya no puede superar newTotal, así que no debe forzar liberar
      // asignaciones de mazos por algo que la tienda ya absorbió.
      final reservedAfterCuts = reservations.values.fold<int>(
        0,
        (sum, r) => sum + r.quantity,
      );
      // Cuánto hay que quitarle a asignaciones para que quepa en newTotal.
      // Si parte de "assigned" ya se contaba dos veces a propósito (copias
      // de un mazo "vendible" que también están reservadas para venta), ese
      // solapamiento no cuenta como exceso a liberar — ya es válido tal
      // cual, aunque el usuario no haya cambiado nada.
      final sellableOverlap =
          live.free < 0
              ? (-live.free).clamp(0, live.allocatedToSellableDecks(sellable))
              : 0;
      var toRemove =
          (live.assigned + reservedAfterCuts - sellableOverlap) - newTotal;
      final allocations = Map<String, int>.from(live.allocations);
      if (toRemove > 0) {
        final order = <String>[
          if (preferredDeckId != null &&
              allocations.containsKey(preferredDeckId))
            preferredDeckId,
          ...allocations.keys.where((id) => id != preferredDeckId),
        ];
        for (final deckId in order) {
          if (toRemove <= 0) break;
          final current = allocations[deckId] ?? 0;
          final removed = current.clamp(0, toRemove);
          final next = current - removed;
          if (next == 0) {
            allocations.remove(deckId);
          } else {
            allocations[deckId] = next;
          }
          toRemove -= removed;
        }
      }
      if (toRemove > 0) {
        // No debería pasar (ya se validó contra reserved arriba), pero deja
        // la carta en un estado inválido si ocurre: aborta antes de escribir.
        throw const InventoryException(
          'No se pudo ajustar la cantidad: hay copias que no se pueden liberar.',
        );
      }

      final variantAllocations = <String, Map<String, int>>{
        for (final variant in live.variantAllocations.entries)
          variant.key: Map<String, int>.from(variant.value),
      };
      for (final byDeck in variantAllocations.values) {
        byDeck.removeWhere((deckId, _) => !allocations.containsKey(deckId));
      }
      for (final deckId in allocations.keys) {
        var remaining = allocations[deckId] ?? 0;
        for (final variantId in variantAllocations.keys.toList()) {
          final byDeck = variantAllocations[variantId]!;
          final current = byDeck[deckId] ?? 0;
          final accepted = current.clamp(0, remaining);
          if (accepted == 0) {
            byDeck.remove(deckId);
          } else {
            byDeck[deckId] = accepted;
          }
          remaining -= accepted;
        }
      }
      variantAllocations.removeWhere((_, byDeck) => byDeck.isEmpty);

      // Recortar variantTotals proporcionalmente si el nuevo total ya no
      // alcanza para todas las copias identificadas.
      final variantTotals = Map<String, int>.from(live.variantTotals);
      var variantExcess =
          variantTotals.values.fold<int>(0, (a, b) => a + b) - newTotal;
      if (variantExcess > 0) {
        for (final variantId in variantTotals.keys.toList()) {
          if (variantExcess <= 0) break;
          final current = variantTotals[variantId] ?? 0;
          final assigned = (variantAllocations[variantId] ?? const {}).values
              .fold<int>(0, (a, b) => a + b);
          final reservedForVariant = reservations.values
              .where((r) => r.variantId == variantId)
              .fold<int>(0, (sum, r) => sum + r.quantity);
          final minimum = assigned + reservedForVariant;
          final removed = (current - minimum).clamp(0, variantExcess);
          final next = current - removed;
          if (next == 0) {
            variantTotals.remove(variantId);
          } else {
            variantTotals[variantId] = next;
          }
          variantExcess -= removed;
        }
      }
      if (variantExcess > 0) {
        final deckOrder = <String>[
          if (preferredDeckId != null) preferredDeckId,
          ...allocations.keys.where((id) => id != preferredDeckId),
        ];
        for (final deckId in deckOrder) {
          if (variantExcess <= 0) break;
          for (final variantId in variantTotals.keys.toList()) {
            if (variantExcess <= 0) break;
            final byDeck = variantAllocations[variantId];
            final currentAtDeck = byDeck?[deckId] ?? 0;
            final removed = currentAtDeck.clamp(0, variantExcess);
            if (removed == 0) continue;
            final nextAtDeck = currentAtDeck - removed;
            if (nextAtDeck == 0) {
              byDeck!.remove(deckId);
            } else {
              byDeck![deckId] = nextAtDeck;
            }
            final nextTotal = (variantTotals[variantId] ?? 0) - removed;
            if (nextTotal == 0) {
              variantTotals.remove(variantId);
              variantAllocations.remove(variantId);
            } else {
              variantTotals[variantId] = nextTotal;
            }
            variantExcess -= removed;
          }
        }
      }
      if (variantExcess > 0) {
        throw const InventoryException(
          'No se pueden eliminar esas variantes porque están reservadas.',
        );
      }

      if (newTotal == 0) {
        tx.delete(itemRef);
        return;
      }
      final updated = live.copyWith(
        total: newTotal,
        allocations: allocations,
        variantTotals: variantTotals,
        variantAllocations: variantAllocations,
        reservations: reservations,
      );
      if (!updated.isValidAllowingSellableOverlap(sellable)) {
        throw const InventoryException(
          'El total y las variantes quedarían en cantidades incompatibles.',
        );
      }
      tx.update(itemRef, {
        'total': newTotal,
        'allocations': allocations,
        'variantTotals': variantTotals,
        'variantAllocations': variantAllocations,
        'reservations': reservations.map(
          (key, value) => MapEntry(key, value.toMap()),
        ),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    await refreshDynamicWishlist();
  }

  Future<void> setAllocation(
    InventoryItem item,
    Deck deck,
    int quantity,
  ) async {
    if (quantity < 0)
      throw const InventoryException('La cantidad no puede ser negativa.');
    final itemRef = _inventory.doc(item.key);
    final deckRef = _decks.doc(deck.id);
    await db.runTransaction((tx) async {
      final itemSnap = await tx.get(itemRef);
      final deckSnap = await tx.get(deckRef);
      if (!itemSnap.exists || !deckSnap.exists)
        throw const InventoryException('La carta o el mazo ya no existe.');
      final liveItem = InventoryItem.fromMap(item.key, itemSnap.data()!);
      final liveDeck = Deck.fromFirestore(deck.id, deckSnap.data()!);
      final listingRefs = <String, DocumentReference<Map<String, dynamic>>>{};
      final listingExists = <String, bool>{};
      for (final reservation in liveItem.reservations.values) {
        final ref = _user
            .collection('marketplace_folders')
            .doc(reservation.folderId)
            .collection('listings')
            .doc(reservation.listingId);
        listingRefs[reservation.listingId] = ref;
        listingExists[reservation.listingId] = (await tx.get(ref)).exists;
      }
      final stockTargetId = deckStockTargetId(liveDeck);
      final allocations = Map<String, int>.from(liveItem.allocations);
      if (quantity == 0)
        allocations.remove(stockTargetId);
      else
        allocations[stockTargetId] = quantity;
      final variantAllocations = <String, Map<String, int>>{
        for (final variant in liveItem.variantAllocations.entries)
          variant.key: Map<String, int>.from(variant.value),
      };
      var excess =
          variantAllocations.values.fold<int>(
            0,
            (sum, byDeck) => sum + (byDeck[stockTargetId] ?? 0),
          ) -
          quantity;
      if (excess > 0) {
        for (final byDeck in variantAllocations.values) {
          final current = byDeck[stockTargetId] ?? 0;
          final removed = current.clamp(0, excess);
          final next = current - removed;
          if (next == 0)
            byDeck.remove(stockTargetId);
          else
            byDeck[stockTargetId] = next;
          excess -= removed;
          if (excess == 0) break;
        }
        variantAllocations.removeWhere((_, byDeck) => byDeck.isEmpty);
      }
      final updated = liveItem.copyWith(
        allocations: allocations,
        variantAllocations: variantAllocations,
      );

      // Las publicaciones representan copias sueltas. Si el usuario toma una
      // de ellas para un mazo, reducir primero el stock de tienda en orden
      // estable. Una ficha agotada se conserva con stock 0 para no perder su
      // precio ni sus datos y poder reactivarla luego.
      final reservations = Map<String, InventoryReservation>.from(
        liveItem.reservations,
      );
      var toWithdraw = (updated.assigned + updated.reserved - updated.total)
          .clamp(0, updated.reserved);
      final reservationIds = reservations.keys.toList()..sort();
      for (final listingId in reservationIds) {
        if (toWithdraw <= 0) break;
        final reservation = reservations[listingId]!;
        final removed = reservation.quantity.clamp(0, toWithdraw);
        final nextQuantity = reservation.quantity - removed;
        if (nextQuantity == 0) {
          reservations.remove(listingId);
        } else {
          reservations[listingId] = InventoryReservation(
            folderId: reservation.folderId,
            listingId: reservation.listingId,
            variantId: reservation.variantId,
            quantity: nextQuantity,
          );
        }
        final listingRef = listingRefs[reservation.listingId];
        if (listingRef != null &&
            (listingExists[reservation.listingId] ?? false)) {
          tx.update(listingRef, {
            'stock': nextQuantity,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        toWithdraw -= removed;
      }
      final fullyUpdated = updated.copyWith(reservations: reservations);
      if (!fullyUpdated.isValid)
        throw InventoryException(
          'Solo hay ${liveItem.outsideDecks + liveItem.allocatedTo(stockTargetId)} copias disponibles para este mazo.',
        );
      final delta = quantity - liveItem.allocatedTo(stockTargetId);
      tx.update(itemRef, {
        'allocations': allocations,
        'variantAllocations': variantAllocations,
        'reservations': reservations.map(
          (key, value) => MapEntry(key, value.toMap()),
        ),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.update(deckRef, {
        if (!liveDeck.isUnified)
          'cards':
              _cardsWithDelta(
                liveDeck.cards,
                liveItem,
                delta,
              ).map((entry) => entry.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Qué stock libre sobrante podría cubrir cada mazo activo, y de qué
  /// cartas hay varios mazos candidatos (ver [findFreeStockAssignments]).
  /// Base del botón "Rellenar mazos" de /inventario: no decide ni mueve
  /// nada por sí solo.
  /// Define las variantes físicas de las copias realmente ubicadas en un
  /// mazo. `null` representa una copia sin variante identificada.
  Future<InventoryItem> setDeckCopyVariants({
    required Deck deck,
    required DeckCardEntry card,
    required List<String?> variants,
  }) async {
    final key = entryInventoryKey(card);
    final itemRef = _inventory.doc(key);
    final deckRef = _decks.doc(deck.id);
    final requestedTargetId = deckStockTargetId(deck);
    final memberRefs = <String, DocumentReference<Map<String, dynamic>>>{
      deck.id: deckRef,
    };
    if (isSharedStockTargetId(requestedTargetId)) {
      final deckSnapshot = await _decks.get();
      for (final document in deckSnapshot.docs) {
        try {
          final candidate = Deck.fromFirestore(document.id, document.data());
          if (deckStockTargetId(candidate) == requestedTargetId) {
            memberRefs[document.id] = document.reference;
          }
        } catch (_) {
          // Un documento de mazo legado malformado no debe impedir que se
          // identifiquen las variantes de la familia válida.
        }
      }
    }
    return db.runTransaction((tx) async {
      final itemSnapshot = await tx.get(itemRef);
      final memberSnapshots =
          <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final entry in memberRefs.entries) {
        memberSnapshots[entry.key] = await tx.get(entry.value);
      }
      final deckSnapshot = memberSnapshots[deck.id]!;
      if (!deckSnapshot.exists) {
        throw const InventoryException('El mazo ya no existe.');
      }
      final liveDeck = Deck.fromFirestore(deck.id, deckSnapshot.data()!);
      final stockTargetId = deckStockTargetId(liveDeck);
      final item =
          itemSnapshot.exists
              ? InventoryItem.fromMap(key, itemSnapshot.data()!)
              : InventoryItem(
                key: key,
                cardId: card.cardId,
                name: card.name,
                edition: card.edicion,
                type: card.tipo,
                total: 0,
              );
      final allocated = item.allocatedTo(stockTargetId);
      if (variants.length < allocated) {
        throw InventoryException(
          'Este mazo ya tiene $allocated copias físicas asignadas; no puedes omitirlas.',
        );
      }
      final additionalVariants = variants.skip(allocated).toList();
      if (additionalVariants.any((id) => (id ?? '').trim().isEmpty)) {
        throw const InventoryException(
          'Elige una versión para cada copia nueva que quieras declarar.',
        );
      }
      final additional = additionalVariants.length;
      final allocatedAfter = allocated + additional;
      final allocations = Map<String, int>.from(item.allocations);
      if (allocatedAfter > 0) allocations[stockTargetId] = allocatedAfter;

      final declaredVariantTotals = Map<String, int>.from(item.variantTotals);
      for (final variantId in additionalVariants) {
        final id = variantId!.trim();
        declaredVariantTotals[id] = (declaredVariantTotals[id] ?? 0) + 1;
      }
      final workingItem = item.copyWith(
        total: item.total + additional,
        allocations: allocations,
        variantTotals: declaredVariantTotals,
      );

      final requested = <String, int>{};
      var requestedUnidentified = 0;
      for (final variantId in variants) {
        final id = variantId?.trim() ?? '';
        if (id.isEmpty) {
          requestedUnidentified++;
        } else {
          requested[id] = (requested[id] ?? 0) + 1;
        }
      }
      final nextVariantAllocations = <String, Map<String, int>>{
        for (final entry in item.variantAllocations.entries)
          entry.key: Map<String, int>.from(entry.value)..remove(stockTargetId),
      }..removeWhere((_, byDeck) => byDeck.isEmpty);

      final assignedElsewhereBase = workingItem.assigned - allocatedAfter;
      final variantsAssignedElsewhereBase = nextVariantAllocations.values
          .fold<int>(
            0,
            (sum, byDeck) =>
                sum +
                byDeck.entries
                    .where((entry) => entry.key != stockTargetId)
                    .fold<int>(0, (a, entry) => a + entry.value),
          );
      // Copias sin variante identificada que no están siendo usadas por
      // OTRO mazo: son las que se pueden "convertir" a una variante nueva
      // que el usuario recién está declarando (ver más abajo).
      var unidentifiedFreeToConvert = (workingItem.unidentified -
              (assignedElsewhereBase - variantsAssignedElsewhereBase))
          .clamp(0, workingItem.total);
      final nextVariantTotals = Map<String, int>.from(
        workingItem.variantTotals,
      );
      // Reservas de marketplace tocadas en esta transacción: el armado de
      // mazos manda sobre lo publicado en la tienda, así que si a un mazo
      // le falta cupo de una variante solo porque está reservada para
      // venta, se recorta la reserva (y su listing) en vez de bloquear la
      // asignación. Lo reservado es "lo último de lo sobrante".
      final reservations = Map<String, InventoryReservation>.from(
        item.reservations,
      );
      final reservationCuts = <InventoryReservation>[];

      for (final request in requested.entries) {
        final assignedElsewhere = (nextVariantAllocations[request.key] ??
                const {})
            .values
            .fold<int>(0, (a, b) => a + b);
        final variantReserved = reservations.values
            .where((r) => r.variantId == request.key)
            .fold<int>(0, (sum, r) => sum + r.quantity);
        var available =
            (nextVariantTotals[request.key] ?? 0) -
            variantReserved -
            assignedElsewhere;
        if (request.value > available) {
          // No hay suficiente stock YA declarado de esta variante: si hay
          // copias sin identificar libres, se declaran ahora como esta
          // variante (primera vez que se marca cuál es cuál).
          final missing = request.value - available;
          final convert = missing.clamp(0, unidentifiedFreeToConvert);
          if (convert > 0) {
            nextVariantTotals[request.key] =
                (nextVariantTotals[request.key] ?? 0) + convert;
            unidentifiedFreeToConvert -= convert;
            available += convert;
          }
        }
        if (request.value > available) {
          // Sigue sin alcanzar: recortar reservas de marketplace de esta
          // variante hasta cubrir lo que falte, antes de rendirse.
          var toFree = request.value - available;
          for (final id in reservations.keys.toList()) {
            if (toFree <= 0) break;
            final reservation = reservations[id]!;
            if (reservation.variantId != request.key) continue;
            final cut = reservation.quantity.clamp(0, toFree);
            if (cut <= 0) continue;
            final nextQuantity = reservation.quantity - cut;
            final updated = InventoryReservation(
              folderId: reservation.folderId,
              listingId: reservation.listingId,
              variantId: reservation.variantId,
              quantity: nextQuantity,
            );
            if (nextQuantity == 0) {
              reservations.remove(id);
            } else {
              reservations[id] = updated;
            }
            reservationCuts.add(updated);
            toFree -= cut;
            available += cut;
          }
        }
        if (request.value > available) {
          throw VariantShortageException(
            'Solo tienes $available copias disponibles de esa variante '
            '(incluyendo las que se pueden identificar ahora).',
            request.key,
            request.value - available,
          );
        }
        nextVariantAllocations.putIfAbsent(
              request.key,
              () => <String, int>{},
            )[stockTargetId] =
            request.value;
      }

      if (requestedUnidentified > unidentifiedFreeToConvert) {
        throw InventoryException(
          'Solo tienes $unidentifiedFreeToConvert copias sin variante identificada disponibles.',
        );
      }

      if (!liveDeck.cards.any((entry) => entryInventoryKey(entry) == key)) {
        throw const InventoryException('La carta ya no está en el mazo.');
      }

      // Recortar en la misma transacción el stock publicado de cada
      // listing cuya reserva se redujo, para que la tienda nunca muestre
      // más copias de las que en realidad quedan libres para vender.
      for (final cut in reservationCuts) {
        final listingRef = _user
            .collection('marketplace_folders')
            .doc(cut.folderId)
            .collection('listings')
            .doc(cut.listingId);
        if (cut.quantity == 0) {
          // Sale de la tienda pública, pero la ficha agotada queda en el
          // catálogo del vendedor para conservar precio y poder editarla.
          tx.update(listingRef, {
            'stock': 0,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          tx.update(listingRef, {
            'stock': cut.quantity,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      tx.set(itemRef, {
        'key': key,
        'cardId': item.cardId ?? card.cardId,
        'name': item.name.isEmpty ? card.name : item.name,
        'edition': item.edition ?? card.edicion,
        'type': item.type ?? card.tipo,
        'total': workingItem.total,
        'allocations': allocations,
        'variantTotals': nextVariantTotals,
        'variantAllocations': nextVariantAllocations,
        'reservations': reservations.map(
          (key, value) => MapEntry(key, value.toMap()),
        ),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      for (final memberSnapshot in memberSnapshots.entries) {
        if (!memberSnapshot.value.exists) continue;
        final member = Deck.fromFirestore(
          memberSnapshot.key,
          memberSnapshot.value.data()!,
        );
        if (deckStockTargetId(member) != stockTargetId) continue;
        final memberCards = applySharedVariantPoolToDeckCards(
          cards: member.cards,
          itemKey: key,
          variants: variants,
        );
        tx.update(memberRefs[memberSnapshot.key]!, {
          'cards': memberCards.map((entry) => entry.toMap()).toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      return item.copyWith(
        total: workingItem.total,
        allocations: allocations,
        variantTotals: nextVariantTotals,
        variantAllocations: nextVariantAllocations,
        reservations: reservations,
      );
    });
  }

  Future<List<FreeStockAssignment>> findFreeStockForActiveDecks() async {
    final inventory = await listInventory();
    final deckSnapshot = await _decks.get();
    final decks =
        deckSnapshot.docs
            .map((doc) => Deck.fromFirestore(doc.id, doc.data()))
            .where(
              (deck) =>
                  deck.isUnified &&
                  deck.assemblyEnabled &&
                  countsTowardCollectionCompleteness(deck),
            )
            .toList();
    return findFreeStockAssignments(inventory: inventory, decks: decks);
  }

  /// Aplica la selección de "Rellenar mazos": por cada carta, reparte la
  /// cantidad elegida a cada mazo destino. La variante física de cada copia
  /// no se corrige contra lo que el mazo pidió (selectedVariants); si un
  /// mazo pidió una variante que no hay libre, igual se le asigna la que
  /// esté disponible — el conteo de copias manda, no el match exacto de
  /// variante (mismo criterio que el armado automático individual).
  Future<void> applyFreeStockSelection(
    Map<String, List<(String deckId, int quantity)>> selection,
  ) async {
    final inventory = {
      for (final item in await listInventory()) item.key: item,
    };
    final deckSnapshot = await _decks.get();
    final decks = {
      for (final doc in deckSnapshot.docs)
        doc.id: Deck.fromFirestore(doc.id, doc.data()),
    };
    for (final entry in selection.entries) {
      InventoryItem? item = inventory[entry.key];
      for (final (deckId, quantity) in entry.value) {
        if (item == null || quantity <= 0) continue;
        final deck = decks[deckId];
        if (deck == null) continue;
        await setAllocation(
          item,
          deck,
          item.allocatedTo(deckStockTargetId(deck)) + quantity,
        );
        // Releer para que la siguiente asignación de la misma carta (a otro
        // mazo) vea el stock libre ya descontado.
        final refreshed = await _inventory.doc(entry.key).get();
        item =
            refreshed.exists
                ? InventoryItem.fromMap(entry.key, refreshed.data()!)
                : null;
      }
    }
    await refreshDynamicWishlist();
  }

  /// Agrega copias nuevas de una carta al inventario (una o varias
  /// variantes a la vez) y las reparte en un solo paso: primero completa
  /// [target] (el mazo que el usuario está viendo) hasta donde alcance, y
  /// con el sobrante intenta completar a los demás mazos activos que la
  /// necesiten. Si el sobrante alcanza para más de un mazo sin poder cubrir
  /// a todos, esos casos quedan en [FillFromHereResult.ambiguous] para que
  /// la UI los resuelva con el mismo selector que "Rellenar mazos" — nunca
  /// se reparte a ciegas entre varios candidatos.
  Future<FillFromHereResult> addCardsHere({
    required Deck target,
    required String cardId,
    required String name,
    String? edition,
    String? type,
    required Map<String, int> quantityByVariant, // '' = sin variante
  }) async {
    final totalAdded = quantityByVariant.values.fold(0, (a, b) => a + b);
    if (totalAdded <= 0) {
      throw const InventoryException('La cantidad debe ser mayor que cero.');
    }
    for (final entry in quantityByVariant.entries) {
      if (entry.value <= 0) continue;
      await addCatalogCard(
        cardId: cardId,
        name: name,
        edition: edition,
        type: type,
        quantity: entry.value,
        variantId: entry.key.isEmpty ? null : entry.key,
      );
    }

    final key = inventoryKey(cardId: cardId, name: name, edition: edition);
    var item = (await listInventory()).where((i) => i.key == key).firstOrNull;
    if (item == null)
      return const FillFromHereResult(addedHere: 0, ambiguous: []);

    // 1) Completar el mazo actual primero, hasta lo que le falte.
    final neededHere = target.cards
        .where((entry) => entryInventoryKey(entry) == key)
        .fold<int>(0, (sum, entry) => sum + entry.count);
    final targetStockId = deckStockTargetId(target);
    final missingHere = neededHere - item.allocatedTo(targetStockId);
    var addedHere = 0;
    if (missingHere > 0 && item.free > 0) {
      addedHere = missingHere.clamp(0, item.free);
      await setAllocation(
        item,
        target,
        item.allocatedTo(targetStockId) + addedHere,
      );
      final refreshed = await _inventory.doc(key).get();
      item =
          refreshed.exists
              ? InventoryItem.fromMap(key, refreshed.data()!)
              : null;
    }
    if (item == null || item.free <= 0) {
      return FillFromHereResult(addedHere: addedHere, ambiguous: const []);
    }

    // 2) Con el sobrante, completar automáticamente a otros mazos activos
    // sin ambigüedad; lo ambiguo se devuelve para que el usuario decida.
    final deckSnapshot = await _decks.get();
    final others =
        deckSnapshot.docs
            .map((doc) => Deck.fromFirestore(doc.id, doc.data()))
            .where(
              (deck) =>
                  deck.isUnified &&
                  deck.assemblyEnabled &&
                  countsTowardCollectionCompleteness(deck) &&
                  deck.id != target.id,
            )
            .toList();
    final assignments = findFreeStockAssignments(
      inventory: [item],
      decks: others,
    );
    final ambiguous = <FreeStockAssignment>[];
    for (final assignment in assignments) {
      if (assignment.isUnambiguous) {
        final candidate = assignment.candidates.single;
        final take = assignment.free.clamp(0, candidate.missing);
        if (take <= 0) continue;
        final deck = others.firstWhere((d) => d.id == candidate.deckId);
        await setAllocation(
          item!,
          deck,
          item.allocatedTo(deckStockTargetId(deck)) + take,
        );
        final refreshed = await _inventory.doc(key).get();
        item =
            refreshed.exists
                ? InventoryItem.fromMap(key, refreshed.data()!)
                : null;
        if (item == null) break;
      } else {
        ambiguous.add(assignment);
      }
    }

    await refreshDynamicWishlist();
    return FillFromHereResult(addedHere: addedHere, ambiguous: ambiguous);
  }

  Future<void> saveDeckProjection(
    Deck deck, {
    Map<String, String?> conflictSelections = const {},
  }) async {
    if (deck.isUnified) {
      await _saveUnifiedDeck(deck, conflictSelections: conflictSelections);
      unawaited(refreshDynamicWishlist().catchError((_) {}));
      return;
    }
    if (deck.isTarget) {
      final map =
          deck.toMap()
            ..remove('createdAt')
            ..['ownerId'] = uid
            ..['updatedAt'] = FieldValue.serverTimestamp()
            ..['initialGoldCardId'] = FieldValue.delete()
            ..['initialGoldName'] = FieldValue.delete()
            ..['initialGoldId'] = FieldValue.delete()
            ..['initialGold'] = FieldValue.delete();
      await _decks.doc(deck.id).set(map, SetOptions(merge: true));
      return;
    }
    final deckRef = _decks.doc(deck.id);
    await db.runTransaction((tx) async {
      final deckSnap = await tx.get(deckRef);
      final oldDeck =
          deckSnap.exists
              ? Deck.fromFirestore(deck.id, deckSnap.data()!)
              : null;
      final oldCounts = _entryCounts(oldDeck?.cards ?? const []);
      final newCounts = _entryCounts(deck.cards);
      final newVariantCounts = _entryVariantCounts(deck.cards);
      final entries = {
        for (final entry in deck.cards) entryInventoryKey(entry): entry,
      };
      final keys = {...oldCounts.keys, ...newCounts.keys};
      final refs = {for (final key in keys) key: _inventory.doc(key)};
      final snaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final ref in refs.entries) {
        snaps[ref.key] = await tx.get(ref.value);
      }
      for (final key in keys) {
        final snap = snaps[key]!;
        if (!snap.exists && (newCounts[key] ?? 0) > 0) {
          throw InventoryException(
            'Agrega ${entries[key]?.name ?? key} a tu inventario antes de incluirla en un mazo.',
          );
        }
        if (!snap.exists) continue;
        final item = InventoryItem.fromMap(key, snap.data()!);
        final allocations = Map<String, int>.from(item.allocations);
        final newQuantity = newCounts[key] ?? 0;
        if (newQuantity == 0)
          allocations.remove(deck.id);
        else
          allocations[deck.id] = newQuantity;
        final updated = item.copyWith(allocations: allocations);
        final variantAllocations = <String, Map<String, int>>{
          for (final variant in item.variantAllocations.entries)
            variant.key: Map<String, int>.from(variant.value)..remove(deck.id),
        };
        for (final variant in (newVariantCounts[key] ?? const {}).entries) {
          variantAllocations.putIfAbsent(
                variant.key,
                () => <String, int>{},
              )[deck.id] =
              variant.value;
        }
        variantAllocations.removeWhere((_, allocation) => allocation.isEmpty);
        final fullyUpdated = updated.copyWith(
          variantAllocations: variantAllocations,
        );
        if (!fullyUpdated.isValid) {
          final requestedMore = newQuantity - (oldCounts[key] ?? 0);
          throw InventoryException(
            'Faltan ${requestedMore.clamp(1, 999)} copias libres de ${item.name}.',
          );
        }
        tx.update(refs[key]!, {
          'allocations': allocations,
          'variantAllocations': variantAllocations,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      final map =
          deck.toMap()
            ..remove('createdAt')
            ..['ownerId'] = uid
            ..['updatedAt'] = FieldValue.serverTimestamp()
            ..['initialGoldCardId'] = FieldValue.delete()
            ..['initialGoldName'] = FieldValue.delete()
            ..['initialGoldId'] = FieldValue.delete()
            ..['initialGold'] = FieldValue.delete();
      tx.set(deckRef, map, SetOptions(merge: true));
    });
  }

  Future<void> _saveUnifiedDeck(
    Deck deck, {
    bool writeConfiguration = true,
    Map<String, String?> conflictSelections = const {},
  }) async {
    final deckRef = _decks.doc(deck.id);
    final configurationMap =
        writeConfiguration
            ? (deck.toMap()
              ..remove('createdAt')
              ..['ownerId'] = uid
              ..['schemaVersion'] = 2
              ..['updatedAt'] = FieldValue.serverTimestamp()
              ..['initialGoldCardId'] = FieldValue.delete()
              ..['initialGoldName'] = FieldValue.delete()
              ..['initialGoldId'] = FieldValue.delete()
              ..['initialGold'] = FieldValue.delete()
              ..['status'] = FieldValue.delete()
              ..['objectiveCards'] = FieldValue.delete()
              ..['linkedDeckId'] = FieldValue.delete())
            : null;
    if (!countsTowardCollectionCompleteness(deck)) {
      await _saveOptionalUnifiedDeck(
        deck,
        deckRef: deckRef,
        configurationMap: configurationMap,
      );
      return;
    }
    try {
      final allDeckSnapshot = await _decks.get();
      final storedDecks =
          allDeckSnapshot.docs
              .map((doc) => Deck.fromFirestore(doc.id, doc.data()))
              .toList();
      final previous =
          storedDecks.where((stored) => stored.id == deck.id).firstOrNull;
      final keys = _changedEntryKeys(previous, deck);
      final activeDecks = [
        for (final stored in storedDecks.where(
          (stored) =>
              stored.id != deck.id &&
              countsTowardCollectionCompleteness(stored),
        ))
          _onlyCards(stored, keys),
        _onlyCards(deck, keys),
      ];
      final completionDemandKeys = {
        for (final active in activeDecks.where(
          (candidate) => candidate.assemblyEnabled,
        ))
          for (final card in active.cards) entryInventoryKey(card),
      };
      final optionalTargetIds = {
        for (final stored in storedDecks.where(
          (candidate) => !countsTowardCollectionCompleteness(candidate),
        ))
          deckStockTargetId(stored),
      };
      if (keys.isEmpty) {
        if (configurationMap != null) {
          await deckRef.set(configurationMap, SetOptions(merge: true));
        }
        return;
      }
      await db.runTransaction((tx) async {
        final refs = {for (final key in keys) key: _inventory.doc(key)};
        final fetched = await Future.wait([
          for (final entry in refs.entries)
            tx
                .get(entry.value)
                .then((snapshot) => MapEntry(entry.key, snapshot)),
        ]);
        final snapshots = <String, DocumentSnapshot<Map<String, dynamic>>>{
          for (final entry in fetched) entry.key: entry.value,
        };
        final liveInventory = <InventoryItem>[
          for (final entry in snapshots.entries)
            if (entry.value.exists)
              InventoryItem.fromMap(entry.key, entry.value.data()!),
        ];
        final proposal = buildDeckReconciliation(
          inventory: liveInventory,
          decks: activeDecks,
        );
        if (configurationMap != null) {
          tx.set(deckRef, configurationMap, SetOptions(merge: true));
        }
        for (final item in liveInventory) {
          final finalAllocations = Map<String, int>.from(
            proposal.automaticAllocations[item.key] ?? const {},
          );
          if (!completionDemandKeys.contains(item.key)) {
            for (final allocation in item.allocations.entries) {
              if (optionalTargetIds.contains(allocation.key) &&
                  allocation.value > 0) {
                finalAllocations[allocation.key] = allocation.value;
              }
            }
          }
          final conflict =
              proposal.conflicts
                  .where((candidate) => candidate.itemKey == item.key)
                  .firstOrNull;
          final chosenDeckId = conflictSelections[item.key];
          if (conflict != null &&
              chosenDeckId != null &&
              conflict.requestedByDeck.containsKey(chosenDeckId)) {
            final take = conflict.requestedByDeck[chosenDeckId]!.clamp(
              0,
              conflict.available,
            );
            finalAllocations[chosenDeckId] =
                (finalAllocations[chosenDeckId] ?? 0) + take;
          }
          final variantAllocations = _variantsForAllocations(
            item: item,
            allocations: finalAllocations,
          );
          tx.update(refs[item.key]!, {
            'allocations': finalAllocations,
            'variantAllocations': variantAllocations,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } catch (_) {
      rethrow;
    }
  }

  /// Full y Racial Libre guardan su configuración sin reclamar stock nuevo.
  /// Solo conservan asignaciones que el usuario ya hizo explícitamente y las
  /// recortan si redujo la cantidad o pausó el mazo.
  Future<void> _saveOptionalUnifiedDeck(
    Deck deck, {
    required DocumentReference<Map<String, dynamic>> deckRef,
    required Map<String, dynamic>? configurationMap,
  }) async {
    final previousSnapshot = await deckRef.get();
    final previous =
        previousSnapshot.exists
            ? Deck.fromFirestore(deck.id, previousSnapshot.data()!)
            : null;
    final keys = {
      ..._entryCounts(previous?.cards ?? const []).keys,
      ..._entryCounts(deck.cards).keys,
    };
    if (keys.isEmpty) {
      if (configurationMap != null) {
        await deckRef.set(configurationMap, SetOptions(merge: true));
      }
      return;
    }
    final requested = _entryCounts(deck.cards);
    final targetId = deckStockTargetId(deck);
    await db.runTransaction((tx) async {
      final refs = {for (final key in keys) key: _inventory.doc(key)};
      final snapshots = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final entry in refs.entries) {
        snapshots[entry.key] = await tx.get(entry.value);
      }
      if (configurationMap != null) {
        tx.set(deckRef, configurationMap, SetOptions(merge: true));
      }
      for (final entry in snapshots.entries) {
        if (!entry.value.exists) continue;
        final item = InventoryItem.fromMap(entry.key, entry.value.data()!);
        final allocations = Map<String, int>.from(item.allocations);
        final keep =
            deck.assemblyEnabled
                ? item.allocatedTo(targetId).clamp(0, requested[entry.key] ?? 0)
                : 0;
        if (keep == 0) {
          allocations.remove(targetId);
        } else {
          allocations[targetId] = keep;
        }
        tx.update(refs[entry.key]!, {
          'allocations': allocations,
          'variantAllocations': _variantsForAllocations(
            item: item,
            allocations: allocations,
          ),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  Map<String, Map<String, int>> _variantsForAllocations({
    required InventoryItem item,
    required Map<String, int> allocations,
  }) {
    final result = <String, Map<String, int>>{};
    final remainingVariant = <String, int>{
      for (final entry in item.variantTotals.entries)
        entry.key: () {
          final safeVariantTotal = entry.value < 0 ? 0 : entry.value;
          return (safeVariantTotal - item.variantReserved(entry.key)).clamp(
            0,
            safeVariantTotal,
          );
        }(),
    };
    // `unidentified` puede ser negativo en datos legacy si variantTotals
    // quedó duplicado. Para repartir asignaciones representa un pool vacío,
    // no un límite negativo para num.clamp().
    var unidentifiedLeft = item.unidentified < 0 ? 0 : item.unidentified;
    for (final allocation in allocations.entries) {
      var remaining = allocation.value < 0 ? 0 : allocation.value;
      for (final variant in item.variantAllocations.entries) {
        if (remaining == 0) break;
        final wanted = variant.value[allocation.key] ?? 0;
        final keep = wanted
            .clamp(0, remainingVariant[variant.key] ?? 0)
            .clamp(0, remaining);
        if (keep <= 0) continue;
        result.putIfAbsent(variant.key, () => <String, int>{})[allocation.key] =
            keep;
        remainingVariant[variant.key] =
            (remainingVariant[variant.key] ?? 0) - keep;
        remaining -= keep;
      }
      final unidentified = remaining.clamp(0, unidentifiedLeft);
      unidentifiedLeft -= unidentified;
      remaining -= unidentified;
      for (final variantId in remainingVariant.keys.toList()..sort()) {
        if (remaining == 0) break;
        final take = (remainingVariant[variantId] ?? 0).clamp(0, remaining);
        if (take <= 0) continue;
        result.putIfAbsent(variantId, () => <String, int>{})[allocation.key] =
            (result[variantId]?[allocation.key] ?? 0) + take;
        remainingVariant[variantId] = (remainingVariant[variantId] ?? 0) - take;
        remaining -= take;
      }
    }
    return result;
  }

  Future<void> deleteDeck(Deck deck) async {
    if (deck.isTarget) {
      await _decks.doc(deck.id).delete();
      return;
    }
    final counts = _entryCounts(deck.cards);
    final refs = {for (final key in counts.keys) key: _inventory.doc(key)};
    final remainingDecks =
        (await _decks.get()).docs
            .where((doc) => doc.id != deck.id)
            .map((doc) => Deck.fromFirestore(doc.id, doc.data()))
            .toList();
    final completionDecks =
        remainingDecks.where(countsTowardCollectionCompleteness).toList();
    final completionDemandKeys = {
      for (final remaining in completionDecks.where(
        (candidate) => candidate.assemblyEnabled,
      ))
        for (final card in remaining.cards) entryInventoryKey(card),
    };
    final optionalTargetIds = {
      for (final remaining in remainingDecks.where(
        (candidate) => !countsTowardCollectionCompleteness(candidate),
      ))
        deckStockTargetId(remaining),
    };
    await db.runTransaction((tx) async {
      final snaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final ref in refs.entries) {
        snaps[ref.key] = await tx.get(ref.value);
      }
      final liveInventory = [
        for (final entry in snaps.entries)
          if (entry.value.exists)
            InventoryItem.fromMap(entry.key, entry.value.data()!),
      ];
      final proposal = buildDeckReconciliation(
        inventory: liveInventory,
        decks: completionDecks,
      );
      for (final item in liveInventory) {
        final allocations = Map<String, int>.from(
          proposal.automaticAllocations[item.key] ?? const {},
        );
        if (!completionDemandKeys.contains(item.key)) {
          for (final allocation in item.allocations.entries) {
            if (optionalTargetIds.contains(allocation.key) &&
                allocation.value > 0) {
              allocations[allocation.key] = allocation.value;
            }
          }
        }
        final variantAllocations = _variantsForAllocations(
          item: item,
          allocations: allocations,
        );
        tx.update(refs[item.key]!, {
          'allocations': allocations,
          'variantAllocations': variantAllocations,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      tx.delete(_decks.doc(deck.id));
    });
    if (deck.isUnified) {
      await refreshDynamicWishlist();
    }
  }

  Map<String, int> _entryCounts(List<DeckCardEntry> cards) {
    final result = <String, int>{};
    for (final entry in cards) {
      final key = entryInventoryKey(entry);
      result[key] = (result[key] ?? 0) + entry.count;
    }
    return result;
  }

  Map<String, Map<String, int>> _entryVariantCounts(List<DeckCardEntry> cards) {
    final result = <String, Map<String, int>>{};
    for (final entry in cards) {
      final key = entryInventoryKey(entry);
      final variants = result.putIfAbsent(key, () => <String, int>{});
      for (final variantId in entry.selectedVariants ?? const <String>[]) {
        if (variantId.isNotEmpty) {
          variants[variantId] = (variants[variantId] ?? 0) + 1;
        }
      }
    }
    return result;
  }

  Future<void> addCatalogCard({
    required String cardId,
    required String name,
    String? edition,
    String? type,
    int quantity = 1,
    String? variantId,
  }) async {
    if (quantity <= 0)
      throw const InventoryException('La cantidad debe ser mayor que cero.');
    final key = inventoryKey(cardId: cardId, name: name, edition: edition);
    await db.runTransaction((tx) async {
      final ref = _inventory.doc(key);
      final snap = await tx.get(ref);
      final current =
          snap.exists ? InventoryItem.fromMap(ref.id, snap.data()!) : null;
      final variants = Map<String, int>.from(
        current?.variantTotals ?? const {},
      );
      final selectedVariant = variantId?.trim() ?? '';
      if (selectedVariant.isNotEmpty) {
        variants[selectedVariant] = (variants[selectedVariant] ?? 0) + quantity;
      }
      final item = InventoryItem(
        key: key,
        cardId: cardId,
        name: name,
        edition: edition,
        type: type,
        total: (current?.total ?? 0) + quantity,
        allocations: current?.allocations ?? const {},
        variantTotals: variants,
        variantAllocations: current?.variantAllocations ?? const {},
        reservations: current?.reservations ?? const {},
      );
      tx.set(ref, {...item.toMap(), 'updatedAt': FieldValue.serverTimestamp()});
    });
    await refreshDynamicWishlist();
  }

  /// Declara la variante de copias que YA existen en el inventario y están
  /// "sin identificar" pero libres (no asignadas a ningún mazo ni
  /// reservadas en venta) — a diferencia de [addCatalogCard], no agrega
  /// copias nuevas ni cambia el total, solo mueve de "sin identificar" a
  /// una variante concreta. Para copias sin identificar que sí están en un
  /// mazo, se declaran con [setDeckCopyVariants].
  Future<void> identifyFreeCopies(
    InventoryItem item,
    Map<String, int> quantityByVariant,
  ) async {
    final requested = quantityByVariant.values.fold<int>(0, (a, b) => a + b);
    if (requested <= 0) return;
    final itemRef = _inventory.doc(item.key);
    await db.runTransaction((tx) async {
      final snap = await tx.get(itemRef);
      if (!snap.exists) {
        throw const InventoryException('La carta ya no existe.');
      }
      final live = InventoryItem.fromMap(itemRef.id, snap.data()!);
      if (requested > live.unidentifiedFree) {
        throw InventoryException(
          'Solo hay ${live.unidentifiedFree} copias sin identificar libres.',
        );
      }
      final variantTotals = Map<String, int>.from(live.variantTotals);
      for (final entry in quantityByVariant.entries) {
        if (entry.value <= 0) continue;
        variantTotals[entry.key] =
            (variantTotals[entry.key] ?? 0) + entry.value;
      }
      final updated = live.copyWith(variantTotals: variantTotals);
      if (!updated.isValid) {
        throw const InventoryException(
          'Esa combinación de variantes no es válida para esta carta.',
        );
      }
      tx.update(itemRef, {
        'variantTotals': variantTotals,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> refreshDynamicWishlist() async {
    final deckSnapshot = await _decks.get();
    final decks =
        deckSnapshot.docs
            .map((doc) => Deck.fromFirestore(doc.id, doc.data()))
            .toList();
    await WishlistService(
      uid,
    ).recalculateDeckShortages(decks: decks, inventory: await listInventory());
  }

  Future<String> createPlan({
    required String name,
    required List<Deck> orderedTargets,
    required Map<String, String> destinationByTarget,
    required List<InventoryItem> inventory,
  }) async {
    final storedDecks =
        (await _decks.get()).docs
            .map((doc) => Deck.fromFirestore(doc.id, doc.data()))
            .toList();
    final byId = {for (final deck in storedDecks) deck.id: deck};
    final physicalDestinations = <String, String>{
      for (final entry in destinationByTarget.entries)
        entry.key:
            byId[entry.value] == null
                ? entry.value
                : deckStockTargetId(byId[entry.value]!),
    };
    final calculated = buildInventoryPlan(
      inventory: inventory,
      orderedTargets: orderedTargets,
      destinationByTarget: physicalDestinations,
      releaseUnselectedDecks: orderedTargets.every((deck) => deck.isUnified),
    );
    final ref = _plans.doc();
    final now = DateTime.now();
    final involvedKeys = <String>{
      for (final target in orderedTargets)
        for (final entry in target.cards) entryInventoryKey(entry),
      ...calculated.moves.map((move) => move.cardKey),
    };
    final plan = TransferPlan(
      id: ref.id,
      name: name,
      targetDeckIds: orderedTargets.map((deck) => deck.id).toList(),
      destinationDeckIds: physicalDestinations,
      initialAllocations: {
        for (final item in inventory.where(
          (item) => involvedKeys.contains(item.key),
        ))
          item.key: Map<String, int>.from(item.allocations),
      },
      moves: calculated.moves,
      shortages: calculated.shortages,
      status: TransferPlanStatus.active,
      createdAt: now,
      updatedAt: now,
    );
    await ref.set(plan.toMap());
    return ref.id;
  }

  /// Qué le falta a [target] carta por carta, y de qué otros mazos se podría
  /// sacar cada una (ver [findMissingCardsWithSources]). No decide nada: es
  /// para mostrarle al usuario las opciones antes de generar el plan.
  Future<List<MissingCardWithSources>> findMissingCardsForDeck(
    Deck target,
    Map<String, String> deckNames,
  ) async {
    final inventory = await listInventory();
    return findMissingCardsWithSources(
      inventory: inventory,
      target: target,
      deckNames: deckNames,
    );
  }

  /// Plan para terminar de armar un único mazo, a partir de lo que el
  /// usuario eligió explícitamente en pantalla (qué tomar del stock libre y
  /// de qué mazos sacar el resto). Devuelve null si no hay nada que mover.
  Future<String?> createSingleDeckPlanFromSelection({
    required Deck target,
    required List<MissingCardWithSources> missing,
    required Map<String, int> freeAmountByCard,
    required Map<String, List<(String deckId, int quantity)>> sourcesByCard,
  }) async {
    final calculated = buildSingleDeckPlanFromSelection(
      target: target,
      missing: missing,
      freeAmountByCard: freeAmountByCard,
      sourcesByCard: sourcesByCard,
    );
    if (calculated.moves.isEmpty) return null;

    final inventory = await listInventory();
    final ref = _plans.doc();
    final now = DateTime.now();
    final involvedKeys = <String>{
      for (final entry in target.cards) entryInventoryKey(entry),
      ...calculated.moves.map((move) => move.cardKey),
    };
    final plan = TransferPlan(
      id: ref.id,
      name: 'Armar ${target.name}',
      targetDeckIds: [target.id],
      destinationDeckIds: {target.id: deckStockTargetId(target)},
      initialAllocations: {
        for (final item in inventory.where(
          (item) => involvedKeys.contains(item.key),
        ))
          item.key: Map<String, int>.from(item.allocations),
      },
      moves: calculated.moves,
      shortages: calculated.shortages,
      status: TransferPlanStatus.active,
      createdAt: now,
      updatedAt: now,
    );
    await ref.set(plan.toMap());
    return ref.id;
  }

  Future<void> applyMove(TransferPlan plan, TransferMove move) =>
      _move(plan, move, reverse: false);
  Future<void> returnMove(TransferPlan plan, TransferMove move) =>
      _move(plan, move, reverse: true);

  Future<void> _move(
    TransferPlan plan,
    TransferMove move, {
    required bool reverse,
  }) async {
    final from = reverse ? move.toDeckId : move.fromDeckId;
    final to = reverse ? move.fromDeckId : move.toDeckId;
    final itemRef = _inventory.doc(move.cardKey);
    final planRef = _plans.doc(plan.id);
    final deckSnapshot = await _decks.get();
    final allDecks =
        deckSnapshot.docs
            .map((doc) => Deck.fromFirestore(doc.id, doc.data()))
            .toList();
    final targets = deckStockTargetsById(allDecks);

    Deck? representativeFor(String id) {
      final target = targets[id];
      if (target != null) return target.members.first;
      return allDecks.where((deck) => deck.id == id).firstOrNull;
    }

    Deck? projectionFor(String id) {
      final target = targets[id];
      if (target != null) return target.asDeck();
      return allDecks.where((deck) => deck.id == id).firstOrNull;
    }

    final deckRefs = <String, DocumentReference<Map<String, dynamic>>>{
      if (from != null && representativeFor(from) != null)
        from: _decks.doc(representativeFor(from)!.id),
      if (to != null && representativeFor(to) != null)
        to: _decks.doc(representativeFor(to)!.id),
    };

    await db.runTransaction((tx) async {
      final itemSnap = await tx.get(itemRef);
      final planSnap = await tx.get(planRef);
      if (!itemSnap.exists || !planSnap.exists)
        throw const InventoryException('El plan o la carta ya no existe.');
      final deckSnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final entry in deckRefs.entries) {
        deckSnaps[entry.key] = await tx.get(entry.value);
      }
      final livePlan = TransferPlan.fromMap(planRef.id, planSnap.data()!);
      final index = livePlan.moves.indexWhere(
        (candidate) => candidate.id == move.id,
      );
      if (index < 0)
        throw const InventoryException(
          'El movimiento ya no pertenece al plan.',
        );
      final expected =
          reverse ? TransferMoveStatus.applied : TransferMoveStatus.pending;
      if (livePlan.moves[index].status != expected)
        throw const InventoryException(
          'Este movimiento cambió de estado. Actualiza el plan.',
        );
      if (!reverse &&
          livePlan.moves
              .take(index)
              .any(
                (candidate) => candidate.status == TransferMoveStatus.pending,
              )) {
        throw const InventoryException(
          'Completa primero los movimientos anteriores.',
        );
      }
      if (reverse &&
          livePlan.moves
              .skip(index + 1)
              .any(
                (candidate) => candidate.status == TransferMoveStatus.applied,
              )) {
        throw const InventoryException(
          'Devuelve primero los movimientos posteriores.',
        );
      }

      final item = InventoryItem.fromMap(itemRef.id, itemSnap.data()!);
      final allocations = Map<String, int>.from(item.allocations);
      if (!reverse && to != null) {
        final destination = projectionFor(to);
        if (destination == null) {
          throw const InventoryException(
            'El destino del movimiento ya no existe.',
          );
        }
        if (destination.isUnified) {
          final required = _entryCounts(destination.cards)[item.key] ?? 0;
          if (!destination.assemblyEnabled ||
              (allocations[to] ?? 0) + move.quantity > required) {
            throw InventoryException(
              'El mazo destino cambió. Recalcula los movimientos pendientes.',
            );
          }
        }
      }
      final sourceAvailable =
          from == null ? item.free : (allocations[from] ?? 0);
      if (sourceAvailable < move.quantity)
        throw InventoryException(
          'Ya no hay ${move.quantity} copias disponibles de ${move.cardName} en el origen.',
        );
      if (from != null) {
        final next = (allocations[from] ?? 0) - move.quantity;
        if (next == 0)
          allocations.remove(from);
        else
          allocations[from] = next;
      }
      if (to != null) allocations[to] = (allocations[to] ?? 0) + move.quantity;

      final variantAllocations = <String, Map<String, int>>{
        for (final variant in item.variantAllocations.entries)
          variant.key: Map<String, int>.from(variant.value),
      };
      var variantRemainder = move.quantity;
      if (from != null) {
        for (final byVariant in variantAllocations.entries) {
          final atSource = byVariant.value[from] ?? 0;
          final moved = atSource.clamp(0, variantRemainder);
          if (moved == 0) continue;
          final sourceNext = atSource - moved;
          if (sourceNext == 0) {
            byVariant.value.remove(from);
          } else {
            byVariant.value[from] = sourceNext;
          }
          if (to != null) {
            byVariant.value[to] = (byVariant.value[to] ?? 0) + moved;
          }
          variantRemainder -= moved;
          if (variantRemainder == 0) break;
        }
      } else if (to != null) {
        final candidates = <String>{
          ...move.variantIds,
          ...item.variantTotals.keys,
        };
        for (final variantId in candidates) {
          final available = item.variantFree(variantId);
          final moved = available.clamp(0, variantRemainder);
          if (moved == 0) continue;
          final byDeck = variantAllocations.putIfAbsent(
            variantId,
            () => <String, int>{},
          );
          byDeck[to] = (byDeck[to] ?? 0) + moved;
          variantRemainder -= moved;
          if (variantRemainder == 0) break;
        }
      }
      variantAllocations.removeWhere((_, byDeck) => byDeck.isEmpty);
      final updatedItem = item.copyWith(
        allocations: allocations,
        variantAllocations: variantAllocations,
      );
      if (!updatedItem.isValid) {
        throw const InventoryException(
          'El movimiento ya no es compatible con las variantes disponibles.',
        );
      }

      final updatedMoves = [...livePlan.moves];
      updatedMoves[index] = updatedMoves[index].copyWith(
        status:
            reverse ? TransferMoveStatus.returned : TransferMoveStatus.applied,
      );
      final allApplied = updatedMoves.every(
        (candidate) => candidate.status == TransferMoveStatus.applied,
      );
      final allReturned = updatedMoves.every(
        (candidate) =>
            candidate.status == TransferMoveStatus.returned ||
            candidate.status == TransferMoveStatus.pending,
      );
      final nextStatus =
          reverse && allReturned
              ? TransferPlanStatus.returned
              : (!reverse && allApplied
                  ? TransferPlanStatus.readyToReturn
                  : TransferPlanStatus.active);

      tx.update(itemRef, {
        'allocations': allocations,
        'variantAllocations': variantAllocations,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      for (final deckEntry in deckSnaps.entries) {
        if (!deckEntry.value.exists)
          throw InventoryException('El mazo ${deckEntry.key} ya no existe.');
        final deck = representativeFor(deckEntry.key)!;
        final delta = deckEntry.key == to ? move.quantity : -move.quantity;
        tx.update(deckRefs[deckEntry.key]!, {
          if (!deck.isUnified)
            'cards':
                _cardsWithDelta(
                  deck.cards,
                  item,
                  delta,
                ).map((e) => e.toMap()).toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      tx.update(planRef, {
        'moves': updatedMoves.map((m) => m.toMap()).toList(),
        'status': nextStatus.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  List<DeckCardEntry> _cardsWithDelta(
    List<DeckCardEntry> cards,
    InventoryItem item,
    int delta,
  ) {
    final result = [...cards];
    final index = result.indexWhere(
      (entry) => entryInventoryKey(entry) == item.key,
    );
    final old = index < 0 ? 0 : result[index].count;
    final next = old + delta;
    if (next < 0)
      throw InventoryException(
        'La proyección del mazo no tiene suficientes copias de ${item.name}.',
      );
    if (index >= 0 && next == 0)
      result.removeAt(index);
    else if (index >= 0)
      result[index] = result[index].copyWith(count: next);
    else if (next > 0)
      result.add(
        DeckCardEntry(
          cardId: item.cardId,
          name: item.name,
          count: next,
          edicion: item.edition,
          tipo: item.type,
        ),
      );
    return result;
  }

  Future<void> keepPlan(String planId) => _plans.doc(planId).update({
    'status': TransferPlanStatus.kept.name,
    'updatedAt': FieldValue.serverTimestamp(),
  });
  Future<void> cancelUnusedPlan(String planId) => _plans.doc(planId).update({
    'status': TransferPlanStatus.cancelled.name,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<String> createDestinationForTarget(Deck target) async {
    final ref = _decks.doc();
    final now = DateTime.now();
    final deck = Deck(
      id: ref.id,
      ownerId: uid,
      name: target.name,
      race: target.race,
      edition: target.edition,
      format: target.format,
      linkedDeckId: target.id,
      createdAt: now,
      updatedAt: now,
    );
    await ref.set(deck.toMap());
    return ref.id;
  }
}
