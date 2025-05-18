import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProfileService {
  static Future<bool> isProfileComplete() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return false;

    final isGoogleUser = user.providerData.any(
      (info) => info.providerId == 'google.com',
    );

    // For Google users, we only need role and ID verification
    if (isGoogleUser) {
      final isRoleSelected = prefs.getBool('isRoleSelected') ?? false;
      final isIdVerified = prefs.getBool('isIdVerified') ?? false;
      final isFirstTimeUser = prefs.getBool('isFirstTimeUser') ?? true;

      // If it's a first-time user, we don't require profile completion yet
      if (isFirstTimeUser) return true;

      return isRoleSelected && isIdVerified;
    }
    // For email/password users, we need name verification as well
    else {
      final isNameVerified = prefs.getBool('isNameVerified') ?? false;
      final isRoleSelected = prefs.getBool('isRoleSelected') ?? false;
      final isIdVerified = prefs.getBool('isIdVerified') ?? false;
      final isFirstTimeUser = prefs.getBool('isFirstTimeUser') ?? true;

      // If it's a first-time user, we don't require profile completion yet
      if (isFirstTimeUser) return true;

      return isNameVerified && isRoleSelected && isIdVerified;
    }
  }

  static Future<void> saveProfileCompletionStatus({
    required bool isNameVerified,
    required bool isRoleSelected,
    required bool isIdVerified,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isNameVerified', isNameVerified);
    await prefs.setBool('isRoleSelected', isRoleSelected);
    await prefs.setBool('isIdVerified', isIdVerified);
  }
}
