import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pencraftpro/services/SyncService.dart';

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
              backgroundColor:
                  Theme.of(
                    context,
                  ).colorScheme.secondary, // Use theme's secondary color
              foregroundColor:
                  Theme.of(
                    context,
                  ).colorScheme.onSecondary, // Use theme's onSecondary color
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              textStyle: const TextStyle(fontSize: 16),
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
          content: const Text(
            '⚠️ You need to be online first before logging out.',
          ),
          backgroundColor:
              Theme.of(context).colorScheme.error, // Use theme's error color
        ),
      );
      return;
    }

    await SyncService.clearLocalDataOnLogout();
    await FirebaseAuth.instance.signOut();

    if (context.mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/login',
        (Route<dynamic> route) => false,
        arguments: {'showWelcomeBack': true},
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('✅ Logged out successfully.'),
          backgroundColor:
              Theme.of(
                context,
              ).colorScheme.primary, // Use theme's primary color
        ),
      );
    }
  }
}
