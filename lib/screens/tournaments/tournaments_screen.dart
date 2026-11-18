// lib/screens/tournaments/tournaments_screen.dart
//
// Lista de torneos (abiertos y míos), unirse con código y crear/editar.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../domain/torneo/torneo.dart';
import '../../models/current_user.dart';
import '../../models/torneo.dart';
import '../../services/tournament_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_state_view.dart';
import '../leagues/models.dart' show RoundFormat;

String fechaCorta(DateTime? f) {
  if (f == null) return 'Sin fecha';
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(f.day)}/${dos(f.month)}/${f.year} · ${dos(f.hour)}:${dos(f.minute)}';
}

Color colorEstado(String estado) {
  switch (estado) {
    case EstadoTorneo.suizo:
    case EstadoTorneo.top:
      return AppColors.warning;
    case EstadoTorneo.finalizado:
      return AppColors.textFaint;
    default:
      return AppColors.success;
  }
}

class TournamentsScreen extends StatelessWidget {
  const TournamentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final servicio = TournamentService();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Torneos'),
          actions: [
            IconButton(
              tooltip: 'Unirme con código',
              icon: const Icon(Icons.vpn_key_outlined),
              onPressed: () => _unirmeConCodigo(context, servicio),
            ),
          ],
          bottom: const TabBar(
            tabs: [Tab(text: 'Abiertos'), Tab(text: 'Mis torneos')],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _crear(context),
          icon: const Icon(Icons.add),
          label: const Text('Crear torneo'),
        ),
        body: TabBarView(
          children: [
            _Lista(
              stream: servicio.abiertos(),
              uid: uid,
              vacio: 'No hay torneos abiertos por ahora.',
            ),
            // Los que organizo y los que juego, sin duplicados.
            StreamBuilder<List<Torneo>>(
              stream: servicio.queOrganizo(uid),
              builder:
                  (context, organizo) => _Lista(
                    stream: servicio.dondeJuego(uid),
                    extra: organizo.data ?? const [],
                    uid: uid,
                    vacio:
                        'Aún no organizas ni juegas ningún torneo. Crea uno o '
                        'inscríbete en uno abierto.',
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _crear(BuildContext context) async {
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const TournamentFormScreen()),
    );
    if (id != null && context.mounted) context.push('/torneos/$id');
  }

  Future<void> _unirmeConCodigo(
    BuildContext context,
    TournamentService servicio,
  ) async {
    final ctrl = TextEditingController();
    final codigo = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Unirme con código'),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: 'Código de 6 caracteres',
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text),
                child: const Text('Buscar'),
              ),
            ],
          ),
    );
    if (codigo == null || codigo.trim().isEmpty || !context.mounted) return;
    final torneo = await servicio.porCodigo(codigo);
    if (!context.mounted) return;
    if (torneo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay un torneo con ese código.')),
      );
      return;
    }
    context.push('/torneos/${torneo.id}');
  }
}

class _Lista extends StatelessWidget {
  final Stream<List<Torneo>> stream;
  final List<Torneo> extra;
  final String uid;
  final String vacio;

  const _Lista({
    required this.stream,
    required this.uid,
    required this.vacio,
    this.extra = const [],
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Torneo>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) return ErrorStateView(error: snap.error);
        if (!snap.hasData) {
          return const LoadingStateView(message: 'Cargando torneos…');
        }
        final porId = {
          for (final t in [...extra, ...snap.data!]) t.id: t,
        };
        // En curso primero, luego próximos por fecha y al final los cerrados.
        int grupo(Torneo t) =>
            t.finalizado
                ? 2
                : t.enInscripcion
                ? 1
                : 0;
        final torneos =
            porId.values.toList()..sort((a, b) {
              final g = grupo(a).compareTo(grupo(b));
              if (g != 0) return g;
              final fa = a.fecha ?? DateTime(2100), fb = b.fecha ?? DateTime(2100);
              return a.finalizado ? fb.compareTo(fa) : fa.compareTo(fb);
            });
        if (torneos.isEmpty) {
          return EmptyStateView(
            icon: Icons.emoji_events_outlined,
            title: 'Sin torneos',
            message: vacio,
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: torneos.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _TorneoCard(torneo: torneos[i], uid: uid),
        );
      },
    );
  }
}

class _TorneoCard extends StatelessWidget {
  final Torneo torneo;
  final String uid;

  const _TorneoCard({required this.torneo, required this.uid});

  @override
  Widget build(BuildContext context) {
    final t = torneo;
    final inscritos = t.playerUids.length;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/torneos/${t.id}'),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t.nombre,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  EtiquetaEstado(estado: t.estado),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                [
                  fechaCorta(t.fecha),
                  if (t.lugar.isNotEmpty) t.lugar,
                ].join(' · '),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _Dato(
                    Icons.style_outlined,
                    RoundFormat.fromKey(t.formato).label,
                  ),
                  _Dato(
                    Icons.people_alt_outlined,
                    t.cupo > 0
                        ? '$inscritos de ${t.cupo} inscritos'
                        : '$inscritos inscrito${inscritos == 1 ? '' : 's'}',
                  ),
                  if (t.esOrganizador(uid))
                    const _Dato(Icons.shield_outlined, 'Organizas'),
                  if (t.participa(uid))
                    const _Dato(Icons.check_circle_outline, 'Inscrito'),
                  if (t.finalizado && t.campeonNombre.isNotEmpty)
                    _Dato(Icons.emoji_events_outlined, t.campeonNombre),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EtiquetaEstado extends StatelessWidget {
  final String estado;
  const EtiquetaEstado({super.key, required this.estado});

  @override
  Widget build(BuildContext context) {
    final color = colorEstado(estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .5)),
      ),
      child: Text(
        EstadoTorneo.etiqueta(estado),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  final IconData icon;
  final String texto;
  const _Dato(this.icon, this.texto);

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: AppColors.gold),
      const SizedBox(width: 4),
      Text(
        texto,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
    ],
  );
}

// ── Crear / editar ───────────────────────────────────────────────────────────

class TournamentFormScreen extends StatefulWidget {
  /// null = torneo nuevo.
  final Torneo? torneo;
  const TournamentFormScreen({super.key, this.torneo});

  @override
  State<TournamentFormScreen> createState() => _TournamentFormScreenState();
}

class _TournamentFormScreenState extends State<TournamentFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.torneo?.nombre);
  late final _descripcion = TextEditingController(
    text: widget.torneo?.descripcion,
  );
  late final _lugar = TextEditingController(text: widget.torneo?.lugar);
  late final _cupo = TextEditingController(
    text: (widget.torneo?.cupo ?? 0) > 0 ? '${widget.torneo!.cupo}' : '',
  );
  late DateTime _fecha =
      widget.torneo?.fecha ??
      DateTime.now().add(const Duration(days: 7)).copyWith(
        hour: 15,
        minute: 0,
        second: 0,
        millisecond: 0,
        microsecond: 0,
      );
  late RoundFormat _formato = RoundFormat.fromKey(widget.torneo?.formato);
  late String _visibilidad = widget.torneo?.visibilidad ?? 'open';
  late int _rondas = widget.torneo?.rondasSuizas ?? 0;
  late int _top = widget.torneo?.topCut ?? 4;
  bool _guardando = false;

  bool get _editando => widget.torneo != null;
  bool get _estructuraFija => _editando && !widget.torneo!.enInscripcion;
  bool get _formatoFijo => _editando && widget.torneo!.playerUids.isNotEmpty;

  @override
  void dispose() {
    _nombre.dispose();
    _descripcion.dispose();
    _lugar.dispose();
    _cupo.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha() async {
    final dia = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (dia == null || !mounted) return;
    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_fecha),
    );
    if (!mounted) return;
    setState(
      () =>
          _fecha = DateTime(
            dia.year,
            dia.month,
            dia.day,
            hora?.hour ?? _fecha.hour,
            hora?.minute ?? _fecha.minute,
          ),
    );
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    final usuario = context.read<CurrentUser>();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _guardando = true);
    final servicio = TournamentService();
    final cupo = int.tryParse(_cupo.text.trim()) ?? 0;
    try {
      String? id;
      if (_editando) {
        await servicio.editar(
          widget.torneo!,
          nombre: _nombre.text,
          descripcion: _descripcion.text,
          lugar: _lugar.text,
          fecha: _fecha,
          formato: _formato.firestoreKey,
          visibilidad: _visibilidad,
          rondasSuizas: _rondas,
          topCut: _top,
          cupo: cupo,
        );
      } else {
        id = await servicio.crear(
          ownerUid: uid,
          ownerNombre: usuario.displayName ?? usuario.email ?? 'Organizador',
          nombre: _nombre.text,
          descripcion: _descripcion.text,
          lugar: _lugar.text,
          fecha: _fecha,
          formato: _formato.firestoreKey,
          visibilidad: _visibilidad,
          rondasSuizas: _rondas,
          topCut: _top,
          cupo: cupo,
        );
      }
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
      setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cupo = int.tryParse(_cupo.text.trim()) ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar torneo' : 'Crear torneo')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  controller: _nombre,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  textCapitalization: TextCapitalization.sentences,
                  validator:
                      (v) =>
                          (v ?? '').trim().length < 3
                              ? 'Escribe un nombre (mínimo 3 letras)'
                              : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _lugar,
                  decoration: const InputDecoration(
                    labelText: 'Lugar',
                    hintText: 'Tienda, dirección o «en línea»',
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Fecha y hora'),
                  subtitle: Text(fechaCorta(_fecha)),
                  trailing: TextButton(
                    onPressed: _elegirFecha,
                    child: const Text('Cambiar'),
                  ),
                ),
                const SizedBox(height: 4),
                DropdownButtonFormField<RoundFormat>(
                  initialValue: _formato,
                  decoration: InputDecoration(
                    labelText: 'Formato',
                    helperText:
                        _formatoFijo
                            ? 'No se puede cambiar con jugadores inscritos.'
                            : 'Se congela la Ban List vigente de este formato.',
                  ),
                  items: [
                    for (final f in RoundFormat.values)
                      DropdownMenuItem(value: f, child: Text(f.label)),
                  ],
                  onChanged:
                      _formatoFijo
                          ? null
                          : (v) => setState(() => _formato = v ?? _formato),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _rondas,
                  decoration: InputDecoration(
                    labelText: 'Rondas suizas',
                    helperText:
                        _rondas == 0 && cupo > 1
                            ? 'Con $cupo jugadores serían ${rondasSugeridas(cupo)} rondas.'
                            : null,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 0,
                      child: Text('Automático, según los inscritos'),
                    ),
                    for (var i = 2; i <= 8; i++)
                      DropdownMenuItem(value: i, child: Text('$i rondas')),
                  ],
                  onChanged:
                      _estructuraFija
                          ? null
                          : (v) => setState(() => _rondas = v ?? 0),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _top,
                  decoration: const InputDecoration(
                    labelText: 'Eliminación directa después del suizo',
                    helperText:
                        'Si hay menos jugadores que el top, se reduce solo.',
                  ),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Sin top')),
                    DropdownMenuItem(value: 2, child: Text('Final (top 2)')),
                    DropdownMenuItem(value: 4, child: Text('Top 4')),
                    DropdownMenuItem(value: 8, child: Text('Top 8')),
                  ],
                  onChanged:
                      _estructuraFija
                          ? null
                          : (v) => setState(() => _top = v ?? 0),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cupo,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Cupo máximo (opcional)',
                    hintText: 'Vacío = sin límite',
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    final texto = (v ?? '').trim();
                    if (texto.isEmpty) return null;
                    final n = int.tryParse(texto);
                    if (n == null || n < 2 || n > 256) {
                      return 'Entre 2 y 256 jugadores';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'open',
                      icon: Icon(Icons.public),
                      label: Text('Abierto'),
                    ),
                    ButtonSegment(
                      value: 'invite',
                      icon: Icon(Icons.vpn_key_outlined),
                      label: Text('Con código'),
                    ),
                  ],
                  selected: {_visibilidad},
                  onSelectionChanged:
                      (s) => setState(() => _visibilidad = s.first),
                ),
                const SizedBox(height: 6),
                Text(
                  _visibilidad == 'open'
                      ? 'Aparece en la lista de torneos abiertos.'
                      : 'No aparece en la lista: se entra con el código o el enlace.',
                  style: const TextStyle(
                    color: AppColors.textFaint,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descripcion,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Descripción',
                    hintText: 'Valor de la inscripción, premios, horarios…',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon:
                      _guardando
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.check),
                  label: Text(_editando ? 'Guardar cambios' : 'Crear torneo'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Cada jugador se inscribe con su cuenta y un mazo válido. '
                  'Los duelos son al mejor de 3: victoria 3 puntos, empate 1.',
                  style: TextStyle(color: AppColors.textFaint, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
