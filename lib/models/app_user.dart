// lib/models/app_user.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String? displayName;
  final String? photoUrl;
  final String? email;
  final DateTime createdAt;

  // 👇 nuevos campos de estadísticas
  final int matchesPlayed;
  final int wins;
  final int losses;

  // 👇 fields para roles / features
  final String role; // 'basico' | 'pro' | 'administrador'
  final DateTime? proSince; // cuando pasó a pro (null si nunca)
  final int? maxDecks; // límite configurable por rol
  final bool? canUploadImages; // permiso para subir imágenes oficiales

  AppUser({
    required this.uid,
    this.displayName,
    this.photoUrl,
    this.email,
    required this.createdAt,
    this.matchesPlayed = 0,
    this.wins = 0,
    this.losses = 0,
    this.role = 'basico',
    this.proSince,
    this.maxDecks,
    this.canUploadImages,
  });

  factory AppUser.fromMap(Map<String, dynamic> m, String uid) {
    DateTime parseCreatedAt(dynamic raw) {
      if (raw == null) return DateTime.now();
      if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
      if (raw is String) {
        final parsed = int.tryParse(raw);
        if (parsed != null) return DateTime.fromMillisecondsSinceEpoch(parsed);
        return DateTime.tryParse(raw) ?? DateTime.now();
      }
      if (raw is Timestamp) return raw.toDate();
      // fallback
      return DateTime.now();
    }

    DateTime? parseOptionalDate(dynamic raw) {
      if (raw == null) return null;
      if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
      if (raw is Timestamp) return raw.toDate();
      if (raw is String) {
        final parsed = int.tryParse(raw);
        if (parsed != null) return DateTime.fromMillisecondsSinceEpoch(parsed);
        return DateTime.tryParse(raw);
      }
      return null;
    }

    return AppUser(
      uid: uid,
      displayName: m['displayName'] as String?,
      photoUrl: m['photoUrl'] as String?,
      email: m['email'] as String?,
      createdAt: parseCreatedAt(m['createdAt']),
      matchesPlayed: (m['matchesPlayed'] ?? 0) is int ? (m['matchesPlayed'] as int) : ((m['matchesPlayed'] ?? 0) as num).toInt(),
      wins: (m['wins'] ?? 0) is int ? (m['wins'] as int) : ((m['wins'] ?? 0) as num).toInt(),
      losses: (m['losses'] ?? 0) is int ? (m['losses'] as int) : ((m['losses'] ?? 0) as num).toInt(),
      role: (m['role'] as String?) ?? 'basico',
      proSince: parseOptionalDate(m['proSince']),
      maxDecks: m['maxDecks'] != null ? (m['maxDecks'] as num).toInt() : null,
      canUploadImages: m['canUploadImages'] as bool?,
    );
  }

  Map<String, dynamic> toMap() => {
        'displayName': displayName,
        'photoUrl': photoUrl,
        'email': email,
        // tu código actual usaba ms epoch; mantenemos eso para compatibilidad.
        'createdAt': createdAt.millisecondsSinceEpoch,
        'matchesPlayed': matchesPlayed,
        'wins': wins,
        'losses': losses,
        // campos de rol/feature
        'role': role,
        if (proSince != null) 'proSince': proSince!.millisecondsSinceEpoch,
        if (maxDecks != null) 'maxDecks': maxDecks,
        if (canUploadImages != null) 'canUploadImages': canUploadImages,
      };

  AppUser copyWith({
    String? displayName,
    String? photoUrl,
    String? email,
    DateTime? createdAt,
    int? matchesPlayed,
    int? wins,
    int? losses,
    String? role,
    DateTime? proSince,
    int? maxDecks,
    bool? canUploadImages,
  }) {
    return AppUser(
      uid: uid,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      email: email ?? this.email,
      createdAt: createdAt ?? this.createdAt,
      matchesPlayed: matchesPlayed ?? this.matchesPlayed,
      wins: wins ?? this.wins,
      losses: losses ?? this.losses,
      role: role ?? this.role,
      proSince: proSince ?? this.proSince,
      maxDecks: maxDecks ?? this.maxDecks,
      canUploadImages: canUploadImages ?? this.canUploadImages,
    );
  }

  @override
  String toString() {
    return 'AppUser(uid: $uid, displayName: $displayName, role: $role, email: $email)';
  }
}
