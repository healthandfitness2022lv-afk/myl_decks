import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import '../models/current_user.dart';
import '../services/drive_service.dart';
import '../widgets/drive_image_picker.dart';
import '../utils/wallpaper_image.dart';
import './admin_users_screen.dart';
import './admin_bulk_assign_screen.dart';
import './ban_list_screen.dart';
import './submissions_screen.dart';

enum MenuSection { mazos, cartas, social }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  MenuSection _selected = MenuSection.mazos;
  String _selectedBg = '';

  @override
  void initState() {
    super.initState();
    _loadBg();
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Sesión cerrada')));
  }

  void _goFriends() {
    context.push('/amigos');
  }

  void _goCreateDeck() => context.push('/mazos/nuevo');

  void _goMyDecks() => context.push('/mazos');

  void _goCatalog() => context.push('/catalogo');

  Future<void> _loadBg() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _selectedBg = prefs.getString('background') ?? '';
    });
  }

  Future<void> _setBg(String asset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('background', asset);
    if (!mounted) return;
    setState(() => _selectedBg = asset);
  }

  Future<void> _openBgSelector() async {
    final result = await showRaceWallpaperPicker(
      context,
      rootFolderId: DriveService.wallpaperRootFolderId,
    );
    if (result == null) return;
    await _setBg(result.viewUrl);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<CurrentUser>();
    final isWide = MediaQuery.of(context).size.width > 700;

    return Scaffold(
      appBar:
          isWide
              ? null
              : AppBar(
                title: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield_rounded, color: Color(0xFFF1D48B)),
                    SizedBox(width: 9),
                    Text('MyL Mazos'),
                  ],
                ),
                backgroundColor: Colors.black.withOpacity(0.6),
                actions: [
                  NotificationsButton(
                    currentUid: currentUser.uid,
                    userRole: currentUser.role,
                  ),
                  IconButton(
                    icon: const Icon(Icons.wallpaper),
                    tooltip: 'Cambiar fondo',
                    onPressed: _openBgSelector,
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Cuenta',
                    onSelected: (value) {
                      if (value == 'profile') context.push('/perfil');
                      if (value == 'logout') _logout();
                    },
                    itemBuilder:
                        (_) => const [
                          PopupMenuItem(
                            value: 'profile',
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.person_outline),
                              title: Text('Mi perfil'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'logout',
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.logout),
                              title: Text('Cerrar sesión'),
                            ),
                          ),
                        ],
                  ),
                ],
              ),
      bottomNavigationBar:
          isWide
              ? null
              : NavigationBar(
                height: 68,
                backgroundColor: const Color(0xFF11141B),
                indicatorColor: const Color(0xFFF1D48B).withOpacity(0.18),
                selectedIndex: _selected.index,
                onDestinationSelected:
                    (index) =>
                        setState(() => _selected = MenuSection.values[index]),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.style_outlined),
                    selectedIcon: Icon(Icons.style_rounded),
                    label: 'Mazos',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.inventory_2_outlined),
                    selectedIcon: Icon(Icons.inventory_2_rounded),
                    label: 'Colección',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.groups_outlined),
                    selectedIcon: Icon(Icons.groups_rounded),
                    label: 'Comunidad',
                  ),
                ],
              ),
      body: Stack(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color:
                  isWallpaperUnset(_selectedBg) ? wallpaperFallbackColor : null,
              image:
                  isWallpaperUnset(_selectedBg)
                      ? null
                      : DecorationImage(
                        image: wallpaperImageProvider(_selectedBg),
                        fit: BoxFit.cover,
                      ),
            ),
            child: const SizedBox.expand(),
          ),
          Container(color: Colors.black.withOpacity(0.42)),
          if (isWide)
            Row(
              children: [
                _LeftBar(
                  displayName: currentUser.displayName,
                  email: currentUser.email,
                  userRole: currentUser.role,
                  selected: _selected,
                  onSelect: (section) => setState(() => _selected = section),
                  onLogout: _logout,
                  onOpenFriends: _goFriends,
                  currentUid: currentUser.uid,
                ),
                Expanded(child: _buildPanel()),
              ],
            )
          else
            SafeArea(child: _buildPanel()),
          if (isWide)
            Positioned(
              right: 16,
              top: 40,
              child: IconButton(
                icon: const Icon(
                  Icons.wallpaper,
                  color: Colors.white,
                  size: 30,
                ),
                tooltip: 'Cambiar fondo',
                onPressed: _openBgSelector,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPanel() {
    final currentUser = context.watch<CurrentUser>();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: _SubmenuPanel(
        key: ValueKey(_selected),
        section: _selected,
        isAdmin: currentUser.role == 'administrador',
        onCreateDeck: _goCreateDeck,
        onMyDecks: _goMyDecks,
        onCatalog: _goCatalog,
      ),
    );
  }
}

class _LeftBar extends StatelessWidget {
  final String? displayName;
  final String? email;
  final String? userRole;
  final MenuSection selected;
  final ValueChanged<MenuSection> onSelect;
  final VoidCallback onLogout;
  final VoidCallback onOpenFriends;
  final String? currentUid;

  const _LeftBar({
    required this.displayName,
    required this.email,
    required this.userRole,
    required this.selected,
    required this.onSelect,
    required this.onLogout,
    required this.onOpenFriends,
    required this.currentUid,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 270,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            color: Colors.black.withOpacity(0.35),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Hola, ${displayName ?? email ?? 'Jugador'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.shield, color: Color(0xFFF9D74B)),
                  ],
                ),
                if (userRole != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    userRole!.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                _SideItem(
                  icon: Icons.style_outlined,
                  label: 'Mazos',
                  selected: selected == MenuSection.mazos,
                  onTap: () => onSelect(MenuSection.mazos),
                ),
                _SideItem(
                  icon: Icons.inventory_2_outlined,
                  label: 'Colección',
                  selected: selected == MenuSection.cartas,
                  onTap: () => onSelect(MenuSection.cartas),
                ),
                _SideItem(
                  icon: Icons.groups_outlined,
                  label: 'Comunidad',
                  selected: selected == MenuSection.social,
                  onTap: () => onSelect(MenuSection.social),
                ),
                const Spacer(),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    NotificationsButton(
                      currentUid: currentUid,
                      userRole: userRole,
                    ),
                    _FriendsButton(
                      currentUid: currentUid,
                      onTap: onOpenFriends,
                    ),
                    if (userRole == 'administrador') ...[
                      _CircleBtn(
                        icon: Icons.admin_panel_settings,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AdminUsersScreen(),
                            ),
                          );
                        },
                      ),
                      _CircleBtn(
                        icon: Icons.photo_library_rounded,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AdminBulkAssignScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                    _CircleBtn(icon: Icons.logout, onTap: onLogout),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FriendsButton extends StatelessWidget {
  final String? currentUid;
  final VoidCallback onTap;

  const _FriendsButton({required this.currentUid, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (currentUid == null) {
      return _CircleBtn(icon: Icons.group, onTap: onTap);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance
              .collection('friend_requests')
              .where('toUid', isEqualTo: currentUid)
              .where('status', isEqualTo: 'pending')
              .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            _CircleBtn(icon: Icons.group, onTap: onTap),
            if (count > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  constraints: const BoxConstraints(minWidth: 20),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(blurRadius: 4, color: Colors.black26),
                    ],
                  ),
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SideItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SideItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 58,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? Colors.white.withOpacity(0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _CircleBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}

class _SubmenuPanel extends StatelessWidget {
  final MenuSection section;
  final bool isAdmin;
  final VoidCallback onCreateDeck;
  final VoidCallback onMyDecks;
  final VoidCallback onCatalog;

  const _SubmenuPanel({
    super.key,
    required this.section,
    required this.isAdmin,
    required this.onCreateDeck,
    required this.onMyDecks,
    required this.onCatalog,
  });

  @override
  Widget build(BuildContext context) {
    final items = _itemsForSection(context);
    final title = switch (section) {
      MenuSection.mazos => 'Tus mazos',
      MenuSection.cartas => 'Tu colección',
      MenuSection.social => 'Comunidad',
    };
    final subtitle = switch (section) {
      MenuSection.mazos => 'Construye, organiza y revisa tus mazos.',
      MenuSection.cartas => 'Controla tus copias, faltantes y deseos.',
      MenuSection.social => 'Conecta, compite y comparte con otros jugadores.',
    };
    final icon = switch (section) {
      MenuSection.mazos => Icons.style_rounded,
      MenuSection.cartas => Icons.inventory_2_rounded,
      MenuSection.social => Icons.groups_rounded,
    };
    final accent = switch (section) {
      MenuSection.mazos => const Color(0xFF78A9FF),
      MenuSection.cartas => const Color(0xFF5DD69E),
      MenuSection.social => const Color(0xFFC79BF2),
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        return ListView(
          padding: EdgeInsets.fromLTRB(
            constraints.maxWidth < 600 ? 16 : 32,
            24,
            constraints.maxWidth < 600 ? 16 : 32,
            28,
          ),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: accent.withOpacity(0.35)),
                  ),
                  child: Icon(icon, color: accent, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Column(
                  children: [
                    for (var index = 0; index < items.length; index++) ...[
                      if (index > 0) const SizedBox(height: 11),
                      _PanelRow(
                        icon: items[index].icon,
                        title: items[index].title,
                        subtitle: items[index].subtitle,
                        onTap: items[index].onTap,
                        enabled: items[index].enabled,
                        accent: accent,
                        featured: items[index].featured,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<_RowItem> _itemsForSection(BuildContext context) {
    switch (section) {
      case MenuSection.mazos:
        return [
          _RowItem(
            Icons.collections_bookmark_rounded,
            'Mis mazos',
            'Ver, completar y editar tus mazos',
            onMyDecks,
            featured: true,
          ),
          _RowItem(
            Icons.add_circle_outline_rounded,
            'Nuevo mazo',
            'Crea una lista sin elegir variantes',
            onCreateDeck,
          ),
          _RowItem(
            Icons.fitness_center_rounded,
            'Entrenamiento',
            'Sube de rating contra mazos del meta',
            () => context.push('/entrenamiento'),
          ),
          _RowItem(
            Icons.insights_rounded,
            'Meta y tendencias',
            'Qué se juega y qué gana: agro o control',
            () => context.push('/meta'),
          ),
        ];
      case MenuSection.cartas:
        return [
          _RowItem(
            Icons.inventory_2_rounded,
            'Mi colección',
            'Copias libres, asignadas y faltantes',
            () => context.push('/inventario'),
            featured: true,
          ),
          _RowItem(
            Icons.favorite_border_rounded,
            'Wishlist',
            'Faltantes automáticos y deseos personales',
            () => context.push('/wishlist'),
          ),
          _RowItem(
            Icons.manage_search_rounded,
            'Catálogo de cartas',
            'Busca por nombre, edición o tipo',
            onCatalog,
          ),
        ];
      case MenuSection.social:
        return [
          _RowItem(
            Icons.forum_rounded,
            'Comunidades',
            'Conversaciones, miembros y contenido',
            () => context.push('/comunidades/global'),
            featured: true,
          ),
          _RowItem(
            Icons.people_alt_outlined,
            'Amigos',
            'Solicitudes y jugadores conectados',
            () => context.push('/amigos'),
          ),
          _RowItem(
            Icons.emoji_events_outlined,
            'Torneos',
            'Suizo con top: inscríbete u organiza uno',
            () => context.push('/torneos'),
          ),
          _RowItem(
            Icons.groups_2_outlined,
            'Equipos y ligas',
            'Teams, competencias y posiciones',
            () => context.push('/teams'),
          ),
          _RowItem(
            Icons.person_outline,
            'Mi perfil',
            'Cuenta, actividad y estadísticas',
            () => context.push('/perfil'),
          ),
          if (isAdmin)
            _RowItem(
              Icons.block,
              'Ban List',
              'Administrar cartas prohibidas o limitadas',
              () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const BanListScreen())),
            ),
        ];
    }
  }
}

class _PanelRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool enabled;
  final Color accent;
  final bool featured;

  const _PanelRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.accent,
    this.enabled = true,
    this.featured = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color:
          enabled
              ? featured
                  ? accent.withOpacity(0.18)
                  : Colors.white.withOpacity(0.10)
              : Colors.white.withOpacity(0.07),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 76,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: featured ? accent.withOpacity(0.5) : Colors.white10,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (enabled ? accent : Colors.white54).withOpacity(0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  enabled ? icon : Icons.lock_clock_outlined,
                  color: enabled ? accent : Colors.white60,
                  size: 24,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: enabled ? Colors.white : Colors.white70,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: enabled ? Colors.white60 : Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                enabled ? Icons.chevron_right_rounded : Icons.lock_outline,
                color: enabled ? Colors.white54 : Colors.white38,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RowItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool enabled;
  final bool featured;

  const _RowItem(
    this.icon,
    this.title,
    this.subtitle,
    this.onTap, {
    this.enabled = true,
    this.featured = false,
  });
}
