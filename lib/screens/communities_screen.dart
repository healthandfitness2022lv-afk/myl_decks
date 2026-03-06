// ignore_for_file: use_build_context_synchronously

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';

import '../services/cloudinary_service.dart';

class CommunitiesScreen extends StatelessWidget {
  final String communityId;
  const CommunitiesScreen({super.key, required this.communityId});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Comunidad'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.forum), text: 'Foro'),
              Tab(icon: Icon(Icons.group), text: 'Miembros'),
              Tab(icon: Icon(Icons.video_library), text: 'Videos'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ForumTab(communityId: communityId),
            _MembersTab(communityId: communityId),
            _VideosTab(communityId: communityId),
          ],
        ),
      ),
    );
  }
}

// =====================
// Pestaña: FORO (DEBATES)
// =====================
class _ForumTab extends StatefulWidget {
  final String communityId;
  const _ForumTab({required this.communityId});

  @override
  State<_ForumTab> createState() => _ForumTabState();
}

class _ForumTabState extends State<_ForumTab> {
  final _titleCtrl = TextEditingController();
  final _textCtrl  = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _startDebate() async {
    final title = _titleCtrl.text.trim();
    final text  = _textCtrl.text.trim();
    if (title.isEmpty || text.isEmpty) return;

    setState(() => _sending = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      await FirebaseFirestore.instance
          .collection('communities')
          .doc(widget.communityId)
          .collection('posts')
          .add({
        'title': title,
        'text': text, // mensaje inicial
        'authorUid': user.uid,
        'authorName': user.displayName ?? user.email ?? 'Usuario',
        'createdAt': FieldValue.serverTimestamp(),
        'comments': 0,
        'likes': 0,
        'dislikes': 0,
      });
      _titleCtrl.clear();
      _textCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Debate iniciado')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _fmt(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
           '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final postsRef = FirebaseFirestore.instance
        .collection('communities')
        .doc(widget.communityId)
        .collection('posts')
        .orderBy('createdAt', descending: true);

    return Column(
      children: [
        // Iniciar debate
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Iniciar debate', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Título del debate',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _textCtrl,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Mensaje inicial',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _sending ? null : _startDebate,
                  icon: _sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.playlist_add),
                  label: const Text('Publicar debate'),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 0),
        // Lista de debates
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: postsRef.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) return const Center(child: Text('Aún no hay debates.'));

              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final id = docs[i].id;
                  final d  = docs[i].data();
                  final ts = (d['createdAt'] as Timestamp?)?.toDate();

                  return Card(
                    child: ListTile(
                      title: Text(d['title'] ?? 'Debate'),
                      subtitle: Text('${d['authorName'] ?? 'Usuario'} · ${_fmt(ts)}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.thumb_up_alt_outlined, size: 18),
                          const SizedBox(width: 4),
                          Text('${d['likes'] ?? 0}'),
                          const SizedBox(width: 10),
                          const Icon(Icons.thumb_down_alt_outlined, size: 18),
                          const SizedBox(width: 4),
                          Text('${d['dislikes'] ?? 0}'),
                          const SizedBox(width: 12),
                          const Icon(Icons.mode_comment_outlined, size: 18),
                          const SizedBox(width: 4),
                          Text('${d['comments'] ?? 0}'),
                        ],
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => _PostDetailsScreen(
                              communityId: widget.communityId,
                              postId: id,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PostDetailsScreen extends StatefulWidget {
  final String communityId;
  final String postId;
  const _PostDetailsScreen({required this.communityId, required this.postId});

  @override
  State<_PostDetailsScreen> createState() => _PostDetailsScreenState();
}

class _PostDetailsScreenState extends State<_PostDetailsScreen> {
  final _replyCtrl = TextEditingController();
  bool _sending = false;

  Future<void> _sendReply() async {
    final txt = _replyCtrl.text.trim();
    if (txt.isEmpty) return;
    setState(() => _sending = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final postRef = FirebaseFirestore.instance
          .collection('communities')
          .doc(widget.communityId)
          .collection('posts')
          .doc(widget.postId);

      final replyRef = postRef.collection('replies').doc();
      await FirebaseFirestore.instance.runTransaction((tx) async {
        tx.set(replyRef, {
          'text': txt,
          'authorUid': user.uid,
          'authorName': user.displayName ?? user.email ?? 'Usuario',
          'createdAt': FieldValue.serverTimestamp(),
        });
        tx.update(postRef, {'comments': FieldValue.increment(1)});
      });
      _replyCtrl.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final postRef = FirebaseFirestore.instance
        .collection('communities')
        .doc(widget.communityId)
        .collection('posts')
        .doc(widget.postId);

    final repliesRef = postRef.collection('replies').orderBy('createdAt', descending: true);

    return Scaffold(
      appBar: AppBar(title: const Text('Publicación')),
      body: Column(
        children: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: postRef.snapshots(),
            builder: (_, snap) {
              final d = snap.data?.data();
              if (d == null) return const SizedBox();
              final ts = (d['createdAt'] as Timestamp?)?.toDate();
              return Padding(
                padding: const EdgeInsets.all(12.0),
                child: Card(
                  child: ListTile(
                    title: Text(d['text'] ?? ''),
                    subtitle: Text(
                      '${d['authorName'] ?? 'Usuario'} · ${ts != null ? _fmt(ts) : '—'}',
                    ),
                  ),
                ),
              );
            },
          ),
          const Divider(height: 0),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _replyCtrl,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Responder…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _sending ? null : _sendReply,
                  icon: _sending
                      ? const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.reply),
                  label: const Text('Enviar'),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: repliesRef.snapshots(),
              builder: (_, snap) {
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text('Sin respuestas todavía.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final r = docs[i].data();
                    final ts = (r['createdAt'] as Timestamp?)?.toDate();
                    return Card(
                      child: ListTile(
                        title: Text(r['text'] ?? ''),
                        subtitle: Text(
                          '${r['authorName'] ?? 'Usuario'} · ${ts != null ? _fmt(ts) : '—'}',
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
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

// =====================
// Pestaña: MIEMBROS
// =====================
class _MembersTab extends StatelessWidget {
  final String communityId;
  const _MembersTab({required this.communityId});

  @override
  Widget build(BuildContext context) {
    final membersRef = FirebaseFirestore.instance
        .collection('communities')
        .doc(communityId)
        .collection('members')
        .orderBy('joinedAt', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: membersRef.snapshots(),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const Center(child: Text('No hay miembros aún.'));
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (_, i) {
            final m = docs[i].data();
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Text((m['name'] ?? 'U')[0].toString().toUpperCase()),
                ),
                title: Text(m['name'] ?? 'Usuario'),
                subtitle: Text(m['role'] ?? 'miembro'),
                trailing: m['active'] == false
                    ? const Chip(label: Text('Inactivo'))
                    : const SizedBox.shrink(),
              ),
            );
          },
        );
      },
    );
  }
}

// =====================
// Pestaña: VIDEOS (Cloudinary)
// =====================
class _VideosTab extends StatefulWidget {
  final String communityId;
  const _VideosTab({required this.communityId});

  @override
  State<_VideosTab> createState() => _VideosTabState();
}

class _VideosTabState extends State<_VideosTab> {
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
      withData: kIsWeb,
    );
    if (res == null || res.files.isEmpty) return;

    // 1) Pedir título y descripción antes de subir
    final meta = await showDialog<_VideoMeta>(
      context: context,
      builder: (_) => const _VideoMetaDialog(),
    );
    if (meta == null) return;

    setState(() => _uploading = true);
    try {
      final file = res.files.first;
      Map<String, String> up;

      if (kIsWeb) {
        final bytes = file.bytes!;
        up = await CloudinaryService.instance.uploadVideoUnsignedBytes(
          bytes: bytes,
          fileName: file.name,
          folder: 'myl_videos',
        );
      } else {
        final path = file.path;
        if (path == null || path.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo leer la ruta del video.')),
          );
          return;
        }
        up = await CloudinaryService.instance.uploadVideoUnsignedFile(
          filePath: path,
          fileName: file.name,
          folder: 'myl_videos',
        );
      }

      final secureUrl = up['url'];
      final publicId = up['publicId'];

      if (secureUrl == null || secureUrl.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Subida fallida: URL vacía.')),
        );
        return;
      }

      final user = FirebaseAuth.instance.currentUser!;
      await FirebaseFirestore.instance
          .collection('communities')
          .doc(widget.communityId)
          .collection('videos')
          .add({
        'url': secureUrl,
        'publicId': publicId,
        'title': meta.title,
        'description': meta.description,
        'uploadedBy': user.uid,
        'uploaderName': user.displayName ?? user.email ?? 'Usuario',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video subido con éxito.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error al subir: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final videosRef = FirebaseFirestore.instance
        .collection('communities')
        .doc(widget.communityId)
        .collection('videos')
        .orderBy('createdAt', descending: true);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              FilledButton.icon(
                onPressed: _uploading ? null : _pickAndUpload,
                icon: _uploading
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_upload),
                label: const Text('Subir video'),
              ),
              const SizedBox(width: 12),
              const Text('Sube y agrega un título/descripcion'),
            ],
          ),
        ),
        const Divider(height: 0),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: videosRef.snapshots(),
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) return const Center(child: Text('No hay videos aún.'));
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
  final v = docs[i].data();
  final dt = (v['createdAt'] as Timestamp?)?.toDate();
  return _VideoTile(
    url: v['url'] ?? '',
    publicId: v['publicId'],
    title: (v['title'] ?? 'Video').toString(),
    description: (v['description'] ?? '').toString(),
    uploaderName: (v['uploaderName'] ?? 'Usuario').toString(),
    date: dt,
  );
},

              );
            },
          ),
        ),
      ],
    );
  }
}

class _VideoMeta {
  final String title;
  final String description;
  const _VideoMeta(this.title, this.description);
}

class _VideoMetaDialog extends StatefulWidget {
  const _VideoMetaDialog();

  @override
  State<_VideoMetaDialog> createState() => _VideoMetaDialogState();
}

class _VideoMetaDialogState extends State<_VideoMetaDialog> {
  final _t = TextEditingController();
  final _d = TextEditingController();

  @override
  void dispose() {
    _t.dispose();
    _d.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Detalles del video'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _t,
              decoration: const InputDecoration(
                labelText: 'Título',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _d,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Descripción',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final title = _t.text.trim().isEmpty ? 'Video' : _t.text.trim();
            final desc = _d.text.trim();
            Navigator.pop(context, _VideoMeta(title, desc));
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}



class _VideoTile extends StatelessWidget {
  final String url;
  final String? publicId;
  final String title;
  final String description;
  final String uploaderName;
  final DateTime? date;

  const _VideoTile({
    required this.url,
    required this.title,
    required this.description,
    required this.uploaderName,
    this.publicId,
    this.date,
  });

  @override
  Widget build(BuildContext context) {
    // Miniatura (Cloudinary) o fallback
    Widget thumb;
    if (publicId != null && publicId!.isNotEmpty) {
      final thumbUrl = CloudinaryService.videoThumbnailUrl(
        publicId: publicId!,
        width: 640,
        height: 360,
      );
      thumb = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          thumbUrl,
          width: 120,
          height: 68,
          fit: BoxFit.cover,
        ),
      );
    } else {
      thumb = Container(
        width: 120,
        height: 68,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.ondemand_video, size: 38),
      );
    }

    final dateStr = date != null
        ? '${date!.day.toString().padLeft(2, '0')}/${date!.month.toString().padLeft(2, '0')} '
          '${date!.hour.toString().padLeft(2, '0')}:${date!.minute.toString().padLeft(2, '0')}'
        : null;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openPlayer(context),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              thumb,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Título (máx 1 línea)
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Descripción (máx 2 líneas)
                    if (description.isNotEmpty)
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.black87),
                      ),
                    const SizedBox(height: 6),
                    // “Compartido por … · fecha”
                    Row(
                      children: [
                        const Icon(Icons.person, size: 16, color: Colors.black54),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Compartido por $uploaderName'
                            '${dateStr != null ? ' · $dateStr' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.open_in_new, color: Colors.black54),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPlayer(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      showDragHandle: true,
      builder: (_) => _VideoPlayerSheet(url: url, title: title),
    );
  }
}


class _VideoPlayerSheet extends StatefulWidget {
  final String url;
  final String title;
  const _VideoPlayerSheet({required this.url, required this.title});

  @override
  State<_VideoPlayerSheet> createState() => _VideoPlayerSheetState();
}

class _VideoPlayerSheetState extends State<_VideoPlayerSheet> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    await c.initialize();
    setState(() {
      _controller = c;
      _ready = true;
    });
    c.play();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Hoja ajustable con altura máxima 90% de pantalla
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scroll) {
        return SingleChildScrollView(
          controller: scroll,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Título
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Text(
                    widget.title,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                // Player encajado a ancho con ratio original y altura limitada
                LayoutBuilder(
                  builder: (context, constraints) {
                    final maxW = constraints.maxWidth;
                    final ratio = (_ready && _controller!.value.aspectRatio > 0)
                        ? _controller!.value.aspectRatio
                        : (16 / 9);
                    // límite de altura para no “salirse”
                    final targetW = maxW;
                    final targetH = targetW / ratio;
                    final maxH = MediaQuery.of(context).size.height * 0.6;
                    final h = targetH.clamp(160.0, maxH);
                    return SizedBox(
                      width: targetW,
                      height: h,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: _ready
                              ? Stack(
                                  alignment: Alignment.bottomCenter,
                                  children: [
                                    VideoPlayer(_controller!),
                                    _ControlsOverlay(controller: _controller!),
                                  ],
                                )
                              : const Center(child: CircularProgressIndicator()),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                // Botones básicos
                Row(
                  children: [
                    IconButton(
                      onPressed: _ready ? () => _controller!.pause() : null,
                      icon: const Icon(Icons.pause, color: Colors.white),
                    ),
                    IconButton(
                      onPressed: _ready ? () => _controller!.play() : null,
                      icon: const Icon(Icons.play_arrow, color: Colors.white),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                    )
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ControlsOverlay extends StatelessWidget {
  final VideoPlayerController controller;
  const _ControlsOverlay({required this.controller});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => controller.value.isPlaying ? controller.pause() : controller.play(),
      child: Stack(
        children: <Widget>[
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            reverseDuration: const Duration(milliseconds: 200),
            child: controller.value.isPlaying
                ? const SizedBox.shrink()
                : const Center(
                    child: Icon(Icons.play_circle_fill, size: 64, color: Colors.white70),
                  ),
          ),
          VideoProgressIndicator(controller, allowScrubbing: true),
        ],
      ),
    );
  }
}

