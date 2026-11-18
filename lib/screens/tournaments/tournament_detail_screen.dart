// lib/screens/tournaments/tournament_detail_screen.dart
//
// Un torneo: inscripción, rondas, tabla, llave y meta. El organizador lo
// conduce desde aquí; cada jugador carga su resultado y el rival lo confirma.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../domain/torneo/torneo.dart';
import '../../models/current_user.dart';
import '../../models/torneo.dart';
import '../../services/tournament_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_state_view.dart';
import '../leagues/models.dart' show RoundFormat;
import '../leagues/round_ban_list_viewer.dart';
import 'tournament_widgets.dart';
import 'tournaments_screen.dart';

class TournamentDetailScreen extends StatelessWidget {
  final String torneoId;
  const TournamentDetailScreen({super.key, required this.torneoId});

  @override
  Widget build(BuildContext context) {
    final servicio = TournamentService();
    return StreamBuilder<Torneo?>(
      stream: servicio.torneo(torneoId),
      builder: (context, st) {
        if (st.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Torneo')),
            body: ErrorStateView(error: st.error),
          );
        }
        if (st.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: LoadingStateView(message: 'Cargando torneo…'),
          );
        }
        final torneo = st.data;
        if (torneo == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Torneo')),
            body: EmptyStateView(
              icon: Icons.emoji_events_outlined,
              title: 'Este torneo no existe',
              message: 'Puede que el organizador lo haya borrado.',
              actionLabel: 'Ver torneos',
              onAction: () => context.go('/torneos'),
            ),
          );
        }
        return StreamBuilder<List<Inscrito>>(
          stream: servicio.inscritos(torneoId),
          builder:
              (context, si) => StreamBuilder<List<DueloDoc>>(
                stream: servicio.duelos(torneoId),
                builder:
                    (context, sd) => _Detalle(
                      servicio: servicio,
                      torneo: torneo,
                      inscritos: si.data ?? const [],
                      duelos: sd.data ?? const [],
                    ),
              ),
        );
      },
    );
  }
}

class _Detalle extends StatefulWidget {
  final TournamentService servicio;
  final Torneo torneo;
  final List<Inscrito> inscritos;
  final List<DueloDoc> duelos;

  const _Detalle({
    required this.servicio,
    required this.torneo,
    required this.inscritos,
    required this.duelos,
  });

  @override
  State<_Detalle> createState() => _DetalleState();
}

class _DetalleState extends State<_Detalle> {
  bool _ocupado = false;

  Torneo get t => widget.torneo;
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  bool get _organizo => t.esOrganizador(_uid);

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  /// Ejecuta una acción mostrando el error en palabras simples.
  Future<void> _hacer(Future<String?> Function() accion) async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      final mensaje = await accion();
      if (mensaje != null) _aviso(mensaje);
    } on TorneoError catch (e) {
      _aviso(e.mensaje);
    } catch (e) {
      _aviso('No se pudo completar: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<bool> _confirmar(String titulo, String texto, String accion) async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(titulo),
            content: Text(texto),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(accion),
              ),
            ],
          ),
    );
    return ok == true;
  }

  // ── Acciones del jugador ──────────────────────────────────────────────────
  Future<void> _inscribirme() async {
    final uid = _uid;
    if (uid == null) return;
    final usuario = context.read<CurrentUser>();
    final deck = await elegirMazoParaTorneo(context, t);
    if (deck == null) return;
    await _hacer(() async {
      await widget.servicio.inscribir(
        torneoId: t.id,
        uid: uid,
        nombre: usuario.displayName ?? usuario.email ?? 'Jugador',
        deck: deck,
      );
      return 'Inscrito con «${deck.name}»';
    });
  }

  Future<void> _salir() async {
    if (!await _confirmar(
      'Salir del torneo',
      'Se borrará tu inscripción. Podrás volver a inscribirte mientras la '
          'inscripción siga abierta.',
      'Salir',
    )) {
      return;
    }
    await _hacer(() async {
      await widget.servicio.desinscribir(t.id, _uid!);
      return 'Saliste del torneo';
    });
  }

  Future<void> _reportar(DueloDoc d) async {
    final marcador = await pedirMarcador(
      context,
      duelo: d,
      permiteEmpate: d.fase != 'top',
    );
    if (marcador == null) return;
    await _hacer(() async {
      await widget.servicio.reportar(
        torneoId: t.id,
        duelo: d,
        scoreA: marcador.$1,
        scoreB: marcador.$2,
        uid: _uid!,
        // El organizador que no juega el duelo lo deja confirmado.
        organizador: _organizo && !d.juega(_uid),
      );
      return _organizo && !d.juega(_uid)
          ? 'Resultado guardado'
          : 'Resultado cargado. Falta que tu rival lo confirme.';
    });
  }

  Future<void> _confirmarDuelo(DueloDoc d) => _hacer(() async {
    await widget.servicio.confirmar(t.id, d, _uid!);
    return 'Resultado confirmado';
  });

  Future<void> _rechazarDuelo(DueloDoc d) => _hacer(() async {
    await widget.servicio.rechazar(t.id, d);
    return 'Marcador borrado. Cárguenlo de nuevo.';
  });

  // ── Acciones del organizador ──────────────────────────────────────────────
  Future<void> _iniciar() async {
    final n = widget.inscritos.length;
    final rondas = t.rondasSuizas > 0 ? t.rondasSuizas : rondasSugeridas(n);
    if (!await _confirmar(
      'Iniciar el torneo',
      'Se cierra la inscripción con $n jugadores y se genera la ronda 1 de '
          '$rondas. Después de esto nadie más puede inscribirse ni cambiar '
          'su mazo.',
      'Iniciar',
    )) {
      return;
    }
    await _hacer(() async {
      await widget.servicio.iniciar(t);
      return 'Torneo iniciado: ronda 1 generada';
    });
  }

  Future<void> _avanzar() => _hacer(() => widget.servicio.avanzar(t));

  Future<void> _editar() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => TournamentFormScreen(torneo: t)),
  );

  Future<void> _eliminar() async {
    final servicio = widget.servicio;
    final ruta = GoRouter.of(context);
    if (!await _confirmar(
      'Borrar el torneo',
      'Se borra el torneo y todas las inscripciones. No se puede deshacer.',
      'Borrar',
    )) {
      return;
    }
    await _hacer(() async {
      await servicio.eliminar(t);
      ruta.go('/torneos');
      return null;
    });
  }

  Future<void> _retirar(Inscrito i) async {
    final retirar = !i.retirado;
    if (!await _confirmar(
      retirar ? 'Retirar a ${i.nombre}' : 'Reintegrar a ${i.nombre}',
      retirar
          ? 'No se le emparejará en las rondas siguientes. Sus duelos jugados '
              'siguen contando. Si tiene un duelo abierto en esta ronda, '
              'carga antes el resultado.'
          : 'Volverá a ser emparejado desde la próxima ronda.',
      retirar ? 'Retirar' : 'Reintegrar',
    )) {
      return;
    }
    await _hacer(() async {
      await widget.servicio.retirar(t.id, i.uid, retirado: retirar);
      return retirar ? '${i.nombre} retirado' : '${i.nombre} reintegrado';
    });
  }

  Future<void> _compartir() async {
    await Clipboard.setData(
      ClipboardData(
        text:
            '${t.nombre} · ${fechaCorta(t.fecha)}\n'
            'https://mylmazos.web.app/torneos/${t.id}\n'
            'Código: ${t.codigo}',
      ),
    );
    _aviso('Enlace y código copiados');
  }

  @override
  Widget build(BuildContext context) {
    final paso = PasoTorneo.de(t, widget.inscritos, widget.duelos);
    final jugadores = [for (final i in widget.inscritos) i.jugador];
    final dominio = [for (final d in widget.duelos) d.dominio];
    final tabla = calcularTabla(jugadores, dominio);
    final hayLlave = widget.duelos.any((d) => d.fase == 'top');
    final listasVisibles = t.finalizado;

    final pestanas = <(String, Widget)>[
      (
        'Inscritos (${widget.inscritos.length})',
        InscritosTab(
          torneo: t,
          inscritos: widget.inscritos,
          uid: _uid,
          organizo: _organizo,
          listasVisibles: listasVisibles,
          onRetirar: _organizo && !t.enInscripcion && !t.finalizado ? _retirar : null,
        ),
      ),
      if (!t.enInscripcion)
        (
          'Rondas',
          RondasTab(
            torneo: t,
            duelos: widget.duelos,
            uid: _uid,
            organizo: _organizo,
            onReportar: t.finalizado ? null : _reportar,
          ),
        ),
      if (!t.enInscripcion) ('Tabla', TablaTab(tabla: tabla, uid: _uid, top: paso.top)),
      if (hayLlave) ('Llave', LlaveTab(duelos: widget.duelos)),
      if (t.finalizado)
        ('Meta', MetaTorneoTab(inscritos: widget.inscritos, tabla: tabla)),
    ];

    return DefaultTabController(
      key: ValueKey(pestanas.length),
      length: pestanas.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.nombre),
          actions: [
            IconButton(
              tooltip: 'Copiar enlace y código',
              icon: const Icon(Icons.share_outlined),
              onPressed: _compartir,
            ),
            if (_organizo)
              PopupMenuButton<String>(
                onSelected: (v) => v == 'editar' ? _editar() : _eliminar(),
                itemBuilder:
                    (_) => [
                      const PopupMenuItem(
                        value: 'editar',
                        child: Text('Editar datos'),
                      ),
                      if (t.enInscripcion)
                        const PopupMenuItem(
                          value: 'borrar',
                          child: Text('Borrar torneo'),
                        ),
                    ],
              ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: NestedScrollView(
              headerSliverBuilder:
                  (context, _) => [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _cabecera(paso),
                            const SizedBox(height: 10),
                            ..._panelJugador(paso),
                            if (_organizo) _panelOrganizador(paso),
                          ],
                        ),
                      ),
                    ),
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _BarraPestanas(
                        TabBar(
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          tabs: [for (final p in pestanas) Tab(text: p.$1)],
                        ),
                      ),
                    ),
                  ],
              body: TabBarView(children: [for (final p in pestanas) p.$2]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cabecera(PasoTorneo paso) {
    final n = widget.inscritos.length;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              EtiquetaEstado(estado: t.estado),
              const Spacer(),
              TextButton.icon(
                onPressed:
                    () => showRoundBanListViewer(
                      context,
                      roundName: t.nombre,
                      roundData: t.data,
                    ),
                icon: const Icon(Icons.shield_outlined, size: 18),
                label: const Text('Ban List'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (t.finalizado && t.campeonNombre.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.emoji_events, color: AppColors.gold),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Campeón: ${t.campeonNombre}',
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              DatoTorneo(Icons.event_outlined, fechaCorta(t.fecha)),
              if (t.lugar.isNotEmpty) DatoTorneo(Icons.place_outlined, t.lugar),
              DatoTorneo(
                Icons.style_outlined,
                RoundFormat.fromKey(t.formato).label,
              ),
              DatoTorneo(
                Icons.people_alt_outlined,
                t.cupo > 0 ? '$n de ${t.cupo} inscritos' : '$n inscritos',
              ),
              DatoTorneo(
                Icons.account_tree_outlined,
                [
                  t.enInscripcion && t.rondasSuizas == 0
                      ? 'Suizo (${n < 2 ? 'rondas según inscritos' : '${rondasSugeridas(n)} rondas con $n'})'
                      : 'Suizo de ${paso.rondasSuizas} rondas',
                  if (t.topCut > 0) 'top ${t.topCut}',
                  'al mejor de ${t.mejorDe}',
                ].join(' · '),
              ),
              if (t.ownerNombre.isNotEmpty)
                DatoTorneo(Icons.person_outline, 'Organiza ${t.ownerNombre}'),
              if (_organizo || t.participa(_uid))
                DatoTorneo(Icons.vpn_key_outlined, 'Código ${t.codigo}'),
            ],
          ),
          if (t.descripcion.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              t.descripcion,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  /// Lo que le toca hacer al jugador ahora.
  List<Widget> _panelJugador(PasoTorneo paso) {
    final uid = _uid;
    if (uid == null) return const [];
    if (t.enInscripcion) {
      final yo = widget.inscritos.where((i) => i.uid == uid).firstOrNull;
      return [
        Panel(
          destacado: yo == null,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  yo != null
                      ? 'Estás inscrito con «${yo.deckNombre}». Puedes cambiar '
                          'de mazo hasta que empiece el torneo.'
                      : t.lleno
                      ? 'El torneo completó su cupo.'
                      : 'Inscríbete con uno de tus mazos válidos para este '
                          'formato y Ban List.',
                  style: const TextStyle(color: AppColors.text),
                ),
              ),
              const SizedBox(width: 10),
              if (yo != null) ...[
                TextButton(
                  onPressed: _ocupado ? null : _salir,
                  child: const Text('Salir'),
                ),
                FilledButton.tonal(
                  onPressed: _ocupado ? null : _inscribirme,
                  child: const Text('Cambiar mazo'),
                ),
              ] else if (!t.lleno)
                FilledButton(
                  onPressed: _ocupado ? null : _inscribirme,
                  child: const Text('Inscribirme'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
      ];
    }
    if (t.finalizado) return const [];
    final mio = paso.rondaEnCurso.where((d) => d.juega(uid)).firstOrNull;
    if (mio == null) return const [];
    final soyA = mio.aUid == uid;
    final rival = soyA ? (mio.bNombre ?? '') : mio.aNombre;
    final marcadorMio =
        mio.tieneMarcador
            ? (soyA
                ? '${mio.scoreA}-${mio.scoreB}'
                : '${mio.scoreB}-${mio.scoreA}')
            : '';
    String texto;
    final botones = <Widget>[];
    if (mio.esBye) {
      texto = 'Esta ronda tienes bye: sumas una victoria 2-0 sin jugar.';
    } else if (mio.confirmado) {
      texto = 'Mesa ${mio.mesa} contra $rival: $marcadorMio, confirmado.';
    } else if (!mio.tieneMarcador) {
      texto = 'Tu duelo: mesa ${mio.mesa} contra $rival.';
      botones.add(
        FilledButton(
          onPressed: _ocupado ? null : () => _reportar(mio),
          child: const Text('Cargar resultado'),
        ),
      );
    } else if (mio.reportadoPor == uid) {
      texto =
          'Cargaste $marcadorMio contra $rival. Falta que tu rival lo confirme.';
      botones.add(
        TextButton(
          onPressed: _ocupado ? null : () => _reportar(mio),
          child: const Text('Corregir'),
        ),
      );
    } else {
      texto = '$rival cargó el resultado: $marcadorMio para ti. ¿Es correcto?';
      botones.addAll([
        TextButton(
          onPressed: _ocupado ? null : () => _rechazarDuelo(mio),
          child: const Text('No es correcto'),
        ),
        FilledButton(
          onPressed: _ocupado ? null : () => _confirmarDuelo(mio),
          child: const Text('Confirmar'),
        ),
      ]);
    }
    return [
      Panel(
        destacado: botones.isNotEmpty,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            Text(texto, style: const TextStyle(color: AppColors.text)),
            Row(mainAxisSize: MainAxisSize.min, children: botones),
          ],
        ),
      ),
      const SizedBox(height: 10),
    ];
  }

  Widget _panelOrganizador(PasoTorneo paso) {
    String texto;
    Widget? boton;
    if (t.enInscripcion) {
      final n = widget.inscritos.length;
      texto =
          n < 2
              ? 'Organizas este torneo. Necesitas al menos 2 inscritos para '
                  'iniciarlo.'
              : 'Organizas este torneo. Al iniciarlo se cierra la inscripción '
                  'y se genera la ronda 1.';
      boton = FilledButton.icon(
        onPressed: _ocupado || n < 2 ? null : _iniciar,
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('Iniciar torneo'),
      );
    } else if (t.finalizado) {
      return const SizedBox.shrink();
    } else {
      final cerrados = paso.rondaEnCurso.where((d) => d.dominio.cerrado).length;
      final total = paso.rondaEnCurso.length;
      final enTop = t.estado == EstadoTorneo.top;
      final nombreRonda =
          enTop
              ? nombreRondaTop(total)
              : 'Ronda ${t.rondaActual} de ${paso.rondasSuizas}';
      String siguiente;
      if (enTop) {
        siguiente = total == 1 ? 'Cerrar torneo' : 'Generar ${nombreRondaTop(total ~/ 2).toLowerCase()}';
      } else if (t.rondaActual < paso.rondasSuizas) {
        siguiente = 'Generar ronda ${t.rondaActual + 1}';
      } else {
        siguiente = paso.top > 0 ? 'Pasar al top ${paso.top}' : 'Cerrar torneo';
      }
      texto =
          '$nombreRonda: $cerrados de $total duelos cerrados.'
          '${paso.rondaCerrada ? '' : ' Puedes cargar o corregir cualquier resultado desde la pestaña Rondas.'}';
      boton = FilledButton.icon(
        onPressed: _ocupado || !paso.rondaCerrada ? null : _avanzar,
        icon: const Icon(Icons.skip_next_rounded),
        label: Text(siguiente),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.shield_outlined,
                  color: AppColors.gold,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    texto,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
            boton,
          ],
        ),
      ),
    );
  }
}

class _BarraPestanas extends SliverPersistentHeaderDelegate {
  final TabBar barra;
  _BarraPestanas(this.barra);

  @override
  double get minExtent => barra.preferredSize.height;
  @override
  double get maxExtent => barra.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      Material(color: AppColors.bg, child: barra);

  @override
  bool shouldRebuild(covariant _BarraPestanas old) => old.barra != barra;
}
