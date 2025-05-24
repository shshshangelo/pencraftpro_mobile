// ignore_for_file: deprecated_member_use, unused_field, unused_element, use_build_context_synchronously, unused_local_variable

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pencraftpro/services/LogoutService.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';

class AccountSettings extends StatefulWidget {
  final bool allowAccessAfterSetup;
  const AccountSettings({super.key, this.allowAccessAfterSetup = false});

  @override
  State<AccountSettings> createState() => _AccountSettingsState();
}

class _AnimatedSpinnerSmall extends StatefulWidget {
  const _AnimatedSpinnerSmall();

  @override
  __AnimatedSpinnerSmallState createState() => __AnimatedSpinnerSmallState();
}

class __AnimatedSpinnerSmallState extends State<_AnimatedSpinnerSmall>
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
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.primaryContainer,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.4),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                Icons.settings,
                color: Theme.of(context).colorScheme.onPrimary,
                size: 30,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AccountSettingsState extends State<AccountSettings> {
  final _nameController = TextEditingController();
  final _idController = TextEditingController();
  final _teacherIdController = TextEditingController();
  String _selectedRole = 'Student';
  bool _isIdVerified = false;
  bool _isRoleSelected = false;
  String? _idNumberErrorText;
  String? _teacherIdErrorText;
  bool _isGoogleUser = false;
  String _fullName = '';
  String _profileInitials = 'U';
  String? _profilePictureUrl;
  bool _isNameEditable = true;
  int? _lastNameChangeTimestamp;
  bool _isNameVerified = false;
  bool _isFirstTimeUser = true;
  File? _customProfileImage;
  final bool _justLoadedAccountSettings = false;

  @override
  void initState() {
    super.initState();
    _initializeUserData();
  }

  bool _shouldShowFinalSpinner() {
    // For Google users, only need role and ID verification
    if (_isGoogleUser) {
      return _isRoleSelected && _isIdVerified;
    }
    // For non-Google users, need name verification too
    else {
      return _isNameVerified && _isRoleSelected && _isIdVerified;
    }
  }

  Future<void> _initializeUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final currentUser = FirebaseAuth.instance.currentUser;

    // Check if user is logged in
    if (currentUser == null) {
      debugPrint('No user logged in');
      return;
    }

    // Check if this is a Google user
    _isGoogleUser = currentUser.providerData.any(
      (info) => info.providerId == 'google.com',
    );

    // Initialize new Google user in Firestore if needed
    if (_isGoogleUser) {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid);
      final docSnapshot = await docRef.get();

      if (!docSnapshot.exists) {
        try {
          await docRef.set({
            'email': currentUser.email,
            'fullName': currentUser.displayName ?? '',
            'role': '',
            'createdAt': FieldValue.serverTimestamp(),
            'isNameVerified': true,
            'isRoleSelected': false,
            'isIdVerified': false,
            'isFirstTimeUser': true,
            'photoUrl': currentUser.photoURL ?? '',
          });
          debugPrint('Initialized new Google user in Firestore');
        } catch (e) {
          debugPrint('Failed to initialize Google user in Firestore: $e');
        }
      }
    }

    // Load data from SharedPreferences first
    setState(() {
      _fullName =
          prefs.getString('fullName') ??
          (_isGoogleUser ? currentUser.displayName ?? '' : '');
      _profileInitials = _getInitials(_fullName);
      _profilePictureUrl =
          prefs.getString('photoUrl') ??
          (_isGoogleUser ? currentUser.photoURL ?? '' : '');
      _isNameVerified = prefs.getBool('isNameVerified') ?? _isGoogleUser;
      _isRoleSelected = prefs.getBool('isRoleSelected') ?? false;
      _isIdVerified = prefs.getBool('isIdVerified') ?? false;
      _isFirstTimeUser = prefs.getBool('isFirstTimeUser') ?? true;
      _selectedRole = prefs.getString('selectedRole') ?? '';
      _lastNameChangeTimestamp = prefs.getInt('lastNameChangeTimestamp');

      // Set controller values
      _nameController.text = _fullName;
      if (_selectedRole == 'Student') {
        _idController.text = prefs.getString('studentId') ?? '';
      } else if (_selectedRole == 'Teacher') {
        _teacherIdController.text = prefs.getString('teacherId') ?? '';
      }
    });

    // Try to sync with Firestore if online
    try {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid);
      final docSnapshot = await docRef.get();

      if (docSnapshot.exists) {
        final data = docSnapshot.data()!;

        // Only update state if Firestore has newer data
        setState(() {
          if (!_isGoogleUser) {
            _fullName = data['fullName'] as String? ?? _fullName;
            _profilePictureUrl =
                data['photoUrl'] as String? ?? _profilePictureUrl;
            _nameController.text = _fullName;
          }
          _isNameVerified = data['isNameVerified'] as bool? ?? _isNameVerified;
          _isRoleSelected = data['isRoleSelected'] as bool? ?? _isRoleSelected;
          _isIdVerified = data['isIdVerified'] as bool? ?? _isIdVerified;
          _isFirstTimeUser =
              data['isFirstTimeUser'] as bool? ?? _isFirstTimeUser;

          // Always load role from Firestore for both Google and non-Google users
          if (data['role'] != null) {
            _selectedRole = data['role'] as String;
          } else {
            _selectedRole = 'Student';
          }

          // Load ID based on role
          final idNumber = data['idNumber'] as String?;
          if (idNumber != null) {
            if (_selectedRole == 'Student') {
              _idController.text = idNumber;
            } else {
              _teacherIdController.text = idNumber;
            }
          }
        });

        // Save the synced data back to SharedPreferences
        await _savePreferences();
      } else if (!_isGoogleUser) {
        // Initialize new user in Firestore
        try {
          await docRef.set({
            'email': currentUser.email,
            'fullName': '',
            'role': 'Student',
            'createdAt': FieldValue.serverTimestamp(),
            'isNameVerified': false,
            'isRoleSelected': false,
            'isIdVerified': false,
            'isFirstTimeUser': true,
            'photoUrl': '',
          }, SetOptions(merge: true));
          debugPrint('Initialized new email/password user in Firestore');
        } catch (e) {
          debugPrint(
            'Failed to initialize email/password user in Firestore: $e',
          );
        }
      }
    } catch (e) {
      debugPrint('Firestore unavailable, using SharedPreferences data: $e');
    }

    if (!_isGoogleUser) {
      _checkNameEditability();
    }

    await _loadCustomProfileImage();

    // Show loading spinner for first-time setup
    if (_isFirstTimeUser && _shouldShowFinalSpinner()) {
      await _showLoadingSpinner(
        'Please wait while we are creating your PenCraft Pro account.',
      );
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/select', (route) => false);
      }
    }
  }

  String _getInitials(String name) {
    final nameParts = name.trim().split(' ');
    if (nameParts.isEmpty || name.trim().isEmpty) return 'U';
    if (nameParts.length == 1) {
      return nameParts[0].isNotEmpty ? nameParts[0][0].toUpperCase() : 'U';
    }
    final firstInitial =
        nameParts[0].isNotEmpty ? nameParts[0][0].toUpperCase() : '';
    final lastInitial =
        nameParts.last.isNotEmpty ? nameParts.last[0].toUpperCase() : '';
    return '$firstInitial$lastInitial';
  }

  Future<void> _pickProfileImage() async {
    final status = await Permission.photos.request();
    if (!status.isGranted) {
      debugPrint('Gallery permission denied');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Gallery permission denied. Cannot access photos.',
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

    final prefs = await SharedPreferences.getInstance();
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    debugPrint('Picked image path: ${pickedFile?.path}');

    if (pickedFile != null) {
      final file = File(pickedFile.path);
      if (await file.exists()) {
        setState(() {
          _customProfileImage = file;
        });
        await prefs.setString('customProfileImagePath', pickedFile.path);
        await _uploadProfileImage(file);
        await _savePreferences();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Profile picture updated successfully.',
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
    }
  }

  Future<void> _takeProfilePicture() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Camera permission denied. Cannot take picture.',
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

    final prefs = await SharedPreferences.getInstance();
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);

    if (pickedFile != null) {
      final file = File(pickedFile.path);
      if (await file.exists()) {
        setState(() {
          _customProfileImage = file;
        });
        await prefs.setString('customProfileImagePath', pickedFile.path);
        await _uploadProfileImage(file);
        await _savePreferences();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Profile picture updated successfully.',
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
    }
  }

  Future<void> _removeProfileImage() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            title: Text(
              'Remove Profile Photo',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Are you sure you want to remove your profile photo?',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '⚠ You can only upload a new profile photo after 7 days.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                onPressed: () => Navigator.pop(context, false),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                child: Text(
                  'Remove',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onError,
                  ),
                ),
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
    );

    if (confirm == true) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final imageRef = FirebaseStorage.instance.ref().child(
            'profile_images/${user.uid}.jpg',
          );
          try {
            await imageRef.delete();
          } catch (e) {
            debugPrint('No image to delete or error: $e');
          }
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({'photoUrl': ''}, SetOptions(merge: true));
          await user.updatePhotoURL(null);
          await user.reload();
        }
      } catch (e) {
        debugPrint('Failed to remove profile image: $e');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('customProfileImagePath');
      await prefs.setString('photoUrl', '');
      setState(() {
        _customProfileImage = null;
        _profilePictureUrl = '';
      });
      await _savePreferences();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Profile photo removed successfully.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  Future<void> _loadCustomProfileImage() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('customProfileImagePath');
    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (await file.exists()) {
        setState(() {
          _customProfileImage = file;
        });
        debugPrint('Loaded custom profile image from: $path');
      } else {
        await prefs.remove('customProfileImagePath');
        debugPrint('Custom profile image not found, cleared path');
      }
    }
  }

  void _checkNameEditability() {
    if (_lastNameChangeTimestamp != null) {
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      const sevenDaysInMillis = 7 * 24 * 60 * 60 * 1000;
      _isNameEditable =
          currentTime - _lastNameChangeTimestamp! > sevenDaysInMillis;
    } else {
      _isNameEditable = true;
    }
    debugPrint('Name editability checked: _isNameEditable=$_isNameEditable');
  }

  Future<void> _saveGoogleUserToFirestore(User user) async {
    final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    try {
      await docRef.set({
        'email': user.email,
        'fullName': user.displayName ?? user.email!.split('@')[0],
        'role': _selectedRole,
        'createdAt': FieldValue.serverTimestamp(),
        'isNameVerified': _isNameVerified,
        'isRoleSelected': _isRoleSelected,
        'isIdVerified': _isIdVerified,
        'isFirstTimeUser': _isFirstTimeUser,
        'photoUrl': user.photoURL ?? '',
      }, SetOptions(merge: true));
      debugPrint('Saved Google user to Firestore');
    } catch (e) {
      debugPrint('Failed to save Google user to Firestore: $e');
    }
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();

    // Save basic profile information
    await prefs.setString('fullName', _fullName);
    await prefs.setString('profileInitials', _profileInitials);
    await prefs.setString('selectedRole', _selectedRole);
    await prefs.setString('photoUrl', _profilePictureUrl ?? '');

    // Save ID information
    await prefs.setString('studentId', _idController.text.trim());
    await prefs.setString('teacherId', _teacherIdController.text.trim());

    // Save verification flags
    await prefs.setBool('isIdVerified', _isIdVerified);
    await prefs.setBool('isNameVerified', _isNameVerified);
    await prefs.setBool('isRoleSelected', _isRoleSelected);
    await prefs.setBool('isFirstTimeUser', _isFirstTimeUser);

    // Save timestamps
    if (_lastNameChangeTimestamp != null) {
      await prefs.setInt('lastNameChangeTimestamp', _lastNameChangeTimestamp!);
    }

    // Save profile image path if exists
    if (_customProfileImage != null) {
      await prefs.setString(
        'customProfileImagePath',
        _customProfileImage!.path,
      );
    }

    // Save user ID for offline reference
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await prefs.setString('userId', user.uid);
    }

    debugPrint(
      'Saved preferences: fullName=$_fullName, role=$_selectedRole, isNameVerified=$_isNameVerified, isRoleSelected=$_isRoleSelected, isIdVerified=$_isIdVerified, isFirstTimeUser=$_isFirstTimeUser',
    );
  }

  Future<void> _updateUserFirestoreData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('No user logged in');
      return;
    }

    // Save to SharedPreferences first (works offline)
    await _savePreferences();

    // Attempt to save to Firestore
    String? downloadUrl;
    if (!_isGoogleUser && _customProfileImage != null) {
      final file = File(_customProfileImage!.path);
      final ref = FirebaseStorage.instance
          .ref()
          .child('profile_images')
          .child('${user.uid}.jpg');
      try {
        await ref.putFile(file);
        downloadUrl = await ref.getDownloadURL();
      } catch (e) {
        debugPrint('Failed to upload profile image: $e');
      }
    }

    final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final dataToUpdate = {
      'fullName': _fullName,
      'role': _selectedRole,
      'idNumber':
          _selectedRole == 'Student'
              ? _idController.text.trim()
              : _teacherIdController.text.trim(),
      'photoUrl':
          downloadUrl ??
          (_isGoogleUser ? _profilePictureUrl ?? '' : _profilePictureUrl ?? ''),
      'isNameVerified': _isNameVerified,
      'isRoleSelected': _isRoleSelected,
      'isIdVerified': _isIdVerified,
      'isFirstTimeUser': _isFirstTimeUser,
      'lastNameChangeTimestamp': _lastNameChangeTimestamp,
    };

    try {
      await docRef.set(dataToUpdate, SetOptions(merge: true));
      debugPrint('Firestore updated: fullName=$_fullName, role=$_selectedRole');
    } catch (e) {
      debugPrint('Failed to update Firestore: $e');
    }
  }

  Future<void> _syncState() async {
    await _savePreferences();
    await _updateUserFirestoreData();
  }

  void _showProfileOptions() {
    final hasProfilePicture =
        (_profilePictureUrl != null && _profilePictureUrl!.isNotEmpty) ||
        _customProfileImage != null;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (BuildContext context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Icons.photo_library,
                size: 22,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              title: Text(
                'Import from Gallery',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontSize: 14),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickProfileImage();
              },
            ),
            ListTile(
              leading: Icon(
                Icons.photo_camera,
                size: 22,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              title: Text(
                'Take a Picture',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontSize: 14),
              ),
              onTap: () {
                Navigator.pop(context);
                _takeProfilePicture();
              },
            ),
            if (hasProfilePicture)
              ListTile(
                leading: Icon(
                  Icons.delete,
                  size: 22,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                title: Text(
                  'Remove Profile Photo',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontSize: 14),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _removeProfileImage();
                },
              ),
            const SizedBox(height: 10),
          ],
        );
      },
    );
  }

  Future<void> _saveName() async {
    final user = FirebaseAuth.instance.currentUser;
    final newName = _nameController.text.trim();

    if (!_isGoogleUser && user != null && newName.isNotEmpty) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            title: Text(
              'Confirm Name Change',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
            content: Text(
              'Is this correct? Full Name: $newName\nYou won\'t be able to change it again for 3 days.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            actions: [
              TextButton(
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                child: Text(
                  'Confirm',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
                onPressed: () async {
                  Navigator.of(context).pop();

                  // Get current photoUrl before updating
                  final currentPhotoUrl = _profilePictureUrl ?? '';

                  setState(() {
                    _fullName = newName;
                    _profileInitials = _getInitials(_fullName);
                    _isNameEditable = false;
                    _lastNameChangeTimestamp =
                        DateTime.now().millisecondsSinceEpoch;
                    _isNameVerified = true;
                    _isFirstTimeUser = false;
                  });

                  // Update Firestore with all user data including photoUrl
                  try {
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.uid)
                        .update({
                          'fullName': newName,
                          'isNameVerified': true,
                          'isRoleSelected': _isRoleSelected,
                          'isIdVerified': _isIdVerified,
                          'isFirstTimeUser': false,
                          'lastNameChangeTimestamp': _lastNameChangeTimestamp,
                          'photoUrl': currentPhotoUrl, // Preserve the photoUrl
                        });
                  } catch (e) {
                    debugPrint('Error updating Firestore: $e');
                  }

                  // Update SharedPreferences
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('fullName', newName);
                  await prefs.setString('profileInitials', _profileInitials);
                  await prefs.setBool('isNameVerified', true);
                  await prefs.setBool('isRoleSelected', _isRoleSelected);
                  await prefs.setBool('isIdVerified', _isIdVerified);
                  await prefs.setBool('isFirstTimeUser', false);
                  await prefs.setInt(
                    'lastNameChangeTimestamp',
                    _lastNameChangeTimestamp!,
                  );
                  await prefs.setString(
                    'photoUrl',
                    currentPhotoUrl,
                  ); // Preserve the photoUrl

                  if (_shouldShowFinalSpinner()) {
                    await _showLoadingSpinner(
                      'Please wait while we are creating your PenCraft Pro account.',
                    );
                    if (mounted) {
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        '/select',
                        (route) => false,
                      );
                    }
                  }
                },
              ),
            ],
          );
        },
      );
    }
  }

  Future<bool> _isIdDuplicate(String id) async {
    try {
      final querySnapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .where('idNumber', isEqualTo: id)
              .get();

      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking for duplicate ID: $e');
      return false;
    }
  }

  void _verifyId() async {
    final id = _idController.text.trim();
    if (id.length != 11 || !RegExp(r'^\d{11}$').hasMatch(id)) {
      setState(() {
        _idNumberErrorText = 'Student ID No. must be exactly 11 digits.';
      });
      debugPrint('Student ID verification failed: invalid format');
      return;
    }

    // Check for duplicate ID
    final isDuplicate = await _isIdDuplicate(id);
    if (isDuplicate) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'This Student ID No. is already registered.',
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

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text(
            'Confirm Student ID No. Verification',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          content: Text(
            'Is this correct? Student ID No.: $id\nOnce verified, you can\'t change it.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          actions: [
            TextButton(
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              child: Text(
                'Confirm',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
              onPressed: () async {
                Navigator.of(context).pop();
                setState(() {
                  _isIdVerified = true;
                  _idNumberErrorText = null;
                  _isFirstTimeUser = false;
                });
                await _syncState();

                if (_shouldShowFinalSpinner()) {
                  await _showLoadingSpinner(
                    'Please wait while we are creating your PenCraft Pro account.',
                  );
                  if (mounted) {
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/select',
                      (route) => false,
                    );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _verifyTeacherId() async {
    final teacherId = _teacherIdController.text.trim();
    if (teacherId.length != 11 || !RegExp(r'^\d{11}$').hasMatch(teacherId)) {
      setState(() {
        _teacherIdErrorText = 'Teacher ID No. must be exactly 11 digits.';
      });
      debugPrint('Teacher ID verification failed: invalid format');
      return;
    }

    // Check for duplicate ID
    final isDuplicate = await _isIdDuplicate(teacherId);
    if (isDuplicate) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'This Teacher ID No. is already registered.',
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

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text(
            'Confirm Teacher ID No. Verification',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          content: Text(
            'Is this correct? Teacher ID No.: $teacherId\nOnce verified, you can\'t change it.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          actions: [
            TextButton(
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              child: Text(
                'Confirm',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
              onPressed: () async {
                Navigator.of(context).pop();
                setState(() {
                  _isIdVerified = true;
                  _teacherIdErrorText = null;
                  _isFirstTimeUser = false;
                });
                await _syncState();

                if (_shouldShowFinalSpinner()) {
                  await _showLoadingSpinner(
                    'Please wait while we are creating your PenCraft Pro account.',
                  );
                  if (mounted) {
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/select',
                      (route) => false,
                    );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showLoadingSpinner(String message) async {
    debugPrint('Showing loading spinner: $message');
    final currentContext = context;
    final overlayEntry = OverlayEntry(
      builder:
          (context) => Material(
            color: Theme.of(context).colorScheme.scrim.withOpacity(0.5),
            child: Center(
              child: Container(
                width: 200,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).colorScheme.shadow.withOpacity(0.2),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _AnimatedSpinnerSmall(),
                    const SizedBox(height: 16),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );

    Overlay.of(currentContext, rootOverlay: true).insert(overlayEntry);
    await Future.delayed(const Duration(seconds: 2));

    // Update _isFirstTimeUser in Firestore and SharedPreferences
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'isFirstTimeUser': false});

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isFirstTimeUser', false);

        setState(() {
          _isFirstTimeUser = false;
        });
      } catch (e) {
        debugPrint('Failed to update isFirstTimeUser: $e');
      }
    }

    if (mounted) {
      overlayEntry.remove();
      Navigator.pushNamedAndRemoveUntil(context, '/select', (route) => false);
    }
  }

  bool _isProfileSetupComplete() {
    if (_isGoogleUser) {
      return _isRoleSelected && _isIdVerified;
    } else {
      return _isNameVerified && _isRoleSelected && _isIdVerified;
    }
  }

  Future<bool> _onWillPop() async {
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Only show "No data available" if we're not in the middle of profile setup
    if (_fullName.isEmpty &&
        !_isGoogleUser &&
        !_isFirstTimeUser &&
        _isNameVerified) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'No data available. Please connect to the internet.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ),
      );
    }

    bool isLikelyEmail(String text) {
      final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
      return emailRegex.hasMatch(text);
    }

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        drawer: Drawer(
          backgroundColor: Theme.of(context).colorScheme.surface,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Container(
                height: 200,
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/aclc.png'),
                    fit: BoxFit.contain,
                    colorFilter: ColorFilter.mode(
                      Colors.black12,
                      BlendMode.srcATop,
                    ),
                  ),
                ),
              ),
              Divider(
                thickness: 2,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              _drawerItem(context, Icons.note, 'Notes', '/notes'),
              _drawerItem(context, Icons.alarm, 'Reminders', '/reminders'),
              Divider(
                thickness: 1,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              _drawerItem(context, Icons.label, 'Labels', '/labels'),
              Divider(
                thickness: 1,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              _drawerItem(context, Icons.folder, 'Folders', '/folders'),
              _drawerItem(context, Icons.archive, 'Archive', '/archive'),
              _drawerItem(context, Icons.delete, 'Recycle Bin', '/deleted'),
              ListTile(
                leading: Icon(
                  Icons.settings,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(
                  'Account Settings',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                selected: true,
                selectedTileColor: Theme.of(
                  context,
                ).colorScheme.primary.withOpacity(0.1),
                onTap: () {},
              ),
              Divider(
                thickness: 1,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              ListTile(
                leading: Icon(Icons.logout),
                title: Text(
                  'Logout',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                onTap: () => showLogoutDialog(context),
              ),
            ],
          ),
        ),
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          leading: Builder(
            builder:
                (context) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () {
                    debugPrint('Opening Drawer');
                    Scaffold.of(context).openDrawer();
                  },
                ),
          ),
          title: Text(
            'Account Settings',
            style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'User Information',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 45,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      backgroundImage:
                          _profilePictureUrl != null &&
                                  _profilePictureUrl!.isNotEmpty
                              ? NetworkImage(_profilePictureUrl!)
                              : (_customProfileImage != null
                                  ? FileImage(_customProfileImage!)
                                  : null),
                      child:
                          (_profilePictureUrl == null ||
                                      _profilePictureUrl!.isEmpty) &&
                                  _customProfileImage == null
                              ? Text(
                                _profileInitials,
                                style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.onPrimary,
                                  fontSize: 30,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                              : null,
                    ),
                    if (!_isGoogleUser)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: InkWell(
                          onTap: _showProfileOptions,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(6),
                            child: Icon(
                              Icons.camera_alt,
                              size: 20,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  _fullName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Full Name',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _nameController,
                style: TextStyle(
                  fontSize: 15,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                enabled: !_isGoogleUser && _isNameEditable && !_isNameVerified,
                readOnly: _isGoogleUser || _isNameVerified,
                textCapitalization: TextCapitalization.words,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
                  TextInputFormatter.withFunction((oldValue, newValue) {
                    // Capitalize first letter of each word
                    if (newValue.text.isEmpty) return newValue;
                    final words = newValue.text.split(' ');
                    final capitalizedWords = words.map((word) {
                      if (word.isEmpty) return word;
                      return word[0].toUpperCase() +
                          word.substring(1).toLowerCase();
                    });
                    return TextEditingValue(
                      text: capitalizedWords.join(' '),
                      selection: newValue.selection,
                    );
                  }),
                ],
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: 'Enter your full name',
                  hintStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 12,
                  ),
                  suffixIcon:
                      (!_isGoogleUser && !_isNameVerified)
                          ? IconButton(
                            icon: Icon(
                              Icons.check,
                              size: 20,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            onPressed: _isNameEditable ? _saveName : null,
                            tooltip: 'Save Name',
                          )
                          : null,
                ),
              ),
              if (_isGoogleUser)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Full Name is linked to your Google account already.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Full Name Verified',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
              if (!_isGoogleUser &&
                  !_isNameVerified &&
                  (isLikelyEmail(_nameController.text.trim()) ||
                      _nameController.text.trim().isEmpty))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Please update your full name.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (!_isGoogleUser && _isNameVerified)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Full Name Verified',
                    style: const TextStyle(fontSize: 14, color: Colors.green),
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                'Account Settings',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.email,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    user.email ?? 'No email',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (!_isGoogleUser)
                Row(
                  children: [
                    Icon(
                      Icons.lock,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed:
                          () => Navigator.pushNamed(context, '/changepassword'),
                      child: Text(
                        'Change Password',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              Text(
                'Role Selection',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              if (!_isRoleSelected)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '⚠ Please select your role to proceed.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _showRoleSelectionDialog,
                      icon: Icon(
                        Icons.edit,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                      label: Text(
                        'Select Role',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                        foregroundColor: Theme.of(context).colorScheme.onError,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        textStyle: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selected Role: $_selectedRole',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _showRoleSelectionDialog,
                      icon: Icon(
                        Icons.edit,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                      label: Text(
                        'Change Role',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor:
                            Theme.of(context).colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        textStyle: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              if (_selectedRole == 'Student' &&
                  !_isIdVerified &&
                  _isRoleSelected)
                TextField(
                  controller: _idController,
                  keyboardType: TextInputType.number,
                  maxLength: 11,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(
                    fontSize: 15,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  enabled: !_isIdVerified,
                  decoration: InputDecoration(
                    labelText: 'Student ID No. (11 digits)',
                    labelStyle: TextStyle(
                      fontSize: 15,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    border: const OutlineInputBorder(),
                    errorText: _idNumberErrorText,
                    errorStyle: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    counterText: '',
                    suffixIcon: IconButton(
                      icon: Icon(
                        Icons.check,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      onPressed: _isIdVerified ? null : _verifyId,
                      tooltip: 'Verify Student ID No.',
                    ),
                  ),
                ),
              if (_selectedRole == 'Teacher' &&
                  !_isIdVerified &&
                  _isRoleSelected)
                TextField(
                  controller: _teacherIdController,
                  keyboardType: TextInputType.number,
                  maxLength: 11,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(
                    fontSize: 15,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  enabled: !_isIdVerified,
                  decoration: InputDecoration(
                    labelText: 'Teacher ID No. (11 digits)',
                    labelStyle: TextStyle(
                      fontSize: 15,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    border: const OutlineInputBorder(),
                    errorText: _teacherIdErrorText,
                    errorStyle: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    counterText: '',
                    suffixIcon: IconButton(
                      icon: Icon(
                        Icons.check,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      onPressed: _isIdVerified ? null : _verifyTeacherId,
                      tooltip: 'Verify Teacher ID No.',
                    ),
                  ),
                ),
              if (_isIdVerified && _selectedRole == 'Student')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Student ID No. Verified: ${_idController.text}',
                    style: const TextStyle(fontSize: 14, color: Colors.green),
                  ),
                ),
              if (_isIdVerified && _selectedRole == 'Teacher')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Teacher ID No. Verified: ${_teacherIdController.text}',
                    style: const TextStyle(fontSize: 14, color: Colors.green),
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                'Help & About',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              ListTile(
                leading: Icon(
                  Icons.help_outline,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                title: Text(
                  'How to Use the App',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                onTap: () => Navigator.pushNamed(context, '/howtouse'),
              ),
              ListTile(
                leading: Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                title: Text(
                  'About the App',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                onTap: () => Navigator.pushNamed(context, '/about'),
              ),
              ListTile(
                leading: Icon(
                  Icons.question_answer,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                title: Text(
                  'FAQs',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                onTap: () => Navigator.pushNamed(context, '/faqs'),
              ),
              ListTile(
                leading: Icon(
                  Icons.group,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                title: Text(
                  'About the Team',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                onTap: () => Navigator.pushNamed(context, '/team'),
              ),
            ],
          ),
        ),
        bottomNavigationBar: BottomAppBar(
          color: Theme.of(context).colorScheme.error,
          shape: const CircularNotchedRectangle(),
          notchMargin: 10.0,
          child: IconButton(
            icon: Icon(
              Icons.home,
              color: Theme.of(context).colorScheme.onError,
            ),
            iconSize: 32,
            onPressed: () => Navigator.pushNamed(context, '/select'),
            tooltip: 'Go to Home',
          ),
        ),
      ),
    );
  }

  void _showRoleSelectionDialog() {
    if (_isRoleSelected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Role is already selected and cannot be changed.',
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

    String? tempSelectedRole;
    const List<String> roles = ['Student', 'Teacher'];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (roles.isEmpty) {
              return AlertDialog(
                backgroundColor: Theme.of(context).colorScheme.surface,
                title: Text(
                  'Error',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                content: Text(
                  'No roles available. Please try again.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'OK',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              );
            }

            return AlertDialog(
              backgroundColor: Theme.of(context).colorScheme.surface,
              title: Text(
                'Select Your Role',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButton<String>(
                    value: tempSelectedRole,
                    isExpanded: true,
                    hint: Text(
                      'Choose your role',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    dropdownColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    items:
                        roles.map((role) {
                          return DropdownMenuItem<String>(
                            value: role,
                            child: Text(
                              role,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          );
                        }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() {
                          tempSelectedRole = value;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed:
                      tempSelectedRole == null
                          ? null
                          : () async {
                            Navigator.pop(context);

                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) {
                                return AlertDialog(
                                  backgroundColor:
                                      Theme.of(context).colorScheme.surface,
                                  title: Text(
                                    'Confirm Role Selection',
                                    style: TextStyle(
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                    ),
                                  ),
                                  content: Text(
                                    'Are you sure you want to select "$tempSelectedRole" as your role?\n\nYou cannot change it after ID verification.',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed:
                                          () => Navigator.pop(context, false),
                                      child: Text(
                                        'Cancel',
                                        style: TextStyle(
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    ElevatedButton(
                                      onPressed:
                                          () => Navigator.pop(context, true),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                        foregroundColor:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onPrimary,
                                      ),
                                      child: Text(
                                        'Confirm',
                                        style: TextStyle(
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onPrimary,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );

                            if (confirm == true && tempSelectedRole != null) {
                              setState(() {
                                _selectedRole = tempSelectedRole!;
                                _isRoleSelected = true;
                                _isIdVerified = false;
                                _idController.clear();
                                _teacherIdController.clear();
                              });
                              await _syncState();

                              if (_isGoogleUser &&
                                  _isRoleSelected &&
                                  _isIdVerified) {
                                await _showLoadingSpinner(
                                  'Please wait while we are creating your PenCraft Pro account.',
                                );
                              }
                            }
                          },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  child: Text(
                    'Continue',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  ListTile _drawerItem(
    BuildContext context,
    IconData icon,
    String label,
    String route,
  ) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.onSurface),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      onTap: () async {
        if (!_isProfileSetupComplete()) {
          if (!mounted) return;
          await showDialog(
            context: context,
            builder:
                (context) => AlertDialog(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  title: Text(
                    'Incomplete Profile Setup',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  content: Text(
                    'Please complete your profile setup before leaving this page.\n\nRequired steps:\n${!_isNameVerified && !_isGoogleUser ? '• Set your full name\n' : ''}${!_isRoleSelected ? '• Select your role\n' : ''}${!_isIdVerified ? '• Verify your ID number' : ''}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'OK',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
          );
          return;
        }
        debugPrint('Navigating to $route');
        Navigator.pushNamed(context, route);
      },
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    _teacherIdController.dispose();
    super.dispose();
  }

  Future<void> _uploadProfileImage(File file) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('profile_images')
          .child('${user.uid}.jpg');

      final uploadTask = await ref.putFile(file);
      final downloadUrl = await ref.getDownloadURL();

      final userDoc = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);

      final docSnapshot = await userDoc.get();
      if (!docSnapshot.exists) {
        await userDoc.set({
          'email': user.email,
          'photoUrl': downloadUrl,
          'lastProfileUpdate': FieldValue.serverTimestamp(),
        });
      } else {
        await userDoc.update({
          'photoUrl': downloadUrl,
          'lastProfileUpdate': FieldValue.serverTimestamp(),
        });
      }

      await user.updatePhotoURL(downloadUrl);
      await user.reload();

      setState(() {
        _profilePictureUrl = downloadUrl;
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('photoUrl', downloadUrl);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Profile picture updated successfully.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
    }
  }
}
