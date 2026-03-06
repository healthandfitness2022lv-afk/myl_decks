import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/deck.dart';
import '../../services/card_service.dart';

class AddCardsScreen extends StatefulWidget {
  final CardService cardService;
  final String? currentRace;
  final String? currentEdition;

  const AddCardsScreen({
    super.key,
    required this.cardService,
    required this.currentRace,
    required this.currentEdition,
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

  bool get _hasDeckContext => (widget.currentRace != null && widget.currentEdition != null);

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
      final snap = await FirebaseFirestore.instance.collection('cards').limit(5000).get();
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

    final r = _rows.firstWhere((x) => x.id == cardId, orElse: () => _CardRow(id: '', nombre: '', tipo: '', raza: '', edicion: '', coste: null));
    if (r.id.isNotEmpty) {
      _selected[cardId] = r;
      return;
    }

    final d = await FirebaseFirestore.instance.collection('cards').doc(cardId).get();
    if (!d.exists) return;
    final data = d.data() as Map<String, dynamic>;
    final nueva = _CardRow(
      id: d.id,
      nombre: (data['nombre'] ?? '').toString(),
      tipo: (data['tipo'] ?? '').toString(),
      raza: (data['raza'] ?? '').toString(),
      edicion: (data['edicion'] ?? '').toString(),
      coste: (data['tipo']?.toString().toLowerCase() == 'oro') ? null : _parseIntOrNull(data['coste']),
      thumbUrl: _extractThumb(data),
    );
    _selected[cardId] = nueva;
  }

  Future<void> _fetch() async {
    if (_hasDeckContext) {
      _raza = widget.currentRace;
      _edicion = widget.currentEdition;
    }

    setState(() => _loading = true);
    try {
      final col = FirebaseFirestore.instance.collection('cards');
      final text = _searchCtrl.text.trim().toLowerCase();
      final minCost = int.tryParse(_minCostCtrl.text.trim());
      final maxCost = int.tryParse(_maxCostCtrl.text.trim());

      Future<List<_CardRow>> run(Query q) async {
        q = q.orderBy('nombre_lower');
        q = q.limit(80);
        final snap = await q.get();
        final list = <_CardRow>[];
        for (final d in snap.docs) {
          final data = d.data() as Map<String, dynamic>;
          final nombreLower = (data['nombre_lower'] ?? (data['nombre'] ?? '')).toString().toLowerCase();
          if (text.isNotEmpty && !nombreLower.contains(text)) continue;
          final row = _CardRow(
            id: d.id,
            nombre: (data['nombre'] ?? '').toString(),
            tipo: (data['tipo'] ?? '').toString(),
            raza: (data['raza'] ?? '').toString(),
            edicion: (data['edicion'] ?? '').toString(),
            coste: (data['tipo']?.toString().toLowerCase() == 'oro') ? null : _parseIntOrNull(data['coste']),
            thumbUrl: _extractThumb(data),
          );
          list.add(row);
        }
        return list;
      }

      if (_hasDeckContext) {
        final otherTypes = ['Talismán', 'Tótem', 'Arma'];
        final wantAliado = (_tipo == null || _tipo == 'Aliado');
        final wantOro = (_tipo == null || _tipo == 'Oro');
        final List<String> wantedOthers = (_tipo == null) ? otherTypes : (otherTypes.contains(_tipo!) ? <String>[_tipo!] : <String>[]);

        Future<List<_CardRow>> aliadosFut = Future.value(<_CardRow>[]);
        if (wantAliado) {
          Query qa = col.where('edicion', isEqualTo: _edicion).where('raza', isEqualTo: _raza).where('tipo', isEqualTo: 'Aliado');
          if (minCost != null) qa = qa.where('coste', isGreaterThanOrEqualTo: minCost);
          if (maxCost != null) qa = qa.where('coste', isLessThanOrEqualTo: maxCost);
          aliadosFut = run(qa);
        }

        Future<List<_CardRow>> oroFut = Future.value(<_CardRow>[]);
        if (wantOro) {
          Query qo = col.where('edicion', isEqualTo: _edicion).where('tipo', isEqualTo: 'Oro');
          oroFut = run(qo);
        }

        Future<List<_CardRow>> otrosFut = Future.value(<_CardRow>[]);
        if (wantedOthers.isNotEmpty) {
          Query qx = col.where('edicion', isEqualTo: _edicion).where('tipo', whereIn: wantedOthers);
          if (minCost != null) qx = qx.where('coste', isGreaterThanOrEqualTo: minCost);
          if (maxCost != null) qx = qx.where('coste', isLessThanOrEqualTo: maxCost);
          otrosFut = run(qx);
        }

        final lists = await Future.wait([aliadosFut, oroFut, otrosFut]);
        final Map<String, _CardRow> byId = {};
        for (final l in lists) {
          for (final r in l) {
            byId[r.id] = r;
          }
        }
        final combined = byId.values.toList()..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
        if (mounted) setState(() => _rows = combined);
      } else {
        Query q = col;
        if (_tipo != null && _tipo!.isNotEmpty) q = q.where('tipo', isEqualTo: _tipo);
        if (_raza != null && _raza!.isNotEmpty) q = q.where('raza', isEqualTo: _raza);
        if (_edicion != null && _edicion!.isNotEmpty) q = q.where('edicion', isEqualTo: _edicion);

        if ((_tipo == null || _tipo!.toLowerCase() != 'oro')) {
          if (minCost != null) q = q.where('coste', isGreaterThanOrEqualTo: minCost);
          if (maxCost != null) q = q.where('coste', isLessThanOrEqualTo: maxCost);
        }

        final fetched = await run(q);
        fetched.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));

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

  Future<void> _setQty(String cardId, int v) async {
    if (v <= 0) {
      _qty.remove(cardId);
      _selected.remove(cardId);
    } else {
      _qty[cardId] = v.clamp(1, 3);
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

      final r = _selected[cardId] ??
          _rows.firstWhere(
            (x) => x.id == cardId,
            orElse: () => _CardRow(id: cardId, nombre: '', tipo: '', raza: '', edicion: '', coste: null),
          );

      entries.add(DeckCardEntry(
        cardId: cardId,
        name: r.nombre,
        count: q,
        tipo: r.tipo,
        coste: r.coste,
      ));
    }
    Navigator.pop(context, entries);
  }

  // Helper para deduplicar preservando orden (case-insensitive)
  List<String> _uniquePreserveOrder(List<String> src) {
    final seen = <String>{};
    final out = <String>[];
    for (final s in src) {
      final key = s.trim().toLowerCase();
      if (!seen.contains(key)) {
        seen.add(key);
        out.add(s);
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final chipContexto = _hasDeckContext
        ? Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Align(alignment: Alignment.centerLeft, child: Wrap(spacing: 8, runSpacing: 6)),
          )
        : const SizedBox.shrink();

    // build listas únicas y aseguro que el valor seleccionado esté presente
    final uniqueRazas = _uniquePreserveOrder(_razas);
    if (widget.currentRace != null && widget.currentRace!.isNotEmpty && !uniqueRazas.any((r) => r.trim() == widget.currentRace!.trim())) {
      uniqueRazas.insert(0, widget.currentRace!.trim());
    }
    final uniqueEdiciones = _uniquePreserveOrder(_ediciones);
    if (widget.currentEdition != null && widget.currentEdition!.isNotEmpty && !uniqueEdiciones.any((e) => e.trim() == widget.currentEdition!.trim())) {
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
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(labelText: 'Buscar por nombre', prefixIcon: Icon(Icons.search)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    value: _tipo,
                    decoration: const InputDecoration(labelText: 'Tipo'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('-')),
                      DropdownMenuItem(value: 'Aliado', child: Text('Aliado')),
                      DropdownMenuItem(value: 'Oro', child: Text('Oro')),
                      DropdownMenuItem(value: 'Talismán', child: Text('Talismán')),
                      DropdownMenuItem(value: 'Tótem', child: Text('Tótem')),
                      DropdownMenuItem(value: 'Arma', child: Text('Arma')),
                    ],
                    onChanged: (v) {
                      setState(() => _tipo = v);
                      _fetch();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    value: _hasDeckContext ? widget.currentRace : _raza,
                    decoration: const InputDecoration(labelText: 'Raza'),
                    items: [
                      if (!_hasDeckContext) const DropdownMenuItem(value: null, child: Text('-')),
                      ...uniqueRazas.map((r) => DropdownMenuItem(value: r, child: Text(r))),
                    ],
                    onChanged: _hasDeckContext
                        ? null
                        : (v) {
                            setState(() => _raza = v);
                            _fetch();
                          },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    value: _hasDeckContext ? widget.currentEdition : _edicion,
                    decoration: const InputDecoration(labelText: 'Edición'),
                    items: [
                      if (!_hasDeckContext) const DropdownMenuItem(value: null, child: Text('-')),
                      ...uniqueEdiciones.map((e) => DropdownMenuItem(value: e, child: Text(e))),
                    ],
                    onChanged: _hasDeckContext
                        ? null
                        : (v) {
                            setState(() => _edicion = v);
                            _fetch();
                          },
                  ),
                ),
              ],
            ),
            if (_loading) const LinearProgressIndicator(),
            Expanded(
              child: _rows.isEmpty
                  ? const Center(child: Text('Sin resultados'))
                  : ListView.separated(
                      itemCount: _rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final r = _rows[i];
                        final q = _qty[r.id] ?? 0;
                        return ListTile(
                          leading: r.thumbUrl != null && r.thumbUrl!.isNotEmpty
                              ? SizedBox(
                                  width: 44,
                                  height: 64,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.network(
                                      r.thumbUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => _defaultAvatar(r.nombre),
                                      loadingBuilder: (ctx, child, progress) {
                                        if (progress == null) return child;
                                        return Container(
                                          color: Colors.grey.shade200,
                                          child: const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                                        );
                                      },
                                    ),
                                  ),
                                )
                              : _defaultAvatar(r.nombre),
                          title: Text(r.nombre),
                          subtitle: Text([
                            if (r.edicion.isNotEmpty) 'Edición: ${r.edicion}',
                            if (r.tipo.isNotEmpty) r.tipo,
                            if (r.raza.isNotEmpty) 'Raza: ${r.raza}',
                            if (r.coste != null) 'Coste ${r.coste}',
                          ].join(' · ')),
                          trailing: _QtyPicker(value: q, onChanged: (v) => _setQty(r.id, v)),
                          onTap: () => _setQty(r.id, (q == 0 ? 1 : (q % 3) + 1)),
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
              Expanded(child: OutlinedButton.icon(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.close), label: const Text('Cancelar'))),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton.icon(onPressed: _qty.isEmpty ? null : _confirm, icon: const Icon(Icons.check_circle), label: Text('Agregar (${_qty.length})'))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _defaultAvatar(String nombre) {
    final init = (nombre.trim().isEmpty ? '?' : nombre.trim()[0].toUpperCase());
    return CircleAvatar(radius: 22, child: Text(init, style: const TextStyle(fontWeight: FontWeight.bold)));
  }

  String? _extractThumb(Map<String, dynamic> data) {
    final candidates = ['thumb', 'imagen', 'image', 'imageUrl', 'img', 'officialImg', 'picture', 'thumbnail', 'thumbUrl'];
    for (final k in candidates) {
      final v = data[k];
      if (v is String && v.isNotEmpty) return v;
      if (v is Map && v['url'] is String && (v['url'] as String).isNotEmpty) return v['url'] as String;
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

  _CardRow({required this.id, required this.nombre, required this.tipo, required this.raza, required this.edicion, required this.coste, this.thumbUrl});
}

class _QtyPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _QtyPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(tooltip: 'Quitar', onPressed: value <= 0 ? null : () => onChanged(value - 1), icon: const Icon(Icons.remove_circle_outline)),
      SizedBox(width: 36, child: Text(value.toString(), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))),
      IconButton(tooltip: 'Agregar', onPressed: value >= 3 ? null : () => onChanged(value + 1), icon: const Icon(Icons.add_circle_outline)),
    ]);
  }
}
