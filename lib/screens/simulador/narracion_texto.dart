// Narración del simulador con los nombres de las cartas resaltados
// ("Forma de Lince: Faraón guerrero roba Escarabeo").

import 'package:flutter/material.dart';

const colorCarta = Color(0xFF7FD4FF);

/// Separa [texto] en tramos y pinta con [estiloCarta] los que son nombres de
/// cartas. Los nombres más largos primero ("Dragón de Magma" antes que "Dragón").
List<TextSpan> tramosConCartas(
  String texto,
  Iterable<String> nombres, {
  TextStyle estiloCarta = const TextStyle(
    color: colorCarta,
    fontWeight: FontWeight.w800,
  ),
}) {
  final lista =
      nombres.where((n) => n.trim().length > 1).toSet().toList()
        ..sort((a, b) => b.length.compareTo(a.length));
  if (lista.isEmpty) return [TextSpan(text: texto)];
  final patron = RegExp(lista.map(RegExp.escape).join('|'));
  final out = <TextSpan>[];
  var desde = 0;
  for (final m in patron.allMatches(texto)) {
    if (m.start > desde) out.add(TextSpan(text: texto.substring(desde, m.start)));
    out.add(TextSpan(text: m.group(0), style: estiloCarta));
    desde = m.end;
  }
  if (desde < texto.length) out.add(TextSpan(text: texto.substring(desde)));
  return out;
}
