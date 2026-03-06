import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

String _makeChatId(String a, String b) {
  final ordered = (a.compareTo(b) <= 0) ? '$a\_$b' : '$b\_$a';
  return ordered;
}

Future<String> createOrGetChatId(String uidA, String uidB) async {
  final chatId = _makeChatId(uidA, uidB);
  final ref = FirebaseFirestore.instance.collection('chats').doc(chatId);
  final snap = await ref.get();
  if (!snap.exists) {
    await ref.set({
      'participants': [uidA, uidB],
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessage': null,
    });
  }
  return chatId;
}

class UserProfileScreen extends StatelessWidget {
  final String userUid;
  const UserProfileScreen({super.key, required this.userUid});

  @override
  Widget build(BuildContext context) {
    final users = FirebaseFirestore.instance.collection('users');
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: users.doc(userUid).get(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final data = snap.data!.data();
          if (data == null) return const Center(child: Text('Usuario no encontrado'));
          final name = (data['displayName'] ?? 'Usuario').toString();
          final username = (data['username'] ?? '').toString();
          final email = (data['email'] ?? '').toString();
          final photo = (data['photoUrl'] ?? '').toString();

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundImage: photo.isNotEmpty ? NetworkImage(photo) as ImageProvider : null,
                  child: photo.isEmpty ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'U', style: const TextStyle(fontSize: 28)) : null,
                ),
                const SizedBox(height: 12),
                Text(name, style: Theme.of(context).textTheme.headlineSmall),
                if (username.isNotEmpty) Text('@$username', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey)),
                const SizedBox(height: 8),
                if (email.isNotEmpty) Text(email),
                const SizedBox(height: 20),
                FilledButton.icon(
                  icon: const Icon(Icons.message),
                  label: const Text('Enviar mensaje'),
                  onPressed: () async {
                    final meUid = FirebaseAuth.instance.currentUser!.uid;
                    final chatId = await createOrGetChatId(meUid, userUid);
                    if (context.mounted) {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ChatScreen(chatId: chatId, otherUid: userUid),
                      ));
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String otherUid;
  const ChatScreen({super.key, required this.chatId, required this.otherUid});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  String get _meUid => FirebaseAuth.instance.currentUser!.uid;

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    final msgsRef = FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages');
    final doc = msgsRef.doc();
    final now = FieldValue.serverTimestamp();
    await doc.set({
      'id': doc.id,
      'from': _meUid,
      'text': text.trim(),
      'createdAt': now,
    });
    // actualizar meta del chat
    await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).set({
      'lastMessage': text.trim(),
      'lastAt': now,
    }, SetOptions(merge: true));
    _ctrl.clear();
    // scrollear al final (con delay)
    await Future.delayed(const Duration(milliseconds: 100));
    if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Widget _bubble(Map<String, dynamic> m) {
    final from = (m['from'] ?? '') as String;
    final text = (m['text'] ?? '').toString();
    final me = from == _meUid;
    final align = me ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final color = me ? Theme.of(context).colorScheme.primary : Colors.grey.shade200;
    final txtColor = me ? Colors.white : Colors.black87;

    return Column(
      crossAxisAlignment: align,
      children: [
        Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(text, style: TextStyle(color: txtColor)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatRef = FirebaseFirestore.instance.collection('chats').doc(widget.chatId);
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: chatRef.collection('messages').orderBy('createdAt', descending: false).snapshots(),
              builder: (context, snap) {
                if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snap.data!.docs;
                if (docs.isEmpty) return const Center(child: Text('Inicio de conversación. Envía el primer mensaje.'));
                return ListView.builder(
                  controller: _scroll,
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final m = docs[i].data();
                    return _bubble(m);
                  },
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (v) => _sendMessage(v),
                    decoration: const InputDecoration.collapsed(hintText: 'Escribe un mensaje...'),
                  ),
                ),
                IconButton(
                  onPressed: () => _sendMessage(_ctrl.text),
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class _FriendsScreenState extends State<FriendsScreen> {
  final _q = TextEditingController();
  String _term = '';

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _sendInvite(String toUid, String toName) async {
    if (toUid == _uid) return;
    final id = '${_uid}_$toUid';
    final ref = FirebaseFirestore.instance.collection('friend_requests').doc(id);

    final snap = await ref.get();
    if (snap.exists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ya existe una invitación con este usuario')),
        );
      }
      return;
    }

    // Denormalizar nombre mío
    final meDoc = await FirebaseFirestore.instance.collection('users').doc(_uid).get();
    final myName = (meDoc.data()?['displayName'] ?? 'Yo').toString();

    await ref.set({
      'fromUid': _uid,
      'fromName': myName,
      'toUid': toUid,
      'toName': toName,
      'status': 'pending', // pending | accepted | rejected
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invitación enviada')),
      );
    }
  }

  Future<void> _acceptInvite(DocumentReference docRef) async {
    final reqSnap = await docRef.get();
    final req = reqSnap.data() as Map<String, dynamic>?;

    if (req == null) return;

    final fromUid = req['fromUid'] as String; // quien envió
    final toUid = req['toUid'] as String; // quien recibe (tú)

    final users = FirebaseFirestore.instance.collection('users');
    final meDoc = await users.doc(toUid).get();
    final otherDoc = await users.doc(fromUid).get();

    final myName = (meDoc.data()?['displayName'] ?? 'Yo').toString();
    final myUserName = (meDoc.data()?['username'] ?? '').toString();

    final otherName = (otherDoc.data()?['displayName'] ?? 'Usuario').toString();
    final otherUserName = (otherDoc.data()?['username'] ?? '').toString();

    final batch = FirebaseFirestore.instance.batch();

    final myFriendsRef = users.doc(toUid).collection('friends').doc(fromUid);
    batch.set(myFriendsRef, {
      'friendUid': fromUid,
      'friendName': otherName,
      'friendUsername': otherUserName,
      'since': FieldValue.serverTimestamp(),
    });

    final otherFriendsRef = users.doc(fromUid).collection('friends').doc(toUid);
    batch.set(otherFriendsRef, {
      'friendUid': toUid,
      'friendName': myName,
      'friendUsername': myUserName,
      'since': FieldValue.serverTimestamp(),
    });

    batch.delete(docRef);

    await batch.commit();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ahora son amigos')),
      );
    }
  }

  Future<void> _rejectInvite(DocumentReference docRef) async {
    await docRef.delete();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solicitud rechazada y eliminada')),
      );
    }
  }

  Future<void> _removeFriend(String friendUid, String friendName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar amigo'),
        content: Text('¿Confirmas eliminar a $friendName de tu lista de amigos?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Eliminar')),
        ],
      ),
    );

    if (confirmed != true) return;

    final batch = FirebaseFirestore.instance.batch();
    final users = FirebaseFirestore.instance.collection('users');
    final myFriendRef = users.doc(_uid).collection('friends').doc(friendUid);
    final otherFriendRef = users.doc(friendUid).collection('friends').doc(_uid);

    batch.delete(myFriendRef);
    batch.delete(otherFriendRef);
    await batch.commit();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Amigo eliminado')),
      );
    }
  }

  String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return '—';
    final dt = ts.toDate();
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final yy = dt.year;
    return '$dd/$mm/$yy';
  }

  // chequea si ya es amigo o si ya hay invitación (doc con id '${from}_${to}' o '${to}_${from}')
  Future<String> _checkRelationStatus(String otherUid) async {
    // 0 => nada, 'friend', 'sent', 'received'
    final users = FirebaseFirestore.instance.collection('users');
    final friendDoc = await users.doc(_uid).collection('friends').doc(otherUid).get();
    if (friendDoc.exists) return 'friend';

    final sentId = '${_uid}_$otherUid';
    final receivedId = '${otherUid}_$_uid';

    final sentSnap = await FirebaseFirestore.instance.collection('friend_requests').doc(sentId).get();
    if (sentSnap.exists) return 'sent';

    final recSnap = await FirebaseFirestore.instance.collection('friend_requests').doc(receivedId).get();
    if (recSnap.exists) return 'received';

    return 'none';
  }

  void _openIncomingSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.85,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _IncomingInvitesList(
            currentUid: _uid,
            onAccept: _acceptInvite,
            onReject: _rejectInvite,
          ),
        ),
      ),
    );
  }

  void _openOutgoingSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.7,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _OutgoingInvitesList(currentUid: _uid),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Amigos'),
        actions: [
          // Outgoing invites quick access
          IconButton(
            tooltip: 'Invitaciones enviadas',
            onPressed: _openOutgoingSheet,
            icon: const Icon(Icons.send_outlined),
          ),

          // Incoming invites with badge
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('friend_requests')
                .where('toUid', isEqualTo: _uid)
                .where('status', isEqualTo: 'pending')
                .snapshots(),
            builder: (context, snap) {
              final count = (snap.data?.docs.length ?? 0);
              return IconButton(
                tooltip: 'Invitaciones recibidas ($count)',
                onPressed: _openIncomingSheet,
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.person_add_alt_1_outlined),
                    if (count > 0)
                      Positioned(
                        right: -6,
                        top: -6,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                            border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 1.5),
                          ),
                          child: Text(
                            count.toString(),
                            style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
        child: Column(
          children: [
            // Búsqueda
            TextField(
              controller: _q,
              decoration: InputDecoration(
                labelText: 'Buscar usuarios (nombre o correo)',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _term.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _q.clear();
                          setState(() => _term = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _term = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 12),

            Expanded(
              child: ListView(
                children: [
                  // Resultado búsqueda
                  _UsersSearchListImproved(
                    term: _term,
                    currentUid: _uid,
                    onInvite: _sendInvite,
                    checkRelationStatus: _checkRelationStatus,
                  ),
                  const Divider(),

                  // Cabecera amigos
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4),
                    child: Text('Mis amigos', style: Theme.of(context).textTheme.titleMedium),
                  ),

                  _FriendsListImproved(
                    currentUid: _uid,
                    onRemove: _removeFriend,
                    formatTimestamp: _formatTimestamp,
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

/// ---------------------- Widgets mejorados ----------------------

class _FriendsListImproved extends StatelessWidget {
  final String currentUid;
  final Future<void> Function(String friendUid, String friendName) onRemove;
  final String Function(Timestamp?) formatTimestamp;

  const _FriendsListImproved({
    required this.currentUid,
    required this.onRemove,
    required this.formatTimestamp,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUid)
          .collection('friends')
          .orderBy('since', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Text('Error: ${snap.error}');
        if (!snap.hasData) return const Padding(
          padding: EdgeInsets.all(16.0),
          child: Center(child: CircularProgressIndicator()),
        );

        final docs = snap.data!.docs;
        if (docs.isEmpty) return const Padding(
          padding: EdgeInsets.all(12.0),
          child: Text('Aún no tienes amigos. Invita a alguien interesante.'),
        );

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final d = docs[index].data();
            final friendUid = (d['friendUid'] ?? '') as String;
            final friendName = (d['friendName'] ?? 'Usuario') as String;
            final unameRaw = (d['friendUsername'] ?? '') as String;
            final since = d['since'] as Timestamp?;

            final subtitle = unameRaw.isEmpty ? formatTimestamp(since) : '@$unameRaw • ${formatTimestamp(since)}';

            return Dismissible(
              key: ValueKey(friendUid),
              direction: DismissDirection.endToStart,
              background: Container(
                color: Colors.redAccent,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: const Icon(Icons.delete_forever, color: Colors.white),
              ),
              confirmDismiss: (_) async {
                // usamos la misma función para confirmar y ejecutar
                await onRemove(friendUid, friendName);
                return false; // ya manejamos eliminación manualmente (evita doble borrado visual)
              },
              child: Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: friendName.isNotEmpty
                        ? Text(friendName.trim().split(' ').map((p) => p.isNotEmpty ? p[0] : '').take(2).join().toUpperCase())
                        : const Icon(Icons.person),
                  ),
                  title: Text(friendName),
                  subtitle: Text(subtitle),
                  trailing: PopupMenuButton<String>(
  onSelected: (v) async {
    if (v == 'profile') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserProfileScreen(userUid: friendUid)));
    } else if (v == 'message') {
      final meUid = currentUid;
      final chatId = await createOrGetChatId(meUid, friendUid);
      if (context.mounted) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(chatId: chatId, otherUid: friendUid)));
      }
    } else if (v == 'remove') {
      await onRemove(friendUid, friendName);
    }
  },
  itemBuilder: (_) => [
    const PopupMenuItem(value: 'profile', child: Text('Ver perfil')),
    const PopupMenuItem(value: 'message', child: Text('Enviar mensaje')),
    const PopupMenuDivider(),
    const PopupMenuItem(value: 'remove', child: Text('Eliminar amigo')),
  ],
),

                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _UsersSearchListImproved extends StatelessWidget {
  final String term;
  final String currentUid;
  final Future<void> Function(String toUid, String toName) onInvite;
  final Future<String> Function(String otherUid) checkRelationStatus;

  const _UsersSearchListImproved({
    required this.term,
    required this.currentUid,
    required this.onInvite,
    required this.checkRelationStatus,
  });

  @override
  Widget build(BuildContext context) {
    // Stream de usuarios (igual que antes)
    final stream = (term.isEmpty)
        ? FirebaseFirestore.instance.collection('users').orderBy('displayName').limit(30).snapshots()
        : FirebaseFirestore.instance
            .collection('users')
            .orderBy('displayName')
            .limit(100)
            .snapshots();

    // Primero obtenemos la lista de amigos (una sola vez) y luego renderizamos el stream excluyendo esos UIDs
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUid)
          .collection('friends')
          .get(),
      builder: (context, friendsSnap) {
        if (friendsSnap.hasError) return Text('Error: ${friendsSnap.error}');
        if (!friendsSnap.hasData) return const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        );

        // Construimos el set de UIDs que ya son amigos
        final Set<String> friendsUids = friendsSnap.data!.docs
            .map((d) => (d.data()['friendUid'] ?? '').toString())
            .where((s) => s.isNotEmpty)
            .toSet();

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: stream,
          builder: (context, snap) {
            if (snap.hasError) return Text('Error: ${snap.error}');
            if (!snap.hasData) return const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            );

            // Filtramos usuarios: no mostrar al currentUid ni a quienes ya son amigos
            var docs = snap.data!.docs.where((d) => d.id != currentUid && !friendsUids.contains(d.id)).toList();

            if (term.isNotEmpty) {
              final q = term.toLowerCase();
              docs = docs.where((d) {
                final name = (d.data()['displayName'] ?? '').toString().toLowerCase();
                final email = (d.data()['email'] ?? '').toString().toLowerCase();
                final username = (d.data()['username'] ?? '').toString().toLowerCase();
                return name.contains(q) || email.contains(q) || username.contains(q);
              }).toList();
            }

            return Column(
              children: docs.map((d) {
                final data = d.data();
                final name = (data['displayName'] ?? 'Usuario').toString();
                final email = (data['email'] ?? '').toString();
                final usernameRaw = (data['username'] ?? '').toString();
                final username = usernameRaw.isEmpty ? null : '@$usernameRaw';

                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: name.isNotEmpty
                          ? Text(name.trim().split(' ').map((p) => p.isNotEmpty ? p[0] : '').take(2).join().toUpperCase())
                          : const Icon(Icons.person),
                    ),
                    title: Text(name),
                    subtitle: Text(username ?? email),
                    trailing: FutureBuilder<String>(
                      future: checkRelationStatus(d.id),
                      builder: (context, state) {
                        final status = state.data ?? 'none';
                        if (state.connectionState != ConnectionState.done) {
                          return const SizedBox(width: 80, height: 36, child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))));
                        }
                        if (status == 'friend') {
                          return const Text('Amigo', style: TextStyle(color: Colors.green));
                        } else if (status == 'sent') {
                          return const Text('Invitado', style: TextStyle(color: Colors.orange));
                        } else if (status == 'received') {
                          return FilledButton(
                            onPressed: () {
                              // abrir modal de invitaciones entrantes (para ver y aceptar)
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                builder: (_) => FractionallySizedBox(
                                  heightFactor: 0.85,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: _IncomingInvitesList(
                                      currentUid: currentUid,
                                      onAccept: (docRef) => FirebaseFirestore.instance.runTransaction((tx) => tx.get(docRef).then((snap) {
                                        // delegar a UI no posible desde aquí -> show snackbar instructivo
                                      })),
                                      onReject: (docRef) async {
                                        await docRef.delete();
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Solicitud eliminada')));
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                            child: const Text('Revisar'),
                          );
                        } else {
                          return FilledButton.icon(
                            onPressed: () => onInvite(d.id, name),
                            icon: const Icon(Icons.person_add_alt_1),
                            label: const Text('Invitar'),
                          );
                        }
                      },
                    ),
                  ),
                );
              }).toList(),
            );
          },
        );
      },
    );
  }
}


/// Lista de invitaciones entrantes (reuseable)
class _IncomingInvitesList extends StatelessWidget {
  final String currentUid;
  final Future<void> Function(DocumentReference docRef) onAccept;
  final Future<void> Function(DocumentReference docRef) onReject;

  const _IncomingInvitesList({
    required this.currentUid,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 6),
        Row(
          children: [
            const Text('Invitaciones recibidas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const Spacer(),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const Divider(),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('friend_requests')
                .where('toUid', isEqualTo: currentUid)
                .where('status', isEqualTo: 'pending')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.docs;
              if (docs.isEmpty) return const Center(child: Text('No tienes invitaciones pendientes'));

              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, i) {
                  final d = docs[i].data();
                  final docRef = docs[i].reference;
                  final fromName = (d['fromName'] ?? 'Usuario').toString();
                  final createdAt = d['createdAt'] as Timestamp?;
                  final dateStr = createdAt == null ? '—' : '${createdAt.toDate().day}/${createdAt.toDate().month}/${createdAt.toDate().year}';
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person_add)),
                    title: Text(fromName),
                    subtitle: Text('Recibida: $dateStr'),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(onPressed: () => onReject(docRef), child: const Text('Rechazar')),
                        FilledButton(onPressed: () => onAccept(docRef), child: const Text('Aceptar')),
                      ],
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

/// Lista de invitaciones enviadas (mejor vista)
class _OutgoingInvitesList extends StatelessWidget {
  final String currentUid;
  const _OutgoingInvitesList({required this.currentUid});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 6),
        Row(
          children: [
            const Text('Invitaciones enviadas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const Spacer(),
            IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
          ],
        ),
        const Divider(),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('friend_requests')
                .where('fromUid', isEqualTo: currentUid)
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.docs;
              if (docs.isEmpty) return const Center(child: Text('No has enviado invitaciones'));

              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, i) {
                  final d = docs[i].data();
                  final toName = (d['toName'] ?? 'Usuario').toString();
                  final status = (d['status'] ?? 'pending').toString();
                  final createdAt = d['createdAt'] as Timestamp?;
                  final dateStr = createdAt == null ? '—' : '${createdAt.toDate().day}/${createdAt.toDate().month}/${createdAt.toDate().year}';
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.send)),
                    title: Text(toName),
                    subtitle: Text('Estado: $status • $dateStr'),
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
