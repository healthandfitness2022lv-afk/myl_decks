// lib/widgets/skeletons.dart
// Skeleton loaders con pulso sutil — sin dependencias externas.
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Caja con animación de pulso para placeholders de carga.
class SkeletonBox extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius borderRadius;

  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(
        begin: .45,
        end: 1.0,
      ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: AppColors.surfaceDeep,
          borderRadius: widget.borderRadius,
          border: Border.all(color: AppColors.border),
        ),
      ),
    );
  }
}

/// Skeleton con forma de carta del catálogo (imagen + título + chips).
class SkeletonCatalogCard extends StatelessWidget {
  const SkeletonCatalogCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Expanded(
            child: SkeletonBox(
              borderRadius: BorderRadius.all(Radius.circular(18)),
            ),
          ),
          const SizedBox(height: 10),
          const SkeletonBox(height: 16, width: 120),
          const SizedBox(height: 8),
          Row(
            children: const [
              SkeletonBox(
                height: 20,
                width: 64,
                borderRadius: BorderRadius.all(Radius.circular(999)),
              ),
              SizedBox(width: 6),
              SkeletonBox(
                height: 20,
                width: 48,
                borderRadius: BorderRadius.all(Radius.circular(999)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Grid completo de skeletons para el catálogo mientras carga.
class SkeletonCatalogGrid extends StatelessWidget {
  const SkeletonCatalogGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final maxExtent =
            width >= 1400
                ? 250.0
                : width >= 1000
                ? 220.0
                : 190.0;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: maxExtent,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: .62,
          ),
          itemCount: 12,
          itemBuilder: (_, __) => const SkeletonCatalogCard(),
        );
      },
    );
  }
}

/// Fila skeleton para listas (mazos, resultados de búsqueda…).
class SkeletonListTile extends StatelessWidget {
  const SkeletonListTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: const [
          SkeletonBox(width: 54, height: 72),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 16, width: 180),
                SizedBox(height: 8),
                SkeletonBox(height: 12, width: 120),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
