// lib/screens/teams_screen.dart
// Redirige al nuevo sistema de teams integrado con ligas.
export 'package:myl_decks/screens/leagues/team_screen.dart'
    show TeamsListScreen;

import 'package:flutter/material.dart';
import 'leagues/team_screen.dart';

class TeamsScreen extends StatelessWidget {
  const TeamsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const TeamsListScreen();
  }
}
