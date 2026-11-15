import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/pb_data.dart';
import '../models/ban_list_entry.dart';
import '../models/card_myl.dart';
import '../models/current_user.dart';
import '../services/ban_list_service.dart';
import '../services/deck_poster_share_service.dart';
import '../services/drive_service.dart';
import '../widgets/drive_image_picker.dart' show showRaceGallery;
import '../utils/wallpaper_image.dart';
import '../widgets/network_image.dart';

part 'ban_list/ban_list_poster_export.dart';

enum BanListScope { racialEdicion, racialLibre, full }

extension BanListScopeLabel on BanListScope {
  String get label => switch (this) {
    BanListScope.racialEdicion => 'Racial Edición',
    BanListScope.racialLibre => 'Racial Libre',
    BanListScope.full => 'Formato Libre',
  };

  String get title => 'Ban List — $label';

  BanListService service() => switch (this) {
    BanListScope.racialEdicion => BanListService(),
    BanListScope.racialLibre => BanListService.racialLibre(),
    BanListScope.full => BanListService.full(),
  };

  String get exportFileName => switch (this) {
    BanListScope.racialEdicion => 'ban_list_racial_edicion',
    BanListScope.racialLibre => 'ban_list_racial_libre',
    BanListScope.full => 'ban_list_full',
  };
}

class BanListScreen extends StatefulWidget {
  const BanListScreen({
    super.key,
    this.initialScope = BanListScope.racialEdicion,
  });

  final BanListScope initialScope;

  @override
  State<BanListScreen> createState() => _BanListScreenState();
}

class _BanListScreenState extends State<BanListScreen> {
  late BanListScope _scope = widget.initialScope;
  late BanListService _service = _scope.service();
  final TextEditingController _searchCtrl = TextEditingController();
  static const Color _bg = Color(0xFF0D1016);
  static const Color _panel = Color(0xFF12161D);
  static const Color _panelAlt = Color(0xFF14181F);
  static const Color _gold = Color(0xFFF1D48B);

  Timer? _debounce;
  bool _loadingSearch = false;
  bool _resyncing = false;
  List<CardMyL> _searchResults = [];

  void _switchList(BanListScope scope) {
    if (_scope == scope) return;
    setState(() {
      _scope = scope;
      _service = scope.service();
      _searchResults = [];
      _searchCtrl.clear();
    });
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _searchCards);
  }

  Future<void> _searchCards() async {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) {
      if (!mounted) return;
      setState(() => _searchResults = []);
      return;
    }

    setState(() => _loadingSearch = true);
    try {
      final snap =
          await FirebaseFirestore.instance
              .collection('cards')
              .orderBy('nombre_lower')
              .startAt([query])
              .endAt(['$query\uf8ff'])
              .limit(40)
              .get();

      final matches =
          snap.docs.map((d) => CardMyL.fromMap(d.data(), d.id)).toList()..sort(
            (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
          );

      if (!mounted) return;
      setState(() => _searchResults = matches);
    } catch (_) {
      if (!mounted) return;
      setState(() => _searchResults = []);
    } finally {
      if (mounted) setState(() => _loadingSearch = false);
    }
  }

  Future<void> _setRestriction(CardMyL card, int maxCopies) async {
    await _service.saveRestriction(card: card, maxCopies: maxCopies);
    if (!mounted) return;
    final label =
        maxCopies == 0
            ? '${card.nombre} ahora está prohibida.'
            : maxCopies >= 3
            ? 'Se eliminó la restricción de ${card.nombre}.'
            : '${card.nombre} quedó limitada a $maxCopies copias.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(label)));
  }

  Future<void> _resync() async {
    setState(() => _resyncing = true);
    try {
      final updated = await _service.resyncWithCards();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            updated == 0
                ? 'La ban list ya estaba al día.'
                : 'Se actualizaron $updated entradas desde el catálogo de cartas.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo resincronizar la ban list.')),
      );
    } finally {
      if (mounted) setState(() => _resyncing = false);
    }
  }

  Future<void> _exportImage(List<BanListEntry> entries) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _BanListPosterDialog(entries: entries, scope: _scope),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<CurrentUser>();
    final isAdmin = currentUser.isAdmin;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _panelAlt,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(_scope.title),
        centerTitle: true,
        actions: [
          if (isAdmin)
            IconButton(
              tooltip: 'Resincronizar con el catálogo de cartas',
              onPressed: _resyncing ? null : _resync,
              icon:
                  _resyncing
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.sync),
            ),
        ],
      ),
      body: StreamBuilder<List<BanListEntry>>(
        key: ValueKey(_scope),
        stream: _service.watchEntries(),
        builder: (context, snap) {
          final entries = snap.data ?? const <BanListEntry>[];
          final byCardId = {
            for (final entry in entries)
              normalizeBanListKey(entry.cardId): entry,
          };
          final groupedEntries = _groupEntries(entries);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _ListSwitcher(scope: _scope, onChanged: _switchList),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed:
                        entries.isEmpty ? null : () => _exportImage(entries),
                    icon: const Icon(Icons.image_outlined, size: 18),
                    label: const Text('Exportar imagen'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _gold,
                      side: const BorderSide(color: Color(0x66F1D48B)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (isAdmin) ...[
                _SearchCard(
                  controller: _searchCtrl,
                  isAdmin: isAdmin,
                  loading: _loadingSearch,
                  results: _searchResults,
                  byCardId: byCardId,
                  onSelectRestriction: _setRestriction,
                ),
                const SizedBox(height: 20),
              ],
              if (entries.isEmpty)
                _EmptyStateCard(
                  icon: Icons.shield_outlined,
                  title: 'No hay restricciones activas',
                  subtitle:
                      isAdmin
                          ? 'Busca una carta arriba para marcarla como prohibida o limitada.'
                          : 'Cuando haya cambios en la ban list, aparecerán aquí.',
                )
              else
                ...groupedEntries.entries.map(
                  (copiesGroup) => Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: _CopiesTableSection(
                      maxCopies: copiesGroup.key,
                      groupedByEdition: copiesGroup.value,
                      isAdmin: isAdmin,
                      onSelected: (entry, value) async {
                        if (value == 4) {
                          await _service.removeRestriction(entry.cardId);
                          return;
                        }

                        final card = CardMyL(
                          id: entry.cardId,
                          nombre: entry.cardName,
                          tipo: entry.cardType ?? '',
                          coste: entry.coste,
                          rareza: '',
                          edicion: entry.edition ?? '',
                          habilidad: '',
                          raza: entry.race,
                          soloLibre: entry.soloLibre,
                        );
                        await _setRestriction(card, value);
                      },
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Map<int, Map<String, List<BanListEntry>>> _groupEntries(
    List<BanListEntry> entries,
  ) {
    final grouped = <int, Map<String, List<BanListEntry>>>{};

    final sortedEntries = [...entries]..sort((a, b) {
      final copiesCompare = a.maxCopies.compareTo(b.maxCopies);
      if (copiesCompare != 0) return copiesCompare;
      final editionCompare = a.editionGroupLabel.compareTo(b.editionGroupLabel);
      if (editionCompare != 0) return editionCompare;
      return a.cardName.toLowerCase().compareTo(b.cardName.toLowerCase());
    });

    for (final entry in sortedEntries) {
      final edition = entry.editionGroupLabel;
      grouped.putIfAbsent(
        entry.maxCopies,
        () => <String, List<BanListEntry>>{},
      );
      grouped[entry.maxCopies]!.putIfAbsent(edition, () => <BanListEntry>[]);
      grouped[entry.maxCopies]![edition]!.add(entry);
    }

    return grouped;
  }
}

class _ListSwitcher extends StatelessWidget {
  final BanListScope scope;
  final ValueChanged<BanListScope> onChanged;

  const _ListSwitcher({required this.scope, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<BanListScope>(
      segments: const [
        ButtonSegment(
          value: BanListScope.racialEdicion,
          label: Text('Racial Edición'),
          icon: Icon(Icons.shield_outlined),
        ),
        ButtonSegment(
          value: BanListScope.racialLibre,
          label: Text('Racial Libre'),
          icon: Icon(Icons.public_outlined),
        ),
        ButtonSegment(
          value: BanListScope.full,
          label: Text('Formato Libre'),
          icon: Icon(Icons.all_inclusive_rounded),
        ),
      ],
      selected: {scope},
      onSelectionChanged: (s) => onChanged(s.first),
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0x33F1D48B);
          }
          return _BanListScreenState._panelAlt;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return _BanListScreenState._gold;
          }
          return Colors.white70;
        }),
        side: const WidgetStatePropertyAll(BorderSide(color: Colors.white12)),
      ),
    );
  }
}

class _SearchCard extends StatelessWidget {
  final TextEditingController controller;
  final bool isAdmin;
  final bool loading;
  final List<CardMyL> results;
  final Map<String, BanListEntry> byCardId;
  final Future<void> Function(CardMyL card, int maxCopies) onSelectRestriction;

  const _SearchCard({
    required this.controller,
    required this.isAdmin,
    required this.loading,
    required this.results,
    required this.byCardId,
    required this.onSelectRestriction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      elevation: 0,
      color: _BanListScreenState._panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isAdmin ? 'Buscar y editar restricciones' : 'Buscar cartas',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (!isAdmin)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x1AF1D48B),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0x33F1D48B)),
                    ),
                    child: Text(
                      'Solo lectura',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: _BanListScreenState._gold,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isAdmin
                  ? 'Busca una carta y define si queda prohibida, limitada a 1, limitada a 2 o sin límite.'
                  : 'Puedes consultar cartas, pero solo un administrador puede cambiar la ban list.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              enabled: isAdmin,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Escribe el nombre de la carta',
                hintStyle: const TextStyle(color: Colors.white54),
                prefixIcon: const Icon(Icons.search),
                suffixIcon:
                    loading
                        ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                        : controller.text.isNotEmpty
                        ? IconButton(
                          onPressed: () => controller.clear(),
                          icon: const Icon(Icons.close, color: Colors.white70),
                        )
                        : null,
                filled: true,
                fillColor: _BanListScreenState._panelAlt,
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
                  borderSide: const BorderSide(
                    color: _BanListScreenState._gold,
                  ),
                ),
              ),
            ),
            if (isAdmin && results.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Resultados',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              ...results.map((card) {
                final existing = byCardId[normalizeBanListKey(card.id)];
                final selectedValue = existing?.maxCopies ?? 3;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _SearchResultTile(
                    card: card,
                    selectedValue: selectedValue,
                    onChanged: (value) {
                      if (value == null) return;
                      onSelectRestriction(card, value);
                    },
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final CardMyL card;
  final int selectedValue;
  final ValueChanged<int?> onChanged;

  const _SearchResultTile({
    required this.card,
    required this.selectedValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _BanListScreenState._panelAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0x1AF1D48B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.style_outlined,
              color: _BanListScreenState._gold,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card.nombre,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (card.tipo.isNotEmpty) card.tipo,
                    if (card.edicion.isNotEmpty) card.edicion,
                    if ((card.raza ?? '').isNotEmpty) card.raza!,
                  ].join(' • '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          DropdownButton<int>(
            value: selectedValue,
            underline: const SizedBox.shrink(),
            borderRadius: BorderRadius.circular(16),
            dropdownColor: _BanListScreenState._panelAlt,
            style: const TextStyle(color: Colors.white),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Prohibida')),
              DropdownMenuItem(value: 1, child: Text('x1')),
              DropdownMenuItem(value: 2, child: Text('x2')),
              DropdownMenuItem(value: 3, child: Text('Sin limite')),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _RestrictionCard extends StatelessWidget {
  final BanListEntry entry;
  final bool isAdmin;
  final ValueChanged<int> onSelected;

  const _RestrictionCard({
    required this.entry,
    required this.isAdmin,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = entry.isBanned ? Colors.redAccent : cs.primary;

    return Card(
      elevation: 0,
      color: _BanListScreenState._panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color:
                      entry.isBanned
                          ? Colors.redAccent.withOpacity(0.35)
                          : const Color(0x33F1D48B),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                entry.isBanned ? '0' : '${entry.maxCopies}',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.cardName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      _StatusBadge(label: entry.statusLabel, color: accent),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if ((entry.cardType ?? '').isNotEmpty)
                        _MetaChip(label: entry.cardType!),
                      if ((entry.edition ?? '').isNotEmpty)
                        _MetaChip(label: entry.edition!),
                      if ((entry.race ?? '').isNotEmpty)
                        _MetaChip(label: entry.race!),
                    ],
                  ),
                ],
              ),
            ),
            if (isAdmin) ...[
              const SizedBox(width: 12),
              PopupMenuButton<int>(
                tooltip: 'Editar restriccion',
                color: _BanListScreenState._panelAlt,
                iconColor: Colors.white70,
                onSelected: onSelected,
                itemBuilder:
                    (_) => const [
                      PopupMenuItem(value: 0, child: Text('Prohibir')),
                      PopupMenuItem(value: 1, child: Text('Limitar a 1')),
                      PopupMenuItem(value: 2, child: Text('Limitar a 2')),
                      PopupMenuItem(
                        value: 4,
                        child: Text('Quitar restriccion'),
                      ),
                    ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CopiesTableSection extends StatelessWidget {
  final int maxCopies;
  final Map<String, List<BanListEntry>> groupedByEdition;
  final bool isAdmin;
  final Future<void> Function(BanListEntry entry, int value) onSelected;

  const _CopiesTableSection({
    required this.maxCopies,
    required this.groupedByEdition,
    required this.isAdmin,
    required this.onSelected,
  });

  String get _title {
    if (maxCopies <= 0) return 'Cartas prohibidas';
    return 'Cartas limitadas a $maxCopies ${maxCopies == 1 ? 'copia' : 'copias'}';
  }

  String get _subtitle {
    if (maxCopies <= 0)
      return 'Estas cartas no pueden usarse en la construccion de tu mazo.';
    return 'Solo puedes tener hasta $maxCopies ${maxCopies == 1 ? 'copia' : 'copias'} de esta carta en tu mazo.';
  }

  @override
  Widget build(BuildContext context) {
    final editions = groupedByEdition.keys.toList()..sort();
    final maxRows = editions.fold<int>(
      0,
      (current, edition) =>
          groupedByEdition[edition]!.length > current
              ? groupedByEdition[edition]!.length
              : current,
    );

    return Container(
      decoration: BoxDecoration(
        color: _BanListScreenState._panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _subtitle,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: editions.length * 250),
                child: Column(
                  children: [
                    Row(
                      children: [
                        for (final edition in editions)
                          _TableHeaderCell(
                            title: edition,
                            count: groupedByEdition[edition]!.length,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    for (var rowIndex = 0; rowIndex < maxRows; rowIndex++)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final edition in editions)
                            _TableCardCell(
                              entry:
                                  rowIndex < groupedByEdition[edition]!.length
                                      ? groupedByEdition[edition]![rowIndex]
                                      : null,
                              isAdmin: isAdmin,
                              onSelected: onSelected,
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TableHeaderCell extends StatelessWidget {
  final String title;
  final int count;

  const _TableHeaderCell({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 250,
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white24, width: 2)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '$count',
                style: const TextStyle(
                  color: _BanListScreenState._gold,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TableCardCell extends StatelessWidget {
  final BanListEntry? entry;
  final bool isAdmin;
  final Future<void> Function(BanListEntry entry, int value) onSelected;

  const _TableCardCell({
    required this.entry,
    required this.isAdmin,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (entry == null) {
      return const SizedBox(
        width: 250,
        child: Padding(
          padding: EdgeInsets.only(right: 12, bottom: 12),
          child: SizedBox(height: 116),
        ),
      );
    }

    return SizedBox(
      width: 250,
      child: Padding(
        padding: const EdgeInsets.only(right: 12, bottom: 12),
        child: _RestrictionListRow(
          entry: entry!,
          isAdmin: isAdmin,
          onSelected: (value) => onSelected(entry!, value),
          compact: true,
        ),
      ),
    );
  }
}

class _RestrictionListRow extends StatelessWidget {
  final BanListEntry entry;
  final bool isAdmin;
  final Future<void> Function(int value) onSelected;
  final bool compact;

  const _RestrictionListRow({
    required this.entry,
    required this.isAdmin,
    required this.onSelected,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _BanListScreenState._panelAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BanCardThumb(entry: entry),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.cardName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: compact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!compact) _MetaChip(label: entry.statusLabel),
                    if ((entry.cardType ?? '').isNotEmpty)
                      _MetaChip(label: entry.cardType!),
                    if ((entry.race ?? '').isNotEmpty)
                      _MetaChip(label: entry.race!),
                  ],
                ),
              ],
            ),
          ),
          if (isAdmin)
            PopupMenuButton<int>(
              tooltip: 'Editar restriccion',
              color: _BanListScreenState._panelAlt,
              iconColor: Colors.white70,
              onSelected: onSelected,
              itemBuilder:
                  (_) => const [
                    PopupMenuItem(value: 0, child: Text('Prohibir')),
                    PopupMenuItem(value: 1, child: Text('Limitar a 1')),
                    PopupMenuItem(value: 2, child: Text('Limitar a 2')),
                    PopupMenuItem(value: 4, child: Text('Quitar restriccion')),
                  ],
            ),
        ],
      ),
    );
  }
}

String? _safeCardImageUrl(String? url) {
  if (url == null || url.trim().isEmpty) return null;
  final clean = url.trim();
  if (clean.contains('drive.google.com')) return DriveService.webSafeUrl(clean);
  return clean;
}

String? _pickImageFromCardDoc(Map<String, dynamic> m) {
  for (final key in [
    'officialImageUrl',
    'imageUrl',
    'officialImage',
    'frontUrl',
    'img',
    'url',
  ]) {
    final v = _safeCardImageUrl(m[key]?.toString());
    if (v != null && v.isNotEmpty) return v;
  }
  final images = m['images'];
  if (images is Map) {
    for (final k in ['front', 'anverso']) {
      final v = _safeCardImageUrl(images[k]?.toString());
      if (v != null && v.isNotEmpty) return v;
    }
  }
  return null;
}

String? _pickImageFromVariantDoc(Map<String, dynamic> m) {
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
      final v = _safeCardImageUrl(thumbs[k]?.toString());
      if (v != null && v.isNotEmpty) return v;
    }
    for (final v in thumbs.values) {
      final s = _safeCardImageUrl(v?.toString());
      if (s != null && s.isNotEmpty) return s;
    }
  }
  for (final key in [
    'thumbUrl',
    'imageFrontUrl',
    'frontUrl',
    'imageUrl',
    'officialImageUrl',
    'officialImage',
    'img',
    'url',
  ]) {
    final v = _safeCardImageUrl(m[key]?.toString());
    if (v != null && v.isNotEmpty) return v;
  }
  return null;
}

/// Resuelve la imagen de una entrada de ban list. Las entradas nunca guardan
/// `imageUrl` directamente (se restringe una carta desde su ficha del
/// catálogo, sin pasar la URL), así que hay que ir a buscarla al doc de
/// `cards/{cardId}` y, si no está ahí, a sus variantes — igual que el resto
/// de la app resuelve imágenes de carta.
Future<String?> resolveBanEntryImageUrl(BanListEntry entry) async {
  if (entry.imageUrl != null && entry.imageUrl!.isNotEmpty)
    return entry.imageUrl;
  if (entry.cardId.trim().isEmpty) return null;
  final cardRef = FirebaseFirestore.instance
      .collection('cards')
      .doc(entry.cardId);
  final doc = await cardRef.get();
  if (doc.data() != null) {
    final url = _pickImageFromCardDoc(doc.data()!);
    if (url != null && url.isNotEmpty) return url;
  }
  final varSnap =
      await cardRef
          .collection('variants')
          .orderBy('official', descending: true)
          .orderBy('isBase', descending: true)
          .limit(4)
          .get();
  for (final d in varSnap.docs) {
    final url = _pickImageFromVariantDoc(d.data());
    if (url != null && url.isNotEmpty) return url;
  }
  return null;
}

class _BanCardThumb extends StatelessWidget {
  final BanListEntry entry;

  const _BanCardThumb({required this.entry});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: resolveBanEntryImageUrl(entry),
      builder:
          (context, snap) => _BanThumbImage(
            url: snap.data,
            fallbackType: entry.cardType ?? '',
          ),
    );
  }
}

class _BanThumbImage extends StatelessWidget {
  final String? url;
  final String fallbackType;

  const _BanThumbImage({required this.url, required this.fallbackType});

  Color _colorByType(String t) {
    t = t.toLowerCase();
    if (t == 'aliado') return Colors.teal;
    if (t == 'talisman' || t == 'talismán') return Colors.deepPurple;
    if (t == 'totem' || t == 'tótem') return Colors.orange;
    if (t == 'arma') return Colors.brown;
    if (t == 'oro') return Colors.amber;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    Widget fallback() => Container(
      width: 54,
      height: 72,
      decoration: BoxDecoration(
        color: _colorByType(fallbackType).withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported, color: Colors.white70),
    );

    if (url == null || url!.isEmpty) return fallback();

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 54,
        height: 72,
        child: MylNetworkImage(
          imageUrl: url!,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => fallback(),
          placeholder:
              (_, __) => Container(
                color: Colors.black26,
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
        ),
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyStateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      elevation: 0,
      color: _BanListScreenState._panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0x1AF1D48B),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: _BanListScreenState._gold, size: 30),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white70,
                height: 1.35,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;

  const _MetaChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2430),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white10),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
