import 'dart:math' as math;
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/wallpaper_image.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  static const String _logoAsset = 'assets/nexus tcg.png';
  late final TabController _tab;
  late final AnimationController _fx;

  final _loginEmailCtrl = TextEditingController();
  final _loginPassCtrl = TextEditingController();
  final _regUserCtrl = TextEditingController();
  final _regEmailCtrl = TextEditingController();
  final _regPassCtrl = TextEditingController();
  final _regPass2Ctrl = TextEditingController();

  bool _loginObscure = true;
  bool _regObscure = true;
  bool _regObscure2 = true;
  bool _loading = false;
  List<String> _recentEmails = [];
  String _bg = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _fx = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);
    _loadBg();
    _loadRecentEmails();
  }

  @override
  void dispose() {
    _tab.dispose();
    _fx.dispose();
    _loginEmailCtrl.dispose();
    _loginPassCtrl.dispose();
    _regUserCtrl.dispose();
    _regEmailCtrl.dispose();
    _regPassCtrl.dispose();
    _regPass2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadBg() async {
    final sp = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _bg = sp.getString('background') ?? '');
  }

  Future<void> _loadRecentEmails() async {
    final sp = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _recentEmails = sp.getStringList('recent_emails') ?? []);
  }

  Future<void> _saveRecentEmail(String email) async {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList('recent_emails') ?? [];
    if (!list.contains(email)) {
      list.insert(0, email);
      if (list.length > 5) list.removeLast();
      await sp.setStringList('recent_emails', list);
      if (mounted) setState(() => _recentEmails = list);
    }
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _login() async {
    final email = _loginEmailCtrl.text.trim();
    final pass = _loginPassCtrl.text;
    if (email.isEmpty || pass.isEmpty) {
      _snack('Ingresa correo y contraseña.');
      return;
    }

    try {
      setState(() => _loading = true);
      final userCred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: pass,
      );
      await _saveRecentEmail(email);

      final uid = FirebaseAuth.instance.currentUser!.uid;
      final userDocRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid);
      final userSnap = await userDocRef.get();
      Map<String, dynamic> data;
      if (!userSnap.exists) {
        data = {
          'username': userCred.user?.displayName ?? '',
          'displayName': userCred.user?.displayName ?? '',
          'email': email,
          'createdAt': FieldValue.serverTimestamp(),
          'active': true,
          'role': 'basico',
          'maxDecks': 3,
          'canUploadImages': false,
        };
        await userDocRef.set(data, SetOptions(merge: true));
      } else {
        data = userSnap.data() ?? {};
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_role', (data['role'] as String?) ?? 'basico');
      await prefs.setInt(
        'user_maxDecks',
        data['maxDecks'] != null ? (data['maxDecks'] as num).toInt() : 3,
      );
      await prefs.setBool(
        'user_canUploadImages',
        data['canUploadImages'] == true,
      );
      final displayName =
          (data['displayName'] as String?) ??
          (data['username'] as String?) ??
          FirebaseAuth.instance.currentUser?.displayName;
      final photoUrl =
          (data['photoUrl'] as String?) ??
          FirebaseAuth.instance.currentUser?.photoURL;
      if (displayName != null)
        await prefs.setString('user_displayName', displayName);
      if (photoUrl != null) await prefs.setString('user_photoUrl', photoUrl);
      if (mounted) context.go('/');
    } on FirebaseAuthException catch (e) {
      var msg = 'Error al iniciar sesion.';
      switch (e.code) {
        case 'user-not-found':
          msg = 'Usuario no encontrado.';
          break;
        case 'wrong-password':
          msg = 'Contraseña incorrecta.';
          break;
        case 'invalid-email':
          msg = 'Correo invalido.';
          break;
        case 'user-disabled':
          msg = 'Usuario deshabilitado.';
          break;
      }
      _snack(msg);
    } on FirebaseException catch (e) {
      _snack('Error al cargar perfil: ${e.message ?? e.code}');
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    final username = _regUserCtrl.text.trim();
    final email = _regEmailCtrl.text.trim();
    final pass = _regPassCtrl.text;
    final pass2 = _regPass2Ctrl.text;
    if (username.isEmpty) {
      _snack('Escribe un nombre de usuario.');
      return;
    }
    if (email.isEmpty) {
      _snack('Escribe tu correo.');
      return;
    }
    if (pass.length < 6) {
      _snack('La contraseña debe tener al menos 6 caracteres.');
      return;
    }
    if (pass != pass2) {
      _snack('Las contraseñas no coinciden.');
      return;
    }

    try {
      setState(() => _loading = true);
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: pass,
      );
      await cred.user?.updateDisplayName(username);
      final uid = cred.user!.uid;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'username': username,
        'displayName': username,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
        'active': true,
        'role': 'basico',
        'maxDecks': 3,
        'canUploadImages': false,
      }, SetOptions(merge: true));
      await _saveRecentEmail(email);
      _snack('Cuenta creada. Bienvenido, $username!');
      if (mounted) context.go('/');
    } on FirebaseAuthException catch (e) {
      var msg = 'No se pudo crear la cuenta.';
      switch (e.code) {
        case 'email-already-in-use':
          msg = 'Ese correo ya esta en uso.';
          break;
        case 'invalid-email':
          msg = 'Correo invalido.';
          break;
        case 'weak-password':
          msg = 'Contraseña débil.';
          break;
        case 'operation-not-allowed':
          msg = 'Operación no permitida en Auth.';
          break;
      }
      _snack(msg);
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgot() async {
    final emailCtrl = TextEditingController(text: _loginEmailCtrl.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1612),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            title: const Text(
              'Recuperar contraseña',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            content: TextField(
              controller: emailCtrl,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration(
                label: 'Correo a recuperar',
                hint: 'usuario@dominio.cl',
                icon: Icons.alternate_email_rounded,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, emailCtrl.text.trim()),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8A5A3B),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Enviar correo'),
              ),
            ],
          ),
    );

    if (email == null || email.isEmpty) {
      _snack('Escribe tu correo para enviarte el enlace.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _snack('Te enviamos un correo para restablecer la contraseña.');
    } catch (e) {
      _snack('No se pudo enviar el correo: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width > 980;
    return Scaffold(
      body: AnimatedBuilder(
        animation: _fx,
        builder: (context, _) {
          return Stack(
            fit: StackFit.expand,
            children: [
              _background(),
              SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1180),
                      child:
                          wide
                              ? Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(child: _heroSection()),
                                  const SizedBox(width: 28),
                                  Expanded(child: _authPanel()),
                                ],
                              )
                              : Column(
                                children: [
                                  _heroSection(compact: true),
                                  const SizedBox(height: 24),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 620,
                                    ),
                                    child: _authPanel(),
                                  ),
                                ],
                              ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _background() {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: isWallpaperUnset(_bg) ? wallpaperFallbackColor : null,
            image:
                isWallpaperUnset(_bg)
                    ? null
                    : DecorationImage(
                      image: wallpaperImageProvider(_bg),
                      fit: BoxFit.cover,
                    ),
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xE005080C), Color(0xF0070B11), Color(0xFF090B10)],
            ),
          ),
        ),
        Positioned(
          left: -40,
          top: -80 + (_fx.value * 40),
          child: _orb(260, const Color(0xFFE1A93B).withOpacity(.42)),
        ),
        Positioned(
          right: -70,
          top: 110,
          child: _orb(220, const Color(0xFF2F8DBA).withOpacity(.28)),
        ),
        Positioned(
          bottom: -120,
          left: 60 + (_fx.value * 30),
          child: _orb(320, const Color(0xFF9C352F).withOpacity(.24)),
        ),
        IgnorePointer(child: CustomPaint(painter: _RunePainter(_fx.value))),
      ],
    );
  }

  Widget _heroSection({bool compact = false}) {
    return Padding(
      padding: EdgeInsets.only(
        top: compact ? 8 : 10,
        right: compact ? 0 : 18,
        bottom: 10,
      ),
      child: Column(
        crossAxisAlignment:
            compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Align(
            alignment: compact ? Alignment.center : Alignment.centerLeft,
            child: Image.asset(_logoAsset, height: 56, fit: BoxFit.contain),
          ),
          const SizedBox(height: 18),
          Text(
            'Arma, valida y compara tus mazos de Mitos y Leyendas.',
            textAlign: compact ? TextAlign.center : TextAlign.start,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Lleva el control de tu colección y exporta pósters de tus listas.',
            textAlign: compact ? TextAlign.center : TextAlign.start,
            style: const TextStyle(color: Colors.white70, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _authPanel() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF3E2A1F).withOpacity(.92),
                const Color(0xFF1C130E).withOpacity(.96),
              ],
            ),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.white.withOpacity(.14)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.28),
                blurRadius: 30,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF8A5A3B), Color(0xFF5E3A27)],
                        ),
                      ),
                      child: Image.asset(_logoAsset, fit: BoxFit.contain),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Acceso',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Ingresa a tu cuenta o crea una nueva.',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _tabBar(),
                const SizedBox(height: 18),
                SizedBox(
                  height: 470,
                  child: TabBarView(
                    controller: _tab,
                    children: [_loginTab(), _registerTab()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabBar() {
    return AnimatedBuilder(
      animation: _tab.animation!,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(.26),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(.08)),
          ),
          child: Row(
            children: [
              Expanded(
                child: _TabButton(
                  selected: _tab.index == 0,
                  icon: Icons.login_rounded,
                  label: 'Entrar',
                  onTap: () => _tab.animateTo(0),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TabButton(
                  selected: _tab.index == 1,
                  icon: Icons.person_add_alt_1_rounded,
                  label: 'Crear cuenta',
                  onTap: () => _tab.animateTo(1),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _loginTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Eyebrow(text: 'Inicio de sesion', icon: Icons.login_outlined),
          const SizedBox(height: 10),
          const Text(
            'Entra para seguir tu actividad, mover tus mazos, revisar torneos y mantener tu espacio dentro de la comunidad.',
            style: TextStyle(color: Colors.white70, height: 1.35),
          ),
          const SizedBox(height: 18),
          Autocomplete<String>(
            optionsBuilder: (v) {
              final q = v.text.toLowerCase();
              if (q.isEmpty) return const Iterable<String>.empty();
              return _recentEmails.where((e) => e.toLowerCase().contains(q));
            },
            onSelected: (val) => _loginEmailCtrl.text = val,
            fieldViewBuilder: (_, textCtrl, focus, __) {
              textCtrl.addListener(
                () => _loginEmailCtrl.value = textCtrl.value,
              );
              return TextField(
                controller: textCtrl,
                focusNode: focus,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration(
                  label: 'Correo',
                  hint: 'usuario@dominio.cl',
                  icon: Icons.alternate_email_rounded,
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _loginPassCtrl,
            obscureText: _loginObscure,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration(
              label: 'Contraseña',
              icon: Icons.key_outlined,
              suffixIcon: IconButton(
                onPressed: () => setState(() => _loginObscure = !_loginObscure),
                icon: Icon(
                  _loginObscure ? Icons.visibility : Icons.visibility_off,
                  color: const Color(0xFFC9A27D),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _primaryButton(
            label: 'Iniciar sesion',
            icon: Icons.login_rounded,
            onPressed: _loading ? null : _login,
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _forgot,
            icon: const Icon(Icons.mail_outline_rounded, size: 18),
            label: const Text('Recuperar contraseña'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _registerTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Eyebrow(
            text: 'Registro',
            icon: Icons.person_add_alt_1_outlined,
          ),
          const SizedBox(height: 10),
          const Text(
            'Crea una cuenta para guardar mazos, sumarte a comunidades, y participar en torneos.',
            style: TextStyle(color: Colors.white70, height: 1.35),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _regUserCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration(
              label: 'Nombre de usuario',
              icon: Icons.badge_outlined,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _regEmailCtrl,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration(
              label: 'Correo',
              icon: Icons.mail_outline_rounded,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _regPassCtrl,
            obscureText: _regObscure,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration(
              label: 'Contraseña',
              icon: Icons.lock_outline_rounded,
              suffixIcon: IconButton(
                onPressed: () => setState(() => _regObscure = !_regObscure),
                icon: Icon(
                  _regObscure ? Icons.visibility : Icons.visibility_off,
                  color: const Color(0xFFD8C2B0),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _regPass2Ctrl,
            obscureText: _regObscure2,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration(
              label: 'Repite la contraseña',
              icon: Icons.verified_user_outlined,
              suffixIcon: IconButton(
                onPressed: () => setState(() => _regObscure2 = !_regObscure2),
                icon: Icon(
                  _regObscure2 ? Icons.visibility : Icons.visibility_off,
                  color: const Color(0xFFD8C2B0),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _primaryButton(
            label: 'Crear cuenta',
            icon: Icons.person_add_alt_1_rounded,
            onPressed: _loading ? null : _register,
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.05),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(.08)),
            ),
            child: const Text(
              'No enviamos verificacion por correo. Luego podras cambiar tu nombre visible desde el perfil.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    String? hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: Colors.white.withOpacity(.12)),
    );
    return InputDecoration(
      filled: true,
      fillColor: Colors.white.withOpacity(.07),
      hintText: hint,
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xFFC9A27D)),
      suffixIcon: suffixIcon,
      labelStyle: const TextStyle(color: Colors.white70),
      hintStyle: const TextStyle(color: Colors.white38),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: Color(0xFF9D6B4A), width: 1.4),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7B5237).withOpacity(.28),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF7B5237),
            foregroundColor: const Color(0xFFF3E8D8),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          onPressed: onPressed,
          icon:
              _loading
                  ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : Icon(icon),
          label: Text(
            _loading ? 'Procesando...' : label,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ),
    );
  }

  Widget _orb(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, Colors.transparent]),
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  final String text;
  final IconData icon;

  const _Eyebrow({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFC9A27D), size: 16),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            color: Color(0xFFC9A27D),
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: .5,
          ),
        ),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _TabButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          gradient:
              selected
                  ? const LinearGradient(
                    colors: [Color(0xFF8A5A3B), Color(0xFF5E3A27)],
                  )
                  : null,
          color: selected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? Colors.white24 : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color:
                  selected ? const Color(0xFFF3E8D8) : const Color(0xFFD8C2B0),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color:
                      selected
                          ? const Color(0xFFF3E8D8)
                          : const Color(0xFFD8C2B0),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RunePainter extends CustomPainter {
  final double progress;

  const _RunePainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint =
        Paint()
          ..color = Colors.white.withOpacity(.035)
          ..strokeWidth = 1;
    const gap = 42.0;

    for (double x = 0; x <= size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    for (double y = 0; y <= size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    final runePaint =
        Paint()
          ..color = const Color(0xFF8E694B).withOpacity(.07 + (progress * .04))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;

    final center = Offset(size.width * .78, size.height * .24);
    final radius = 90 + (progress * 12);
    canvas.drawCircle(center, radius, runePaint);
    canvas.drawCircle(center, radius * .62, runePaint);

    for (int i = 0; i < 7; i++) {
      final angle = ((math.pi * 2) / 7) * i + (progress * .55);
      final point = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      canvas.drawLine(center, point, runePaint);
      canvas.drawCircle(point, 4, runePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RunePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
