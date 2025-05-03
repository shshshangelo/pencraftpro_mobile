import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../SelectionAction.dart';

class EmailVerifiedWait extends StatefulWidget {
  const EmailVerifiedWait({super.key});

  @override
  State<EmailVerifiedWait> createState() => _EmailVerifiedWaitState();
}

class _EmailVerifiedWaitState extends State<EmailVerifiedWait> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startVerificationCheck();
  }

  void _startVerificationCheck() {
    final user = FirebaseAuth.instance.currentUser;

    // Auto-pass Google Sign-In users
    final isGoogleUser =
        user?.providerData.any((info) => info.providerId == 'google.com') ??
        false;

    if (isGoogleUser) {
      Future.delayed(const Duration(seconds: 3), () {
        _navigateToSelect();
      });
      return;
    }

    // Poll email verification every 3 seconds
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      await FirebaseAuth.instance.currentUser?.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser;

      if (refreshedUser != null && refreshedUser.emailVerified) {
        timer.cancel();
        _navigateToSelect();
      }
    });
  }

  void _navigateToSelect() {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const SelectionAction()),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text('Verifying your account...', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }
}
