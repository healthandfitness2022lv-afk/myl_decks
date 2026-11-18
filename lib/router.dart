// lib/router.dart
// Rutas reales para web: URLs compartibles, botón atrás del navegador
// y deep links. Cada ruta protegida pasa por _AuthGuard.
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import 'services/deck_service.dart';
import 'screens/login_screen.dart';
import 'screens/nexus_home_screen.dart';
import 'screens/home_screen.dart';
import 'screens/card_inventory_screen.dart';
import 'screens/cards_catalog_screen.dart';
import 'screens/deck_by_id_screen.dart';
import 'screens/meta_stats_screen.dart';
import 'screens/create_deck_screen.dart';
import 'screens/my_decks_screen.dart';
import 'screens/wishlist_screen.dart';
import 'screens/friends_screen.dart';
import 'screens/communities_screen.dart';
import 'screens/teams_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/leagues/team_screen.dart';
import 'screens/simulador/entrenamiento_screen.dart';
import 'screens/tournaments/tournament_detail_screen.dart';
import 'screens/tournaments/tournaments_screen.dart';

/// Muestra login si no hay sesión; el destino pedido cuando la hay.
class _AuthGuard extends StatelessWidget {
  final Widget child;
  const _AuthGuard({required this.child});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasData) return child;
        return const LoginScreen();
      },
    );
  }
}

final GoRouter appRouter = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (_, __) {
        return StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (_, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return snapshot.hasData
                ? const HomeScreen()
                : const NexusHomeScreen();
          },
        );
      },
    ),
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(
      path: '/inventario',
      builder: (_, __) => const _AuthGuard(child: _InventoryRoute()),
    ),
    GoRoute(
      path: '/catalogo',
      builder: (_, __) => const _AuthGuard(child: CardsCatalogScreen()),
    ),
    GoRoute(
      path: '/meta',
      builder: (_, __) => const _AuthGuard(child: MetaStatsScreen()),
    ),
    GoRoute(
      path: '/mazos',
      builder: (_, __) => const _AuthGuard(child: MyDecksScreen()),
    ),
    GoRoute(
      path: '/mazos/nuevo',
      builder: (_, __) => const _AuthGuard(child: CreateDeckScreen()),
    ),
    GoRoute(
      path: '/wishlist',
      builder: (_, __) => const _AuthGuard(child: WishlistScreen()),
    ),
    GoRoute(
      path: '/amigos',
      builder: (_, __) => const _AuthGuard(child: FriendsScreen()),
    ),
    GoRoute(
      path: '/comunidades/:id',
      builder:
          (_, state) => _AuthGuard(
            child: CommunitiesScreen(
              communityId: state.pathParameters['id'] ?? 'global',
            ),
          ),
    ),
    GoRoute(
      path: '/teams',
      builder: (_, __) => const _AuthGuard(child: TeamsScreen()),
    ),
    GoRoute(
      path: '/teams/:id',
      builder:
          (_, state) => _AuthGuard(
            child: _TeamByIdScreen(teamId: state.pathParameters['id'] ?? ''),
          ),
    ),
    GoRoute(
      path: '/entrenamiento',
      builder: (_, __) => const _AuthGuard(child: EntrenamientoScreen()),
    ),
    GoRoute(
      path: '/torneos',
      builder: (_, __) => const _AuthGuard(child: TournamentsScreen()),
    ),
    GoRoute(
      path: '/torneos/:id',
      builder:
          (_, state) => _AuthGuard(
            child: TournamentDetailScreen(
              torneoId: state.pathParameters['id'] ?? '',
            ),
          ),
    ),
    GoRoute(
      path: '/perfil',
      builder: (_, __) => const _AuthGuard(child: ProfileScreen()),
    ),
    GoRoute(
      path: '/mazo/:uid/:id',
      builder:
          (_, state) => _AuthGuard(
            child: DeckByIdScreen(
              ownerId: state.pathParameters['uid'] ?? '',
              deckId: state.pathParameters['id'] ?? '',
            ),
          ),
    ),
  ],
  // Cualquier URL desconocida vuelve al home.
  errorBuilder: (_, __) => const NexusHomeScreen(),
);

class _InventoryRoute extends StatelessWidget {
  const _InventoryRoute();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const LoginScreen();
    return StreamBuilder(
      stream: DeckService(uid).watchMyDecks(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(child: Text('Error: ${snapshot.error}')),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final decks = snapshot.data!;
        return CardInventoryScreen(
          decks: decks,
          targetDecks:
              decks
                  .where(
                    (deck) =>
                        deck.isUnified ? deck.assemblyEnabled : deck.isTarget,
                  )
                  .toList(),
        );
      },
    );
  }
}

class _TeamByIdScreen extends StatelessWidget {
  final String teamId;
  const _TeamByIdScreen({required this.teamId});

  Widget _backButtonScaffold(
    BuildContext context,
    String title,
    String message,
  ) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            const SizedBox(height: 16),
            FilledButton(
              onPressed:
                  () =>
                      Navigator.of(context).canPop()
                          ? Navigator.of(context).pop()
                          : context.go('/'),
              child: const Text('Volver'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('teams').doc(teamId).get(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _backButtonScaffold(
            context,
            'Error',
            'Error: ${snapshot.error}',
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snapshot.data!.data();
        if (data == null) {
          return _backButtonScaffold(
            context,
            'Team no encontrado',
            'Este team no existe o fue eliminado.',
          );
        }
        return TeamDetailScreen(
          teamId: teamId,
          teamName: (data['name'] ?? 'Team').toString(),
          adminUid: (data['ownerId'] ?? data['adminUid'] ?? '').toString(),
        );
      },
    );
  }
}
