// lib/screens/new_card_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/card_myl.dart';
import '../utils/app_constants.dart';
import '../widgets/drive_image_picker.dart';
import '../services/drive_service.dart';
import '../services/card_ai_job_service.dart';

class NewCardScreen extends StatefulWidget {
  final CardMyL? initial; // null => crea, no-null => edita
  final String? initialImageUrl; // <-- nueva
  const NewCardScreen({super.key, this.initial, this.initialImageUrl});

  @override
  State<NewCardScreen> createState() => _NewCardScreenState();
}

class _NewCardScreenState extends State<NewCardScreen> {
  static const List<String> kEdiciones = <String>[
    'Espada Sagrada',
    'Helénica',
    'Hijos de Daana',
    'Dominios de Ra',
  ];

  static const Map<String, List<String>> kRazasPorEdicion = {
    'Espada Sagrada': ['Caballero', 'Dragón', 'Faerie'],
    'Helénica': ['Héroe', 'Titán', 'Olímpico'],
    'Hijos de Daana': ['Defensor', 'Desafiante', 'Sombra'],
    'Dominios de Ra': ['Eterno', 'Sacerdote', 'Faraón'],
  };

  static const List<String> _tipos = <String>[
    'Aliado',
    'Talismán',
    'Tótem',
    'Arma',
    'Oro',
  ];

  // Estado del formulario
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _costeCtrl = TextEditingController();
  final _fuerzaCtrl = TextEditingController();

  String? _edicion;
  String? _tipo;
  String? _raza; // solo si Aliado

  bool _unica = false;
  bool _soloLibre = false;
  final Set<String> _caracteristicas = <String>{};

  bool _saving = false;

  // ---- imagen (Drive) ----
  String? _imageUrl; // raw URL guardada en Firestore
  String?
  _imageDisplayUrl; // URL lista para mostrar en web (proxy si corresponde)
  bool _imageUploading = false;

  // custom features traídas desde Firestore
  final List<String> _customFeatures = [];
  bool _loadingCustomFeatures = false;
  static const String _ownerEmail = AppConstants.ownerEmail;

  // guarda tags iniciales convertidos en Set<CardTag>

  String _currentUserEmail() => FirebaseAuth.instance.currentUser?.email ?? '';

  // Debounce y sugerencias para autocomplete
  Timer? _nameDebounce;
  List<String> _nameSuggestions = [];
  bool _loadingNameSuggestions = false;

  // comprobar existencia de cardId (duplicado)
  bool _nameExists = false;
  bool _checkingNameExists = false;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (widget.initialImageUrl != null && widget.initialImageUrl!.isNotEmpty) {
      _imageUrl = widget.initialImageUrl;
      _imageDisplayUrl = DriveService.webSafeUrl(widget.initialImageUrl!);
    }
    if (init != null) {
      // campos simples
      _nombreCtrl.text = init.nombre;
      _edicion = init.edicion.isNotEmpty ? init.edicion : null;
      _tipo = init.tipo.isNotEmpty ? init.tipo : null;
      _raza = init.raza;
      _costeCtrl.text = init.coste?.toString() ?? '';
      _fuerzaCtrl.text = init.fuerza?.toString() ?? '';
      // texto largo: por ahora inicializamos vacío (tu modelo no expone 'texto' ni 'descripcion')
      _unica = init.unica;
      _soloLibre = init.soloLibre;

      // Intentamos obtener las características directamente desde el campo esperado
      List<String> raws = [];
      try {
        final maybe = init.caracteristicasRaw;
        raws =
            List<String>.from(
              (maybe as Iterable).map((e) => e?.toString().trim() ?? ''),
            ).where((s) => s.isNotEmpty).toList();
      } catch (_) {
        raws = [];
      }

      // rellenamos el set usado por los chips
      _caracteristicas
        ..clear()
        ..addAll(raws);

      // carga imagen oficial desde Firestore si existe (respaldo seguro)
      if (init.id.isNotEmpty) {
        _loadOfficialImageFromFirestore(init.id);
      }
    }

    // carga las características personalizadas (async, no bloqueante)
    _loadCustomFeatures();
  }

  Future<void> _loadOfficialImageFromFirestore(String cardId) async {
    try {
      final doc =
          await FirebaseFirestore.instance
              .collection('cards')
              .doc(cardId)
              .get();
      final data = doc.data();
      if (data != null) {
        final maybe = data['officialImageUrl'];
        if (maybe != null && maybe is String && maybe.isNotEmpty) {
          if (!mounted) return;
          setState(() {
            _imageUrl = maybe;
            _imageDisplayUrl = DriveService.webSafeUrl(maybe);
          });
        }
      }
    } catch (_) {
      // silencioso
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _costeCtrl.dispose();
    _fuerzaCtrl.dispose();
    _nameDebounce?.cancel();
    super.dispose();
  }

  // Helpers: tags <-> CardTag
  Set<CardTag> _mapCaracteristicasATags(Iterable<String> raw) {
    final out = <CardTag>{};
    for (final s in raw) {
      final t = CardTagX.parse(s);
      if (t != null) out.add(t);
    }
    return out;
  }

  Future<void> _pickFromDrive() async {
    final result = await showDriveImagePicker(
      context,
      rootFolderId: DriveService.rootFolderId,
    );
    if (result == null || !mounted) return;
    setState(() {
      _imageUrl = result.viewUrl;
      _imageDisplayUrl = DriveService.webSafeUrl(result.viewUrl);
    });
  }

  // ==========================
  // Nuevo: obtener role del usuario desde Firestore
  // ==========================
  Future<String> _fetchCurrentUserRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return 'basico';
      final doc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
      final r = doc.data()?['role'];
      if (r == null) return 'basico';
      return r.toString();
    } catch (_) {
      return 'basico';
    }
  }

  // ==========================
  // Guardado (con creación de variante oficial si hay imagen y se quiere)
  // ==========================
  Future<void> _save() async {
    // Validación formulario
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final nombre = _nombreCtrl.text.trim();
      final edicion = (_edicion ?? '').trim();
      final tipo = (_tipo ?? '').trim();
      final raza = (tipo == 'Aliado') ? _raza : null;

      int? coste = _tipo == 'Oro' ? null : int.tryParse(_costeCtrl.text.trim());
      int? fuerza =
          (tipo == 'Aliado') ? int.tryParse(_fuerzaCtrl.text.trim()) : null;

      final caracteristicas = _caracteristicas.toList()..sort();

      final tagsFromRaw = _mapCaracteristicasATags(caracteristicas);
      final tags = <CardTag>{}..addAll(tagsFromRaw);

      const rareza = '';
      const descripcion = '';

      final String cardId =
          widget.initial?.id ??
          (edicion.isNotEmpty
              ? '${_normalize(edicion)}_${_normalize(nombre)}'
              : 'libre_${_normalize(nombre)}');

      final card = CardMyL(
        id: cardId,
        nombre: nombre,
        tipo: tipo,
        coste: coste,
        fuerza: fuerza,
        rareza: rareza,
        edicion: edicion,
        habilidad: descripcion,
        raza: raza,
        unica: _unica,
        soloLibre: _soloLibre,
        tags: tags,
        caracteristicasRaw: caracteristicas,
      );

      // Check user and role to decide publish vs propose
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Debes iniciar sesión');

      final role = await _fetchCurrentUserRole();
      final isOwner = (user.email ?? '').toLowerCase() == _ownerEmail;
      final isAdmin = role == 'administrador';

      // Payload común para submissions (audit trail)
      final submissionPayload = <String, dynamic>{
        'title': nombre,
        'description': '',
        'cardData': {
          'tipo': tipo,
          'raza': raza ?? '',
          'edicion': edicion,
          'coste': coste,
          'fuerza': fuerza,
          'rareza': rareza,
          'habilidad': descripcion,
          'unica': _unica,
          'caracteristicas': caracteristicas,
        },
        'imageUrl': _imageUrl,
        'submittedBy': user.uid,
        'submittedByEmail': user.email,
      };

      final cardRef = FirebaseFirestore.instance
          .collection('cards')
          .doc(cardId);

      if (isOwner || isAdmin) {
        // Crear nuevo documento de forma atómica (no duplicar)
        if (widget.initial == null) {
          try {
            await FirebaseFirestore.instance.runTransaction((tx) async {
              final snap = await tx.get(cardRef);
              if (snap.exists) throw Exception('exists');
              tx.set(cardRef, card.toMap());
            });
          } catch (err) {
            if (err is Exception && err.toString().contains('exists')) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Ya existe una carta con ese ID/nombre. Abre o edita la existente.',
                  ),
                ),
              );
              setState(() => _saving = false);
              return;
            }
            rethrow;
          }
        } else {
          // edición: merge para no pisar campos como variantes
          await cardRef.set(card.toMap(), SetOptions(merge: true));
        }

        // Manejo de variantes / imagen oficial
        if (_imageUrl != null && _imageUrl!.isNotEmpty) {
          final variantsCol = cardRef.collection('variants');
          final cardSnap = await cardRef.get();
          final existingOfficialId =
              (cardSnap.data()?['officialVariantId'] as String?)?.trim();

          if (existingOfficialId != null && existingOfficialId.isNotEmpty) {
            final officialDocRef = variantsCol.doc(existingOfficialId);
            await officialDocRef.set({
              'imageFrontUrl': _imageUrl,
              'official': true,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));

            final snap = await variantsCol.get();
            final batch = FirebaseFirestore.instance.batch();
            for (final d in snap.docs) {
              if (d.id != existingOfficialId) {
                batch.set(d.reference, {
                  'official': false,
                }, SetOptions(merge: true));
              }
            }
            await batch.commit();
          } else {
            final snap = await variantsCol.get();
            final newRef = variantsCol.doc();
            final payload = <String, dynamic>{
              'name': 'Oficial',
              'imageFrontUrl': _imageUrl,
              'official': true,
              'createdAt': FieldValue.serverTimestamp(),
            };

            final batch = FirebaseFirestore.instance.batch();
            for (final d in snap.docs) {
              batch.set(d.reference, {
                'official': false,
              }, SetOptions(merge: true));
            }
            batch.set(newRef, payload);
            await batch.commit();

            await cardRef.set({
              'officialVariantId': newRef.id,
            }, SetOptions(merge: true));
          }

          await cardRef.set({
            'officialImageUrl': _imageUrl,
            'officialUpdatedAt': FieldValue.serverTimestamp(),
            'nombre_lower': card.nombre.toLowerCase(),
            'status': FieldValue.delete(),
          }, SetOptions(merge: true));
          // La imagen oficial es suficiente para arrancar la transcripción;
          // no se pregunta ni se bloquea el guardado de la carta.
          if (isOwner) {
            unawaited(CardAiJobService.encolarLecturaAutomatica(cardId));
          }
        } else {
          // ensure nombre_lower exists and clear stub flag if editing
          await cardRef.set({
            'nombre_lower': card.nombre.toLowerCase(),
            'status': FieldValue.delete(),
          }, SetOptions(merge: true));
        }

        // Guardar registro en 'card_submissions' con status approved (audit)
        await FirebaseFirestore.instance.collection('card_submissions').add({
          ...submissionPayload,
          'status': 'approved',
          'createdAt': FieldValue.serverTimestamp(),
          'submittedAt': FieldValue.serverTimestamp(),
          'submitterSeen': false,
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Carta publicada correctamente.')),
        );
        Navigator.of(context).pop(true);
      } else {
        // Usuario normal: crear propuesta en 'card_submissions'
        await FirebaseFirestore.instance.collection('card_submissions').add({
          ...submissionPayload,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'submitterSeen': false,
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Propuesta enviada. Espera aprobación.'),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al guardar: $msg')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ==========================
  // Custom features (Firestore)
  // ==========================
  Future<void> _loadCustomFeatures() async {
    try {
      setState(() => _loadingCustomFeatures = true);
      final snap =
          await FirebaseFirestore.instance
              .collection('card_custom_features')
              .orderBy('name')
              .get();
      final list = <String>[];
      for (final d in snap.docs) {
        // Las unificadas en una genérica ya no se ofrecen.
        if (d.data()['unificadaEn'] != null) continue;
        final n = d.data()['name'];
        if (n != null && n is String && n.trim().isNotEmpty) list.add(n.trim());
      }

      list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _customFeatures
          ..clear()
          ..addAll(list);
      });
    } catch (e) {
      // fallback silencioso
    } finally {
      if (mounted) setState(() => _loadingCustomFeatures = false);
    }
  }

  void _onNameChanged(String value) {
    // debounce
    _nameDebounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _nameSuggestions = [];
        _nameExists = false;
      });
      return;
    }
    _nameDebounce = Timer(const Duration(milliseconds: 350), () {
      _fetchNameSuggestions(value.trim().toLowerCase());
      // también comprobar existencia exacta del cardId (si ya tienes edición)
      final ed = _edicion ?? '';
      final candidateId = '${_normalize(ed)}_${_normalize(value.trim())}';
      _checkNameExists(candidateId);
    });
  }

  Future<void> _fetchNameSuggestions(String prefix) async {
    try {
      setState(() {
        _loadingNameSuggestions = true;
      });
      final q = FirebaseFirestore.instance
          .collection('cards')
          .where('nombre_lower', isGreaterThanOrEqualTo: prefix)
          .where('nombre_lower', isLessThanOrEqualTo: '$prefix\uf8ff')
          .limit(12);

      final snap = await q.get();
      final list = <String>[];
      for (final d in snap.docs) {
        final n = (d.data()['nombre'] as String?)?.trim();
        if (n != null && n.isNotEmpty) list.add(n);
      }
      if (!mounted) return;
      setState(() {
        _nameSuggestions = list;
      });
    } catch (e) {
      // silencioso
    } finally {
      if (mounted) setState(() => _loadingNameSuggestions = false);
    }
  }

  Future<void> _checkNameExists(String candidateCardId) async {
    try {
      setState(() => _checkingNameExists = true);
      final doc =
          await FirebaseFirestore.instance
              .collection('cards')
              .doc(candidateCardId)
              .get();
      final exists = doc.exists;
      if (!mounted) return;
      // Si estamos editando la misma carta, no marcar como existente
      final editingSame =
          widget.initial != null && widget.initial!.id == candidateCardId;
      setState(() {
        _nameExists = exists && !editingSame;
      });
    } catch (_) {
      if (mounted) setState(() => _nameExists = false);
    } finally {
      if (mounted) setState(() => _checkingNameExists = false);
    }
  }

  Future<void> _addCustomFeatureDialog() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Agregar característica'),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'Nombre de la característica',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  final value = ctrl.text.trim();
                  if (value.isEmpty) return;
                  Navigator.pop(ctx, true);
                },
                child: const Text('Agregar'),
              ),
            ],
          ),
    );

    if (ok != true) return;
    final value = ctrl.text.trim();

    final lower = value.toLowerCase();
    final exists = _customFeatures.any((c) => c.toLowerCase() == lower);
    if (exists) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ya existe esa característica')),
      );
      return;
    }

    try {
      final docRef =
          FirebaseFirestore.instance.collection('card_custom_features').doc();
      await docRef.set({
        'name': value,
        'createdBy': _currentUserEmail(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      setState(() {
        _customFeatures.add(value);
        _customFeatures.sort(
          (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
        );
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Característica agregada')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al agregar: $e')));
    }
  }

  String _saveButtonMessage() {
    if (_saving) return 'Guardando...';
    if (_nameExists) return 'Ya existe una carta con ese nombre';
    return '';
  }

  InputDecoration _darkInputDecoration({
    required String label,
    IconData? icon,
    Widget? suffixIcon,
    String? hintText,
    bool alignLabelWithHint = false,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      alignLabelWithHint: alignLabelWithHint,
      prefixIcon:
          icon == null ? null : Icon(icon, color: const Color(0xFFF1D48B)),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFF12161D),
      labelStyle: const TextStyle(color: Colors.white70),
      hintStyle: const TextStyle(color: Colors.white38),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFF1D48B)),
      ),
    );
  }

  Widget _sectionCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF171B22),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white10),
      ),
      child: child,
    );
  }

  void _toggleFeature(String feature, bool selected) {
    setState(() {
      if (selected) {
        _caracteristicas.add(feature);
      } else {
        _caracteristicas.remove(feature);
      }
    });
  }

  Widget _buildUniqueSwitch() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF12161D),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star, color: Color(0xFFF1D48B), size: 18),
                  SizedBox(width: 8),
                  Text('Unica', style: TextStyle(color: Colors.white)),
                ],
              ),
              Switch.adaptive(
                value: _unica,
                onChanged: (v) => setState(() => _unica = v),
                activeColor: const Color(0xFFF1D48B),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF12161D),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _soloLibre ? const Color(0xFFD8B46A) : Colors.white12,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.swap_horiz_rounded,
                    color: Color(0xFFD8B46A),
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text('Libre', style: TextStyle(color: Colors.white)),
                ],
              ),
              Switch.adaptive(
                value: _soloLibre,
                onChanged: (v) => setState(() => _soloLibre = v),
                activeColor: const Color(0xFFD8B46A),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFeaturesSection() {
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Expanded(
                child: Text(
                  'Caracteristicas',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (_loadingCustomFeatures)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  tooltip: 'Agregar caracteristica nueva',
                  onPressed: _addCustomFeatureDialog,
                  icon: const Icon(
                    Icons.add_circle_outline,
                    color: Color(0xFFF1D48B),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (!_loadingCustomFeatures && _customFeatures.isEmpty)
            const Text(
              'No hay caracteristicas cargadas.',
              style: TextStyle(color: Colors.white60),
            ),
          if (_customFeatures.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  _customFeatures.map((feature) {
                    final selected = _caracteristicas.contains(feature);
                    return FilterChip(
                      label: Text(feature),
                      selected: selected,
                      labelStyle: TextStyle(
                        color:
                            selected ? const Color(0xFF14181F) : Colors.white70,
                      ),
                      selectedColor: const Color(0xFFF1D48B),
                      backgroundColor: const Color(0xFF1A212B),
                      side: const BorderSide(color: Colors.white12),
                      onSelected: (value) => _toggleFeature(feature, value),
                    );
                  }).toList(),
            ),
        ],
      ),
    );
  }

  // UI
  // ==========================
  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initial != null;
    final bool saveEnabled = !_saving && !_nameExists;
    // En modo libre no hay edición, pero sí puede haber raza si el tipo es Aliado
    final razaEnabled = _tipo == 'Aliado' && (_edicion != null || _soloLibre);
    // Si hay edición, mostrar solo sus razas; si es libre, mostrar todas las razas del juego
    final razaList =
        _edicion != null
            ? List<String>.from(kRazasPorEdicion[_edicion] ?? const <String>[])
            : (List<String>.from(
              kRazasPorEdicion.values.expand((r) => r).toSet(),
            )..sort());
    final razaItems =
        razaList
            .map(
              (r) => DropdownMenuItem(
                value: r,
                child: Text(r, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList();

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1016),
      appBar: AppBar(
        backgroundColor: const Color(0xFF14181F),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(isEditing ? 'Editar carta' : 'Nueva carta'),
      ),
      body: SafeArea(
        child: Theme(
          data: Theme.of(context).copyWith(
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF12161D),
              labelStyle: const TextStyle(color: Colors.white70),
              hintStyle: const TextStyle(color: Colors.white38),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFF1D48B)),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Colors.white12),
              ),
            ),
          ),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                isMobile ? 12 : 16,
                12,
                isMobile ? 12 : 16,
                32,
              ),
              children: [
                _sectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (isMobile) ...[
                        _buildNombreField(),
                        const SizedBox(height: 12),
                        _buildEdicionField(),
                      ] else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 2, child: _buildNombreField()),
                            const SizedBox(width: 12),
                            Expanded(child: _buildEdicionField()),
                          ],
                        ),
                      const SizedBox(height: 12),
                      if (isMobile) ...[
                        _buildTipoField(),
                        if (_tipo == 'Aliado') ...[
                          const SizedBox(height: 12),
                          _buildRazaField(razaItems, razaEnabled),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            if (_tipo != 'Oro') ...[
                              Expanded(child: _buildCosteField()),
                              const SizedBox(width: 12),
                            ],
                            Expanded(child: _buildUniqueSwitch()),
                          ],
                        ),
                      ] else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildTipoField()),
                            if (_tipo == 'Aliado') ...[
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildRazaField(razaItems, razaEnabled),
                              ),
                            ],
                            if (_tipo != 'Oro') ...[
                              const SizedBox(width: 12),
                              Expanded(child: _buildCosteField()),
                            ],
                            const SizedBox(width: 12),
                            Expanded(child: _buildUniqueSwitch()),
                          ],
                        ),
                      if (_tipo == 'Aliado') ...[
                        const SizedBox(height: 12),
                        if (isMobile)
                          _buildFuerzaField()
                        else
                          Row(
                            children: [
                              Expanded(child: _buildFuerzaField()),
                              const SizedBox(width: 12),
                              const Expanded(child: SizedBox.shrink()),
                            ],
                          ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildFeaturesSection(),
                const SizedBox(height: 16),
                // Botones de acción
                if (isMobile) ...[
                  SizedBox(
                    height: 54,
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: saveEnabled ? _save : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFF1D48B),
                        foregroundColor: const Color(0xFF14181F),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon:
                          _saving
                              ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.save),
                      label: Text(
                        _saving
                            ? 'Guardando...'
                            : (isEditing
                                ? 'Actualizar Carta'
                                : 'Publicar Carta'),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: OutlinedButton.icon(
                            onPressed: _imageUploading ? null : _pickFromDrive,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0x664FC3F7)),
                              foregroundColor: const Color(0xFF4FC3F7),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            icon: const Icon(Icons.drive_folder_upload_rounded),
                            label: Text(
                              _imageUrl == null
                                  ? 'Imagen desde Drive'
                                  : 'Cambiar imagen',
                            ),
                          ),
                        ),
                      ),
                      if (_imageUrl != null) ...[
                        const SizedBox(width: 8),
                        _buildImagePreviewButton(),
                      ],
                    ],
                  ),
                  if (_saveButtonMessage().isNotEmpty && !saveEnabled)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _saveButtonMessage(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ] else
                  Row(
                    children: [
                      Expanded(
                        child: Tooltip(
                          message:
                              !_saveButtonMessage().isEmpty
                                  ? _saveButtonMessage()
                                  : 'Guardar',
                          child: FilledButton.icon(
                            onPressed: saveEnabled ? _save : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFF1D48B),
                              foregroundColor: const Color(0xFF14181F),
                            ),
                            icon: const Icon(Icons.save),
                            label:
                                _saving
                                    ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                    : const Text('Guardar'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 44,
                        child: OutlinedButton.icon(
                          onPressed: _imageUploading ? null : _pickFromDrive,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0x664FC3F7)),
                            foregroundColor: const Color(0xFF4FC3F7),
                          ),
                          icon: const Icon(
                            Icons.drive_folder_upload_rounded,
                            size: 18,
                          ),
                          label: Text(
                            _imageUrl == null
                                ? 'Imagen desde Drive'
                                : 'Cambiar imagen',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_imageUrl != null)
                        _buildImagePreviewButton()
                      else
                        const SizedBox(
                          width: 44,
                          height: 44,
                          child: IconButton(
                            onPressed: null,
                            icon: Icon(
                              Icons.visibility_off,
                              color: Colors.white24,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Refactored helper fields for cleaner build method
  Widget _buildNombreField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _nombreCtrl,
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(color: Colors.white),
          decoration: _darkInputDecoration(
            label: 'Nombre de la carta',
            icon: Icons.style,
            suffixIcon:
                _checkingNameExists
                    ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                    : (_nameExists
                        ? const Icon(Icons.error, color: Colors.red)
                        : null),
          ),
          onChanged: _onNameChanged,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Ingresa el nombre';
            if (v.trim().length < 2) return 'Nombre demasiado corto';
            if (_nameExists) return 'Ya existe una carta con este nombre';
            return null;
          },
        ),
        if (_loadingNameSuggestions || _nameSuggestions.isNotEmpty)
          const SizedBox(height: 6),
        if (_loadingNameSuggestions)
          const SizedBox(
            height: 2,
            child: LinearProgressIndicator(minHeight: 2),
          )
        else if (_nameSuggestions.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 160),
            child: Card(
              color: const Color(0xFF171B22),
              elevation: 2,
              margin: EdgeInsets.zero,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _nameSuggestions.length,
                itemBuilder: (ctx, i) {
                  final s = _nameSuggestions[i];
                  return ListTile(
                    dense: true,
                    title: Text(s, style: const TextStyle(color: Colors.white)),
                    onTap: () {
                      setState(() {
                        _nombreCtrl.text = s;
                        _nameSuggestions = [];
                      });
                      final ed = _edicion ?? '';
                      final candidateId = '${_normalize(ed)}_${_normalize(s)}';
                      _checkNameExists(candidateId);
                    },
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEdicionField() {
    return DropdownButtonFormField<String>(
      value: _edicion,
      isExpanded: true,
      dropdownColor: const Color(0xFF171B22),
      style: const TextStyle(color: Colors.white),
      items: [
        if (_soloLibre)
          const DropdownMenuItem<String>(
            value: null,
            child: Text('Cualquiera (Solo Libre)'),
          ),
        ...kEdiciones.map(
          (e) => DropdownMenuItem(
            value: e,
            child: Text(e, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged:
          (v) => setState(() {
            _edicion = v;
            if (_raza != null &&
                !(kRazasPorEdicion[_edicion] ?? []).contains(_raza)) {
              _raza = null;
            }
          }),
      decoration: _darkInputDecoration(
        label: 'Edicion',
        icon: Icons.collections_bookmark,
      ),
      validator:
          (v) =>
              (!_soloLibre && (v == null || v.isEmpty))
                  ? 'Selecciona edicion'
                  : null,
    );
  }

  Widget _buildTipoField() {
    return DropdownButtonFormField<String>(
      value: _tipo,
      isExpanded: true,
      dropdownColor: const Color(0xFF171B22),
      style: const TextStyle(color: Colors.white),
      items:
          _tipos
              .map(
                (t) => DropdownMenuItem(
                  value: t,
                  child: Text(t, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
      onChanged:
          (v) => setState(() {
            _tipo = v;
            if (_tipo != 'Aliado') {
              _raza = null;
              _fuerzaCtrl.clear();
            }
          }),
      decoration: _darkInputDecoration(
        label: 'Tipo de carta',
        icon: Icons.category,
      ),
      validator: (v) => v == null || v.isEmpty ? 'Selecciona tipo' : null,
    );
  }

  Widget _buildRazaField(List<DropdownMenuItem<String>> items, bool enabled) {
    return DropdownButtonFormField<String>(
      value: _raza,
      isExpanded: true,
      dropdownColor: const Color(0xFF171B22),
      style: const TextStyle(color: Colors.white),
      items: items,
      onChanged: enabled ? (v) => setState(() => _raza = v) : null,
      decoration: _darkInputDecoration(
        label: 'Raza',
        icon: Icons.groups,
        hintText: enabled ? 'Selecciona raza' : 'Solo para Aliado',
      ),
      validator: (v) {
        if (_tipo != 'Aliado') return null;
        if (v == null || v.isEmpty) return 'Selecciona raza';
        return null;
      },
    );
  }

  Widget _buildCosteField() {
    return TextFormField(
      controller: _costeCtrl,
      keyboardType: TextInputType.number,
      enabled: _tipo != 'Oro',
      style: const TextStyle(color: Colors.white),
      decoration: _darkInputDecoration(
        label: 'Coste',
        icon: Icons.local_fire_department,
        hintText: _tipo == 'Oro' ? 'No aplica' : null,
      ),
      validator: (v) {
        if (_tipo == 'Oro') return null;
        if (v == null || v.trim().isEmpty) return null;
        if (int.tryParse(v.trim()) == null) return 'Debe ser un numero';
        return null;
      },
    );
  }

  Widget _buildFuerzaField() {
    return TextFormField(
      controller: _fuerzaCtrl,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Colors.white),
      decoration: _darkInputDecoration(
        label: 'Fuerza',
        icon: Icons.fitness_center,
      ),
      validator: (v) {
        if (_tipo != 'Aliado') return null;
        if (v == null || v.trim().isEmpty) return null;
        if (int.tryParse(v.trim()) == null) return 'Debe ser un numero';
        return null;
      },
    );
  }

  Widget _buildImagePreviewButton() {
    return Tooltip(
      message: 'Ver imagen',
      child: InkWell(
        onTap:
            () => showDialog(
              context: context,
              builder:
                  (ctx) => Dialog(
                    insetPadding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            widget.initial == null
                                ? 'Imagen'
                                : widget.initial!.nombre,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Flexible(
                          child: InteractiveViewer(
                            child: Image.network(
                              _imageDisplayUrl ?? _imageUrl!,
                              fit: BoxFit.contain,
                              errorBuilder:
                                  (_, __, ___) => const Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Icon(Icons.broken_image, size: 56),
                                  ),
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Cerrar'),
                        ),
                      ],
                    ),
                  ),
            ),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.hardEdge,
          child:
              (_imageDisplayUrl ?? _imageUrl!).contains('res.cloudinary.com')
                  ? Image.network(
                    _imageUrl!.replaceFirst(
                      '/upload/',
                      '/upload/f_auto,q_auto,w_100,h_100,c_fill,g_auto/',
                    ),
                    fit: BoxFit.cover,
                    errorBuilder:
                        (_, __, ___) => const Icon(Icons.broken_image),
                  )
                  : Image.network(
                    _imageDisplayUrl ?? _imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder:
                        (_, __, ___) => const Icon(Icons.broken_image),
                  ),
        ),
      ),
    );
  }

  // small helper
  String _normalize(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[áàä]'), 'a')
        .replaceAll(RegExp(r'[éèë]'), 'e')
        .replaceAll(RegExp(r'[íìï]'), 'i')
        .replaceAll(RegExp(r'[óòö]'), 'o')
        .replaceAll(RegExp(r'[úùü]'), 'u')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }
}
