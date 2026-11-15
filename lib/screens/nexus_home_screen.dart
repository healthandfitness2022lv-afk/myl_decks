import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/current_user.dart';

class NexusHomeScreen extends StatelessWidget {
  const NexusHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<CurrentUser>();
    final signedIn = FirebaseAuth.instance.currentUser != null;
    final width = MediaQuery.sizeOf(context).width;
    final sections = <_NexusSection>[
      const _NexusSection(
        title: 'Jugar',
        subtitle: 'Mazos, objetivos, comparación y ligas',
        icon: Icons.sports_esports_rounded,
        color: Color(0xFF5B8DEF),
        primaryLabel: 'Mis mazos',
        primaryRoute: '/mazos',
        secondaryLabel: 'Meta',
        secondaryRoute: '/meta',
      ),
      const _NexusSection(
        title: 'Mi carpeta',
        subtitle: 'Inventario, armabilidad, wishlist y planes',
        icon: Icons.auto_awesome_mosaic_rounded,
        color: Color(0xFF2ECC71),
        primaryLabel: 'Inventario',
        primaryRoute: '/inventario',
        secondaryLabel: 'Wishlist',
        secondaryRoute: '/wishlist',
      ),
      const _NexusSection(
        title: 'Comunidad',
        subtitle: 'Amigos, comunidades, equipos y estadísticas',
        icon: Icons.groups_rounded,
        color: Color(0xFFBB86FC),
        primaryLabel: 'Comunidades',
        primaryRoute: '/comunidades/global',
        secondaryLabel: 'Equipos',
        secondaryRoute: '/teams',
      ),
    ];
    final columns =
        width >= 1050
            ? sections.length.clamp(1, 4)
            : width >= 620
            ? 2
            : 1;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.shield_rounded,
              color: Color(0xFFF1D48B),
              size: 32,
            ),
            const SizedBox(width: 10),
            const Text('MyL Mazos'),
          ],
        ),
        actions: [
          if (signedIn)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text(user.displayName ?? user.email ?? 'Jugador'),
              ),
            ),
          TextButton.icon(
            onPressed:
                signedIn
                    ? () => FirebaseAuth.instance.signOut()
                    : () => context.push('/login'),
            icon: Icon(signedIn ? Icons.logout : Icons.login),
            label: Text(signedIn ? 'Salir' : 'Ingresar'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF080A0F), Color(0xFF151B27)],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 40, 20, 40),
          children: [
            Text(
              'Arma tus mazos y controla tu colección en un solo lugar',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              signedIn
                  ? 'Administra tus cartas y conecta con la comunidad.'
                  : 'Explora la plataforma. Inicia sesión para usar funciones personales.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 34),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: columns == 1 ? 1.65 : 0.94,
              ),
              itemCount: sections.length,
              itemBuilder: (_, index) => _SectionCard(section: sections[index]),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final _NexusSection section;
  const _SectionCard({required this.section});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF13171F),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(section.icon, size: 44, color: section.color),
            const SizedBox(height: 16),
            Text(
              section.title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                section.subtitle,
                style: const TextStyle(color: Colors.white70, height: 1.35),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => context.push(section.primaryRoute),
                style: FilledButton.styleFrom(
                  backgroundColor: section.color,
                  foregroundColor: Colors.black,
                ),
                child: Text(section.primaryLabel),
              ),
            ),
            TextButton(
              onPressed: () => context.push(section.secondaryRoute),
              child: Text(section.secondaryLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _NexusSection {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String primaryLabel;
  final String primaryRoute;
  final String secondaryLabel;
  final String secondaryRoute;

  const _NexusSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.primaryLabel,
    required this.primaryRoute,
    required this.secondaryLabel,
    required this.secondaryRoute,
  });
}
