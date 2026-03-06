// lib/battlefield/widgets/card_widget.dart
import 'package:flutter/material.dart';
import '../models/card_stub.dart';

class CardWidget extends StatelessWidget {
  final CardStub c;

  /// Tamaño opcional. Si es null, se usa `small` para decidir.
  final Size? _sizeParam;

  /// Compat: si no pasas `size`, usa small=false (64x90) o small=true (56x80).
  final bool small;

  const CardWidget(
    this.c, {
    super.key,
    Size? size,
    this.small = false,
  }) : _sizeParam = size;

  @override
  Widget build(BuildContext context) {
    // Compat: prioridad a `size`; si no viene, decide por `small`
    final Size size =
        _sizeParam ?? (small ? const Size(56, 80) : const Size(64, 90));

    final hasImg = (c.imageUrl != null && c.imageUrl!.isNotEmpty);

    final Widget content = hasImg
        ? ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.network(
              c.imageUrl!,
              width: size.width,
              height: size.height,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallback(size, c.id),
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : _skeleton(size),
            ),
          )
        : _fallback(size, c.id);

    return content;
  }

  Widget _fallback(Size size, String id) {
    return Container(
      width: size.width,
      height: size.height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        border: Border.all(color: Colors.black54),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        id,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _skeleton(Size size) {
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
