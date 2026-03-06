// lib/screens/home_screen.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import './admin_users_screen.dart';
import '../models/current_user.dart';
import './cards_catalog_screen.dart';
import './teams_screen.dart';
import './create_deck_screen.dart';
import './my_decks_screen.dart';
import './profile_screen.dart';
import './new_card_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import './communities_screen.dart';
import './match_screen.dart';
import './friends_screen.dart';
import './wishlist_screen.dart';
import './tournaments/tournaments_screen.dart';
import './submissions_screen.dart';
import './feature_grouping_screen.dart';





enum MenuSection { none, jugar, mazos, cartas, social }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  MenuSection _selected = MenuSection.none;

  // Fondo seleccionado
  String _selectedBg = 'assets/wallpaper/1.jpg';

  @override
  void initState() {
    super.initState();
    _loadBg();
    // Nota: NO llamamos a _loadUserGreeting() porque ahora usamos Provider CurrentUser.
  }


Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sesión cerrada')),
    );
  }

  // ==========================
  // Navegaciones reales
  // ==========================
  void _goFriends() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FriendsScreen()),
    );
  }

  void _goCreateDeck() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const CreateDeckScreen()),
      );

  void _goMyDecks() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const MyDecksScreen()),
      );

  void _goCatalog() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const CardsCatalogScreen()),
      );

  void _goNewCard() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const NewCardScreen()),
      );


  // ==========================
  // Acciones dummy
  // ==========================
  void _openGoldCurve() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Curva de oro')),
    );
  }

  void _openTypeBreakdown() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cartas por tipo')),
    );
  }

  void _openImportExport() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Importar / Exportar')),
    );
  }

  void _openDataTools() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Herramientas de datos')),
    );
  }

  // ==========================
  // Fondo
  // ==========================
  Future<void> _loadBg() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedBg = prefs.getString('background') ?? 'assets/wallpaper/1.jpg';
    });
  }

  Future<void> _setBg(String asset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('background', asset);
    setState(() => _selectedBg = asset);
  }

  void _openBgSelector() {
    showModalBottomSheet(
      context: context,
      builder: (_) {
        final fondos = [
          'assets/wallpaper/1.jpg',
          'assets/wallpaper/2.jpg',
          'assets/wallpaper/3.png',
          'assets/wallpaper/4.jpg',
          'assets/wallpaper/5.jpg',
          'assets/wallpaper/6.jpg',
        ];
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: fondos.length,
          itemBuilder: (_, i) {
            final asset = fondos[i];
            final selected = _selectedBg == asset;
            return GestureDetector(
              onTap: () {
                Navigator.pop(context);
                _setBg(asset);
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(asset, fit: BoxFit.cover),
                  if (selected)
                    Container(
                      color: Colors.black45,
                      child: const Icon(Icons.check, color: Colors.white, size: 40),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ==========================
  // UI
  // ==========================
  @override
  Widget build(BuildContext context) {
    // Usamos Provider CurrentUser en toda la pantalla
    final cu = context.watch<CurrentUser>();

    final isWide = MediaQuery.of(context).size.width > 700; // breakpoint

    return Scaffold(
      drawer: isWide
          ? null
          : Drawer(
              child: _LeftBar(
                displayName: cu.displayName,
                email: cu.email,
                userRole: cu.role,
                selected: _selected,
                onSelect: (s) {
                  setState(() => _selected = s);
                  Navigator.pop(context); // cierra drawer
                },
                onLogout: _logout,
                onOpenFriends: _goFriends,
                currentUid: cu.uid, onAddUser: () {  },
              ),
            ),
      appBar: isWide
          ? null
          : AppBar(
              title: Text(cu.displayName ?? cu.email ?? "MyL Decks"),
              backgroundColor: Colors.black.withOpacity(0.6),
              actions: [
                IconButton(
                  icon: const Icon(Icons.wallpaper),
                  tooltip: "Cambiar fondo",
                  onPressed: _openBgSelector,
                ),
              ],
            ),
      body: Stack(
        children: [
          // Fondo
          Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage(_selectedBg),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Container(color: Colors.black.withOpacity(0.4)),

          if (isWide)
            Row(
              children: [
                _LeftBar(
                  displayName: cu.displayName,
                  email: cu.email,
                  userRole: cu.role,
                  selected: _selected,
                  onSelect: (s) => setState(() => _selected = s),
                  onLogout: _logout,
                  onOpenFriends: _goFriends,
                  currentUid: cu.uid, onAddUser: () {  },
                ),
                Expanded(child: _buildPanel()),
              ],
            )
          else
            _buildPanel(),

          // botón fondo solo en pantallas anchas
          if (isWide)
            Positioned(
              right: 16,
              top: 40,
              child: IconButton(
                icon: const Icon(Icons.wallpaper, color: Colors.white, size: 30),
                tooltip: "Cambiar fondo",
                onPressed: _openBgSelector,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPanel() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: _selected == MenuSection.none
          ? const _CenterHint(key: ValueKey('hint'))
          : _SubmenuPanel(
              key: ValueKey(_selected),
              section: _selected,
              onCreateDeck: _goCreateDeck,
              onMyDecks: _goMyDecks,
              onCatalog: _goCatalog,
              onAddCard: _goNewCard,
              onGoldCurve: _openGoldCurve,
              onTypeBreakdown: _openTypeBreakdown,
              onImportExport: _openImportExport,
              onDataTools: _openDataTools,
            ),
    );
  }
}

/* -------------------------
   LEFT BAR (actualizado)
   ------------------------- */
class _LeftBar extends StatelessWidget {
  final String? displayName;
  final String? email;
  final String? userRole; // <- nuevo
  final MenuSection selected;
  final ValueChanged<MenuSection> onSelect;
  final VoidCallback onAddUser;
  final VoidCallback onLogout;
  final VoidCallback onOpenFriends;
  final String? currentUid;

  const _LeftBar({
    required this.displayName,
    required this.email,
    required this.userRole,
    required this.selected,
    required this.onSelect,
    required this.onAddUser,
    required this.onLogout,
    required this.onOpenFriends,
    required this.currentUid,
  });

  @override
  Widget build(BuildContext context) {
    const double width = 270;
    return SizedBox(
      width: width,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            color: Colors.black.withOpacity(0.35),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Saludo
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Hola, ${displayName ?? (email ?? 'Jugador')}',
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

                // Rol del usuario (si está disponible)
                if (userRole != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    userRole!.toUpperCase(),
                    style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ],

                const SizedBox(height: 18),

                _SideItem(
                  icon: Icons.sports_esports_outlined,
                  label: 'Jugar',
                  selected: selected == MenuSection.jugar,
                  onTap: () => onSelect(MenuSection.jugar),
                ),
                _SideItem(
                  icon: Icons.collections_bookmark_outlined,
                  label: 'Mazos',
                  selected: selected == MenuSection.mazos,
                  onTap: () => onSelect(MenuSection.mazos),
                ),
                _SideItem(
                  icon: Icons.style,
                  label: 'Cartas',
                  selected: selected == MenuSection.cartas,
                  onTap: () => onSelect(MenuSection.cartas),
                ),
                _SideItem(
                  icon: Icons.dataset_outlined,
                  label: 'Social',
                  selected: selected == MenuSection.social,
                  onTap: () => onSelect(MenuSection.social),
                ),
                const Spacer(),

                Row(
  children: [
    NotificationsButton(currentUid: currentUid, userRole: userRole),

    const SizedBox(width: 12),
    _CircleBtn(icon: Icons.dark_mode),
    const SizedBox(width: 12),
    _FriendsButton(
      currentUid: currentUid,
      onTap: onOpenFriends,
    ),
    const SizedBox(width: 12),
    // Botón Admin: solo visible si es administrador
    if (userRole == 'administrador') ...[
      _CircleBtn(
        icon: Icons.admin_panel_settings,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AdminUsersScreen()),
          );
        },
      ),
      const SizedBox(width: 12),
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

/* -------------------------
   FRIENDS BUTTON
   ------------------------- */
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
      stream: FirebaseFirestore.instance
          .collection('friend_requests')
          .where('toUid', isEqualTo: currentUid)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snap) {
        final count = (snap.data?.docs.length ?? 0);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            _CircleBtn(icon: Icons.group, onTap: onTap),
            if (count > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
                  ),
                  constraints: const BoxConstraints(minWidth: 20),
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
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

class _CenterHint extends StatelessWidget {
  const _CenterHint({super.key});
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Selecciona una opción',
        style: TextStyle(color: Colors.white70, fontSize: 22, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _SubmenuPanel extends StatelessWidget {
  final MenuSection section;

  final VoidCallback onCreateDeck;
  final VoidCallback onMyDecks;
  final VoidCallback onCatalog;
  final VoidCallback onAddCard;
  final VoidCallback onGoldCurve;
  final VoidCallback onTypeBreakdown;
  final VoidCallback onImportExport;
  final VoidCallback onDataTools;

  const _SubmenuPanel({
    super.key,
    required this.section,
    required this.onCreateDeck,
    required this.onMyDecks,
    required this.onCatalog,
    required this.onAddCard,
    required this.onGoldCurve,
    required this.onTypeBreakdown,
    required this.onImportExport,
    required this.onDataTools,
  });

  void _showWorkInProgress(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.36,
      minChildSize: 0.2,
      maxChildSize: 0.8,
      builder: (context, scrollController) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: Theme.of(context).dialogBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 12,
              offset: const Offset(0, -4),
            )
          ],
        ),
        child: SingleChildScrollView(
          controller: scrollController,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 14),
              Icon(Icons.construction, size: 52, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                'En construcción',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Estamos afinando los detalles para Partida normal. Pronto estará disponible para todos (o solo para quien deba tenerlo).',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Entendido'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}


  @override
  Widget build(BuildContext context) {
    final items = _itemsForSection(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, i) {
          final it = items[i];
          return _PanelRow(
            icon: it.icon,
            title: it.title,
            subtitle: it.subtitle,
            onTap: it.onTap,
          );
        },
      ),
    );
  }

  List<_RowItem> _itemsForSection(BuildContext context) {
    switch (section) {
      case MenuSection.jugar:
  final userEmail = FirebaseAuth.instance.currentUser?.email?.toLowerCase();
  const allowedEmail = 'hecturnicolas@gmail.com';

  return [
    _RowItem(
      Icons.sports_kabaddi,
      'Partida normal',
      'Mejor de 3',
      () {
        if (userEmail == allowedEmail) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MatchScreen()),
          );
        } else {
          _showWorkInProgress(context);
        }
      },
    ),
  ];

      case MenuSection.mazos:
        return [
          _RowItem(Icons.add_box_outlined, 'Crear mazo', 'Empieza uno nuevo', onCreateDeck),
          _RowItem(Icons.collections_bookmark_outlined, 'Todos mis mazos', 'Ver / editar', onMyDecks),
        ];
      case MenuSection.cartas:
  return [
    _RowItem(Icons.style, 'Nueva carta', 'Agregar a la base', onAddCard),
    _RowItem(Icons.manage_search, 'Explorar cartas', 'Filtrar por edición/tipo', onCatalog),
    _RowItem(
      Icons.favorite_border,
      'Lista de deseos',
      'Cartas que quiero conseguir',
      () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const WishlistScreen()),
        );
      },
    ),
    // ↓ Nuevo item justo debajo de “Lista de deseos”
    _RowItem(
      Icons.category_outlined,
      'Agrupar características',
      'Crear grupos y arrastrar features',
      () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const FeatureGroupingScreen(
              // Todo libre, sin seed:
              initialGroups: {},              // opcional (vacío por defecto)
              // canonicalFeaturesOverride: [], // descomenta si NO quieres canónicas base
              // disableFirestore: true,       // para pruebas locales sin nube
            ),
          ),
        );
      },
    ),
  ];

      case MenuSection.social:
  final userEmail = FirebaseAuth.instance.currentUser?.email?.toLowerCase();
  const allowedEmail = 'hecturnicolas@gmail.com';

  return [
    _RowItem(
      Icons.forum_outlined,
      'Comunidades',
      'Foro • Miembros • Videos',
      () {
        if (userEmail == allowedEmail) {
          const communityId = 'global';
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => CommunitiesScreen(communityId: communityId)),
          );
        } else {
          _showWorkInProgress(context);
        }
      },
    ),
    _RowItem(
      Icons.flag,
      'Torneos',
      'Gestionar eventos y partidas',
      () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TournamentsScreen()));
      },
    ),
    _RowItem(
      Icons.groups_2_outlined,
      'Teams',
      'Crea o únete a un equipo',
      () {
        if (userEmail == allowedEmail) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeamsScreen()));
        } else {
          _showWorkInProgress(context);
        }
      },
    ),
    _RowItem(
      Icons.person_outline,
      'Perfil',
      'Tu cuenta y estadísticas',
      () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
      },
    ),
  ];

      case MenuSection.none:
        return const [];
    }
  }
}

class _PanelRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PanelRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.12),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 70,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.help_outline, color: Colors.white70),
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
  final VoidCallback onTap;
  _RowItem(this.icon, this.title, this.subtitle, this.onTap);
}
