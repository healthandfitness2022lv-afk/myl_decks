import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/card_myl.dart';
import './new_card_screen.dart';
import '../models/card_variant.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/app_constants.dart';
import '../widgets/drive_image_picker.dart';
import '../services/drive_service.dart';
import '../services/card_ai_job_service.dart';
import 'habilidades/card_habilidades_section.dart';

class CardDetailsScreen extends StatefulWidget {
  final CardMyL card;
  const CardDetailsScreen({super.key, required this.card});

  @override
  State<CardDetailsScreen> createState() => _CardDetailsScreenState();
}

class _CardDetailsScreenState extends State<CardDetailsScreen> {
  static const Map<String, String> _variantOptions = {
    'normal': 'Normal',
    'legendaria': 'Legendaria',
    'arte_alternativo': 'Arte alternativo',
    'full_art': 'Full art',
    'milenaria': 'Milenaria',
    'shogun': 'Shogun',
    'foil_lluvia': 'Foil lluvia',
    'jo': 'JO',
  };

  String? _selectedVariantId;
  bool _leyendoHabilidad = false;

  // Firestore
  late final DocumentReference<Map<String, dynamic>> _docRef;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _cardStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _variantsStream;

  // Cache anti-parpadeo
  List<CardVariant> _lastVariants = const [];

  @override
  void initState() {
    super.initState();
    _docRef = FirebaseFirestore.instance
        .collection('cards')
        .doc(widget.card.id);
    _cardStream = _docRef.snapshots();
    _variantsStream =
        _docRef.collection('variants').orderBy('name').snapshots();
  }

  Future<void> _setOfficialVariant(String variantId) async {
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final col = _docRef.collection('variants');
        final snap = await col.get();

        String? officialUrl;
        for (final d in snap.docs) {
          final isTarget = d.id == variantId;
          tx.set(d.reference, {'official': isTarget}, SetOptions(merge: true));
          if (isTarget) {
            final m = d.data();
            officialUrl = (m['imageFrontUrl'] as String?)?.trim();
          }
        }

        tx.set(_docRef, {
          'officialVariantId': variantId,
          if (officialUrl != null && officialUrl.isNotEmpty)
            'officialImageUrl': officialUrl
          else
            'officialImageUrl': FieldValue.delete(),
          'officialUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });

      if (_isAdmin) {
        unawaited(CardAiJobService.encolarLecturaAutomatica(widget.card.id));
      }

      if (!mounted) return;
      setState(() => _selectedVariantId = variantId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Variante marcada como oficial')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al marcar oficial: $e')));
    }
  }

  Future<void> _updateVariantType(CardVariant variant, String groupKey) async {
    final selectedGroupLabel = _variantOptions[groupKey] ?? 'Normal';
    try {
      await _docRef.collection('variants').doc(variant.id).set({
        'printType': selectedGroupLabel,
        if ((variant.name).trim().isEmpty || variant.name == variant.printType)
          'name': selectedGroupLabel,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tipo actualizado a $selectedGroupLabel')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al actualizar tipo: $e')));
    }
  }

  Future<void> _showVariantActions(CardVariant variant) async {
    final currentGroup = variant.groupKey;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF132126),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  variant.name.isEmpty ? 'Variante' : variant.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.star_rounded, color: Colors.amber),
                  title: const Text(
                    'Marcar como oficial',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _setOfficialVariant(variant.id);
                  },
                ),
                if (_isAdmin)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.drive_folder_upload_rounded,
                      color: Color(0xFF4FC3F7),
                    ),
                    title: const Text(
                      'Asignar imagen desde Drive',
                      style: TextStyle(color: Colors.white),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _assignDriveImageToVariant(variant);
                    },
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Cambiar tipo de variante',
                  style: TextStyle(
                    color: Color(0xFFF2D487),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      _variantOptions.entries.map((entry) {
                        final selected = entry.key == currentGroup;
                        return ChoiceChip(
                          label: Text(entry.value),
                          selected: selected,
                          onSelected: (_) {
                            Navigator.pop(context);
                            _updateVariantType(variant, entry.key);
                          },
                        );
                      }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _assignDriveImageToVariant(CardVariant variant) async {
    final result = await showDriveImagePicker(
      context,
      rootFolderId: DriveService.rootFolderId,
    );
    if (result == null || !mounted) return;

    try {
      await _docRef.collection('variants').doc(variant.id).set({
        'imageFrontUrl': result.viewUrl,
        'driveFileId': result.fileId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Si esta variante es la oficial, actualizar también officialImageUrl en el documento de la carta
      final cardSnap = await _docRef.get();
      final officialId = cardSnap.data()?['officialVariantId'] as String?;
      if (officialId == variant.id) {
        await _docRef.set({
          'officialImageUrl': result.viewUrl,
          'officialUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        if (_isAdmin) {
          unawaited(CardAiJobService.encolarLecturaAutomatica(widget.card.id));
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Imagen "${result.fileName}" asignada')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al asignar: $e')));
    }
  }

  static const String _ownerEmail = AppConstants.ownerEmail;

  bool get _isAdmin {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return email.toLowerCase() == _ownerEmail;
  }

  /// El texto oficial vive en el catálogo, no en un mazo.  Así se puede
  /// completar y programar una carta aunque todavía ningún mazo la use.
  Future<void> _editarTextoHabilidad(CardMyL card) async {
    final controller = TextEditingController(text: card.habilidad);
    final texto = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Habilidad de ${card.nombre}'),
            content: TextField(
              controller: controller,
              autofocus: true,
              minLines: 4,
              maxLines: 10,
              decoration: const InputDecoration(
                hintText: 'Escribe el texto impreso de la habilidad…',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: const Text('Guardar'),
              ),
            ],
          ),
    );
    controller.dispose();
    if (texto == null) return;

    try {
      await _docRef.set({
        'habilidad': texto,
        'habilidadUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Texto de habilidad guardado')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar la habilidad: $e')),
      );
    }
  }

  /// Reutiliza la misma cola que "Cartas por completar". El worker local
  /// transcribe solo el cuadro de habilidad y actualiza habilidadTextoIA.
  Future<void> _leerHabilidadConIa(CardMyL card) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _leyendoHabilidad = true);
    try {
      await FirebaseFirestore.instance.collection('card_ai_jobs').add({
        'ownerUid': user.uid,
        'tipo': 'leer',
        'cardIds': [card.id],
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Lectura solicitada. El worker la cargará desde la imagen.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo pedir la lectura: $e')),
      );
    } finally {
      if (mounted) setState(() => _leyendoHabilidad = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _cardStream,
      builder: (context, snapBase) {
        final data = snapBase.data?.data();
        final live =
            (data != null)
                ? CardMyL.fromMap(data, widget.card.id)
                : widget.card;
        final textoIa = '${data?['habilidadTextoIA'] ?? ''}'.trim();
        final tieneTexto =
            RegExp(
              r'\p{L}',
              unicode: true,
            ).allMatches('$textoIa ${live.habilidad}').length >=
            8;
        final tieneImagenOficial =
            '${data?['officialImageUrl'] ?? ''}'.trim().isNotEmpty;

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _variantsStream,
          builder: (context, snapVar) {
            // Variantes (fallback a cache)
            final liveVariants =
                (snapVar.hasData && (snapVar.data?.docs.isNotEmpty ?? false))
                    ? (() {
                      // Excluir variantes pendientes (approved == false) de la vista de detalle de carta.
                      // Tratamos `approved == null` como aprobada para compatibilidad con variantes antiguas.
                      final docs =
                          snapVar.data!.docs.where((d) {
                            final apro = d.data()['approved'];
                            return apro == null || apro == true;
                          }).toList();
                      return docs
                          .map((d) => CardVariant.fromMap(d.data(), d.id))
                          .toList();
                    })()
                    : _lastVariants;

            final variants = [...liveVariants]..sort((a, b) {
              final groupCmp = a.groupRank.compareTo(b.groupRank);
              if (groupCmp != 0) return groupCmp;
              if (a.isBase != b.isBase) return a.isBase ? -1 : 1;
              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            });

            // Oficial
            String? officialVariantId;
            if (snapVar.hasData && (snapVar.data?.docs.isNotEmpty ?? false)) {
              for (final d in snapVar.data!.docs) {
                final m = d.data();
                if (m['official'] == true) {
                  officialVariantId = d.id;
                  break;
                }
              }
            }
            // Variante a mostrar
            CardVariant? selectedVariant;
            if (_selectedVariantId != null && variants.isNotEmpty) {
              selectedVariant = variants.firstWhere(
                (v) => v.id == _selectedVariantId,
                orElse: () => variants.first,
              );
            } else if (officialVariantId != null && variants.isNotEmpty) {
              selectedVariant = variants.firstWhere(
                (v) => v.id == officialVariantId,
                orElse: () => variants.first,
              );
            } else {
              selectedVariant = variants.isNotEmpty ? variants.first : null;
            }

            if (snapVar.hasData && (snapVar.data?.docs.isNotEmpty ?? false)) {
              _lastVariants = variants;
            }

            return Scaffold(
              appBar: AppBar(
                backgroundColor: const Color(0xFF1A120C),
                centerTitle: true,
                title: Text(
                  live.nombre,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFF2D487),
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Color(0xFFF2D487)),
                    tooltip: 'Editar carta',
                    onPressed:
                        () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => NewCardScreen(initial: live),
                          ),
                        ),
                  ),
                ],
              ),
              floatingActionButton:
                  (variants.isEmpty)
                      ? FloatingActionButton.extended(
                        onPressed: () => _openNewVariantSheet(context, _docRef),
                        icon: const Icon(Icons.add),
                        label: const Text('Nueva variante'),
                      )
                      : null,
              body: LayoutBuilder(
                builder: (context, c) {
                  final isWide = c.maxWidth >= 980;

                  final left = _CardImagePanel(variant: selectedVariant);

                  final rightCard = _CardInfoPanel(
                    card: live,
                    variant: selectedVariant,
                    variants: variants,
                    selectedVariantId: selectedVariant?.id,
                    onSelectVariant:
                        (id) => setState(() => _selectedVariantId = id),
                    onMarkOfficial: _setOfficialVariant,
                    onEditVariant: _showVariantActions,
                    officialVariantId: officialVariantId,
                    onAddVariant: () => _openNewVariantSheet(context, _docRef),
                    onEditAbility:
                        _isAdmin ? () => _editarTextoHabilidad(live) : null,
                    aiAbilityText: textoIa,
                    onReadAbility:
                        _isAdmin &&
                                !_leyendoHabilidad &&
                                !tieneTexto &&
                                tieneImagenOficial
                            ? () => _leerHabilidadConIa(live)
                            : null,
                    readingAbility: _leyendoHabilidad,
                  );

                  return Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF0F181B), Color(0xFF13292D)],
                      ),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1200),
                          child:
                              isWide
                                  ? Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Flexible(
                                        flex: 4,
                                        child: Column(
                                          children: [
                                            _SectionCard(child: left),
                                            const SizedBox(height: 12),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Flexible(
                                        flex: 6,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            rightCard,
                                            if (_isAdmin) ...[
                                              const SizedBox(height: 12),
                                              CardHabilidadesSection(
                                                card: live,
                                                textoCarta:
                                                    textoIa.isEmpty
                                                        ? live.habilidad
                                                        : textoIa,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  )
                                  : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _SectionCard(child: left),
                                      const SizedBox(height: 12),
                                      rightCard,
                                      if (_isAdmin) ...[
                                        const SizedBox(height: 12),
                                        CardHabilidadesSection(
                                          card: live,
                                          textoCarta:
                                              textoIa.isEmpty
                                                  ? live.habilidad
                                                  : textoIa,
                                        ),
                                      ],
                                    ],
                                  ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  void _openNewVariantSheet(
    BuildContext context,
    DocumentReference<Map<String, dynamic>> cardRef,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NewVariantSheet(cardRef: cardRef),
    );
  }
}

// ===== Imagen =====
// ===== Imagen (mejorada: siempre ocupa el marco, con placeholder y carga) =====
class _CardImagePanel extends StatefulWidget {
  final CardVariant? variant;
  const _CardImagePanel({required this.variant});

  @override
  State<_CardImagePanel> createState() => _CardImagePanelState();
}

class _CardImagePanelState extends State<_CardImagePanel> {
  @override
  void didUpdateWidget(covariant _CardImagePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Si cambia la variante, forzamos rebuild (Image.network lo gestionará)
    if (oldWidget.variant?.imageFrontUrl != widget.variant?.imageFrontUrl ||
        oldWidget.variant?.fitPanelUrl(w: 600, h: 840) !=
            widget.variant?.fitPanelUrl(w: 600, h: 840)) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    const double cardAspect = 63 / 88;
    final panelUrl =
        widget.variant?.fitPanelUrl(w: 1200, h: 1680) ??
        widget.variant?.imageFrontUrl;

    return AspectRatio(
      aspectRatio: cardAspect,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: const Color(0xFF0E1C1E),
          child:
              (panelUrl == null || panelUrl.isEmpty)
                  ? const Center(
                    child: Text(
                      'Sin imagen',
                      style: TextStyle(color: Colors.white70),
                    ),
                  )
                  : Stack(
                    fit: StackFit.expand,
                    children: [
                      // DecorationImage-style fill para evitar que la imagen quede chica
                      // usamos Image.network directamente para poder mostrar loading/error builders
                      Image.network(
                        panelUrl,
                        fit: BoxFit.cover, // <--- importante: llena el marco
                        width: double.infinity,
                        height: double.infinity,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            color: const Color(0xFF0E1C1E),
                            child: const Center(
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          // si falla, mostramos la miniatura frontal si existe, o texto
                          final fallback =
                              widget.variant?.thumbUrl(w: 240, h: 336) ??
                              widget.variant?.imageFrontUrl;
                          if (fallback != null && fallback != panelUrl) {
                            return Image.network(
                              fallback,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                            );
                          }
                          return const Center(
                            child: Text(
                              'Error al cargar imagen',
                              style: TextStyle(color: Colors.white70),
                            ),
                          );
                        },
                        // evita que Flutter escale borrosamente en algunos casos
                        gaplessPlayback: true,
                      ),

                      // pequeña capa de overlay para mejorar contraste si la imagen es muy clara
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.04),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ],
                  ),
        ),
      ),
    );
  }
}

class _VariantsRow extends StatelessWidget {
  final CardMyL card;
  final List<CardVariant> variants;
  final String? selectedVariantId;
  final String? officialVariantId;
  final ValueChanged<String>? onSelectVariant;
  final ValueChanged<String>? onMarkOfficial;
  final ValueChanged<CardVariant>? onEditVariant;
  final VoidCallback? onAddVariant;

  const _VariantsRow({
    required this.card,
    required this.variants,
    this.selectedVariantId,
    this.officialVariantId,
    this.onSelectVariant,
    this.onMarkOfficial,
    this.onEditVariant,
    this.onAddVariant,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_mosaic_outlined,
                color: Colors.white70,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Variantes',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onAddVariant,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Nueva'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (variants.isEmpty)
            const Text(
              'Aún no hay variantes publicadas para esta carta.',
              style: TextStyle(color: Colors.white60),
            )
          else
            SizedBox(
              height: 122,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: variants.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final v = variants[index];
                  final isSel = v.id == selectedVariantId;
                  final isOfficial = v.id == officialVariantId;
                  final bestThumb =
                      v.thumbUrl(w: 160, h: 220) ?? v.imageFrontUrl;

                  return InkWell(
                    onTap: () => onSelectVariant?.call(v.id),
                    onLongPress: () {
                      onSelectVariant?.call(v.id);
                      onEditVariant?.call(v);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 92,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF101F22),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color:
                                      isSel
                                          ? const Color(0xFFF2D487)
                                          : Colors.white24,
                                  width: isSel ? 2 : 1,
                                ),
                              ),
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(11),
                                      child:
                                          bestThumb == null
                                              ? const ColoredBox(
                                                color: Color(0xFF1B3034),
                                                child: Icon(
                                                  Icons
                                                      .image_not_supported_outlined,
                                                  color: Colors.white54,
                                                ),
                                              )
                                              : Image.network(
                                                bestThumb,
                                                fit: BoxFit.cover,
                                              ),
                                    ),
                                  ),
                                  if (isOfficial)
                                    const Positioned(
                                      top: 6,
                                      right: 6,
                                      child: Icon(
                                        Icons.star_rounded,
                                        size: 18,
                                        color: Colors.amber,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            v.groupLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFFF2D487),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ===== Panel de información (detalles + características) =====
class _CardInfoPanel extends StatelessWidget {
  final CardMyL card;
  final CardVariant? variant;
  final List<CardVariant> variants;
  final String? selectedVariantId;
  final ValueChanged<String>? onSelectVariant;

  final String? officialVariantId;
  final ValueChanged<String>? onMarkOfficial;
  final ValueChanged<CardVariant>? onEditVariant;
  final VoidCallback? onAddVariant;
  final VoidCallback? onEditAbility;
  final VoidCallback? onReadAbility;
  final bool readingAbility;
  final String aiAbilityText;

  const _CardInfoPanel({
    required this.card,
    this.variant,
    this.variants = const [],
    this.selectedVariantId,
    this.onSelectVariant,
    this.officialVariantId,
    this.onMarkOfficial,
    this.onEditVariant,
    this.onAddVariant,
    this.onEditAbility,
    this.onReadAbility,
    this.readingAbility = false,
    this.aiAbilityText = '',
  });

  List<String> _getFeatures(CardMyL c) =>
      c.caracteristicasRaw.where((s) => s.trim().isNotEmpty).toList();

  Widget _infoTile(
    IconData icon,
    String label,
    String value, {
    bool highlight = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0E1C1E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white70),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // etiqueta pequeña (no bold)
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: Colors.white60),
                ),
                // valor en negrita como pediste
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    color: highlight ? Colors.cyanAccent : Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Bloque ancho para características, ahora con "chips" (burbujas)
  /// Bloque de características con "burbujas" oscuras y texto claro
  Widget _featuresBlock(BuildContext context, List<String> features) {
    final theme = Theme.of(context);
    final chipTextStyle =
        theme.textTheme.bodyMedium?.copyWith(color: Colors.white) ??
        const TextStyle(color: Colors.white, fontSize: 14);

    // Colores pensados para fondo oscuro: chip oscuro, texto claro, borde sutil
    const chipBg = Color(0xFF0B2B2A); // oscuro, mantiene la paleta verdosa
    const chipBorder = Color(
      0x1FFFFFFF,
    ); // borde muy sutil (blanco transparente)

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0E1C1E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.bolt, size: 18, color: Colors.white70),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Características Legacy',
                  style: TextStyle(fontSize: 11, color: Colors.white60),
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder:
                      (context, constraints) => Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            features.map((f) {
                              final txt = f.trim();
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: chipBg,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: chipBorder),
                                ),
                                constraints: BoxConstraints(
                                  minHeight: 28,
                                  maxWidth: constraints.maxWidth,
                                ),
                                child: Text(
                                  txt,
                                  style: chipTextStyle.copyWith(fontSize: 13),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _abilityBlock() {
    final textoIa = aiAbilityText.trim();
    final texto = textoIa.isEmpty ? card.habilidad.trim() : textoIa;
    final sinTexto = texto.isEmpty;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0E1C1E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: sinTexto ? Colors.amber.withValues(alpha: .3) : Colors.white10,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome, size: 18, color: Color(0xFFF2D487)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Habilidad',
                  style: TextStyle(fontSize: 11, color: Colors.white60),
                ),
                const SizedBox(height: 4),
                Text(
                  sinTexto ? 'Sin texto de habilidad cargado.' : texto,
                  style: TextStyle(
                    color: sinTexto ? Colors.white38 : Colors.white70,
                    fontStyle: sinTexto ? FontStyle.italic : FontStyle.normal,
                    height: 1.35,
                  ),
                ),
                if (textoIa.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Texto leído desde la imagen con IA',
                      style: TextStyle(fontSize: 11, color: Color(0xFF7DD3FC)),
                    ),
                  ),
              ],
            ),
          ),
          if (onReadAbility != null || readingAbility)
            IconButton(
              tooltip: 'Leer habilidad desde la imagen con IA',
              onPressed: onReadAbility,
              icon:
                  readingAbility
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.document_scanner_outlined),
              color: const Color(0xFF7DD3FC),
            ),
          if (onEditAbility != null)
            IconButton(
              tooltip: sinTexto ? 'Cargar habilidad' : 'Editar habilidad',
              onPressed: onEditAbility,
              icon: Icon(
                sinTexto ? Icons.add_circle_outline : Icons.edit_outlined,
              ),
              color: const Color(0xFFF2D487),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fuerza = card.fuerza;
    final coste = card.coste;
    final feats = _getFeatures(card);

    // sacamos features de la grilla para que ocupen todo el ancho
    final items = <Widget>[
      _infoTile(Icons.category, 'Tipo', card.tipo),
      if (card.esAliado && fuerza != null)
        _infoTile(Icons.fitness_center, 'Fuerza', '$fuerza'),
      _infoTile(Icons.monetization_on, 'Coste de oro', '$coste'),
      if (card.esAliado && (card.raza?.isNotEmpty ?? false))
        _infoTile(Icons.pets, 'Raza', card.raza!, highlight: true),
      _infoTile(Icons.star_half, 'Frecuencia', card.rareza),
      _infoTile(Icons.layers, 'Edición', card.edicion),
      if ((variant?.code ?? '').isNotEmpty)
        _infoTile(Icons.qr_code_2, 'Código', variant!.code!),
    ];

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // grilla de detalles (sin características)
          LayoutBuilder(
            builder: (context, c) {
              final colCount = c.maxWidth >= 620 ? 2 : 1;
              return GridView.builder(
                itemCount: items.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: colCount,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 3.6,
                ),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (_, i) => items[i],
              );
            },
          ),

          const SizedBox(height: 12),

          // bloque ancho con chips
          if (feats.isNotEmpty) _featuresBlock(context, feats),

          if (feats.isNotEmpty) const SizedBox(height: 12),

          // Siempre visible, incluso si la carta aún no está en un mazo.
          _abilityBlock(),

          const SizedBox(height: 16),

          // variantes debajo
          _VariantsRow(
            card: card,
            variants: variants,
            selectedVariantId: selectedVariantId,
            officialVariantId: officialVariantId,
            onSelectVariant: onSelectVariant,
            onMarkOfficial: onMarkOfficial,
            onEditVariant: onEditVariant,
            onAddVariant: onAddVariant,
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF132126),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.white10),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

// ===== Hoja para crear una nueva variante =====
class _NewVariantSheet extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> cardRef;
  const _NewVariantSheet({required this.cardRef});

  @override
  State<_NewVariantSheet> createState() => _NewVariantSheetState();
}

class _NewVariantSheetState extends State<_NewVariantSheet> {
  String _variantGroup = 'normal';
  String? _imageUrl;
  bool _saving = false;

  static const Map<String, String> _variantOptions =
      _CardDetailsScreenState._variantOptions;

  Future<void> _pickFromDrive() async {
    final result = await showDriveImagePicker(
      context,
      rootFolderId: DriveService.rootFolderId,
    );
    if (result == null || !mounted) return;
    setState(() => _imageUrl = result.viewUrl);
  }

  Future<void> _save() async {
    if (_imageUrl == null || _imageUrl!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sube una imagen antes de guardar')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Debes iniciar sesión');

      // Obtener rol desde Firestore (fallback a 'basico')
      final userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
      final role = userDoc.data()?['role']?.toString() ?? 'basico';
      final isAdmin = role == 'administrador';
      final isOwner = (user.email ?? '').toLowerCase() == _ownerEmailLocal;

      final selectedGroupLabel = _variantOptions[_variantGroup] ?? 'Normal';
      final approvedFlag = (isAdmin || isOwner);

      final payload = <String, dynamic>{
        'name': selectedGroupLabel,
        'printType': selectedGroupLabel,
        'imageFrontUrl': _imageUrl,
        'imageSource': 'drive',
        'approved': approvedFlag,
        'status': approvedFlag ? 'approved' : 'pending',
        // Nunca marcar como oficial/base por defecto: solo debe quedar como
        // vista previa del catálogo si un admin la marca explícitamente
        // desde "Marcar como oficial". Sin esto, Firestore excluye estos
        // docs de los orderBy('official')/orderBy('isBase') del catálogo,
        // lo que en cartas sin ninguna variante ya marcada hacía que la
        // última variante subida terminara mostrándose como si fuera la
        // oficial.
        'official': false,
        'isBase': false,
        'submittedBy': user.uid,
        'submittedByEmail': user.email,
        'createdAt': FieldValue.serverTimestamp(),
      };

      await widget.cardRef.collection('variants').add(payload);

      if (!mounted) return;
      Navigator.pop(context);

      if (approvedFlag) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Variante creada y publicada')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Variante enviada para revisión')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error guardando: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static const String _ownerEmailLocal = AppConstants.ownerEmail;

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: Material(
        color: const Color(0xFF13292D),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.layers, color: Color(0xFFF2D487)),
                    const SizedBox(width: 8),
                    Text(
                      'Nueva variante',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Sube la imagen y define el tipo de impresión.',
                  style: TextStyle(color: Colors.white70, height: 1.35),
                ),
                const SizedBox(height: 14),

                DropdownButtonFormField<String>(
                  value: _variantGroup,
                  dropdownColor: const Color(0xFF0E1C1E),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Tipo de variante',
                  ),
                  items:
                      _variantOptions.entries
                          .map(
                            (entry) => DropdownMenuItem<String>(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                  onChanged:
                      _saving
                          ? null
                          : (value) {
                            if (value == null) return;
                            setState(() => _variantGroup = value);
                          },
                ),

                const SizedBox(height: 14),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E1C1E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _pickFromDrive,
                        icon: const Icon(
                          Icons.drive_folder_upload_rounded,
                          size: 18,
                        ),
                        label: Text(
                          _imageUrl == null
                              ? 'Buscar en Drive'
                              : 'Cambiar imagen',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF4FC3F7),
                          side: const BorderSide(color: Color(0x664FC3F7)),
                        ),
                      ),
                      if (_imageUrl != null) ...[
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            _imageUrl!,
                            height: 120,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF2D487),
                      foregroundColor: const Color(0xFF1A120C),
                    ),
                    icon:
                        _saving
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.save),
                    label: Text(_saving ? 'Guardando…' : 'Guardar variante'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
