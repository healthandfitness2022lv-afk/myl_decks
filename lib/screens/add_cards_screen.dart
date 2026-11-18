import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../domain/validation/mercenarios.dart';
import '../../models/deck.dart';
import '../../services/card_service.dart';
import '../../utils/text_normalize.dart';
import '../widgets/card_image_preview.dart';
import '../widgets/network_image.dart';

class AddCardsScreen extends StatefulWidget {
  final CardService cardService;
  final String? currentRace;
  final String? currentEdition;
  final bool isLibre;
  final Map<String, int> copyLimitsByCardId;

  const AddCardsScreen({
    super.key,
    required this.cardService,
    required this.currentRace,
    required this.currentEdition,
    this.isLibre = false,
    this.copyLimitsByCardId = const {},
  });

  @override
  State<AddCardsScreen> createState() => _AddCardsScreenState();
}

class _AddCardsScreenState extends State<AddCardsScreen> {
  final _searchCtrl = TextEditingController();
  final _minCostCtrl = TextEditingController();
  final _maxCostCtrl = TextEditingController();

  final Map<String, int> _qty = {};
  final Map<String, _CardRow> _selected = {};

  String? _tipo;
  String? _raza;
  String? _edicion;

  bool _loading = false;
  List<_CardRow> _rows = [];
  List<String> _razas = [];
  List<String> _ediciones = [];
  Timer? _debounce;

  bool get _hasDeckContext =>
      widget.currentRace != null &&
      (widget.isLibre || widget.currentEdition != null);

  @override
  void initState() {
    super.initState();
    _loadFacets();
    _searchCtrl.addListener(_onQueryChanged);
    _fetch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.removeListener(_onQueryChanged);
    _searchCtrl.dispose();
    _minCostCtrl.dispose();
    _maxCostCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFacets() async {
    try {
      final snap =
          await FirebaseFirestore.instance
              .collection('cards')
              .limit(5000)
              .get();
      final razas = <String>{};
      final eds = <String>{};
      for (final d in snap.docs) {
        final data = d.data();
        final r = (data['raza'] ?? '').toString().trim();
        final e = (data['edicion'] ?? '').toString().trim();
        if (r.isNotEmpty) razas.add(r);
        if (e.isNotEmpty) eds.add(e);
      }
      if (mounted) {
        setState(() {
          _razas = razas.toList()..sort();
          _ediciones = eds.toList()..sort();
          _raza ??= widget.currentRace;
          _edicion ??= widget.currentEdition;
        });
      }
    } catch (e) {
      debugPrint('Error loading facets: $e');
    }
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), _fetch);
  }

  Future<void> _ensureSelectedRow(String cardId) async {
    if (_selected.containsKey(cardId)) return;

    final r = _rows.firstWhere(
      (x) => x.id == cardId,
      orElse:
          () => _CardRow(
            id: '',
            nombre: '',
            tipo: '',
            raza: '',
            edicion: '',
            coste: null,
          ),
    );
    if (r.id.isNotEmpty) {
      _selected[cardId] = r;
      return;
    }

    final d =
        await FirebaseFirestore.instance.collection('cards').doc(cardId).get();
    if (!d.exists) return;
    final data = d.data() as Map<String, dynamic>;
    _anotarMercenario(d.id, data);
    _selected[cardId] = _CardRow(
      id: d.id,
      nombre: (data['nombre'] ?? '').toString(),
      tipo: (data['tipo'] ?? '').toString(),
      raza: (data['raza'] ?? '').toString(),
      edicion: (data['edicion'] ?? '').toString(),
      coste:
          (data['tipo']?.toString().toLowerCase() == 'oro')
              ? null
              : _parseIntOrNull(data['coste']),
      thumbUrl: _extractThumb(data),
      soloLibre: (data['soloLibre'] as bool?) ?? false,
    );
  }

  Future<void> _fetch() async {
    if (_hasDeckContext) {
      _raza = widget.currentRace;
      _edicion = widget.currentEdition;
    }

    setState(() => _loading = true);
    try {
      final col = FirebaseFirestore.instance.collection('cards');
      final text = normalizeSearch(_searchCtrl.text);
      final minCost = int.tryParse(_minCostCtrl.text.trim());
      final maxCost = int.tryParse(_maxCostCtrl.text.trim());

      Future<List<_CardRow>> run(Query q) async {
        Query query = q;
        if (text.isNotEmpty) {
          query = query
              .where('nombre_lower', isGreaterThanOrEqualTo: text)
              .where('nombre_lower', isLessThan: '$text\uf8ff');
        }
        query = query.limit(300);
        final snap = await query.get();
        final list = <_CardRow>[];
        for (final d in snap.docs) {
          final data = d.data() as Map<String, dynamic>;
          _anotarMercenario(d.id, data);
          list.add(
            _CardRow(
              id: d.id,
              nombre: (data['nombre'] ?? '').toString(),
              tipo: (data['tipo'] ?? '').toString(),
              raza: (data['raza'] ?? '').toString(),
              edicion: (data['edicion'] ?? '').toString(),
              coste:
                  (data['tipo']?.toString().toLowerCase() == 'oro')
                      ? null
                      : _parseIntOrNull(data['coste']),
              thumbUrl: _extractThumb(data),
              soloLibre: (data['soloLibre'] as bool?) ?? false,
            ),
          );
        }
        return list;
      }

      if (_hasDeckContext) {
        final otherTypes = ['Talism\u00e1n', 'T\u00f3tem', 'Arma'];
        final wantAliado = _tipo == null || _tipo == 'Aliado';
        final wantOro = _tipo == null || _tipo == 'Oro';
        final List<String> wantedOthers =
            _tipo == null
                ? otherTypes
                : (otherTypes.contains(_tipo!) ? <String>[_tipo!] : <String>[]);

        Future<List<_CardRow>> aliadosFut = Future.value(<_CardRow>[]);
        if (wantAliado) {
          Query qa =
              widget.isLibre
                  ? col
                      .where('raza', isEqualTo: _raza)
                      .where('tipo', isEqualTo: 'Aliado')
                  : col
                      .where('edicion', isEqualTo: _edicion)
                      .where('raza', isEqualTo: _raza)
                      .where('tipo', isEqualTo: 'Aliado');
          if (minCost != null) {
            qa = qa.where('coste', isGreaterThanOrEqualTo: minCost);
          }
          if (maxCost != null) {
            qa = qa.where('coste', isLessThanOrEqualTo: maxCost);
          }
          aliadosFut = run(qa);
        }

        Future<List<_CardRow>> oroFut = Future.value(<_CardRow>[]);
        if (wantOro) {
          Query qo =
              widget.isLibre
                  ? col.where('tipo', isEqualTo: 'Oro')
                  : col
                      .where('edicion', isEqualTo: _edicion)
                      .where('tipo', isEqualTo: 'Oro');
          oroFut = run(qo);
        }

        Future<List<_CardRow>> otrosFut = Future.value(<_CardRow>[]);
        if (wantedOthers.isNotEmpty) {
          Query qx =
              widget.isLibre
                  ? col.where('tipo', whereIn: wantedOthers)
                  : col
                      .where('edicion', isEqualTo: _edicion)
                      .where('tipo', whereIn: wantedOthers);
          if (minCost != null) {
            qx = qx.where('coste', isGreaterThanOrEqualTo: minCost);
          }
          if (maxCost != null) {
            qx = qx.where('coste', isLessThanOrEqualTo: maxCost);
          }
          otrosFut = run(qx);
        }

        final lists = await Future.wait([aliadosFut, oroFut, otrosFut]);
        final byId = <String, _CardRow>{};
        for (final list in lists) {
          for (final row in list) {
            byId[row.id] = row;
          }
        }
        final combined =
            byId.values.toList()..sort(
              (a, b) =>
                  a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
            );
        if (mounted) setState(() => _rows = combined);
      } else {
        Query q = col;
        if (_tipo != null && _tipo!.isNotEmpty) {
          q = q.where('tipo', isEqualTo: _tipo);
        }
        if (_raza != null && _raza!.isNotEmpty) {
          q = q.where('raza', isEqualTo: _raza);
        }
        if (_edicion != null && _edicion!.isNotEmpty) {
          q = q.where('edicion', isEqualTo: _edicion);
        }

        if (_tipo == null || _tipo!.toLowerCase() != 'oro') {
          if (minCost != null) {
            q = q.where('coste', isGreaterThanOrEqualTo: minCost);
          }
          if (maxCost != null) {
            q = q.where('coste', isLessThanOrEqualTo: maxCost);
          }
        }

        final fetched = await run(q)
          ..sort(
            (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
          );

        if (mounted) setState(() => _rows = fetched);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int? _parseIntOrNull(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  int _maxCopiesForCardId(String cardId) {
    return limiteDeCopias(
      enBanList: widget.copyLimitsByCardId[cardId.trim().toLowerCase()],
      unica: false,
      mercenario: esMercenario(id: cardId),
    );
  }

  Future<void> _setQty(String cardId, int v) async {
    final maxAllowed = _maxCopiesForCardId(cardId);
    if (v <= 0 || maxAllowed == 0) {
      _qty.remove(cardId);
      _selected.remove(cardId);
    } else {
      _qty[cardId] = v.clamp(1, maxAllowed);
      await _ensureSelectedRow(cardId);
    }
    if (mounted) setState(() {});
  }

  void _clearAll() {
    setState(() {
      _qty.clear();
      _selected.clear();
    });
  }

  void _confirm() {
    final entries = <DeckCardEntry>[];
    for (final entry in _qty.entries) {
      final cardId = entry.key;
      final q = entry.value;
      if (q <= 0) continue;

      final r =
          _selected[cardId] ??
          _rows.firstWhere(
            (x) => x.id == cardId,
            orElse:
                () => _CardRow(
                  id: cardId,
                  nombre: '',
                  tipo: '',
                  raza: '',
                  edicion: '',
                  coste: null,
                ),
          );

      entries.add(
        DeckCardEntry(
          cardId: cardId,
          name: r.nombre,
          count: q,
          tipo: r.tipo,
          coste: r.coste,
          edicion: r.edicion.isEmpty ? null : r.edicion,
          soloLibre: r.soloLibre,
        ),
      );
    }
    Navigator.pop(context, entries);
  }

  List<String> _uniquePreserveOrder(List<String> src) {
    final seen = <String>{};
    final out = <String>[];
    for (final s in src) {
      final key = s.trim().toLowerCase();
      if (seen.add(key)) out.add(s);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final chipContexto =
        _hasDeckContext
            ? const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(spacing: 8, runSpacing: 6),
              ),
            )
            : const SizedBox.shrink();

    final uniqueRazas = _uniquePreserveOrder(_razas);
    if (widget.currentRace != null &&
        widget.currentRace!.isNotEmpty &&
        !uniqueRazas.any((r) => r.trim() == widget.currentRace!.trim())) {
      uniqueRazas.insert(0, widget.currentRace!.trim());
    }

    final uniqueEdiciones = _uniquePreserveOrder(_ediciones);
    if (widget.currentEdition != null &&
        widget.currentEdition!.isNotEmpty &&
        !uniqueEdiciones.any(
          (e) => e.trim() == widget.currentEdition!.trim(),
        )) {
      uniqueEdiciones.insert(0, widget.currentEdition!.trim());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agregar cartas'),
        actions: [
          IconButton(
            tooltip: 'Limpiar cantidades',
            onPressed: _qty.isEmpty ? null : _clearAll,
            icon: const Icon(Icons.clear_all),
          ),
          TextButton.icon(
            onPressed: _qty.isEmpty ? null : _confirm,
            icon: const Icon(Icons.check),
            label: Text('Agregar (${_qty.length})'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          children: [
            chipContexto,
            LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 560;

                const tipoItems = <DropdownMenuItem<String?>>[
                  DropdownMenuItem(value: null, child: Text('-')),
                  DropdownMenuItem(value: 'Aliado', child: Text('Aliado')),
                  DropdownMenuItem(value: 'Oro', child: Text('Oro')),
                  DropdownMenuItem(value: 'Talismán', child: Text('Talismán')),
                  DropdownMenuItem(value: 'Tótem', child: Text('Tótem')),
                  DropdownMenuItem(value: 'Arma', child: Text('Arma')),
                ];

                Widget searchField = TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Buscar por nombre',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                );

                Widget tipoField = DropdownButtonFormField<String?>(
                  value: _tipo,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Tipo',
                    isDense: true,
                  ),
                  items: tipoItems,
                  onChanged: (v) {
                    setState(() => _tipo = v);
                    _fetch();
                  },
                );

                Widget razaField = DropdownButtonFormField<String?>(
                  value: _hasDeckContext ? widget.currentRace : _raza,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Raza',
                    isDense: true,
                  ),
                  items: [
                    if (!_hasDeckContext)
                      const DropdownMenuItem(value: null, child: Text('-')),
                    ...uniqueRazas.map(
                      (r) => DropdownMenuItem(value: r, child: Text(r)),
                    ),
                  ],
                  onChanged:
                      _hasDeckContext
                          ? null
                          : (v) {
                            setState(() => _raza = v);
                            _fetch();
                          },
                );

                Widget? edicionField =
                    !widget.isLibre
                        ? DropdownButtonFormField<String?>(
                          value:
                              _hasDeckContext
                                  ? widget.currentEdition
                                  : _edicion,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Edición',
                            isDense: true,
                          ),
                          items: [
                            if (!_hasDeckContext)
                              const DropdownMenuItem(
                                value: null,
                                child: Text('-'),
                              ),
                            ...uniqueEdiciones.map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)),
                            ),
                          ],
                          onChanged:
                              _hasDeckContext
                                  ? null
                                  : (v) {
                                    setState(() => _edicion = v);
                                    _fetch();
                                  },
                        )
                        : null;

                if (isMobile) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      searchField,
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: tipoField),
                          const SizedBox(width: 8),
                          Expanded(child: razaField),
                          if (edicionField != null) ...[
                            const SizedBox(width: 8),
                            Expanded(child: edicionField),
                          ],
                        ],
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(flex: 2, child: searchField),
                    const SizedBox(width: 8),
                    Expanded(child: tipoField),
                    const SizedBox(width: 8),
                    Expanded(child: razaField),
                    if (edicionField != null) ...[
                      const SizedBox(width: 8),
                      Expanded(child: edicionField),
                    ],
                  ],
                );
              },
            ),
            if (_loading) const LinearProgressIndicator(),
            Expanded(
              child:
                  _rows.isEmpty
                      ? const Center(child: Text('Sin resultados'))
                      : ListView.separated(
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (itemContext, i) {
                          final r = _rows[i];
                          final q = _qty[r.id] ?? 0;
                          final maxCopies = _maxCopiesForCardId(r.id);
                          final blocked = maxCopies == 0;

                          return ListTile(
                            leading:
                                r.thumbUrl != null && r.thumbUrl!.isNotEmpty
                                    ? SizedBox(
                                      width: 44,
                                      height: 64,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: MylNetworkImage(
                                          imageUrl: r.thumbUrl!,
                                          fit: BoxFit.cover,
                                          errorWidget:
                                              (_, __, ___) =>
                                                  _defaultAvatar(r.nombre),
                                          placeholder:
                                              (_, __) => Container(
                                                color: Colors.grey.shade200,
                                                child: const Center(
                                                  child: SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                        ),
                                      ),
                                    )
                                    : _defaultAvatar(r.nombre),
                            title: Text(r.nombre),
                            subtitle: Text(
                              [
                                if (r.edicion.isNotEmpty)
                                  'Edicion: ${r.edicion}',
                                if (r.tipo.isNotEmpty) r.tipo,
                                if (r.raza.isNotEmpty) 'Raza: ${r.raza}',
                                if (r.coste != null) 'Coste ${r.coste}',
                                if (blocked)
                                  'Ban List: prohibida'
                                else if (maxCopies < 3)
                                  'Ban List: limitada a $maxCopies copias',
                              ].join(' · '),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Ampliar carta',
                                  onPressed:
                                      () => showCardImagePreview(
                                        itemContext,
                                        cardName: r.nombre,
                                        imageUrl: r.thumbUrl,
                                      ),
                                  icon: const Icon(Icons.zoom_out_map_rounded),
                                ),
                                _QtyPicker(
                                  value: q,
                                  max: maxCopies,
                                  onChanged:
                                      blocked
                                          ? (_) {}
                                          : (v) => _setQty(r.id, v),
                                ),
                              ],
                            ),
                            onTap:
                                blocked
                                    ? null
                                    : () => _setQty(
                                      r.id,
                                      q == 0 ? 1 : ((q % maxCopies) + 1),
                                    ),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close),
                  label: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _qty.isEmpty ? null : _confirm,
                  icon: const Icon(Icons.check_circle),
                  label: Text('Agregar (${_qty.length})'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _defaultAvatar(String nombre) {
    final init = nombre.trim().isEmpty ? '?' : nombre.trim()[0].toUpperCase();
    return CircleAvatar(
      radius: 22,
      child: Text(init, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  /// Carta Mercenario («Puedes tener más de 3…»): admite hasta 6 copias.
  void _anotarMercenario(String id, Map<String, dynamic> data) {
    if (textoEsMercenario('${data['habilidadTextoIA'] ?? ''} ${data['habilidad'] ?? ''}')) {
      registrarMercenario(id: id, nombre: '${data['nombre'] ?? ''}');
    }
  }

  String? _extractThumb(Map<String, dynamic> data) {
    const candidates = [
      'thumb',
      'imagen',
      'image',
      'imageUrl',
      'img',
      'officialImg',
      'picture',
      'thumbnail',
      'thumbUrl',
    ];
    for (final k in candidates) {
      final v = data[k];
      if (v is String && v.isNotEmpty) return v;
      if (v is Map && v['url'] is String && (v['url'] as String).isNotEmpty) {
        return v['url'] as String;
      }
    }
    return null;
  }
}

class _CardRow {
  final String id;
  final String nombre;
  final String tipo;
  final String raza;
  final String edicion;
  final int? coste;
  final String? thumbUrl;
  final bool soloLibre;

  _CardRow({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.raza,
    required this.edicion,
    required this.coste,
    this.thumbUrl,
    this.soloLibre = false,
  });
}

class _QtyPicker extends StatelessWidget {
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  const _QtyPicker({
    required this.value,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Quitar',
          onPressed: value <= 0 ? null : () => onChanged(value - 1),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 36,
          child: Text(
            value.toString(),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: max == 0 ? 'Prohibida' : 'Agregar',
          onPressed:
              max == 0 || value >= max ? null : () => onChanged(value + 1),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}
