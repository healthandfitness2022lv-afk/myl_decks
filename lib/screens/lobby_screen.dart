// lib/screens/lobby_screen.dart (ejemplo)
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'match_details_screen.dart';

class LobbyScreen extends StatefulWidget {
  final String currentUserId; // pásale el UID logueado

  const LobbyScreen({super.key, required this.currentUserId});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  StreamSubscription<QuerySnapshot>? _sub;
  final Set<String> _opened = <String>{}; // para no abrir el mismo match 2 veces

  @override
  void initState() {
    super.initState();

    _sub = FirebaseFirestore.instance
        .collection('matches')
        .where('players', arrayContains: widget.currentUserId)
        .where('status', isEqualTo: 'ongoing')
        .snapshots()
        .listen((snap) {
      for (final ch in snap.docChanges) {
        if (ch.type == DocumentChangeType.added ||
            ch.type == DocumentChangeType.modified) {
          final data = ch.doc.data();
          if (data == null) continue;

          final acceptedBy = (data['acceptedBy'] ?? '').toString();
          final matchId = ch.doc.id;

          // Solo dispara en el dispositivo del RIVAL (no quien aceptó)
          if (acceptedBy.isNotEmpty &&
              acceptedBy != widget.currentUserId &&
              !_opened.contains(matchId)) {
            _opened.add(matchId);

            if (!mounted) return;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MatchDetailsScreen(
                  matchId: matchId,
                  autoOpenBattlefield: true, // si quieres salto automático
                ),
              ),
            );
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // tu UI normal del Lobby/Home aquí
    return Scaffold(
      appBar: AppBar(title: const Text('Lobby')),
      body: const Center(child: Text('Esperando desafíos…')),
    );
  }
}