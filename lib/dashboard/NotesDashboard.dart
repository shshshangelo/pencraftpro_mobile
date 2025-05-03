// ignore_for_file: deprecated_member_use, library_private_types_in_public_api, unused_field

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pencraftpro/services/SyncService.dart';
import 'package:pencraftpro/services/logout_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../notes/AddNotePage.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class NotesDashboard extends StatefulWidget {
  const NotesDashboard({super.key});

  @override
  _NotesDashboardState createState() => _NotesDashboardState();
}

class _NotesDashboardState extends State<NotesDashboard> {
  final TextEditingController _searchController = TextEditingController();
  bool isSearching = false;
  bool isSelecting = false;
  List<Map<String, dynamic>> notes = [];
  Set<String> selectedNoteIds = {};
  int _nextId = 1;
  final TextStyle appBarTitleStyle = TextStyle(
    fontSize: 22,
    color: Colors.white,
  );

  @override
  void initState() {
    super.initState();
    _checkIfVerifiedAndStartSync();
  }

  Future<void> _checkIfVerifiedAndStartSync() async {
    final prefs = await SharedPreferences.getInstance();
    final connectivityResult = await Connectivity().checkConnectivity();
    final isOffline = connectivityResult == ConnectivityResult.none;
    print('Connectivity status: ${isOffline ? 'Offline' : 'Online'}');

    // Always load from SharedPreferences first for offline support
    await _loadNotesFromPrefs();

    final isVerified =
        prefs.getBool('isNameVerified') == true &&
        prefs.getBool('isRoleSelected') == true &&
        prefs.getBool('isIdVerified') == true;
    final isFirstTimeUser = prefs.getBool('isFirstTimeUser') ?? true;

    if (isVerified && !isFirstTimeUser) {
      if (!isOffline) {
        // Load notes from Firestore when online
        await _loadNotesFromFirestore();
        print('Loaded notes from Firestore on login');

        // Start auto-sync
        SyncService.startAutoSync(
          context,
          onAutoSyncComplete: () async {
            await _loadNotesFromPrefs();
            print(
              'Auto-sync completed, refreshed notes from SharedPreferences',
            );
          },
        );

        // Trigger immediate sync
        await SyncService.syncNow(
          context,
          onComplete: () async {
            await _loadNotesFromPrefs();
            print(
              'Manual sync completed, refreshed notes from SharedPreferences',
            );
          },
        );

        debugPrint('✅ Sync triggered and notes loaded.');
      } else {
        print('Offline: Using cached notes from SharedPreferences');
        debugPrint('✅ Offline mode: Loaded cached notes.');
      }
    } else {
      debugPrint('⏸️ Sync blocked: First-time user or not yet verified.');
      print('Loading notes from SharedPreferences for first-time user');
    }
  }

  Future<void> _loadNotesFromFirestore() async {
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final notesRef = FirebaseFirestore.instance.collection('notes');
      final ownNotesQuery =
          notesRef
              .where('owner', isEqualTo: user.uid)
              .where('isDeleted', isEqualTo: false)
              .get();
      final sharedNotesQuery =
          notesRef
              .where('collaborators', arrayContains: user.uid)
              .where('isDeleted', isEqualTo: false)
              .get();
      final results = await Future.wait([ownNotesQuery, sharedNotesQuery]);
      final allNotes =
          [...results[0].docs, ...results[1].docs].map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList();

      print(
        'Fetched ${allNotes.length} notes from Firestore (cached if offline): ${jsonEncode(allNotes)}',
      );

      setState(() {
        notes = allNotes;
      });
      await _saveNotesToPrefs();
      print('Saved ${allNotes.length} notes to SharedPreferences');
    } catch (e, stackTrace) {
      print('Failed to load notes from Firestore: $e');
      print('Stack trace: $stackTrace');
      // Fallback to SharedPreferences if Firestore fails (e.g., offline with no cache)
      await _loadNotesFromPrefs();
    }
  }

  Future<void> _loadNotesFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('notes') ?? '[]';
    final List<dynamic> jsonList = jsonDecode(jsonString);

    setState(() {
      notes =
          jsonList
              .map((e) => Map<String, dynamic>.from(e))
              .where((note) => !_isNoteEmpty(note))
              .toList();
      notes.sort((a, b) {
        final int idA = int.tryParse(a['id'] ?? '0') ?? 0;
        final int idB = int.tryParse(b['id'] ?? '0') ?? 0;
        return idB.compareTo(idA);
      });
      if (notes.isNotEmpty) {
        final maxId = notes
            .map((n) => int.tryParse(n['id'].toString()) ?? 0)
            .reduce((a, b) => a > b ? a : b);
        _nextId = maxId + 1;
      }
      print(
        'Loaded ${notes.length} notes from SharedPreferences: ${jsonEncode(notes)}',
      );
    });
  }

  Future<void> _saveNotesToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notes', jsonEncode(notes));
    print('Saved ${notes.length} notes to SharedPreferences');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _addOrUpdateNote({
    String? id,
    required String title,
    required List<Map<String, dynamic>> contentJson,
    required bool isPinned,
    required bool isDeleted,
    DateTime? reminder,
    List<String>? imagePaths,
    String? voiceNote,
    List<String>? labels,
    bool isArchived = false,
    String? fontFamily,
    String? folderId,
    int? folderColor,
    List<String>? collaboratorEmails,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final noteId = id ?? DateTime.now().millisecondsSinceEpoch.toString();
    List<String> collaboratorUIDs = [];

    if (collaboratorEmails != null && collaboratorEmails.isNotEmpty) {
      final connectivityResult = await Connectivity().checkConnectivity();
      final isOffline = connectivityResult == ConnectivityResult.none;

      if (!isOffline) {
        final userQuery =
            await FirebaseFirestore.instance
                .collection('users')
                .where('email', whereIn: collaboratorEmails)
                .get();
        collaboratorUIDs = userQuery.docs.map((doc) => doc.id).toList();
      } else {
        print('Offline: Queuing collaborator emails for sync');
      }
    }

    final noteData = {
      'id': noteId,
      'owner': user.uid,
      'title': title,
      'contentJson': contentJson,
      'isPinned': isPinned,
      'isDeleted': isDeleted,
      'reminder': reminder?.toIso8601String(),
      'imagePaths': imagePaths ?? [],
      'voiceNote': voiceNote,
      'labels': labels ?? [],
      'isArchived': isArchived,
      'fontFamily': fontFamily ?? 'Roboto',
      'folderId': folderId,
      'folderColor': folderColor,
      'collaboratorEmails': collaboratorEmails ?? [],
      'collaborators': collaboratorUIDs,
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
    };

    setState(() {
      final index = notes.indexWhere((n) => n['id'] == noteId);
      if (index != -1) {
        notes[index] = noteData;
      } else {
        notes.add(noteData);
      }
    });

    await _saveNotesToPrefs();

    try {
      await FirebaseFirestore.instance
          .collection('notes')
          .doc(noteId)
          .set(noteData, SetOptions(merge: true));
      print('Synced note $noteId to Firestore (queued if offline)');
    } catch (e) {
      print('⚠️ Failed to sync note to Firestore: $e');
      final connectivity = await Connectivity().checkConnectivity();
      final isOffline = connectivity == ConnectivityResult.none;

      if (isOffline) {
        print('📴 Offline mode: Note saved locally and will sync when online.');
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '⚠️ Failed to sync note to cloud: $e',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _deleteNote(String id) async {
    setState(() {
      final index = notes.indexWhere((note) => note['id'] == id);
      if (index != -1) {
        notes[index]['isDeleted'] = true;
      }
    });

    await _saveNotesToPrefs();

    try {
      await FirebaseFirestore.instance.collection('notes').doc(id).update({
        'isDeleted': true,
      });
      await _saveNotesToPrefs();
      print('Deleted note $id in Firestore (queued if offline)');
    } catch (e) {
      print('⚠️ Warning: Failed to delete note on Firestore: $e');
    }
  }

  void _toggleSelectNote(String id) {
    setState(() {
      if (selectedNoteIds.contains(id)) {
        selectedNoteIds.remove(id);
      } else {
        selectedNoteIds.add(id);
      }
    });
  }

  void _selectAllNotes() {
    setState(() {
      if (selectedNoteIds.length == notes.length) {
        selectedNoteIds.clear();
      } else {
        selectedNoteIds =
            notes
                .where(
                  (note) =>
                      note['isDeleted'] != true && note['isArchived'] != true,
                )
                .map((note) => note['id'].toString())
                .toSet();
      }
    });
  }

  void _deleteSelectedNotes() async {
    final selectedCount = selectedNoteIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              'Delete Notes',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            content: Text(
              selectedCount == 1
                  ? 'Are you sure you want to delete this note?'
                  : 'Are you sure you want to delete $selectedCount notes?',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontSize: 16),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              TextButton(
                child: Text(
                  'Cancel',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                onPressed: () => Navigator.pop(context, false),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                ),
                child: Text(
                  'Delete',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onError,
                  ),
                ),
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
    );

    if (confirm != true) return;

    setState(() {
      for (var id in selectedNoteIds) {
        final index = notes.indexWhere((note) => note['id'] == id);
        if (index != -1) {
          notes[index]['isDeleted'] = true;
        }
      }
      selectedNoteIds.clear();
      isSelecting = false;
    });

    await _saveNotesToPrefs();

    for (var id in selectedNoteIds) {
      try {
        await FirebaseFirestore.instance.collection('notes').doc(id).update({
          'isDeleted': true,
        });
      } catch (e) {
        print('⚠️ Warning: Failed to delete note on Firestore: $e');
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            selectedCount == 1
                ? '🗑️ Note deleted.'
                : '🗑️ $selectedCount notes deleted.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.surface,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _navigateToAddNote({Map<String, dynamic>? note}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => AddNotePage(
              noteId: note?['id'],
              title: note?['title'],
              contentJson:
                  (note?['contentJson'] as List<dynamic>?)
                      ?.map((e) => Map<String, dynamic>.from(e))
                      .toList(),
              isPinned: note?['isPinned'] ?? false,
              reminder:
                  note?['reminder'] != null
                      ? DateTime.tryParse(note!['reminder'])
                      : null,
              imagePaths:
                  (note?['imagePaths'] as List<dynamic>?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  [],
              voiceNote: note?['voiceNote'],
              labels:
                  (note?['labels'] as List<dynamic>?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  [],
              isArchived: note?['isArchived'] ?? false,
              fontFamily: note?['fontFamily'] ?? 'Roboto',
              folderId: note?['folderId'],
              folderColor: note?['folderColor'],
              collaboratorEmails:
                  (note?['collaboratorEmails'] as List<dynamic>?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  [],
              onSave: ({
                String? id,
                required String title,
                required List<Map<String, dynamic>> contentJson,
                required bool isPinned,
                required bool isDeleted,
                DateTime? reminder,
                List<String>? imagePaths,
                String? voiceNote,
                List<String>? labels,
                bool isArchived = false,
                String? fontFamily,
                String? folderId,
                int? folderColor,
                List<String>? collaboratorEmails,
              }) {
                _addOrUpdateNote(
                  id: id,
                  title: title,
                  contentJson: contentJson,
                  isPinned: isPinned,
                  isDeleted: isDeleted,
                  reminder: reminder,
                  imagePaths: imagePaths,
                  voiceNote: voiceNote,
                  labels: labels,
                  isArchived: isArchived,
                  fontFamily: fontFamily,
                  folderId: folderId,
                  folderColor: folderColor,
                  collaboratorEmails: collaboratorEmails,
                );
              },
              onDelete: _deleteNote,
            ),
      ),
    );

    if (result != null) {
      final connectivityResult = await Connectivity().checkConnectivity();
      final isOffline = connectivityResult == ConnectivityResult.none;

      if (!isOffline) {
        try {
          await _loadNotesFromFirestore();
        } catch (e) {
          debugPrint('⚠️ Failed to load notes from Firestore: $e');
        }
      }

      await _loadNotesFromPrefs();

      String message;
      if (result['isNew'] == true) {
        message = 'Note created';
      } else if (result['delete'] == true) {
        message = 'Note deleted';
      } else {
        message = 'Note updated';
      }

      showDialog(
        context: context,
        builder:
            (_) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              backgroundColor: Theme.of(context).colorScheme.surface,
              elevation: 8,
              titlePadding: const EdgeInsets.only(top: 20),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 10,
              ),
              actionsPadding: const EdgeInsets.only(bottom: 10),
              title: Column(
                children: [
                  Icon(
                    message == 'Note deleted'
                        ? Icons.delete_forever
                        : Icons.check_circle,
                    color:
                        message == 'Note deleted'
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.primary,
                    size: 40,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                  ),
                ],
              ),
              actionsAlignment: MainAxisAlignment.center,
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        message == 'Note deleted'
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'OK',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
      );
    }
  }

  bool _isNoteEmpty(Map<String, dynamic> note) {
    final title = note['title']?.toString().trim() ?? '';
    final contentJson = note['contentJson'] as List<dynamic>? ?? [];

    final hasTitle = title.isNotEmpty;
    final hasText = contentJson.any(
      (item) => (item['text']?.toString().trim().isNotEmpty ?? false),
    );

    final hasChecklist = contentJson.any((item) {
      final checklist = (item['checklistItems'] as List<dynamic>? ?? []);
      return checklist.any(
        (task) => (task['text']?.toString().trim().isNotEmpty ?? false),
      );
    });

    final hasImage = (note['imagePaths'] as List<dynamic>? ?? []).isNotEmpty;
    final hasVoice = (note['voiceNote']?.toString().trim().isNotEmpty ?? false);

    return !(hasTitle || hasText || hasChecklist || hasImage || hasVoice);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        body: Center(
          child: Text(
            'Please sign in to view notes',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }

    final filteredNotes =
        notes.where((note) {
          if (note['isDeleted'] == true || note['isArchived'] == true) {
            return false;
          }
          final title = note['title']?.toString().toLowerCase() ?? '';
          final contentJson = note['contentJson'] as List<dynamic>? ?? [];
          final contentText = contentJson
              .map((e) => e['text']?.toString().toLowerCase() ?? '')
              .join(' ');
          final labels =
              (note['labels'] as List<dynamic>?)
                  ?.map((e) => e.toString().toLowerCase())
                  .toList() ??
              [];
          final collaboratorEmails =
              (note['collaboratorEmails'] as List<dynamic>?)
                  ?.map((e) => e.toString().toLowerCase())
                  .toList() ??
              [];
          DateTime? parsedReminder;
          if (note['reminder'] != null) {
            parsedReminder = DateTime.tryParse(note['reminder'].toString());
          }
          final reminderText =
              parsedReminder != null
                  ? DateFormat('MMM dd, yyyy hh:mm a').format(parsedReminder)
                  : '';
          final query = _searchController.text.toLowerCase();
          return title.contains(query) ||
              contentText.contains(query) ||
              labels.any((label) => label.contains(query)) ||
              collaboratorEmails.any((email) => email.contains(query)) ||
              reminderText.toLowerCase().contains(query);
        }).toList();

    filteredNotes.sort((a, b) {
      if (a['isPinned'] == true && b['isPinned'] != true) {
        return -1;
      } else if (a['isPinned'] != true && b['isPinned'] == true) {
        return 1;
      } else {
        final idA = int.tryParse(a['id'] ?? '0') ?? 0;
        final idB = int.tryParse(b['id'] ?? '0') ?? 0;
        return idB.compareTo(idA);
      }
    });

    return WillPopScope(
      onWillPop: () async => false,
      child: OrientationBuilder(
        builder: (context, orientation) {
          final isLandscape = orientation == Orientation.landscape;
          final screenWidth = MediaQuery.of(context).size.width;
          const minCardWidth = 150.0;
          final crossAxisCount = (screenWidth / minCardWidth).floor().clamp(
            2,
            4,
          );
          final childAspectRatio = isLandscape ? 1.0 : 0.75;
          final padding = screenWidth * 0.03;
          final spacing = screenWidth * 0.02;

          return Scaffold(
            drawer: Drawer(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  Container(
                    height: isLandscape ? 150 : 200,
                    decoration: const BoxDecoration(
                      image: DecorationImage(
                        image: AssetImage('assets/aclc.png'),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  Divider(
                    thickness: 2,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.note,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(
                      'Notes',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    selected: true,
                    selectedTileColor: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.1),
                    onTap: () => Navigator.pushNamed(context, '/notes'),
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.alarm,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    title: Text(
                      'Reminders',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(fontSize: 13),
                    ),
                    onTap: () => Navigator.pushNamed(context, '/reminders'),
                  ),
                  Divider(
                    thickness: 1,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.label,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    title: Text(
                      'Labels',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(fontSize: 13),
                    ),
                    onTap: () => Navigator.pushNamed(context, '/labels'),
                  ),
                  Divider(
                    thickness: 1,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.folder,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    title: Text(
                      'Folders',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(fontSize: 13),
                    ),
                    onTap: () => Navigator.pushNamed(context, '/folders'),
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.archive,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    title: Text(
                      'Archive',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(fontSize: 13),
                    ),
                    onTap: () => Navigator.pushNamed(context, '/archive'),
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.delete,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    title: Text(
                      'Recycle Bin',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(fontSize: 13),
                    ),
                    onTap: () => Navigator.pushNamed(context, '/deleted'),
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.settings,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    title: Text(
                      'Account Settings',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(fontSize: 13),
                    ),
                    onTap:
                        () => Navigator.pushNamed(context, '/accountsettings'),
                  ),
                  Divider(
                    thickness: 1,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.logout,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    title: Text(
                      'Logout',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(fontSize: 13),
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
                    (ctx) => IconButton(
                      icon: const Icon(Icons.menu),
                      onPressed: () => Scaffold.of(ctx).openDrawer(),
                    ),
              ),
              title:
                  isSelecting
                      ? Text(
                        '${selectedNoteIds.length} selected',
                        style: appBarTitleStyle.copyWith(
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      )
                      : isSearching
                      ? TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search notes...',
                          border: InputBorder.none,
                          hintStyle: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimary.withOpacity(0.6),
                          ),
                        ),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontSize: 16,
                        ),
                        autofocus: true,
                        onChanged: (_) => setState(() {}),
                      )
                      : Text(
                        'Notes',
                        style: appBarTitleStyle.copyWith(
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
              actions:
                  isSelecting
                      ? [
                        IconButton(
                          icon: const Icon(Icons.select_all),
                          onPressed: _selectAllNotes,
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            setState(() {
                              isSelecting = false;
                              selectedNoteIds.clear();
                            });
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed:
                              selectedNoteIds.isNotEmpty
                                  ? _deleteSelectedNotes
                                  : null,
                        ),
                      ]
                      : [
                        IconButton(
                          icon: Icon(isSearching ? Icons.close : Icons.search),
                          onPressed: () {
                            setState(() {
                              isSearching = !isSearching;
                              if (!isSearching) _searchController.clear();
                            });
                          },
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              isSelecting = true;
                              isSearching = false;
                              _searchController.clear();
                            });
                          },
                          child: Text(
                            'Edit',
                            style: Theme.of(
                              context,
                            ).textTheme.titleLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onPrimary,
                              fontSize: appBarTitleStyle.fontSize,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: () async {
                            final connectivityResult =
                                await Connectivity().checkConnectivity();
                            final isOffline =
                                connectivityResult == ConnectivityResult.none;
                            if (!isOffline) {
                              await SyncService.syncNow(
                                context,
                                onComplete: _loadNotesFromPrefs,
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Offline: Notes will sync when online',
                                  ),
                                  duration: Duration(seconds: 3),
                                ),
                              );
                              await _loadNotesFromPrefs();
                            }
                          },
                        ),
                      ],
            ),
            body: Padding(
              padding: EdgeInsets.all(padding),
              child:
                  filteredNotes.isEmpty
                      ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isSearching ? Icons.search : Icons.note,
                              size: isLandscape ? 80 : 100,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isSearching
                                  ? 'You don\'t have any notes yet.'
                                  : 'Notes you add appear here',
                              style: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.copyWith(
                                fontSize: isLandscape ? 13 : 15,
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                      : GridView.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: spacing,
                          mainAxisSpacing: spacing,
                          childAspectRatio: childAspectRatio,
                        ),
                        itemCount: filteredNotes.length,
                        itemBuilder: (context, index) {
                          final note = filteredNotes[index];
                          final isSelected = selectedNoteIds.contains(
                            note['id'],
                          );
                          return GestureDetector(
                            onTap:
                                isSelecting
                                    ? () => _toggleSelectNote(note['id'])
                                    : () => _navigateToAddNote(note: note),
                            child: Card(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side:
                                    isSelected
                                        ? BorderSide(
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                          width: 2,
                                        )
                                        : BorderSide.none,
                              ),
                              elevation: 5,
                              child: Stack(
                                children: [
                                  Padding(
                                    padding: EdgeInsets.all(padding * 1.5),
                                    child: SingleChildScrollView(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (note.containsKey('owner') &&
                                              note['owner'] !=
                                                  FirebaseAuth
                                                      .instance
                                                      .currentUser
                                                      ?.uid)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              margin: const EdgeInsets.only(
                                                bottom: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color:
                                                    Theme.of(context)
                                                        .colorScheme
                                                        .secondaryContainer,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'Shared Note',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.labelSmall?.copyWith(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color:
                                                      Theme.of(context)
                                                          .colorScheme
                                                          .onSecondaryContainer,
                                                ),
                                              ),
                                            ),
                                          if ((note['collaboratorEmails']
                                                      as List<dynamic>?)
                                                  ?.isNotEmpty ??
                                              false)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 4,
                                              ),
                                              child: Text(
                                                'Shared with: ${(note['collaboratorEmails'] as List<dynamic>).join(', ')}',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall?.copyWith(
                                                  fontSize:
                                                      isLandscape ? 8 : 10,
                                                  color:
                                                      Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          Row(
                                            children: [
                                              if ((note['imagePaths']
                                                          as List<dynamic>?)
                                                      ?.isNotEmpty ??
                                                  false)
                                                Icon(
                                                  Icons.image,
                                                  size: isLandscape ? 14 : 16,
                                                  color:
                                                      Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                ),
                                              if (note['voiceNote'] != null)
                                                Icon(
                                                  Icons.mic,
                                                  size: isLandscape ? 14 : 16,
                                                  color:
                                                      Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                ),
                                              if (note['folderId'] != null)
                                                Icon(
                                                  Icons.bookmark,
                                                  size: 16,
                                                  color:
                                                      note['folderColor'] !=
                                                              null
                                                          ? Color(
                                                            note['folderColor'],
                                                          )
                                                          : Theme.of(
                                                            context,
                                                          ).colorScheme.primary,
                                                ),
                                              if (note['isPinned'] == true)
                                                Icon(
                                                  Icons.push_pin,
                                                  size: isLandscape ? 14 : 16,
                                                  color:
                                                      Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                ),
                                              const Spacer(),
                                            ],
                                          ),
                                          if ((note['labels'] as List<dynamic>?)
                                                  ?.isNotEmpty ??
                                              false)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 4,
                                              ),
                                              child: Wrap(
                                                spacing: 4,
                                                runSpacing: 4,
                                                children:
                                                    (note['labels'] as List<dynamic>).map<
                                                      Widget
                                                    >((label) {
                                                      return Chip(
                                                        padding:
                                                            EdgeInsets.zero,
                                                        labelPadding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                            ),
                                                        materialTapTargetSize:
                                                            MaterialTapTargetSize
                                                                .shrinkWrap,
                                                        label: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .label_important,
                                                              size:
                                                                  isLandscape
                                                                      ? 10
                                                                      : 12,
                                                              color:
                                                                  Theme.of(
                                                                        context,
                                                                      )
                                                                      .colorScheme
                                                                      .onSurfaceVariant,
                                                            ),
                                                            const SizedBox(
                                                              width: 2,
                                                            ),
                                                            Text(
                                                              label,
                                                              style: Theme.of(
                                                                context,
                                                              ).textTheme.bodySmall?.copyWith(
                                                                fontSize:
                                                                    isLandscape
                                                                        ? 8
                                                                        : 10,
                                                                color:
                                                                    Theme.of(
                                                                          context,
                                                                        )
                                                                        .colorScheme
                                                                        .onPrimaryContainer,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        backgroundColor:
                                                            Theme.of(context)
                                                                .colorScheme
                                                                .primaryContainer,
                                                      );
                                                    }).toList(),
                                              ),
                                            ),
                                          Text(
                                            note['title']?.toString() ??
                                                'Untitled',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              fontSize: isLandscape ? 14 : 16,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          if (note['reminder'] != null)
                                            Builder(
                                              builder: (context) {
                                                final reminder =
                                                    DateTime.tryParse(
                                                      note['reminder']
                                                          .toString(),
                                                    );
                                                if (reminder == null) {
                                                  return const SizedBox.shrink();
                                                }
                                                final now = DateTime.now();
                                                final isExpired = reminder
                                                    .isBefore(now);
                                                return Row(
                                                  children: [
                                                    Icon(
                                                      Icons.alarm,
                                                      size:
                                                          isLandscape ? 12 : 14,
                                                      color:
                                                          isExpired
                                                              ? Theme.of(
                                                                    context,
                                                                  )
                                                                  .colorScheme
                                                                  .error
                                                              : Theme.of(
                                                                    context,
                                                                  )
                                                                  .colorScheme
                                                                  .onSurfaceVariant,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      DateFormat(
                                                        'MMM dd, hh:mm a',
                                                      ).format(reminder),
                                                      style: Theme.of(
                                                        context,
                                                      ).textTheme.bodySmall?.copyWith(
                                                        fontSize:
                                                            isLandscape
                                                                ? 10
                                                                : 12,
                                                        color:
                                                            isExpired
                                                                ? Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .error
                                                                : Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .onSurfaceVariant,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                );
                                              },
                                            ),
                                          const SizedBox(height: 4),
                                          Builder(
                                            builder: (context) {
                                              final contentList =
                                                  (note['contentJson']
                                                          as List<dynamic>?)
                                                      ?.map(
                                                        (e) => Map<
                                                          String,
                                                          dynamic
                                                        >.from(e),
                                                      )
                                                      .toList();
                                              if (contentList == null ||
                                                  contentList.isEmpty) {
                                                return const SizedBox.shrink();
                                              }
                                              final item = contentList.first;
                                              final checklistItems =
                                                  item['checklistItems']
                                                      as List<dynamic>? ??
                                                  [];

                                              return Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  if ((item['text'] as String?)
                                                          ?.trim()
                                                          .isNotEmpty ??
                                                      false)
                                                    Text(
                                                      item['text'],
                                                      maxLines:
                                                          isLandscape ? 3 : 6,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: Theme.of(
                                                        context,
                                                      ).textTheme.bodyMedium?.copyWith(
                                                        fontSize:
                                                            (item['fontSize'] !=
                                                                    null)
                                                                ? (item['fontSize']
                                                                        as num)
                                                                    .toDouble()
                                                                : (isLandscape
                                                                    ? 12
                                                                    : 14),
                                                        fontFamily:
                                                            item['fontFamily'] ??
                                                            'Roboto',
                                                        fontWeight:
                                                            (item['bold'] ==
                                                                    true)
                                                                ? FontWeight
                                                                    .bold
                                                                : FontWeight
                                                                    .normal,
                                                        fontStyle:
                                                            (item['italic'] ==
                                                                    true)
                                                                ? FontStyle
                                                                    .italic
                                                                : FontStyle
                                                                    .normal,
                                                        decoration: TextDecoration.combine([
                                                          if (item['underline'] ==
                                                              true)
                                                            TextDecoration
                                                                .underline,
                                                          if (item['strikethrough'] ==
                                                              true)
                                                            TextDecoration
                                                                .lineThrough,
                                                        ]),
                                                        color:
                                                            Theme.of(context)
                                                                .textTheme
                                                                .bodyMedium
                                                                ?.color,
                                                      ),
                                                    ),
                                                  const SizedBox(height: 6),
                                                  if (checklistItems.isNotEmpty)
                                                    ...checklistItems.take(3).map((
                                                      task,
                                                    ) {
                                                      final checked =
                                                          task['checked'] ==
                                                          true;
                                                      final text =
                                                          task['text'] ?? '';
                                                      return Row(
                                                        children: [
                                                          Checkbox(
                                                            value: checked,
                                                            onChanged: null,
                                                            visualDensity:
                                                                VisualDensity
                                                                    .compact,
                                                            activeColor:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .primary,
                                                            side: BorderSide(
                                                              color:
                                                                  checked
                                                                      ? Theme.of(
                                                                        context,
                                                                      ).colorScheme.primary
                                                                      : Theme.of(
                                                                        context,
                                                                      ).colorScheme.onSurfaceVariant,
                                                              width: 2,
                                                            ),
                                                          ),
                                                          Expanded(
                                                            child: Text(
                                                              text,
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: Theme.of(
                                                                context,
                                                              ).textTheme.bodyMedium?.copyWith(
                                                                fontSize:
                                                                    (item['fontSize'] !=
                                                                            null)
                                                                        ? (item['fontSize']
                                                                                as num)
                                                                            .toDouble()
                                                                        : (isLandscape
                                                                            ? 12
                                                                            : 14),
                                                                fontFamily:
                                                                    item['fontFamily'] ??
                                                                    'Roboto',
                                                                fontWeight:
                                                                    (item['bold'] ==
                                                                            true)
                                                                        ? FontWeight
                                                                            .bold
                                                                        : FontWeight
                                                                            .normal,
                                                                fontStyle:
                                                                    (item['italic'] ==
                                                                            true)
                                                                        ? FontStyle
                                                                            .italic
                                                                        : FontStyle
                                                                            .normal,
                                                                decoration: TextDecoration.combine([
                                                                  if (item['underline'] ==
                                                                      true)
                                                                    TextDecoration
                                                                        .underline,
                                                                  if (item['strikethrough'] ==
                                                                          true ||
                                                                      checked)
                                                                    TextDecoration
                                                                        .lineThrough,
                                                                ]),
                                                                color:
                                                                    checked
                                                                        ? Theme.of(
                                                                          context,
                                                                        ).colorScheme.primary
                                                                        : Theme.of(
                                                                              context,
                                                                            )
                                                                            .textTheme
                                                                            .bodyMedium
                                                                            ?.color,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      );
                                                    }),
                                                ],
                                              );
                                            },
                                          ),
                                          if ((note['imagePaths']
                                                      as List<dynamic>?)
                                                  ?.isNotEmpty ??
                                              false)
                                            Container(
                                              height: 120,
                                              margin: const EdgeInsets.only(
                                                top: 8,
                                              ),
                                              child: ListView.builder(
                                                scrollDirection:
                                                    Axis.horizontal,
                                                itemCount:
                                                    (note['imagePaths'] as List)
                                                        .length,
                                                itemBuilder: (context, index) {
                                                  return Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          right: 8.0,
                                                        ),
                                                    child: ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                      child: Image.file(
                                                        File(
                                                          note['imagePaths'][index],
                                                        ),
                                                        width: 120,
                                                        height: 120,
                                                        fit: BoxFit.cover,
                                                        errorBuilder:
                                                            (
                                                              context,
                                                              error,
                                                              stackTrace,
                                                            ) => Icon(
                                                              Icons
                                                                  .broken_image,
                                                              size: 120,
                                                              color:
                                                                  Theme.of(
                                                                        context,
                                                                      )
                                                                      .colorScheme
                                                                      .onSurfaceVariant,
                                                            ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Icon(
                                        Icons.check_circle,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                        size: 24,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
            ),
            floatingActionButton: FloatingActionButton(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              onPressed: () => _navigateToAddNote(),
              child: const Icon(Icons.note_add),
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
                iconSize: isLandscape ? 28 : 32,
                onPressed: () {
                  Navigator.pushNamed(context, '/select');
                },
                tooltip: 'Go to Home',
              ),
            ),
          );
        },
      ),
    );
  }
}
