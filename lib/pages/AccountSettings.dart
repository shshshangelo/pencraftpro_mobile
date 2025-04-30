import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pencraftpro/services/logout_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_storage/firebase_storage.dart';

class AccountSettings extends StatefulWidget {
  const AccountSettings({super.key});

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
                gradient: const RadialGradient(
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
              child: const Icon(Icons.settings, color: Colors.white, size: 30),
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
  String _profileInitials = '';
  String? _profilePictureUrl;
  bool _isNameEditable = false;
  int? _lastNameChangeTimestamp;
  bool _isNameVerified = false;
  bool _isFirstTimeUser = true;
  File? _customProfileImage;
  bool _verificationSnackShown = false;

  @override
  void initState() {
    super.initState();
    _initializeUserData();
  }

  Future<void> _initializeUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final currentUser = FirebaseAuth.instance.currentUser;
    await currentUser?.reload();
    final user = FirebaseAuth.instance.currentUser;

    final storedUserId = prefs.getString('userId');

    if (user != null && storedUserId != null && storedUserId != user.uid) {
      await prefs.clear();
      await prefs.setString('userId', user.uid);
    } else if (user != null && storedUserId == null) {
      await prefs.setString('userId', user.uid);
    }

    final savedPhotoUrl = prefs.getString('photoUrl');
    if (savedPhotoUrl != null && savedPhotoUrl.isNotEmpty) {
      if (mounted) {
        setState(() {
          _profilePictureUrl = savedPhotoUrl;
        });
      }
    }

    // Initialize defaults
    _isGoogleUser = user != null &&
        user.providerData.any((info) => info.providerId == 'google.com');

    if (user != null) {
      final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final docSnapshot = await docRef.get();

      // Set Google user data immediately
      if (_isGoogleUser) {
        if (mounted) {
          setState(() {
            _fullName = user.displayName ?? user.email!.split('@')[0];
            _profilePictureUrl = user.photoURL;
            _profileInitials = _getInitials(_fullName);
            _isNameVerified = true;
            _nameController.text = _fullName;
          });
        }
        await prefs.setString('fullName', _fullName);
        await prefs.setString('profileInitials', _profileInitials);
        await prefs.setBool('isNameVerified', true);
        await _saveGoogleUserToFirestore(user);
      }

      // Load Firestore data or initialize
      if (docSnapshot.exists) {
        final data = docSnapshot.data()!;
        if (mounted) {
          setState(() {
            _isNameVerified = data['isNameVerified'] as bool? ?? _isGoogleUser;
            _isRoleSelected = data['isRoleSelected'] as bool? ?? false;
            _isIdVerified = data['isIdVerified'] as bool? ?? false;
            _isFirstTimeUser = data['isFirstTimeUser'] as bool? ?? true;
            // Only override _fullName if not a Google user
            if (!_isGoogleUser) {
              _fullName = data['fullName'] as String? ?? '';
              _nameController.text = _fullName;
            }
            _profileInitials = _getInitials(_fullName);
            _selectedRole = ['Student', 'Teacher'].contains(data['role'])
                ? data['role'] as String
                : 'Student';
            if (_selectedRole == 'Student') {
              _idController.text = data['idNumber'] as String? ?? '';
            } else {
              _teacherIdController.text = data['idNumber'] as String? ?? '';
            }
          });
        }
      } else {
        // Initialize Firestore document
        await docRef.set({
          'email': user.email,
          'fullName': _isGoogleUser ? _fullName : '',
          'role': 'Student',
          'createdAt': FieldValue.serverTimestamp(),
          'isNameVerified': _isGoogleUser,
          'isRoleSelected': false,
          'isIdVerified': false,
          'isFirstTimeUser': true,
        }, SetOptions(merge: true));
      }

      // Non-Google user fallback
      if (!_isGoogleUser) {
        _fullName = docSnapshot.exists
            ? (docSnapshot.data()!['fullName'] as String? ?? '')
            : prefs.getString('fullName') ?? '';
        _profileInitials = _getInitials(_fullName);
        _isNameVerified = docSnapshot.exists
            ? (docSnapshot.data()!['isNameVerified'] as bool? ?? false)
            : prefs.getBool('isNameVerified') ?? false;
        _nameController.text = _fullName;
        _checkNameEditability();
      }
    }

    await _loadCustomProfileImage();
    await _loadVerificationSnackStatus();
  }

  Future<void> _pickProfileImage() async {
    final status = await Permission.photos.request();
    if (!status.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gallery permission denied. Cannot access photos.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final lastChange = prefs.getInt('lastProfileChangeTimestamp');
    final now = DateTime.now().millisecondsSinceEpoch;
    const limit = 7 * 24 * 60 * 60 * 1000;

    if (lastChange != null && now - lastChange < limit) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You can only change your profile photo once every 7 days.',
          ),
          backgroundColor: Colors.black,
        ),
      );
      return;
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      final file = File(pickedFile.path);

      setState(() {
        _profilePictureUrl = pickedFile.path;
        _customProfileImage = file;
      });

      await prefs.setString('customProfileImagePath', pickedFile.path);
      await prefs.setInt('lastProfileChangeTimestamp', now);

      await _uploadProfileImage(file);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile picture updated successfully.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _showSuccessAndRedirect() async {
    final overlayEntry = OverlayEntry(
      builder: (context) => Material(
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
                const _AnimatedSpinnerSmall(),
                const SizedBox(height: 16),
                const Text(
                  'Please wait while we are setting up your account...',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black87,
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

    Overlay.of(context, rootOverlay: true).insert(overlayEntry);

    await Future.delayed(const Duration(seconds: 5));

    if (mounted) {
      overlayEntry.remove();
      Navigator.pushNamedAndRemoveUntil(context, '/select', (route) => false);
    }
  }

  Future<void> _checkAllVerifications() async {
    if (_isNameVerified &&
        _isRoleSelected &&
        _isIdVerified &&
        _isFirstTimeUser) {
      setState(() {
        _isFirstTimeUser = false;
      });
      await _updateUserFirestoreData();
      await _showSuccessAndRedirect();
    }
  }

  Future<void> _updateUserFirestoreData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String? downloadUrl;

    if (!_isGoogleUser && _customProfileImage != null) {
      final file = File(_customProfileImage!.path);
      final ref = FirebaseStorage.instance
          .ref()
          .child('profile_images')
          .child('${user.uid}.jpg');

      await ref.putFile(file);
      downloadUrl = await ref.getDownloadURL();
    }

    final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

    final dataToUpdate = {
      'fullName': _fullName,
      'role': _selectedRole,
      'idNumber': _selectedRole == 'Student'
          ? _idController.text.trim()
          : _teacherIdController.text.trim(),
      'profileImage': _isGoogleUser ? _profilePictureUrl ?? '' : downloadUrl ?? '',
      'isNameVerified': _isNameVerified,
      'isRoleSelected': _isRoleSelected,
      'isIdVerified': _isIdVerified,
      'isFirstTimeUser': _isFirstTimeUser,
    };

    await docRef.set(dataToUpdate, SetOptions(merge: true));

    await _checkAllVerifications();
  }

  Future<void> _uploadProfileImage(File file) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseStorage.instance
        .ref()
        .child('profile_pictures')
        .child('${user.uid}.jpg');

    await ref.putFile(file);
    final downloadUrl = await ref.getDownloadURL();

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'photoUrl': downloadUrl,
    }, SetOptions(merge: true));

    await user.updatePhotoURL(downloadUrl);
    await user.reload();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('photoUrl', downloadUrl);

    setState(() {
      _profilePictureUrl = downloadUrl;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profile photo uploaded successfully.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _takeProfilePicture() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera permission denied. Cannot take picture.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final lastChange = prefs.getInt('lastProfileChangeTimestamp');
    final now = DateTime.now().millisecondsSinceEpoch;
    const limit = 7 * 24 * 60 * 60 * 1000;

    if (lastChange != null && now - lastChange < limit) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You can only change your profile photo once every 7 days.',
          ),
          backgroundColor: Colors.black,
        ),
      );
      return;
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);

    if (pickedFile != null) {
      final file = File(pickedFile.path);

      setState(() {
        _profilePictureUrl = pickedFile.path;
        _customProfileImage = file;
      });

      await prefs.setString('customProfileImagePath', pickedFile.path);
      await prefs.setInt('lastProfileChangeTimestamp', now);

      await _uploadProfileImage(file);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile picture updated successfully.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _showProfileOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
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
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
              ),
              onTap: () {
                Navigator.pop(context);
                _takeProfilePicture();
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete,
                size: 22,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              title: Text(
                'Remove Profile Photo',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
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

  Future<void> _loadCustomProfileImage() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('customProfileImagePath');
    if (path != null && path.isNotEmpty) {
      setState(() {
        _customProfileImage = File(path);
      });
    }
  }

  Future<void> _removeProfileImage() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Remove Profile Photo',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to remove your profile photo?',
              style: Theme.of(context).textTheme.bodyMedium,
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
          final imageRef =
              FirebaseStorage.instance.ref().child('profile_images/${user.uid}.jpg');
          await imageRef.delete();
        }
      } catch (_) {}

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('customProfileImagePath');

      setState(() {
        _customProfileImage = null;
        _profilePictureUrl = null;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Profile photo removed successfully.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        ),
      );
    }
  }

  Future<void> _loadVerificationSnackStatus() async {
    final prefs = await SharedPreferences.getInstance();
    _verificationSnackShown = prefs.getBool('verificationSnackShown') ?? false;
  }

  void _checkNameEditability() {
    if (_lastNameChangeTimestamp != null) {
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      const threeDaysInMillis = 3 * 24 * 60 * 60 * 1000;
      _isNameEditable = currentTime - _lastNameChangeTimestamp! > threeDaysInMillis;
    } else {
      _isNameEditable = true;
    }
  }

  String _getInitials(String name) {
    final nameParts = name.trim().split(' ');
    if (nameParts.isEmpty) return 'U';
    if (nameParts.length == 1) {
      return nameParts[0].isNotEmpty ? nameParts[0][0].toUpperCase() : 'U';
    }
    final firstInitial = nameParts[0].isNotEmpty ? nameParts[0][0].toUpperCase() : '';
    final lastInitial =
        nameParts.last.isNotEmpty ? nameParts.last[0].toUpperCase() : '';
    return '$firstInitial$lastInitial';
  }

  Future<void> _saveGoogleUserToFirestore(User user) async {
    final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final docSnapshot = await docRef.get();

    if (!docSnapshot.exists) {
      await docRef.set({
        'email': user.email,
        'fullName': user.displayName ?? user.email!.split('@')[0],
        'role': '',
        'createdAt': FieldValue.serverTimestamp(),
        'isNameVerified': true,
        'isFirstTimeUser': true,
      }, SetOptions(merge: true));
    }
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fullName', _fullName);
    await prefs.setString('profileInitials', _profileInitials);
    await prefs.setString('selectedRole', _selectedRole);
    await prefs.setBool('isIdVerified', _isIdVerified);
    await prefs.setBool('isNameVerified', _isNameVerified);
    await prefs.setBool('isRoleSelected', _isRoleSelected);
    await prefs.setBool('isFirstTimeUser', _isFirstTimeUser);
    if (_selectedRole == 'Student') {
      await prefs.setString('studentId', _idController.text);
    } else {
      await prefs.setString('teacherId', _teacherIdController.text);
    }
    if (_lastNameChangeTimestamp != null) {
      await prefs.setInt('lastNameChangeTimestamp', _lastNameChangeTimestamp!);
    }
  }

  Future<void> _saveName() async {
    final user = FirebaseAuth.instance.currentUser;
    final newName = _nameController.text.trim();

    if (!_isGoogleUser && user != null && newName.isNotEmpty) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Confirm Name Change'),
            content: Text(
              'Is this correct? Full Name: $newName\nYou won\'t be able to change it again for 3 days.',
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
                child: const Text('Confirm'),
                onPressed: () async {
                  Navigator.of(context).pop();
                  await user.updateDisplayName(newName);

                  // Update state
                  if (!mounted) return;
                  setState(() {
                    _fullName = newName;
                    _profileInitials = _getInitials(_fullName);
                    _isNameEditable = false;
                    _lastNameChangeTimestamp = DateTime.now().millisecondsSinceEpoch;
                    _isNameVerified = true;
                  });

                  // Persist to SharedPreferences
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('fullName', _fullName);
                  await prefs.setBool('isNameVerified', _isNameVerified);
                  await prefs.setString('profileInitials', _profileInitials);
                  if (_lastNameChangeTimestamp != null) {
                    await prefs.setInt(
                      'lastNameChangeTimestamp',
                      _lastNameChangeTimestamp!,
                    );
                  }

                  // Persist to Firestore
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .set({
                    'fullName': _fullName,
                    'isNameVerified': _isNameVerified,
                    'profileInitials': _profileInitials,
                  }, SetOptions(merge: true));

                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Full name updated successfully.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
              ),
            ],
          );
        },
      );
    }
  }

  void _verifyId() {
    final id = _idController.text.trim();
    if (_selectedRole == 'Student') {
      if (id.length != 11 || !RegExp(r'^\d{11}$').hasMatch(id)) {
        setState(() {
          _idNumberErrorText = 'Student ID No. must be exactly 11 digits.';
        });
        return;
      }
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Student ID No. Verification'),
          content: Text(
            'Is this correct? ID No.: $id\nOnce verified, you can\'t change it.',
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
              child: const Text('Confirm'),
              onPressed: () async {
                Navigator.of(context).pop();
                setState(() {
                  _isIdVerified = true;
                  _idNumberErrorText = null;
                });
                await _savePreferences();
                await _updateUserFirestoreData();
              },
            ),
          ],
        );
      },
    );
  }

  void _verifyTeacherId() {
    final teacherId = _teacherIdController.text.trim();
    if (teacherId.length != 11 || !RegExp(r'^\d{11}$').hasMatch(teacherId)) {
      setState(() {
        _teacherIdErrorText = 'Teacher ID No. must be exactly 11 digits.';
      });
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Teacher ID No. Verification'),
          content: Text(
            'Is this correct? Teacher ID No.: $teacherId\nOnce verified, you can\'t change it.',
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
              child: const Text('Confirm'),
              onPressed: () async {
                Navigator.of(context).pop();
                setState(() {
                  _isIdVerified = true;
                  _teacherIdErrorText = null;
                });
                await _savePreferences();
                await _updateUserFirestoreData();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    bool isLikelyEmail(String text) {
      final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
      return emailRegex.hasMatch(text);
    }

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        drawer: Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Container(
                height: 200,
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/aclc.png'),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const Divider(thickness: 2, color: Colors.black),
              _drawerItem(context, Icons.note, 'Notes', '/notes'),
              _drawerItem(context, Icons.alarm, 'Reminders', '/reminders'),
              const Divider(thickness: 1, color: Colors.black),
              _drawerItem(context, Icons.label, 'Labels', '/labels'),
              const Divider(thickness: 1, color: Colors.black),
              _drawerItem(context, Icons.folder, 'Folders', '/folders'),
              _drawerItem(context, Icons.archive, 'Archive', '/archive'),
              _drawerItem(context, Icons.delete, 'Recycle Bin', '/deleted'),
              ListTile(
                leading: const Icon(Icons.settings, color: Colors.blue),
                title: const Text(
                  'Account Settings',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                selected: true,
                selectedTileColor: Colors.blue.shade50,
                onTap: () {},
              ),
              const Divider(thickness: 1, color: Colors.black),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Logout', style: TextStyle(fontSize: 13)),
                onTap: () => showLogoutDialog(context),
              ),
            ],
          ),
        ),
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          leading: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu),
              onPressed: (_isNameVerified &&
                      _isRoleSelected &&
                      _isIdVerified &&
                      !_isFirstTimeUser)
                  ? () => Scaffold.of(context).openDrawer()
                  : () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(_getMenuAccessErrorMessage()),
                        ),
                      );
                    },
            ),
          ),
          title: const Text('Account Settings'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'User Information',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 45,
                      backgroundColor: Colors.blue,
                      backgroundImage: _isGoogleUser
                          ? (_profilePictureUrl != null
                              ? NetworkImage(_profilePictureUrl!)
                              : null)
                          : (_customProfileImage != null
                              ? FileImage(_customProfileImage!)
                              : null),
                      child: (!_isGoogleUser && _customProfileImage == null)
                          ? Text(
                              _profileInitials,
                              style: const TextStyle(
                                color: Colors.white,
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
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(6),
                            child: const Icon(
                              Icons.camera_alt,
                              size: 20,
                              color: Colors.blue,
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
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Full Name',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _nameController,
                style: const TextStyle(fontSize: 15),
                enabled: !_isGoogleUser && _isNameEditable && !_isNameVerified,
                readOnly: _isGoogleUser || _isNameVerified,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: 'Enter your full name',
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 12,
                  ),
                  suffixIcon: (!_isGoogleUser && !_isNameVerified)
                      ? IconButton(
                          icon: const Icon(Icons.check, size: 20),
                          onPressed: _isNameEditable ? _saveName : null,
                          tooltip: 'Save Name',
                        )
                      : null,
                ),
              ),
              if (_isGoogleUser)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Full Name is linked to your Google account.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              if (!_isNameVerified &&
                  (isLikelyEmail(_nameController.text.trim()) ||
                      _nameController.text.trim().isEmpty))
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Please update your full name.',
                    style: TextStyle(fontSize: 13, color: Colors.red),
                  ),
                ),
              if (_isNameVerified)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Full Name Verified',
                    style: TextStyle(fontSize: 14, color: Colors.green),
                  ),
                ),
              const SizedBox(height: 20),
              const Text(
                'Account Settings',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.email, size: 20),
                  const SizedBox(width: 8),
                  Text(user?.email ?? '', style: const TextStyle(fontSize: 14)),
                ],
              ),
              const SizedBox(height: 12),
              if (!_isGoogleUser)
                Row(
                  children: [
                    const Icon(Icons.lock, size: 20),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/changepassword'),
                      child: const Text(
                        'Change Password',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              const Text(
                'Role Selection',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _showRoleSelectionDialog,
                      icon: const Icon(Icons.edit),
                      label: const Text('Select Role'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
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
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _showRoleSelectionDialog,
                      icon: const Icon(Icons.edit),
                      label: const Text('Change Role'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
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
              if (_selectedRole == 'Student' && !_isIdVerified)
                TextField(
                  controller: _idController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 15),
                  enabled: !_isIdVerified,
                  decoration: InputDecoration(
                    labelText: 'Student ID No. (11 digits)',
                    labelStyle: const TextStyle(fontSize: 15),
                    border: const OutlineInputBorder(),
                    errorText: _idNumberErrorText,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.check),
                      onPressed: _isIdVerified ? null : _verifyId,
                      tooltip: 'Verify Student ID No.',
                    ),
                  ),
                ),
              if (_selectedRole == 'Teacher' && !_isIdVerified)
                TextField(
                  controller: _teacherIdController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 15),
                  enabled: !_isIdVerified,
                  decoration: InputDecoration(
                    labelText: 'Teacher ID No. (11 digits)',
                    labelStyle: const TextStyle(fontSize: 15),
                    border: const OutlineInputBorder(),
                    errorText: _teacherIdErrorText,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.check),
                      onPressed: _isIdVerified ? null : _verifyTeacherId,
                      tooltip: 'Verify Teacher ID No.',
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              if (_isIdVerified && _selectedRole == 'Student')
                Text(
                  'Student ID No. Verified: ${_idController.text}',
                  style: const TextStyle(fontSize: 14, color: Colors.green),
                ),
              if (_isIdVerified && _selectedRole == 'Teacher')
                Text(
                  'Teacher ID No. Verified: ${_teacherIdController.text}',
                  style: const TextStyle(fontSize: 14, color: Colors.green),
                ),
              const SizedBox(height: 20),
              const Text(
                'Help & About',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text(
                  'How to Use the App',
                  style: TextStyle(fontSize: 13),
                ),
                onTap: () => Navigator.pushNamed(context, '/howtouse'),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text(
                  'About the App',
                  style: TextStyle(fontSize: 13),
                ),
                onTap: () => Navigator.pushNamed(context, '/about'),
              ),
              ListTile(
                leading: const Icon(Icons.question_answer),
                title: const Text('FAQs', style: TextStyle(fontSize: 13)),
                onTap: () => Navigator.pushNamed(context, '/faqs'),
              ),
              ListTile(
                leading: const Icon(Icons.group),
                title: const Text(
                  'About the Team',
                  style: TextStyle(fontSize: 13),
                ),
                onTap: () => Navigator.pushNamed(context, '/team'),
              ),
            ],
          ),
        ),
        bottomNavigationBar: BottomAppBar(
          color: Colors.red,
          shape: const CircularNotchedRectangle(),
          notchMargin: 10.0,
          child: IconButton(
            icon: const Icon(Icons.home, color: Colors.white),
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
        const SnackBar(
          content: Text('Role is already selected and cannot be changed.'),
          backgroundColor: Colors.black,
        ),
      );
      return;
    }

    String tempSelectedRole =
        _selectedRole.isNotEmpty && ['Student', 'Teacher'].contains(_selectedRole)
            ? _selectedRole
            : 'Student';

    const List<String> roles = ['Student', 'Teacher'];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder
        builder: (context, setDialogState) {
          if (roles.isEmpty) {
            return AlertDialog(
              title: const Text('Error'),
              content: const Text('No roles available. Please try again.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            );
          }

          return AlertDialog(
            title: const Text('Select Your Role'),
            content: DropdownButton<String>(
              value: tempSelectedRole,
              isExpanded: true,
              items: roles.map((role) {
                return DropdownMenuItem<String>(
                  value: role,
                  child: Text(role),
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
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);

                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: const Text('Confirm Role Selection'),
                        content: Text(
                          'Are you sure you want to select "$tempSelectedRole" as your role?\n\nYou cannot change it after ID verification.',
                          style: const TextStyle(fontSize: 14),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Confirm'),
                          ),
                        ],
                      );
                    },
                  );

                  if (confirm == true) {
                    setState(() {
                      _selectedRole = tempSelectedRole;
                      _isRoleSelected = true;
                      _isIdVerified = false;
                      _idController.clear();
                      _teacherIdController.clear();
                    });
                    await _savePreferences();
                    await _updateUserFirestoreData();

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Role selected: $_selectedRole'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
                child: const Text('Continue'),
              ),
            ],
          );
        },
      );
    }
  }

  ListTile _drawerItem(
    BuildContext context,
    IconData icon,
    String label,
    String route,
  ) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label, style: const TextStyle(fontSize: 13)),
      onTap: () async {
        if (!(_isNameVerified &&
            _isRoleSelected &&
            _isIdVerified &&
            !_isFirstTimeUser)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_getMenuAccessErrorMessage())),
          );
        } else {
          if (!_verificationSnackShown) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('verificationSnackShown', true);
            _verificationSnackShown = true;
          }
          Navigator.pushNamed(context, route);
        }
      },
    );
  }

  String _getMenuAccessErrorMessage() {
    if (!_isNameVerified && !_isGoogleUser) {
      return 'Please update and verify your full name.';
    }
    if (!_isRoleSelected) {
      return 'Please select a role.';
    }
    if (!_isIdVerified) {
      return 'Please verify your ID number.';
    }
    if (_isFirstTimeUser) {
      return 'Please complete your account setup.';
    }
    return 'Please complete all verifications.';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    _teacherIdController.dispose();
    super.dispose();
  }
}