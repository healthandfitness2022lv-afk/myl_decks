// lib/models/current_user.dart
import 'package:flutter/foundation.dart';

class CurrentUser extends ChangeNotifier {
  String? uid;
  String? email;
  String role = 'basico';
  String? displayName;
  String? photoUrl;

  bool get isBasico => role == 'basico';
  bool get isPro    => role == 'pro';
  bool get isAdmin  => role == 'administrador';

  void update({String? uid_, String? email_, String? role_, String? displayName_, String? photoUrl_}) {
    uid = uid_;
    email = email_;
    role = role_ ?? role;
    displayName = displayName_ ?? displayName;
    photoUrl = photoUrl_ ?? photoUrl;
    notifyListeners();
  }
}
