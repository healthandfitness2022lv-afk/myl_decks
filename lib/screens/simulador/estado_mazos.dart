import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/ban_list_entry.dart';
import '../../models/deck.dart';
import '../../services/ban_list_service.dart';

enum EstadoMazo { programado, textoCompleto }

/// Cartas del Mazo Castillo que exige el simulador (sin el Oro inicial).
const tamanoMazoSimulador = 49;

/// Un mazo entra al simulador solo con sus 49 cartas y sin pasar las copias
/// que permite la Ban List de su formato (3 si la carta no está en la lista).
/// La misma regla la aplica el worker (`datos.problemas_mazo`).
bool mazoValidoParaSimular(Deck mazo, Map<String, int> limites) {
  final copias = <String, int>{};
  var total = 0;
  for (final carta in mazo.cards) {
    if (carta.count <= 0) continue;
    total += carta.count;
    final id = carta.cardId?.trim() ?? '';
    final clave = normalizeBanListKey(id.isNotEmpty ? id : carta.name);
    copias[clave] = (copias[clave] ?? 0) + carta.count;
  }
  if (total != tamanoMazoSimulador) return false;
  return copias.entries.every((e) => e.value <= (limites[e.key] ?? 3));
}

BanListService _banListDe(DeckFormat formato) => switch (formato) {
  DeckFormat.racial => BanListService(),
  DeckFormat.racialLibre => BanListService.racialLibre(),
  DeckFormat.full => BanListService.full(),
};

/// Deja pasar solo los mazos válidos: los demás no aparecen en ninguna lista
/// del simulador. No emite hasta conocer las tres Ban List.
Stream<List<Deck>> soloMazosValidos(Stream<List<Deck>> mazos) {
  late final StreamController<List<Deck>> salida;
  final subs = <StreamSubscription>[];
  final limites = <DeckFormat, Map<String, int>>{};
  List<Deck>? ultimos;

  void emitir() {
    final actuales = ultimos;
    if (actuales == null || limites.length < DeckFormat.values.length) return;
    salida.add([
      for (final mazo in actuales)
        if (mazoValidoParaSimular(mazo, limites[mazo.format]!)) mazo,
    ]);
  }

  salida = StreamController<List<Deck>>(
    onListen: () {
      subs.add(
        mazos.listen((lista) {
          ultimos = lista;
          emitir();
        }, onError: salida.addError),
      );
      for (final formato in DeckFormat.values) {
        subs.add(
          _banListDe(formato).watchEntries().listen((entradas) {
            limites[formato] = {
              for (final entrada in entradas)
                if (entrada.cardId.trim().isNotEmpty)
                  normalizeBanListKey(entrada.cardId): entrada.maxCopies.clamp(
                    0,
                    3,
                  ),
            };
            emitir();
          }, onError: salida.addError),
        );
      }
    },
    onCancel: () async {
      for (final sub in subs) {
        await sub.cancel();
      }
      subs.clear();
    },
  );
  return salida.stream;
}

/// Consulta una sola vez cada carta compartida entre los mazos y escucha cambios.
class EstadosMazos extends StatefulWidget {
  final List<Deck> mazos;
  final Widget Function(BuildContext, Map<String, EstadoMazo>) builder;

  const EstadosMazos({super.key, required this.mazos, required this.builder});

  @override
  State<EstadosMazos> createState() => _EstadosMazosState();
}

class _EstadosMazosState extends State<EstadosMazos> {
  final _subs = <StreamSubscription>[];
  final _cartas = <String, Map<String, dynamic>>{};
  String _firma = '';

  String _firmaDe(List<Deck> mazos) {
    final ids =
        <String>{
            for (final mazo in mazos)
              for (final carta in mazo.cards)
                if (carta.count > 0 &&
                    (carta.cardId?.trim().isNotEmpty ?? false))
                  carta.cardId!.trim(),
          }.toList()
          ..sort();
    return ids.join('\u0000');
  }

  void _escuchar() {
    final firma = _firmaDe(widget.mazos);
    if (firma == _firma) return;
    _firma = firma;
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    _cartas.clear();
    if (firma.isEmpty) return;
    final ids = firma.split('\u0000');
    final cartas = FirebaseFirestore.instance.collection('cards');
    for (var i = 0; i < ids.length; i += 30) {
      final grupo = ids.sublist(i, (i + 30).clamp(0, ids.length));
      _subs.add(
        cartas
            .where(FieldPath.documentId, whereIn: grupo)
            .snapshots()
            .listen(
              (snapshot) {
                if (!mounted || _firma != firma) return;
                setState(() {
                  for (final id in grupo) {
                    _cartas.remove(id);
                  }
                  for (final doc in snapshot.docs) {
                    _cartas[doc.id] = doc.data();
                  }
                });
              },
              onError: (Object error) {
                if (!mounted || _firma != firma) return;
                setState(() {
                  for (final id in grupo) {
                    _cartas.remove(id);
                  }
                });
              },
            ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _escuchar();
  }

  @override
  void didUpdateWidget(covariant EstadosMazos oldWidget) {
    super.didUpdateWidget(oldWidget);
    _escuchar();
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  EstadoMazo? _estado(Deck mazo) {
    final entradas = mazo.cards.where((c) => c.count > 0).toList();
    if (entradas.isEmpty ||
        entradas.any((c) => c.cardId?.trim().isNotEmpty != true)) {
      return null;
    }
    final datos = [for (final c in entradas) _cartas[c.cardId!.trim()]];
    if (datos.any((c) => c == null)) return null;
    bool programada(Map<String, dynamic> c) =>
        c['habilidadesRevisadas'] == true &&
        '${c['notasSimulador'] ?? ''}'.trim().isEmpty;
    bool textoEscrito(Map<String, dynamic> c) =>
        programada(c) ||
        ['habilidadTextoIA', 'habilidad'].any(
          (campo) =>
              RegExp(
                r'\p{L}',
                unicode: true,
              ).allMatches('${c[campo] ?? ''}').length >=
              8,
        );
    if (datos.every((c) => programada(c!))) return EstadoMazo.programado;
    if (datos.every((c) => textoEscrito(c!))) return EstadoMazo.textoCompleto;
    return null;
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, {
    for (final mazo in widget.mazos)
      if (_estado(mazo) case final estado?) mazo.id: estado,
  });
}

class IconoEstadoMazo extends StatelessWidget {
  final EstadoMazo? estado;
  const IconoEstadoMazo(this.estado, {super.key});

  @override
  Widget build(BuildContext context) => switch (estado) {
    EstadoMazo.programado => const Tooltip(
      message: 'Todas las cartas están programadas para el simulador',
      child: Icon(Icons.check_circle, color: Color(0xFF34D399), size: 19),
    ),
    EstadoMazo.textoCompleto => const Tooltip(
      message:
          'Todos los textos están escritos; faltan habilidades por programar',
      child: Icon(Icons.description, color: Color(0xFF60A5FA), size: 19),
    ),
    null => const SizedBox.shrink(),
  };
}
