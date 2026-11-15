import 'package:flutter/material.dart';

import '../models/card_variant.dart';

/// Deja elegir, copia por copia, qué variante física corresponde a cada
/// una — usado tanto para "Asignar variante por copia" (mazo) como desde
/// Inventario para declarar variantes de copias sueltas o en un mazo.
/// Guardar resuelve la asignación tal cual quedó elegida en el momento,
/// sin validar stock disponible ni desviar a otro flujo. Devuelve la lista
/// de variantId por copia (null = sin variante) o null si se cancela.
class PerCopyVariantDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  final int count;
  final int ownedCount;
  final List<CardVariant> variants;
  final List<String?> currentSelection;
  // Se conservan por compatibilidad con los llamadores existentes; ya no
  // se usan para bloquear el guardado (ver nota de la clase).
  final Map<String, int> availableByVariant;
  final int unidentifiedAvailable;
  final VoidCallback? onNeedMoreCopies;

  const PerCopyVariantDialog({
    super.key,
    required this.title,
    required this.subtitle,
    required this.count,
    this.ownedCount = 0,
    required this.variants,
    required this.currentSelection,
    required this.availableByVariant,
    required this.unidentifiedAvailable,
    this.onNeedMoreCopies,
  });

  @override
  State<PerCopyVariantDialog> createState() => _PerCopyVariantDialogState();
}

class _PerCopyVariantDialogState extends State<PerCopyVariantDialog> {
  late List<String?> _selection; // null = sin variante asignada

  @override
  void initState() {
    super.initState();
    // Pre-poblar con la selección actual, rellenando con null si faltan
    _selection = List.generate(widget.count, (i) {
      final id =
          i < widget.currentSelection.length
              ? widget.currentSelection[i]
              : null;
      return (id == null || id.isEmpty) ? null : id;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF141418),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Colors.white12, height: 24),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: widget.count,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    return _CopyVariantRow(
                      copyIndex: i,
                      isOwned: i < widget.ownedCount,
                      variants: widget.variants,
                      selectedId: _selection[i],
                      onChanged: (vId) => setState(() => _selection[i] = vId),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF1D184),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(context, List<String?>.from(_selection));
                    },
                    child: const Text(
                      'Guardar',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CopyVariantRow extends StatelessWidget {
  final int copyIndex;
  final bool isOwned;
  final List<CardVariant> variants;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  const _CopyVariantRow({
    required this.copyIndex,
    required this.isOwned,
    required this.variants,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // El id seleccionado puede apuntar a una variante que ya no está en
    // `variants` (p.ej. fue desaprobada o eliminada del catálogo después de
    // haber sido asignada a esta copia). DropdownButton exige que su `value`
    // coincida con exactamente un item, así que si no lo encontramos acá
    // tratamos la copia como "sin variante" en vez de crashear.
    final selected =
        selectedId != null
            ? variants.where((v) => v.id == selectedId).firstOrNull
            : null;
    final effectiveSelectedId = selected != null ? selectedId : null;
    // true cuando había una variante asignada pero ya no figura en el
    // catálogo disponible: si el usuario guarda sin tocar este selector,
    // la copia quedaría "sin variante" silenciosamente.
    final orphanedSelection = selectedId != null && selected == null;
    final imgUrl = selected?.thumbUrl(w: 80, h: 112);

    return Row(
      children: [
        // Miniatura de la variante seleccionada
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child:
              imgUrl != null
                  ? Image.network(
                    imgUrl,
                    width: 52,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholder(),
                  )
                  : _placeholder(),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Copia ${copyIndex + 1}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                isOwned
                    ? (selected == null
                        ? 'La tienes · versión sin identificar'
                        : 'La tienes')
                    : (selected == null
                        ? 'No tengo versión'
                        : 'Se agregará al inventario al guardar'),
                style: TextStyle(
                  color:
                      isOwned
                          ? Colors.greenAccent.shade100
                          : selected == null
                          ? Colors.orangeAccent
                          : const Color(0xFFF1D184),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (orphanedSelection) ...[
                const SizedBox(height: 2),
                const Text(
                  'Su variante asignada ya no está disponible; elige otra o '
                  'guarda como "Sin variante".',
                  style: TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E26),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: effectiveSelectedId,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF1A1A22),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    hint: const Text(
                      'Selecciona una versión',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          isOwned
                              ? 'Sin versión identificada'
                              : 'No tengo versión',
                          style: TextStyle(color: Colors.white38, fontSize: 13),
                        ),
                      ),
                      ...variants.map((v) {
                        final label = v.name.isNotEmpty ? v.name : v.groupLabel;
                        final code =
                            (v.code ?? '').isNotEmpty ? ' · ${v.code}' : '';
                        return DropdownMenuItem<String?>(
                          value: v.id,
                          child: Row(
                            children: [
                              if ((v.thumbUrl(w: 24, h: 34)) != null)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: Image.network(
                                      v.thumbUrl(w: 24, h: 34)!,
                                      width: 24,
                                      height: 34,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (_, __, ___) => const SizedBox(
                                            width: 24,
                                            height: 34,
                                          ),
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  '$label$code',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                    onChanged: onChanged,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _placeholder() {
    return Container(
      width: 52,
      height: 72,
      decoration: BoxDecoration(
        color: const Color(0xFF26222A),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.style, color: Colors.white38, size: 22),
    );
  }
}
