import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SyncService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static bool _isSyncing = false;
  static OverlayEntry? _overlayEntry;
  static bool _hasSyncedThisSession = false;

  static Future<void> syncNow(BuildContext context) async {
    if (_isSyncing || _hasSyncedThisSession) return;
    _isSyncing = true;

    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        print('⚡ Offline detected, skipping sync.');
        _isSyncing = false;
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _isSyncing = false;
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final bool isFirstTimeUser = prefs.getBool('isFirstTimeUser') ?? true;

      if (isFirstTimeUser) {
        print('🆕 First time user detected. Skipping sync.');
        _isSyncing = false;
        _hasSyncedThisSession = true;
        return;
      }

      final notesSnapshot =
          await _firestore
              .collection('notes')
              .where('owner', isEqualTo: user.uid)
              .limit(1)
              .get();

      final hasNotes = notesSnapshot.docs.isNotEmpty;

      if (hasNotes) {
        _showLoadingSpinner(context);
      }

      await _syncData(context);

      if (hasNotes) {
        _hideLoadingSpinner(context);
      }

      _hasSyncedThisSession = true;
    } catch (e) {
      print('Sync error: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Sync failed: $e')));
      _hideLoadingSpinner(context);
    } finally {
      _isSyncing = false;
    }
  }

  // Start auto-sync for notes and user verification data
  static Future<void> startAutoSync(BuildContext context) async {
    Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) async {
      if (results.isNotEmpty &&
          results.first != ConnectivityResult.none &&
          !_isSyncing) {
        _isSyncing = true;
        _showLoadingSpinner(context);
        try {
          await _syncData(context);
        } catch (e) {
          print('Sync error: $e');
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Sync failed: $e')));
        }
        _hideLoadingSpinner(context);
        _isSyncing = false;
      }
    });
  }

  // Sync both notes and verification data in both directions
  static Future<void> _syncData(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await _syncLocalNotesToFirestore(user.uid);
    await _syncFirestoreNotesToLocal(user.uid);
    await _syncLocalVerificationToFirestore(user.uid);
  }

  // Sync local notes to Firestore
  static Future<void> _syncLocalNotesToFirestore(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final String? notesString = prefs.getString('notes');

    if (notesString != null) {
      final List<dynamic> notes = jsonDecode(notesString);
      for (var note in notes) {
        if (note['id'] != null) {
          await _firestore.collection('notes').doc(note['id']).set({
            ...note,
            'owner': userId,
          }, SetOptions(merge: true));
        }
      }
    }
  }

  // Sync notes from Firestore to local SharedPreferences
  static Future<void> _syncFirestoreNotesToLocal(String userId) async {
    final prefs = await SharedPreferences.getInstance();

    // Fetch notes where user is the owner
    final ownerNotesSnapshot =
        await _firestore
            .collection('notes')
            .where('owner', isEqualTo: userId)
            .get();

    // Fetch notes where user is a collaborator
    final collaboratorNotesSnapshot =
        await _firestore
            .collection('notes')
            .where('collaborators', arrayContains: userId)
            .get();

    // Merge results
    final firestoreNotes =
        [
          ...ownerNotesSnapshot.docs,
          ...collaboratorNotesSnapshot.docs,
        ].map((doc) => {...doc.data(), 'id': doc.id}).toList();

    // Merge with local notes
    final String? localNotesString = prefs.getString('notes');
    List<dynamic> localNotes =
        localNotesString != null ? jsonDecode(localNotesString) : [];

    final Map<String, dynamic> mergedNotesMap = {};
    for (var note in localNotes) {
      if (note['id'] != null) {
        mergedNotesMap[note['id']] = note;
      }
    }
    for (var note in firestoreNotes) {
      mergedNotesMap[note['id']] = note;
    }

    final mergedNotes = mergedNotesMap.values.toList();
    await prefs.setString('notes', jsonEncode(mergedNotes));
  }

  // Sync local verification data to Firestore
  static Future<void> _syncLocalVerificationToFirestore(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final docRef = _firestore.collection('users').doc(userId);
    final docSnapshot = await docRef.get();

    if (docSnapshot.exists) {
      // Firestore data takes precedence
      final data = docSnapshot.data()!;
      final verificationData = {
        'isNameVerified': data['isNameVerified'] ?? false,
        'isRoleSelected': data['isRoleSelected'] ?? false,
        'isIdVerified': data['isIdVerified'] ?? false,
        'isFirstTimeUser': data['isFirstTimeUser'] ?? true,
        'fullName': data['fullName'] ?? '',
        'selectedRole': data['role'] ?? 'Student',
        'profileInitials': prefs.getString('profileInitials') ?? '',
        'studentId': data['idNumber'] ?? '',
        'teacherId': data['idNumber'] ?? '',
      };

      // Update SharedPreferences with Firestore data
      await prefs.setBool('isNameVerified', verificationData['isNameVerified']);
      await prefs.setBool('isRoleSelected', verificationData['isRoleSelected']);
      await prefs.setBool('isIdVerified', verificationData['isIdVerified']);
      await prefs.setBool(
        'isFirstTimeUser',
        verificationData['isFirstTimeUser'],
      );
      await prefs.setString('fullName', verificationData['fullName']);
      await prefs.setString('selectedRole', verificationData['selectedRole']);
      await prefs.setString('studentId', verificationData['studentId']);
      await prefs.setString('teacherId', verificationData['teacherId']);
      await prefs.setString(
        'profileInitials',
        verificationData['profileInitials'],
      );
    } else {
      // If no Firestore data, sync local SharedPreferences to Firestore
      final localData = {
        'isNameVerified': prefs.getBool('isNameVerified') ?? false,
        'isRoleSelected': prefs.getBool('isRoleSelected') ?? false,
        'isIdVerified': prefs.getBool('isIdVerified') ?? false,
        'isFirstTimeUser': prefs.getBool('isFirstTimeUser') ?? true,
        'fullName': prefs.getString('fullName') ?? '',
        'role': prefs.getString('selectedRole') ?? 'Student',
        'idNumber':
            prefs.getString('studentId') ?? prefs.getString('teacherId') ?? '',
        'profileInitials': prefs.getString('profileInitials') ?? '',
      };

      await docRef.set(localData, SetOptions(merge: true));
    }
  }

  // Sync verification data and notes from Firestore to local on login
  static Future<void> syncVerificationOnLogin(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final docRef = _firestore.collection('users').doc(userId);
    final docSnapshot = await docRef.get();

    if (docSnapshot.exists) {
      final data = docSnapshot.data()!;
      print('Syncing verification data from Firestore: $data');
      await prefs.setBool('isNameVerified', data['isNameVerified'] ?? false);
      await prefs.setBool('isRoleSelected', data['isRoleSelected'] ?? false);
      await prefs.setBool('isIdVerified', data['isIdVerified'] ?? false);
      await prefs.setBool('isFirstTimeUser', data['isFirstTimeUser'] ?? true);
      await prefs.setString('fullName', data['fullName'] ?? '');
      await prefs.setString('selectedRole', data['role'] ?? 'Student');
      await prefs.setString('studentId', data['idNumber'] ?? '');
      await prefs.setString('teacherId', data['idNumber'] ?? '');
      await prefs.setString(
        'profileInitials',
        data['profileInitials'] ?? _getInitials(data['fullName'] ?? ''),
      );
    }

    // Sync notes from Firestore to local on login
    await _syncFirestoreNotesToLocal(userId);
  }

  // Clear local data on logout
  static Future<void> clearLocalDataOnLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  // Load notes from Firestore (used for manual refresh or UI updates)
  static Future<List<Map<String, dynamic>>> loadNotesFromFirestore(
    String userId,
  ) async {
    final querySnapshot =
        await _firestore
            .collection('notes')
            .where('owner', isEqualTo: userId)
            .get();

    return querySnapshot.docs
        .map((doc) => {...doc.data(), 'id': doc.id})
        .toList();
  }

  // Show loading spinner
  static void _showLoadingSpinner(BuildContext context) {
    _overlayEntry = OverlayEntry(
      builder:
          (context) => Material(
            color: Colors.black.withOpacity(0.5),
            child: Center(
              child: Container(
                width: 200,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AnimatedSpinner(),
                    const SizedBox(height: 16),
                    _AnimatedSyncText(),
                  ],
                ),
              ),
            ),
          ),
    );

    Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);

    // Auto-hide after 10 seconds to account for slower networks
    Future.delayed(const Duration(seconds: 10), () {
      _hideLoadingSpinner(context);
    });
  }

  // Hide loading spinner
  static void _hideLoadingSpinner(BuildContext context) {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // Helper to get initials
  static String _getInitials(String name) {
    final nameParts = name.trim().split(' ');
    if (nameParts.isEmpty) return 'U';
    if (nameParts.length == 1) {
      return nameParts[0].isNotEmpty ? nameParts[0][0].toUpperCase() : 'U';
    }
    final firstInitial =
        nameParts[0].isNotEmpty ? nameParts[0][0].toUpperCase() : '';
    final lastInitial =
        nameParts.last.isNotEmpty ? nameParts.last[0].toUpperCase() : '';
    return '$firstInitial$lastInitial';
  }
}

// Custom Animated Spinner Widget
class _AnimatedSpinner extends StatefulWidget {
  @override
  __AnimatedSpinnerState createState() => __AnimatedSpinnerState();
}

class __AnimatedSpinnerState extends State<_AnimatedSpinner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotateAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _rotateAnimation = Tween<double>(
      begin: 0,
      end: 360,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.linear));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: _rotateAnimation.value * (3.14159 / 180),
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Colors.blueAccent, Colors.lightBlueAccent],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blueAccent.withOpacity(0.4),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(Icons.sync, color: Colors.white, size: 30),
            ),
          ),
        );
      },
    );
  }
}

// Animated Sync Text Widget
class _AnimatedSyncText extends StatefulWidget {
  @override
  __AnimatedSyncTextState createState() => __AnimatedSyncTextState();
}

class __AnimatedSyncTextState extends State<_AnimatedSyncText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _fadeAnimation = Tween<double>(
      begin: 0.4,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: const Text(
        'Syncing notes...\nPlease wait.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.black87,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
