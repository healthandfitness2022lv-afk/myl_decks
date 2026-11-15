part of '../deck_details_screen.dart';

enum _TitlePosition { lateral, top }

// Fuentes reales de Google Fonts (funcionan en todas las plataformas,
// incluida web — los alias genéricos 'serif'/'monospace' no se aplican en
// Flutter Web porque no hay una fuente de sistema real detrás).
final Map<
  String,
  TextStyle Function({
    required double fontSize,
    required FontWeight fontWeight,
    required Color color,
    required double letterSpacing,
  })
>
_posterFontBuilders = {
  'Playfair Display':
      ({
        required fontSize,
        required fontWeight,
        required color,
        required letterSpacing,
      }) => GoogleFonts.playfairDisplay(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
      ),
  'Roboto Mono':
      ({
        required fontSize,
        required fontWeight,
        required color,
        required letterSpacing,
      }) => GoogleFonts.robotoMono(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
      ),
  'Pacifico':
      ({
        required fontSize,
        required fontWeight,
        required color,
        required letterSpacing,
      }) => GoogleFonts.pacifico(
        fontSize: fontSize,
        // Pacifico solo trae peso regular — forzar bold rompe la carga web.
        fontWeight: FontWeight.normal,
        color: color,
        letterSpacing: letterSpacing,
      ),
  'Cinzel':
      ({
        required fontSize,
        required fontWeight,
        required color,
        required letterSpacing,
      }) => GoogleFonts.cinzel(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
      ),
};

// Color de borde por tipo de carta (ver normalizeTipoLoose en card_utils.dart)
// cuando el toggle "Distinguir por tipo" está activo.
const Map<String, Color> _posterTypeColors = {
  'aliado': Color(0xFF4FA8E0), // azul
  'oro': Color(0xFFD9A323), // dorado
  'talisman': Color(0xFF9B6BD9), // violeta
  'totem': Color(0xFF3FB77E), // verde
  'arma': Color(0xFFE05C5C), // rojo
  'descendiente': Color(0xFFE0894F), // naranja
};
const Color _posterTypeColorFallback = Color(0xFFD9A323);

class _DeckPdfPreviewDialog extends StatefulWidget {
  final String deckName;
  final String edition;
  final String raceLabel;
  final int totalCards;
  final List<_DeckVisualCard> cards;
  final Map<String, int> byType;
  final Map<int, int> curve;
  final Future<void> Function(Uint8List posterBytes) onExport;

  const _DeckPdfPreviewDialog({
    required this.deckName,
    required this.edition,
    required this.raceLabel,
    required this.totalCards,
    required this.cards,
    required this.byType,
    required this.curve,
    required this.onExport,
  });

  @override
  State<_DeckPdfPreviewDialog> createState() => _DeckPdfPreviewDialogState();
}

class _DeckPdfPreviewDialogState extends State<_DeckPdfPreviewDialog> {
  final GlobalKey _previewKey = GlobalKey();
  String? _selectedBackground;
  bool _busy = false;
  bool _grouped = false; // false = desplegadas, true = agrupadas por tipo
  // Colorea el borde de cada carta según su tipo (aliado/oro/talismán/etc).
  bool _colorByType = false;
  // null = automático (calcula cuántas entran para que quepa todo). Si el
  // usuario elige una cantidad, el ancho de carta se deriva del ancho
  // disponible del póster / cartas por fila (ver _PosterCardsWall) — se
  // acomoda solo al tamaño real del playmat, no a un pixelaje fijo.
  int? _cardsPerRow;
  _TitlePosition _titlePosition = _TitlePosition.lateral;
  double _cardOpacity = 1.0;
  String _titleFontFamily = _posterFontBuilders.keys.first;
  double _titleFontSize = 20;
  Color _titleColor = Colors.white70;
  bool _titleBold = true;
  // Solo aplica cuando _titlePosition == top (el título "lateral" siempre
  // queda centrado verticalmente en su columna angosta).
  final TextAlign _titleAlign = TextAlign.center;
  // Overlays informativos opcionales, mismo color que el título.
  bool _showCostCurve = false;
  bool _showTypeBreakdown = false;
  List<DriveFile> _raceFolders = [];
  bool _loadingFolders = true;
  String? _foldersError;

  @override
  void initState() {
    super.initState();
    _loadRaceFolders();
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
      // Si el usuario todavía no eligió fondo, se sortea uno para que la
      // vista previa nunca arranque en pantalla negra.
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

  final _random = math.Random();

  /// Elige una raza y una imagen al azar dentro de ella como fondo. Se usa
  /// como default automático (nunca dejar la vista previa en negro) y como
  /// respaldo si el usuario intenta exportar sin haber elegido fondo.
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

  Future<void> _pickTitleColor() async {
    Color picked = _titleColor;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF12161D),
            title: const Text(
              'Color del título',
              style: TextStyle(color: Colors.white),
            ),
            content: SingleChildScrollView(
              child: ColorPicker(
                pickerColor: _titleColor,
                onColorChanged: (c) => picked = c,
                enableAlpha: false,
                labelTypes: const [ColorLabelType.rgb, ColorLabelType.hex],
                pickerAreaHeightPercent: 0.7,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Usar'),
              ),
            ],
          ),
    );
    if (confirmed == true && mounted) {
      setState(() => _titleColor = picked);
    }
  }

  /// Todas las URLs (ya con webSafeUrl aplicado río arriba) que aparecen en
  /// el poster. No volver a pasar por webSafeUrl acá: rompe la URL de weserv.
  /// Solo se toma la URL que realmente se renderiza por copia (variante
  /// asignada o, si esa copia no tiene variante, la oficial como respaldo),
  /// para no precachear/cargar dos veces la misma carta.
  Set<String> _allPosterUrls() {
    final seen = <String>{};
    for (final card in widget.cards) {
      final copies = card.count > 0 ? card.count : 1;
      for (var i = 0; i < copies; i++) {
        final u = card.urlForCopy(i);
        if (u.trim().isNotEmpty) seen.add(u);
      }
    }
    return seen;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bg = _selectedBackground;
    if (bg != null) precacheImage(wallpaperImageProvider(bg), context);
    for (final safe in _allPosterUrls()) {
      precacheImage(NetworkImage(safe), context);
    }
  }

  Future<void> _handleExport() async {
    if (_busy) return;

    // Respaldo: si por lo que sea no se sorteó fondo al abrir el diálogo
    // (ej. tardó la carga de Drive), se elige uno ahora en vez de bloquear
    // la exportación.
    if (_selectedBackground == null) {
      await _pickRandomBackground();
      if (_selectedBackground == null) return; // sin conexión: no hay nada
    }

    setState(() => _busy = true);
    try {
      // Esperar a que TODAS las imágenes estén realmente cargadas antes de
      // capturar (Drive vía weserv puede tardar > 1s). Sin esto, las cartas
      // que se resolvieron tarde salen vacías en el PNG.
      await Future.wait(
        _allPosterUrls().map((u) async {
          try {
            await precacheImage(NetworkImage(u), context);
          } catch (_) {}
        }),
      );
      // Un frame extra para que el layout termine de pintarse.
      await Future.delayed(const Duration(milliseconds: 120));
      final boundary =
          _previewKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('No se pudo preparar la vista previa.');
      }

      // Exportar en alta resolución (~2560px de ancho) para poder hacer zoom
      // sin pixelado. pixelRatio = anchoObjetivo / anchoLógico del boundary.
      const targetWidth = 2560.0;
      final logicalWidth = boundary.size.width;
      final pixelRatio =
          logicalWidth > 0 ? (targetWidth / logicalWidth).clamp(2.0, 6.0) : 3.0;
      final image = await boundary.toImage(pixelRatio: pixelRatio.toDouble());
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw Exception('No se pudo capturar el poster.');
      }

      await widget.onExport(data.buffer.asUint8List());
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _groupLabelStyle = TextStyle(
    color: Colors.white38,
    fontSize: 9,
    fontWeight: FontWeight.w700,
    letterSpacing: .08,
  );

  /// Columna angosta con las carpetas de raza (fondo), al costado del
  /// póster — scroll vertical, ícono + nombre corto.
  Widget _buildRaceSidebar() {
    return SizedBox(
      width: 110,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('FONDO', style: _groupLabelStyle),
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

  /// Controles agrupados por qué afectan (Diseño / Título / Cartas), en el
  /// menor espacio vertical posible: el protagonista es el póster.
  ButtonStyle get _iconSegStyle => ButtonStyle(
    visualDensity: VisualDensity.compact,
    padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 5)),
    minimumSize: WidgetStateProperty.all(const Size(0, 30)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.selected)
              ? const Color(0xFF14181F)
              : Colors.white70,
    ),
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.selected)
              ? const Color(0xFFF1D48B)
              : Colors.transparent,
    ),
  );

  Widget _miniToggle({
    required IconData icon,
    required bool active,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: Icon(
          icon,
          size: 17,
          color: active ? const Color(0xFFF1D48B) : Colors.white38,
        ),
      ),
    );
  }

  Widget _miniDivider() => Container(
    width: 1,
    height: 22,
    margin: const EdgeInsets.symmetric(horizontal: 6),
    color: Colors.white12,
  );

  /// Todo en una sola fila, sin scroll: solo íconos + tooltip (sin labels de
  /// texto en los SegmentedButton) y sliders angostos, para que quepa entera.
  Widget _buildCompactControls() {
    return Row(
      children: [
        // Diseño: apiladas/separadas + distinguir por tipo.
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment<bool>(
              value: false,
              tooltip: 'Apiladas',
              icon: Icon(Icons.layers_rounded, size: 15),
            ),
            ButtonSegment<bool>(
              value: true,
              tooltip: 'Separadas',
              icon: Icon(Icons.view_column_rounded, size: 15),
            ),
          ],
          selected: {_grouped},
          showSelectedIcon: false,
          onSelectionChanged:
              _busy ? null : (s) => setState(() => _grouped = s.first),
          style: _iconSegStyle,
        ),
        _miniToggle(
          icon: Icons.palette_rounded,
          active: _colorByType,
          tooltip: 'Distinguir por tipo (borde de color)',
          onPressed:
              _busy ? null : () => setState(() => _colorByType = !_colorByType),
        ),
        _miniDivider(),
        // Título: posición + alineación (si va arriba) + fuente/negrita/color.
        SegmentedButton<_TitlePosition>(
          segments: const [
            ButtonSegment<_TitlePosition>(
              value: _TitlePosition.lateral,
              tooltip: 'Título lateral',
              icon: Icon(Icons.view_sidebar_rounded, size: 15),
            ),
            ButtonSegment<_TitlePosition>(
              value: _TitlePosition.top,
              tooltip: 'Título arriba',
              icon: Icon(Icons.vertical_align_top_rounded, size: 15),
            ),
          ],
          selected: {_titlePosition},
          showSelectedIcon: false,
          onSelectionChanged:
              _busy ? null : (s) => setState(() => _titlePosition = s.first),
          style: _iconSegStyle,
        ),
        PopupMenuButton<String>(
          tooltip: 'Fuente del título',
          enabled: !_busy,
          initialValue: _titleFontFamily,
          onSelected: (v) => setState(() => _titleFontFamily = v),
          itemBuilder:
              (_) =>
                  _posterFontBuilders.keys
                      .map(
                        (name) => PopupMenuItem(
                          value: name,
                          child: Text(
                            name,
                            style: _posterFontBuilders[name]!(
                              fontSize: 14,
                              fontWeight: FontWeight.normal,
                              color: Colors.black87,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      )
                      .toList(),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 5),
            child: Icon(
              Icons.font_download_outlined,
              color: Colors.white70,
              size: 17,
            ),
          ),
        ),
        _miniToggle(
          icon: Icons.format_bold_rounded,
          active: _titleBold,
          tooltip: 'Negrita',
          onPressed:
              _busy ? null : () => setState(() => _titleBold = !_titleBold),
        ),
        Tooltip(
          message: 'Color del título',
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _busy ? null : _pickTitleColor,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Container(
                width: 17,
                height: 17,
                decoration: BoxDecoration(
                  color: _titleColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Slider(
            value: _titleFontSize,
            min: 10,
            max: 40,
            divisions: 30,
            label: '${_titleFontSize.round()}',
            onChanged: _busy ? null : (v) => setState(() => _titleFontSize = v),
          ),
        ),
        _miniDivider(),
        // Cartas: cantidad por fila + transparencia.
        Tooltip(
          message: 'Cartas por fila',
          child: Icon(Icons.view_week_rounded, color: Colors.white54, size: 16),
        ),
        Expanded(
          flex: 3,
          child: Slider(
            value: (_cardsPerRow ?? 11).clamp(9, 13).toDouble(),
            min: 9,
            max: 13,
            divisions: 4,
            label: _cardsPerRow == null ? 'Auto' : '${_cardsPerRow!}',
            onChanged:
                _busy ? null : (v) => setState(() => _cardsPerRow = v.round()),
          ),
        ),
        _miniToggle(
          icon: Icons.auto_fix_high_rounded,
          active: _cardsPerRow == null,
          tooltip: 'Cantidad automática',
          onPressed:
              _busy || _cardsPerRow == null
                  ? null
                  : () => setState(() => _cardsPerRow = null),
        ),
        Tooltip(
          message: 'Transparencia',
          child: Icon(Icons.opacity_rounded, color: Colors.white54, size: 16),
        ),
        Expanded(
          flex: 2,
          child: Slider(
            value: _cardOpacity,
            min: 0.2,
            max: 1.0,
            divisions: 16,
            label: '${(_cardOpacity * 100).round()}%',
            onChanged: _busy ? null : (v) => setState(() => _cardOpacity = v),
          ),
        ),
        _miniDivider(),
        // Info: overlays opcionales.
        _miniToggle(
          icon: Icons.bar_chart_rounded,
          active: _showCostCurve,
          tooltip: 'Curva de coste',
          onPressed:
              _busy
                  ? null
                  : () => setState(() => _showCostCurve = !_showCostCurve),
        ),
        _miniToggle(
          icon: Icons.pie_chart_rounded,
          active: _showTypeBreakdown,
          tooltip: 'Cantidad por tipo',
          onPressed:
              _busy
                  ? null
                  : () =>
                      setState(() => _showTypeBreakdown = !_showTypeBreakdown),
        ),
      ],
    );
  }

  Widget _buildPreviewArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final previewWidth = constraints.maxWidth;
        final previewHeight = constraints.maxHeight;
        // Los fondos (assets y wallpapers de Drive) son 16:9.
        const posterAspect = 16 / 9;
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
                        borderRadius: BorderRadius.circular(26),
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
                      child: _DeckPdfPosterPreview(
                        backgroundAsset: bg,
                        deckName: widget.deckName,
                        edition: widget.edition,
                        raceLabel: widget.raceLabel,
                        totalCards: widget.totalCards,
                        cards: widget.cards,
                        byType: widget.byType,
                        curve: widget.curve,
                        grouped: _grouped,
                        colorByType: _colorByType,
                        cardsPerRow: _cardsPerRow,
                        titlePosition: _titlePosition,
                        cardOpacity: _cardOpacity,
                        titleFontFamily: _titleFontFamily,
                        titleFontSize: _titleFontSize,
                        titleColor: _titleColor,
                        titleBold: _titleBold,
                        titleAlign: _titleAlign,
                        showCostCurve: _showCostCurve,
                        showTypeBreakdown: _showTypeBreakdown,
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
    final dialogWidth = math.min(size.width - 32, 1180.0);
    final dialogHeight = math.min(size.height - 48, 860.0);

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
                      'Vista previa de la imagen',
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
              const SizedBox(height: 6),
              _buildCompactControls(),
              const SizedBox(height: 6),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildRaceSidebar(),
                    const SizedBox(width: 10),
                    Expanded(child: _buildPreviewArea()),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 10),
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
                    label: Text(_busy ? 'Exportando...' : 'Exportar PNG'),
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

class _DeckPdfPosterPreview extends StatelessWidget {
  final String backgroundAsset;
  final String deckName;
  final String edition;
  final String raceLabel;
  final int totalCards;
  final List<_DeckVisualCard> cards;
  final Map<String, int> byType;
  final Map<int, int> curve;
  final bool grouped;
  final bool colorByType;
  final int? cardsPerRow;
  final _TitlePosition titlePosition;
  final double cardOpacity;
  final String titleFontFamily;
  final double titleFontSize;
  final Color titleColor;
  final bool titleBold;
  // Solo aplica cuando titlePosition == top.
  final TextAlign titleAlign;
  final bool showCostCurve;
  final bool showTypeBreakdown;

  const _DeckPdfPosterPreview({
    required this.backgroundAsset,
    required this.deckName,
    required this.edition,
    required this.raceLabel,
    required this.totalCards,
    required this.cards,
    required this.byType,
    required this.curve,
    this.grouped = false,
    this.colorByType = false,
    this.cardsPerRow,
    this.titlePosition = _TitlePosition.lateral,
    this.cardOpacity = 1.0,
    required this.titleFontFamily,
    this.titleFontSize = 20,
    this.titleColor = Colors.white70,
    this.titleBold = true,
    this.titleAlign = TextAlign.center,
    this.showCostCurve = false,
    this.showTypeBreakdown = false,
  });

  Widget _titleText({required bool horizontal}) {
    final fontBuilder =
        _posterFontBuilders[titleFontFamily] ??
        _posterFontBuilders.values.first;
    final text = Text(
      deckName.isEmpty ? 'Mazo' : deckName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: horizontal ? titleAlign : null,
      style: fontBuilder(
        fontSize: titleFontSize,
        fontWeight: titleBold ? FontWeight.w900 : FontWeight.normal,
        color: titleColor,
        letterSpacing: 0.6,
      ),
    );
    if (!horizontal) {
      return Center(child: RotatedBox(quarterTurns: 3, child: text));
    }
    final align = switch (titleAlign) {
      TextAlign.left => Alignment.centerLeft,
      TextAlign.right => Alignment.centerRight,
      _ => Alignment.center,
    };
    return Align(alignment: align, child: text);
  }

  @override
  Widget build(BuildContext context) {
    final hasInfo = showCostCurve || showTypeBreakdown;
    final cardsWall = _PosterCardsWall(
      cards: cards,
      spread: grouped,
      cardsPerRow: cardsPerRow,
      cardOpacity: cardOpacity,
      colorByType: colorByType,
    );
    // El contenedor del título debe crecer con el tamaño de fuente elegido.
    final titleBoxSize = titleFontSize + 14;

    final Widget content;
    switch (titlePosition) {
      case _TitlePosition.top:
        // Título y panel de info comparten la misma franja horizontal
        // superior (uno a cada lado); las cartas abajo usan el ancho
        // completo sin ningún recorte.
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: hasInfo ? math.max(titleBoxSize, 100) : titleBoxSize,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: _titleText(horizontal: true)),
                  if (hasInfo) ...[
                    const SizedBox(width: 10),
                    _buildInfoPanel(),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: cardsWall),
          ],
        );
        break;
      case _TitlePosition.lateral:
        // Título rotado arriba y panel de info debajo, ambos en la misma
        // columna angosta de la izquierda; las cartas ocupan el resto.
        content = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: hasInfo ? math.max(titleBoxSize, 140) : titleBoxSize,
              child: Column(
                children: [
                  Expanded(child: _titleText(horizontal: false)),
                  if (hasInfo) ...[
                    const SizedBox(height: 8),
                    _buildInfoPanel(horizontal: false),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(2, 2, 0, 2),
                child: cardsWall,
              ),
            ),
          ],
        );
        break;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image(
            image: wallpaperImageProvider(backgroundAsset),
            fit: BoxFit.cover,
          ),
          Padding(padding: const EdgeInsets.all(18), child: content),
        ],
      ),
    );
  }

  // horizontal=true (título "Arriba", franja ancha): curva y tipos van lado
  // a lado. horizontal=false (título "Lateral", columna angosta): se apilan
  // uno debajo del otro para no desbordar el ancho disponible.
  Widget _buildInfoPanel({bool horizontal = true}) {
    final children = [
      if (showCostCurve) _buildCostCurve(),
      if (showTypeBreakdown) _buildTypeBreakdown(),
    ];
    if (horizontal) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            children[i],
          ],
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          children[i],
        ],
      ],
    );
  }

  Widget _infoBox(Widget child) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: titleColor.withOpacity(.35)),
      ),
      child: child,
    );
  }

  Widget _buildCostCurve() {
    if (curve.isEmpty) return const SizedBox.shrink();
    final maxCount = curve.values.fold<int>(0, (m, v) => math.max(m, v));
    final costs = curve.keys.toList()..sort();
    return _infoBox(
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children:
              costs.map((cost) {
                final count = curve[cost] ?? 0;
                final barHeight =
                    maxCount > 0 ? 6 + (count / maxCount) * 44 : 6.0;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$count',
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        width: 10,
                        height: barHeight,
                        decoration: BoxDecoration(
                          color: titleColor,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$cost',
                        style: TextStyle(
                          color: titleColor.withOpacity(.7),
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
        ),
      ),
    );
  }

  static const _typeLabels = {
    'aliado': 'Aliados',
    'oro': 'Oros',
    'talisman': 'Talismanes',
    'totem': 'Tótems',
    'arma': 'Armas',
    'descendiente': 'Descendientes',
  };

  Widget _buildTypeBreakdown() {
    final entries =
        byType.entries.where((e) => e.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return const SizedBox.shrink();
    return _infoBox(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children:
            entries.map((e) {
              final label = _typeLabels[e.key.toLowerCase()] ?? e.key;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  '$label: ${e.value}',
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }
}

class _PosterCardsWall extends StatelessWidget {
  final List<_DeckVisualCard> cards;
  final bool spread; // true = cada copia lado a lado; false = apiladas
  // Si está definido, el ancho de carta se deriva del ancho disponible del
  // póster dividido esta cantidad — se acomoda solo al tamaño real del
  // playmat en vez de fijar un pixelaje. null = automático (ver _fitBaseWidth).
  final int? cardsPerRow;
  final double cardOpacity;
  final bool colorByType;

  const _PosterCardsWall({
    required this.cards,
    this.spread = false,
    this.cardsPerRow,
    this.cardOpacity = 1.0,
    this.colorByType = false,
  });

  // Extra por lado (como fracción de baseWidth) que la rotación de
  // Transform.rotate en _PosterMiniCard hace sobresalir del bounding box
  // axis-aligned del tile, en el peor caso (3 copias, ángulo máximo
  // 0.035*2 rad). Debe mantenerse en sync con el cálculo de rotationSlack
  // en _PosterMiniCard._buildCard(). Sin este margen, los tiles vecinos del
  // Wrap se solapan visualmente (overflow entre pilas de cartas).
  static const _rotationSlackFactor = 0.038;

  /// Ancho de carta tal que exactamente [perRow] tiles (peor caso: 3 copias
  /// apiladas) entran en el ancho disponible [maxW]. Si con ese ancho las
  /// filas resultantes ([tileCount] / [perRow]) no entran en el alto
  /// disponible [maxH], se achica hasta que quepan — la cantidad de
  /// columnas elegida por el usuario nunca cambia, solo el tamaño.
  double _baseWidthForCardsPerRow(
    double maxW,
    double maxH,
    int perRow,
    int tileCount,
    double spacing,
  ) {
    final availableForFootprints = maxW - spacing * (perRow - 1);
    final footprintPerCard = availableForFootprints / perRow;
    // footprint = w + 2*(w*0.095) + 2*rotationSlack ≈ w * 1.265 (peor caso 3
    // copias apiladas; ver _rotationSlackFactor para el término de rotación).
    final widthFromColumns = math.max(
      12.0,
      spread
          ? footprintPerCard
          : footprintPerCard / (1.19 + _rotationSlackFactor * 2),
    );

    if (tileCount == 0) return widthFromColumns;
    const cardAspect = 1.42; // alto = ancho * 1.42
    final rows = (tileCount / perRow).ceil();

    // Alto que ocuparían `rows` filas con este ancho; si no entra, se achica
    // proporcionalmente (misma cantidad de columnas, cartas más chicas).
    double heightForWidth(double w) {
      final rowH = w * cardAspect + (2 * (w * 0.03));
      return rows * rowH + (rows - 1) * spacing;
    }

    if (heightForWidth(widthFromColumns) <= maxH) return widthFromColumns;

    double lo = 12.0, hi = widthFromColumns;
    for (var i = 0; i < 24; i++) {
      final mid = (lo + hi) / 2;
      if (heightForWidth(mid) <= maxH) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Calcula el mayor `baseWidth` tal que todos los tiles quepan en el área
  /// disponible (ancho × alto), simulando el wrap por filas.
  double _fitBaseWidth(
    double maxW,
    double maxH,
    int tileCount,
    double spacing,
  ) {
    if (tileCount == 0) return 78.0;
    const cardAspect = 1.42; // alto = ancho * 1.42
    double best = 12.0;
    // Probamos de grande a chico hasta que quepa verticalmente.
    for (double w = 160.0; w >= 12.0; w -= 1.0) {
      final footprint =
          spread
              ? w
              : w +
                  2 * (w * 0.095) +
                  2 * (w * _rotationSlackFactor); // peor caso (3 copias)
      final perRow = math.max(
        1,
        ((maxW + spacing) / (footprint + spacing)).floor(),
      );
      final rows = (tileCount / perRow).ceil();
      final rowH =
          w * cardAspect + (2 * (w * 0.03)); // alto con offset de stack
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
        final spacing = maxW >= 820 ? 6.0 : 5.0;

        // Número real de tiles (en modo separadas cada copia es un tile).
        final tileCount =
            spread ? cards.fold<int>(0, (s, c) => s + c.count) : cards.length;

        final maxH =
            constraints.maxHeight.isFinite ? constraints.maxHeight : maxW;
        final perRow = cardsPerRow;
        final baseWidth =
            perRow != null
                ? _baseWidthForCardsPerRow(
                  maxW,
                  maxH,
                  perRow,
                  tileCount,
                  spacing,
                )
                : _fitBaseWidth(maxW, maxH, tileCount, spacing);

        // Ancho de "slot" de columna cuando se fija cantidad por fila: cada
        // tile (sea 1 copia o 3 apiladas) ocupa el mismo espacio horizontal,
        // así el Wrap respeta exactamente `perRow` por fila sin importar
        // cuántas copias tenga cada carta.
        final slotWidth =
            perRow != null ? (maxW - spacing * (perRow - 1)) / perRow : null;

        Widget wrapInSlot(Widget tile) {
          if (slotWidth == null) return tile;
          return SizedBox(
            width: slotWidth,
            child: Align(alignment: Alignment.topCenter, child: tile),
          );
        }

        final tiles = <Widget>[];
        for (final card in cards) {
          final typeColor =
              colorByType
                  ? (_posterTypeColors[card.tipo.toLowerCase()] ??
                      _posterTypeColorFallback)
                  : null;
          if (spread) {
            // Una carta por copia, lado a lado, cada una con su propia variante.
            for (int i = 0; i < card.count; i++) {
              tiles.add(
                wrapInSlot(
                  _PosterMiniCard(
                    card: card,
                    baseWidth: baseWidth,
                    singleCopyIndex: i,
                    opacity: cardOpacity,
                    borderColor: typeColor,
                  ),
                ),
              );
            }
          } else {
            tiles.add(
              wrapInSlot(
                _PosterMiniCard(
                  card: card,
                  baseWidth: baseWidth,
                  opacity: cardOpacity,
                  borderColor: typeColor,
                ),
              ),
            );
          }
        }

        return SizedBox(
          width: maxW,
          height: maxH,
          child: Align(
            alignment: Alignment.topCenter,
            child: Wrap(
              spacing: spacing,
              runSpacing: spacing,
              alignment: WrapAlignment.center,
              children: tiles,
            ),
          ),
        );
      },
    );
  }
}

class _PosterMiniCard extends StatelessWidget {
  final _DeckVisualCard card;
  final double baseWidth;
  // Si está definido, renderiza SOLO esa copia (sin apilar) mostrando su variante.
  final int? singleCopyIndex;
  final double opacity;
  // Si está definido (toggle "Distinguir por tipo"), reemplaza el borde
  // dorado por defecto por el color asociado al tipo de esta carta.
  final Color? borderColor;

  const _PosterMiniCard({
    required this.card,
    required this.baseWidth,
    this.singleCopyIndex,
    this.opacity = 1.0,
    this.borderColor,
  });

  Widget _cardImage(int copyIndex, double w, double h) {
    // card.urlForCopy ya viene resuelta vía DriveService.webSafeUrl (ver
    // _loadImgIndex / _resolveAnyImageForCard en deck_details_screen.dart).
    // Volver a envolverla acá rompe la URL de weserv (404).
    final u = card.urlForCopy(copyIndex);
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child:
          u.trim().isNotEmpty
              ? Image.network(
                u,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _miniFallback(),
              )
              : _miniFallback(),
    );
  }

  BoxDecoration get _cardDecoration => BoxDecoration(
    borderRadius: BorderRadius.circular(12),
    border: Border.all(
      color: borderColor ?? const Color(0xFFD9A323).withOpacity(.68),
      width: borderColor != null ? 2.2 : 1.2,
    ),
    color: const Color(0xFF232833),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(.28),
        blurRadius: 12,
        offset: const Offset(0, 6),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Opacity(opacity: opacity, child: _buildCard());
  }

  Widget _buildCard() {
    final cardWidth = baseWidth;
    final cardHeight = baseWidth * 1.42;

    // Modo "separadas": una sola copia individual.
    if (singleCopyIndex != null) {
      return Container(
        width: cardWidth,
        height: cardHeight,
        decoration: _cardDecoration,
        child: _cardImage(singleCopyIndex!, cardWidth, cardHeight),
      );
    }

    final stackCopies = card.count.clamp(1, 3);
    final dx = baseWidth * 0.095;
    final dy = baseWidth * 0.03;

    // Transform.rotate pivota en el centro del Container: al rotar, sus
    // esquinas sobresalen del bounding box axis-aligned original. Sin este
    // margen, ese sobresaliente invade el tile vecino dentro del Wrap
    // (overflow visual entre pilas). maxAngle es el mayor ángulo usado
    // (última copia visible, i = stackCopies - 1).
    final maxAngle = (0.035 * (stackCopies - 1)).abs();
    final rotationSlack =
        (cardWidth / 2) * math.sin(maxAngle) +
        (cardHeight / 2) * (1 - math.cos(maxAngle));

    final tileWidth = cardWidth + ((stackCopies - 1) * dx) + rotationSlack * 2;
    final tileHeight =
        cardHeight + ((stackCopies - 1) * dy) + rotationSlack * 2;

    return SizedBox(
      width: tileWidth,
      child: SizedBox(
        width: tileWidth,
        height: tileHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (int i = stackCopies - 1; i >= 0; i--)
              Positioned(
                left: rotationSlack + i * dx,
                top: rotationSlack + i * dy,
                child: Transform.rotate(
                  angle: i == 0 ? 0 : (-0.035 * i),
                  child: Container(
                    width: cardWidth,
                    height: cardHeight,
                    decoration: _cardDecoration,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child:
                          (() {
                            // Ya resuelta vía webSafeUrl más arriba en el pipeline.
                            final u = card.urlForCopy(i);
                            return u.trim().isNotEmpty
                                ? Image.network(
                                  u,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _miniFallback(),
                                )
                                : _miniFallback();
                          })(),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _miniFallback() {
    return Container(
      color: const Color(0xFF232833),
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported, color: Colors.white54),
    );
  }
}
