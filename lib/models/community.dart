import 'package:cloud_firestore/cloud_firestore.dart';

class CommunityPost {
  final String id;
  final String title;
  final String text;
  final String authorUid;
  final String authorName;
  final DateTime? createdAt;
  final int comments;
  final int likes;
  final int dislikes;

  const CommunityPost({
    required this.id,
    required this.title,
    required this.text,
    required this.authorUid,
    required this.authorName,
    required this.createdAt,
    required this.comments,
    required this.likes,
    required this.dislikes,
  });

  factory CommunityPost.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return CommunityPost(
      id: snapshot.id,
      title: (data['title'] ?? 'Debate').toString(),
      text: (data['text'] ?? '').toString(),
      authorUid: (data['authorUid'] ?? '').toString(),
      authorName: (data['authorName'] ?? 'Usuario').toString(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      comments: (data['comments'] as num?)?.toInt() ?? 0,
      likes: (data['likes'] as num?)?.toInt() ?? 0,
      dislikes: (data['dislikes'] as num?)?.toInt() ?? 0,
    );
  }
}
