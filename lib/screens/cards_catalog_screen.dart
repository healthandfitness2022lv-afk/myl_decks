// lib/screens/cards_catalog_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../data/pb_data.dart';
import '../domain/analisis_mazo/analisis_mazo.dart';
import '../models/card_myl.dart';
import '../services/drive_service.dart';
import '../models/current_user.dart';
import '../widgets/skeletons.dart';
import '../utils/app_constants.dart';
import '../utils/text_normalize.dart';
import 'card_details_screen.dart';
import 'new_card_screen.dart';
import '../widgets/network_image.dart';

class CardsCatalogScreen extends StatefulWidget {
  const CardsCatalogScreen({super.key});

  @override
  State<CardsCatalogScreen> createState() => _CardsCatalogScreenState();
}

class _CardsCatalogScreenState extends State<CardsCatalogScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  // ── estado de carga ─────────────────────────────────────────
  final List<CardMyL> _allCards = [];
  bool _initialLoading = true; // muestra spinner hasta tener datos
  bool _refreshing = false; // refresco silencioso desde servidor
  bool _enviandoLecturaMasiva = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _lecturaMasivaSub;
  String? _lecturaMasivaRunId;
  int _lecturaMasivaTotal = 0;
  int _lecturaMasivaHechas = 0;
  int _lecturaMasivaErrores = 0;
  bool _modoSeleccionIa = false;
  final Set<String> _seleccionIa = {};

  bool get _lecturaMasivaActiva =>
      _lecturaMasivaRunId != null && _lecturaMasivaHechas < _lecturaMasivaTotal;

  // ── roles por carta (según sus habilidades programadas) ──────
  final Map<String, List<String>> _caracCache = {};

  // ── resultados filtrados (computados fuera del build) ────────
  List<CardMyL> _filteredItems = [];
  Map<String, int> _caracCounts = {};
  List<String> _visibleCaracs = [];

  // ── filtros ──────────────────────────────────────────────────
  String? _edicion;
  String? _tipo;
  String? _raza;
  bool _soloLibre = false;
  bool _soloStubs = false; // filtro "solo incompletas"
  bool _soloSinHabilidad = false;
  final Set<String> _caracFilter = {};
  static final List<String> _features = [
    for (final r in roles) nombresRol[r]!,
  ];

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _loadAllCards();
  }

  /// Estrategia cache-first + carga progresiva:
  /// 1. Muestra la caché local de Firestore al instante (si existe).
  /// 2. Refresca desde el servidor EN CHUNKS paginados: las primeras cartas
  ///    aparecen de inmediato en vez de esperar la colección completa.
  Future<void> _loadAllCards() async {
    final query = FirebaseFirestore.instance
        .collection('cards')
        .orderBy('nombre');

    // — Paso 1: caché local (no hace red, es instantáneo) ————————
    try {
      final cacheSnap = await query.get(const GetOptions(source: Source.cache));
      if (!mounted) return;
      if (cacheSnap.docs.isNotEmpty) {
        _allCards
          ..clear()
          ..addAll(cacheSnap.docs.map((d) => CardMyL.fromMap(d.data(), d.id)));
        _caracCache.clear();
        setState(() {
          _initialLoading = false;
          _refreshing = true; // indica al usuario que hay refresh silencioso
          _recompute();
        });
      }
    } catch (_) {
      // Sin caché aún (primera apertura) → esperamos al servidor
    }

    // — Paso 2: servidor en chunks progresivos ———————————————————
    try {
      const chunkSize = 400;
      final fresh = <CardMyL>[];
      DocumentSnapshot<Map<String, dynamic>>? cursor;
      final hadCache = _allCards.isNotEmpty;

      while (true) {
        var q = query.limit(chunkSize);
        if (cursor != null) q = q.startAfterDocument(cursor);
        final snap = await q.get(const GetOptions(source: Source.server));
        if (!mounted) return;
        if (snap.docs.isEmpty) break;

        fresh.addAll(snap.docs.map((d) => CardMyL.fromMap(d.data(), d.id)));
        cursor = snap.docs.last;

        // Sin caché previa: pintar progresivamente cada chunk recibido.
        if (!hadCache) {
          _allCards
            ..clear()
            ..addAll(fresh);
          _caracCache.clear();
          setState(() {
            _initialLoading = false;
            _refreshing = true;
            _recompute();
          });
        }
        if (snap.docs.length < chunkSize) break;
      }

      if (!mounted) return;
      _allCards
        ..clear()
        ..addAll(fresh);
      _caracCache.clear();
      setState(() {
        _initialLoading = false;
        _refreshing = false;
        _recompute();
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _initialLoading = false;
          _refreshing = false;
        });
    }
  }

  bool _tieneTextoHabilidad(Map<String, dynamic> data) {
    for (final campo in ['habilidadTextoIA', 'habilidad']) {
      final texto = '${data[campo] ?? ''}'.trim();
      if (RegExp(r'\p{L}', unicode: true).allMatches(texto).length >= 8) {
        return true;
      }
    }
    return false;
  }

  bool _cartaTieneTextoHabilidad(CardMyL carta) => _tieneTextoHabilidad({
    'habilidadTextoIA': carta.habilidadTextoIA,
    'habilidad': carta.habilidad,
  });

  /// Encola todo el catálogo en lotes de 60, el máximo seguro del worker.
  /// Solo incluye cartas con imagen oficial y sin texto, por lo que repetir
  /// esta acción no vuelve a gastar en las cartas ya leídas.
  Future<void> _leerHabilidadesMasivamente({Set<String>? soloIds}) async {
    final current = context.read<CurrentUser>();
    if ((current.email ?? '').toLowerCase() != AppConstants.ownerEmail) return;

    setState(() => _enviandoLecturaMasiva = true);
    try {
      final snap = await FirebaseFirestore.instance.collection('cards').get();
      final ids = [
        for (final doc in snap.docs)
          if ((soloIds == null || soloIds.contains(doc.id)) &&
              '${doc.data()['officialImageUrl'] ?? ''}'.trim().isNotEmpty &&
              !_tieneTextoHabilidad(doc.data()))
            doc.id,
      ];
      if (!mounted) return;
      if (ids.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              soloIds == null
                  ? 'No hay cartas con imagen pendientes de leer.'
                  : 'Ninguna de las cartas seleccionadas necesita lectura.',
            ),
          ),
        );
        return;
      }

      final grupos = <List<String>>[
        for (var i = 0; i < ids.length; i += 60)
          ids.sublist(i, (i + 60).clamp(0, ids.length)),
      ];
      final confirmar = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Leer catálogo con IA'),
              content: Text(
                'Se leerán ${ids.length} cartas con imagen oficial pero sin texto de habilidad. '
                'Se enviarán ${grupos.length} lote(s) al worker local.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('Empezar lectura'),
                ),
              ],
            ),
      );
      if (confirmar != true || !mounted) return;

      final uid = current.uid;
      if (uid == null) return;
      final runId = 'catalogo-${DateTime.now().toUtc().microsecondsSinceEpoch}';
      await Future.wait(
        grupos.map(
          (lote) => FirebaseFirestore.instance.collection('card_ai_jobs').add({
            'ownerUid': uid,
            'tipo': 'leer',
            'cardIds': lote,
            'bulkRunId': runId,
            'status': 'pending',
            'createdAt': FieldValue.serverTimestamp(),
          }),
        ),
      );
      if (!mounted) return;
      _observarLecturaMasiva(runId, ids.length);
      setState(() {
        _modoSeleccionIa = false;
        _seleccionIa.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${ids.length} cartas enviadas en ${grupos.length} lote(s). El worker seguirá en segundo plano.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo iniciar la lectura masiva: $e')),
      );
    } finally {
      if (mounted) setState(() => _enviandoLecturaMasiva = false);
    }
  }

  void _observarLecturaMasiva(String runId, int total) {
    _lecturaMasivaSub?.cancel();
    setState(() {
      _lecturaMasivaRunId = runId;
      _lecturaMasivaTotal = total;
      _lecturaMasivaHechas = 0;
      _lecturaMasivaErrores = 0;
    });
    _lecturaMasivaSub = FirebaseFirestore.instance
        .collection('card_ai_jobs')
        .where('bulkRunId', isEqualTo: runId)
        .snapshots()
        .listen((snap) {
          var hechas = 0;
          var errores = 0;
          for (final doc in snap.docs) {
            final data = doc.data();
            final ids = List<Object?>.from(
              data['cardIds'] as List? ?? const [],
            );
            final resultados = Map<String, dynamic>.from(
              data['resultados'] as Map? ?? const {},
            );
            hechas += resultados.length;
            for (final resultado in resultados.values) {
              if (resultado is Map && resultado['status'] == 'error') errores++;
            }
            // Si un lote falla antes de alcanzar cada carta, se cierra igual
            // para que el contador no quede detenido indefinidamente.
            if ((data['status'] == 'error' || data['status'] == 'blocked') &&
                resultados.length < ids.length) {
              hechas += ids.length - resultados.length;
              errores += ids.length - resultados.length;
            }
          }
          if (!mounted) return;
          setState(() {
            _lecturaMasivaHechas = hechas.clamp(0, total);
            _lecturaMasivaErrores = errores;
          });
        }, onError: (_) {});
  }

  Widget _barraLecturaMasiva() {
    final total = _lecturaMasivaTotal;
    if (_lecturaMasivaRunId == null || total == 0)
      return const SizedBox.shrink();
    final hechas = _lecturaMasivaHechas.clamp(0, total);
    final terminada = hechas >= total;
    final progreso = total == 0 ? 0.0 : hechas / total;
    return Container(
      color: const Color(0xFF12262C),
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 12),
      child: Row(
        children: [
          Icon(
            terminada
                ? Icons.check_circle_rounded
                : Icons.document_scanner_outlined,
            color:
                terminada ? const Color(0xFF34D399) : const Color(0xFF7DD3FC),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  terminada
                      ? 'Lectura del catálogo terminada'
                      : 'Leyendo habilidades con IA',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                LinearProgressIndicator(
                  value: progreso,
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(8),
                  color: const Color(0xFF7DD3FC),
                  backgroundColor: Colors.white12,
                ),
                const SizedBox(height: 5),
                Text(
                  '$hechas / $total cartas · ${(progreso * 100).round()}%'
                  '${_lecturaMasivaErrores > 0 ? ' · $_lecturaMasivaErrores con error' : ''}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          if (terminada)
            IconButton(
              tooltip: 'Cerrar progreso',
              icon: const Icon(Icons.close, color: Colors.white54),
              onPressed: () {
                _lecturaMasivaSub?.cancel();
                setState(() => _lecturaMasivaRunId = null);
              },
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _lecturaMasivaSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(_recompute);
    });
  }

  // Recalcula filteredItems / caracCounts / visibleCaracs fuera del build
  void _recompute() {
    final q = normalizeSearch(_searchCtrl.text);

    final preChar =
        _allCards.where((c) {
          if (q.isNotEmpty && !normalizeSearch(c.nombre).contains(q))
            return false;
          if (_soloStubs && !c.isStub) return false;
          if (_edicion != null && c.edicion != _edicion) return false;
          if (_tipo != null && c.tipo != _tipo) return false;
          if (_raza != null) {
            if (c.tipo.toLowerCase() != 'aliado') return false;
            if ((c.raza ?? '') != _raza) return false;
          }
          if (_soloLibre && !c.soloLibre) return false;
          if (_soloSinHabilidad && _cartaTieneTextoHabilidad(c)) return false;
          return true;
        }).toList();

    final counts = <String, int>{for (final c in _features) c: 0};
    for (final card in preChar) {
      for (final name in _caracteristicasDe(card)) {
        if (counts.containsKey(name)) counts[name] = counts[name]! + 1;
      }
    }

    _caracCounts = counts;
    _visibleCaracs = _features.where((c) => (counts[c] ?? 0) > 0).toList();
    _filteredItems =
        _caracFilter.isEmpty
            ? preChar
            : preChar
                .where((c) => _caracteristicasDe(c).toSet().containsAll(_caracFilter))
                .toList();
  }

  bool get _esAliado => (_tipo ?? '').toLowerCase() == 'aliado';

  List<String> get _razasDeEdicion {
    final e = _edicion;
    if (e == null) return const <String>[];
    return PBData.razasPorEdicion[e] ?? const <String>[];
  }

  void _clearFilters() {
    setState(() {
      _edicion = null;
      _tipo = null;
      _raza = null;
      _soloLibre = false;
      _soloStubs = false;
      _soloSinHabilidad = false;
      _caracFilter.clear();
      _searchCtrl.clear();
      _recompute();
    });
  }

  Future<void> _quickAddCard() async {
    final ctrl = TextEditingController();
    final nombre = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A212C),
            title: const Text(
              'Agregar carta rápido',
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
                    'Se crea con solo el nombre. Completá el resto después.',
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

    final cardId = nombre
        .toLowerCase()
        .replaceAll(RegExp(r'[áàä]'), 'a')
        .replaceAll(RegExp(r'[éèë]'), 'e')
        .replaceAll(RegExp(r'[íìï]'), 'i')
        .replaceAll(RegExp(r'[óòö]'), 'o')
        .replaceAll(RegExp(r'[úùü]'), 'u')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');

    try {
      final ref = FirebaseFirestore.instance.collection('cards').doc(cardId);
      final existing = await ref.get();
      if (existing.exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ya existe una carta con ID "$cardId"')),
        );
        return;
      }
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

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ "$nombre" creada — completá el resto cuando puedas'),
          action: SnackBarAction(
            label: 'Completar ahora',
            onPressed: () => _loadAllCards(),
          ),
        ),
      );
      _loadAllCards();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al crear: $e')));
    }
  }

  InputDecoration _catalogInputDecoration({
    String? hintText,
    String? labelText,
    Widget? prefixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      labelText: labelText,
      prefixIcon: prefixIcon,
      hintStyle: const TextStyle(color: Colors.white54),
      labelStyle: const TextStyle(color: Colors.white70),
      filled: true,
      fillColor: const Color(0xFF12161D),
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
      isDense: true,
    );
  }

  // ========================================
  // Características desde el modelo/Firestore
  // ========================================
  /// Calcula conteos directamente desde las cartas ya cargadas en memoria.
  /// Si aún hay páginas pendientes, muestra una nota al usuario.
  Map<String, dynamic> _computeCounts() {
    final Map<String, int> byEdition = {};
    final Map<String, Map<String, int>> byEditionType = {};

    for (final c in _allCards) {
      final ed = c.edicion.isNotEmpty ? c.edicion : 'Sin edición';
      final tipo = c.tipo.isNotEmpty ? c.tipo : 'Desconocido';
      byEdition[ed] = (byEdition[ed] ?? 0) + 1;
      byEditionType.putIfAbsent(ed, () => {})[tipo] =
          (byEditionType[ed]![tipo] ?? 0) + 1;
    }

    return {
      'total': _allCards.length,
      'hasMore': _refreshing,
      'byEdition': byEdition,
      'byEditionType': byEditionType,
    };
  }

  /// Muestra diálogo con los conteos usando los datos ya cargados en memoria.
  void _showCountsDialog(BuildContext context) {
    final data = _computeCounts();

    showDialog(
      context: context,
      builder:
          (ctx) => Dialog(
            insetPadding: const EdgeInsets.all(12),
            child: SizedBox(
              width: 520,
              height: 520,
              child: Builder(
                builder: (context) {
                  final int total = data['total'] as int;
                  final Map<String, int> byEdition = Map<String, int>.from(
                    data['byEdition'] as Map,
                  );
                  final Map<String, Map<String, int>> byEditionType =
                      (data['byEditionType'] as Map).map(
                        (k, v) => MapEntry(
                          k as String,
                          Map<String, int>.from(v as Map),
                        ),
                      );

                  final editionsSorted =
                      byEdition.keys.toList()..sort(
                        (a, b) => byEdition[b]!.compareTo(byEdition[a]!),
                      ); // descendente

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                (data['hasMore'] as bool? ?? false)
                                    ? 'Estadísticas — $total cargadas*'
                                    : 'Estadísticas — Total: $total',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          separatorBuilder:
                              (_, __) => const SizedBox(height: 8),
                          itemCount: editionsSorted.length,
                          itemBuilder: (context, i) {
                            final ed = editionsSorted[i];
                            final edTotal = byEdition[ed] ?? 0;
                            final types = byEditionType[ed] ?? {};
                            // ordenar tipos por cantidad descendente
                            final typesList =
                                types.keys.toList()..sort(
                                  (a, b) => types[b]!.compareTo(types[a]!),
                                );

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$ed — $edTotal',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 6,
                                  children:
                                      typesList.map((t) {
                                        final cnt = types[t] ?? 0;
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .surfaceVariant
                                                .withOpacity(0.6),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            '$t: $cnt',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
    );
  }

  /// Qué hace la carta: sus roles, del más fuerte al más débil.
  List<String> _caracteristicasDe(CardMyL c) =>
      _caracCache[c.id] ??= [
        for (final r in rolesOrdenados(c)) nombresRol[r]!,
      ];

  // ===== función para eliminar carta (solo administrador) =====
  Future<void> _confirmAndDeleteCard(String cardId) async {
    final isAdmin = context.read<CurrentUser>().isAdmin;
    if (!isAdmin) return;

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Eliminar carta'),
            content: Text(
              '¿Seguro querés eliminar la carta "$cardId"? Se borrarán sus variantes también.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
    );

    if (ok != true) return;

    setState(() {});
    final ScaffoldMessengerState sm = ScaffoldMessenger.of(context);
    try {
      final cardRef = FirebaseFirestore.instance
          .collection('cards')
          .doc(cardId);

      // eliminar variantes en batch (si existen)
      final variantsSnap = await cardRef.collection('variants').get();
      final batch = FirebaseFirestore.instance.batch();
      for (final d in variantsSnap.docs) {
        batch.delete(d.reference);
      }
      // borrar doc de la carta
      batch.delete(cardRef);

      await batch.commit();
      sm.showSnackBar(
        const SnackBar(content: Text('Carta eliminada correctamente.')),
      );
    } catch (e) {
      sm.showSnackBar(SnackBar(content: Text('Error al eliminar: $e')));
    } finally {
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    final puedeLeerConIa =
        (context.watch<CurrentUser>().email ?? '').toLowerCase() ==
        AppConstants.ownerEmail;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1016),
      // El buscador está en el AppBar (siempre visible arriba), así que el body
      // no necesita redimensionarse al aparecer el teclado → evita relayout del grid.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: const Color(0xFF14181F),
        foregroundColor: Colors.white,
        title: const Text('Catálogo'),
        centerTitle: true,
        actions: [
          if (puedeLeerConIa)
            IconButton(
              tooltip: 'Leer habilidades pendientes con IA',
              icon:
                  _enviandoLecturaMasiva
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.document_scanner_outlined),
              onPressed:
                  _enviandoLecturaMasiva ||
                          _lecturaMasivaActiva ||
                          _modoSeleccionIa
                      ? null
                      : _leerHabilidadesMasivamente,
            ),
          if (puedeLeerConIa)
            IconButton(
              tooltip:
                  _modoSeleccionIa
                      ? 'Cancelar selección de lectura'
                      : 'Seleccionar cartas para leer',
              icon: Icon(
                _modoSeleccionIa
                    ? Icons.playlist_remove_rounded
                    : Icons.checklist_rounded,
              ),
              onPressed:
                  _lecturaMasivaActiva
                      ? null
                      : () => setState(() {
                        _modoSeleccionIa = !_modoSeleccionIa;
                        if (!_modoSeleccionIa) _seleccionIa.clear();
                      }),
            ),
          IconButton(
            tooltip: 'Agregar carta rápido (solo nombre)',
            icon: const Icon(Icons.bolt_rounded),
            onPressed: _quickAddCard,
          ),
          IconButton(
            tooltip: 'Estadísticas (por edición / tipo)',
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showCountsDialog(context),
          ),
          if (!wide)
            IconButton(
              tooltip: 'Filtrar por lo que hace la carta',
              icon: const Icon(Icons.tune),
              onPressed: () => _openCaracFilterSheet(context),
            ),
          IconButton(
            tooltip: 'Limpiar filtros',
            onPressed: _clearFilters,
            icon: const Icon(Icons.filter_alt_off),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(wide ? 64 : 118),
          child: Container(
            color: const Color(0xFF14181F),
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child:
                wide
                    ? _buildFiltersRow()
                    : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: _searchCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: _catalogInputDecoration(
                            prefixIcon: const Icon(
                              Icons.search,
                              color: Colors.white70,
                            ),
                            hintText: 'Buscar carta...',
                          ),
                        ),
                        const SizedBox(height: 6),
                        _buildFiltersRow(),
                      ],
                    ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nueva carta',
        backgroundColor: const Color(0xFFF1D48B),
        foregroundColor: const Color(0xFF14181F),
        onPressed: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const NewCardScreen()));
        },
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [_barraLecturaMasiva(), Expanded(child: _buildBody(wide))],
      ),
    );
  }

  Widget _buildFiltersRow() {
    final wide = MediaQuery.of(context).size.width >= 900;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (wide)
            SizedBox(
              width: 220,
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: _catalogInputDecoration(
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  hintText: 'Buscar...',
                ),
              ),
            ),
          if (wide) const SizedBox(width: 8),
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<String>(
              value: _edicion,
              dropdownColor: const Color(0xFF14181F),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              iconEnabledColor: Colors.white70,
              isExpanded: true,
              decoration: _catalogInputDecoration(labelText: 'Edición'),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('Todas'),
                ),
                ...PBData.ediciones.map(
                  (e) => DropdownMenuItem(value: e, child: Text(e)),
                ),
              ],
              onChanged:
                  (v) => setState(() {
                    _edicion = v;
                    if (_raza != null && !_razasDeEdicion.contains(_raza)) {
                      _raza = null;
                    }
                    _recompute();
                  }),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 130,
            child: DropdownButtonFormField<String>(
              value: _tipo,
              dropdownColor: const Color(0xFF14181F),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              iconEnabledColor: Colors.white70,
              isExpanded: true,
              decoration: _catalogInputDecoration(labelText: 'Tipo'),
              items: const [
                DropdownMenuItem<String>(value: null, child: Text('Todos')),
                DropdownMenuItem(value: 'Aliado', child: Text('Aliado')),
                DropdownMenuItem(value: 'Talismán', child: Text('Talismán')),
                DropdownMenuItem(value: 'Tótem', child: Text('Tótem')),
                DropdownMenuItem(value: 'Arma', child: Text('Arma')),
                DropdownMenuItem(value: 'Oro', child: Text('Oro')),
              ],
              onChanged:
                  (v) => setState(() {
                    _tipo = v;
                    if (!_esAliado) _raza = null;
                    _recompute();
                  }),
            ),
          ),
          if (_esAliado && _edicion != null) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 130,
              child: DropdownButtonFormField<String>(
                value: _raza,
                dropdownColor: const Color(0xFF14181F),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                iconEnabledColor: Colors.white70,
                isExpanded: true,
                decoration: _catalogInputDecoration(labelText: 'Raza'),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('Todas'),
                  ),
                  ..._razasDeEdicion.map(
                    (r) => DropdownMenuItem(value: r, child: Text(r)),
                  ),
                ],
                onChanged:
                    (v) => setState(() {
                      _raza = v;
                      _recompute();
                    }),
              ),
            ),
          ],
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Libre', style: TextStyle(fontSize: 12)),
            selected: _soloLibre,
            onSelected:
                (v) => setState(() {
                  _soloLibre = v;
                  _recompute();
                }),
            selectedColor: const Color(0x33C084FC),
            checkmarkColor: const Color(0xFFC084FC),
            labelStyle: TextStyle(
              color: _soloLibre ? const Color(0xFFC084FC) : Colors.white70,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            side: BorderSide(
              color: _soloLibre ? const Color(0xFFC084FC) : Colors.white24,
            ),
            backgroundColor: const Color(0xFF12161D),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),
          FilterChip(
            avatar: const Icon(Icons.warning_amber_rounded, size: 14),
            label: const Text('Incompletas', style: TextStyle(fontSize: 12)),
            selected: _soloStubs,
            onSelected:
                (v) => setState(() {
                  _soloStubs = v;
                  _recompute();
                }),
            selectedColor: const Color(0x33F59E0B),
            checkmarkColor: const Color(0xFFF59E0B),
            avatarBoxConstraints: const BoxConstraints(
              maxWidth: 20,
              maxHeight: 20,
            ),
            labelStyle: TextStyle(
              color: _soloStubs ? const Color(0xFFF59E0B) : Colors.white70,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            side: BorderSide(
              color: _soloStubs ? const Color(0xFFF59E0B) : Colors.white24,
            ),
            backgroundColor: const Color(0xFF12161D),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),
          FilterChip(
            avatar: const Icon(Icons.document_scanner_outlined, size: 14),
            label: const Text(
              'Sin texto de habilidad',
              style: TextStyle(fontSize: 12),
            ),
            selected: _soloSinHabilidad,
            onSelected:
                (v) => setState(() {
                  _soloSinHabilidad = v;
                  _recompute();
                }),
            selectedColor: const Color(0x337DD3FC),
            checkmarkColor: const Color(0xFF7DD3FC),
            labelStyle: TextStyle(
              color:
                  _soloSinHabilidad ? const Color(0xFF7DD3FC) : Colors.white70,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            side: BorderSide(
              color:
                  _soloSinHabilidad ? const Color(0xFF7DD3FC) : Colors.white24,
            ),
            backgroundColor: const Color(0xFF12161D),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildBody(bool wide) {
    if (_initialLoading) {
      return const SkeletonCatalogGrid();
    }

    final items = _filteredItems;
    final puedeSeleccionarIa =
        (context.read<CurrentUser>().email ?? '').toLowerCase() ==
        AppConstants.ownerEmail;

    void onToggleCarac(String name, bool v) => setState(() {
      if (v)
        _caracFilter.add(name);
      else
        _caracFilter.remove(name);
      _recompute();
    });
    void onClearCarac() => setState(() {
      _caracFilter.clear();
      _recompute();
    });

    final grid = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final maxExtent =
            width >= 1400
                ? 250.0
                : width >= 1000
                ? 220.0
                : 190.0;
        return GridView.builder(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: maxExtent,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: .62,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final card = items[i];
            return _CatalogGridCard(
              card: card,
              caracs: const [],
              selectionMode: _modoSeleccionIa,
              selected: _seleccionIa.contains(card.id),
              onTap: () {
                if (_modoSeleccionIa) {
                  setState(() {
                    if (!_seleccionIa.add(card.id))
                      _seleccionIa.remove(card.id);
                  });
                  return;
                }
                if (card.isStub) {
                  Navigator.of(context)
                      .push(
                        MaterialPageRoute(
                          builder: (_) => NewCardScreen(initial: card),
                        ),
                      )
                      .then((_) => _loadAllCards());
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CardDetailsScreen(card: card),
                    ),
                  );
                }
              },
              onLongPress:
                  !puedeSeleccionarIa || _lecturaMasivaActiva
                      ? null
                      : () => setState(() {
                        _modoSeleccionIa = true;
                        _seleccionIa.add(card.id);
                      }),
            );
          },
        );
      },
    );

    // Barra de estado: chips de filtros activos + pills de conteo + spinner de refresh
    Widget statusBar = Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (_caracFilter.isNotEmpty) ...[
                  ..._caracFilter.map(
                    (c) => InputChip(
                      label: Text(c),
                      onDeleted:
                          () => setState(() {
                            _caracFilter.remove(c);
                            _recompute();
                          }),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onClearCarac,
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('Limpiar'),
                  ),
                ],
                _CatalogInfoPill(label: 'Resultados', value: '${items.length}'),
                _CatalogInfoPill(label: 'Total', value: '${_allCards.length}'),
                if (_modoSeleccionIa)
                  ActionChip(
                    avatar: const Icon(Icons.check_circle_outline, size: 17),
                    label: Text(
                      '${_seleccionIa.length} seleccionadas · Leer IA',
                    ),
                    onPressed:
                        _seleccionIa.isEmpty || _lecturaMasivaActiva
                            ? null
                            : () => _leerHabilidadesMasivamente(
                              soloIds: _seleccionIa.toSet(),
                            ),
                  ),
                if (_modoSeleccionIa && _seleccionIa.isEmpty)
                  const Chip(label: Text('Toca cartas para seleccionarlas')),
              ],
            ),
          ),
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );

    if (items.isEmpty) {
      return wide
          ? Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    statusBar,
                    const Expanded(child: _EmptyResultHint()),
                  ],
                ),
              ),
              _RightPanel(
                allCaracs: _visibleCaracs,
                caracCounts: _caracCounts,
                selected: _caracFilter,
                onToggle: onToggleCarac,
                onClear: onClearCarac,
              ),
            ],
          )
          : Column(
            children: [statusBar, const Expanded(child: _EmptyResultHint())],
          );
    }

    if (!wide) {
      return Column(children: [statusBar, Expanded(child: grid)]);
    }

    // Vista ancha con panel lateral
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: Column(children: [statusBar, Expanded(child: grid)])),
        _RightPanel(
          allCaracs: _visibleCaracs,
          caracCounts: _caracCounts,
          selected: _caracFilter,
          onToggle: onToggleCarac,
          onClear: onClearCarac,
        ),
      ],
    );
  }

  void _openCaracFilterSheet(BuildContext context) {
    // Usa los datos ya calculados en memoria (_visibleCaracs, _caracCounts)
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.tune),
                        const SizedBox(width: 8),
                        const Text(
                          'Qué hace la carta',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _caracFilter.clear();
                              _recompute();
                            });
                            Navigator.pop(context);
                          },
                          icon: const Icon(Icons.clear_all),
                          label: const Text('Limpiar'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final name in _visibleCaracs)
                            CheckboxListTile(
                              value: _caracFilter.contains(name),
                              onChanged: (bool? v) {
                                setState(() {
                                  if (v == true) {
                                    _caracFilter.add(name);
                                  } else {
                                    _caracFilter.remove(name);
                                  }
                                  _recompute();
                                });
                                setSheetState(() {});
                              },
                              dense: true,
                              title: Text(name),
                              secondary: CircleAvatar(
                                radius: 12,
                                child: Text(
                                  (_caracCounts[name] ?? 0).toString(),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.check),
                        label: const Text('Aplicar'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _EmptyResultHint extends StatelessWidget {
  const _EmptyResultHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 56),
            const SizedBox(height: 10),
            const Text('Sin resultados'),
            const SizedBox(height: 6),
            Text(
              'Ajusta el texto de búsqueda o quita filtros.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogInfoPill extends StatelessWidget {
  final String label;
  final String value;

  const _CatalogInfoPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x1AF1D48B),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x33F1D48B)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontFamily: 'inherit'),
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: Color(0xFFF1D48B),
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogFeaturePill extends StatelessWidget {
  final String label;

  const _CatalogFeaturePill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1A212C),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white10),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CatalogGridCard extends StatelessWidget {
  final CardMyL card;
  final List<String> caracs;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selectionMode;
  final bool selected;

  const _CatalogGridCard({
    required this.card,
    required this.caracs,
    required this.onTap,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            color:
                card.isStub ? const Color(0xFF1A1400) : const Color(0xFF12161D),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color:
                  selected
                      ? const Color(0xFF7DD3FC)
                      : card.isStub
                      ? const Color(0x66F59E0B)
                      : Colors.white10,
              width: selected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.24),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: SizedBox.expand(
                          child: _CatalogCardImage(card: card),
                        ),
                      ),
                      if (card.soloLibre)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A0D2E),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0xFFC084FC),
                                width: 1.2,
                              ),
                            ),
                            child: const Text(
                              'LIBRE',
                              style: TextStyle(
                                color: Color(0xFFC084FC),
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .6,
                              ),
                            ),
                          ),
                        ),
                      if (selectionMode)
                        Positioned(
                          top: card.soloLibre ? 38 : 6,
                          right: 6,
                          child: CircleAvatar(
                            radius: 14,
                            backgroundColor:
                                selected
                                    ? const Color(0xFF7DD3FC)
                                    : const Color(0xCC101820),
                            child: Icon(
                              selected
                                  ? Icons.check_rounded
                                  : Icons.add_rounded,
                              size: 18,
                              color:
                                  selected
                                      ? const Color(0xFF102027)
                                      : Colors.white70,
                            ),
                          ),
                        ),
                      if (card.isStub)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A1A00),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0xFFF59E0B),
                                width: 1.2,
                              ),
                            ),
                            child: const Text(
                              'INCOMPLETA',
                              style: TextStyle(
                                color: Color(0xFFF59E0B),
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .6,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  card.nombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                if (caracs.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 54,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children:
                          caracs
                              .take(4)
                              .map((c) => _CatalogFeaturePill(label: c))
                              .toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogCardImage extends StatelessWidget {
  final CardMyL card;

  const _CatalogCardImage({required this.card});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF0E1117)),
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: 220,
          height: 308,
          child: VariantThumbFromCard(
            cardId: card.id,
            fallbackTipo: card.tipo,
            size: 220,
          ),
        ),
      ),
    );
  }
}

class _RightPanel extends StatelessWidget {
  final List<String> allCaracs;
  final Map<String, int> caracCounts;
  final Set<String> selected;
  final void Function(String name, bool value) onToggle;
  final VoidCallback onClear;

  const _RightPanel({
    Key? key,
    required this.allCaracs,
    required this.caracCounts,
    required this.selected,
    required this.onToggle,
    required this.onClear,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: const Color(0xFF12161D),
        border: const Border(left: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                const Icon(Icons.bolt_outlined, color: Color(0xFFF1D48B)),
                const SizedBox(width: 8),
                const Text(
                  'Qué hace la carta',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.clear_all, color: Color(0xFFF1D48B)),
                  label: const Text(
                    'Limpiar',
                    style: TextStyle(color: Color(0xFFF1D48B)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final name in allCaracs)
                  CheckboxListTile(
                    activeColor: const Color(0xFFF1D48B),
                    checkColor: const Color(0xFF14181F),
                    value: selected.contains(name),
                    onChanged: (v) => onToggle(name, v ?? false),
                    dense: true,
                    title: Text(
                      name,
                      style: const TextStyle(color: Colors.white),
                    ),
                    secondary: CircleAvatar(
                      radius: 12,
                      backgroundColor: const Color(0xFF1A212C),
                      child: Text(
                        (caracCounts[name] ?? 0).toString(),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFF1D48B),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Miniatura de una carta basada en su MEJOR variante disponible:
/// - official == true
/// - luego isBase == true
/// - luego la primera por name
class VariantThumbFromCard extends StatelessWidget {
  final String cardId;
  final String fallbackTipo;
  final double size;
  const VariantThumbFromCard({
    super.key,
    required this.cardId,
    required this.fallbackTipo,
    this.size = 56,
  });

  static String? _safe(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.contains('drive.google.com')) return DriveService.webSafeUrl(url);
    return url;
  }

  // ---- URL desde el doc principal (cards/{id}) ----
  String? _pickFromDoc(Map<String, dynamic> m) {
    for (final key in [
      'officialImageUrl',
      'imageUrl',
      'officialImage',
      'frontUrl',
      'img',
      'url',
    ]) {
      final v = _safe(m[key]?.toString());
      if (v != null) return v;
    }
    final images = m['images'];
    if (images is Map) {
      for (final k in ['front', 'anverso']) {
        final v = _safe(images[k]?.toString());
        if (v != null) return v;
      }
    }
    return null;
  }

  // ---- URL desde una variante (cards/{id}/variants/{vid}) ----
  String? _pickFromVariant(Map<String, dynamic> m) {
    final thumbs = m['thumbs'];
    if (thumbs is Map) {
      for (final k in [
        '56x56',
        '64x64',
        '72x72',
        '80x80',
        '96x96',
        'small',
        'thumb',
        's',
      ]) {
        final v = _safe(thumbs[k]?.toString());
        if (v != null) return v;
      }
      for (final v in thumbs.values) {
        final s = _safe(v?.toString());
        if (s != null) return s;
      }
    }
    for (final key in [
      'thumbUrl',
      'imageFrontThumb',
      'imageFrontUrl',
      'frontUrl',
      'imageUrl',
      'officialImageUrl',
      'officialImage',
      'img',
      'url',
    ]) {
      final v = _safe(m[key]?.toString());
      if (v != null) return v;
    }
    final images = m['images'];
    if (images is Map) {
      for (final k in ['front', 'anverso']) {
        final v = _safe(images[k]?.toString());
        if (v != null) return v;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cardRef = FirebaseFirestore.instance.collection('cards').doc(cardId);

    // 1) Escucha el doc principal: si trae URL, úsala.
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: cardRef.snapshots(),
      builder: (context, docSnap) {
        String? topUrl;
        if (docSnap.hasData && docSnap.data!.data() != null) {
          topUrl = _pickFromDoc(docSnap.data!.data()!);
        }
        if (topUrl != null && topUrl.isNotEmpty) {
          return _CardThumb(
            url: topUrl,
            fallbackTipo: fallbackTipo,
            size: size,
          );
        }

        // 2) Si no hubo URL en el doc, cae a variants.
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream:
              cardRef
                  .collection('variants')
                  .orderBy('official', descending: true)
                  .orderBy('isBase', descending: true)
                  .orderBy('name')
                  .limit(6)
                  .snapshots(),
          builder: (context, varSnap) {
            String? vurl;
            if (varSnap.hasData && varSnap.data!.docs.isNotEmpty) {
              for (final d in varSnap.data!.docs) {
                vurl = _pickFromVariant(d.data());
                if (vurl != null && vurl.isNotEmpty) break;
              }
            }
            return _CardThumb(
              url: vurl,
              fallbackTipo: fallbackTipo,
              size: size,
            );
          },
        );
      },
    );
  }
}

class _CardThumb extends StatelessWidget {
  final String? url;
  final String fallbackTipo;
  final double size;
  const _CardThumb({
    required this.url,
    required this.fallbackTipo,
    this.size = 56,
  });

  Color _colorPorTipo(String t) {
    t = t.toLowerCase();
    if (t == 'aliado') return Colors.teal;
    if (t == 'talismán' || t == 'talisman') return Colors.deepPurple;
    if (t == 'tótem' || t == 'totem') return Colors.orange;
    if (t == 'arma') return Colors.brown;
    if (t == 'oro') return Colors.amber;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    Widget fallback() => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _colorPorTipo(fallbackTipo).withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported, size: 22),
    );

    if (url == null || url!.isEmpty) return fallback();

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: MylNetworkImage(
          imageUrl: url!,
          fit: BoxFit.cover,
          placeholder:
              (_, __) => const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          errorWidget: (_, __, ___) => fallback(),
        ),
      ),
    );
  }
}
