// lib/screens/leagues/import_round_matches.dart
//
// Importa mesas (duelos) de una fecha desde un Excel con 4 columnas sin
// encabezado: nombre A, marcador A, nombre B, marcador B.
// Genera una mesa (RoundMatch) por cada fila. "libre" en el nombre A o B
// se interpreta como BYE. Si un nombre no matchea a ningún jugador de la
// liga, se le pide al usuario vincularlo a uno existente (o crear nuevo /
// omitir la fila).

import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'models.dart';

const _byeKeyword = 'libre';

class _ImportRow {
  final int rowNumber; // 1-indexed, para mensajes al usuario
  final String rawNameA;
  final String rawNameB;
  final int? scoreA;
  final int? scoreB;

  _ImportRow({
    required this.rowNumber,
    required this.rawNameA,
    required this.rawNameB,
    required this.scoreA,
    required this.scoreB,
  });

  bool get aIsBye => rawNameA.trim().toLowerCase() == _byeKeyword;
  bool get bIsBye => rawNameB.trim().toLowerCase() == _byeKeyword;
}

/// Abre el selector de archivo, parsea el Excel, resuelve nombres contra
/// [players] (pidiendo vinculación manual cuando hace falta) y devuelve la
/// lista de [RoundMatch] a agregar a la fecha. Devuelve null si se canceló.
Future<List<RoundMatch>?> pickAndImportRoundMatches({
  required BuildContext context,
  required List<LeaguePlayer> players,
}) async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
    withData: true,
  );
  if (picked == null || picked.files.isEmpty) return null;
  final bytes = picked.files.single.bytes;
  if (bytes == null) return null;

  final rows = _parseRows(bytes);
  if (rows.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El archivo no tiene filas válidas.')),
      );
    }
    return null;
  }

  if (!context.mounted) return null;
  return _resolveAndBuildMatches(
    context: context,
    rows: rows,
    players: players,
  );
}

List<_ImportRow> _parseRows(Uint8List bytes) {
  final book = Excel.decodeBytes(bytes);
  if (book.tables.isEmpty) return [];
  final sheet = book.tables[book.tables.keys.first]!;

  int? parseScore(dynamic cellValue) {
    if (cellValue == null) return null;
    final s = cellValue.toString().trim();
    if (s.isEmpty) return null;
    return int.tryParse(s);
  }

  String cellText(List<Data?> row, int i) {
    if (i >= row.length) return '';
    final v = row[i]?.value;
    if (v == null) return '';
    return v.toString().trim();
  }

  final rows = <_ImportRow>[];
  for (var i = 0; i < sheet.maxRows; i++) {
    final row = sheet.row(i);
    final nameA = cellText(row, 0);
    final nameB = cellText(row, 2);
    if (nameA.isEmpty && nameB.isEmpty) continue; // fila vacía
    rows.add(
      _ImportRow(
        rowNumber: i + 1,
        rawNameA: nameA,
        rawNameB: nameB,
        scoreA: parseScore(row.length > 1 ? row[1]?.value : null),
        scoreB: parseScore(row.length > 3 ? row[3]?.value : null),
      ),
    );
  }
  return rows;
}

Future<List<RoundMatch>?> _resolveAndBuildMatches({
  required BuildContext context,
  required List<_ImportRow> rows,
  required List<LeaguePlayer> players,
}) async {
  // playerId → LeaguePlayer, más un índice por nombre normalizado.
  final byNormalizedName = <String, LeaguePlayer>{
    for (final p in players) _normalize(p.name): p,
  };
  // Resoluciones ya decididas en esta importación, para no repreguntar el
  // mismo nombre no encontrado dos veces.
  final resolved = <String, LeaguePlayer?>{}; // null = omitir siempre

  Future<LeaguePlayer?> resolveName(String rawName) async {
    if (rawName.trim().isEmpty) return null;
    final key = _normalize(rawName);
    final direct = byNormalizedName[key];
    if (direct != null) return direct;
    if (resolved.containsKey(key)) return resolved[key];

    if (!context.mounted) return null;
    final choice = await _askLinkPlayer(
      context: context,
      rawName: rawName,
      players: players,
    );
    resolved[key] = choice;
    if (choice != null) {
      // Para próximas filas con el mismo nombre, matchear directo.
      byNormalizedName[_normalize(choice.name)] = choice;
    }
    return choice;
  }

  final matches = <RoundMatch>[];
  var skipped = 0;

  for (final row in rows) {
    final aIsBye = row.aIsBye;
    final bIsBye = row.bIsBye;

    if (aIsBye && bIsBye) {
      skipped++;
      continue; // fila sin ningún jugador real
    }

    if (bIsBye) {
      final playerA = await resolveName(row.rawNameA);
      if (playerA == null) {
        skipped++;
        continue;
      }
      matches.add(
        RoundMatch(
          playerAId: playerA.id,
          playerAName: playerA.name,
          scoreA: 2,
          scoreB: 0,
          winnerId: playerA.id,
        ),
      );
      continue;
    }

    if (aIsBye) {
      final playerB = await resolveName(row.rawNameB);
      if (playerB == null) {
        skipped++;
        continue;
      }
      matches.add(
        RoundMatch(
          playerAId: playerB.id,
          playerAName: playerB.name,
          scoreA: 2,
          scoreB: 0,
          winnerId: playerB.id,
          resultAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      continue;
    }

    final playerA = await resolveName(row.rawNameA);
    final playerB = await resolveName(row.rawNameB);
    if (playerA == null || playerB == null) {
      skipped++;
      continue;
    }

    final sA = row.scoreA;
    final sB = row.scoreB;
    final hasResult = sA != null && sB != null;

    matches.add(
      RoundMatch(
        playerAId: playerA.id,
        playerAName: playerA.name,
        playerBId: playerB.id,
        playerBName: playerB.name,
        scoreA: sA,
        scoreB: sB,
        winnerId:
            !hasResult
                ? null
                : (sA == sB ? 'draw' : (sA > sB ? playerA.id : playerB.id)),
        resultAt: hasResult ? DateTime.now().millisecondsSinceEpoch : null,
      ),
    );
  }

  if (!context.mounted) return matches;
  if (skipped > 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$skipped fila(s) omitida(s) sin vincular.')),
    );
  }
  return matches;
}

String _normalize(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Diálogo para vincular un nombre no encontrado a un jugador existente de
/// la liga, o crear uno nuevo, o omitir esa fila.
Future<LeaguePlayer?> _askLinkPlayer({
  required BuildContext context,
  required String rawName,
  required List<LeaguePlayer> players,
}) async {
  final sorted = [...players]..sort((a, b) => a.name.compareTo(b.name));

  final result = await showDialog<_LinkChoice>(
    context: context,
    barrierDismissible: false,
    builder:
        (ctx) => AlertDialog(
          title: Text('Jugador no encontrado: "$rawName"'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Vinculalo a un jugador de la liga:'),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: sorted.length,
                    itemBuilder:
                        (_, i) => ListTile(
                          dense: true,
                          title: Text(sorted[i].name),
                          onTap:
                              () => Navigator.pop(
                                ctx,
                                _LinkChoice.link(sorted[i]),
                              ),
                        ),
                  ),
                ),
                const Divider(),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.person_add_alt_1_outlined),
                  title: Text('Crear jugador nuevo "$rawName"'),
                  onTap: () => Navigator.pop(ctx, _LinkChoice.create()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, _LinkChoice.skip()),
              child: const Text('Omitir fila'),
            ),
          ],
        ),
  );

  if (result == null || result.skip) return null;
  if (result.create) {
    return LeaguePlayer(
      id: '_new_${_normalize(rawName)}',
      name: rawName.trim(),
    );
  }
  return result.player;
}

class _LinkChoice {
  final LeaguePlayer? player;
  final bool create;
  final bool skip;
  _LinkChoice._(this.player, this.create, this.skip);
  factory _LinkChoice.link(LeaguePlayer p) => _LinkChoice._(p, false, false);
  factory _LinkChoice.create() => _LinkChoice._(null, true, false);
  factory _LinkChoice.skip() => _LinkChoice._(null, false, true);
}
