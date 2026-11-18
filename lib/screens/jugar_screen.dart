// lib/screens/jugar_screen.dart
//
// «Jugar»: todo lo del simulador en un solo lugar (Héctor 18-11). Solo lo ve
// quien tiene acceso (services/acceso_jugar.dart).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'meta_stats_screen.dart';
import 'simulador/desafio_ia_screen.dart';
import 'simulador/laboratorio_ml_screen.dart';
import 'simulador/simulador_screen.dart';

class JugarOpcion {
  const JugarOpcion(this.icono, this.titulo, this.detalle, this.abrir);

  final IconData icono;
  final String titulo;
  final String detalle;
  final void Function(BuildContext) abrir;
}

void _push(BuildContext context, Widget pantalla) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => pantalla));

/// Lo que hay dentro de «Jugar», en orden.
final opcionesJugar = <JugarOpcion>[
  JugarOpcion(
    Icons.smart_toy_outlined,
    'Desafío contra la IA',
    'Juega una partida contra la IA con tus mazos',
    (c) => _push(c, const DesafioIaScreen()),
  ),
  JugarOpcion(
    Icons.fitness_center_rounded,
    'ELO',
    'Sube de rating contra mazos del meta, cada vez más difíciles',
    (c) => c.push('/entrenamiento'),
  ),
  JugarOpcion(
    Icons.sports_esports_outlined,
    'Simulador de partidas',
    'Mazo contra mazo: miles de partidas y su informe',
    (c) => _push(c, const SimuladorScreen()),
  ),
  JugarOpcion(
    Icons.insights_rounded,
    'Lo que gana',
    'El meta según el simulador: agro o control',
    (c) => _push(c, const MetaStatsScreen(soloSimulador: true)),
  ),
  JugarOpcion(
    Icons.science_outlined,
    'Laboratorio',
    'Entrenamiento de la IA y mediciones',
    (c) => _push(c, const LaboratorioMlScreen()),
  ),
];
