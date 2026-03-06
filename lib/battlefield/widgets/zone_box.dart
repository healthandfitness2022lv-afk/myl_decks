// lib/battlefield/widgets/zone_box.dart
import 'package:flutter/material.dart';
import '../models/player_state.dart';
import '../models/card_stub.dart';
import '../models/drag_payload.dart';
import '../models/zone.dart';
import 'deck_stack.dart';
import 'card_widget.dart';
import '../screens/battlefield_screen.dart';

class ZoneBox extends StatefulWidget {
  final String label;
  final Zone zone;
  final List<CardStub> cards;
  final bool readOnly;
  final int flex;
  final bool tall;
  final bool slim;
  final VoidCallback? onTap;
  final PlayerState owner;

  const ZoneBox({
    super.key,
    required this.label,
    required this.zone,
    required this.cards,
    required this.readOnly,
    required this.owner,
    this.flex = 1,
    this.tall = false,
    this.slim = false,
    this.onTap,
  });

  @override
  State<ZoneBox> createState() => _ZoneBoxState();
}

class _ZoneBoxState extends State<ZoneBox> {
  bool hovering = false;

  // Tamaño base de carta (coincide con tu CardWidget por defecto)
  static const double _cardW = 64;
  static const double _cardH = 90;
  static const double _gap = 6; // separación ideal cuando no hay solape

  double _boxHeight() => (widget.tall ? 120 : (widget.slim ? 96 : 110));

  String _norm(String s) {
    final t = s.trim().toLowerCase();
    if (t == 'talismán') return 'talisman';
    if (t == 'tótem' || t == 'totem de raza') return 'totem';
    if (t == 'gran aliado') return 'aliado';
    if (t == 'oros') return 'oro';
    return t;
  }

  bool _isAlly(String s) {
    final t = s.trim().toLowerCase();
    return t == 'aliado' || t == 'gran aliado';
  }

  /// Construye una tira horizontal **sobrepuesta** que se adapta al ancho disponible.
  /// - Si [capacity] != null, intenta que el ancho máximo no supere el de `capacity` cartas.
  /// - Si [alwaysOverlap] es true, siempre forzará solape (p.ej. cementerio/destierro).
  Widget _overlappedStrip(
    List<CardStub> cards, {
    int? capacity,
    bool alwaysOverlap = false,
    bool showDefenseShuffleButton = false,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final n = cards.length;
        if (n == 0) {
          return const SizedBox.shrink();
        }

        final maxWidth = constraints.maxWidth;
        // Paso ideal si no hay solape
        final idealStep = _cardW + _gap;

        // Calcular step real para que quepa en el ancho disponible
        double step;
        if (alwaysOverlap) {
          // Apila siempre dentro del ancho disponible (aunque sean pocas)
          step = (maxWidth - _cardW) / (n - 1).clamp(1, 999999);
          // Limitar para que no se separen demasiado (si hay pocas)
          step = step.clamp(_cardW * 0.35, idealStep);
        } else if (capacity != null && n > capacity) {
          // Más de la capacidad: ajusta para que no use más de (capacity * idealStep)
          final targetWidth = (_cardW + idealStep * (capacity - 1)).clamp(0, maxWidth);
          step = (targetWidth - _cardW) / (n - 1);
          step = step.clamp(_cardW * 0.35, idealStep);
        } else {
          // No sobrepasa capacidad: intenta separación normal, pero si no cabe, solapa un poco
          if (n == 1) {
            step = 0;
          } else {
            final maxStep = (maxWidth - _cardW) / (n - 1);
            step = idealStep.clamp(0, maxStep);
          }
        }

        final totalWidth = (n == 1) ? _cardW : (_cardW + step * (n - 1));

        return SizedBox(
          width: totalWidth,
          height: _cardH,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (int i = 0; i < n; i++)
                Positioned(
                  left: i * step,
                  child: _buildCardTile(
                    cards[i],
                    showDefenseShuffleButton: showDefenseShuffleButton,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCardTile(CardStub card, {bool showDefenseShuffleButton = false}) {
    final content = CardWidget(card); // usa tamaño por defecto 64x90

    if (widget.readOnly) {
      return SizedBox(
        width: _cardW,
        height: _cardH,
        child: Stack(
          children: [
            content,
            if (showDefenseShuffleButton && _isAlly(card.tipo))
              _defenseShuffleBtn(card),
          ],
        ),
      );
    }

    final screenState = context.findAncestorStateOfType<BattlefieldScreenState>()!;
    final draggable = Draggable<DragPayload>(
      data: DragPayload(card: card, origin: widget.zone, owner: widget.owner),
      feedback: Material(color: Colors.transparent, child: content),
      childWhenDragging: Opacity(opacity: .3, child: content),
      onDragEnd: (details) {
        if (!details.wasAccepted) {
          screenState.setState(() {
            for (final z in Zone.values) {
              widget.owner.piles[z]!.remove(card);
            }
            widget.owner.piles[Zone.hand]!.add(card);
          });
        }
      },
      child: content,
    );

    return SizedBox(
      width: _cardW,
      height: _cardH,
      child: Stack(
        children: [
          draggable,
          if (showDefenseShuffleButton && _isAlly(card.tipo))
            _defenseShuffleBtn(card),
        ],
      ),
    );
  }

  Positioned _defenseShuffleBtn(CardStub card) {
    return Positioned(
      right: 0,
      top: 0,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            final screen = context.findAncestorStateOfType<BattlefieldScreenState>()!;
            screen.setState(() {
              widget.owner.piles[Zone.defense]!.remove(card);
              widget.owner.piles[Zone.deck]!.add(card);
              widget.owner.shuffle();
            });
          },
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.35),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.shuffle, size: 16, color: Colors.white),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Mazo Castillo: una carta (DeckStack) y listo
    if (widget.zone == Zone.deck) {
  final deckCount = widget.cards.length;

  // Contenedor compacto: solo la carta (DeckStack) y, si hay label, lo mostramos.
  final inner = Container(
    padding: const EdgeInsets.all(6),
    height: _boxHeight(),
    decoration: BoxDecoration(
      border: Border.all(color: Colors.black54, width: 1.2),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min, // 👈 clave: que mida su propio ancho
      children: [
        DeckStack(
          count: deckCount,
          onTap: widget.onTap,
          compact: true, // carta más chica (56x80 aprox)
        ),
        if (widget.label.isNotEmpty) ...[
          const SizedBox(width: 8),
          // Si quieres un label, úsalo sin Expanded para no forzar ancho
          Flexible(
            fit: FlexFit.loose,
            child: Text(
              widget.label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    ),
  );

  // Si hay onTap, hazlo tocable
  final tappable = (widget.onTap != null)
      ? InkWell(onTap: widget.onTap, borderRadius: BorderRadius.circular(10), child: inner)
      : inner;

  // 👇 IMPORTANTE: NO uses Expanded aquí. Deja tamaño intrínseco.
  return tappable;
}


    // Para el resto de zonas, construimos el contenedor con DragTarget y la tira adecuada
    final body = LayoutBuilder(
      builder: (context, constraints) {
        // Selección de layout por zona
        Widget strip;

        // Reglas pedidas:
        // - Oro pagado / Reserva: capacidad 5, luego sobreponer
        // - Cementerio / Destierro: siempre sobrepuestas
        // - Ataque / Defensa: hasta 5, luego sobreponer
        // - Apoyo u otras: usamos capacidad 6 por defecto (puedes ajustar)
        switch (widget.zone) {
          case Zone.goldPaid:
          case Zone.goldPool:
            strip = _overlappedStrip(widget.cards, capacity: 5);
            break;

          case Zone.grave:
          case Zone.exile:
            strip = _overlappedStrip(widget.cards, alwaysOverlap: true);
            break;

          case Zone.attack:
            strip = _overlappedStrip(widget.cards, capacity: 5);
            break;

          case Zone.defense:
            // En defensa además mostramos el botón de “barajar al mazo” sobre cada aliado
            strip = _overlappedStrip(
              widget.cards,
              capacity: 5,
              showDefenseShuffleButton: true,
            );
            break;

          default:
            // support u otras zonas no especificadas: capacidad 6 (ajustable)
            strip = _overlappedStrip(widget.cards, capacity: 6);
            break;
        }

        return strip;
      },
    );

    final content = Container(
      padding: const EdgeInsets.all(6),
      height: _boxHeight(),
      decoration: BoxDecoration(
        border: Border.all(color: hovering ? Colors.blue : Colors.black54, width: 1.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: body,
            ),
          ),
        ],
      ),
    );

    // Si es solo lectura, no hay DragTarget
    if (widget.readOnly) {
      final tappable = (widget.onTap != null)
          ? InkWell(onTap: widget.onTap, child: content)
          : content;
      return Expanded(flex: widget.flex, child: tappable);
    }

    // DragTarget con reglas de aceptación
    return Expanded(
      flex: widget.flex,
      child: DragTarget<DragPayload>(
        onWillAccept: (payload) {
          if (payload == null) return false;
          final tipo = _norm(payload.card.tipo);

          // Reglas estrictas
          if (widget.zone == Zone.goldPool && tipo != 'oro') return false;
          if (widget.zone == Zone.goldPaid && tipo != 'oro') return false;
          if ((widget.zone == Zone.attack || widget.zone == Zone.defense) && tipo != 'aliado') return false;

          setState(() => hovering = true);
          return true;
        },
        onLeave: (_) => setState(() => hovering = false),
        onAccept: (payload) {
  setState(() => hovering = false);
  final screen = context.findAncestorStateOfType<BattlefieldScreenState>()!;
  screen.setState(() {
    for (final z in Zone.values) {
      if (z == Zone.deck) continue;
      payload.owner.piles[z]!.remove(payload.card);
    }
    payload.owner.piles[widget.zone]!.add(payload.card);
  });
  // 👇 NUEVO: sube el estado compartido
  screen.syncNow();
},

        builder: (context, _, __) {
          final tappable = (widget.onTap != null)
              ? InkWell(onTap: widget.onTap, child: content)
              : content;
          return tappable;
        },
      ),
    );
  }
}
