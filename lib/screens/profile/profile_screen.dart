// lib/screens/profile/profile_screen.dart
//
// Perfil del jugador: historial competitivo (torneos y ligas), mazos y
// estilo de juego, colección y Desafío contra la IA. Cada bloque carga por
// separado, así un error en uno no deja el resto en blanco.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../domain/analisis_mazo/analisis_mazo.dart';
import '../../domain/entrenamiento.dart';
import '../../domain/perfil_jugador.dart';
import '../../models/torneo.dart';
import '../../services/card_service.dart';
import '../../services/deck_service.dart';
import '../../services/inventory_service.dart';
import '../../services/tournament_service.dart';
import '../../theme/app_theme.dart';
import '../leagues/team_history.dart';
import '../tournaments/tournament_widgets.dart' show colorPerfil;

/// Mi jugador en las ligas de un team.
class _LigaTeam {
  final String teamId;
  final String teamNombre;

  /// Jugador del team vinculado a mi cuenta; null si aún no se vincula.
  final String? playerId;
  final TeamHistoryRow? fila;
  final int ligas;

  const _LigaTeam({
    required this.teamId,
    required this.teamNombre,
    this.playerId,
    this.fila,
    this.ligas = 0,
  });
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final String _uid = FirebaseAuth.instance.currentUser!.uid;
  final _db = FirebaseFirestore.instance;
  bool _subiendo = false;

  late Future<ResumenMazos> _mazos = _cargarMazos();
  late Future<ResumenColeccion> _coleccion = InventoryService(
    _uid,
  ).listInventory().then(resumirColeccion);
  late Future<ResumenDesafio> _desafio = _cargarDesafio();
  late Future<List<ParticipacionTorneo>> _torneos = _cargarTorneos();
  late Future<List<_LigaTeam>> _ligas = _cargarLigas();

  void _recargar() => setState(() {
    _mazos = _cargarMazos();
    _coleccion = InventoryService(_uid).listInventory().then(resumirColeccion);
    _desafio = _cargarDesafio();
    _torneos = _cargarTorneos();
    _ligas = _cargarLigas();
  });

  Future<ResumenMazos> _cargarMazos() async {
    final decks = await DeckService(_uid).listMine();
    final cartas = await CardService.catalogo();
    final porId = {for (final c in cartas) c.id: c};
    final porNombre = {
      for (final c in cartas) c.nombre.trim().toLowerCase(): c,
    };
    return resumirMazos(
      decks,
      resolver:
          (e) =>
              porId[(e.cardId ?? '').trim()] ??
              porNombre[e.name.trim().toLowerCase()],
    );
  }

  Future<ResumenDesafio> _cargarDesafio() async {
    final s =
        await _db
            .collection('ai_challenges')
            .where('ownerUid', isEqualTo: _uid)
            .get();
    return resumirDesafios(s.docs.map((d) => d.data()));
  }

  Future<List<ParticipacionTorneo>> _cargarTorneos() async {
    final servicio = TournamentService();
    final torneos =
        (await servicio.jugadosPor(_uid))..sort(
          (a, b) => (b.fecha ?? DateTime(2000)).compareTo(
            a.fecha ?? DateTime(2000),
          ),
        );
    return Future.wait([
      for (final t in torneos.take(12))
        () async {
          final inscritos = await servicio.leerInscritos(t.id);
          final duelos = await servicio.leerDuelos(t.id);
          return participacionEn(t, inscritos, duelos, _uid);
        }(),
    ]);
  }

  Future<List<_LigaTeam>> _cargarLigas() async {
    final misTeams =
        await _db.collection('users').doc(_uid).collection('teams').get();
    final out = <_LigaTeam>[];
    for (final ref in misTeams.docs) {
      final team = await _db.collection('teams').doc(ref.id).get();
      if (!team.exists) continue;
      final nombre = (team.data()?['name'] ?? 'Team').toString();
      final mio =
          await team.reference
              .collection('players')
              .where('uid', isEqualTo: _uid)
              .limit(1)
              .get();
      if (mio.docs.isEmpty) {
        out.add(_LigaTeam(teamId: ref.id, teamNombre: nombre));
        continue;
      }
      final historia = await computeTeamHistory(ref.id);
      final playerId = mio.docs.first.id;
      out.add(
        _LigaTeam(
          teamId: ref.id,
          teamNombre: nombre,
          playerId: playerId,
          fila: historia.rows.where((r) => r.playerId == playerId).firstOrNull,
          ligas: historia.leagueCount,
        ),
      );
    }
    return out;
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  /// Sube la foto como bytes (funciona en web y en móvil).
  Future<void> _cambiarFoto() async {
    final elegida = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 720,
      imageQuality: 85,
    );
    if (elegida == null) return;
    setState(() => _subiendo = true);
    try {
      final bytes = await elegida.readAsBytes();
      final ref = FirebaseStorage.instance.ref('profile_avatars/$_uid.jpg');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      await _db.collection('users').doc(_uid).set({
        'photoUrl': await ref.getDownloadURL(),
      }, SetOptions(merge: true));
      _aviso('Foto actualizada');
    } catch (e) {
      _aviso('No se pudo subir la foto: $e');
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  Future<void> _editarNombre(String actual) async {
    final ctrl = TextEditingController(text: actual);
    final nombre = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Tu nombre'),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              maxLength: 40,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'Como te verán en torneos y comunidades',
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
                child: const Text('Guardar'),
              ),
            ],
          ),
    );
    final limpio = (nombre ?? '').trim();
    if (limpio.isEmpty || limpio == actual) return;
    await _db.collection('users').doc(_uid).set({
      'displayName': limpio,
      'username': limpio,
    }, SetOptions(merge: true));
  }

  /// Elegir cuál de los jugadores del team soy yo (o desvincularme).
  Future<void> _vincular(_LigaTeam team) async {
    final jugadores =
        await _db
            .collection('teams')
            .doc(team.teamId)
            .collection('players')
            .orderBy('name')
            .get();
    if (!mounted) return;
    final elegido = await showDialog<String>(
      context: context,
      builder:
          (ctx) => SimpleDialog(
            title: Text('¿Quién eres en ${team.teamNombre}?'),
            children: [
              if (jugadores.docs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Text('Este team aún no tiene jugadores cargados.'),
                ),
              for (final j in jugadores.docs)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, j.id),
                  child: Row(
                    children: [
                      Expanded(child: Text((j.data()['name'] ?? j.id).toString())),
                      if (j.id == team.playerId)
                        const Icon(Icons.check, color: AppColors.success)
                      else if ((j.data()['uid'] ?? '').toString().isNotEmpty)
                        const Text(
                          'ya vinculado',
                          style: TextStyle(
                            color: AppColors.textFaint,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              if (team.playerId != null)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, ''),
                  child: const Text(
                    'No soy ninguno (quitar vínculo)',
                    style: TextStyle(color: AppColors.danger),
                  ),
                ),
            ],
          ),
    );
    if (elegido == null || elegido == team.playerId) return;
    final players = _db
        .collection('teams')
        .doc(team.teamId)
        .collection('players');
    try {
      final ocupado = jugadores.docs
          .where((j) => j.id == elegido)
          .any((j) {
            final otro = (j.data()['uid'] ?? '').toString();
            return otro.isNotEmpty && otro != _uid;
          });
      if (ocupado) {
        _aviso('Ese jugador ya está vinculado a otra cuenta.');
        return;
      }
      final batch = _db.batch();
      if (team.playerId != null) {
        batch.update(players.doc(team.playerId), {'uid': FieldValue.delete()});
      }
      if (elegido.isNotEmpty) batch.update(players.doc(elegido), {'uid': _uid});
      await batch.commit();
      setState(() => _ligas = _cargarLigas());
    } catch (e) {
      _aviso('No se pudo guardar el vínculo: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi perfil'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _recargar,
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _db.collection('users').doc(_uid).snapshots(),
        builder: (context, snap) {
          final data = snap.data?.data() ?? const <String, dynamic>{};
          final secciones = <Widget>[
            _competitivo(),
            _estilo(),
            _coleccionCard(),
            _desafioCard(),
          ];
          return LayoutBuilder(
            builder: (context, c) {
              final ancho = c.maxWidth >= 900;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _cabecera(data),
                          const SizedBox(height: 14),
                          if (ancho)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    children: [
                                      secciones[0],
                                      const SizedBox(height: 14),
                                      secciones[3],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    children: [
                                      secciones[1],
                                      const SizedBox(height: 14),
                                      secciones[2],
                                    ],
                                  ),
                                ),
                              ],
                            )
                          else
                            for (final s in secciones) ...[
                              s,
                              const SizedBox(height: 14),
                            ],
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // ── Cabecera ──────────────────────────────────────────────────────────────
  Widget _cabecera(Map<String, dynamic> data) {
    final usuario = FirebaseAuth.instance.currentUser;
    final nombre =
        ((data['displayName'] ?? data['username'] ?? usuario?.displayName ?? '')
                as String)
            .trim();
    final correo = (data['email'] ?? usuario?.email ?? '').toString();
    final foto = (data['photoUrl'] ?? '').toString();
    final creado = data['createdAt'];
    final desde =
        creado is Timestamp
            ? creado.toDate()
            : creado is int
            ? DateTime.fromMillisecondsSinceEpoch(creado)
            : usuario?.metadata.creationTime;
    const meses = [
      'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio',
      'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
    ];
    return _Tarjeta(
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 44,
                backgroundColor: AppColors.surfaceDeep,
                backgroundImage: foto.isNotEmpty ? NetworkImage(foto) : null,
                child:
                    foto.isEmpty
                        ? Text(
                          nombre.isEmpty ? '?' : nombre[0].toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.gold,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                          ),
                        )
                        : null,
              ),
              Positioned(
                right: -4,
                bottom: -4,
                child: IconButton.filled(
                  tooltip: 'Cambiar foto',
                  iconSize: 18,
                  constraints: const BoxConstraints.tightFor(
                    width: 34,
                    height: 34,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: _subiendo ? null : _cambiarFoto,
                  icon:
                      _subiendo
                          ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.photo_camera_outlined),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        nombre.isEmpty ? 'Jugador' : nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cambiar nombre',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () => _editarNombre(nombre),
                    ),
                  ],
                ),
                if (correo.isNotEmpty)
                  Text(
                    correo,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                if (data['entrenamiento'] is Map)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: InkWell(
                      onTap: () => context.push('/entrenamiento'),
                      child: Builder(
                        builder: (context) {
                          final p = ProgresoEntrenamiento.fromMap(
                            data['entrenamiento'],
                            inicial: 0,
                          );
                          return Text(
                            'Entrenamiento: rating ${p.rating} · '
                            '${p.ganadas} de ${p.partidas} ganadas · '
                            'mejor ${p.mejorRating}',
                            style: const TextStyle(
                              color: AppColors.gold,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                if (desde != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'En MyL Mazos desde ${meses[desde.month - 1]} de ${desde.year}',
                      style: const TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Historial competitivo ─────────────────────────────────────────────────
  Widget _competitivo() {
    return _Seccion(
      icono: Icons.emoji_events_outlined,
      titulo: 'Historial competitivo',
      child: FutureBuilder<List<ParticipacionTorneo>>(
        future: _torneos,
        builder:
            (context, st) => FutureBuilder<List<_LigaTeam>>(
              future: _ligas,
              builder: (context, sl) {
                if (st.hasError && sl.hasError) {
                  return _Error('${st.error}');
                }
                if (!st.hasData && !st.hasError || !sl.hasData && !sl.hasError) {
                  return const _Cargando();
                }
                final torneos = st.data ?? const <ParticipacionTorneo>[];
                final ligas = sl.data ?? const <_LigaTeam>[];
                var total = const RecordCompetitivo(0, 0, 0);
                for (final p in torneos) {
                  total += RecordCompetitivo(p.ganados, p.empatados, p.perdidos);
                }
                for (final l in ligas) {
                  final f = l.fila;
                  if (f != null) {
                    total += RecordCompetitivo(
                      f.matchesWon,
                      f.matchesDraw,
                      f.matchesLost,
                    );
                  }
                }
                final titulos = torneos.where((p) => p.campeon).length;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _Cifra('Duelos', '${total.duelos}'),
                        _Cifra(
                          'Victorias',
                          total.victorias == null
                              ? '-'
                              : '${(total.victorias! * 100).round()}%',
                        ),
                        _Cifra(
                          'G-E-P',
                          '${total.ganados}-${total.empatados}-${total.perdidos}',
                        ),
                        _Cifra('Torneos', '${torneos.length}'),
                        if (titulos > 0) _Cifra('Títulos', '$titulos'),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const _Subtitulo('Torneos'),
                    if (st.hasError)
                      _Error('${st.error}')
                    else if (torneos.isEmpty)
                      _Vacio(
                        'Aún no juegas ningún torneo.',
                        accion: 'Ver torneos',
                        onTap: () => context.push('/torneos'),
                      )
                    else
                      for (final p in torneos) _filaTorneo(p),
                    const SizedBox(height: 14),
                    const _Subtitulo('Ligas'),
                    if (sl.hasError)
                      _Error('${sl.error}')
                    else if (ligas.isEmpty)
                      _Vacio(
                        'No perteneces a ningún team con ligas.',
                        accion: 'Ver teams',
                        onTap: () => context.push('/teams'),
                      )
                    else
                      for (final l in ligas) _filaLiga(l),
                  ],
                );
              },
            ),
      ),
    );
  }

  Widget _filaTorneo(ParticipacionTorneo p) {
    final t = p.torneo;
    final f = t.fecha;
    final fecha =
        f == null
            ? ''
            : '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';
    return InkWell(
      onTap: () => context.push('/torneos/${t.id}'),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child:
                  p.campeon
                      ? const Icon(Icons.emoji_events, color: AppColors.gold)
                      : Text(
                        p.posicion == 0 ? '-' : '${p.posicion}º',
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    [
                      if (fecha.isNotEmpty) fecha,
                      if (t.finalizado)
                        '${p.jugadores} jugadores'
                      else
                        EstadoTorneo.etiqueta(t.estado),
                      if (p.raza.isNotEmpty) p.raza else if (p.mazo.isNotEmpty) p.mazo,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              p.duelos == 0
                  ? ''
                  : '${p.ganados}-${p.empatados}-${p.perdidos}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filaLiga(_LigaTeam l) {
    final f = l.fila;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const SizedBox(
            width: 44,
            child: Icon(Icons.groups_2_outlined, color: AppColors.gold),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.teamNombre,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  l.playerId == null
                      ? 'Indica cuál jugador eres para ver tus resultados'
                      : f == null
                      ? 'Aún sin duelos jugados'
                      : '${l.ligas} liga${l.ligas == 1 ? '' : 's'} · '
                          '${f.matchesPlayed} duelos · ${f.winPct.round()}% de victorias',
                  style: const TextStyle(
                    color: AppColors.textFaint,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (f != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                '${f.matchesWon}-${f.matchesDraw}-${f.matchesLost}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          TextButton(
            onPressed: () => _vincular(l),
            child: Text(l.playerId == null ? 'Soy…' : 'Cambiar'),
          ),
        ],
      ),
    );
  }

  // ── Mazos y estilo ────────────────────────────────────────────────────────
  Widget _estilo() {
    return _Seccion(
      icono: Icons.style_outlined,
      titulo: 'Mazos y estilo de juego',
      accion: 'Mis mazos',
      onAccion: () => context.push('/mazos'),
      child: FutureBuilder<ResumenMazos>(
        future: _mazos,
        builder: (context, snap) {
          if (snap.hasError) return _Error('${snap.error}');
          if (!snap.hasData) return const _Cargando();
          final r = snap.data!;
          if (r.mazos == 0) {
            return _Vacio(
              'Aún no tienes mazos.',
              accion: 'Crear mazo',
              onTap: () => context.push('/mazos/nuevo'),
            );
          }
          final conPerfil = r.porPerfil.values.fold<int>(0, (s, v) => s + v);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _Cifra('Mazos', '${r.mazos}'),
                  if (r.indiceMedio != null)
                    _Cifra('Velocidad media', '${r.indiceMedio} / 100'),
                ],
              ),
              if (r.estilo != null) ...[
                const SizedBox(height: 12),
                Text(
                  '${r.estilo}.',
                  style: const TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Row(
                    children: [
                      for (final p in const ['Agro', 'Medio', 'Control', 'Combo'])
                        if ((r.porPerfil[p] ?? 0) > 0)
                          Expanded(
                            flex: r.porPerfil[p]!,
                            child: Container(height: 12, color: colorPerfil(p)),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    for (final p in const ['Agro', 'Medio', 'Control', 'Combo'])
                      if ((r.porPerfil[p] ?? 0) > 0)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: colorPerfil(p),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '$p ${r.porPerfil[p]} de $conPerfil',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                  ],
                ),
              ],
              if (r.rolesFavoritos.isNotEmpty) ...[
                const SizedBox(height: 12),
                const _Subtitulo('Lo que más hacen tus mazos'),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final rol in r.rolesFavoritos)
                      _Chip(nombresRol[rol] ?? rol),
                  ],
                ),
              ],
              if (r.razas.isNotEmpty) ...[
                const SizedBox(height: 12),
                const _Subtitulo('Razas'),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final e in r.razas) _Chip('${e.key} · ${e.value}'),
                  ],
                ),
              ],
              if (r.cartasFrecuentes.isNotEmpty) ...[
                const SizedBox(height: 12),
                const _Subtitulo('Tus cartas de siempre'),
                for (final e in r.cartasFrecuentes)
                  _Barra(
                    etiqueta: e.key,
                    valor: '${e.value} mazo${e.value == 1 ? '' : 's'}',
                    fraccion: e.value / r.cartasFrecuentes.first.value,
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  // ── Colección ─────────────────────────────────────────────────────────────
  Widget _coleccionCard() {
    return _Seccion(
      icono: Icons.inventory_2_outlined,
      titulo: 'Colección',
      accion: 'Mi colección',
      onAccion: () => context.push('/inventario'),
      child: FutureBuilder<ResumenColeccion>(
        future: _coleccion,
        builder: (context, snap) {
          if (snap.hasError) return _Error('${snap.error}');
          if (!snap.hasData) return const _Cargando();
          final r = snap.data!;
          if (r.copias == 0) {
            return _Vacio(
              'Tu colección está vacía.',
              accion: 'Agregar cartas',
              onTap: () => context.push('/inventario'),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _Cifra('Copias', '${r.copias}'),
                  _Cifra('Cartas distintas', '${r.cartasDistintas}'),
                  _Cifra('En mazos', '${r.asignadas}'),
                  _Cifra('Libres', '${r.libres}'),
                ],
              ),
              const SizedBox(height: 12),
              const _Subtitulo('Copias por edición'),
              for (final e in r.porEdicion.take(8))
                _Barra(
                  etiqueta: e.key,
                  valor: '${e.value}',
                  fraccion: e.value / r.porEdicion.first.value,
                ),
            ],
          );
        },
      ),
    );
  }

  // ── Desafío IA ────────────────────────────────────────────────────────────
  Widget _desafioCard() {
    return _Seccion(
      icono: Icons.smart_toy_outlined,
      titulo: 'Desafío contra la IA',
      child: FutureBuilder<ResumenDesafio>(
        future: _desafio,
        builder: (context, snap) {
          if (snap.hasError) return _Error('${snap.error}');
          if (!snap.hasData) return const _Cargando();
          final r = snap.data!;
          if (r.jugadas == 0) {
            return const _Vacio(
              'Aún no terminas ninguna partida contra la IA. Las encuentras '
              'en el Laboratorio, desde Mis mazos.',
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _Cifra('Partidas', '${r.jugadas}'),
                  _Cifra('Ganadas', '${r.ganadas}'),
                  _Cifra(
                    'Mejor nivel vencido',
                    r.mejorNivelVencido == 0 ? '-' : '${r.mejorNivelVencido}',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (var nivel = 5; nivel >= 1; nivel--)
                if (r.porNivel[nivel] != null)
                  _Barra(
                    etiqueta: 'Nivel $nivel',
                    valor:
                        '${r.porNivel[nivel]!.$2} de ${r.porNivel[nivel]!.$1} ganadas',
                    fraccion: r.porNivel[nivel]!.$2 / r.porNivel[nivel]!.$1,
                  ),
            ],
          );
        },
      ),
    );
  }
}

// ── Piezas ───────────────────────────────────────────────────────────────────

class _Tarjeta extends StatelessWidget {
  final Widget child;
  const _Tarjeta({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.border),
    ),
    child: child,
  );
}

class _Seccion extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String? accion;
  final VoidCallback? onAccion;
  final Widget child;

  const _Seccion({
    required this.icono,
    required this.titulo,
    required this.child,
    this.accion,
    this.onAccion,
  });

  @override
  Widget build(BuildContext context) => _Tarjeta(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icono, color: AppColors.gold, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                titulo,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (accion != null)
              TextButton(onPressed: onAccion, child: Text(accion!)),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

class _Cifra extends StatelessWidget {
  final String etiqueta;
  final String valor;
  const _Cifra(this.etiqueta, this.valor);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.surfaceDeep,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          etiqueta,
          style: const TextStyle(color: AppColors.textFaint, fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          valor,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _Subtitulo extends StatelessWidget {
  final String texto;
  const _Subtitulo(this.texto);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      texto,
      style: const TextStyle(
        color: AppColors.textFaint,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _Chip extends StatelessWidget {
  final String texto;
  const _Chip(this.texto);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.surfaceDeep,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
    ),
    child: Text(
      texto,
      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
    ),
  );
}

class _Barra extends StatelessWidget {
  final String etiqueta;
  final String valor;
  final double fraccion;
  const _Barra({
    required this.etiqueta,
    required this.valor,
    required this.fraccion,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                etiqueta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.text, fontSize: 13),
              ),
            ),
            Text(
              valor,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraccion.clamp(0.0, 1.0),
            minHeight: 5,
            backgroundColor: AppColors.surfaceDeep,
            valueColor: const AlwaysStoppedAnimation(AppColors.goldStrong),
          ),
        ),
      ],
    ),
  );
}

class _Cargando extends StatelessWidget {
  const _Cargando();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 18),
    child: Center(
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}

class _Error extends StatelessWidget {
  final String detalle;
  const _Error(this.detalle);

  @override
  Widget build(BuildContext context) => Text(
    'No se pudo cargar este bloque. $detalle',
    style: const TextStyle(color: AppColors.danger, fontSize: 12),
  );
}

class _Vacio extends StatelessWidget {
  final String texto;
  final String? accion;
  final VoidCallback? onTap;
  const _Vacio(this.texto, {this.accion, this.onTap});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          texto,
          style: const TextStyle(color: AppColors.textFaint, fontSize: 13),
        ),
      ),
      if (accion != null) TextButton(onPressed: onTap, child: Text(accion!)),
    ],
  );
}
