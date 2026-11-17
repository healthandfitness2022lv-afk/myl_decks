// lib/screens/admin_bulk_assign_screen.dart
// Asignación masiva de imágenes Drive → cartas.
// Flujo por grupo:
//   1. Seleccionás imagen → tocás carta → queda en el grupo pendiente (no guarda aún)
//   2. Repetís hasta terminar la carpeta
//   3. "Guardar grupo" → pedimos nombre de variante → guardamos todo junto en Firestore
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/drive_service.dart';
import '../utils/app_constants.dart';
import '../utils/text_normalize.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/network_image.dart';

// ── Modelos ────────────────────────────────────────────────────────────────

class _CardItem {
  final String id;
  final String nombre;
  final String edicion;
  final String tipo;
  String? existingUrl; // officialImageUrl ya en Firestore

  _CardItem({
    required this.id,
    required this.nombre,
    required this.edicion,
    required this.tipo,
    this.existingUrl,
  });
}

// Una asignación pendiente: imagen Drive → carta
class _PendingAssign {
  final _CardItem card;
  final DriveFile image;
  _PendingAssign(this.card, this.image);
}

// ── Pantalla ───────────────────────────────────────────────────────────────

class AdminBulkAssignScreen extends StatefulWidget {
  const AdminBulkAssignScreen({super.key});

  @override
  State<AdminBulkAssignScreen> createState() => _AdminBulkAssignScreenState();
}

class _AdminBulkAssignScreenState extends State<AdminBulkAssignScreen> {
  // Drive
  List<DriveFile> _driveImages = [];
  List<DriveFile> _driveFolders = [];
  DriveFile? _selectedImage;
  bool _loadingDrive = false;
  String? _driveError;
  final List<(String, String)> _folderStack = [];

  String get _currentFolderId =>
      _folderStack.isEmpty
          ? DriveService.bulkRootFolderId
          : _folderStack.last.$1;
  String get _currentFolderName =>
      _folderStack.isEmpty ? 'Ediciones PBX' : _folderStack.last.$2;

  // Cartas
  List<_CardItem> _cards = [];
  bool _loadingCards = false;
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';

  // Grupo pendiente (imagen → carta, aún no guardado)
  final List<_PendingAssign> _pending = [];

  // Cartas ya confirmadas en esta sesión (cardId → viewUrl)
  final Map<String, String> _confirmed = {};
  // driveFileIds usados en esta sesión (para filtrar inmediatamente sin esperar Firestore)
  final Set<String> _confirmedDriveIds = {};

  // Guardando
  bool _savingGroup = false;

  // Filtro: mostrar solo cartas sin imagen
  bool _showOnlyWithoutImage = false;

  // Ocultar imágenes ya asignadas en el grid de Drive
  bool _hideUsedImages = false;
  // driveFileIds que ya están en al menos una variante en Firestore
  final Set<String> _usedDriveIds = {};
  bool _loadingUsedIds = false;

  // Zoom del grid de imágenes Drive (columnas: 3=grande … 10=chico)
  int _driveColumns = 7;

  // Notas por carpeta (folderId → nota) y contador de imágenes
  // (folderId → {total, assigned})
  final Map<String, String> _folderNotes = {};
  final Map<String, ({int total, int assigned})> _folderCounts = {};

  // Cache de listados Drive para evitar llamadas repetidas a la API
  final Map<String, List<DriveFile>> _driveListCache = {};
  // Cache de imágenes recursivas por carpeta (folderId → todas las imágenes)
  final Map<String, List<DriveFile>> _allImagesCache = {};

  // ── Init ──────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadDrive(_currentFolderId);
    _loadCards();
    _loadFolderNotes();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Notas de carpetas ─────────────────────────────────────────────────────

  Future<void> _loadFolderNotes() async {
    try {
      final snap =
          await FirebaseFirestore.instance
              .collection('drive_folder_notes')
              .get();
      if (!mounted) return;
      final notes = <String, String>{};
      for (final doc in snap.docs) {
        final n = doc.data()['note'] as String?;
        if (n != null && n.isNotEmpty) notes[doc.id] = n;
      }
      setState(() => _folderNotes.addAll(notes));
    } catch (e) {
      debugPrint('❌ _loadFolderNotes: $e');
    }
  }

  Future<void> _saveFolderNote(String folderId, String note) async {
    try {
      await FirebaseFirestore.instance
          .collection('drive_folder_notes')
          .doc(folderId)
          .set({'note': note, 'updatedAt': FieldValue.serverTimestamp()});
      setState(() {
        if (note.isEmpty) {
          _folderNotes.remove(folderId);
        } else {
          _folderNotes[folderId] = note;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error guardando nota: $e')));
      }
    }
  }

  Future<void> _showFolderOptions(DriveFile folder) async {
    final currentNote = _folderNotes[folder.id] ?? '';
    final noteCtrl = TextEditingController(text: currentNote);
    final counts = _folderCounts[folder.id];

    await showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A212C),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  folder.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                if (counts != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${counts.assigned}/${counts.total} imágenes asignadas',
                      style: TextStyle(
                        color:
                            counts.assigned >= counts.total && counts.total > 0
                                ? Colors.greenAccent
                                : const Color(0xFFF1D48B),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nota de la carpeta',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteCtrl,
                    autofocus: true,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Ej: No subir, Falta revisión, Completada…',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF12161D),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (currentNote.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _saveFolderNote(folder.id, '');
                  },
                  child: const Text(
                    'Borrar nota',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF1D48B),
                  foregroundColor: const Color(0xFF14181F),
                ),
                onPressed: () async {
                  final note = noteCtrl.text.trim();
                  Navigator.pop(ctx);
                  await _saveFolderNote(folder.id, note);
                },
                child: const Text('Guardar'),
              ),
            ],
          ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => noteCtrl.dispose());
  }

  // Calcula cuántas imágenes de la carpeta están en _usedDriveIds o _confirmedDriveIds
  void _updateFolderCounts(String folderId, List<DriveFile> images) {
    final total = images.length;
    final assigned =
        images
            .where(
              (img) =>
                  _usedDriveIds.contains(img.id) ||
                  _confirmedDriveIds.contains(img.id),
            )
            .length;
    setState(
      () => _folderCounts[folderId] = (total: total, assigned: assigned),
    );
  }

  // ── IDs usados ───────────────────────────────────────────────────────────

  static String? _safeUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    return DriveService.webSafeUrl(url);
  }

  // Regex para extraer el Drive file ID de una URL tipo:
  // https://drive.google.com/uc?export=view&id=FILE_ID
  static final _driveIdFromUrl = RegExp(r'[?&]id=([a-zA-Z0-9_-]+)');

  // Extrae el Drive file ID de cualquier campo de URL en un mapa de Firestore
  static Set<String> _extractIds(Map<String, dynamic> data) {
    final ids = <String>{};
    // campo directo
    final fid = data['driveFileId'] as String?;
    if (fid != null && fid.isNotEmpty) ids.add(fid);
    // cualquier campo que contenga una URL de Drive
    for (final val in data.values) {
      if (val is String && val.contains('drive.google.com')) {
        final m = _driveIdFromUrl.firstMatch(val);
        if (m != null) ids.add(m.group(1)!);
      }
    }
    return ids;
  }

  void _startUsedIdsListener() {
    if (_loadingUsedIds) return;
    setState(() => _loadingUsedIds = true);
    _doLoadUsedIds();
  }

  Future<void> _doLoadUsedIds() async {
    if (!mounted) return;
    try {
      final ids = <String>{};

      // 1. officialImageUrl de cada carta (imagen principal)
      final cardsSnap =
          await FirebaseFirestore.instance.collection('cards').get();
      for (final doc in cardsSnap.docs) {
        ids.addAll(_extractIds(doc.data()));
      }

      // 2. Todas las variantes de cada carta
      final futures = cardsSnap.docs.map(
        (cardDoc) =>
            FirebaseFirestore.instance
                .collection('cards')
                .doc(cardDoc.id)
                .collection('variants')
                .get(),
      );
      final variantSnaps = await Future.wait(futures);
      for (final snap in variantSnaps) {
        for (final doc in snap.docs) {
          ids.addAll(_extractIds(doc.data()));
        }
      }

      if (!mounted) return;
      setState(() {
        _usedDriveIds
          ..clear()
          ..addAll(ids);
        _loadingUsedIds = false;
      });
      // Refresca contadores de subcarpetas con los IDs recién cargados
      _prefetchSubfolderCounts(_driveFolders);
    } catch (e) {
      debugPrint('_doLoadUsedIds error: $e');
      if (mounted) setState(() => _loadingUsedIds = false);
    }
  }

  void _enableHideUsed() {
    _startUsedIdsListener();
  }

  void _disableHideUsed() {
    setState(() => _usedDriveIds.clear());
  }

  // Lista una carpeta usando cache en memoria para evitar llamadas repetidas
  Future<List<DriveFile>> _listFolderCached(String folderId) async {
    if (_driveListCache.containsKey(folderId)) {
      return _driveListCache[folderId]!;
    }
    final items = await DriveService.listFolder(folderId);
    _driveListCache[folderId] = items;
    return items;
  }

  Future<void> _loadDrive(String folderId) async {
    setState(() {
      _loadingDrive = true;
      _driveError = null;
      _driveImages = [];
      _driveFolders = [];
      _selectedImage = null;
    });
    try {
      final items = await _listFolderCached(folderId);
      if (!mounted) return;
      final folders = items.where((f) => f.isFolder).toList();
      final images = items.where((f) => !f.isFolder).toList();
      setState(() {
        _driveFolders = folders;
        _driveImages = images;
      });
      // Precarga en segundo plano los contadores de cada subcarpeta
      _prefetchSubfolderCounts(folders);
    } catch (e) {
      if (!mounted) return;
      setState(() => _driveError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingDrive = false);
    }
  }

  Future<void> _prefetchSubfolderCounts(List<DriveFile> folders) async {
    for (final folder in folders) {
      if (!mounted) return;
      // Si ya tenemos el conteo cacheado, solo actualizamos assigned (puede haber cambiado)
      if (_allImagesCache.containsKey(folder.id)) {
        _updateFolderCounts(folder.id, _allImagesCache[folder.id]!);
        continue;
      }
      try {
        final images = await _collectAllImages(folder.id);
        if (!mounted) return;
        _updateFolderCounts(folder.id, images);
      } catch (_) {}
    }
  }

  // Recorre recursivamente la carpeta usando cache, devuelve TODAS las imágenes
  Future<List<DriveFile>> _collectAllImages(String folderId) async {
    if (_allImagesCache.containsKey(folderId)) {
      return _allImagesCache[folderId]!;
    }
    final items = await _listFolderCached(folderId);
    final images = items.where((f) => !f.isFolder).toList();
    final subFolders = items.where((f) => f.isFolder).toList();
    for (final sub in subFolders) {
      if (!mounted) return images;
      images.addAll(await _collectAllImages(sub.id));
    }
    _allImagesCache[folderId] = images;
    return images;
  }

  void _enterFolder(DriveFile folder) {
    setState(() => _folderStack.add((folder.id, folder.name)));
    _loadDrive(folder.id);
  }

  void _goBack() {
    if (_folderStack.isEmpty) return;
    setState(() => _folderStack.removeLast());
    _loadDrive(_currentFolderId);
  }

  // ── Cartas ────────────────────────────────────────────────────────────────

  Future<void> _loadCards() async {
    setState(() => _loadingCards = true);
    try {
      final snap =
          await FirebaseFirestore.instance
              .collection('cards')
              .orderBy('nombre_lower')
              .get();
      if (!mounted) return;
      setState(() {
        _cards =
            snap.docs.map((d) {
              final m = d.data();
              return _CardItem(
                id: d.id,
                nombre: m['nombre'] as String? ?? d.id,
                edicion: m['edicion'] as String? ?? '',
                tipo: m['tipo'] as String? ?? '',
                existingUrl: _safeUrl(m['officialImageUrl'] as String?),
              );
            }).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error cargando cartas: $e')));
      }
    } finally {
      if (mounted) setState(() => _loadingCards = false);
    }
  }

  List<_CardItem> get _filteredCards {
    var list = _cards.where((c) {
      if (_showOnlyWithoutImage) {
        final hasImage =
            c.existingUrl != null ||
            _confirmed.containsKey(c.id) ||
            _pending.any((p) => p.card.id == c.id);
        if (hasImage) return false;
      }
      if (_search.isEmpty) return true;
      return normalizeSearch(c.nombre).contains(_search) ||
          normalizeSearch(c.edicion).contains(_search);
    });
    return list.toList();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _toCardId(String nombre) => nombre
      .toLowerCase()
      .replaceAll(RegExp(r'[áàä]'), 'a')
      .replaceAll(RegExp(r'[éèë]'), 'e')
      .replaceAll(RegExp(r'[íìï]'), 'i')
      .replaceAll(RegExp(r'[óòö]'), 'o')
      .replaceAll(RegExp(r'[úùü]'), 'u')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  Future<void> _saveCardStub(String nombre) async {
    final cardId = _toCardId(nombre);
    final ref = FirebaseFirestore.instance.collection('cards').doc(cardId);
    final existing = await ref.get();
    if (existing.exists) throw Exception('Ya existe "$cardId"');
    await ref.set({
      'nombre': nombre,
      'nombre_lower': nombre.toLowerCase(),
      'tipo': '',
      'edicion': '',
      'coste': 0,
      'rareza': '',
      'habilidad': '',
      'unica': false,
      'status': 'stub',
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (mounted) {
      setState(() {
        _cards.add(
          _CardItem(id: cardId, nombre: nombre, edicion: '', tipo: ''),
        );
        _cards.sort(
          (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
        );
      });
    }
  }

  // ── Agregar carta rápido ──────────────────────────────────────────────────

  Future<void> _quickAddCard() async {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    if (email.toLowerCase() != AppConstants.ownerEmail) return;

    final ctrl = TextEditingController();
    final nombre = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A212C),
            title: const Text(
              'Nueva carta rápida',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Solo el nombre — completá el resto después desde el catálogo.',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Nombre de la carta',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF12161D),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (v) {
                      if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF1D48B),
                  foregroundColor: const Color(0xFF14181F),
                ),
                onPressed: () {
                  final v = ctrl.text.trim();
                  if (v.isEmpty) return;
                  Navigator.pop(ctx, v);
                },
                child: const Text('Crear'),
              ),
            ],
          ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    if (nombre == null || !mounted) return;

    try {
      await _saveCardStub(nombre);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('✅ "$nombre" creada')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // ── Agregar muchas cartas de una vez ──────────────────────────────────────

  Future<void> _bulkAddCards() async {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    if (email.toLowerCase() != AppConstants.ownerEmail) return;

    final ctrl = TextEditingController();

    // Paso 1: ingresar la lista
    final confirmed = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => _BulkAddDialog(ctrl: ctrl),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    if (confirmed == null || confirmed.isEmpty || !mounted) return;

    // Paso 2: guardar con progreso
    int saved = 0;
    final errors = <String>[];

    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => _BulkProgressDialog(
            nombres: confirmed,
            onSave: _saveCardStub,
            onDone: (s, e) {
              saved = s;
              errors.addAll(e);
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
    );

    // El diálogo llama onDone que cierra él mismo; esperamos a que termine
    // mostrando el snack después de que se desmonte
    await Future.delayed(Duration.zero);
    if (!mounted) return;

    final msg =
        errors.isEmpty
            ? '✅ $saved carta(s) creadas'
            : '⚠️ $saved creadas — errores: ${errors.join(', ')}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 5),
        backgroundColor:
            errors.isEmpty ? const Color(0xFF1A3A1A) : const Color(0xFF3A1A1A),
      ),
    );
  }

  // ── Lógica del grupo ──────────────────────────────────────────────────────

  // Agrega o reemplaza la asignación pendiente para esa carta
  void _stagePair(_CardItem card) {
    final img = _selectedImage;
    if (img == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero seleccioná una imagen')),
      );
      return;
    }
    setState(() {
      _pending.removeWhere((p) => p.card.id == card.id);
      _pending.add(_PendingAssign(card, img));
    });
  }

  void _removePending(_PendingAssign p) => setState(() => _pending.remove(p));

  // Pide nombre de variante y guarda todo el grupo en Firestore
  Future<void> _commitGroup() async {
    if (_pending.isEmpty) return;

    // Diálogo: nombre de variante
    final nameCtrl = TextEditingController(text: 'Normal');
    final variantName = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A212C),
            title: const Text(
              'Nombre de variante',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Se guardará como variante en ${_pending.length} carta(s).',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Ej: Normal, Legendaria, Full Art…',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF12161D),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF1D48B),
                  foregroundColor: const Color(0xFF14181F),
                ),
                onPressed: () {
                  final v = nameCtrl.text.trim();
                  if (v.isEmpty) return;
                  Navigator.pop(ctx, v);
                },
                child: const Text('Guardar grupo'),
              ),
            ],
          ),
    );

    // Dispose after the dialog animation fully tears down to avoid
    // "controller used after dispose" when the TextField is still animating out.
    WidgetsBinding.instance.addPostFrameCallback((_) => nameCtrl.dispose());
    if (variantName == null || !mounted) return;

    setState(() => _savingGroup = true);

    final db = FirebaseFirestore.instance;
    int saved = 0;
    int errors = 0;

    for (final p in List.of(_pending)) {
      try {
        final cardRef = db.collection('cards').doc(p.card.id);
        final varRef = cardRef.collection('variants').doc();
        final viewUrl = p.image.viewUrl;

        final batch = db.batch();
        batch.set(varRef, {
          'name': variantName,
          'printType': variantName,
          'imageFrontUrl': viewUrl,
          'driveFileId': p.image.id,
          'imageSource': 'drive',
          'official': true,
          'approved': true,
          'status': 'approved',
          'createdAt': FieldValue.serverTimestamp(),
        });
        batch.set(cardRef, {
          'officialImageUrl': viewUrl,
          'officialVariantId': varRef.id,
          'officialUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        await batch.commit();

        _confirmed[p.card.id] = viewUrl;
        _confirmedDriveIds.add(p.image.id);
        p.card.existingUrl = _safeUrl(viewUrl);
        saved++;
      } catch (_) {
        errors++;
      }
    }

    if (!mounted) return;
    setState(() {
      _pending.clear();
      _savingGroup = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          errors == 0
              ? '✅ $saved carta(s) guardadas como "$variantName"'
              : '⚠️ $saved guardadas, $errors errores',
        ),
        backgroundColor:
            errors == 0 ? const Color(0xFF1A3A1A) : const Color(0xFF3A1A1A),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 700;
    final pendingCount = _pending.length;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1016),
      appBar: AppBar(
        backgroundColor: const Color(0xFF14181F),
        foregroundColor: Colors.white,
        title: const Text('Asignar imágenes en masa'),
        actions: [
          if (pendingCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: _savingGroup ? null : _commitGroup,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF1D48B),
                  foregroundColor: const Color(0xFF14181F),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 0,
                  ),
                  minimumSize: const Size(0, 36),
                ),
                icon:
                    _savingGroup
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF14181F),
                          ),
                        )
                        : const Icon(Icons.save_rounded, size: 18),
                label: Text('Guardar grupo ($pendingCount)'),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.playlist_add_rounded),
            tooltip: 'Agregar varias cartas',
            onPressed: _bulkAddCards,
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Nueva carta rápida',
            onPressed: _quickAddCard,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Recargar cartas',
            onPressed: _loadCards,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Bandeja de pendientes ──────────────────────────────────────
          if (_pending.isNotEmpty) _buildPendingTray(),

          // ── Cuerpo principal ──────────────────────────────────────────
          Expanded(
            child:
                isWide
                    ? Row(
                      children: [
                        SizedBox(width: 620, child: _buildDrivePanel()),
                        const VerticalDivider(width: 1, color: Colors.white10),
                        Expanded(child: _buildCardsPanel()),
                      ],
                    )
                    : Column(
                      children: [
                        SizedBox(height: 280, child: _buildDrivePanel()),
                        const Divider(height: 1, color: Colors.white10),
                        Expanded(child: _buildCardsPanel()),
                      ],
                    ),
          ),
        ],
      ),
    );
  }

  // ── Bandeja de pares pendientes ───────────────────────────────────────────
  Widget _buildPendingTray() {
    return Container(
      color: const Color(0xFF12161D),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.pending_actions_rounded,
                color: Color(0xFFF1D48B),
                size: 15,
              ),
              const SizedBox(width: 6),
              Text(
                'Pendientes de guardar (${_pending.length})',
                style: const TextStyle(
                  color: Color(0xFFF1D48B),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _pending.clear()),
                child: const Text(
                  'Limpiar todo',
                  style: TextStyle(color: Colors.redAccent, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _pending.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final p = _pending[i];
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 52,
                      height: 72,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFF1D48B)),
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: Column(
                        children: [
                          Expanded(
                            child: MylNetworkImage(
                              imageUrl: p.image.previewUrl,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              errorWidget:
                                  (_, __, ___) => const ColoredBox(
                                    color: Color(0xFF1A212C),
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      size: 14,
                                      color: Colors.white24,
                                    ),
                                  ),
                            ),
                          ),
                          Container(
                            color: const Color(0xFF0D1016),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 2,
                            ),
                            child: Text(
                              p.card.nombre,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Botón quitar
                    Positioned(
                      top: -5,
                      right: -5,
                      child: GestureDetector(
                        onTap: () => _removePending(p),
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 10,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Zoom de imagen ────────────────────────────────────────────────────────

  void _showImageZoom(DriveFile img) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder:
          (ctx) => GestureDetector(
            onTap: () => Navigator.pop(ctx),
            onLongPressEnd: (_) => Navigator.pop(ctx),
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: Stack(
                children: [
                  // Fondo: toca para cerrar
                  const SizedBox.expand(),
                  // Imagen centrada con zoom interactivo
                  Center(
                    child: Hero(
                      tag: 'zoom_${img.id}',
                      child: InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 6,
                        child: MylNetworkImage(
                          imageUrl: DriveService.webSafeUrl(img.viewUrl),
                          fit: BoxFit.contain,
                          placeholder:
                              (_, __) => const SizedBox(
                                width: 60,
                                height: 60,
                                child: CircularProgressIndicator(
                                  color: Color(0xFFF1D48B),
                                ),
                              ),
                          errorWidget:
                              (_, __, ___) => const Icon(
                                Icons.broken_image_outlined,
                                color: Colors.white38,
                                size: 64,
                              ),
                        ),
                      ),
                    ),
                  ),
                  // Nombre de la imagen arriba
                  Positioned(
                    top: MediaQuery.of(ctx).padding.top + 8,
                    left: 16,
                    right: 48,
                    child: Text(
                      img.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        shadows: [Shadow(color: Colors.black, blurRadius: 6)],
                      ),
                    ),
                  ),
                  // Botón cerrar
                  Positioned(
                    top: MediaQuery.of(ctx).padding.top + 4,
                    right: 8,
                    child: IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                      ),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  // ── Panel Drive ───────────────────────────────────────────────────────────
  Widget _buildDrivePanel() {
    return Container(
      color: const Color(0xFF0E1117),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            color: const Color(0xFF12161D),
            child: Row(
              children: [
                if (_folderStack.isNotEmpty)
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 16,
                      color: Colors.white70,
                    ),
                    onPressed: _goBack,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                const Icon(
                  Icons.folder_open_rounded,
                  color: Color(0xFFF1D48B),
                  size: 18,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _currentFolderName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Zoom −/+
                SizedBox(
                  width: 26,
                  height: 26,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.remove_rounded, size: 14),
                    color: _driveColumns < 10 ? Colors.white54 : Colors.white24,
                    onPressed:
                        _driveColumns < 10
                            ? () => setState(() => _driveColumns++)
                            : null,
                    tooltip: 'Más pequeñas',
                  ),
                ),
                SizedBox(
                  width: 26,
                  height: 26,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.add_rounded, size: 14),
                    color: _driveColumns > 3 ? Colors.white54 : Colors.white24,
                    onPressed:
                        _driveColumns > 3
                            ? () => setState(() => _driveColumns--)
                            : null,
                    tooltip: 'Más grandes',
                  ),
                ),
                if (_loadingDrive)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFF1D48B),
                    ),
                  ),
              ],
            ),
          ),

          // Hint
          Container(
            width: double.infinity,
            color:
                _selectedImage != null
                    ? const Color(0xFF1A0D2E)
                    : const Color(0xFF0A1520),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Text(
              _selectedImage != null
                  ? '📌 "${_selectedImage!.name}" — tocá una carta para asignar'
                  : 'Tocá una imagen para seleccionarla',
              style: TextStyle(
                color:
                    _selectedImage != null
                        ? const Color(0xFFC084FC)
                        : Colors.white38,
                fontSize: 11,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Switch ocultar usadas
          Container(
            color: const Color(0xFF0E1117),
            padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
            child: Row(
              children: [
                const Icon(
                  Icons.visibility_off_rounded,
                  size: 14,
                  color: Colors.white38,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Ocultar ya asignadas',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                      if (_usedDriveIds.isNotEmpty)
                        Text(
                          '${_usedDriveIds.length} ya asignadas',
                          style: const TextStyle(
                            color: Colors.white24,
                            fontSize: 9,
                          ),
                        ),
                    ],
                  ),
                ),
                if (_loadingUsedIds)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFF1D48B),
                      ),
                    ),
                  ),
                Switch.adaptive(
                  value: _hideUsedImages,
                  onChanged: (v) {
                    setState(() => _hideUsedImages = v);
                    if (v) {
                      _enableHideUsed();
                    } else {
                      _disableHideUsed();
                    }
                  },
                  activeColor: const Color(0xFFF1D48B),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),

          // Grid unificado: carpetas + imágenes en un solo scroll
          Expanded(
            child:
                _loadingDrive
                    ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFF1D48B),
                      ),
                    )
                    : _driveError != null
                    ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.cloud_off_rounded,
                              color: Colors.white24,
                              size: 40,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _driveError!,
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            TextButton.icon(
                              onPressed: () => _loadDrive(_currentFolderId),
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      ),
                    )
                    : Builder(
                      builder: (context) {
                        final visibleImages =
                            _hideUsedImages
                                ? _driveImages
                                    .where(
                                      (img) =>
                                          !_usedDriveIds.contains(img.id) &&
                                          !_confirmedDriveIds.contains(
                                            img.id,
                                          ) &&
                                          !_pending.any(
                                            (p) => p.image.id == img.id,
                                          ),
                                    )
                                    .toList()
                                : _driveImages;
                        final hasFolders = _driveFolders.isNotEmpty;
                        final hasImages = visibleImages.isNotEmpty;

                        if (!hasFolders && !hasImages) {
                          return Center(
                            child: Text(
                              _hideUsedImages
                                  ? '✅ Todas asignadas en esta carpeta'
                                  : 'Sin imágenes en esta carpeta',
                              style: const TextStyle(color: Colors.white38),
                            ),
                          );
                        }

                        return CustomScrollView(
                          slivers: [
                            // ── Carpetas ──────────────────────────────────
                            if (hasFolders) ...[
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    8,
                                    8,
                                    8,
                                    4,
                                  ),
                                  child: Text(
                                    'Carpetas (${_driveFolders.length})',
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: .5,
                                    ),
                                  ),
                                ),
                              ),
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                                sliver: SliverGrid(
                                  delegate: SliverChildBuilderDelegate((_, i) {
                                    final folder = _driveFolders[i];
                                    final counts = _folderCounts[folder.id];
                                    final note = _folderNotes[folder.id];
                                    final isComplete =
                                        counts != null &&
                                        counts.total > 0 &&
                                        counts.assigned >= counts.total;
                                    final hasNote =
                                        note != null && note.isNotEmpty;
                                    return GestureDetector(
                                      onTap: () => _enterFolder(folder),
                                      onLongPress:
                                          () => _showFolderOptions(folder),
                                      onSecondaryTap:
                                          () => _showFolderOptions(folder),
                                      child: Stack(
                                        children: [
                                          Container(
                                            decoration: BoxDecoration(
                                              color:
                                                  isComplete
                                                      ? const Color(0xFF0D2010)
                                                      : hasNote
                                                      ? const Color(0xFF1A1A0D)
                                                      : const Color(0xFF1A212C),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                color:
                                                    isComplete
                                                        ? Colors.greenAccent
                                                            .withValues(
                                                              alpha: .5,
                                                            )
                                                        : hasNote
                                                        ? const Color(
                                                          0xFFF1D48B,
                                                        ).withValues(alpha: .4)
                                                        : Colors.white10,
                                              ),
                                            ),
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.folder_rounded,
                                                  color:
                                                      isComplete
                                                          ? Colors.greenAccent
                                                          : const Color(
                                                            0xFFF1D48B,
                                                          ),
                                                  size: 24,
                                                ),
                                                const SizedBox(height: 2),
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 3,
                                                      ),
                                                  child: Text(
                                                    folder.name,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 9,
                                                    ),
                                                  ),
                                                ),
                                                if (counts != null) ...[
                                                  const SizedBox(height: 2),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 4,
                                                          vertical: 1,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          isComplete
                                                              ? Colors
                                                                  .greenAccent
                                                                  .withValues(
                                                                    alpha: .2,
                                                                  )
                                                              : Colors.white10,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      '${counts.assigned}/${counts.total}',
                                                      style: TextStyle(
                                                        color:
                                                            isComplete
                                                                ? Colors
                                                                    .greenAccent
                                                                : Colors
                                                                    .white54,
                                                        fontSize: 8,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                                if (hasNote) ...[
                                                  const SizedBox(height: 2),
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 3,
                                                        ),
                                                    child: Text(
                                                      note,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: const TextStyle(
                                                        color: Color(
                                                          0xFFF1D48B,
                                                        ),
                                                        fontSize: 7,
                                                        fontStyle:
                                                            FontStyle.italic,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          // Ícono de nota en esquina superior derecha
                                          if (hasNote)
                                            Positioned(
                                              top: 3,
                                              right: 3,
                                              child: Icon(
                                                Icons.sticky_note_2_rounded,
                                                size: 10,
                                                color: const Color(
                                                  0xFFF1D48B,
                                                ).withValues(alpha: .8),
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  }, childCount: _driveFolders.length),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: _driveColumns,
                                        mainAxisSpacing: 6,
                                        crossAxisSpacing: 6,
                                        childAspectRatio: .75,
                                      ),
                                ),
                              ),
                            ],

                            // ── Separador ─────────────────────────────────
                            if (hasFolders && hasImages)
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    8,
                                    8,
                                    8,
                                    4,
                                  ),
                                  child: Row(
                                    children: [
                                      const Expanded(
                                        child: Divider(
                                          color: Colors.white10,
                                          height: 1,
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                        child: Text(
                                          'Imágenes (${visibleImages.length})',
                                          style: const TextStyle(
                                            color: Colors.white38,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: .5,
                                          ),
                                        ),
                                      ),
                                      const Expanded(
                                        child: Divider(
                                          color: Colors.white10,
                                          height: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            // ── Imágenes ──────────────────────────────────
                            if (hasImages)
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                                sliver: SliverGrid(
                                  delegate: SliverChildBuilderDelegate((_, i) {
                                    final img = visibleImages[i];
                                    final isSel = _selectedImage?.id == img.id;
                                    final isUsed = _pending.any(
                                      (p) => p.image.id == img.id,
                                    );
                                    return GestureDetector(
                                      onLongPress: () => _showImageZoom(img),
                                      onTap:
                                          () => setState(
                                            () =>
                                                _selectedImage =
                                                    isSel ? null : img,
                                          ),
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 120,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color:
                                                isSel
                                                    ? const Color(0xFFC084FC)
                                                    : isUsed
                                                    ? const Color(0xFFF1D48B)
                                                    : Colors.white10,
                                            width: isSel ? 2.5 : 1,
                                          ),
                                          boxShadow:
                                              isSel
                                                  ? [
                                                    BoxShadow(
                                                      color: const Color(
                                                        0xFFC084FC,
                                                      ).withValues(alpha: .35),
                                                      blurRadius: 8,
                                                    ),
                                                  ]
                                                  : null,
                                        ),
                                        child: Stack(
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(9),
                                              child: MylNetworkImage(
                                                imageUrl: img.previewUrl,
                                                fit: BoxFit.cover,
                                                width: double.infinity,
                                                height: double.infinity,
                                                placeholder:
                                                    (_, __) => Container(
                                                      color: const Color(
                                                        0xFF12161D,
                                                      ),
                                                      child: const Center(
                                                        child: SizedBox(
                                                          width: 16,
                                                          height: 16,
                                                          child:
                                                              CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                                color: Color(
                                                                  0xFFF1D48B,
                                                                ),
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                errorWidget:
                                                    (_, __, ___) => Container(
                                                      color: const Color(
                                                        0xFF12161D,
                                                      ),
                                                      child: const Icon(
                                                        Icons
                                                            .broken_image_outlined,
                                                        color: Colors.white24,
                                                      ),
                                                    ),
                                              ),
                                            ),
                                            // nombre
                                            Positioned(
                                              left: 0,
                                              right: 0,
                                              bottom: 0,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 3,
                                                      vertical: 3,
                                                    ),
                                                decoration: const BoxDecoration(
                                                  gradient: LinearGradient(
                                                    begin:
                                                        Alignment.bottomCenter,
                                                    end: Alignment.topCenter,
                                                    colors: [
                                                      Color(0xCC000000),
                                                      Colors.transparent,
                                                    ],
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.vertical(
                                                        bottom: Radius.circular(
                                                          9,
                                                        ),
                                                      ),
                                                ),
                                                child: Text(
                                                  img.name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 9,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            // check seleccionada
                                            if (isSel)
                                              Positioned(
                                                top: 4,
                                                right: 4,
                                                child: Container(
                                                  width: 20,
                                                  height: 20,
                                                  decoration:
                                                      const BoxDecoration(
                                                        color: Color(
                                                          0xFFC084FC,
                                                        ),
                                                        shape: BoxShape.circle,
                                                      ),
                                                  child: const Icon(
                                                    Icons.check_rounded,
                                                    color: Colors.white,
                                                    size: 13,
                                                  ),
                                                ),
                                              ),
                                            // indicador "en uso"
                                            if (isUsed && !isSel)
                                              Positioned(
                                                top: 4,
                                                right: 4,
                                                child: Container(
                                                  width: 20,
                                                  height: 20,
                                                  decoration:
                                                      const BoxDecoration(
                                                        color: Color(
                                                          0xFFF1D48B,
                                                        ),
                                                        shape: BoxShape.circle,
                                                      ),
                                                  child: const Icon(
                                                    Icons.link_rounded,
                                                    color: Color(0xFF14181F),
                                                    size: 13,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }, childCount: visibleImages.length),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: _driveColumns,
                                        mainAxisSpacing: 6,
                                        crossAxisSpacing: 6,
                                        childAspectRatio: .72,
                                      ),
                                ),
                              ),

                            // Padding final
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 12),
                            ),
                          ],
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }

  // ── Panel cartas ──────────────────────────────────────────────────────────
  Widget _buildCardsPanel() {
    final filtered = _filteredCards;
    final confirmedCount = _confirmed.length;
    final total = _cards.length;

    return Column(
      children: [
        // Búsqueda + contador
        Container(
          color: const Color(0xFF12161D),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged:
                      (v) => setState(() => _search = normalizeSearch(v)),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Buscar carta...',
                    hintStyle: const TextStyle(
                      color: Colors.white38,
                      fontSize: 13,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Colors.white38,
                      size: 18,
                    ),
                    suffixIcon:
                        _search.isNotEmpty
                            ? IconButton(
                              icon: const Icon(
                                Icons.clear_rounded,
                                color: Colors.white38,
                                size: 16,
                              ),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _search = '');
                              },
                            )
                            : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    filled: true,
                    fillColor: const Color(0xFF1A212C),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message:
                    _showOnlyWithoutImage
                        ? 'Mostrando sin imagen'
                        : 'Mostrar solo sin imagen',
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  icon: Icon(
                    Icons.image_not_supported_rounded,
                    size: 18,
                    color:
                        _showOnlyWithoutImage
                            ? const Color(0xFFF1D48B)
                            : Colors.white24,
                  ),
                  onPressed:
                      () => setState(
                        () => _showOnlyWithoutImage = !_showOnlyWithoutImage,
                      ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '$confirmedCount/$total',
                style: TextStyle(
                  color:
                      confirmedCount > 0
                          ? const Color(0xFF4FC3F7)
                          : Colors.white38,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),

        // Lista
        Expanded(
          child:
              _loadingCards
                  ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFF1D48B)),
                  )
                  : filtered.isEmpty
                  ? const Center(
                    child: Text(
                      'Sin resultados',
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                  : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final card = filtered[i];
                      final pendingEntry =
                          _pending
                              .where((p) => p.card.id == card.id)
                              .firstOrNull;
                      final isConfirmed = _confirmed.containsKey(card.id);
                      final hasPending = pendingEntry != null;
                      final displayUrl =
                          pendingEntry?.image.previewUrl ??
                          _safeUrl(_confirmed[card.id]) ??
                          card.existingUrl;

                      return InkWell(
                        onTap: () => _stagePair(card),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color:
                                isConfirmed
                                    ? const Color(0xFF0A1A0A)
                                    : hasPending
                                    ? const Color(0xFF1A1400)
                                    : _selectedImage != null
                                    ? const Color(0xFF0D1520)
                                    : Colors.transparent,
                            border: const Border(
                              bottom: BorderSide(
                                color: Colors.white10,
                                width: .5,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 50,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  color: const Color(0xFF1A212C),
                                  border: Border.all(
                                    color:
                                        isConfirmed
                                            ? Colors.green.withValues(alpha: .5)
                                            : hasPending
                                            ? const Color(
                                              0xFFF1D48B,
                                            ).withValues(alpha: .6)
                                            : Colors.white10,
                                  ),
                                ),
                                clipBehavior: Clip.hardEdge,
                                child:
                                    displayUrl != null
                                        ? MylNetworkImage(
                                          imageUrl: displayUrl,
                                          fit: BoxFit.cover,
                                          errorWidget:
                                              (_, __, ___) => const Icon(
                                                Icons.broken_image_outlined,
                                                color: Colors.white24,
                                                size: 16,
                                              ),
                                        )
                                        : const Icon(
                                          Icons.image_outlined,
                                          color: Colors.white24,
                                          size: 16,
                                        ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      card.nombre,
                                      style: TextStyle(
                                        color:
                                            isConfirmed
                                                ? Colors.white54
                                                : Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '${card.tipo}${card.edicion.isNotEmpty ? ' · ${card.edicion}' : ''}',
                                      style: const TextStyle(
                                        color: Colors.white38,
                                        fontSize: 11,
                                      ),
                                    ),
                                    if (hasPending)
                                      Text(
                                        '⏳ pendiente: ${pendingEntry.image.name}',
                                        style: const TextStyle(
                                          color: Color(0xFFF1D48B),
                                          fontSize: 10,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (isConfirmed)
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: Colors.green,
                                  size: 20,
                                )
                              else if (hasPending)
                                const Icon(
                                  Icons.pending_rounded,
                                  color: Color(0xFFF1D48B),
                                  size: 20,
                                )
                              else if (_selectedImage != null)
                                const Icon(
                                  Icons.add_photo_alternate_rounded,
                                  color: Color(0xFF4FC3F7),
                                  size: 20,
                                )
                              else
                                const Icon(
                                  Icons.radio_button_unchecked,
                                  color: Colors.white12,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
        ),
      ],
    );
  }
}

// ── Widgets auxiliares para carga masiva ──────────────────────────────────

class _BulkAddDialog extends StatefulWidget {
  final TextEditingController ctrl;
  const _BulkAddDialog({required this.ctrl});

  @override
  State<_BulkAddDialog> createState() => _BulkAddDialogState();
}

class _BulkAddDialogState extends State<_BulkAddDialog> {
  List<String> _preview = [];

  void _parse(String text) {
    final lines =
        text
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
    setState(() => _preview = lines);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A212C),
      title: const Text(
        'Agregar varias cartas',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Un nombre por línea. Se crean todas como stub.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: widget.ctrl,
                autofocus: true,
                maxLines: 10,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Carta Uno\nCarta Dos\nCarta Tres…',
                  hintStyle: const TextStyle(
                    color: Colors.white24,
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: const Color(0xFF12161D),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: _parse,
              ),
              if (_preview.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '${_preview.length} carta(s) a crear:',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children:
                      _preview
                          .map(
                            (n) => Chip(
                              label: Text(
                                n,
                                style: const TextStyle(
                                  color: Color(0xFF14181F),
                                  fontSize: 11,
                                ),
                              ),
                              backgroundColor: const Color(0xFFF1D48B),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                            ),
                          )
                          .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFF1D48B),
            foregroundColor: const Color(0xFF14181F),
          ),
          onPressed:
              _preview.isEmpty ? null : () => Navigator.pop(context, _preview),
          child: Text(_preview.isEmpty ? 'Crear' : 'Crear ${_preview.length}'),
        ),
      ],
    );
  }
}

class _BulkProgressDialog extends StatefulWidget {
  final List<String> nombres;
  final Future<void> Function(String nombre) onSave;
  final void Function(int saved, List<String> errors) onDone;

  const _BulkProgressDialog({
    required this.nombres,
    required this.onSave,
    required this.onDone,
  });

  @override
  State<_BulkProgressDialog> createState() => _BulkProgressDialogState();
}

class _BulkProgressDialogState extends State<_BulkProgressDialog> {
  int _done = 0;
  String _current = '';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    int saved = 0;
    final errors = <String>[];
    for (final nombre in widget.nombres) {
      if (!mounted) break;
      setState(() => _current = nombre);
      try {
        await widget.onSave(nombre);
        saved++;
      } catch (_) {
        errors.add(nombre);
      }
      if (mounted) setState(() => _done++);
    }
    widget.onDone(saved, errors);
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.nombres.length;
    final progress = total == 0 ? 0.0 : _done / total;
    return AlertDialog(
      backgroundColor: const Color(0xFF1A212C),
      title: const Text(
        'Creando cartas…',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white12,
            color: const Color(0xFFF1D48B),
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 10),
          Text(
            '$_done / $total',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          if (_current.isNotEmpty)
            Text(
              _current,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
        ],
      ),
    );
  }
}
