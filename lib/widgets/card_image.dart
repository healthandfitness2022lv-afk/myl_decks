// lib/widgets/card_image.dart
// Imagen de carta unificada: caché en memoria+disco (cached_network_image),
// proxy web-safe para URLs de Drive y fallback consistente.
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/card_image_resolver.dart';
import 'network_image.dart';

class MylCardImage extends StatelessWidget {
  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? fallback;

  const MylCardImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.fallback,
  });

  Widget _fallback() =>
      fallback ??
      Container(
        width: width,
        height: height,
        color: AppColors.surfaceDeep,
        alignment: Alignment.center,
        child: const Icon(
          Icons.image_not_supported_outlined,
          color: AppColors.textFaint,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final raw = (url ?? '').trim();
    if (raw.isEmpty) return _clip(_fallback());

    final safe = CardImageResolver.normalize(raw);
    return _clip(
      MylNetworkImage(
        imageUrl: safe,
        width: width,
        height: height,
        fit: fit,
        fadeInDuration: const Duration(milliseconds: 120),
        placeholder:
            (_, __) => Container(
              width: width,
              height: height,
              color: AppColors.surfaceDeep,
            ),
        errorWidget: (_, __, ___) => _fallback(),
      ),
    );
  }

  Widget _clip(Widget child) =>
      borderRadius != null
          ? ClipRRect(borderRadius: borderRadius!, child: child)
          : child;
}
