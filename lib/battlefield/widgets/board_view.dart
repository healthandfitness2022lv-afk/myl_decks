import 'package:flutter/material.dart';
import '../models/player_state.dart';
import '../models/zone.dart';
import 'zone_box.dart';

class BoardView extends StatelessWidget {
  final String title;
  final String deckName;
  final PlayerState player;
  final bool readOnly;
  final VoidCallback? onDeckTap;
  final bool compact;
  final VoidCallback? onGoldTap;
  final VoidCallback? onOpenGrave; // viewer de cementerio (si lo usas)

  const BoardView({
    super.key,
    required this.title,
    required this.deckName,
    required this.player,
    required this.readOnly,
    this.onDeckTap,
    this.compact = false,
    this.onGoldTap,
    this.onOpenGrave,
  });

  // ---------- Helpers de flex dinámico ----------

  /// Zonas de línea (ataque/defensa/apoyo) se ensanchan con la cantidad de cartas.
  /// Mantiene la altura (via `tall: true`), solo variamos el ancho con `flex`.
  int _lineFlex(int count, {int min = 2, int max = 5}) {
    if (count <= 1) return min;
    if (count <= 3) return (min + 1).clamp(min, max);
    if (count <= 5) return (min + 2).clamp(min, max);
    if (count <= 7) return (min + 3).clamp(min, max);
    return max;
  }

  /// Zonas densas (cementerio, destierro, oros) reciben algo más de espacio.
  /// No crecen infinito: tope `max` para no romper layout.
  int _denseFlex(int count, {int base = 1, int max = 3}) {
    if (count == 0) return base;
    if (count <= 5) return (base + 1).clamp(base, max);
    if (count <= 10) return (base + 2).clamp(base, max);
    return max;
  }

  @override
  Widget build(BuildContext context) {
    const gridGap = 10.0;

    final atkCount = player.piles[Zone.attack]!.length;
    final defCount = player.piles[Zone.defense]!.length;
    final supCount = player.piles[Zone.support]!.length;

    final goldPaidCount = player.piles[Zone.goldPaid]!.length;
    final goldPoolCount = player.piles[Zone.goldPool]!.length;

    final graveCount = player.piles[Zone.grave]!.length;
    final exileCount = player.piles[Zone.exile]!.length;

    // Flex dinámicos
    final attackFlex = _lineFlex(atkCount, min: 2, max: 5);
    final defenseFlex = _lineFlex(defCount, min: 2, max: 5);
    final supportFlex = _lineFlex(supCount, min: 2, max: 5);

    final goldPaidFlex = _denseFlex(goldPaidCount, base: 2, max: 3);
    final goldPoolFlex = _denseFlex(goldPoolCount, base: 2, max: 3);

    final graveFlex = _denseFlex(graveCount, base: 1, max: 3);
    final exileFlex = _denseFlex(exileCount, base: 1, max: 3);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$title • $deckName',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),

        // Fila superior: Oro pagado | Línea de Ataque
        Row(
          children: [
            ZoneBox(
              label: 'Oro pagado ($goldPaidCount)',
              zone: Zone.goldPaid,
              cards: player.piles[Zone.goldPaid]!,
              readOnly: readOnly,
              flex: goldPaidFlex, // más espacio si hay más oros pagados
              owner: player,
            ),
            const SizedBox(width: gridGap),
            ZoneBox(
              label: 'Línea de Ataque',
              zone: Zone.attack,
              cards: player.piles[Zone.attack]!,
              readOnly: readOnly,
              flex: attackFlex, // se ensancha con cartas
              tall: true,       // misma altura, cambia el ancho
              owner: player,
            ),
          ],
        ),
        const SizedBox(height: gridGap),

        // Fila media: Cementerio | Mazo Castillo | Línea de Defensa
        Row(
          children: [
            ZoneBox(
              label: 'Cementerio ($graveCount)',
              zone: Zone.grave,
              cards: player.piles[Zone.grave]!,
              readOnly: readOnly,
              flex: graveFlex,  // más espacio si está poblado
              slim: true,
              onTap: onOpenGrave,
              owner: player,
            ),
            const SizedBox(width: gridGap),
            ZoneBox(
              label: '', // Mazo de 1 carta (espacio fijo)
              zone: Zone.deck,
              cards: player.piles[Zone.deck]!,
              readOnly: true,   // el mazo ocupa solo 1 carta a nivel de layout
              flex: 1,          // <— fijo
              slim: true,
              onTap: onDeckTap,
              owner: player,
            ),
            const SizedBox(width: gridGap),
            ZoneBox(
              label: 'Línea de Defensa',
              zone: Zone.defense,
              cards: player.piles[Zone.defense]!,
              readOnly: readOnly,
              flex: defenseFlex, // se ensancha con cartas
              tall: true,
              owner: player,
            ),
          ],
        ),
        const SizedBox(height: gridGap),

        // Fila inferior: Destierro | Reserva de Oro | Línea de Apoyo
        Row(
          children: [
            ZoneBox(
              label: 'Destierro ($exileCount)',
              zone: Zone.exile,
              cards: player.piles[Zone.exile]!,
              readOnly: readOnly,
              flex: exileFlex, // más espacio si está poblado
              slim: true,
              owner: player,
            ),
            const SizedBox(width: gridGap),
            ZoneBox(
              label: 'Reserva de Oro ($goldPoolCount)',
              zone: Zone.goldPool,
              cards: player.piles[Zone.goldPool]!,
              readOnly: readOnly,
              flex: goldPoolFlex, // más espacio si hay muchos oros
              onTap: onGoldTap,
              owner: player,
            ),
            const SizedBox(width: gridGap),
            ZoneBox(
              label: 'Línea de Apoyo',
              zone: Zone.support,
              cards: player.piles[Zone.support]!,
              readOnly: readOnly,
              flex: supportFlex, // se ensancha con cartas
              tall: true,
              owner: player,
            ),
          ],
        ),
      ],
    );
  }
}
