part of '../deck_details_screen.dart';

class _CardZoomDialog extends StatelessWidget {
  final String heroTag;
  final _DeckVisualCard visualCard;
  final CardMyL? fullCard;

  const _CardZoomDialog({
    required this.heroTag,
    required this.visualCard,
    this.fullCard,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Hero(
                    tag: heroTag,
                    child: Container(
                      constraints: const BoxConstraints(
                        maxHeight: 500,
                        maxWidth: 350,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFD9A323).withOpacity(0.3),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child:
                            visualCard.imageUrl.isNotEmpty
                                ? Image.network(
                                  DriveService.webSafeUrl(visualCard.imageUrl),
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => _zoomFallback(),
                                )
                                : _zoomFallback(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 400),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1E),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: const Color(0xFFD9A323).withOpacity(0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          visualCard.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _infoBadge(
                              visualCard.tipo.toUpperCase(),
                              const Color(0xFFF1D184),
                            ),
                            if (fullCard?.raza != null) ...[
                              const SizedBox(width: 8),
                              _infoBadge(fullCard!.raza!, Colors.white24),
                            ],
                            const Spacer(),
                            if (visualCard.cost > 0 ||
                                visualCard.tipo.toLowerCase() != 'oro')
                              _statCircle(
                                visualCard.cost.toString(),
                                Icons.local_fire_department,
                                "Coste",
                              ),
                            if (fullCard?.fuerza != null) ...[
                              const SizedBox(width: 12),
                              _statCircle(
                                fullCard!.fuerza.toString(),
                                Icons.fitness_center,
                                "Fuerza",
                              ),
                            ],
                          ],
                        ),
                        const Divider(color: Colors.white10, height: 32),
                        if (fullCard?.habilidad != null &&
                            fullCard!.habilidad.isNotEmpty) ...[
                          const Text(
                            "HABILIDAD",
                            style: TextStyle(
                              color: Color(0xFFF1D184),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            fullCard!.habilidad,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 15,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white54),
                    label: const Text(
                      "CERRAR",
                      style: TextStyle(
                        color: Colors.white54,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _statCircle(String val, IconData icon, String label) {
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: Color(0xFF2A2A30),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              val,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Icon(icon, size: 12, color: Colors.white38),
      ],
    );
  }

  Widget _fallback() {
    return Container(
      color: const Color(0xFF232833),
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_not_supported,
        color: Colors.white54,
        size: 64,
      ),
    );
  }

  /// Cuando la carta no tiene variante asignada, usa el resolver del catálogo
  /// para mostrar la mejor variante disponible en el zoom.
  Widget _zoomFallback() {
    if (visualCard.cardId.isEmpty) return _fallback();
    return AspectRatio(
      aspectRatio: 63 / 88,
      child: VariantThumbFromCard(
        cardId: visualCard.cardId,
        fallbackTipo: visualCard.tipo,
        size: 350,
      ),
    );
  }
}

// ─── Diálogo de asignación de variante por copia ───────────────────────────
// Ver PerCopyVariantDialog en widgets/per_copy_variant_dialog.dart —
// reutilizado también desde Inventario para declarar variantes.

// ─── Simulador de mano inicial (#13) ─────────────────────────────────────────

class _HandSimulatorDialog extends StatefulWidget {
  final List<MapEntry<String, String>> pool; // (nombre, url) por copia

  const _HandSimulatorDialog({required this.pool});

  @override
  State<_HandSimulatorDialog> createState() => _HandSimulatorDialogState();
}

class _HandSimulatorDialogState extends State<_HandSimulatorDialog> {
  static const int _handSize = 8;
  late List<MapEntry<String, String>> _hand;
  int _draws = 0;

  @override
  void initState() {
    super.initState();
    _draw();
  }

  void _draw() {
    final shuffled = [...widget.pool]..shuffle(math.Random());
    _hand = shuffled.take(_handSize).toList();
    _draws++;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF12161D),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.back_hand_rounded, color: Color(0xFFF1D48B)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Mano de prueba  ·  robo #$_draws',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, c) {
                  final cardW = (c.maxWidth - 3 * 8) / 4;
                  final w = cardW.clamp(70.0, 150.0);
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children:
                        _hand.map((e) {
                          return SizedBox(
                            width: w,
                            child: Column(
                              children: [
                                AspectRatio(
                                  aspectRatio: 63 / 88,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child:
                                        e.value.isNotEmpty
                                            ? Image.network(
                                              DriveService.webSafeUrl(e.value),
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (_, __, ___) => Container(
                                                    color: const Color(
                                                      0xFF232833,
                                                    ),
                                                    alignment: Alignment.center,
                                                    child: const Icon(
                                                      Icons.image_not_supported,
                                                      color: Colors.white38,
                                                    ),
                                                  ),
                                            )
                                            : Container(
                                              color: const Color(0xFF232833),
                                              alignment: Alignment.center,
                                              padding: const EdgeInsets.all(6),
                                              child: Text(
                                                e.key,
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  e.key,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                  );
                },
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cerrar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF1D48B),
                      foregroundColor: const Color(0xFF14181F),
                    ),
                    onPressed: () => setState(_draw),
                    icon: const Icon(Icons.casino_rounded, size: 18),
                    label: const Text('Robar otra mano'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Registro de partida (#14) ───────────────────────────────────────────────

class _MatchResult {
  final bool won;
  final String score; // 2-0, 2-1, 1-2, 0-2
  final String? opponentRace;
  final String? notes;

  const _MatchResult({
    required this.won,
    required this.score,
    this.opponentRace,
    this.notes,
  });
}

class _RegisterMatchDialog extends StatefulWidget {
  final Deck deck;

  const _RegisterMatchDialog({required this.deck});

  @override
  State<_RegisterMatchDialog> createState() => _RegisterMatchDialogState();
}

class _RegisterMatchDialogState extends State<_RegisterMatchDialog> {
  String _score = '2-0';
  String? _opponentRace;
  final _notesCtrl = TextEditingController();

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  bool get _won => _score.startsWith('2');

  @override
  Widget build(BuildContext context) {
    final deck = widget.deck;
    return AlertDialog(
      backgroundColor: const Color(0xFF12161D),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.emoji_events_rounded, color: Color(0xFFF1D48B)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Registrar partida',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: math.min(380, MediaQuery.of(context).size.width - 96),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (deck.games > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Récord actual: ${deck.wins}W / ${deck.losses}L  ·  ${deck.winRateLabel}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            const Text(
              'Resultado',
              style: TextStyle(
                color: Color(0xFFF2D487),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children:
                  ['2-0', '2-1', '1-2', '0-2'].map((s) {
                    final sel = s == _score;
                    final win = s.startsWith('2');
                    return ChoiceChip(
                      label: Text(
                        win ? '🏆 $s' : '💀 $s',
                        style: TextStyle(
                          color: sel ? const Color(0xFF14181F) : Colors.white70,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      selected: sel,
                      selectedColor:
                          win
                              ? const Color(0xFFF1D48B)
                              : const Color(0xFFE57373),
                      backgroundColor: const Color(0xFF0E1117),
                      onSelected: (_) => setState(() => _score = s),
                    );
                  }).toList(),
            ),
            const SizedBox(height: 14),
            const Text(
              'Raza rival (opcional)',
              style: TextStyle(
                color: Color(0xFFF2D487),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _opponentRace,
              isExpanded: true,
              dropdownColor: const Color(0xFF1A212C),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              items: [
                const DropdownMenuItem<String>(value: null, child: Text('—')),
                ...PBData.todasLasRazas.map(
                  (r) => DropdownMenuItem(value: r, child: Text(r)),
                ),
              ],
              onChanged: (v) => setState(() => _opponentRace = v),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _notesCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
                hintText: 'ej: torneo tienda, mal robo de oros…',
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFF1D48B),
            foregroundColor: const Color(0xFF14181F),
          ),
          onPressed:
              () => Navigator.pop(
                context,
                _MatchResult(
                  won: _won,
                  score: _score,
                  opponentRace: _opponentRace,
                  notes:
                      _notesCtrl.text.trim().isEmpty
                          ? null
                          : _notesCtrl.text.trim(),
                ),
              ),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

/// Checklist embebido del plan generado por "Generar plan para armar este
/// mazo". Cuando [offerReturn] es true y el plan queda listo para devolver
/// (todos los movimientos aplicados), se ofrece devolver las copias a sus
/// mazos originales sin salir de este diálogo.
class _AssemblyPlanDialog extends StatefulWidget {
  final InventoryService service;
  final String planId;
  final Map<String, String> deckNames;
  final bool offerReturn;

  const _AssemblyPlanDialog({
    required this.service,
    required this.planId,
    required this.deckNames,
    required this.offerReturn,
  });

  @override
  State<_AssemblyPlanDialog> createState() => _AssemblyPlanDialogState();
}

class _AssemblyPlanDialogState extends State<_AssemblyPlanDialog> {
  bool _autoKeepTriggered = false;
  bool _applyingAll = false;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _applyMove(TransferPlan plan, TransferMove move) async {
    try {
      await widget.service.applyMove(plan, move);
    } catch (error) {
      _snack('$error');
    }
  }

  /// Aplica todos los movimientos pendientes en orden, sin que el usuario
  /// tenga que marcarlos uno por uno. Relee el plan tras cada paso porque
  /// applyMove valida contra el estado vivo en Firestore.
  Future<void> _applyAllMoves(TransferPlan plan) async {
    if (_applyingAll) return;
    setState(() => _applyingAll = true);
    try {
      var current = plan;
      while (true) {
        final next = current.moves.firstWhereOrNull(
          (m) => m.status == TransferMoveStatus.pending,
        );
        if (next == null) break;
        try {
          await widget.service.applyMove(current, next);
        } catch (error) {
          _snack('$error');
          break;
        }
        final refreshed = await widget.service.watchPlans().first.then(
          (plans) => plans.where((p) => p.id == plan.id).firstOrNull,
        );
        if (refreshed == null) break;
        current = refreshed;
      }
    } finally {
      if (mounted) setState(() => _applyingAll = false);
    }
  }

  Future<void> _returnMove(TransferPlan plan, TransferMove move) async {
    try {
      await widget.service.returnMove(plan, move);
    } catch (error) {
      _snack('$error');
    }
  }

  Future<void> _keepPlan(TransferPlan plan) async {
    await widget.service.keepPlan(plan.id);
    if (mounted) _snack('Distribución conservada.');
  }

  Future<void> _cancelPlan(TransferPlan plan) async {
    if (plan.moves.any((move) => move.status == TransferMoveStatus.applied)) {
      _snack(
        'Devuelve primero los movimientos aplicados o conserva la distribución actual.',
      );
      return;
    }
    await widget.service.cancelUnusedPlan(plan.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF12161D),
      title: const Text(
        'Plan para armar el mazo',
        style: TextStyle(color: Colors.white),
      ),
      content: SizedBox(
        width: 480,
        child: StreamBuilder<List<TransferPlan>>(
          stream: widget.service.watchPlans(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(
                '${snapshot.error}',
                style: const TextStyle(color: Color(0xFFFF7777)),
              );
            }
            if (!snapshot.hasData) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            final plan =
                snapshot.data!.where((p) => p.id == widget.planId).firstOrNull;
            if (plan == null) {
              return const Text(
                'El plan ya no existe.',
                style: TextStyle(color: Colors.white60),
              );
            }
            final closed = {
              TransferPlanStatus.returned,
              TransferPlanStatus.kept,
              TransferPlanStatus.cancelled,
            }.contains(plan.status);
            final readyToReturn =
                plan.status == TransferPlanStatus.readyToReturn;
            if (readyToReturn && !widget.offerReturn && !_autoKeepTriggered) {
              _autoKeepTriggered = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _keepPlan(plan);
              });
            }
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (readyToReturn)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        widget.offerReturn
                            ? 'Mazo armado. Puedes devolver las copias prestadas marcando cada movimiento, o conservar esta distribución.'
                            : 'Mazo armado.',
                        style: const TextStyle(color: Color(0xFF75D69C)),
                      ),
                    ),
                  TransferPlanChecklist(
                    plan: plan,
                    deckNames: widget.deckNames,
                    onApply: _applyMove,
                    onReturn: _returnMove,
                    onKeep: closed ? null : _keepPlan,
                    onCancel: closed ? null : _cancelPlan,
                    onApplyAll: closed ? null : _applyAllMoves,
                    applyingAll: _applyingAll,
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

/// Resultado de [_SourceSelectionDialog]: cuánto tomar del stock libre (se
/// aplica siempre, no interviene ningún otro mazo) y, por carta, de qué
/// mazos y cuánto sacar según eligió el usuario.
class _SourceSelection {
  final Map<String, int> freeAmountByCard;
  final Map<String, List<(String deckId, int quantity)>> sourcesByCard;
  const _SourceSelection({
    required this.freeAmountByCard,
    required this.sourcesByCard,
  });
}

/// Antes de generar el plan, muestra qué le falta al mazo y deja elegir de
/// qué mazos sacar cada carta que el stock libre no alcanza a cubrir. Nunca
/// decide solo: si hay varios mazos candidatos, el usuario reparte cuánto
/// sacar de cada uno con un stepper.
class _SourceSelectionDialog extends StatefulWidget {
  final List<MissingCardWithSources> missing;
  const _SourceSelectionDialog({required this.missing});

  @override
  State<_SourceSelectionDialog> createState() => _SourceSelectionDialogState();
}

class _SourceSelectionDialogState extends State<_SourceSelectionDialog> {
  // cardKey -> deckId -> cantidad elegida
  final Map<String, Map<String, int>> _picked = {};

  int _pickedFor(String cardKey, String deckId) =>
      _picked[cardKey]?[deckId] ?? 0;

  int _pickedTotal(String cardKey) =>
      (_picked[cardKey] ?? const {}).values.fold(0, (a, b) => a + b);

  void _setPicked(MissingCardWithSources entry, String deckId, int value) {
    final stillMissing = entry.missing - entry.coveredByFree;
    final othersPicked =
        _pickedTotal(entry.cardKey) - _pickedFor(entry.cardKey, deckId);
    final room = (stillMissing - othersPicked).clamp(0, entry.missing);
    setState(() {
      final byDeck = _picked.putIfAbsent(entry.cardKey, () => {});
      byDeck[deckId] = value.clamp(0, room);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF12161D),
      title: const Text(
        'Elige de dónde sacar las copias',
        style: TextStyle(color: Colors.white),
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in widget.missing) ...[
                Text(
                  entry.cardName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (entry.coveredByFree > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${entry.coveredByFree} de tu stock libre (automático).',
                      style: const TextStyle(
                        color: Color(0xFF75D69C),
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (entry.missing - entry.coveredByFree > 0) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Faltan ${entry.missing - entry.coveredByFree} más. '
                      '${entry.sources.isEmpty ? 'Ningún otro mazo tiene copias.' : 'Elige de dónde sacarlas:'}',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  for (final source in entry.sources)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${source.deckName} (tiene ${source.available})',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          IconButton(
                            iconSize: 18,
                            onPressed:
                                _pickedFor(entry.cardKey, source.deckId) <= 0
                                    ? null
                                    : () => _setPicked(
                                      entry,
                                      source.deckId,
                                      _pickedFor(entry.cardKey, source.deckId) -
                                          1,
                                    ),
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              color: Colors.white54,
                            ),
                          ),
                          Text(
                            '${_pickedFor(entry.cardKey, source.deckId)}',
                            style: const TextStyle(color: Colors.white),
                          ),
                          IconButton(
                            iconSize: 18,
                            onPressed:
                                _pickedFor(entry.cardKey, source.deckId) >=
                                        source.available
                                    ? null
                                    : () => _setPicked(
                                      entry,
                                      source.deckId,
                                      _pickedFor(entry.cardKey, source.deckId) +
                                          1,
                                    ),
                            icon: const Icon(
                              Icons.add_circle_outline,
                              color: Color(0xFFF1D48B),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final freeAmountByCard = {
              for (final entry in widget.missing)
                entry.cardKey: entry.coveredByFree,
            };
            final sourcesByCard = {
              for (final entry in widget.missing)
                entry.cardKey: [
                  for (final source in entry.sources)
                    if (_pickedFor(entry.cardKey, source.deckId) > 0)
                      (source.deckId, _pickedFor(entry.cardKey, source.deckId)),
                ],
            };
            Navigator.pop(
              context,
              _SourceSelection(
                freeAmountByCard: freeAmountByCard,
                sourcesByCard: sourcesByCard,
              ),
            );
          },
          child: const Text('Generar plan'),
        ),
      ],
    );
  }
}

/// Se abre al tocar una copia gris de una carta del mazo: muestra primero lo
/// que ya se tiene registrado (para no declarar copias que el sistema ya
/// conoce), y pide cuántas copias nuevas hay y de qué variante cada una.
/// Devuelve un mapa variantId ('' = sin variante) -> cantidad.
class _AddOwnedCopiesDialog extends StatefulWidget {
  final String cardName;
  final List<CardVariant> variants;
  final ExistingCardHolding holding;

  const _AddOwnedCopiesDialog({
    required this.cardName,
    required this.variants,
    required this.holding,
  });

  @override
  State<_AddOwnedCopiesDialog> createState() => _AddOwnedCopiesDialogState();
}

class _AddOwnedCopiesDialogState extends State<_AddOwnedCopiesDialog> {
  int _quantity = 1;

  String _variantLabel(String variantId) {
    if (variantId.isEmpty) return 'Sin variante identificada';
    final variant = widget.variants.where((v) => v.id == variantId).firstOrNull;
    return variant?.printType ?? 'Variante';
  }

  @override
  Widget build(BuildContext context) {
    final holding = widget.holding;
    return AlertDialog(
      backgroundColor: const Color(0xFF12161D),
      title: Text(
        '¿Cuántas tienes de "${widget.cardName}"?',
        style: const TextStyle(color: Colors.white),
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (holding.hasAny) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ya tienes ${holding.total} en total'
                        '${holding.free > 0 ? ' (${holding.free} libres)' : ''}:',
                        style: const TextStyle(
                          color: Color(0xFFF1D48B),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final entry in holding.byVariant.entries)
                        Text(
                          '${entry.value}x ${_variantLabel(entry.key)}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      if (holding.byDeck.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        for (final d in holding.byDeck)
                          Text(
                            '${d.quantity}x en ${d.deckName}',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Text(
                holding.hasAny ? '¿Cuántas MÁS tienes ahora?' : 'Cantidad',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed:
                        _quantity <= 1
                            ? null
                            : () => setState(() => _quantity--),
                    icon: const Icon(
                      Icons.remove_circle_outline,
                      color: Colors.white70,
                    ),
                  ),
                  Text(
                    '$_quantity',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _quantity++),
                    icon: const Icon(
                      Icons.add_circle_outline,
                      color: Color(0xFFF1D48B),
                    ),
                  ),
                ],
              ),
              if (widget.variants.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Se agregan sin variante identificada. Puedes elegir de '
                    'qué versión es cada una después, desde "Asignar variante '
                    'por copia" en el menú de la carta.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(.5),
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, <String, int>{'': _quantity}),
          child: Text('Agregar $_quantity copia${_quantity == 1 ? '' : 's'}'),
        ),
      ],
    );
  }
}

/// "En realidad no tengo tantas": deja bajar la cantidad total de una carta
/// por debajo de lo que el inventario tiene asignado a mazos, algo que el
/// editor de cantidad de /inventario no permite. Muestra cuánto se le
/// quitará al mazo actual (y a otros, si no alcanza con solo este) antes de
/// confirmar.
class _CorrectQuantityDialog extends StatefulWidget {
  final String cardName;
  final InventoryItem item;

  const _CorrectQuantityDialog({required this.cardName, required this.item});

  @override
  State<_CorrectQuantityDialog> createState() => _CorrectQuantityDialogState();
}

class _CorrectQuantityDialogState extends State<_CorrectQuantityDialog> {
  late int _newTotal = widget.item.total;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final removedFromDecks = (item.assigned + item.reserved - _newTotal).clamp(
      0,
      item.assigned,
    );
    return AlertDialog(
      backgroundColor: const Color(0xFF12161D),
      title: Text(
        '¿Cuántas copias tienes de "${widget.cardName}"?',
        style: const TextStyle(color: Colors.white),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'El inventario dice ${item.total} (${item.assigned} en mazos'
            '${item.reserved > 0 ? ', ${item.reserved} reservadas en publicaciones' : ''}'
            '${item.free > 0 ? ', ${item.free} libres' : ''}).',
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed:
                    _newTotal <= 0 ? null : () => setState(() => _newTotal--),
                icon: const Icon(
                  Icons.remove_circle_outline,
                  color: Colors.white70,
                ),
              ),
              Text(
                '$_newTotal',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _newTotal++),
                icon: const Icon(
                  Icons.add_circle_outline,
                  color: Color(0xFFF1D48B),
                ),
              ),
            ],
          ),
          if (removedFromDecks > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Se quitarán $removedFromDecks copia${removedFromDecks == 1 ? '' : 's'} de tus mazos '
                '(empezando por este). Esas cartas volverán a aparecer en gris.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFF1D48B), fontSize: 12),
              ),
            ),
          if (_newTotal < item.reserved)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Tienes ${item.reserved} reservadas en publicaciones: cancela esa publicación antes de bajar de ahí.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFFF7777), fontSize: 12),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed:
              _newTotal == item.total || _newTotal < item.reserved
                  ? null
                  : () => Navigator.pop(context, _newTotal),
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}
