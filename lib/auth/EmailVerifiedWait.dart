import 'dart:async';
import 'package:flutter/material.dart';
import '../SelectionAction.dart';

class EmailVerifiedWait extends StatefulWidget {
  const EmailVerifiedWait({super.key});

  @override
  State<EmailVerifiedWait> createState() => _EmailVerifiedWaitState();
}

class _EmailVerifiedWaitState extends State<EmailVerifiedWait> {
  @override
  void initState() {
    super.initState();
    // Wait for 5 seconds then navigate to SelectionAction
    Timer(const Duration(seconds: 5), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const SelectionAction()),
        );
      }
    });
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
