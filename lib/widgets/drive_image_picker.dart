// lib/widgets/drive_image_picker.dart
import 'package:flutter/material.dart';
import '../services/drive_service.dart';
import 'network_image.dart';

/// Resultado que devuelve el picker al confirmar.
class DrivePickResult {
  final String fileId;
  final String fileName;
  final String viewUrl;

  const DrivePickResult({
    required this.fileId,
    required this.fileName,
    required this.viewUrl,
  });
}

/// Sheet modal que permite navegar carpetas de Google Drive y elegir una imagen.
///
/// Uso:
/// ```dart
/// final result = await showDriveImagePicker(context, rootFolderId: '1H4Yz...');
/// if (result != null) { /* usar result.viewUrl */ }
/// ```
Future<DrivePickResult?> showDriveImagePicker(
  BuildContext context, {
  required String rootFolderId,
  String rootLabel = 'Cartas MYL',
}) {
  return showModalBottomSheet<DrivePickResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder:
        (_) =>
            _DrivePickerSheet(rootFolderId: rootFolderId, rootLabel: rootLabel),
  );
}

class _DrivePickerSheet extends StatefulWidget {
  final String rootFolderId;
  final String rootLabel;
  const _DrivePickerSheet({
    required this.rootFolderId,
    required this.rootLabel,
  });

  @override
  State<_DrivePickerSheet> createState() => _DrivePickerSheetState();
}

class _DrivePickerSheetState extends State<_DrivePickerSheet> {
  // Pila de navegación: cada entrada es (folderId, folderName)
  final List<(String, String)> _stack = [];
  List<DriveFile> _items = [];
  bool _loading = false;
  String? _error;
  DriveFile? _selected;

  String get _currentFolderId =>
      _stack.isEmpty ? widget.rootFolderId : _stack.last.$1;

  @override
  void initState() {
    super.initState();
    _load(_currentFolderId);
  }

  Future<void> _load(String folderId) async {
    setState(() {
      _loading = true;
      _error = null;
      _selected = null;
    });
    try {
      final items = await DriveService.listFolder(folderId);
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openFolder(DriveFile folder) {
    setState(() => _stack.add((folder.id, folder.name)));
    _load(folder.id);
  }

  void _goBack() {
    if (_stack.isEmpty) return;
    setState(() => _stack.removeLast());
    _load(_currentFolderId);
  }

  void _confirm() {
    final f = _selected;
    if (f == null) return;
    Navigator.of(
      context,
    ).pop(DrivePickResult(fileId: f.id, fileName: f.name, viewUrl: f.viewUrl));
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: .88,
      maxChildSize: .96,
      minChildSize: .5,
      expand: false,
      builder: (ctx, scroll) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF12161D),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // ── Handle ──────────────────────────────────────────────
              const _SheetHandle(),

              // ── Header ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    if (_stack.isNotEmpty)
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white70,
                          size: 18,
                        ),
                        onPressed: _goBack,
                        tooltip: 'Volver',
                      ),
                    const Icon(
                      Icons.folder_open_rounded,
                      color: Color(0xFFF1D48B),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _stack.isEmpty ? widget.rootLabel : _stack.last.$2,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_stack.length > 1)
                      Text(
                        _stack.map((e) => e.$2).join(' › '),
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white10),

              // ── Preview de la seleccionada ───────────────────────────
              if (_selected != null) _SelectedPreview(file: _selected!),

              // ── Contenido ────────────────────────────────────────────
              Expanded(
                child:
                    _loading
                        ? const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFFF1D48B),
                          ),
                        )
                        : _error != null
                        ? _ErrorView(
                          error: _error!,
                          onRetry: () => _load(_currentFolderId),
                        )
                        : _items.isEmpty
                        ? const _EmptyView()
                        : GridView.builder(
                          controller: scroll,
                          padding: const EdgeInsets.all(12),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: .72,
                              ),
                          itemCount: _items.length,
                          itemBuilder: (_, i) {
                            final item = _items[i];
                            if (item.isFolder) {
                              return _FolderTile(
                                folder: item,
                                onTap: () => _openFolder(item),
                              );
                            }
                            return _ImageTile(
                              file: item,
                              selected: _selected?.id == item.id,
                              onTap: () => setState(() => _selected = item),
                            );
                          },
                        ),
              ),

              // ── Botón confirmar ──────────────────────────────────────
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: FilledButton.icon(
                    onPressed: _selected != null ? _confirm : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF1D48B),
                      foregroundColor: const Color(0xFF14181F),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.check_rounded),
                    label: Text(
                      _selected != null
                          ? 'Usar "${_selected!.name}"'
                          : 'Seleccioná una imagen',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(999),
      ),
    ),
  );
}

class _SelectedPreview extends StatelessWidget {
  final DriveFile file;
  const _SelectedPreview({required this.file});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A212C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF1D48B).withOpacity(.4)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: MylNetworkImage(
              imageUrl: file.previewUrl,
              width: 56,
              height: 78,
              fit: BoxFit.cover,
              errorWidget:
                  (_, __, ___) => Container(
                    width: 56,
                    height: 78,
                    color: const Color(0xFF0E1117),
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white24,
                    ),
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Seleccionada:',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  file.name,
                  style: const TextStyle(
                    color: Color(0xFFF1D48B),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FolderTile extends StatelessWidget {
  final DriveFile folder;
  final VoidCallback onTap;
  const _FolderTile({required this.folder, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A212C),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.folder_rounded,
              color: Color(0xFFF1D48B),
              size: 42,
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                folder.name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white24,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageTile extends StatelessWidget {
  final DriveFile file;
  final bool selected;
  final VoidCallback onTap;
  const _ImageTile({
    required this.file,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFFF1D48B) : Colors.white10,
            width: selected ? 2 : 1,
          ),
          boxShadow:
              selected
                  ? [
                    BoxShadow(
                      color: const Color(0xFFF1D48B).withOpacity(.25),
                      blurRadius: 8,
                    ),
                  ]
                  : null,
        ),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: MylNetworkImage(
                imageUrl: file.previewUrl,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                placeholder:
                    (_, __) => Container(
                      color: const Color(0xFF0E1117),
                      child: const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFF1D48B),
                          ),
                        ),
                      ),
                    ),
                errorWidget:
                    (_, __, ___) => Container(
                      color: const Color(0xFF0E1117),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white24,
                            size: 28,
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              file.name,
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 9,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
              ),
            ),
            // nombre en la parte de abajo
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xCC000000), Colors.transparent],
                  ),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(11),
                  ),
                ),
                child: Text(
                  file.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    height: 1.2,
                  ),
                ),
              ),
            ),
            // checkmark cuando está seleccionada
            if (selected)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1D48B),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Color(0xFF14181F),
                    size: 14,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: Colors.white24,
              size: 48,
            ),
            const SizedBox(height: 12),
            const Text(
              'No se pudo cargar el Drive',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              error.contains('403') || error.contains('401')
                  ? 'Verificá que la carpeta sea pública y la API key esté configurada.'
                  : error,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();
  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.folder_open_rounded, color: Colors.white24, size: 48),
        SizedBox(height: 10),
        Text('Carpeta vacía', style: TextStyle(color: Colors.white38)),
      ],
    ),
  );
}

// ── Selector de wallpapers por raza (carpetas de nivel 1 + galería 16:9) ────
//
// A diferencia de showDriveImagePicker (navegación libre por carpetas), acá
// las carpetas de la raíz (razas) se listan una sola vez y quedan siempre
// visibles en una fila fija; tocar una abre una galería aparte con las
// imágenes de esa carpeta en miniaturas 16:9, con scroll horizontal y
// flechas para desplazarlo.

/// Carga las subcarpetas directas de [rootFolderId] (una sola vez) y las
/// devuelve como fila fija de chips. Al tocar una, abre la galería de esa
/// carpeta. Devuelve el resultado elegido, o null si se cancela.
Future<DrivePickResult?> showRaceWallpaperPicker(
  BuildContext context, {
  required String rootFolderId,
}) {
  return showModalBottomSheet<DrivePickResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RaceFolderRow(rootFolderId: rootFolderId),
  );
}

/// Abre directamente la galería 16:9 (scroll horizontal + flechas) de una
/// carpeta ya conocida — útil cuando el listado de carpetas de raza ya se
/// muestra embebido en otra pantalla (ej. fila fija en un diálogo propio).
Future<DrivePickResult?> showRaceGallery(
  BuildContext context, {
  required DriveFile folder,
}) {
  return showModalBottomSheet<DrivePickResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RaceGallerySheet(folder: folder),
  );
}

class _RaceFolderRow extends StatefulWidget {
  final String rootFolderId;
  const _RaceFolderRow({required this.rootFolderId});

  @override
  State<_RaceFolderRow> createState() => _RaceFolderRowState();
}

class _RaceFolderRowState extends State<_RaceFolderRow> {
  List<DriveFile> _folders = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await DriveService.listFolder(widget.rootFolderId);
      if (!mounted) return;
      setState(() => _folders = items.where((f) => f.isFolder).toList());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openRace(DriveFile folder) async {
    final result = await showModalBottomSheet<DrivePickResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RaceGallerySheet(folder: folder),
    );
    if (result != null && mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: .5,
      maxChildSize: .8,
      minChildSize: .3,
      expand: false,
      builder: (ctx, scroll) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF12161D),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const _SheetHandle(),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_open_rounded,
                      color: Color(0xFFF1D48B),
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Selecciona una raza',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white10),
              Expanded(
                child:
                    _loading
                        ? const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFFF1D48B),
                          ),
                        )
                        : _error != null
                        ? _ErrorView(error: _error!, onRetry: _load)
                        : _folders.isEmpty
                        ? const _EmptyView()
                        : GridView.builder(
                          controller: scroll,
                          padding: const EdgeInsets.all(12),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: .9,
                              ),
                          itemCount: _folders.length,
                          itemBuilder:
                              (_, i) => _FolderTile(
                                folder: _folders[i],
                                onTap: () => _openRace(_folders[i]),
                              ),
                        ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RaceGallerySheet extends StatefulWidget {
  final DriveFile folder;
  const _RaceGallerySheet({required this.folder});

  @override
  State<_RaceGallerySheet> createState() => _RaceGallerySheetState();
}

class _RaceGallerySheetState extends State<_RaceGallerySheet> {
  List<DriveFile> _images = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await DriveService.listFolder(widget.folder.id);
      if (!mounted) return;
      setState(() => _images = items.where((f) => f.isImage).toList());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _confirm(DriveFile file) {
    Navigator.of(context).pop(
      DrivePickResult(
        fileId: file.id,
        fileName: file.name,
        viewUrl: file.viewUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: .92,
      maxChildSize: .96,
      minChildSize: .5,
      expand: false,
      builder: (ctx, scroll) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF12161D),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const _SheetHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white70,
                        size: 18,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Volver',
                    ),
                    const Icon(
                      Icons.image_rounded,
                      color: Color(0xFFF1D48B),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.folder.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white10),
              Expanded(
                child:
                    _loading
                        ? const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFFF1D48B),
                          ),
                        )
                        : _error != null
                        ? _ErrorView(error: _error!, onRetry: _load)
                        : _images.isEmpty
                        ? const _EmptyView()
                        : LayoutBuilder(
                          builder: (context, constraints) {
                            final cols = constraints.maxWidth >= 640 ? 3 : 2;
                            return GridView.builder(
                              controller: scroll,
                              padding: const EdgeInsets.all(16),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: cols,
                                    mainAxisSpacing: 14,
                                    crossAxisSpacing: 14,
                                    childAspectRatio: 16 / 9,
                                  ),
                              itemCount: _images.length,
                              itemBuilder: (_, i) {
                                final file = _images[i];
                                return GestureDetector(
                                  onTap: () => _confirm(file),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        MylNetworkImage(
                                          imageUrl: file.previewUrl,
                                          fit: BoxFit.cover,
                                          placeholder:
                                              (_, __) => Container(
                                                color: const Color(0xFF0E1117),
                                              ),
                                          errorWidget:
                                              (_, __, ___) => Container(
                                                color: const Color(0xFF0E1117),
                                                child: const Icon(
                                                  Icons.broken_image_outlined,
                                                  color: Colors.white24,
                                                ),
                                              ),
                                        ),
                                        Positioned(
                                          left: 0,
                                          right: 0,
                                          bottom: 0,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 6,
                                            ),
                                            decoration: const BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.bottomCenter,
                                                end: Alignment.topCenter,
                                                colors: [
                                                  Color(0xCC000000),
                                                  Colors.transparent,
                                                ],
                                              ),
                                            ),
                                            child: Text(
                                              file.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
              ),
            ],
          ),
        );
      },
    );
  }
}
