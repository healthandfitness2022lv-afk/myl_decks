import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _loginEmailCtrl = TextEditingController();
  final _loginPassCtrl  = TextEditingController();

  final _regUserCtrl = TextEditingController();   // nombre de usuario visible
  final _regEmailCtrl = TextEditingController();
  final _regPassCtrl  = TextEditingController();
  final _regPass2Ctrl = TextEditingController();

  bool _loginObscure = true;
  bool _regObscure   = true;
  bool _regObscure2  = true;
  bool _loading = false;

  List<String> _recentEmails = [];

  // Fondo compartido con Home
  String _bg = 'assets/wallpaper/1.jpg';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadBg();
    _loadRecentEmails();
  }

  @override
  void dispose() {
    _tab.dispose();
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
    setState(() => _bg = sp.getString('background') ?? 'assets/wallpaper/1.jpg');
  }

  Future<void> _loadRecentEmails() async {
    final sp = await SharedPreferences.getInstance();
    setState(() => _recentEmails = sp.getStringList('recent_emails') ?? []);
  }

  Future<void> _saveRecentEmail(String email) async {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList('recent_emails') ?? [];
    if (!list.contains(email)) {
      list.insert(0, email);
      if (list.length > 5) list.removeLast();
      await sp.setStringList('recent_emails', list);
      setState(() => _recentEmails = list);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // =========================
  // LOGIN
  // =========================
  Future<void> _login() async {
  final email = _loginEmailCtrl.text.trim();
  final pass  = _loginPassCtrl.text;

  if (email.isEmpty || pass.isEmpty) {
    _snack('Ingresa correo y contraseña.');
    return;
  }

  try {
    setState(() => _loading = true);

    // 1) Sign in
    final userCred = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: pass,
    );

    // 2) Guardar email reciente
    await _saveRecentEmail(email);

    // 3) Cargar o crear perfil en Firestore con role y flags
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userDocRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final userSnap = await userDocRef.get();

    Map<String, dynamic> data;
    if (!userSnap.exists) {
      // Si no existe, creamos un perfil mínimo y seguro (role: basico).
      final defaultProfile = {
        'username': userCred.user?.displayName ?? '',
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
        'active': true,
        'role': 'basico',
        'maxDecks': 3,
        'canUploadImages': false,
      };
      await userDocRef.set(defaultProfile, SetOptions(merge: true));
      data = defaultProfile.map((k, v) => MapEntry(k, v)); // datos locales temporales
    } else {
      data = userSnap.data() ?? {};
    }

    // 4) Extraer campos con tolerancia a tipos (Timestamp / int / null)
    String role = (data['role'] as String?) ?? 'basico';
    int maxDecks = data['maxDecks'] != null
        ? ((data['maxDecks'] as num).toInt())
        : 3;
    bool canUploadImages = data['canUploadImages'] == true;
    String? displayName = (data['username'] as String?) ?? FirebaseAuth.instance.currentUser?.displayName;
    String? photoUrl = (data['photoUrl'] as String?) ?? FirebaseAuth.instance.currentUser?.photoURL;

    // 5) Guardar en SharedPreferences (o actualiza tu Provider aquí)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', role);
    await prefs.setInt('user_maxDecks', maxDecks);
    await prefs.setBool('user_canUploadImages', canUploadImages);
    if (displayName != null) await prefs.setString('user_displayName', displayName);
    if (photoUrl != null) await prefs.setString('user_photoUrl', photoUrl);

    // Si usas Provider / CurrentUser, actualizalo aquí en vez de SharedPreferences:
    // context.read<CurrentUser>().update(uid_: uid, email_: email, role_: role);

    // Opcional: si tu sistema usa custom claims y esperás cambios recientes,
    // fuerza el refresh del token (comentado porque no siempre es necesario):
    // await FirebaseAuth.instance.currentUser?.getIdToken(true);

    // Ya está: authStateChanges() debería redirigir a Home según tengas implementado.
  } on FirebaseAuthException catch (e) {
    String msg = 'Error al iniciar sesión.';
    switch (e.code) {
      case 'user-not-found':
        msg = 'Usuario no encontrado.';
        break;
      case 'wrong-password':
        msg = 'Contraseña incorrecta.';
        break;
      case 'invalid-email':
        msg = 'Correo inválido.';
        break;
      case 'user-disabled':
        msg = 'Usuario deshabilitado.';
        break;
    }
    _snack(msg);
  } on FirebaseException catch (e) {
    // Errores de Firestore u otros servicios Firebase
    _snack('Error al cargar perfil: ${e.message ?? e.code}');
  } catch (e) {
    _snack('Error: $e');
  } finally {
    if (mounted) setState(() => _loading = false);
  }
}


  // =========================
  // REGISTRO (sin verificación por correo)
  // =========================
  Future<void> _register() async {
    final username = _regUserCtrl.text.trim();
    final email    = _regEmailCtrl.text.trim();
    final pass     = _regPassCtrl.text;
    final pass2    = _regPass2Ctrl.text;

    if (username.isEmpty) { _snack('Escribe un nombre de usuario.'); return; }
    if (email.isEmpty)    { _snack('Escribe tu correo.'); return; }
    if (pass.length < 6)  { _snack('La contraseña debe tener al menos 6 caracteres.'); return; }
    if (pass != pass2)    { _snack('Las contraseñas no coinciden.'); return; }

    try {
      setState(() => _loading = true);

      // Crear en Auth
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: pass,
      );

      // Display name
      await cred.user?.updateDisplayName(username);

      // Perfil en Firestore
      // PERFIL EN FIRESTORE (dentro de _register)
final uid = cred.user!.uid;
await FirebaseFirestore.instance.collection('users').doc(uid).set({
  'username': username,
  'email': email,
  'createdAt': FieldValue.serverTimestamp(),
  'active': true,
  'role': 'basico',        // <- rol por defecto
  'maxDecks': 3,           // opcional: límite para basico
  'canUploadImages': false,// opcional: permiso para subir imágenes
}, SetOptions(merge: true));


      await _saveRecentEmail(email);
      _snack('Cuenta creada. ¡Bienvenido, $username!');
      // authStateChanges() te llevará a Home automáticamente
    } on FirebaseAuthException catch (e) {
      String msg = 'No se pudo crear la cuenta.';
      switch (e.code) {
        case 'email-already-in-use': msg = 'Ese correo ya está en uso.'; break;
        case 'invalid-email':        msg = 'Correo inválido.'; break;
        case 'weak-password':        msg = 'Contraseña débil.'; break;
        case 'operation-not-allowed':msg = 'Operación no permitida en Auth.'; break;
      }
      _snack(msg);
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgot() async {
    final email = _loginEmailCtrl.text.trim();
    if (email.isEmpty) {
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

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Fondo a pantalla completa (mismo que Home)
          DecoratedBox(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage(_bg),
                fit: BoxFit.cover,
              ),
            ),
          ),
          // Capa oscura para contraste
          Container(color: Colors.black.withOpacity(0.45)),

          // Contenido centrado con blur (frosted glass)
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withOpacity(0.20)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Título
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.style, color: Colors.white, size: 26),
                                const SizedBox(width: 8),
                                Text(
                                  'Bienvenido',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            // Tabs
                            TabBar(
                              controller: _tab,
                              labelColor: Colors.white,
                              unselectedLabelColor: Colors.white70,
                              indicatorColor: Colors.amberAccent,
                              tabs: const [
                                Tab(icon: Icon(Icons.login), text: 'Entrar'),
                                Tab(icon: Icon(Icons.person_add), text: 'Crear cuenta'),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Contenido con scroll por si el teclado tapa algo
                            SizedBox(
                              height: 420,
                              child: TabBarView(
                                controller: _tab,
                                children: [
                                  _buildLoginTab(theme),
                                  _buildRegisterTab(theme),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --------- LOGIN TAB ---------
  Widget _buildLoginTab(ThemeData theme) {
    final inputFill = Colors.white.withOpacity(0.14);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.white.withOpacity(0.35)),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          // Autocomplete con correos recientes
          Autocomplete<String>(
            optionsBuilder: (TextEditingValue v) {
              final q = v.text.toLowerCase();
              if (q.isEmpty) return const Iterable<String>.empty();
              return _recentEmails.where((e) => e.toLowerCase().contains(q));
            },
            onSelected: (val) => _loginEmailCtrl.text = val,
            fieldViewBuilder: (_, textCtrl, focus, onFieldSubmitted) {
              textCtrl.addListener(() => _loginEmailCtrl.value = textCtrl.value);
              return TextField(
                controller: textCtrl,
                focusNode: focus,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: inputFill,
                  labelText: 'Correo',
                  hintText: 'usuario@dominio.cl',
                  labelStyle: const TextStyle(color: Colors.white70),
                  hintStyle: const TextStyle(color: Colors.white60),
                  border: border,
                  enabledBorder: border,
                  focusedBorder: border.copyWith(
                    borderSide: const BorderSide(color: Colors.amberAccent),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _loginPassCtrl,
            obscureText: _loginObscure,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: inputFill,
              labelText: 'Contraseña',
              labelStyle: const TextStyle(color: Colors.white70),
              border: border,
              enabledBorder: border,
              focusedBorder: border.copyWith(
                borderSide: const BorderSide(color: Colors.amberAccent),
              ),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _loginObscure = !_loginObscure),
                icon: Icon(_loginObscure ? Icons.visibility : Icons.visibility_off, color: const Color.fromARGB(179, 41, 5, 5)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.amber.shade600,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _loading ? null : _login,
              child: _loading
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Entrar', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _forgot,
            child: const Text('Olvidé mi contraseña', style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(height: 10),            
        ],
      ),
    );
  }

  // --------- REGISTER TAB ---------
  Widget _buildRegisterTab(ThemeData theme) {
    final inputFill = Colors.white.withOpacity(0.14);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.white.withOpacity(0.35)),
    );

    InputDecoration deco(String label) => InputDecoration(
      filled: true,
      fillColor: inputFill,
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: Colors.amberAccent),
      ),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          TextField(
            controller: _regUserCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: deco('Nombre de usuario'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _regEmailCtrl,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: Colors.white),
            decoration: deco('Correo'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _regPassCtrl,
            obscureText: _regObscure,
            style: const TextStyle(color: Colors.white),
            decoration: deco('Contraseña').copyWith(
              suffixIcon: IconButton(
                onPressed: () => setState(() => _regObscure = !_regObscure),
                icon: Icon(_regObscure ? Icons.visibility : Icons.visibility_off, color: Colors.white70),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _regPass2Ctrl,
            obscureText: _regObscure2,
            style: const TextStyle(color: Colors.white),
            decoration: deco('Repite la contraseña').copyWith(
              suffixIcon: IconButton(
                onPressed: () => setState(() => _regObscure2 = !_regObscure2),
                icon: Icon(_regObscure2 ? Icons.visibility : Icons.visibility_off, color: Colors.white70),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.greenAccent.shade400,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _loading ? null : _register,
              icon: _loading
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.person_add_alt_1),
              label: const Text('Crear cuenta', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'No enviamos verificación por correo. Podrás cambiar tu nombre de usuario en tu perfil.',
            style: TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
