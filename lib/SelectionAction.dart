import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SelectionAction extends StatefulWidget {
  const SelectionAction({super.key});

  @override
  State<SelectionAction> createState() => _SelectionActionState();
}

class _SelectionActionState extends State<SelectionAction> {
  bool _isGoogleUser = false;

  @override
  void initState() {
    super.initState();
    _initializeUserData();
  }

  Future<void> _initializeUserData() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      _isGoogleUser = user.providerData.any(
        (info) => info.providerId == 'google.com',
      );
    }

    setState(() {});
  }

  Future<bool> _onWillPop(BuildContext context) async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Exit App?'),
            content: const Text('Are you sure you want to exit the app?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop(true);
                  exit(0);
                },
                child: const Text('Exit'),
              ),
            ],
          ),
    );
    return shouldLeave ?? false;
  }

  void _showVerificationRequiredDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Verification Required'),
          content: Text(
            _isGoogleUser
                ? 'You need to select your role (Student/Teacher) and verify your ID No. before accessing this feature.'
                : 'You need to set your full name, select your role (Student/Teacher), and verify your ID No. before accessing this feature.',
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Go to Settings'),
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.pushNamed(context, '/accountsettings');
              },
            ),
          ],
        );
      },
    );
  }

  void _handleRestrictedAction(BuildContext context, String route) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please sign in first')));
      Navigator.pushNamed(context, '/login');
      return;
    }

    final userDoc =
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
    if (!userDoc.exists) {
      // ignore: use_build_context_synchronously
      _showVerificationRequiredDialog(context);
      return;
    }

    final data = userDoc.data()!;
    final fullName = data['fullName'] ?? '';
    final idNumber = data['idNumber'] ?? '';
    final role = data['role'] ?? '';

    final isVerified =
        fullName.isNotEmpty && idNumber.isNotEmpty && role.isNotEmpty;

    // Debugging step - check the values
    print('FULLNAME: $fullName');
    print('ID NUMBER: $idNumber');
    print('ROLE: $role');
    print('IS VERIFIED: $isVerified');

    if (isVerified) {
      Navigator.pushNamed(context, route);
    } else {
      _showVerificationRequiredDialog(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: () => _onWillPop(context),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Choose Action'),
          automaticallyImplyLeading: false,
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
        ),
        body: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 1),
              Text(
                'Hi there, What would you like to do?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Satisfy',
                  fontSize: 25,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.note_alt_outlined),
                      label: const Text('Take Notes'),
                      onPressed: () {
                        _handleRestrictedAction(context, '/notes');
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.draw_rounded),
                      label: const Text('Start Drawing'),
                      onPressed: () {
                        _handleRestrictedAction(context, '/drawing');
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
