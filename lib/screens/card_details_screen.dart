import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/card_myl.dart';
import '../services/cloudinary_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import './new_card_screen.dart';
import '../models/card_variant.dart';
import 'package:firebase_auth/firebase_auth.dart';


class CardDetailsScreen extends StatefulWidget {
  final CardMyL card;
  const CardDetailsScreen({super.key, required this.card});

  @override
  State<CardDetailsScreen> createState() => _CardDetailsScreenState();
}

class _CardDetailsScreenState extends State<CardDetailsScreen> {
  String? _selectedVariantId;

  // Firestore
  late final DocumentReference<Map<String, dynamic>> _docRef;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _cardStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _variantsStream;

  // Cache anti-parpadeo
  List<CardVariant> _lastVariants = const [];

   @override
  void initState() {
    super.initState();
    _docRef = FirebaseFirestore.instance.collection('cards').doc(widget.card.id);
    _cardStream = _docRef.snapshots();
    _variantsStream = _docRef.collection('variants').orderBy('name').snapshots();
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

        tx.set(
          _docRef,
          {
            'officialVariantId': variantId,
            if (officialUrl != null && officialUrl.isNotEmpty)
              'officialImageUrl': officialUrl
            else
              'officialImageUrl': FieldValue.delete(),
            'officialUpdatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });

      if (!mounted) return;
      setState(() => _selectedVariantId = variantId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Variante marcada como oficial')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error al marcar oficial: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _cardStream,
      builder: (context, snapBase) {
        final data = snapBase.data?.data();
        final live = (data != null) ? CardMyL.fromMap(data, widget.card.id) : widget.card;

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _variantsStream,
          builder: (context, snapVar) {
            // Variantes (fallback a cache)
            final liveVariants = (snapVar.hasData && (snapVar.data?.docs.isNotEmpty ?? false))
    ? (() {
        // Excluir variantes pendientes (approved == false) de la vista de detalle de carta.
        // Tratamos `approved == null` como aprobada para compatibilidad con variantes antiguas.
        final docs = snapVar.data!.docs.where((d) {
          final apro = d.data()['approved'];
          return apro == null || apro == true;
        }).toList();
        return docs.map((d) => CardVariant.fromMap(d.data(), d.id)).toList();
      })()
    : _lastVariants;



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
            final variants = liveVariants;
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
                backgroundColor: Colors.amber.shade300,
                centerTitle: true,
                title: Text(live.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    tooltip: 'Editar carta',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => NewCardScreen(initial: live)),
                    ),
                  ),// ❤️ Wishlist por VARIANTE (usa selectedVariant)
if (selectedVariant != null)
  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: WishlistService.docStream(
      cardId: live.id,                   // tu CardMyL debería tener .id
      variantId: selectedVariant.id,    // la variante elegida
    ),
    builder: (context, snapWish) {
      final exists = snapWish.data?.exists ?? false;

      return IconButton(
        tooltip: exists
            ? 'Quitar esta variante de tu lista'
            : 'Agregar esta variante a tu lista',
        icon: Icon(
          exists ? Icons.favorite : Icons.favorite_border,
          color: exists ? Colors.redAccent : null,
        ),
        onPressed: () async {
          if (exists) {
            await WishlistService.removeExactVariant(
              cardId: live.id,
              variantId: selectedVariant!.id,
            );
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Quitada de tu lista de deseos')),
            );
          } else {
            // Elige la mejor imagen de la variante
            final bestImg = selectedVariant!.thumbUrl(w: 240, h: 336)
                ?? selectedVariant.imageFrontUrl;

            await WishlistService.addExactVariant(
              cardId: live.id,
              cardName: live.nombre,
              edition: live.edicion,
              printType: '',                         
              variantId: selectedVariant.id,
              variantName: selectedVariant.name,
              variantCode: selectedVariant.code,
              imageUrl: bestImg,
              desiredQty: 1,
            );
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Agregada a tu lista de deseos')),
            );
          }
        },
      );
    },
  ),

                ],
              ),
              floatingActionButton: (variants.isEmpty)
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
                    onSelectVariant: (id) => setState(() => _selectedVariantId = id),
                    onMarkOfficial: _setOfficialVariant,
                    officialVariantId: officialVariantId,
                    onAddVariant: () => _openNewVariantSheet(context, _docRef),
                  );

                  return Container(
                    color: const Color(0xFF112528),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1200),
                          child: isWide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                    Flexible(flex: 6, child: rightCard),
                                  ],
                                )
                              : ListView(
                                  children: [
                                    _SectionCard(child: left),
                                    const SizedBox(height: 12),
                                    _SectionCard(
                                      child: _VariantsRow(
                                        card: live,
                                        variants: variants,
                                        selectedVariantId: selectedVariant?.id,
                                        officialVariantId: officialVariantId,
                                        onSelectVariant: (id) => setState(() => _selectedVariantId = id),
                                        onMarkOfficial: _setOfficialVariant,
                                        onAddVariant: () => _openNewVariantSheet(context, _docRef),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    rightCard,
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
        oldWidget.variant?.fitPanelUrl(w: 600, h: 840) != widget.variant?.fitPanelUrl(w: 600, h: 840)) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    const double cardAspect = 63 / 88;
    final panelUrl = widget.variant?.fitPanelUrl(w: 1200, h: 1680) ?? widget.variant?.imageFrontUrl;

    return AspectRatio(
      aspectRatio: cardAspect,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: const Color(0xFF0E1C1E),
          child: (panelUrl == null || panelUrl.isEmpty)
              ? const Center(
                  child: Text('Sin imagen', style: TextStyle(color: Colors.white70)),
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
                            child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        // si falla, mostramos la miniatura frontal si existe, o texto
                        final fallback = widget.variant?.thumbUrl(w: 240, h: 336) ?? widget.variant?.imageFrontUrl;
                        if (fallback != null && fallback != panelUrl) {
                          return Image.network(fallback, fit: BoxFit.cover, width: double.infinity, height: double.infinity);
                        }
                        return const Center(child: Text('Error al cargar imagen', style: TextStyle(color: Colors.white70)));
                      },
                      // evita que Flutter escale borrosamente en algunos casos
                      gaplessPlayback: true,
                    ),

                    // pequeña capa de overlay para mejorar contraste si la imagen es muy clara
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.transparent, Colors.black.withOpacity(0.04)],
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
  final VoidCallback? onAddVariant;

  const _VariantsRow({
    required this.card,
    required this.variants,
    this.selectedVariantId,
    this.officialVariantId,
    this.onSelectVariant,
    this.onMarkOfficial,
    this.onAddVariant,
  });

  @override
  Widget build(BuildContext context) {
    final total = variants.length;

    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: total + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i == total) {
            return InkWell(
              onTap: onAddVariant,
              child: Container(
                width: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF0E1C1E),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24, width: 1),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.add, color: Colors.white70),
              ),
            );
          }

        

          final v = variants[i];
          final isSel = v.id == selectedVariantId;
          final isOfficial = (v.id == officialVariantId);
          final bestThumb = v.thumbUrl(w: 120, h: 160) ?? v.imageFrontUrl;

          return InkWell(
            onTap: () => onSelectVariant?.call(v.id),
            onLongPress: () {
              onMarkOfficial?.call(v.id);
              onSelectVariant?.call(v.id);
            },
            child: Stack(
              children: [
                Container(
                  width: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E1C1E),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSel ? Colors.cyanAccent : Colors.white24,
                      width: isSel ? 2 : 1,
                    ),
                  ),
                  child: bestThumb == null
                      ? Center(child: Text(v.name, style: const TextStyle(color: Colors.white70, fontSize: 10)))
                      : Image.network(bestThumb, fit: BoxFit.cover),
                ),
                if (isOfficial)
                  const Positioned(
                    top: 2,
                    right: 2,
                    child: Icon(Icons.star, size: 16, color: Colors.amber),
                  ),
              ],
            ),
          );
        },
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
  final VoidCallback? onAddVariant;

  const _CardInfoPanel({
    required this.card,
    this.variant,
    this.variants = const [],
    this.selectedVariantId,
    this.onSelectVariant,
    this.officialVariantId,
    this.onMarkOfficial,
    this.onAddVariant,
  });

  List<String> _getFeatures(CardMyL c) =>
      c.caracteristicasRaw.where((s) => s.trim().isNotEmpty).toList();

  Widget _infoTile(IconData icon, String label, String value, {bool highlight = false}) {
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
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.white60)),
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
  final chipTextStyle = theme.textTheme.bodyMedium?.copyWith(color: Colors.white) ??
      const TextStyle(color: Colors.white, fontSize: 14);

  // Colores pensados para fondo oscuro: chip oscuro, texto claro, borde sutil
  const chipBg = Color(0xFF0B2B2A); // oscuro, mantiene la paleta verdosa
  const chipBorder = Color(0x1FFFFFFF); // borde muy sutil (blanco transparente)

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
              const Text('Habilidades', style: TextStyle(fontSize: 11, color: Colors.white60)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: features.map((f) {
                  final txt = f.trim();
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: chipBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: chipBorder),
                    ),
                    constraints: const BoxConstraints(minHeight: 28),
                    child: Text(
                      txt,
                      style: chipTextStyle.copyWith(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
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
      if (card.esAliado && fuerza != null) _infoTile(Icons.fitness_center, 'Fuerza', '$fuerza'),
      _infoTile(Icons.monetization_on, 'Coste de oro', '$coste'),
      if (card.esAliado && (card.raza?.isNotEmpty ?? false))
        _infoTile(Icons.pets, 'Raza', card.raza!, highlight: true),
      _infoTile(Icons.star_half, 'Frecuencia', card.rareza),
      _infoTile(Icons.layers, 'Edición', card.edicion),
      if ((variant?.code ?? '').isNotEmpty) _infoTile(Icons.qr_code_2, 'Código', variant!.code!),
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

          const SizedBox(height: 16),

          // variantes debajo
          _VariantsRow(
            card: card,
            variants: variants,
            selectedVariantId: selectedVariantId,
            officialVariantId: officialVariantId,
            onSelectVariant: onSelectVariant,
            onMarkOfficial: onMarkOfficial,
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
      color: const Color(0xFF13292D),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
  final _form = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _official = false;
  String? _imageUrl;
  String? _cloudinaryId;
  bool _saving = false;


  Future<void> _pickImage() async {
    try {
      Map r;

      if (kIsWeb) {
        final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
        if (result == null || result.files.first.bytes == null) return;
        final f = result.files.first;
        r = await CloudinaryService.uploadFromBytes(f.bytes!, filename: f.name);
      } else {
        final picker = ImagePicker();
        final XFile? x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
        if (x == null) return;
        r = await CloudinaryService.uploadFromPath(x.path, filename: x.name);
      }

      final secure = (r['secure_url'] ?? r['url'] ?? r['secureUrl'] ?? r['secureURL'])?.toString();
      final pubId  = (r['public_id']  ?? r['publicId'])?.toString();

      if (secure == null || secure.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se recibió URL de Cloudinary')),
        );
        return;
      }

      if (!mounted) return;
      setState(() {
        _imageUrl = secure;
        _cloudinaryId = pubId;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error subiendo: $e')));
    }
  }
  

    Future<void> _save() async {
    final ok = _form.currentState?.validate() ?? false;
    if (!ok) return;

    if (_imageUrl == null || _imageUrl!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sube una imagen antes de guardar')));
      return;
    }

    setState(() => _saving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Debes iniciar sesión');

      // Obtener rol desde Firestore (fallback a 'basico')
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final role = userDoc.data()?['role']?.toString() ?? 'basico';
      final isAdmin = role == 'administrador';
      final isOwner = (user.email ?? '').toLowerCase() == _ownerEmailLocal;

      final name = _nameCtrl.text.trim();
      final code = _codeCtrl.text.trim();

      // Si no es admin/owner, ignoramos la casilla 'official' y marcamos como pendiente
      final willBeOfficial = (_official && (isAdmin || isOwner));
      final approvedFlag = (isAdmin || isOwner);

      final payload = <String, dynamic>{
        'name': name,
        if (code.isNotEmpty) 'code': code,
        'imageFrontUrl': _imageUrl,
        if (_cloudinaryId != null) 'cloudinaryPublicId': _cloudinaryId,
        if (willBeOfficial) 'official': true,
        // meta de validación
        'approved': approvedFlag, // true para admin/owner, false para otros
        'status': approvedFlag ? 'approved' : 'pending',
        'submittedBy': user.uid,
        'submittedByEmail': user.email,
        'createdAt': FieldValue.serverTimestamp(),
      };

      final newRef = await widget.cardRef.collection('variants').add(payload);

      if (willBeOfficial) {
        // desmarca otras
        final col = widget.cardRef.collection('variants');
        final snap = await col.get();
        final batch = FirebaseFirestore.instance.batch();
        for (final d in snap.docs) {
          if (d.id != newRef.id) {
            batch.set(d.reference, {'official': false}, SetOptions(merge: true));
          }
        }
        await batch.commit();

        // denormaliza
        await widget.cardRef.set({
          'officialVariantId': newRef.id,
          'officialImageUrl': _imageUrl,
          'officialUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (!mounted) return;
      Navigator.pop(context);

      if (approvedFlag) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Variante creada y publicada')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Variante enviada para revisión')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error guardando: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

    static const String _ownerEmailLocal = 'hecturnicolas@gmail.com';



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
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.layers, color: Colors.white70),
                      const SizedBox(width: 8),
                      Text('Nueva variante',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
                      const Spacer(),
                      IconButton(
                        onPressed: _saving ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Variante'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),

                  const SizedBox(height: 8),

                  TextFormField(
                    controller: _codeCtrl,
                    decoration: const InputDecoration(labelText: 'Código (opcional)'),
                  ),

                  const SizedBox(height: 8),

                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _saving ? null : _pickImage,
                        icon: const Icon(Icons.image),
                        label: const Text('Subir imagen'),
                      ),
                      const SizedBox(width: 12),
                      if (_imageUrl != null)
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              _imageUrl!.contains('res.cloudinary.com')
                                  ? _imageUrl!.replaceFirst('/upload/', '/upload/f_auto,q_auto,w_160,h_120,c_fill,g_auto/')
                                  : _imageUrl!,
                              height: 60,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Row(
  children: [
    Checkbox(
      value: _official,
      onChanged: _saving ? null : (v) => setState(() => _official = v ?? false),
    ),
    const SizedBox(width: 4),
    const Text('Marcar como oficial'),
  ],
),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save),
                      label: Text(_saving ? 'Guardando…' : 'Guardar variante'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WishlistService {
  static String _uid() => FirebaseAuth.instance.currentUser?.uid ?? '';

  /// Usamos un ID compuesto para que cada (carta, variante) sea único
  static String docIdFor(String cardId, String variantId) => '${cardId}__${variantId}';

  static CollectionReference<Map<String, dynamic>> _col(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('wishlist');

  static Stream<DocumentSnapshot<Map<String, dynamic>>> docStream({
    required String cardId,
    required String variantId,
  }) {
    final uid = _uid();
    if (uid.isEmpty) return const Stream.empty();
    final id = docIdFor(cardId, variantId);
    return _col(uid).doc(id).snapshots();
  }

  static Future<void> addExactVariant({
    required String cardId,
    required String cardName,
    required String edition,
    required String printType,       // si no lo manejas aún, pasa '' (string vacío)
    required String variantId,
    required String variantName,
    String? variantCode,
    String? imageUrl,                // miniatura o imagen frontal de la variante
    int desiredQty = 1,
  }) async {
    final uid = _uid();
    if (uid.isEmpty) return;
    final id = docIdFor(cardId, variantId);

    await _col(uid).doc(id).set({
      'cardId': cardId,
      'name': cardName,
      'edition': edition,
      'printType': printType,
      'variantId': variantId,
      'variantName': variantName,
      if (variantCode != null && variantCode.isNotEmpty) 'code': variantCode,
      if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
      'desiredQty': desiredQty,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> removeExactVariant({
    required String cardId,
    required String variantId,
  }) async {
    final uid = _uid();
    if (uid.isEmpty) return;
    final id = docIdFor(cardId, variantId);
    await _col(uid).doc(id).delete();
  }
}
