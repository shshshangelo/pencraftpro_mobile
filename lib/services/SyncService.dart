// ignore_for_file: deprecated_member_use, use_build_context_synchronously, unrelated_type_equality_checks

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
  static bool _hasStartedAutoSync = false;

  // Ensure Firestore offline persistence is enabled
  static void initializeFirestore() {
    _firestore.settings = const Settings(persistenceEnabled: true);
    print('Firestore offline persistence enabled');
  }

  static Future<void> syncNow(
    BuildContext context, {
    VoidCallback? onComplete,
  }) async {
    if (_isSyncing || _hasSyncedThisSession) return;
    _isSyncing = true;

    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final isOffline = connectivityResult == ConnectivityResult.none;
      print('Connectivity status: ${isOffline ? 'Offline' : 'Online'}');

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No authenticated user, skipping sync');
        _isSyncing = false;
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final isFirstTimeUser = prefs.getBool('isFirstTimeUser') ?? true;

      if (isFirstTimeUser) {
        print('First-time user, skipping sync');
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

      if (hasNotes && !isOffline) {
        _showLoadingSpinner(context);
      }

      await _syncData(context, isOffline: isOffline);

      if (hasNotes && !isOffline) {
        _hideLoadingSpinner(context);
      }

      _hasSyncedThisSession = true;

      if (onComplete != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onComplete();
        });
      }
    } catch (e, stackTrace) {
      print('Sync error: $e');
      print('Stack trace: $stackTrace');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sync failed: $e',
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
      _hideLoadingSpinner(context);
    } finally {
      _isSyncing = false;
    }
  }

  static Future<void> startAutoSync(
    BuildContext context, {
    VoidCallback? onAutoSyncComplete,
  }) async {
    if (_hasStartedAutoSync) return;
    _hasStartedAutoSync = true;

    final overlayContext = context;

    Connectivity().onConnectivityChanged.listen((results) async {
      final isOffline =
          results.isEmpty || results.first == ConnectivityResult.none;
      if (!isOffline && !_isSyncing) {
        _isSyncing = true;
        _showLoadingSpinner(overlayContext);
        try {
          await _syncData(overlayContext, isOffline: false);

          if (onAutoSyncComplete != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              onAutoSyncComplete();
            });
          }
        } catch (e, stackTrace) {
          print('AutoSync error: $e');
          print('Stack trace: $stackTrace');
          if (overlayContext.mounted) {
            ScaffoldMessenger.of(overlayContext).showSnackBar(
              SnackBar(
                content: Text(
                  'Auto-sync failed: $e',
                  style: TextStyle(
                    color:
                        Theme.of(overlayContext).colorScheme.onErrorContainer,
                  ),
                ),
                backgroundColor:
                    Theme.of(overlayContext).colorScheme.errorContainer,
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.all(8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            );
          }
        }
        _hideLoadingSpinner(overlayContext);
        _isSyncing = false;
      } else {
        print(
          'Auto-sync skipped: ${isOffline ? 'Offline' : 'Already syncing'}',
        );
      }
    });
  }

  static Future<void> _syncData(
    BuildContext context, {
    required bool isOffline,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (!isOffline) {
      await _syncLocalNotesToFirestore(user.uid);
      await _syncFirestoreNotesToLocal(user.uid);
      await _syncLocalVerificationToFirestore(user.uid);
    } else {
      print('Offline: Skipping Firestore sync, using local data');
    }
  }

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
      print(
        'Synced ${notes.length} local notes to Firestore (queued if offline)',
      );
    }
  }

  static Future<void> _syncFirestoreNotesToLocal(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      print('Starting sync for user: $userId');

      // Fetch notes where user is the owner
      final ownerNotesSnapshot =
          await _firestore
              .collection('notes')
              .where('owner', isEqualTo: userId)
              .where('isDeleted', isEqualTo: false)
              .get();
      print(
        'Fetched ${ownerNotesSnapshot.docs.length} owner notes (cached if offline)',
      );

      // Fetch notes where user is a collaborator
      final collaboratorNotesSnapshot =
          await _firestore
              .collection('notes')
              .where('collaborators', arrayContains: userId)
              .where('isDeleted', isEqualTo: false)
              .get();
      print(
        'Fetched ${collaboratorNotesSnapshot.docs.length} collaborator notes (cached if offline)',
      );

      // Merge results, removing duplicates
      final firestoreNotes =
          [...ownerNotesSnapshot.docs, ...collaboratorNotesSnapshot.docs]
              .fold<Map<String, Map<String, dynamic>>>({}, (map, doc) {
                map[doc.id] = {...doc.data(), 'id': doc.id};
                return map;
              })
              .values
              .toList();

      print('Total unique notes fetched: ${firestoreNotes.length}');
      print('Firestore notes: ${jsonEncode(firestoreNotes)}');

      // Merge with local notes
      final String? localNotesString = prefs.getString('notes');
      List<dynamic> localNotes =
          localNotesString != null ? jsonDecode(localNotesString) : [];
      print('Local notes before merge: ${jsonEncode(localNotes)}');

      final Map<String, dynamic> mergedNotesMap = {};

      // First add local notes to preserve folder information
      for (var note in localNotes) {
        if (note['id'] != null) {
          mergedNotesMap[note['id']] = note;
        }
      }

      // Then merge Firestore notes, preserving folder information if it exists locally
      for (var note in firestoreNotes) {
        final noteId = note['id'];
        final localNote = mergedNotesMap[noteId];

        if (localNote != null) {
          // If local note has folder info, preserve it
          if (localNote['folderId'] != null) {
            note['folderId'] = localNote['folderId'];
            note['folderColor'] = localNote['folderColor'];
            note['folderName'] = localNote['folderName'];
          }
        }
        mergedNotesMap[noteId] = note;
      }

      final mergedNotes = mergedNotesMap.values.toList();
      print('Merged notes: ${jsonEncode(mergedNotes)}');

      // Save to SharedPreferences
      await prefs.setString('notes', jsonEncode(mergedNotes));
      print('Saved ${mergedNotes.length} notes to SharedPreferences');
    } catch (e, stackTrace) {
      print('Error syncing notes to local: $e');
      print('Stack trace: $stackTrace');
    }
  }

  static Future<void> _syncLocalVerificationToFirestore(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final docRef = _firestore.collection('users').doc(userId);
    final docSnapshot = await docRef.get();

    if (docSnapshot.exists) {
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
      print(
        'Queued verification data sync to Firestore (will sync when online)',
      );
    }
  }

  static Future<void> syncVerificationOnLogin(String userId) async {
    _hasSyncedThisSession = false; // Reset to allow sync
    final prefs = await SharedPreferences.getInstance();
    final docRef = _firestore.collection('users').doc(userId);
    final docSnapshot = await docRef.get();

    if (docSnapshot.exists) {
      final data = docSnapshot.data()!;
      print(
        'Syncing verification data from Firestore (cached if offline): $data',
      );
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

    await _syncFirestoreNotesToLocal(userId);
    print('Completed syncVerificationOnLogin for user: $userId');
  }

  static Future<void> clearLocalDataOnLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    print('Cleared local data on logout');
  }

  static Future<List<Map<String, dynamic>>> loadNotesFromFirestore(
    String userId,
  ) async {
    final querySnapshot =
        await _firestore
            .collection('notes')
            .where('owner', isEqualTo: userId)
            .where('isDeleted', isEqualTo: false)
            .get();

    final notes =
        querySnapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
    print('Loaded ${notes.length} notes from Firestore (cached if offline)');
    return notes;
  }

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

    Future.delayed(const Duration(seconds: 10), () {
      _hideLoadingSpinner(context);
    });
  }

  static void _hideLoadingSpinner(BuildContext context) {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

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
        'Sync Notes...',
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
