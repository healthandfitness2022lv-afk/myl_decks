import 'package:flutter/foundation.dart';
import '../../models/deck.dart';

@immutable
class CardData {
  final String id;
  final String name;
  final String type;      // "Aliado", "Oro", "Talismán", "Tótem", "Arma", etc.
  final String? race;     // solo para Aliados
  final String? edition;  // edición/bloque

  const CardData({
    required this.id,
    required this.name,
    required this.type,
    this.race,
    this.edition,
  });
}

@immutable
class ValidationIssue {
  final String code;   // "TOTAL_NOT_50", "COPIES_LIMIT", "RACE_MISMATCH", "EDITION_MISMATCH", "INITIAL_GOLD_MISSING", "INITIAL_GOLD_NOT_IN_DECK", "INITIAL_GOLD_NOT_GOLD"
  final String message;
  const ValidationIssue(this.code, this.message);
}

@immutable
class ValidationResult {
  final bool okForDraft;    // permite guardar borrador
  final bool okForPublish;  // permite publicar
  final List<ValidationIssue> issues;
  const ValidationResult({
    required this.okForDraft,
    required this.okForPublish,
    required this.issues,
  });
}

// -------------------------------------
// Helpers internos del validador
// -------------------------------------
bool _isGoldType(String? raw) {
  if (raw == null) return false;
  final t = raw.trim().toLowerCase();
  return t == 'oro' || t == 'oros';
}

String _keyFor(DeckCardEntry e) => (e.cardId ?? e.name).toLowerCase();

/// Reglas:
/// - Draft: permite casi todo, excepto exceder 3 copias por carta.
/// - Publish: exige 50 cartas exactas, 1 Oro inicial válido y cero issues (racial/edición/copias).
ValidationResult validateDeck({
  required Deck deck,
  required Map<String, dynamic> catalogById,
  required Map<String, dynamic> catalogByName,
}) {
  final issues = <ValidationIssue>[];

  // Total de cartas
  final total = deck.cards.fold<int>(0, (s, e) => s + e.count);

  // ----- Oro inicial: debe existir -----
  final hasInitial = (deck.initialGoldCardId != null && deck.initialGoldCardId!.isNotEmpty) ||
                     (deck.initialGoldName != null && deck.initialGoldName!.trim().isNotEmpty);

  if (!hasInitial) {
    issues.add(const ValidationIssue(
      "INITIAL_GOLD_MISSING",
      "Debes seleccionar un Oro inicial.",
    ));
  } else {
    // Resolver entrada de carta que corresponde al oro inicial
    DeckCardEntry? initialEntry;
    if ((deck.initialGoldCardId ?? '').isNotEmpty) {
      initialEntry = deck.cards.firstWhere(
        (e) => (e.cardId ?? '').isNotEmpty && e.cardId == deck.initialGoldCardId,
        orElse: () => const DeckCardEntry(name: '', count: 0),
      );
    } else {
      final target = deck.initialGoldName!.trim().toLowerCase();
      initialEntry = deck.cards.firstWhere(
        (e) => e.name.trim().toLowerCase() == target,
        orElse: () => const DeckCardEntry(name: '', count: 0),
      );
    }

    // Debe estar en el mazo
    if (initialEntry.name.isEmpty) {
      issues.add(const ValidationIssue(
        "INITIAL_GOLD_NOT_IN_DECK",
        "El Oro inicial debe estar incluido en el mazo.",
      ));
    } else {
      // Debe ser de tipo "Oro" (por e.tipo o por catálogo)
      bool isGold = _isGoldType(initialEntry.tipo);
      if (!isGold) {
        // intentar por catálogo (id o nombre)
        final byId = (initialEntry.cardId != null) ? catalogById[initialEntry.cardId!] : null;
        final byName = catalogByName[initialEntry.name];

        final CardData? card = (byId is CardData)
            ? byId
            : (byName is CardData)
                ? byName
                : null;

        if (card != null) {
          isGold = _isGoldType(card.type);
        }
      }

      if (!isGold) {
        issues.add(const ValidationIssue(
          "INITIAL_GOLD_NOT_GOLD",
          "El Oro inicial seleccionado no es de tipo “Oro”.",
        ));
      }
    }
  }

  // Límite de 3 copias por carta (sobre la suma agregada)
  final copyCounter = <String, int>{}; // clave: (cardId??name).toLowerCase()
  for (final e in deck.cards) {
    final key = _keyFor(e);
    copyCounter[key] = (copyCounter[key] ?? 0) + e.count;
  }
  copyCounter.forEach((_, c) {
    if (c > 3) {
      issues.add(const ValidationIssue(
        "COPIES_LIMIT",
        "No puedes tener más de 3 copias de una misma carta.",
      ));
    }
  });

  // Reglas raciales/edición (observaciones en draft; bloquean publish)
  if (deck.isRacial) {
    for (final e in deck.cards) {
      final card = (e.cardId != null)
          ? catalogById[e.cardId!]
          : catalogByName[e.name];

      // Si la carta no está en catálogo, lo permitimos (podría ser temporal en draft)
      if (card == null) continue;

      if (card is CardData) {
        if (card.type == "Aliado") {
          if (deck.race != null && card.race != deck.race) {
            issues.add(ValidationIssue(
              "RACE_MISMATCH",
              "Aliado '${card.name}' no es de raza ${deck.race}.",
            ));
          }
        }

        if (["Oro", "Talismán", "Tótem", "Arma"].contains(card.type)) {
          if (deck.edition != null && card.edition != deck.edition) {
            issues.add(ValidationIssue(
              "EDITION_MISMATCH",
              "'${card.name}' no pertenece a la edición ${deck.edition}.",
            ));
          }
        }
      }
    }
  }

  // Exigir 50 cartas para publicar (lo mostramos como observación en draft)
  if (total != 50) {
    issues.add(ValidationIssue(
      "TOTAL_NOT_50",
      "El mazo tiene $total cartas (debe tener 50 para publicar).",
    ));
  }

  // Cálculo de flags finales
  final hasCopiesError = issues.any((i) => i.code == "COPIES_LIMIT");
  final okForDraft = !hasCopiesError;      // draft solo bloquea si hay exceso de copias
  final okForPublish = issues.isEmpty;     // publish requiere cero issues (incluye total=50 y oro inicial válido)

  return ValidationResult(
    okForDraft: okForDraft,
    okForPublish: okForPublish,
    issues: issues,
  );
}

/// Opcional: fijar edición automáticamente por raza
String? getEditionForRace(String race) {
  const mapRaceEdition = {
    "Eterno": "Dominios de Ra",
    "Guerrero": "Encrucijada",
    // agrega las tuyas…
  };
  return mapRaceEdition[race];
}
