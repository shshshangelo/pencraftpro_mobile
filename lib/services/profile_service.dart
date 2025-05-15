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
    final isNameVerified = prefs.getBool('isNameVerified') ?? isGoogleUser;
    final isRoleSelected = prefs.getBool('isRoleSelected') ?? false;
    final isIdVerified = prefs.getBool('isIdVerified') ?? false;
    final isFirstTimeUser = prefs.getBool('isFirstTimeUser') ?? true;

    if (isGoogleUser) {
      return isRoleSelected && isIdVerified && !isFirstTimeUser;
    } else {
      return isNameVerified &&
          isRoleSelected &&
          isIdVerified &&
          !isFirstTimeUser;
    }
  }
}
