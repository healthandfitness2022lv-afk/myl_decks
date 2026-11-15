import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

List<Map<String, dynamic>>? readRoundBanListSnapshot(
  Map<String, dynamic>? data,
) {
  final raw = data?['banListSnapshot'];
  if (raw is! List) return null;
  return raw
      .whereType<Map>()
      .map((entry) => Map<String, dynamic>.from(entry))
      .toList(growable: false);
}

String roundBanListFormatKey(Map<String, dynamic>? data) {
  final key =
      (data?['banListFormat'] ??
              data?['roundFormat'] ??
              data?['deckType'] ??
              '')
          .toString()
          .toLowerCase();
  if (key.contains('libre')) return 'racial_libre';
  if (key.contains('full')) return 'full';
  return 'standard';
}

String roundBanListFormatLabel(Map<String, dynamic>? data) {
  switch (roundBanListFormatKey(data)) {
    case 'racial_libre':
      return 'Racial Libre';
    case 'full':
      return 'Formato Libre';
    default:
      return 'Racial Edición';
  }
}

String _shortDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';

String roundBanListStatusLabel(Map<String, dynamic>? data) {
  final snapshot = readRoundBanListSnapshot(data);
  if (snapshot == null) return 'Ban List sin guardar';
  final captured = data?['banListCapturedAt'];
  final sourceName = data?['banListSourceRoundName']?.toString();
  final suffix =
      captured is Timestamp ? ' · ${_shortDate(captured.toDate())}' : '';
  if (sourceName != null && sourceName.trim().isNotEmpty) {
    return 'Ban List: ${snapshot.length} reglas · copiada de $sourceName';
  }
  return 'Ban List: ${snapshot.length} reglas$suffix';
}

String _sourceLabel(Map<String, dynamic> data) {
  final source = (data['banListSource'] ?? '').toString();
  switch (source) {
    case 'current':
      return 'Lista vigente capturada para esta fecha';
    case 'current_backfill':
      return 'Lista vigente aplicada como regularización';
    case 'round_copy':
      final name = (data['banListSourceRoundName'] ?? 'otra fecha').toString();
      return 'Copiada desde $name';
    default:
      return 'Snapshot histórico de la fecha';
  }
}

Future<void> showRoundBanListViewer(
  BuildContext context, {
  required String roundName,
  required Map<String, dynamic> roundData,
}) async {
  final snapshot = readRoundBanListSnapshot(roundData);
  final entries = [...?snapshot]..sort((a, b) {
    final aLimit = (a['maxCopies'] as num?)?.toInt() ?? 0;
    final bLimit = (b['maxCopies'] as num?)?.toInt() ?? 0;
    final byLimit = aLimit.compareTo(bLimit);
    if (byLimit != 0) return byLimit;
    return (a['cardName'] ?? '').toString().toLowerCase().compareTo(
      (b['cardName'] ?? '').toString().toLowerCase(),
    );
  });
  final banned =
      entries.where((entry) => ((entry['maxCopies'] as num?) ?? 0) <= 0).length;
  final limited = entries.length - banned;
  final format = roundBanListFormatLabel(roundData);

  await showDialog<void>(
    context: context,
    builder:
        (ctx) => Dialog(
          child: SizedBox(
            width:
                (MediaQuery.sizeOf(ctx).width * .92).clamp(300, 720).toDouble(),
            height:
                (MediaQuery.sizeOf(ctx).height * .82)
                    .clamp(360, 760)
                    .toDouble(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ban List · $roundName',
                              style: Theme.of(ctx).textTheme.titleLarge,
                            ),
                            Text(
                              '$format · ${_sourceLabel(roundData)}',
                              style: Theme.of(ctx).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        tooltip: 'Cerrar',
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (snapshot == null)
                  const Expanded(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.gpp_maybe_outlined, size: 48),
                            SizedBox(height: 12),
                            Text(
                              'Esta fecha todavía no tiene una Ban List guardada.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(label: Text('${entries.length} reglas')),
                        Chip(label: Text('$banned prohibidas')),
                        Chip(label: Text('$limited limitadas')),
                      ],
                    ),
                  ),
                  if (entries.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text('Sin restricciones para esta fecha'),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                        itemCount: entries.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          final maxCopies =
                              (entry['maxCopies'] as num?)?.toInt() ?? 0;
                          final details = [
                            entry['cardType']?.toString(),
                            entry['edition']?.toString(),
                            entry['race']?.toString(),
                          ].whereType<String>().where(
                            (value) => value.isNotEmpty,
                          );
                          return ListTile(
                            leading: CircleAvatar(
                              child: Text(maxCopies <= 0 ? '0' : '$maxCopies'),
                            ),
                            title: Text(
                              (entry['cardName'] ?? entry['cardId'] ?? 'Carta')
                                  .toString(),
                            ),
                            subtitle:
                                details.isEmpty
                                    ? null
                                    : Text(details.join(' · ')),
                            trailing: Text(
                              maxCopies <= 0 ? 'Prohibida' : 'Máx. $maxCopies',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color:
                                    maxCopies <= 0
                                        ? Theme.of(context).colorScheme.error
                                        : null,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
  );
}
