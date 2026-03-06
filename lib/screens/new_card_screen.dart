// lib/screens/new_card_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/cloudinary_service.dart';
import '../models/card_myl.dart';

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
  final _textoCtrl = TextEditingController(); // texto largo (opcional)
  final _rarezaCtrl = TextEditingController();
  final _habilidadCtrl = TextEditingController(); // resumen/skill (opcional)

  String? _edicion;
  String? _tipo;
  String? _raza; // solo si Aliado

  bool _unica = false;
  final Set<String> _caracteristicas = <String>{};

  bool _saving = false;

  // ---- imagen / cloudinary ----
  String? _imageUrl;
  String? _cloudinaryId;
  bool _imageUploading = false;

  // custom features traídas desde Firestore
  final List<String> _customFeatures = [];
  bool _loadingCustomFeatures = false;
  static const String _ownerEmail = 'hecturnicolas@gmail.com';

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
    }
    if (init != null) {
      // campos simples
      _nombreCtrl.text = init.nombre;
      _edicion = init.edicion.isNotEmpty ? init.edicion : null;
      _tipo = init.tipo.isNotEmpty ? init.tipo : null;
      _raza = init.raza;
      _costeCtrl.text = init.coste?.toString() ?? '';
      _fuerzaCtrl.text = init.fuerza?.toString() ?? '';
      _rarezaCtrl.text = init.rareza;
      _habilidadCtrl.text = init.habilidad;
      // texto largo: por ahora inicializamos vacío (tu modelo no expone 'texto' ni 'descripcion')
      _textoCtrl.text = '';

      _unica = init.unica;

      // Intentamos obtener las características directamente desde el campo esperado
      List<String> raws = [];
      try {
        final maybe = init.caracteristicasRaw;
        raws = List<String>.from(
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
      final doc = await FirebaseFirestore.instance.collection('cards').doc(cardId).get();
      final data = doc.data();
      if (data != null) {
        final maybe = data['officialImageUrl'];
        if (maybe != null && maybe is String && maybe.isNotEmpty) {
          if (!mounted) return;
          setState(() => _imageUrl = maybe);
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
    _textoCtrl.dispose();
    _rarezaCtrl.dispose();
    _habilidadCtrl.dispose();
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


  // Imagen: picker + upload
  Future<void> _pickAndUploadImage() async {
    try {
      setState(() => _imageUploading = true);

      Map r;
      if (kIsWeb) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          withData: true,
        );
        if (result == null || result.files.first.bytes == null) {
          setState(() => _imageUploading = false);
          return;
        }
        final f = result.files.first;
        r = await CloudinaryService.uploadFromBytes(f.bytes!, filename: f.name);
      } else {
        final picker = ImagePicker();
        final XFile? x = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 90,
        );
        if (x == null) {
          setState(() => _imageUploading = false);
          return;
        }
        r = await CloudinaryService.uploadFromPath(x.path, filename: x.name);
      }

      final secure = (r['secure_url'] ?? r['url'] ?? r['secureUrl'] ?? r['secureURL'])?.toString();
      final pubId = (r['public_id'] ?? r['publicId'])?.toString();

      if (secure == null || secure.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se recibió URL de Cloudinary')),
        );
        return;
      }

      setState(() {
        _imageUrl = secure;
        _cloudinaryId = pubId;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error subiendo: $e')));
    } finally {
      if (mounted) setState(() => _imageUploading = false);
    }
  }

  // ==========================
  // Nuevo: obtener role del usuario desde Firestore
  // ==========================
  Future<String> _fetchCurrentUserRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return 'basico';
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
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

    // REGLA REQUERIDA: la imagen es obligatoria para propuestas/publicaciones
    if (_imageUrl == null || _imageUrl!.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La imagen es obligatoria.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final nombre = _nombreCtrl.text.trim();
      final edicion = (_edicion ?? '').trim();
      final tipo = (_tipo ?? '').trim();
      final raza = (tipo == 'Aliado') ? _raza : null;

      int? coste = _tipo == 'Oro' ? null : int.tryParse(_costeCtrl.text.trim());
      int? fuerza = (tipo == 'Aliado') ? int.tryParse(_fuerzaCtrl.text.trim()) : null;

      final caracteristicas = _caracteristicas.toList()..sort();

      final tagsFromRaw = _mapCaracteristicasATags(caracteristicas);
      final tags = <CardTag>{}..addAll(tagsFromRaw);

      final rareza = _rarezaCtrl.text.trim();
      final habilidad = _habilidadCtrl.text.trim();

      final String cardId = widget.initial?.id ?? '${_normalize(edicion)}_${_normalize(nombre)}';

      final card = CardMyL(
        id: cardId,
        nombre: nombre,
        tipo: tipo,
        coste: coste,
        fuerza: fuerza,
        rareza: rareza,
        edicion: edicion,
        habilidad: habilidad.isEmpty ? _textoCtrl.text.trim() : habilidad,
        raza: raza,
        unica: _unica,
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
        'description': _textoCtrl.text.trim(),
        'cardData': {
          'tipo': tipo,
          'raza': raza ?? '',
          'edicion': edicion,
          'coste': coste,
          'fuerza': fuerza,
          'rareza': rareza,
          'habilidad': habilidad,
          'unica': _unica,
          'caracteristicas': caracteristicas,
        },
        'imageUrl': _imageUrl,
        'cloudinaryId': _cloudinaryId,
        'submittedBy': user.uid,
        'submittedByEmail': user.email,
      };

      final cardRef = FirebaseFirestore.instance.collection('cards').doc(cardId);

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
                const SnackBar(content: Text('Ya existe una carta con ese ID/nombre. Abre o edita la existente.')),
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
          final existingOfficialId = (cardSnap.data()?['officialVariantId'] as String?)?.trim();

          if (existingOfficialId != null && existingOfficialId.isNotEmpty) {
            final officialDocRef = variantsCol.doc(existingOfficialId);
            await officialDocRef.set({
              'imageFrontUrl': _imageUrl,
              if (_cloudinaryId != null) 'cloudinaryPublicId': _cloudinaryId,
              'official': true,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));

            final snap = await variantsCol.get();
            final batch = FirebaseFirestore.instance.batch();
            for (final d in snap.docs) {
              if (d.id != existingOfficialId) {
                batch.set(d.reference, {'official': false}, SetOptions(merge: true));
              }
            }
            await batch.commit();
          } else {
            final snap = await variantsCol.get();
            final newRef = variantsCol.doc();
            final payload = <String, dynamic>{
              'name': 'Oficial',
              'imageFrontUrl': _imageUrl,
              if (_cloudinaryId != null) 'cloudinaryPublicId': _cloudinaryId,
              'official': true,
              'createdAt': FieldValue.serverTimestamp(),
            };

            final batch = FirebaseFirestore.instance.batch();
            for (final d in snap.docs) {
              batch.set(d.reference, {'official': false}, SetOptions(merge: true));
            }
            batch.set(newRef, payload);
            await batch.commit();

            await cardRef.set({'officialVariantId': newRef.id}, SetOptions(merge: true));
          }

          await cardRef.set({
            'officialImageUrl': _imageUrl,
            'officialUpdatedAt': FieldValue.serverTimestamp(),
            'nombre_lower': card.nombre.toLowerCase(),
          }, SetOptions(merge: true));
        } else {
          // ensure nombre_lower exists
          await cardRef.set({'nombre_lower': card.nombre.toLowerCase()}, SetOptions(merge: true));
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
          const SnackBar(content: Text('Propuesta enviada. Espera aprobación.')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al guardar: $msg')));
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
      final snap = await FirebaseFirestore.instance.collection('card_custom_features').orderBy('name').get();
      final list = <String>[];
      for (final d in snap.docs) {
        final n = d.data()['name'];
        if (n != null && n is String && n.trim().isNotEmpty) list.add(n);
      }

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
      final doc = await FirebaseFirestore.instance.collection('cards').doc(candidateCardId).get();
      final exists = doc.exists;
      if (!mounted) return;
      // Si estamos editando la misma carta, no marcar como existente
      final editingSame = widget.initial != null && widget.initial!.id == candidateCardId;
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
      builder: (ctx) => AlertDialog(
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


    // permiso client-side: solo el owner puede intentar añadir
    final email = _currentUserEmail();
    if (email != _ownerEmail) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No tienes permiso para agregar características'),
        ),
      );
      return;
    }

    try {
      final docRef = FirebaseFirestore.instance.collection('card_custom_features').doc();
      await docRef.set({
        'name': value,
        'createdBy': email,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      setState(() => _customFeatures.add(value));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Característica agregada')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al agregar: $e')));
    }
  }

  String _saveButtonMessage() {
    if (_saving) return 'Guardando...';
    if (_imageUrl == null || _imageUrl!.isEmpty) return 'La imagen es obligatoria';
    if (_nameExists) return 'Ya existe una carta con ese nombre';
    return '';
  }

    // UI
  // ==========================
  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initial != null;
    final bool saveEnabled = !_saving && (_imageUrl != null && _imageUrl!.isNotEmpty) && !_nameExists;

    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Editar carta' : 'Nueva carta')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              // Nombre con autocomplete
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _nombreCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Nombre',
                      prefixIcon: const Icon(Icons.style),
                      suffixIcon: _checkingNameExists
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : (_nameExists ? const Icon(Icons.error, color: Colors.red) : null),
                    ),
                    onChanged: (v) {
                      _onNameChanged(v);
                    },
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Ingresa el nombre';
                      if (v.trim().length < 2) return 'Nombre demasiado corto';
                      if (_nameExists) return 'Ya existe una carta con este nombre';
                      return null;
                    },
                  ),
                  const SizedBox(height: 6),
                  // sugerencias
                  if (_loadingNameSuggestions)
                    const SizedBox(height: 28, child: LinearProgressIndicator(minHeight: 2))
                  else if (_nameSuggestions.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: Card(
                        elevation: 2,
                        margin: EdgeInsets.zero,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _nameSuggestions.length,
                          itemBuilder: (ctx, i) {
                            final s = _nameSuggestions[i];
                            return ListTile(
                              dense: true,
                              title: Text(s),
                              onTap: () {
                                setState(() {
                                  _nombreCtrl.text = s;
                                  _nameSuggestions = [];
                                });
                                // re-check existence with the selected name
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
              ),
              const SizedBox(height: 12),

              // Edición
              DropdownButtonFormField<String>(
                value: _edicion,
                items: kEdiciones.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (v) => setState(() {
                  _edicion = v;
                  if (_raza != null && !(kRazasPorEdicion[_edicion] ?? []).contains(_raza)) {
                    _raza = null;
                  }
                }),
                decoration: const InputDecoration(
                  labelText: 'Edición',
                  prefixIcon: Icon(Icons.collections_bookmark),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Selecciona edición' : null,
              ),
              const SizedBox(height: 12),

              // Tipo
              DropdownButtonFormField<String>(
                value: _tipo,
                items: _tipos.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setState(() {
                  _tipo = v;
                  if (_tipo != 'Aliado') {
                    _raza = null;
                    _fuerzaCtrl.clear();
                  }
                }),
                decoration: const InputDecoration(
                  labelText: 'Tipo',
                  prefixIcon: Icon(Icons.category),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Selecciona tipo' : null,
              ),
              const SizedBox(height: 12),

              // Raza (solo Aliado y con edición definida)
              if (_tipo == 'Aliado' && _edicion != null)
                DropdownButtonFormField<String>(
                  value: _raza,
                  items: (kRazasPorEdicion[_edicion] ?? []).map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                  onChanged: (v) => setState(() => _raza = v),
                  decoration: const InputDecoration(
                    labelText: 'Raza',
                    prefixIcon: Icon(Icons.groups),
                  ),
                  validator: (v) => v == null || v.isEmpty ? 'Selecciona raza' : null,
                ),
              if (_tipo == 'Aliado' && _edicion == null)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Selecciona primero la edición para ver razas',
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ),
              // Coste (no mostrar si es Oro)
              if (_tipo != 'Oro')
                TextFormField(
                  controller: _costeCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Coste',
                    prefixIcon: Icon(Icons.local_fire_department),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null; // opcional
                    if (int.tryParse(v.trim()) == null) return 'Debe ser un número';
                    return null;
                  },
                ),
              if (_tipo != 'Oro') const SizedBox(height: 12),

              // Fuerza (solo Aliado)
              if (_tipo == 'Aliado')
                TextFormField(
                  controller: _fuerzaCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Fuerza',
                    prefixIcon: Icon(Icons.fitness_center),
                  ),
                  validator: (v) {
                    if (_tipo != 'Aliado') return null;
                    if (v == null || v.trim().isEmpty) return null; // opcional
                    if (int.tryParse(v.trim()) == null) return 'Debe ser un número';
                    return null;
                  },
                ),
              if (_tipo == 'Aliado') const SizedBox(height: 12),

              // Rareza
              DropdownButtonFormField<String>(
                value: _rarezaCtrl.text.isNotEmpty ? _rarezaCtrl.text : null,
                items: const [
                  DropdownMenuItem(
                    value: 'Real',
                    child: Row(
                      children: [
                        Icon(Icons.circle, color: Colors.yellow, size: 14),
                        SizedBox(width: 8),
                        Text('Real'),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'Cortesano',
                    child: Row(
                      children: [
                        Icon(Icons.circle, size: 14, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Cortesano'),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'Vasallo',
                    child: Row(
                      children: [
                        Icon(Icons.circle, size: 14, color: Colors.blue),
                        SizedBox(width: 8),
                        Text('Vasallo'),
                      ],
                    ),
                  ),
                ],
                onChanged: (v) => setState(() {
                  _rarezaCtrl.text = v ?? '';
                }),
                decoration: const InputDecoration(
                  labelText: 'Rareza',
                  prefixIcon: Icon(Icons.star_rate),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Selecciona rareza' : null,
              ),

              const SizedBox(height: 12),

              // Habilidad breve
              TextFormField(
                controller: _habilidadCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Habilidad / Regla corta',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.auto_fix_high),
                ),
              ),

              const SizedBox(height: 12),

              // Única
              SwitchListTile.adaptive(
                value: _unica,
                onChanged: (v) => setState(() => _unica = v),
                title: const Text('Carta única'),
                secondary: const Icon(Icons.star),
                contentPadding: EdgeInsets.zero,
              ),

              // Características (chips multi-select)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Expanded(
                    child: Text(
                      'Características',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                  if (_loadingCustomFeatures)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (_currentUserEmail() == _ownerEmail)
                    IconButton(
                      tooltip: 'Agregar característica nueva',
                      onPressed: _addCustomFeatureDialog,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _customFeatures.map((c) {
                  final selected = _caracteristicas.contains(c);
                  return FilterChip(
                    label: Text(c),
                    selected: selected,
                    onSelected: (v) => setState(() {
                      if (v) {
                        _caracteristicas.add(c);
                      } else {
                        _caracteristicas.remove(c);
                      }
                    }),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              // Botones: Guardar / Subir imagen / Ver imagen
              Row(
                children: [
                  Expanded(
                    child: Tooltip(
                      message: !_saveButtonMessage().isEmpty ? _saveButtonMessage() : 'Guardar',
                      child: FilledButton.icon(
                        onPressed: saveEnabled ? _save : null,
                        icon: const Icon(Icons.save),
                        label: _saving
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Guardar'),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Subir / Cambiar imagen
                  SizedBox(
                    height: 44,
                    child: FilledButton.icon(
                      onPressed: _imageUploading ? null : _pickAndUploadImage,
                      icon: _imageUploading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.image_outlined),
                      label: Text(_imageUrl == null ? 'Subir' : 'Cambiar'),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Ver imagen (si existe). Muestra una miniatura; al tocar abre modal con imagen ampliada.
                  if (_imageUrl != null)
                    Tooltip(
                      message: 'Ver imagen',
                      child: InkWell(
                        onTap: () => showDialog(
                          context: context,
                          builder: (ctx) => Dialog(
                            insetPadding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(
                                    widget.initial == null ? 'Imagen' : widget.initial!.nombre,
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                                Flexible(
                                  child: InteractiveViewer(
                                    child: Image.network(
                                      _imageUrl!,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => const Padding(
                                        padding: EdgeInsets.all(24),
                                        child: Icon(
                                          Icons.broken_image,
                                          size: 56,
                                        ),
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
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white12),
                          ),
                          clipBehavior: Clip.hardEdge,
                          child: _imageUrl!.contains('res.cloudinary.com')
                              ? Image.network(
                                  _imageUrl!.replaceFirst(
                                    '/upload/',
                                    '/upload/f_auto,q_auto,w_44,h_44,c_fill,g_auto/',
                                  ),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                                )
                              : Image.network(
                                  _imageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                                ),
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: IconButton(
                        onPressed: null,
                        icon: const Icon(
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
