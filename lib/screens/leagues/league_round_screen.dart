// lib/screens/leagues/league_round_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/ban_list_service.dart';
import 'models.dart';
import 'league_widgets.dart';
import 'league_deck_builder_screen.dart';
import 'league_round_decks_screen.dart';
import 'round_ban_list_viewer.dart';

class LeagueRoundScreen extends StatefulWidget {
  final String leagueId;
  final String roundId;
  final List<LeaguePlayer> players;
  final bool isAdmin;
  // Configuración de la liga (cargada desde el doc padre)
  final int duelsPerMatch;

  const LeagueRoundScreen({
    super.key,
    required this.leagueId,
    required this.roundId,
    required this.players,
    required this.isAdmin,
    this.duelsPerMatch = 1,
  });

  @override
  State<LeagueRoundScreen> createState() => _LeagueRoundScreenState();
}

class _LeagueRoundScreenState extends State<LeagueRoundScreen> {
  Map<String, dynamic>? _round;
  List<RoundMatch> _matches = [];
  // playerId → raza del mazo asignado para esta fecha.
  Map<String, String> _deckRaces = {};
  bool _loading = true;
  bool _saving = false;
  // Copia local editable: crece cuando la importación de Excel crea
  // jugadores nuevos en la liga durante esta misma sesión.
  late List<LeaguePlayer> _players;

  @override
  void initState() {
    super.initState();
    _players = List<LeaguePlayer>.from(widget.players);
    _load();
  }

  DocumentReference<Map<String, dynamic>> get _roundRef => FirebaseFirestore
      .instance
      .collection('leagues')
      .doc(widget.leagueId)
      .collection('rounds')
      .doc(widget.roundId);

  RoundFormat get _roundFormat =>
      RoundFormat.fromKey(_round?['roundFormat'] as String?);

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final snap = await _roundRef.get();
      if (!mounted) return;
      final data = snap.data() ?? {};
      final rawMatches = (data['matches'] as List<dynamic>?) ?? [];
      final rawRaces = (data['deckRaces'] as Map<String, dynamic>?) ?? {};
      final races = <String, String>{};
      final loadedFormat = RoundFormat.fromKey(data['roundFormat'] as String?);
      if (loadedFormat != RoundFormat.full) {
        rawRaces.forEach((playerId, race) {
          if (race is String && race.trim().isNotEmpty) {
            races[playerId] = race.trim();
          }
        });
      }
      setState(() {
        _round = data;
        _deckRaces = races;
        _matches =
            rawMatches
                .whereType<Map<String, dynamic>>()
                .map(RoundMatch.fromMap)
                .toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _persistMatches() async {
    await _roundRef.update({
      'matches': _matches.map((m) => m.toMap()).toList(),
    });
  }

  Future<void> _editRoundDate() async {
    final current = (_round?['date'] as Timestamp?)?.toDate() ?? DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(1990),
      lastDate: DateTime(2100),
      helpText: 'Fecha de la jornada',
      cancelText: 'Cancelar',
      confirmText: 'Guardar',
    );
    if (selected == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await _roundRef.update({'date': Timestamp.fromDate(selected)});
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Fecha actualizada')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo actualizar: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<Map<String, dynamic>>? _banListSnapshotOf(Map<String, dynamic>? data) {
    final raw = data?['banListSnapshot'];
    if (raw is! List) return null;
    return raw
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
  }

  String _shortDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  String _banListStatus(Map<String, dynamic>? data) {
    final snapshot = _banListSnapshotOf(data);
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

  Future<void> _manageBanList() async {
    final snapshot = _banListSnapshotOf(_round);
    final source = (_round?['banListSource'] ?? '').toString();
    final action = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Ban List de la fecha'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_banListStatus(_round)),
                const SizedBox(height: 8),
                Text(
                  snapshot == null
                      ? 'Esta fecha todavía depende de la lista vigente. Guarda '
                          'un snapshot para fijar sus reglas históricas.'
                      : 'El snapshot no cambia cuando se edita la Ban List '
                          'general. Origen: ${source.isEmpty ? 'histórico' : source}.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
              TextButton.icon(
                onPressed: () => Navigator.pop(ctx, 'view'),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Ver cartas'),
              ),
              TextButton.icon(
                onPressed: () => Navigator.pop(ctx, 'copy'),
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Copiar de otra fecha'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, 'current'),
                icon: const Icon(Icons.download_rounded),
                label: const Text('Cargar vigente'),
              ),
            ],
          ),
    );
    if (!mounted) return;
    if (action == 'view') {
      await showRoundBanListViewer(
        context,
        roundName: (_round?['name'] ?? 'Fecha').toString(),
        roundData: _round ?? const <String, dynamic>{},
      );
    }
    if (action == 'current') await _applyCurrentBanList();
    if (action == 'copy') await _copyBanListFromRound();
  }

  Future<bool> _confirmBanListReplacement(String message) async {
    if (_banListSnapshotOf(_round) == null) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Reemplazar Ban List'),
            content: Text(
              '$message\n\nEsto puede modificar las estadísticas históricas de '
              'la fecha. Los resultados y las barajas no se alterarán.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Reemplazar'),
              ),
            ],
          ),
    );
    return confirmed == true;
  }

  Future<void> _applyCurrentBanList() async {
    final confirmed = await _confirmBanListReplacement(
      'Se cargará la Ban List vigente para este formato.',
    );
    if (!confirmed || !mounted) return;

    setState(() => _saving = true);
    try {
      final formatKey = roundBanListFormatKey(_round);
      final service = BanListService.forRoundFormatKey(formatKey);
      final snapshot = await service.fetchSnapshot();
      await _roundRef.update({
        'banListSnapshot': snapshot,
        'banListCapturedAt': FieldValue.serverTimestamp(),
        'banListSource': 'current',
        'banListFormat': formatKey,
        'banListEntryCount': snapshot.length,
        'banListSourceRoundId': FieldValue.delete(),
        'banListSourceRoundName': FieldValue.delete(),
        'banListSourceCapturedAt': FieldValue.delete(),
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ban List vigente guardada (${snapshot.length} reglas)',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo cargar la Ban List: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _copyBanListFromRound() async {
    setState(() => _saving = true);
    try {
      final rounds =
          await FirebaseFirestore.instance
              .collection('leagues')
              .doc(widget.leagueId)
              .collection('rounds')
              .get();
      final formatKey = roundBanListFormatKey(_round);
      final candidates =
          rounds.docs.where((doc) {
            if (doc.id == widget.roundId) return false;
            final data = doc.data();
            return _banListSnapshotOf(data) != null &&
                roundBanListFormatKey(data) == formatKey;
          }).toList();
      candidates.sort((a, b) {
        final aDate = a.data()['date'] as Timestamp?;
        final bDate = b.data()['date'] as Timestamp?;
        return (bDate?.millisecondsSinceEpoch ?? 0).compareTo(
          aDate?.millisecondsSinceEpoch ?? 0,
        );
      });

      if (!mounted) return;
      if (candidates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay otra fecha compatible con snapshot'),
          ),
        );
        return;
      }

      final sourceId = await showDialog<String>(
        context: context,
        builder:
            (ctx) => SimpleDialog(
              title: const Text('Copiar Ban List desde'),
              children:
                  candidates.map((doc) {
                    final data = doc.data();
                    final name = (data['name'] ?? 'Fecha').toString();
                    final date = data['date'] as Timestamp?;
                    final count = _banListSnapshotOf(data)?.length ?? 0;
                    return SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, doc.id),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_note_outlined),
                        title: Text(name),
                        subtitle: Text(
                          [
                            '$count reglas',
                            if (date != null) _shortDate(date.toDate()),
                          ].join(' · '),
                        ),
                      ),
                    );
                  }).toList(),
            ),
      );
      if (sourceId == null || !mounted) return;

      final source = candidates.firstWhere((doc) => doc.id == sourceId);
      final sourceData = source.data();
      final sourceName = (sourceData['name'] ?? 'Fecha').toString();
      final confirmed = await _confirmBanListReplacement(
        'Se copiará el snapshot usado por $sourceName.',
      );
      if (!confirmed || !mounted) return;

      final snapshot = _banListSnapshotOf(sourceData)!;
      await _roundRef.update({
        'banListSnapshot': snapshot,
        'banListCapturedAt': FieldValue.serverTimestamp(),
        'banListSource': 'round_copy',
        'banListFormat': formatKey,
        'banListEntryCount': snapshot.length,
        'banListSourceRoundId': source.id,
        'banListSourceRoundName': sourceName,
        if (sourceData['banListCapturedAt'] != null)
          'banListSourceCapturedAt': sourceData['banListCapturedAt'],
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ban List copiada desde $sourceName')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo copiar la Ban List: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Gestión manual de duelos ───────────────────────────────────────────────

  Future<void> _addMatchManually() async {
    LeaguePlayer? playerA;
    LeaguePlayer? playerB;

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setS) => AlertDialog(
                  title: const Text('Agregar duelo'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField<LeaguePlayer>(
                          decoration: const InputDecoration(
                            labelText: 'Jugador A',
                          ),
                          value: playerA,
                          items:
                              _players
                                  .map(
                                    (p) => DropdownMenuItem(
                                      value: p,
                                      child: Text(p.name),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) => setS(() => playerA = v),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<LeaguePlayer?>(
                          decoration: const InputDecoration(
                            labelText: 'Jugador B (vacío = bye)',
                          ),
                          value: playerB,
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('— Bye —'),
                            ),
                            ..._players.map(
                              (p) => DropdownMenuItem(
                                value: p,
                                child: Text(p.name),
                              ),
                            ),
                          ],
                          onChanged: (v) => setS(() => playerB = v),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed:
                          playerA == null
                              ? null
                              : () => Navigator.pop(ctx, true),
                      child: const Text('Agregar'),
                    ),
                  ],
                ),
          ),
    );

    if (ok != true || playerA == null || !mounted) return;

    setState(() {
      _matches.add(
        RoundMatch(
          playerAId: playerA!.id,
          playerAName: playerA!.name,
          playerBId: playerB?.id,
          playerBName: playerB?.name,
        ),
      );
    });

    setState(() => _saving = true);
    try {
      await _persistMatches();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Asignar mazos por jugador ──────────────────────────────────────────────
  //
  // Un mazo por jugador para toda la fecha (no por duelo). El admin lo arma con
  // la misma vista que create_deck, respetando el formato de la fecha.

  Future<void> _openAssignDecks() async {
    final isFinished = (_round?['status'] as String?) == 'finished';
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => LeagueRoundDecksScreen(
              leagueId: widget.leagueId,
              roundId: widget.roundId,
              players: _players,
              roundFormat: _roundFormat,
              banListSnapshot: _banListSnapshotOf(_round),
              isAdmin: widget.isAdmin && !isFinished,
            ),
      ),
    );
    // Recargar para reflejar las razas de los mazos recién asignados.
    if (mounted) await _load();
  }

  // ── Armar mazo de un jugador (legacy: por duelo) ───────────────────────────

  Future<void> _editMatchDecks(int index) async {
    final m = _matches[index];
    final format = _roundFormat;

    final deckA = await Navigator.push<LeagueDeckResult>(
      context,
      MaterialPageRoute(
        builder:
            (_) => LeagueDeckBuilderScreen(
              playerName: m.playerAName,
              roundFormat: format,
              banListSnapshot: _banListSnapshotOf(_round),
              initialCards: List.from(m.deckA),
            ),
      ),
    );
    if (!mounted) return;
    if (deckA != null) setState(() => _matches[index].deckA = deckA.cards);

    if (!m.isBye) {
      final deckB = await Navigator.push<LeagueDeckResult>(
        context,
        MaterialPageRoute(
          builder:
              (_) => LeagueDeckBuilderScreen(
                playerName: m.playerBName ?? 'Jugador B',
                roundFormat: format,
                banListSnapshot: _banListSnapshotOf(_round),
                initialCards: List.from(m.deckB),
              ),
        ),
      );
      if (!mounted) return;
      if (deckB != null) setState(() => _matches[index].deckB = deckB.cards);
    }

    setState(() => _saving = true);
    try {
      await _persistMatches();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeMatch(int index) async {
    setState(() => _matches.removeAt(index));
    setState(() => _saving = true);
    try {
      await _persistMatches();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Resultado de un duelo ─────────────────────────────────────────────────
  //
  // Con duelsPerMatch > 1 se ingresa cuántos juegos ganó cada uno.
  // Con duelsPerMatch == 1 se ingresa solo el marcador (ej: 2-1).

  Future<void> _enterResult(int index) async {
    final m = _matches[index];
    final dpm = widget.duelsPerMatch;
    final officialTimestamp = _round?['date'] as Timestamp?;
    final officialValue = officialTimestamp?.toDate();
    final officialDate =
        officialValue == null
            ? null
            : DateTime(
              officialValue.year,
              officialValue.month,
              officialValue.day,
            );
    final now = DateTime.now();
    final lastPlayedDate = DateTime(now.year, now.month, now.day);
    final firstPlayedDate = officialDate ?? DateTime(2020);

    if (firstPlayedDate.isAfter(lastPlayedDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se puede cargar un resultado antes de la fecha oficial de la jornada.',
          ),
        ),
      );
      return;
    }

    DateTime validInitialDate(DateTime value) {
      final day = DateTime(value.year, value.month, value.day);
      if (day.isBefore(firstPlayedDate)) return firstPlayedDate;
      if (day.isAfter(lastPlayedDate)) return lastPlayedDate;
      return day;
    }

    bool isValidPlayedDate(DateTime value) {
      final day = DateTime(value.year, value.month, value.day);
      return !day.isBefore(firstPlayedDate) && !day.isAfter(lastPlayedDate);
    }

    if (m.isBye) {
      // Un bye se resuelve solo (2-0 automático), pero si ya tenía resultado
      // cargado esto es una re-edición: se ofrece corregir la fecha real,
      // igual que en un duelo normal, para poder reconstruir fechas pasadas.
      DateTime playedOn =
          m.resultAt != null
              ? DateTime.fromMillisecondsSinceEpoch(m.resultAt!)
              : DateTime.now();
      if (m.hasResult) {
        final picked = await showDatePicker(
          context: context,
          initialDate: validInitialDate(playedOn),
          firstDate: firstPlayedDate,
          lastDate: lastPlayedDate,
          helpText: 'Fecha en que se jugó (BYE)',
        );
        if (picked == null || !mounted) return;
        playedOn = DateTime(
          picked.year,
          picked.month,
          picked.day,
          playedOn.hour,
          playedOn.minute,
        );
      }
      if (!isValidPlayedDate(playedOn)) return;
      setState(() {
        _matches[index].winnerId = m.playerAId;
        _matches[index].scoreA = 2;
        _matches[index].scoreB = 0;
        _matches[index].resultAt = playedOn.millisecondsSinceEpoch;
      });
      setState(() => _saving = true);
      try {
        await _persistMatches();
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }

    final aCtrl = TextEditingController(text: m.scoreA?.toString() ?? '');
    final bCtrl = TextEditingController(text: m.scoreB?.toString() ?? '');
    String? coinTossWinnerId = m.coinTossWinnerId;
    // Fecha real en que se jugó el duelo. Por defecto hoy (o la ya cargada,
    // si se está editando un resultado existente), pero se puede corregir a
    // mano: sirve tanto para cargar en el momento como para reconstruir
    // hacia atrás la fecha real de duelos ya jugados.
    DateTime playedOn =
        m.resultAt != null
            ? DateTime.fromMillisecondsSinceEpoch(m.resultAt!)
            : DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setDialogState) => AlertDialog(
                  title: Text(
                    'Resultado: ${m.playerAName} vs ${m.playerBName}',
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (dpm > 1)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Ingresá los juegos ganados por cada uno (máx ${(dpm ~/ 2) + 1}).',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: aCtrl,
                              keyboardType: TextInputType.number,
                              autofocus: true,
                              decoration: InputDecoration(
                                labelText: m.playerAName,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              '–',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              controller: bCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: m.playerBName ?? '',
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Ganó el dado (empezó jugando):',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: Text(m.playerAName),
                            selected: coinTossWinnerId == m.playerAId,
                            onSelected:
                                (sel) => setDialogState(
                                  () =>
                                      coinTossWinnerId =
                                          sel ? m.playerAId : null,
                                ),
                          ),
                          ChoiceChip(
                            label: Text(m.playerBName ?? ''),
                            selected: coinTossWinnerId == m.playerBId,
                            onSelected:
                                (sel) => setDialogState(
                                  () =>
                                      coinTossWinnerId =
                                          sel ? m.playerBId : null,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Fecha en que se jugó:',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: validInitialDate(playedOn),
                            firstDate: firstPlayedDate,
                            lastDate: lastPlayedDate,
                          );
                          if (picked != null) {
                            setDialogState(
                              () =>
                                  playedOn = DateTime(
                                    picked.year,
                                    picked.month,
                                    picked.day,
                                    playedOn.hour,
                                    playedOn.minute,
                                  ),
                            );
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            suffixIcon: Icon(Icons.calendar_today, size: 18),
                          ),
                          child: Text(
                            '${playedOn.day.toString().padLeft(2, '0')}/${playedOn.month.toString().padLeft(2, '0')}/${playedOn.year}',
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Por defecto es hoy. No puede ser anterior a la fecha oficial de la jornada.',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Guardar'),
                    ),
                  ],
                ),
          ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      aCtrl.dispose();
      bCtrl.dispose();
    });

    if (ok != true || !mounted) return;

    if (!isValidPlayedDate(playedOn)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La fecha del duelo no es válida.')),
      );
      return;
    }

    final sA = int.tryParse(aCtrl.text.trim()) ?? 0;
    final sB = int.tryParse(bCtrl.text.trim()) ?? 0;

    setState(() {
      _matches[index].scoreA = sA;
      _matches[index].scoreB = sB;
      // Marcador igual = empate (1 pto c/u); si no, gana quien tenga más juegos.
      _matches[index].winnerId =
          sA == sB ? 'draw' : (sA > sB ? m.playerAId : m.playerBId);
      _matches[index].coinTossWinnerId = coinTossWinnerId;
      _matches[index].resultAt = playedOn.millisecondsSinceEpoch;
    });

    setState(() => _saving = true);
    try {
      await _persistMatches();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Finalizar fecha ────────────────────────────────────────────────────────

  Future<void> _finishRound() async {
    final pending = _matches.where((m) => !m.hasResult).length;
    final msg =
        pending > 0
            ? 'Hay $pending duelo(s) sin resultado. ¿Finalizar igual?'
            : '¿Marcar esta fecha como finalizada?';

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Finalizar fecha'),
            content: Text(msg),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Finalizar'),
              ),
            ],
          ),
    );
    if (ok != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await _roundRef.update({'status': 'finished'});
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Fecha finalizada')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Tabla interna de la fecha ──────────────────────────────────────────────

  List<_RoundStanding> _computeRoundStandings() {
    final map = <String, _RoundStanding>{};
    for (final p in _players) {
      map[p.id] = _RoundStanding(id: p.id, name: p.name);
    }
    for (final m in _matches) {
      if (!m.hasResult) continue;
      if (m.isBye) {
        final bye = map[m.playerAId];
        if (bye != null) {
          bye.played++;
          bye.won++;
          bye.pts += 3;
          bye.favor += 2;
        }
        continue;
      }
      final aId = m.playerAId;
      final bId = m.playerBId!;
      map.putIfAbsent(aId, () => _RoundStanding(id: aId, name: m.playerAName));
      map.putIfAbsent(
        bId,
        () => _RoundStanding(id: bId, name: m.playerBName ?? bId),
      );

      map[aId]!.played++;
      map[bId]!.played++;
      map[aId]!.favor += m.scoreA ?? 0;
      map[aId]!.against += m.scoreB ?? 0;
      map[bId]!.favor += m.scoreB ?? 0;
      map[bId]!.against += m.scoreA ?? 0;

      if (m.winnerId == aId) {
        map[aId]!.won++;
        map[aId]!.pts += 3;
        map[bId]!.lost++;
      } else if (m.winnerId == bId) {
        map[bId]!.won++;
        map[bId]!.pts += 3;
        map[aId]!.lost++;
      } else {
        map[aId]!.draw++;
        map[aId]!.pts++;
        map[bId]!.draw++;
        map[bId]!.pts++;
      }
    }
    return map.values.toList()..sort((a, b) {
      final cp = b.pts.compareTo(a.pts);
      if (cp != 0) return cp;
      return b.diff.compareTo(a.diff);
    });
  }

  void _showRoundStandings() {
    final rows = _computeRoundStandings();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (_) => DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.35,
            maxChildSize: 0.92,
            expand: false,
            builder:
                (_, ctrl) => Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 4),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Tabla de la fecha',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: ctrl,
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            headingRowHeight: 32,
                            dataRowMinHeight: 36,
                            dataRowMaxHeight: 36,
                            columnSpacing: 16,
                            columns: const [
                              DataColumn(label: Text('#')),
                              DataColumn(label: Text('Jugador')),
                              DataColumn(label: Text('Pts'), numeric: true),
                              DataColumn(label: Text('J'), numeric: true),
                              DataColumn(label: Text('G'), numeric: true),
                              DataColumn(label: Text('P'), numeric: true),
                              DataColumn(label: Text('E'), numeric: true),
                              DataColumn(label: Text('Dif.F'), numeric: true),
                              DataColumn(label: Text('Dif.C'), numeric: true),
                              DataColumn(label: Text('Dif'), numeric: true),
                            ],
                            rows:
                                rows.asMap().entries.map((e) {
                                  final i = e.key;
                                  final r = e.value;
                                  final diff = r.favor - r.against;
                                  final diffStr = diff > 0 ? '+$diff' : '$diff';
                                  final diffColor =
                                      diff > 0
                                          ? Colors.green
                                          : diff < 0
                                          ? Colors.red
                                          : Colors.grey;
                                  return DataRow(
                                    cells: [
                                      DataCell(
                                        Text(
                                          '${i + 1}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          r.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          '${r.pts}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                      DataCell(Text('${r.played}')),
                                      DataCell(Text('${r.won}')),
                                      DataCell(Text('${r.lost}')),
                                      DataCell(Text('${r.draw}')),
                                      DataCell(Text('${r.favor}')),
                                      DataCell(Text('${r.against}')),
                                      DataCell(
                                        Text(
                                          diffStr,
                                          style: TextStyle(
                                            color: diffColor,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
          ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final roundName = (_round?['name'] as String?) ?? 'Fecha';
    final deckType = (_round?['deckType'] as String?) ?? '';
    final status = (_round?['status'] as String?) ?? 'open';
    final isFinished = status == 'finished';
    final roundDate = (_round?['date'] as Timestamp?)?.toDate();
    final banSnapshot = _banListSnapshotOf(_round);
    final allDone = _matches.isNotEmpty && _matches.every((m) => m.hasResult);
    final hasAnyResult = _matches.any((m) => m.hasResult && !m.isBye);
    final playableMatches = _matches.where((m) => !m.isBye).toList();
    final completedMatches = playableMatches.where((m) => m.hasResult).length;
    final progress =
        playableMatches.isEmpty
            ? 0.0
            : completedMatches / playableMatches.length;

    final dpm = widget.duelsPerMatch;
    final dpmLabel = dpm == 1 ? '1 juego' : 'Bo$dpm';

    final infoLine = [
      if (deckType.isNotEmpty) deckType,
      if (roundDate != null)
        '${roundDate.day}/${roundDate.month}/${roundDate.year}',
      dpmLabel,
      banSnapshot == null
          ? 'Ban List pendiente'
          : 'Ban List ${banSnapshot.length}',
      if (isFinished) 'Finalizada',
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(roundName),
            Text(
              infoLine,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isFinished ? Colors.green.shade300 : Colors.white70,
              ),
            ),
          ],
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (hasAnyResult)
            IconButton(
              icon: const Icon(Icons.table_rows_rounded),
              tooltip: 'Tabla de la fecha',
              onPressed: _showRoundStandings,
            ),
          IconButton(
            icon: const Icon(Icons.style_rounded),
            tooltip: 'Asignar mazos',
            onPressed: _saving ? null : _openAssignDecks,
          ),
          IconButton(
            icon: Icon(
              banSnapshot == null
                  ? Icons.gpp_maybe_outlined
                  : Icons.gpp_good_outlined,
            ),
            tooltip:
                widget.isAdmin
                    ? 'Ver o asignar Ban List'
                    : 'Ver Ban List de la fecha',
            onPressed:
                _saving
                    ? null
                    : widget.isAdmin
                    ? _manageBanList
                    : () => showRoundBanListViewer(
                      context,
                      roundName: roundName,
                      roundData: _round ?? const <String, dynamic>{},
                    ),
          ),
          if (widget.isAdmin)
            IconButton(
              icon: const Icon(Icons.edit_calendar_rounded),
              tooltip: 'Editar fecha',
              onPressed: _saving ? null : _editRoundDate,
            ),
          if (widget.isAdmin && !isFinished) ...[
            IconButton(
              icon: const Icon(Icons.add_rounded),
              tooltip: 'Agregar duelo',
              onPressed: _saving ? null : _addMatchManually,
            ),
            if (allDone || _matches.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.check_circle_outline_rounded),
                tooltip: 'Finalizar fecha',
                onPressed: _saving ? null : _finishRound,
              ),
          ],
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isFinished
                          ? Icons.check_circle
                          : Icons.sports_mma_outlined,
                      color: isFinished ? Colors.green : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isFinished
                            ? 'Fecha finalizada'
                            : '$completedMatches de ${playableMatches.length} duelos completados',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (!isFinished && playableMatches.isNotEmpty)
                      Text('${(progress * 100).round()}%'),
                  ],
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: isFinished ? 1 : progress,
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(99),
                ),
                if (!isFinished &&
                    completedMatches < playableMatches.length) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Registra los resultados pendientes antes de cerrar la fecha.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child:
                _matches.isEmpty
                    ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.sports_mma_rounded,
                            size: 48,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Sin duelos en esta fecha.',
                            style: TextStyle(color: Colors.grey),
                          ),
                          if (widget.isAdmin && !isFinished) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _addMatchManually,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Manual'),
                            ),
                          ],
                        ],
                      ),
                    )
                    : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 210,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            mainAxisExtent: 116,
                          ),
                      itemCount: _matches.length,
                      itemBuilder: (context, i) {
                        final m = _matches[i];
                        return RoundMatchTile(
                          match: m,
                          index: i + 1,
                          isAdmin: widget.isAdmin && !isFinished,
                          duelsPerMatch: dpm,
                          onResult: () => _enterResult(i),
                          onEditDecks: () => _editMatchDecks(i),
                          onRemove: () => _removeMatch(i),
                          raceA: _deckRaces[m.playerAId],
                          raceB:
                              m.playerBId != null
                                  ? _deckRaces[m.playerBId]
                                  : null,
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}

class _RoundStanding {
  final String id;
  final String name;
  int played = 0, won = 0, lost = 0, draw = 0, pts = 0, favor = 0, against = 0;
  _RoundStanding({required this.id, required this.name});
  int get diff => favor - against;
}
