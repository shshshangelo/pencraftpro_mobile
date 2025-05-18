import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class DrawingSyncService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static bool _isSyncing = false;
  static OverlayEntry? _overlayEntry;
  static bool _hasSyncedThisSession = false;

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

      // Show loading spinner when coming back online
      if (!isOffline) {
        _showLoadingSpinner(context);
      }

      await _syncDrawings(context, isOffline: isOffline);

      // Hide loading spinner after sync completes
      if (!isOffline) {
        _hideLoadingSpinner(context);
      }

      _hasSyncedThisSession = true;

      if (onComplete != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onComplete();
        });
      }
    } catch (e, stackTrace) {
      print('Drawing sync error: $e');
      print('Stack trace: $stackTrace');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Drawing sync failed: $e.',
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

  static Future<void> _syncDrawings(
    BuildContext context, {
    required bool isOffline,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (!isOffline) {
      await _syncLocalDrawingsToFirestore(user.uid);
      await _syncFirestoreDrawingsToLocal(user.uid);
    } else {
      print('Offline: Skipping Firestore sync, using local data');
    }
  }

  static Future<void> _syncLocalDrawingsToFirestore(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final String? drawingsString = prefs
        .getStringList('saved_drawings')
        ?.join('\n');

    // Fetch user data to include email and fullName
    String userEmail = FirebaseAuth.instance.currentUser?.email ?? '';
    String fullName = '';
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();

      if (userDoc.exists) {
        final userData = userDoc.data()!;
        fullName = userData['fullName'] ?? '';
        userEmail = userData['email'] ?? userEmail;
      }
    } catch (e) {
      print('Error fetching user data: $e');
      // Continue with sync even if user data fetch fails
    }

    if (drawingsString != null) {
      final List<String> drawings = drawingsString.split('\n');
      for (var drawing in drawings) {
        final parts = drawing.split('|');
        if (parts.length >= 3) {
          final fileName = parts[0];
          final title = parts[2];

          // Get the drawing state file
          final directory = await getApplicationDocumentsDirectory();
          final statePath = '${directory.path}/$fileName.json';
          final imagePath = '${directory.path}/$fileName.png';

          if (await File(statePath).exists() &&
              await File(imagePath).exists()) {
            final stateFile = File(statePath);
            final imageFile = File(imagePath);

            final stateJson = await stateFile.readAsString();
            final imageBytes = await imageFile.readAsBytes();

            await _firestore.collection('drawings').doc(fileName).set({
              'title': title,
              'imageData': base64Encode(imageBytes),
              'state': jsonDecode(stateJson),
              'createdAt': FieldValue.serverTimestamp(),
              'owner': userId,
              'email': userEmail,
              'fullName': fullName,
            }, SetOptions(merge: true));
          }
        }
      }
      print('Synced local drawings to Firestore (queued if offline)');
    }
  }

  static Future<void> _syncFirestoreDrawingsToLocal(String userId) async {
    try {
      print('Starting drawing sync for user: $userId');

      final drawingsSnapshot =
          await _firestore
              .collection('drawings')
              .where('owner', isEqualTo: userId)
              .get();

      print(
        'Fetched ${drawingsSnapshot.docs.length} drawings (cached if offline)',
      );

      final prefs = await SharedPreferences.getInstance();
      final savedDrawings = prefs.getStringList('saved_drawings') ?? [];
      final Map<String, String> localDrawings = {};

      // Create a map of existing local drawings
      for (var drawing in savedDrawings) {
        final parts = drawing.split('|');
        if (parts.isNotEmpty) {
          localDrawings[parts[0]] = drawing;
        }
      }

      // Process Firestore drawings
      for (var doc in drawingsSnapshot.docs) {
        final data = doc.data();
        final fileName = doc.id;
        final title = data['title'] ?? 'Untitled Drawing';
        final imageData = data['imageData'] as String?;
        final state = data['state'] as Map<String, dynamic>?;
        final createdAt =
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

        if (imageData != null && state != null) {
          // Save image file
          final directory = await getApplicationDocumentsDirectory();
          final imagePath = '${directory.path}/$fileName.png';
          final statePath = '${directory.path}/$fileName.json';

          await File(imagePath).writeAsBytes(base64Decode(imageData));
          await File(statePath).writeAsString(jsonEncode(state));

          // Update or add to saved drawings list
          final drawingEntry =
              '$fileName|${createdAt.toIso8601String()}|$title';
          localDrawings[fileName] = drawingEntry;
        }
      }

      // Update SharedPreferences with merged drawings
      await prefs.setStringList(
        'saved_drawings',
        localDrawings.values.toList(),
      );
      print('Saved ${localDrawings.length} drawings to SharedPreferences');
    } catch (e, stackTrace) {
      print('Error syncing drawings to local: $e');
      print('Stack trace: $stackTrace');
    }
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

  // New function to update existing drawings with missing email and fullName
  static Future<void> updateExistingDrawingsWithUserInfo(
    BuildContext context,
  ) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // First get the user info
      String userEmail = user.email ?? '';
      String fullName = '';
      try {
        final userDoc =
            await _firestore.collection('users').doc(user.uid).get();

        if (userDoc.exists) {
          final userData = userDoc.data()!;
          fullName = userData['fullName'] ?? '';
          userEmail = userData['email'] ?? userEmail;
        } else {
          print('User document not found, using default values');
        }
      } catch (e) {
        print('Error fetching user data: $e');
        return;
      }

      // Get all drawings for this user (either by uid or owner field)
      final drawingsQuery =
          await _firestore
              .collection('drawings')
              .where('owner', isEqualTo: user.uid)
              .get();

      final drawingsQueryUid =
          await _firestore
              .collection('drawings')
              .where('uid', isEqualTo: user.uid)
              .get();

      final allDrawings = [...drawingsQuery.docs, ...drawingsQueryUid.docs];
      final uniqueIds = <String>{};
      final uniqueDrawings =
          allDrawings.where((doc) => uniqueIds.add(doc.id)).toList();

      print('Found ${uniqueDrawings.length} drawings to update');

      // Update each drawing with the user info
      int updatedCount = 0;
      for (final doc in uniqueDrawings) {
        try {
          await _firestore.collection('drawings').doc(doc.id).update({
            'email': userEmail,
            'fullName': fullName,
          });
          updatedCount++;
        } catch (e) {
          print('Error updating drawing ${doc.id}: $e');
        }
      }

      print('Updated $updatedCount drawings with user info');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Updated $updatedCount drawings with your user info',
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
    } catch (e, stackTrace) {
      print('Error updating existing drawings: $e');
      print('Stack trace: $stackTrace');
    }
  }

  static Future<void> syncDrawings(
    BuildContext context, {
    bool showProgress = true,
    bool isOffline = false,
  }) async {
    // Prevent multiple syncs at once
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      if (showProgress) {
        _showLoadingSpinner(context);
      }
      await _syncDrawings(context, isOffline: isOffline);

      // Update existing drawings with user info if we're online
      if (!isOffline) {
        await updateExistingDrawingsWithUserInfo(context);
      }
    } catch (e, stackTrace) {
      print('Drawing sync error: $e');
      print('Stack trace: $stackTrace');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Drawing sync failed: $e.',
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
        'Sync Drawings...',
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
