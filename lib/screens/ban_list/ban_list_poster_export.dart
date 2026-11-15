part of '../ban_list_screen.dart';

// Póster exportable de la ban list: mismo mecanismo de fondo elegido de
// Drive que usa el póster de mazos (deck_details/poster_export.dart), pero
// con su propio layout — secciones por nivel de restricción (Prohibidas /
// Limitadas a 1 / Limitadas a 2), cada una ordenada por edición, ajustando
// el tamaño de carta automáticamente para que todo quepa en una sola hoja.

const Map<String, Color> _banPosterTypeColors = {
  'aliado': Color(0xFF4FA8E0),
  'oro': Color(0xFFD9A323),
  'talisman': Color(0xFF9B6BD9),
  'totem': Color(0xFF3FB77E),
  'arma': Color(0xFFE05C5C),
  'descendiente': Color(0xFFE0894F),
};
const Color _banPosterTypeFallback = Color(0xFFD9A323);

/// Proporción ancho/alto del PNG. Con pocas cartas evita una hoja demasiado
/// vacía; con muchas agrega alto real al archivo para conservar legibilidad.
double _banPosterAspectForCount(int count) {
  if (count <= 8) return 4 / 5;
  if (count <= 18) return 3 / 4;
  if (count <= 32) return 2 / 3;
  return 9 / 16;
}

// Orden cronológico real de ediciones (no alfabético): el mismo orden en que
// están declaradas en PBData.edicionToExpansion. Ediciones fuera de ese mapa
// (Racial Libre, Sin edicion) quedan al final, ordenadas entre sí por nombre.
int _compareEditions(String a, String b) {
  final order = PBData.edicionToExpansion.keys.toList();
  final ia = order.indexOf(a);
  final ib = order.indexOf(b);
  if (ia != -1 && ib != -1) return ia.compareTo(ib);
  if (ia != -1) return -1;
  if (ib != -1) return 1;
  return a.compareTo(b);
}

class _BanListPosterDialog extends StatefulWidget {
  final List<BanListEntry> entries;
  final BanListScope scope;

  const _BanListPosterDialog({required this.entries, required this.scope});

  @override
  State<_BanListPosterDialog> createState() => _BanListPosterDialogState();
}

class _BanListPosterDialogState extends State<_BanListPosterDialog> {
  final GlobalKey _previewKey = GlobalKey();
  String? _selectedBackground;
  bool _busy = false;
  double _cardScale = 1.0;
  List<DriveFile> _raceFolders = [];
  bool _loadingFolders = true;
  String? _foldersError;
  final _random = math.Random();
  // cardId → URL resuelta (ban list no guarda imageUrl al restringir una
  // carta, así que se resuelve una vez al abrir el diálogo para precachear
  // y para saber qué hay que esperar antes de capturar el póster).
  Future<List<String>>? _resolvedUrls;

  @override
  void initState() {
    super.initState();
    _loadRaceFolders();
    _resolvedUrls = _resolveAllUrls();
  }

  Future<List<String>> _resolveAllUrls() async {
    final urls = await Future.wait(widget.entries.map(resolveBanEntryImageUrl));
    return urls.whereType<String>().where((u) => u.isNotEmpty).toSet().toList();
  }

  Future<void> _loadRaceFolders() async {
    setState(() {
      _loadingFolders = true;
      _foldersError = null;
    });
    try {
      final items = await DriveService.listFolder(
        DriveService.wallpaperRootFolderId,
      );
      if (!mounted) return;
      setState(() => _raceFolders = items.where((f) => f.isFolder).toList());
      if (_selectedBackground == null && _raceFolders.isNotEmpty) {
        unawaited(_pickRandomBackground());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _foldersError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingFolders = false);
    }
  }

  Future<void> _pickRandomBackground() async {
    if (_raceFolders.isEmpty) return;
    final folder = _raceFolders[_random.nextInt(_raceFolders.length)];
    try {
      final images = await DriveService.listFolder(folder.id);
      final onlyImages = images.where((f) => f.isImage).toList();
      if (onlyImages.isEmpty || !mounted) return;
      final file = onlyImages[_random.nextInt(onlyImages.length)];
      await precacheImage(wallpaperImageProvider(file.viewUrl), context);
      if (!mounted) return;
      setState(() => _selectedBackground = file.viewUrl);
    } catch (_) {
      // Sin conexión o carpeta vacía: se deja que el usuario elija a mano.
    }
  }

  Future<void> _openRaceGallery(DriveFile folder) async {
    final result = await showRaceGallery(context, folder: folder);
    if (result == null || !mounted) return;
    await precacheImage(wallpaperImageProvider(result.viewUrl), context);
    if (!mounted) return;
    setState(() => _selectedBackground = result.viewUrl);
  }

  Map<int, Map<String, List<BanListEntry>>> _grouped() {
    final grouped = <int, Map<String, List<BanListEntry>>>{};
    // Solo restricciones reales — "sin límite" (maxCopies>=3) no aplica acá.
    final restricted =
        widget.entries.where((e) => e.maxCopies < 3).toList()..sort((a, b) {
          final c = a.maxCopies.compareTo(b.maxCopies);
          if (c != 0) return c;
          final ed = a.editionGroupLabel.compareTo(b.editionGroupLabel);
          if (ed != 0) return ed;
          return a.cardName.toLowerCase().compareTo(b.cardName.toLowerCase());
        });
    for (final entry in restricted) {
      grouped.putIfAbsent(
        entry.maxCopies,
        () => <String, List<BanListEntry>>{},
      );
      grouped[entry.maxCopies]!
          .putIfAbsent(entry.editionGroupLabel, () => <BanListEntry>[])
          .add(entry);
    }
    return grouped;
  }

  int get _restrictedCount =>
      widget.entries.where((entry) => entry.maxCopies < 3).length;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bg = _selectedBackground;
    if (bg != null) precacheImage(wallpaperImageProvider(bg), context);
    _resolvedUrls?.then((urls) {
      if (!mounted) return;
      for (final url in urls) {
        precacheImage(NetworkImage(url), context);
      }
    });
  }

  Future<void> _handleExport() async {
    if (_busy) return;
    if (_selectedBackground == null) {
      await _pickRandomBackground();
      if (_selectedBackground == null) return;
    }

    setState(() => _busy = true);
    try {
      final urls = await (_resolvedUrls ?? Future.value(const <String>[]));
      if (!mounted) return;
      await Future.wait(
        urls.map((u) async {
          try {
            await precacheImage(NetworkImage(u), context);
          } catch (_) {}
        }),
      );
      await Future.delayed(const Duration(milliseconds: 120));
      final boundary =
          _previewKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('No se pudo preparar la vista previa.');
      }
      const targetWidth = 2560.0;
      final logicalWidth = boundary.size.width;
      final pixelRatio =
          logicalWidth > 0 ? (targetWidth / logicalWidth).clamp(2.0, 6.0) : 3.0;
      final image = await boundary.toImage(pixelRatio: pixelRatio.toDouble());
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw Exception('No se pudo capturar el póster.');

      await _showPreviewAndShare(data.buffer.asUint8List());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo exportar la ban list como imagen.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showPreviewAndShare(Uint8List bytes) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder:
          (_) => _ExportPreviewDialog(
            imageBytes: bytes,
            fileName: widget.scope.exportFileName,
          ),
    );
  }

  Widget _buildRaceSidebar() {
    return SizedBox(
      width: 110,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'FONDO',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: .08,
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child:
                _loadingFolders
                    ? const Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFF1D48B),
                        ),
                      ),
                    )
                    : _foldersError != null
                    ? Center(
                      child: IconButton(
                        tooltip: 'Reintentar',
                        onPressed: _loadRaceFolders,
                        icon: const Icon(
                          Icons.refresh_rounded,
                          color: Colors.white54,
                        ),
                      ),
                    )
                    : ListView.separated(
                      itemCount: _raceFolders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final folder = _raceFolders[i];
                        return OutlinedButton.icon(
                          onPressed:
                              _busy ? null : () => _openRaceGallery(folder),
                          icon: const Icon(
                            Icons.folder_rounded,
                            size: 13,
                            color: Color(0xFFF1D48B),
                          ),
                          label: Text(
                            folder.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Colors.white24),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileBackgroundPicker() {
    if (_loadingFolders) {
      return const SizedBox(
        height: 38,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_foldersError != null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _loadRaceFolders,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Reintentar fondos'),
        ),
      );
    }
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _raceFolders.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, index) {
          final folder = _raceFolders[index];
          return OutlinedButton.icon(
            onPressed: _busy ? null : () => _openRaceGallery(folder),
            icon: const Icon(Icons.image_outlined, size: 14),
            label: Text(folder.name),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white24),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSizeControl() {
    return Row(
      children: [
        const Icon(Icons.photo_size_select_small, color: Colors.white54),
        const SizedBox(width: 8),
        const Text(
          'Tamaño de cartas',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Expanded(
          child: Slider(
            value: _cardScale,
            min: .70,
            max: 1,
            divisions: 6,
            label: '${(_cardScale * 100).round()}%',
            onChanged:
                _busy ? null : (value) => setState(() => _cardScale = value),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '${(_cardScale * 100).round()}%',
            textAlign: TextAlign.end,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final previewWidth = constraints.maxWidth;
        final previewHeight = constraints.maxHeight;
        final posterAspect = _banPosterAspectForCount(_restrictedCount);
        final posterHeight = math.min(
          previewHeight,
          previewWidth / posterAspect,
        );
        final posterWidth = posterHeight * posterAspect;

        final bg = _selectedBackground;
        return Center(
          child: SizedBox(
            width: posterWidth,
            height: posterHeight,
            child:
                bg == null
                    ? Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF17191F),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.6,
                            color: Colors.white38,
                          ),
                        ),
                      ),
                    )
                    : RepaintBoundary(
                      key: _previewKey,
                      child: _BanListPosterPreview(
                        backgroundAsset: bg,
                        scope: widget.scope,
                        grouped: _grouped(),
                        cardScale: _cardScale,
                      ),
                    ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isCompact = size.width < 600;
    final dialogWidth = math.min(size.width - 32, 900.0);
    final dialogHeight = math.min(size.height - 48, 900.0);

    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: const Color(0xFF0D1016),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Vista previa de la ban list',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white70,
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child:
                    isCompact
                        ? Column(
                          children: [
                            _buildMobileBackgroundPicker(),
                            const SizedBox(height: 8),
                            Expanded(child: _buildPreviewArea()),
                          ],
                        )
                        : Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildRaceSidebar(),
                            const SizedBox(width: 10),
                            Expanded(child: _buildPreviewArea()),
                          ],
                        ),
              ),
              _buildSizeControl(),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 6,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _busy ? null : _handleExport,
                    icon:
                        _busy
                            ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.image_outlined),
                    label: Text(
                      _busy ? 'Generando...' : 'Vista previa / Exportar',
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
}

/// El póster en sí: título + secciones (Prohibidas / Limitadas a 1 /
/// Limitadas a 2), cada sección con sus cartas agrupadas y ordenadas por
/// edición. El tamaño de carta se calcula para que TODO quepa sin scroll
/// (una sola hoja), igual que el auto-fit del póster de mazos.
class _BanListPosterPreview extends StatelessWidget {
  final String backgroundAsset;
  final BanListScope scope;
  final Map<int, Map<String, List<BanListEntry>>> grouped;
  final double cardScale;

  const _BanListPosterPreview({
    required this.backgroundAsset,
    required this.scope,
    required this.grouped,
    required this.cardScale,
  });

  static const _sectionTitles = {
    0: 'Cartas Prohibidas',
    1: 'Cartas Limitadas a 1 copia',
    2: 'Cartas Limitadas a 2 copias',
  };

  @override
  Widget build(BuildContext context) {
    final sectionKeys = grouped.keys.toList()..sort();

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image(
            image: wallpaperImageProvider(backgroundAsset),
            fit: BoxFit.cover,
          ),
          Container(color: Colors.black.withOpacity(.32)),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  scope.title,
                  style: GoogleFonts.cinzel(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 2,
                  width: 120,
                  color: const Color(0xFFF1D48B),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child:
                      sectionKeys.isEmpty
                          ? Center(
                            child: Text(
                              'Sin restricciones activas',
                              style: GoogleFonts.cinzel(
                                color: Colors.white70,
                                fontSize: 16,
                              ),
                            ),
                          )
                          : _BanPosterSections(
                            sectionKeys: sectionKeys,
                            grouped: grouped,
                            sectionTitles: _sectionTitles,
                            cardScale: cardScale,
                          ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Reparte el alto disponible entre secciones (proporcional a su cantidad de
/// cartas) y dentro de cada sección calcula el ancho de carta más grande que
/// permite que todas sus filas quepan en el alto asignado.
class _BanPosterSections extends StatelessWidget {
  final List<int> sectionKeys;
  final Map<int, Map<String, List<BanListEntry>>> grouped;
  final Map<int, String> sectionTitles;
  final double cardScale;

  const _BanPosterSections({
    required this.sectionKeys,
    required this.grouped,
    required this.sectionTitles,
    required this.cardScale,
  });

  @override
  Widget build(BuildContext context) {
    final totalCards = sectionKeys.fold<int>(
      0,
      (s, k) => s + grouped[k]!.values.fold<int>(0, (s2, v) => s2 + v.length),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        const headerHeight = 30.0;
        const sectionGap = 10.0;
        final totalHeaders = headerHeight * sectionKeys.length;
        final totalGaps = sectionGap * (sectionKeys.length - 1).clamp(0, 999);
        final availableForCards = (constraints.maxHeight -
                totalHeaders -
                totalGaps)
            .clamp(40.0, double.infinity);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < sectionKeys.length; i++) ...[
              if (i > 0) const SizedBox(height: sectionGap),
              _BanPosterSection(
                title: sectionTitles[sectionKeys[i]] ?? 'Restringidas',
                byEdition: grouped[sectionKeys[i]]!,
                height:
                    totalCards == 0
                        ? availableForCards / sectionKeys.length
                        : availableForCards *
                            (grouped[sectionKeys[i]]!.values.fold<int>(
                                  0,
                                  (s, v) => s + v.length,
                                ) /
                                totalCards),
                headerHeight: headerHeight,
                cardScale: cardScale,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _BanPosterSection extends StatelessWidget {
  final String title;
  final Map<String, List<BanListEntry>> byEdition;
  final double height;
  final double headerHeight;
  final double cardScale;

  const _BanPosterSection({
    required this.title,
    required this.byEdition,
    required this.height,
    required this.headerHeight,
    required this.cardScale,
  });

  @override
  Widget build(BuildContext context) {
    final editions = byEdition.keys.toList()..sort(_compareEditions);
    final allEntries = editions.expand((e) => byEdition[e]!).toList();

    return SizedBox(
      height: headerHeight + height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: headerHeight,
            child: Text(
              '$title:',
              style: GoogleFonts.cinzel(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          Expanded(
            child: _BanPosterCardWall(
              entries: allEntries,
              editions: editions,
              byEdition: byEdition,
              cardScale: cardScale,
            ),
          ),
        ],
      ),
    );
  }
}

/// Cartas ordenadas por edición (con separación visual leve entre ediciones
/// vía el orden del Wrap), tamaño auto-ajustado para caber en el alto de la
/// sección sin scroll.
class _BanPosterCardWall extends StatelessWidget {
  final List<BanListEntry> entries;
  final List<String> editions;
  final Map<String, List<BanListEntry>> byEdition;
  final double cardScale;

  const _BanPosterCardWall({
    required this.entries,
    required this.editions,
    required this.byEdition,
    required this.cardScale,
  });

  double _fitBaseWidth(double maxW, double maxH, int count, double spacing) {
    if (count == 0) return 60.0;
    const cardAspect = 1.42;
    double best = 12.0;
    for (double w = 130.0; w >= 12.0; w -= 1.0) {
      final perRow = math.max(1, ((maxW + spacing) / (w + spacing)).floor());
      final rows = (count / perRow).ceil();
      final rowH = w * cardAspect;
      final totalH = rows * rowH + (rows - 1) * spacing;
      if (totalH <= maxH) {
        best = w;
        break;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH =
            constraints.maxHeight.isFinite ? constraints.maxHeight : maxW;
        const spacing = 6.0;
        final fittedWidth = _fitBaseWidth(maxW, maxH, entries.length, spacing);
        final baseWidth = fittedWidth * cardScale.clamp(.70, 1.0);
        final cardHeight = baseWidth * 1.42;

        return ClipRect(
          child: Align(
            alignment: Alignment.topLeft,
            child: Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final edition in editions)
                  for (final entry in byEdition[edition]!)
                    _BanPosterCardTile(
                      entry: entry,
                      width: baseWidth,
                      height: cardHeight,
                    ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BanPosterCardTile extends StatelessWidget {
  final BanListEntry entry;
  final double width;
  final double height;

  const _BanPosterCardTile({
    required this.entry,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final typeColor =
        _banPosterTypeColors[(entry.cardType ?? '').toLowerCase()] ??
        _banPosterTypeFallback;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.14),
        border: Border.all(color: typeColor.withOpacity(.75), width: 2),
        color: const Color(0xFF232833),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.35),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(width * 0.12),
        child: SizedBox.expand(
          child: FutureBuilder<String?>(
            future: resolveBanEntryImageUrl(entry),
            builder: (context, snap) {
              final url = (snap.data ?? '').trim();
              return url.isNotEmpty
                  ? Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _fallback(),
                  )
                  : _fallback();
            },
          ),
        ),
      ),
    );
  }

  Widget _fallback() => Container(
    color: const Color(0xFF232833),
    alignment: Alignment.center,
    padding: const EdgeInsets.all(4),
    child: Text(
      entry.cardName,
      textAlign: TextAlign.center,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: Colors.white54, fontSize: 9),
    ),
  );
}

class _ExportPreviewDialog extends StatefulWidget {
  final Uint8List imageBytes;
  final String fileName;

  const _ExportPreviewDialog({
    required this.imageBytes,
    required this.fileName,
  });

  @override
  State<_ExportPreviewDialog> createState() => _ExportPreviewDialogState();
}

class _ExportPreviewDialogState extends State<_ExportPreviewDialog> {
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await DeckPosterShareService.sharePosterPng(
        posterBytes: widget.imageBytes,
        deckName: widget.fileName,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo guardar/compartir la imagen.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: const Color(0xFF0D1016),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: math.min(size.width - 32, 720.0),
        height: math.min(size.height - 64, 820.0),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Vista previa',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed:
                        _sharing ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox.expand(
                  child: Image.memory(
                    widget.imageBytes,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _sharing ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cerrar'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _sharing ? null : _share,
                    icon:
                        _sharing
                            ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.ios_share),
                    label: Text(
                      _sharing ? 'Guardando...' : 'Compartir / Guardar',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
