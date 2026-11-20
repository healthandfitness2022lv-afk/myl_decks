import 'package:flutter/foundation.dart';

import '../../models/deck.dart';
import '../../models/ban_list_entry.dart';
import '../../models/card_myl.dart';
import 'mercenarios.dart';

export 'mercenarios.dart';

@immutable
class CardData {
  final String id;
  final String name;
  final String type;
  final String? race;
  final String? edition;
  final bool soloLibre;

  const CardData({
    required this.id,
    required this.name,
    required this.type,
    this.race,
    this.edition,
    this.soloLibre = false,
  });
}

@immutable
class ValidationIssue {
  final String code;
  final String message;

  const ValidationIssue(this.code, this.message);
}

@immutable
class ValidationResult {
  final bool okForDraft;
  final bool okForPublish;
  final List<ValidationIssue> issues;

  const ValidationResult({
    required this.okForDraft,
    required this.okForPublish,
    required this.issues,
  });
}

CardData? _cardDataFrom(dynamic card) {
  if (card is CardData) return card;
  if (card is CardMyL) {
    return CardData(
      id: card.id,
      name: card.nombre,
      type: card.tipo,
      race: card.raza,
      edition: card.edicion,
      soloLibre: card.soloLibre,
    );
  }
  return null;
}

String _keyFor(DeckCardEntry e) {
  final name = e.name.trim();
  return normalizeBanListKey(name.isNotEmpty ? name : (e.cardId ?? ''));
}

/// Carta Mercenario («Puedes tener más de 3 Draco Águila en tu Mazo
/// Castillo»): por el texto de la carta del catálogo o, si la pantalla no
/// trae el catálogo, por haberla visto antes (ver `mercenarios.dart`).
bool cartaEsMercenario(dynamic card, {String? id, String nombre = ''}) =>
    (card is CardMyL &&
        textoEsMercenario('${card.habilidadTextoIA} ${card.habilidad}')) ||
    esMercenario(id: id, nombre: nombre);

int _copyLimitForEntry(
  DeckCardEntry entry,
  Map<String, int> copyLimitsByKey, {
  bool sinLimite = false,
}) {
  final cardId = entry.cardId?.trim();
  if (cardId != null && cardId.isNotEmpty) {
    final fromId = copyLimitsByKey[normalizeBanListKey(cardId)];
    if (fromId != null) {
      return entry.unica ? fromId.clamp(0, 1) : fromId;
    }
  }

  final name = entry.name.trim();
  if (name.isNotEmpty) {
    final fromName = copyLimitsByKey[normalizeBanListKey(name)];
    if (fromName != null) {
      return entry.unica ? fromName.clamp(0, 1) : fromName;
    }
  }

  if (entry.unica) return 1;
  return sinLimite ? copiasMercenario : copiasNormales;
}

ValidationResult validateDeck({
  required Deck deck,
  required Map<String, dynamic> catalogById,
  required Map<String, dynamic> catalogByName,
  Map<String, int> copyLimitsByKey = const {},
}) {
  final issues = <ValidationIssue>[];
  final total = deck.cards.fold<int>(0, (sum, entry) => sum + entry.count);
  final sideboardTotal = deck.sideboardCards.fold<int>(
    0,
    (sum, entry) => sum + entry.count,
  );
  final configuredCards = [...deck.cards, ...deck.sideboardCards];

  final copyCounter = <String, int>{};
  final sideCounter = <String, int>{};
  final labelByKey = <String, String>{};
  final limitByKey = <String, int>{};
  for (final entry in configuredCards) {
    final key = _keyFor(entry);
    copyCounter[key] = (copyCounter[key] ?? 0) + entry.count;
    labelByKey[key] = entry.name;
    final enCatalogo =
        entry.cardId != null
            ? catalogById[entry.cardId!]
            : catalogByName[entry.name] ??
                catalogByName[entry.name.trim().toLowerCase()];
    limitByKey[key] = _copyLimitForEntry(
      entry,
      copyLimitsByKey,
      sinLimite: cartaEsMercenario(
        enCatalogo,
        id: entry.cardId,
        nombre: entry.name,
      ),
    );
  }
  for (final entry in deck.sideboardCards) {
    final key = _keyFor(entry);
    sideCounter[key] = (sideCounter[key] ?? 0) + entry.count;
  }

  copyCounter.forEach((key, copies) {
    final allowed = limitByKey[key] ?? 3;
    if (copies > allowed) {
      final label = labelByKey[key] ?? 'La carta';
      if (allowed <= 0) {
        issues.add(
          ValidationIssue(
            'BANNED_CARD',
            "'$label' está prohibida por la Ban List.",
          ),
        );
      } else {
        // El límite suma mazo y side deck: decirlo evita pensar que es un error
        // cuando las copias de más están en el side.
        final enSide = sideCounter[key] ?? 0;
        final detalle =
            enSide > 0
                ? ' (cuenta mazo y side deck: ${copies - enSide} en el mazo y $enSide en el side).'
                : '.';
        issues.add(
          ValidationIssue(
            'COPIES_LIMIT',
            "'$label' supera el límite de $allowed copias permitido por la Ban List$detalle",
          ),
        );
      }
    }
  });

  if (deck.isRacial && deck.format != DeckFormat.full) {
    final isLibre = deck.format == DeckFormat.racialLibre;

    for (final entry in configuredCards) {
      final rawCard =
          entry.cardId != null
              ? catalogById[entry.cardId!]
              : catalogByName[entry.name] ??
                  catalogByName[entry.name.trim().toLowerCase()];
      final card = _cardDataFrom(rawCard);

      if (card == null) continue;

      // Aliados: siempre deben ser de la raza del mazo (ambos formatos)
      if (card.type == 'Aliado' &&
          deck.race != null &&
          card.race != deck.race) {
        issues.add(
          ValidationIssue(
            'RACE_MISMATCH',
            "Aliado '${card.name}' no es de raza ${deck.race}.",
          ),
        );
      }

      // Racial clásico: aliados Y soporte deben ser de la edición del mazo
      // Racial Libre: aliados y soporte pueden ser de cualquier edición
      if (!isLibre &&
          ['Aliado', 'Oro', 'Talismán', 'Tótem', 'Arma'].contains(card.type) &&
          deck.edition != null &&
          card.edition != null &&
          card.edition != deck.edition) {
        issues.add(
          ValidationIssue(
            'EDITION_MISMATCH',
            "'${card.name}' no pertenece a la edición ${deck.edition}.",
          ),
        );
      }

      // Cartas soloLibre solo pueden usarse en Racial Libre
      if (!isLibre && card.soloLibre) {
        issues.add(
          ValidationIssue(
            'SOLO_LIBRE',
            "'${card.name}' solo puede usarse en formato Racial Libre.",
          ),
        );
      }
    }
  }

  if (total != 49) {
    issues.add(
      ValidationIssue(
        'TOTAL_NOT_49',
        'El mazo tiene $total cartas (debe tener 49 para publicar).',
      ),
    );
  }
  if (sideboardTotal > 10) {
    issues.add(
      ValidationIssue(
        'SIDEBOARD_OVER_10',
        'El side deck tiene $sideboardTotal cartas (máximo 10).',
      ),
    );
  }
  if (sideboardTotal < 0 ||
      deck.sideboardCards.any((entry) => entry.count <= 0)) {
    issues.add(
      const ValidationIssue(
        'INVALID_SIDEBOARD_COUNT',
        'El side deck contiene una cantidad inválida.',
      ),
    );
  }

  final hasDraftBlockingError = issues.any(
    (issue) =>
        issue.code == 'COPIES_LIMIT' ||
        issue.code == 'BANNED_CARD' ||
        issue.code == 'SIDEBOARD_OVER_10' ||
        issue.code == 'INVALID_SIDEBOARD_COUNT',
  );

  return ValidationResult(
    okForDraft: !hasDraftBlockingError,
    okForPublish: issues.isEmpty,
    issues: issues,
  );
}

String? getEditionForRace(String race) {
  const mapRaceEdition = {
    'Eterno': 'Dominios de Ra',
    'Guerrero': 'Encrucijada',
  };
  return mapRaceEdition[race];
}
