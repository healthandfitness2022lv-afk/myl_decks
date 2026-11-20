// lib/screens/tournaments/tournament_widgets.dart
//
// Piezas del detalle de un torneo: pestañas, inscripción con un mazo válido
// y carga de marcador.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../domain/analisis_mazo/analisis_mazo.dart';
import '../../domain/torneo/torneo.dart';
import '../../domain/validation/deck_validator.dart';
import '../../models/card_myl.dart';
import '../../models/deck.dart';
import '../../models/torneo.dart';
import '../../services/ban_list_service.dart';
import '../../services/card_service.dart';
import '../../services/deck_service.dart';
import '../../services/tournament_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_state_view.dart';
import '../leagues/models.dart' show RoundFormat;
import '../leagues/round_ban_list_viewer.dart' show readRoundBanListSnapshot;

class Panel extends StatelessWidget {
  final Widget child;
  final bool destacado;
  const Panel({super.key, required this.child, this.destacado = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color:
            destacado
                ? AppColors.gold.withValues(alpha: .55)
                : AppColors.border,
      ),
    ),
    child: child,
  );
}

class DatoTorneo extends StatelessWidget {
  final IconData icon;
  final String texto;
  const DatoTorneo(this.icon, this.texto, {super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: AppColors.gold),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          texto,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      ),
    ],
  );
}

Color colorPerfil(String perfil) {
  switch (perfil) {
    case 'Agro':
      return const Color(0xFFE5734A);
    case 'Control':
      return const Color(0xFF4FA3E0);
    case 'Combo':
      return const Color(0xFFB07CE8);
    default:
      return AppColors.goldStrong;
  }
}

// ── Inscripción ──────────────────────────────────────────────────────────────

/// ¿El mazo se puede usar en un torneo de este formato?
/// Un mazo de Racial Edición también es legal en Racial Libre, y cualquier
/// mazo lo es en Formato Libre (siempre contra la Ban List del torneo).
bool mazoSirveParaFormato(Deck deck, String formato) {
  final propio = formatoDeMazo(deck);
  if (formato == 'full') return true;
  if (formato == 'racial_libre') return propio != 'full';
  return propio == 'racial_edicion';
}

class _Candidato {
  final Deck deck;
  final List<String> problemas;
  const _Candidato(this.deck, this.problemas);
  bool get valido => problemas.isEmpty;
}

Future<List<_Candidato>> _candidatos(Torneo t, String uid) async {
  final mazos = await DeckService(uid).listMine();
  final cartas = await CardService.catalogo();
  final porId = <String, dynamic>{for (final c in cartas) c.id: c};
  final porNombre = <String, dynamic>{
    for (final c in cartas) c.nombre.trim().toLowerCase(): c,
  };
  final limites = BanListService.copyLimitsFromSnapshot(
    readRoundBanListSnapshot(t.data) ?? const [],
  );
  final formato = RoundFormat.fromKey(t.formato).label;
  final out = <_Candidato>[];
  for (final d in mazos) {
    if (d.cards.isEmpty) continue;
    final problemas = <String>[];
    if (!mazoSirveParaFormato(d, t.formato)) {
      problemas.add('Es de otro formato (el torneo es $formato).');
    } else {
      final r = validateDeck(
        deck: d,
        catalogById: porId,
        catalogByName: porNombre,
        copyLimitsByKey: limites,
      );
      problemas.addAll(r.issues.map((i) => i.message));
    }
    out.add(_Candidato(d, problemas));
  }
  out.sort((a, b) {
    if (a.valido != b.valido) return a.valido ? -1 : 1;
    return a.deck.name.toLowerCase().compareTo(b.deck.name.toLowerCase());
  });
  return out;
}

/// Muestra mis mazos, validados contra el formato y la Ban List congelada
/// del torneo. Devuelve el elegido (solo se pueden elegir los válidos).
Future<Deck?> elegirMazoParaTorneo(BuildContext context, Torneo t) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Future.value();
  final futuro = _candidatos(t, uid);
  return showModalBottomSheet<Deck>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder:
        (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: .7,
          maxChildSize: .92,
          builder:
              (ctx, scroll) => FutureBuilder<List<_Candidato>>(
                future: futuro,
                builder: (ctx, snap) {
                  if (snap.hasError) return ErrorStateView(error: snap.error);
                  if (!snap.hasData) {
                    return const LoadingStateView(
                      message: 'Revisando tus mazos…',
                    );
                  }
                  final lista = snap.data!;
                  if (lista.isEmpty) {
                    return const EmptyStateView(
                      icon: Icons.style_outlined,
                      title: 'No tienes mazos',
                      message: 'Crea un mazo de 49 cartas para inscribirte.',
                    );
                  }
                  return ListView(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      const Text(
                        'Elige tu mazo',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Se guarda una copia de la lista tal como está ahora. '
                        'Nadie más la ve hasta que termine el torneo. '
                        'Formato: ${RoundFormat.fromKey(t.formato).label}.',
                        style: const TextStyle(
                          color: AppColors.textFaint,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (final c in lista)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            enabled: c.valido,
                            leading: Icon(
                              c.valido
                                  ? Icons.check_circle_outline
                                  : Icons.block,
                              color:
                                  c.valido
                                      ? AppColors.success
                                      : AppColors.danger,
                            ),
                            title: Text(
                              c.deck.name.isEmpty
                                  ? 'Mazo sin nombre'
                                  : c.deck.name,
                            ),
                            subtitle: Text(
                              c.valido
                                  ? [
                                    if ((c.deck.race ?? '').isNotEmpty)
                                      c.deck.race!,
                                    'Válido para este torneo',
                                  ].join(' · ')
                                  : c.problemas.take(3).join('\n') +
                                      (c.problemas.length > 3
                                          ? '\n… y ${c.problemas.length - 3} más'
                                          : ''),
                            ),
                            isThreeLine: !c.valido && c.problemas.length > 1,
                            onTap:
                                c.valido
                                    ? () => Navigator.pop(ctx, c.deck)
                                    : null,
                          ),
                        ),
                    ],
                  );
                },
              ),
        ),
  );
}

// ── Marcador ─────────────────────────────────────────────────────────────────

/// Pide el marcador de un duelo. Devuelve (partidas de A, partidas de B).
Future<(int, int)?> pedirMarcador(
  BuildContext context, {
  required DueloDoc duelo,
  required bool permiteEmpate,
}) {
  var a = duelo.scoreA ?? 0;
  var b = duelo.scoreB ?? 0;
  return showDialog<(int, int)>(
    context: context,
    builder:
        (ctx) => StatefulBuilder(
          builder: (ctx, setD) {
            final valido = marcadorValido(a, b, permiteEmpate: permiteEmpate);
            Widget lado(String nombre, int valor, ValueChanged<int> cambia) =>
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        nombre,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<int>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 0, label: Text('0')),
                          ButtonSegment(value: 1, label: Text('1')),
                          ButtonSegment(value: 2, label: Text('2')),
                        ],
                        selected: {valor},
                        onSelectionChanged: (s) => setD(() => cambia(s.first)),
                      ),
                    ],
                  ),
                );
            return AlertDialog(
              title: Text('Mesa ${duelo.mesa}: partidas ganadas'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        lado(duelo.aNombre, a, (v) => a = v),
                        const SizedBox(width: 12),
                        lado(duelo.bNombre ?? '', b, (v) => b = v),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      valido
                          ? (a == b
                              ? 'Empate $a-$b: 1 punto cada uno.'
                              : 'Gana ${a > b ? duelo.aNombre : duelo.bNombre} $a-$b.')
                          : permiteEmpate
                          ? 'Al mejor de 3: 2-0, 2-1, 1-1 o 1-0 si se acabó el tiempo.'
                          : 'En la llave debe haber un ganador: 2-0 o 2-1.',
                      style: TextStyle(
                        color:
                            valido ? AppColors.textSecondary : AppColors.danger,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: valido ? () => Navigator.pop(ctx, (a, b)) : null,
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        ),
  );
}

// ── Pestañas ─────────────────────────────────────────────────────────────────

class InscritosTab extends StatelessWidget {
  final Torneo torneo;
  final List<Inscrito> inscritos;
  final String? uid;
  final bool organizo;

  /// Las listas se pueden ver (torneo terminado).
  final bool listasVisibles;
  final ValueChanged<Inscrito>? onRetirar;

  const InscritosTab({
    super.key,
    required this.torneo,
    required this.inscritos,
    required this.uid,
    required this.organizo,
    required this.listasVisibles,
    this.onRetirar,
  });

  @override
  Widget build(BuildContext context) {
    if (inscritos.isEmpty) {
      return const EmptyStateView(
        icon: Icons.people_outline,
        title: 'Aún no hay inscritos',
        message: 'Comparte el enlace o el código para que se inscriban.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: inscritos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final j = inscritos[i];
        final verLista = listasVisibles || j.uid == uid;
        return Panel(
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.surfaceDeep,
                child: Text(
                  j.nombre.isEmpty ? '?' : j.nombre[0].toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${j.nombre}${j.uid == uid ? ' (tú)' : ''}',
                      style: TextStyle(
                        color:
                            j.retirado ? AppColors.textFaint : AppColors.text,
                        fontWeight: FontWeight.w700,
                        decoration:
                            j.retirado ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    Text(
                      j.retirado
                          ? 'Retirado'
                          : verLista
                          ? [
                            if (j.raza.isNotEmpty) j.raza,
                            j.deckNombre,
                          ].join(' · ')
                          : 'Lista oculta hasta el final',
                      style: const TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (verLista)
                IconButton(
                  tooltip: 'Ver lista',
                  icon: const Icon(Icons.list_alt_outlined),
                  onPressed: () => _verLista(context, j),
                ),
              if (onRetirar != null)
                IconButton(
                  tooltip: j.retirado ? 'Reintegrar' : 'Retirar del torneo',
                  icon: Icon(
                    j.retirado
                        ? Icons.person_add_alt_1_outlined
                        : Icons.person_remove_outlined,
                  ),
                  onPressed: () => onRetirar!(j),
                ),
            ],
          ),
        );
      },
    );
  }

  void _verLista(BuildContext context, Inscrito j) {
    final porTipo = <String, List<DeckCardEntry>>{};
    for (final e in j.cartas) {
      (porTipo[(e.tipo ?? 'Otras').trim()] ??= []).add(e);
    }
    showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text('${j.deckNombre} · ${j.nombre}'),
            content: SizedBox(
              width: 380,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final grupo in porTipo.entries) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Text(
                        '${grupo.key} (${grupo.value.fold<int>(0, (s, e) => s + e.count)})',
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    for (final e
                        in grupo.value..sort((a, b) => a.name.compareTo(b.name)))
                      Text('${e.count}  ${e.name}'),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
            ],
          ),
    );
  }
}

class RondasTab extends StatefulWidget {
  final Torneo torneo;
  final List<DueloDoc> duelos;
  final String? uid;
  final bool organizo;
  final ValueChanged<DueloDoc>? onReportar;

  const RondasTab({
    super.key,
    required this.torneo,
    required this.duelos,
    required this.uid,
    required this.organizo,
    this.onReportar,
  });

  @override
  State<RondasTab> createState() => _RondasTabState();
}

class _RondasTabState extends State<RondasTab> {
  /// (fase, ronda) elegida; null = la última.
  (String, int)? _elegida;

  @override
  Widget build(BuildContext context) {
    final rondas = <(String, int)>{
      for (final d in widget.duelos) (d.fase, d.ronda),
    }.toList()..sort((a, b) {
      if (a.$1 != b.$1) return a.$1 == 'suizo' ? -1 : 1;
      return a.$2.compareTo(b.$2);
    });
    if (rondas.isEmpty) {
      return const EmptyStateView(
        icon: Icons.table_restaurant_outlined,
        title: 'Aún no hay rondas',
      );
    }
    final actual = rondas.contains(_elegida) ? _elegida! : rondas.last;
    final duelos =
        widget.duelos
            .where((d) => d.fase == actual.$1 && d.ronda == actual.$2)
            .toList()
          ..sort((a, b) => a.mesa.compareTo(b.mesa));
    String nombre((String, int) r) {
      if (r.$1 == 'suizo') return 'Ronda ${r.$2}';
      final n =
          widget.duelos.where((d) => d.fase == 'top' && d.ronda == r.$2).length;
      return nombreRondaTop(n);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in rondas)
              ChoiceChip(
                label: Text(nombre(r)),
                selected: r == actual,
                onSelected: (_) => setState(() => _elegida = r),
              ),
          ],
        ),
        const SizedBox(height: 12),
        for (final d in duelos)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _DueloTile(
              duelo: d,
              uid: widget.uid,
              // Puede cargar quien juega el duelo (si no está confirmado) y
              // siempre el organizador.
              onTap:
                  widget.onReportar != null &&
                          !d.esBye &&
                          (widget.organizo ||
                              (d.juega(widget.uid) && !d.confirmado))
                      ? () => widget.onReportar!(d)
                      : null,
            ),
          ),
      ],
    );
  }
}

class _DueloTile extends StatelessWidget {
  final DueloDoc duelo;
  final String? uid;
  final VoidCallback? onTap;

  const _DueloTile({required this.duelo, required this.uid, this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = duelo;
    final ganador = d.dominio.ganador;
    TextStyle estilo(String? id) => TextStyle(
      color: AppColors.text,
      fontWeight: ganador != null && ganador == id ? FontWeight.w900 : FontWeight.w500,
    );
    String estado;
    Color color;
    if (d.esBye) {
      estado = 'Bye';
      color = AppColors.textFaint;
    } else if (d.confirmado) {
      estado = '${d.scoreA} - ${d.scoreB}';
      color = AppColors.success;
    } else if (d.tieneMarcador) {
      estado = '${d.scoreA} - ${d.scoreB} · por confirmar';
      color = AppColors.warning;
    } else {
      estado = 'Por jugar';
      color = AppColors.textFaint;
    }
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  d.juega(uid)
                      ? AppColors.gold.withValues(alpha: .5)
                      : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                child: Text(
                  '${d.mesa}',
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.aNombre, style: estilo(d.aUid)),
                    Text(
                      d.esBye ? 'Sin rival' : (d.bNombre ?? ''),
                      style:
                          d.esBye
                              ? const TextStyle(color: AppColors.textFaint)
                              : estilo(d.bUid),
                    ),
                  ],
                ),
              ),
              Text(
                estado,
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 6),
                const Icon(Icons.edit_outlined, size: 16, color: Colors.white38),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _porc(double v) => '${(v * 100).round()}%';

class TablaTab extends StatelessWidget {
  final List<FilaTabla> tabla;
  final String? uid;

  /// Cuántos clasifican al top (0 = sin top).
  final int top;

  const TablaTab({super.key, required this.tabla, required this.uid, this.top = 0});

  @override
  Widget build(BuildContext context) {
    const cabecera = TextStyle(
      color: AppColors.textFaint,
      fontSize: 11,
      fontWeight: FontWeight.w800,
    );
    Widget celda(String t, double w, {TextStyle? estilo}) => SizedBox(
      width: w,
      child: Text(t, textAlign: TextAlign.center, style: estilo),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Row(
          children: [
            celda('#', 30, estilo: cabecera),
            const Expanded(child: Text('Jugador', style: cabecera)),
            celda('Pts', 36, estilo: cabecera),
            celda('G-E-P', 56, estilo: cabecera),
            celda('% riv.', 48, estilo: cabecera),
            celda('% part.', 50, estilo: cabecera),
          ],
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < tabla.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color:
                  tabla[i].jugador.id == uid
                      ? AppColors.gold.withValues(alpha: .10)
                      : AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border(
                left: BorderSide(
                  color: i < top ? AppColors.gold : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                celda(
                  '${i + 1}',
                  27,
                  estilo: TextStyle(
                    color: i < 3 ? AppColors.gold : AppColors.textFaint,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Expanded(
                  child: Text(
                    tabla[i].jugador.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color:
                          tabla[i].jugador.retirado
                              ? AppColors.textFaint
                              : AppColors.text,
                      fontWeight: FontWeight.w600,
                      decoration:
                          tabla[i].jugador.retirado
                              ? TextDecoration.lineThrough
                              : null,
                    ),
                  ),
                ),
                celda(
                  '${tabla[i].puntos}',
                  36,
                  estilo: const TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                celda(
                  '${tabla[i].ganados}-${tabla[i].empatados}-${tabla[i].perdidos}',
                  56,
                  estilo: const TextStyle(color: AppColors.textSecondary),
                ),
                celda(
                  _porc(tabla[i].rivalesDuelos),
                  48,
                  estilo: const TextStyle(color: AppColors.textSecondary),
                ),
                celda(
                  _porc(tabla[i].porcentajePartidas),
                  50,
                  estilo: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Text(
          'Victoria 3 puntos, empate 1. Desempates en orden: % de duelos de '
          'los rivales, % de partidas propias y % de partidas de los rivales.'
          '${top > 0 ? ' La franja dorada marca a los $top que pasan a la llave.' : ''}',
          style: const TextStyle(color: AppColors.textFaint, fontSize: 12),
        ),
      ],
    );
  }
}

class LlaveTab extends StatelessWidget {
  final List<DueloDoc> duelos;
  const LlaveTab({super.key, required this.duelos});

  @override
  Widget build(BuildContext context) {
    final rondas = <int, List<DueloDoc>>{};
    for (final d in duelos.where((d) => d.fase == 'top')) {
      (rondas[d.ronda] ??= []).add(d);
    }
    final orden = rondas.keys.toList()..sort();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (final r in orden)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: SizedBox(
                  width: 230,
                  child: Column(
                    children: [
                      Text(
                        nombreRondaTop(rondas[r]!.length),
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final d
                          in rondas[r]!
                            ..sort((a, b) => a.mesa.compareTo(b.mesa)))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: _CruceLlave(duelo: d),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CruceLlave extends StatelessWidget {
  final DueloDoc duelo;
  const _CruceLlave({required this.duelo});

  @override
  Widget build(BuildContext context) {
    final ganador = duelo.dominio.ganador;
    Widget fila(String id, String nombre, int? score) => Row(
      children: [
        Expanded(
          child: Text(
            nombre,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: ganador == null || ganador == id ? AppColors.text : AppColors.textFaint,
              fontWeight: ganador == id ? FontWeight.w900 : FontWeight.w500,
            ),
          ),
        ),
        Text(
          score == null ? '-' : '$score',
          style: TextStyle(
            color: ganador == id ? AppColors.gold : AppColors.textSecondary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
    return Panel(
      destacado: duelo.confirmado,
      child: Column(
        children: [
          fila(duelo.aUid, duelo.aNombre, duelo.scoreA),
          const Divider(height: 12),
          fila(duelo.bUid ?? '', duelo.bNombre ?? '', duelo.scoreB),
        ],
      ),
    );
  }
}

/// Qué se jugó y qué ganó: razas y perfiles (agro, medio, control) de las
/// listas inscritas, con su rendimiento en la fase suiza.
class MetaTorneoTab extends StatelessWidget {
  final List<Inscrito> inscritos;
  final List<FilaTabla> tabla;

  const MetaTorneoTab({super.key, required this.inscritos, required this.tabla});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CardMyL>>(
      future: CardService.catalogo(),
      builder: (context, snap) {
        if (snap.hasError) return ErrorStateView(error: snap.error);
        if (!snap.hasData) {
          return const LoadingStateView(message: 'Analizando las listas…');
        }
        final porId = {for (final c in snap.data!) c.id: c};
        final porNombre = {
          for (final c in snap.data!) c.nombre.trim().toLowerCase(): c,
        };
        final filaDe = {for (final f in tabla) f.jugador.id: f};
        final posicion = {
          for (var i = 0; i < tabla.length; i++) tabla[i].jugador.id: i + 1,
        };
        final analisis = <String, AnalisisMazo>{
          for (final i in inscritos)
            i.uid: analizarEntradas(
              i.cartas,
              resolver:
                  (e) =>
                      porId[(e.cardId ?? '').trim()] ??
                      porNombre[e.name.trim().toLowerCase()],
            ),
        };

        // (jugadores, puntos, puntos posibles) por grupo.
        Map<String, (int, int, int)> agrupar(String Function(Inscrito) clave) {
          final out = <String, (int, int, int)>{};
          for (final i in inscritos) {
            final f = filaDe[i.uid];
            final k = clave(i);
            final a = out[k] ?? (0, 0, 0);
            out[k] = (
              a.$1 + 1,
              a.$2 + (f?.puntos ?? 0),
              a.$3 + puntosVictoria * (f?.jugados ?? 0),
            );
          }
          return out;
        }

        final porPerfil = agrupar((i) => analisis[i.uid]!.perfil);
        final porRaza = agrupar((i) => i.raza.isEmpty ? 'Sin raza' : i.raza);
        final indiceMedio =
            inscritos.isEmpty
                ? 50
                : (inscritos.fold<int>(
                          0,
                          (s, i) => s + analisis[i.uid]!.indice,
                        ) /
                        inscritos.length)
                    .round();
        final ordenados = [...inscritos]..sort(
          (a, b) => (posicion[a.uid] ?? 999).compareTo(posicion[b.uid] ?? 999),
        );

        Widget grupo(String titulo, Map<String, (int, int, int)> datos, {Color Function(String)? color}) {
          final claves =
              datos.keys.toList()
                ..sort((a, b) => datos[b]!.$1.compareTo(datos[a]!.$1));
          return Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                for (final k in claves)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 96,
                          child: Text(
                            k,
                            style: TextStyle(
                              color: color?.call(k) ?? AppColors.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: datos[k]!.$1 / inscritos.length,
                              minHeight: 8,
                              backgroundColor: AppColors.surfaceDeep,
                              valueColor: AlwaysStoppedAnimation(
                                color?.call(k) ?? AppColors.goldStrong,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 150,
                          child: Text(
                            '${datos[k]!.$1} mazo${datos[k]!.$1 == 1 ? '' : 's'} · '
                            '${datos[k]!.$3 == 0 ? '-' : _porc(datos[k]!.$2 / datos[k]!.$3)} de puntos',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
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

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Panel(
              child: Text(
                'Velocidad media del torneo: $indiceMedio de 100 '
                '(0 = control, 100 = agro), según las habilidades de las '
                'cartas de cada lista. «De puntos» es cuántos puntos sacó ese '
                'grupo de los que disputó en la fase suiza.',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 10),
            grupo('Estilos de juego', porPerfil, color: colorPerfil),
            const SizedBox(height: 10),
            grupo('Razas', porRaza),
            const SizedBox(height: 10),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Listas por posición',
                    style: TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final i in ordenados)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 30,
                            child: Text(
                              '${posicion[i.uid] ?? '-'}',
                              style: const TextStyle(
                                color: AppColors.gold,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${i.nombre} · ${i.raza.isEmpty ? i.deckNombre : i.raza}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.text),
                            ),
                          ),
                          Text(
                            analisis[i.uid]!.resumen,
                            style: TextStyle(
                              color: colorPerfil(analisis[i.uid]!.perfil),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
