import 'package:flutter/material.dart';
import 'network_image.dart';

Future<void> showCardImagePreview(
  BuildContext context, {
  required String cardName,
  String? imageUrl,
}) {
  final url = imageUrl?.trim();
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (dialogContext) {
      final screen = MediaQuery.sizeOf(dialogContext);
      return Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: const Color(0xFF17110C),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: screen.height * .92,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        cardName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white12),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child:
                          url != null && url.isNotEmpty
                              ? MylNetworkImage(
                                imageUrl: url,
                                fit: BoxFit.contain,
                                placeholder:
                                    (_, __) => const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                errorWidget:
                                    (_, __, ___) => const _PreviewUnavailable(),
                              )
                              : const _PreviewUnavailable(),
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Text(
                  'Puedes ampliar la carta con dos dedos o la rueda del mouse.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _PreviewUnavailable extends StatelessWidget {
  const _PreviewUnavailable();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 260,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported_outlined, color: Colors.white38),
            SizedBox(height: 8),
            Text(
              'Imagen no disponible',
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}
