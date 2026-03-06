import 'package:flutter/material.dart';

class VsHeader extends StatelessWidget {
  final String aName, bName, deckA, deckB;
  const VsHeader({super.key, required this.aName, required this.bName, required this.deckA, required this.deckB});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Card(elevation: 1),
    );
  }
}
