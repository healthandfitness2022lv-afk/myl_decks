// lib/models/current_user.dart
import 'package:flutter/foundation.dart';

class CurrentUser extends ChangeNotifier {
  String? uid;
  String? email;
  String role = 'basico';
  String? displayName;
  String? photoUrl;
  bool isAnonymous = false;
  bool get isBasico => role == 'basico';
  bool get isPro => role == 'pro';
  bool get isAdmin => role == 'administrador';
  bool get isGuest => isAnonymous || uid == null;

  void update({
    String? uid_,
    String? email_,
    String? role_,
    String? displayName_,
    String? photoUrl_,
    bool isAnonymous_ = false,
  }) {
    uid = uid_;
    email = email_;
    role = role_ ?? 'basico';
    displayName = displayName_;
    photoUrl = photoUrl_;
    isAnonymous = isAnonymous_;
    notifyListeners();
  }

  void clear() {
    uid = null;
    email = null;
    role = 'basico';
    displayName = null;
    photoUrl = null;
    isAnonymous = false;
    notifyListeners();
  }
}
