import 'package:flutter/material.dart';

class DeckStack extends StatelessWidget {
  final int count;
  final VoidCallback? onTap;
  final bool compact;
  const DeckStack({super.key, required this.count, this.onTap, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final size = compact ? const Size(56, 80) : const Size(64, 90);
    final cardBack = ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.asset('assets/reves.jpg', width: size.width, height: size.height, fit: BoxFit.cover),
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        alignment: Alignment.center,
        children: [
          cardBack,
          Positioned(
            right: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
