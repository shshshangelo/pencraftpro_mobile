import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pencraftpro/services/SyncService.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<bool> isActuallyOnline() async {
  try {
    final result = await InternetAddress.lookup('google.com');
    return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}

Future<void> showLogoutDialog(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Logout'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      );
    },
  );

  if (confirmed == true) {
    final online = await isActuallyOnline();
    if (!online) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You need to be online first before logging out to ensure that all your PenCraft Pro notes are synced.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      return;
    }

    try {
      // Save email, remember me status, labels and folders before clearing
      final prefs = await SharedPreferences.getInstance();
      final savedEmail = prefs.getString('email');
      final rememberMe = prefs.getBool('rememberMe') ?? false;
      final labels = prefs.getString('labels');
      final folders = prefs.getString('folders');

      // Clear all local data
      await SyncService.clearLocalDataOnLogout();

      // Clear SharedPreferences
      await prefs.clear();

      // Restore email and remember me if it was enabled
      if (rememberMe && savedEmail != null) {
        await prefs.setString('email', savedEmail);
        await prefs.setBool('rememberMe', true);
      }

      // Restore labels and folders
      if (labels != null) {
        await prefs.setString('labels', labels);
      }
      if (folders != null) {
        await prefs.setString('folders', folders);
      }

      // Sign out from Firebase
      await FirebaseAuth.instance.signOut();

      if (context.mounted) {
        // Navigate to login screen and remove all previous routes
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/login',
          (Route<dynamic> route) => false,
          arguments: {'showWelcomeBack': true},
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Logged out successfully.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error during logout: ${e.toString()}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
  }
}
