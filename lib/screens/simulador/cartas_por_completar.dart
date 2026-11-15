// lib/screens/simulador/cartas_por_completar.dart
//
// Antes de simular: lista en vivo las cartas de los mazos elegidos que aún no
// están completas (sin marcar como programadas o con notas pendientes). Tocar
// una abre su detalle para programarla; al volver, la lista ya se actualizó.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/card_myl.dart';
import '../../models/deck.dart';
import '../card_details_screen.dart';

const _orange = Color(0xFFF59E0B);
const _green = Color(0xFF34D399);

class CartasPorCompletar extends StatefulWidget {
  final List<Deck> mazos;
  final ValueChanged<int> onPendientes;

  const CartasPorCompletar({
    super.key,
    required this.mazos,
    required this.onPendientes,
  });

  @override
  State<CartasPorCompletar> createState() => _CartasPorCompletarState();
}

class _Uso {
  int copias = 0;
  final Set<String> mazos = {};
}

class _CartasPorCompletarState extends State<CartasPorCompletar> {
  final Map<String, CardMyL> _cartas = {};

  /// Datos crudos: texto leído por la IA y estado en la cola del agente.
  final Map<String, Map<String, dynamic>> _raw = {};
  final Map<String, _Uso> _usos = {};
  final List<StreamSubscription> _subs = [];
  int _cargados = 0;
  bool _leyendo = false;

  /// Texto de habilidad, si es texto de verdad (muchas cartas tienen solo
  /// "." en el campo oficial).
  String _texto(String id) {
    final d = _raw[id] ?? const {};
    for (final campo in ['habilidadTextoIA', 'habilidad']) {
      final t = '${d[campo] ?? ''}'.trim();
      if (RegExp(r'\p{L}', unicode: true).allMatches(t).length >= 8) return t;
    }
    return '';
  }

  String _cola(String id) =>
      '${((_raw[id]?['solicitudAgente'] as Map?) ?? const {})['estado'] ?? ''}';

  /// Lee con IA el texto de las cartas pendientes que aún no lo tienen.
  Future<void> _leer(List<CardMyL> pend) async {
    final ids = [
      for (final c in pend)
        if (_texto(c.id).isEmpty) c.id,
    ];
    if (ids.isEmpty) return;
    setState(() => _leyendo = true);
    try {
      await FirebaseFirestore.instance.collection('card_ai_jobs').add({
        'ownerUid': FirebaseAuth.instance.currentUser!.uid,
        'tipo': 'leer',
        'cardIds': ids,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo pedir la lectura: $e')),
      );
    } finally {
      if (mounted) setState(() => _leyendo = false);
    }
  }

  /// Deja la carta en la cola para que el agente (Claude, desde el chat) la
  /// programe y cree lo que falte en el editor o el motor.
  Future<void> _encolar(String id) async {
    try {
      await FirebaseFirestore.instance.collection('cards').doc(id).update({
        'solicitudAgente': {
          'estado': 'pendiente',
          'at': FieldValue.serverTimestamp(),
        },
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Carta enviada al agente conversacional para programarla.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo encolar: $e')));
    }
  }

  @override
  void initState() {
    super.initState();
    for (final d in widget.mazos) {
      for (final e in d.cards) {
        final id = e.cardId?.trim() ?? '';
        if (id.isEmpty) continue;
        final u = _usos.putIfAbsent(id, _Uso.new);
        u.copias += e.count;
        u.mazos.add(d.name);
      }
    }
    final ids = _usos.keys.toList();
    final cards = FirebaseFirestore.instance.collection('cards');
    // whereIn admite hasta 30 ids por consulta.
    for (var k = 0; k < ids.length; k += 30) {
      final chunk = ids.sublist(k, (k + 30).clamp(0, ids.length));
      _subs.add(
        cards.where(FieldPath.documentId, whereIn: chunk).snapshots().listen((
          s,
        ) {
          if (!mounted) return;
          setState(() {
            for (final d in s.docs) {
              _cartas[d.id] = CardMyL.fromMap(d.data(), d.id);
              _raw[d.id] = d.data();
            }
            _cargados = _cartas.length;
          });
          _avisar();
        }),
      );
    }
    if (ids.isEmpty)
      WidgetsBinding.instance.addPostFrameCallback((_) => _avisar());
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  bool _completa(CardMyL c) =>
      c.habilidadesRevisadas && c.notasSimulador.trim().isEmpty;

  List<CardMyL> get _pendientes {
    final list = _cartas.values.where((c) => !_completa(c)).toList();
    list.sort(
      (a, b) => (_usos[b.id]?.copias ?? 0).compareTo(_usos[a.id]?.copias ?? 0),
    );
    return list;
  }

  void _avisar() {
    if (_cargados < _usos.length) return; // aún cargando
    widget.onPendientes(_pendientes.length);
  }

  @override
  Widget build(BuildContext context) {
    final total = _usos.length;
    if (_cargados < total) {
      return const LinearProgressIndicator(minHeight: 2);
    }
    final pend = _pendientes;
    final listas = total - pend.length;
    final color = pend.isEmpty ? _green : _orange;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            pend.isEmpty
                ? 'Todas las cartas están completas ($total de $total).'
                : 'Cartas por completar: ${pend.length} · listas $listas de $total',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 1 : listas / total,
              minHeight: 6,
              color: color,
              backgroundColor: Colors.white10,
            ),
          ),
          if (pend.isNotEmpty) ...[
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final sinTexto = pend.where((c) => _texto(c.id).isEmpty).length;
                return Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _orange,
                      foregroundColor: Colors.black,
                    ),
                    onPressed:
                        sinTexto == 0 || _leyendo ? null : () => _leer(pend),
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: Text(
                      sinTexto == 0
                          ? 'Habilidades leídas'
                          : 'Leer habilidades con IA ($sinTexto)',
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 6),
            const Text(
              'Con el texto leído, toca “Programar con agente”: queda pendiente '
              'para que la programe el agente conversacional desde este chat. '
              'No la procesa el worker ni gasta API automáticamente. Tocar la '
              'carta abre su editor.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in pend)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        c.notasSimulador.trim().isNotEmpty
                            ? Icons.sticky_note_2_outlined
                            : Icons.edit_note_rounded,
                        color: _orange,
                      ),
                      title: Text(
                        c.nombre,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        [
                          [
                            c.tipo,
                            '×${_usos[c.id]?.copias ?? 0}',
                            if (widget.mazos.length > 1)
                              (_usos[c.id]?.mazos ?? const {}).join(' / '),
                            if (c.notasSimulador.trim().isNotEmpty)
                              'con notas pendientes'
                            else if (c.habilidades.isNotEmpty)
                              '${c.habilidades.length} habilidad(es), sin marcar'
                            else
                              'sin programar',
                          ].join(' · '),
                          if (_texto(c.id).isNotEmpty) '“${_texto(c.id)}”',
                        ].join('\n'),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                      isThreeLine: _texto(c.id).isNotEmpty,
                      trailing:
                          _texto(c.id).isEmpty
                              ? const Icon(
                                Icons.chevron_right,
                                color: Colors.white38,
                              )
                              : _cola(c.id) == 'pendiente'
                              ? const Chip(
                                label: Text('Pendiente para agente'),
                                visualDensity: VisualDensity.compact,
                              )
                              : TextButton(
                                onPressed: () => _encolar(c.id),
                                child: const Text(
                                  'Programar con agente',
                                  style: TextStyle(color: _orange),
                                ),
                              ),
                      onTap:
                          () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CardDetailsScreen(card: c),
                            ),
                          ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
