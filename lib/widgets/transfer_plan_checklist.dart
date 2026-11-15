import 'package:flutter/material.dart';

import '../models/inventory.dart';

/// Checklist de un [TransferPlan]: marca cada movimiento como aplicado o
/// devuelto, en orden (no se puede saltar un paso pendiente ni devolver uno
/// posterior antes que el actual). Reutilizado por la pantalla de inventario
/// y por el diálogo de "Generar plan" del detalle de mazo.
class TransferPlanChecklist extends StatelessWidget {
  final TransferPlan plan;
  final Map<String, String> deckNames;
  final Future<void> Function(TransferPlan, TransferMove) onApply;
  final Future<void> Function(TransferPlan, TransferMove) onReturn;
  final Future<void> Function(TransferPlan)? onKeep;
  final Future<void> Function(TransferPlan)? onCancel;

  /// Aplica todos los movimientos pendientes de una vez, en orden, sin
  /// tener que marcarlos uno por uno. Si es null, no se muestra el botón.
  final Future<void> Function(TransferPlan)? onApplyAll;
  final bool applyingAll;
  final bool initiallyExpanded;

  const TransferPlanChecklist({
    super.key,
    required this.plan,
    required this.deckNames,
    required this.onApply,
    required this.onReturn,
    this.onKeep,
    this.onCancel,
    this.onApplyAll,
    this.applyingAll = false,
    this.initiallyExpanded = true,
  });

  String _place(String? id) =>
      id == null ? 'Stock libre' : (deckNames[id] ?? 'Mazo nuevo');

  bool get _closed => {
    TransferPlanStatus.returned,
    TransferPlanStatus.kept,
    TransferPlanStatus.cancelled,
  }.contains(plan.status);

  @override
  Widget build(BuildContext context) {
    final closed = _closed;
    final pendingCount =
        plan.moves.where((m) => m.status == TransferMoveStatus.pending).length;
    return Card(
      color: const Color(0xFF171A22),
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        title: Text(
          plan.name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          '${plan.completedMoves}/${plan.moves.length} movimientos · ${plan.shortages.length} faltantes · ${plan.status.name}',
          style: const TextStyle(color: Colors.white60),
        ),
        children: [
          if (plan.shortages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'No disponibles: ${plan.shortages.map((s) => '${s.quantity}x ${s.cardName}').join(', ')}',
                style: const TextStyle(color: Color(0xFFFF7777)),
              ),
            ),
          if (!closed && onApplyAll != null && pendingCount > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: applyingAll ? null : () => onApplyAll!(plan),
                  icon:
                      applyingAll
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.done_all),
                  label: Text(
                    applyingAll
                        ? 'Aplicando...'
                        : 'Aplicar los $pendingCount movimientos',
                  ),
                ),
              ),
            ),
          ...plan.moves.asMap().entries.map((entry) {
            final move = entry.value;
            final canApply =
                move.status == TransferMoveStatus.pending &&
                !plan.moves
                    .take(entry.key)
                    .any(
                      (candidate) =>
                          candidate.status == TransferMoveStatus.pending,
                    );
            final canReturn =
                move.status == TransferMoveStatus.applied &&
                !plan.moves
                    .skip(entry.key + 1)
                    .any(
                      (candidate) =>
                          candidate.status == TransferMoveStatus.applied,
                    );
            return CheckboxListTile(
              value: move.status == TransferMoveStatus.applied,
              onChanged:
                  closed || (!canApply && !canReturn)
                      ? null
                      : (_) =>
                          canApply ? onApply(plan, move) : onReturn(plan, move),
              activeColor: const Color(0xFF75D69C),
              title: Text(
                '${move.quantity}x ${move.cardName}',
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                '${_place(move.fromDeckId)} → ${_place(move.toDeckId)}',
                style: const TextStyle(color: Colors.white60),
              ),
            );
          }),
          if (!closed && (onCancel != null || onKeep != null))
            OverflowBar(
              alignment: MainAxisAlignment.end,
              children: [
                if (onCancel != null)
                  TextButton(
                    onPressed: () => onCancel!(plan),
                    child: const Text('Cancelar'),
                  ),
                if (onKeep != null)
                  FilledButton.tonal(
                    onPressed: () => onKeep!(plan),
                    child: const Text('Conservar distribución'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
