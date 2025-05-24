import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class UserProvider with ChangeNotifier {
  User? _user;
  User? get user => _user;

  void setUser(User? user) {
    _user = user;
    notifyListeners();
  }

  // Placeholder for profile image (not implemented)
  dynamic get profileImage => null;

  void setProfileImage(File file) {}
}
