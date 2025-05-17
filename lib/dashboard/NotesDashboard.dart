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
import 'package:pencraftpro/services/profile_service.dart';

class NotesDashboard extends StatefulWidget {
  const NotesDashboard({super.key});

  @override
  _NotesDashboardState createState() => _NotesDashboardState();
}

class _NotesDashboardState extends State<NotesDashboard> {
  final TextEditingController _searchController = TextEditingController();
  bool isSearching = false;
  bool isSelecting = false;
  bool isOffline = true;
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
    _initConnectivity();

    // Listen for connectivity changes
    Connectivity().onConnectivityChanged.listen((result) async {
      setState(() {
        isOffline = result == ConnectivityResult.none;
      });

      if (!isOffline) {
        // When connection is restored
        final prefs = await SharedPreferences.getInstance();
        final isVerified =
            prefs.getBool('isNameVerified') == true &&
            prefs.getBool('isRoleSelected') == true &&
            prefs.getBool('isIdVerified') == true;
        final isFirstTimeUser = prefs.getBool('isFirstTimeUser') ?? true;

        if (isVerified && !isFirstTimeUser && mounted) {
          await _loadNotesFromFirestore();
          if (mounted) {
            setState(() {}); // Refresh UI after loading notes
          }
        }
      }
    });
  }

  Future<void> _initConnectivity() async {
    try {
      final result = await Connectivity().checkConnectivity();
      setState(() {
        isOffline = result == ConnectivityResult.none;
      });
    } catch (e) {
      print('Failed to get connectivity status: $e');
    }
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

      // Get all notes (including deleted ones) to properly sync
      final ownNotesQuery = notesRef.where('owner', isEqualTo: user.uid).get();
      final sharedNotesQuery =
          notesRef.where('collaborators', arrayContains: user.uid).get();

      final results = await Future.wait([ownNotesQuery, sharedNotesQuery]);
      final firestoreNotes =
          [...results[0].docs, ...results[1].docs].map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList();

      print(
        'Fetched ${firestoreNotes.length} notes from Firestore (cached if offline)',
      );

      // Get existing local notes
      final prefs = await SharedPreferences.getInstance();
      final localNotesString = prefs.getString('notes') ?? '[]';
      final List<dynamic> localNotes = jsonDecode(localNotesString);

      // Create a map of notes by ID for easier merging
      final Map<String, dynamic> mergedNotesMap = {};

      // Add local notes to the map first
      for (var note in localNotes) {
        if (note['id'] != null) {
          mergedNotesMap[note['id']] = note;
        }
      }

      // Merge Firestore notes, overwriting local notes only if the Firestore note is newer
      for (var firestoreNote in firestoreNotes) {
        final noteId = firestoreNote['id'];
        final localNote = mergedNotesMap[noteId];

        if (localNote != null) {
          final firestoreUpdateTime =
              DateTime.tryParse(firestoreNote['updatedAt'] ?? '') ??
              DateTime.now();
          final localUpdateTime =
              DateTime.tryParse(localNote['updatedAt'] ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);

          if (firestoreUpdateTime.isAfter(localUpdateTime)) {
            mergedNotesMap[noteId] = firestoreNote;
          }
        } else {
          mergedNotesMap[noteId] = firestoreNote;
        }
      }

      // Convert map back to list
      final mergedNotes = mergedNotesMap.values.toList();

      // Save merged notes back to SharedPreferences
      await prefs.setString('notes', jsonEncode(mergedNotes));

      // Update UI with non-deleted notes
      if (mounted) {
        setState(() {
          notes =
              mergedNotes
                  .where((note) => note['isDeleted'] != true)
                  .map((note) => Map<String, dynamic>.from(note))
                  .toList();
        });
      }

      print('Saved ${mergedNotes.length} merged notes to SharedPreferences');
    } catch (e) {
      print('Error loading notes from Firestore: $e');
      // Fallback to SharedPreferences if Firestore fails
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
              .where((note) => !_isNoteEmpty(note) && note['isDeleted'] != true)
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

  void _saveNotesToPrefs() async {
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

    // Create a temporary note map to check if it's empty
    final tempNote = {
      'title': title,
      'contentJson': contentJson,
      'imagePaths': imagePaths ?? [],
      'voiceNote': voiceNote,
      'labels': labels ?? [],
    };

    // If the note is empty, don't create/update it
    if (_isNoteEmpty(tempNote)) {
      return;
    }

    final noteId = id ?? DateTime.now().millisecondsSinceEpoch.toString();
    List<String> collaboratorUIDs = [];

    if (collaboratorEmails != null && collaboratorEmails.isNotEmpty) {
      final connectivityResult = await Connectivity().checkConnectivity();
      final isOffline = connectivityResult == ConnectivityResult.none;

      if (!isOffline) {
        try {
          final userQuery =
              await FirebaseFirestore.instance
                  .collection('users')
                  .where('email', whereIn: collaboratorEmails)
                  .get();
          collaboratorUIDs = userQuery.docs.map((doc) => doc.id).toList();
        } catch (e) {
          // Silently handle collaborator lookup error
        }
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

    _saveNotesToPrefs();

    try {
      await FirebaseFirestore.instance
          .collection('notes')
          .doc(noteId)
          .set(noteData, SetOptions(merge: true));
    } catch (e) {
      // Silently handle Firestore errors
      final connectivity = await Connectivity().checkConnectivity();
      final isOffline = connectivity == ConnectivityResult.none;

      if (isOffline && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Note saved locally. Will sync when online.'),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _deleteNote(String id) async {
    // First update local state
    setState(() {
      final index = notes.indexWhere((note) => note['id'] == id);
      if (index != -1) {
        notes[index]['isDeleted'] = true;
      }
    });

    // Update SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final String? notesString = prefs.getString('notes');
    if (notesString != null) {
      List<dynamic> notesList = jsonDecode(notesString);
      final noteIndex = notesList.indexWhere((note) => note['id'] == id);
      if (noteIndex != -1) {
        notesList[noteIndex]['isDeleted'] = true;
        await prefs.setString('notes', jsonEncode(notesList));
      }
    }

    // Update Firestore
    try {
      await FirebaseFirestore.instance.collection('notes').doc(id).update({
        'isDeleted': true,
        'updatedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      final pendingUpdates = prefs.getStringList('pendingUpdates') ?? [];
      if (!pendingUpdates.contains(id)) {
        pendingUpdates.add(id);
        await prefs.setStringList('pendingUpdates', pendingUpdates);
      }
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
    final toDelete = Set<String>.from(selectedNoteIds); // Important fix!
    final selectedCount = toDelete.length;

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
      for (var id in toDelete) {
        final index = notes.indexWhere((note) => note['id'] == id);
        if (index != -1) {
          notes[index]['isDeleted'] = true;
        }
      }
      selectedNoteIds.clear(); // clear after using
      isSelecting = false;
    });

    _saveNotesToPrefs();

    for (var id in toDelete) {
      try {
        await FirebaseFirestore.instance.collection('notes').doc(id).update({
          'isDeleted': true,
          'updatedAt': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        final prefs = await SharedPreferences.getInstance();
        final pendingUpdates = prefs.getStringList('pendingUpdates') ?? [];
        if (!pendingUpdates.contains(id)) {
          pendingUpdates.add(id);
          await prefs.setStringList('pendingUpdates', pendingUpdates);
        }
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            selectedCount == 1
                ? 'Note deleted.'
                : '$selectedCount notes deleted.',
          ),
          duration: const Duration(seconds: 5),
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

      // Only show dialog if the note was actually created/updated/deleted
      if (result['isNew'] == true ||
          result['delete'] == true ||
          result['updated'] == true) {
        String message;
        if (result['isNew'] == true) {
          message = 'Note created';
        } else if (result['delete'] == true) {
          message = 'Note deleted';
        } else {
          message = 'Note updated';
        }

        if (mounted) {
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
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(
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

  ListTile _buildDrawerItem(
    IconData icon,
    String title,
    String route, {
    bool selected = false,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color:
            selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurface,
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontSize: 13,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          color:
              selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).textTheme.bodyMedium?.color,
        ),
      ),
      selected: selected,
      selectedTileColor:
          selected
              ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
              : null,
      onTap: () async {
        final isComplete = await ProfileService.isProfileComplete();
        if (!isComplete) {
          if (!mounted) return;
          Navigator.pushNamed(context, '/accountsettings');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Please complete your profile setup first.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
            ),
          );
          return;
        }
        Navigator.pushNamed(context, route);
      },
    );
  }

  // New helper method for building placeholders
  Widget _buildPlaceholder(
    BuildContext context,
    IconData icon,
    String text, {
    bool isLandscape = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0), // Compact padding
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: isLandscape ? 10 : 12,
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withOpacity(0.6),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: isLandscape ? 8 : 10,
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withOpacity(0.6),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
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
      final isAPinned = a['isPinned'] == true;
      final isBPinned = b['isPinned'] == true;

      if (isAPinned && !isBPinned) {
        return -1; // a (pinned) comes before b (not pinned)
      } else if (!isAPinned && isBPinned) {
        return 1; // b (pinned) comes before a (not pinned)
      } else {
        // Both are pinned or both are not pinned. Sort by creation time.
        final String? createdAtAString = a['createdAt']?.toString();
        final String? createdAtBString = b['createdAt']?.toString();

        DateTime? dateA =
            createdAtAString != null
                ? DateTime.tryParse(createdAtAString)
                : null;
        DateTime? dateB =
            createdAtBString != null
                ? DateTime.tryParse(createdAtBString)
                : null;

        // Handle cases where one or both dates might be null
        if (dateB != null && dateA != null) {
          return dateB.compareTo(dateA); // Primary: newest (later dateB) first
        } else if (dateB != null) {
          // dateA is null, dateB is not
          return 1; // dateB (the one with a date) comes before dateA (no date)
        } else if (dateA != null) {
          // dateB is null, dateA is not
          return -1; // dateA (the one with a date) comes before dateB (no date)
        }
        // Fallback: if createdAt is missing or unparseable for both, use ID
        final idValA = int.tryParse(a['id']?.toString() ?? '0') ?? 0;
        final idValB = int.tryParse(b['id']?.toString() ?? '0') ?? 0;
        return idValB.compareTo(idValA); // Newest (larger ID) first
      }
    });

    return WillPopScope(
      onWillPop: () async => false,
      child: OrientationBuilder(
        builder: (context, orientation) {
          final isLandscape = orientation == Orientation.landscape;
          final screenWidth = MediaQuery.of(context).size.width;
          final screenHeight = MediaQuery.of(context).size.height;
          final crossAxisCount =
              isLandscape ? 4 : 2; // Show 4 columns in landscape, 2 in portrait
          final childAspectRatio =
              isLandscape
                  ? 0.8
                  : 0.7; // Adjusted ratio for better content display
          final padding = screenWidth * 0.02;
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
                  _buildDrawerItem(
                    Icons.note,
                    'Notes',
                    '/notes',
                    selected: true,
                  ),
                  _buildDrawerItem(Icons.alarm, 'Reminders', '/reminders'),
                  Divider(
                    thickness: 1,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  _buildDrawerItem(Icons.label, 'Labels', '/labels'),
                  Divider(
                    thickness: 1,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  _buildDrawerItem(Icons.folder, 'Folders', '/folders'),
                  _buildDrawerItem(Icons.archive, 'Archive', '/archive'),
                  _buildDrawerItem(Icons.delete, 'Recycle Bin', '/deleted'),
                  _buildDrawerItem(
                    Icons.settings,
                    'Account Settings',
                    '/accountsettings',
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
                      ],
            ),
            body: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.all(padding),
                child:
                    filteredNotes.isEmpty
                        ? SizedBox(
                          height: MediaQuery.of(context).size.height * 0.8,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isSearching ? Icons.search : Icons.note,
                                  size: isLandscape ? 80 : 100,
                                  color:
                                      Theme.of(context).colorScheme.secondary,
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
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                        : GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
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

                            final isPinned = note['isPinned'] == true;

                            // --- Content Detection variables ---
                            final hasImages =
                                (note['imagePaths'] as List<dynamic>?)
                                    ?.isNotEmpty ??
                                false;
                            final contentListForCard =
                                (note['contentJson'] as List<dynamic>?)
                                    ?.map((e) => Map<String, dynamic>.from(e))
                                    .toList();
                            bool actualTextContent = false;
                            String firstTextItem = '';
                            String textFontFamily = 'Roboto';
                            double textFontSize = isLandscape ? 12 : 14;
                            bool textIsBold = false;
                            bool textIsItalic = false;
                            bool textIsUnderline = false;
                            bool textIsStrikethrough = false;
                            if (contentListForCard != null &&
                                contentListForCard.isNotEmpty) {
                              final textItems =
                                  contentListForCard
                                      .where(
                                        (item) =>
                                            (item['text'] as String?)
                                                ?.trim()
                                                .isNotEmpty ??
                                            false,
                                      )
                                      .toList();
                              if (textItems.isNotEmpty) {
                                final item = textItems.first;
                                actualTextContent = true;
                                firstTextItem = item['text'];
                                textFontFamily = item['fontFamily'] ?? 'Roboto';
                                textFontSize =
                                    (item['fontSize'] != null)
                                        ? (item['fontSize'] as num).toDouble()
                                        : (isLandscape ? 12 : 14);
                                textIsBold = item['bold'] == true;
                                textIsItalic = item['italic'] == true;
                                textIsUnderline = item['underline'] == true;
                                textIsStrikethrough =
                                    item['strikethrough'] == true;
                              }
                            }
                            final actualVoiceNotePresent =
                                note['voiceNote'] != null &&
                                (note['voiceNote'] as String).trim().isNotEmpty;
                            final actualTitlePresent =
                                (note['title']?.toString() ?? '')
                                    .trim()
                                    .isNotEmpty;
                            final actualReminderPresent =
                                note['reminder'] != null;
                            final actualLabelsPresent =
                                (note['labels'] as List<dynamic>?)
                                    ?.isNotEmpty ??
                                false;
                            final actualCollaboratorsPresent =
                                (note['collaboratorEmails'] as List<dynamic>?)
                                    ?.isNotEmpty ??
                                false;

                            final List<Map<String, dynamic>> checklists =
                                contentListForCard
                                    ?.where(
                                      (item) =>
                                          item['checklistItems'] != null &&
                                          (item['checklistItems'] as List)
                                              .isNotEmpty &&
                                          (item['checklistItems'] as List).any(
                                            (task) =>
                                                (task['text']
                                                        ?.toString()
                                                        .trim()
                                                        .isNotEmpty ??
                                                    false),
                                          ),
                                    )
                                    .toList() ??
                                [];
                            final bool actualChecklistPresent =
                                checklists.isNotEmpty;

                            // Determine if images should be shown in landscape based on other content
                            int landscapeContentScore = 0;
                            if (actualTitlePresent) landscapeContentScore++;
                            if (actualTextContent) landscapeContentScore++;
                            if (actualChecklistPresent) landscapeContentScore++;
                            if (actualLabelsPresent) {
                              landscapeContentScore++; // Labels are small but add to visual density
                            }
                            if (actualReminderPresent) landscapeContentScore++;
                            if (actualVoiceNotePresent) landscapeContentScore++;
                            if (actualCollaboratorsPresent) {
                              landscapeContentScore++;
                            }

                            bool showImagesInCard = true; // Default to true
                            if (isLandscape && landscapeContentScore > 3) {
                              // Threshold: if more than 3 other major items in landscape
                              showImagesInCard = false;
                            }

                            return GestureDetector(
                              onTap: () {
                                if (isSelecting) {
                                  _toggleSelectNote(note['id']);
                                } else {
                                  _navigateToAddNote(note: note);
                                }
                              },
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
                                      padding: EdgeInsets.all(padding),
                                      child: SingleChildScrollView(
                                        physics:
                                            const AlwaysScrollableScrollPhysics(),
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxHeight: isLandscape ? 200 : 300,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              ClipRect(
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    if (hasImages)
                                                      Icon(
                                                        Icons.image,
                                                        size:
                                                            isLandscape
                                                                ? 12
                                                                : 14,
                                                        color:
                                                            Theme.of(context)
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                      ),
                                                    if (actualVoiceNotePresent)
                                                      Icon(
                                                        Icons.mic,
                                                        size:
                                                            isLandscape
                                                                ? 12
                                                                : 14,
                                                        color:
                                                            Theme.of(context)
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                      ),
                                                    if (actualChecklistPresent) // Add this condition
                                                      Icon(
                                                        Icons.checklist,
                                                        size:
                                                            isLandscape
                                                                ? 12
                                                                : 14,
                                                        color:
                                                            Theme.of(context)
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                      ),
                                                    if (note['folderId'] !=
                                                        null)
                                                      Icon(
                                                        Icons.bookmark,
                                                        size:
                                                            isLandscape
                                                                ? 12
                                                                : 14,
                                                        color:
                                                            note['folderColor'] !=
                                                                    null
                                                                ? Color(
                                                                  note['folderColor'],
                                                                )
                                                                : Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .primary,
                                                      ),
                                                    if (isPinned)
                                                      Icon(
                                                        Icons.push_pin,
                                                        size:
                                                            isLandscape
                                                                ? 12
                                                                : 14,
                                                        color:
                                                            Theme.of(context)
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                      ),
                                                  ].whereType<Icon>().fold<
                                                    List<Widget>
                                                  >([], (prev, elm) {
                                                    if (prev.isNotEmpty) {
                                                      prev.add(
                                                        SizedBox(
                                                          width:
                                                              isLandscape
                                                                  ? 2
                                                                  : 4,
                                                        ),
                                                      );
                                                    }
                                                    prev.add(elm);
                                                    return prev;
                                                  }),
                                                ),
                                              ),
                                              if (actualCollaboratorsPresent)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        bottom: 4.0,
                                                      ),
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 4,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          Colors
                                                              .purple
                                                              .shade100,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          Icons.people,
                                                          size:
                                                              isLandscape
                                                                  ? 12
                                                                  : 14,
                                                          color:
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .onSurfaceVariant,
                                                        ),
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        Flexible(
                                                          child: Text(
                                                            'Shared Notes',
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
                                                                      .onSurfaceVariant,
                                                            ),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              if (actualLabelsPresent)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 2,
                                                      ),
                                                  child: Wrap(
                                                    spacing: 2,
                                                    runSpacing: 2,
                                                    children:
                                                        (note['labels']
                                                                as List<
                                                                  dynamic
                                                                >)
                                                            .take(2)
                                                            .map<Widget>((
                                                              label,
                                                            ) {
                                                              return Chip(
                                                                padding:
                                                                    EdgeInsets
                                                                        .zero,
                                                                labelPadding:
                                                                    const EdgeInsets.symmetric(
                                                                      horizontal:
                                                                          4,
                                                                    ),
                                                                materialTapTargetSize:
                                                                    MaterialTapTargetSize
                                                                        .shrinkWrap,
                                                                label: Row(
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .min,
                                                                  children: [
                                                                    Icon(
                                                                      Icons
                                                                          .label_important,
                                                                      size:
                                                                          isLandscape
                                                                              ? 8
                                                                              : 10,
                                                                      color:
                                                                          Theme.of(
                                                                            context,
                                                                          ).colorScheme.onSurfaceVariant,
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
                                                                            ).colorScheme.onPrimaryContainer,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                                backgroundColor:
                                                                    Theme.of(
                                                                          context,
                                                                        )
                                                                        .colorScheme
                                                                        .primaryContainer,
                                                              );
                                                            })
                                                            .toList(),
                                                  ),
                                                ),
                                              if (actualTitlePresent)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 2.0,
                                                      ),
                                                  child: Text(
                                                    note['title']?.toString() ??
                                                        'Untitled',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleMedium
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize:
                                                              isLandscape
                                                                  ? 14
                                                                  : 16,
                                                        ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              if (actualReminderPresent)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 2.0,
                                                      ),
                                                  child: Builder(
                                                    builder: (context) {
                                                      final reminder =
                                                          DateTime.tryParse(
                                                            note['reminder']
                                                                .toString(),
                                                          );
                                                      if (reminder == null) {
                                                        return const SizedBox.shrink();
                                                      }
                                                      final now =
                                                          DateTime.now();
                                                      final isExpired = reminder
                                                          .isBefore(now);
                                                      return ClipRect(
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              Icons.alarm,
                                                              size:
                                                                  isLandscape
                                                                      ? 10
                                                                      : 12,
                                                              color:
                                                                  isExpired
                                                                      ? Theme.of(
                                                                        context,
                                                                      ).colorScheme.error
                                                                      : Theme.of(
                                                                        context,
                                                                      ).colorScheme.onSurfaceVariant,
                                                            ),
                                                            const SizedBox(
                                                              width: 2,
                                                            ),
                                                            Expanded(
                                                              child: Text(
                                                                DateFormat(
                                                                  'MMM dd, hh:mm a',
                                                                ).format(
                                                                  reminder,
                                                                ),
                                                                style: Theme.of(
                                                                  context,
                                                                ).textTheme.bodySmall?.copyWith(
                                                                  fontSize:
                                                                      isLandscape
                                                                          ? 8
                                                                          : 10,
                                                                  color:
                                                                      isExpired
                                                                          ? Theme.of(
                                                                            context,
                                                                          ).colorScheme.error
                                                                          : Theme.of(
                                                                            context,
                                                                          ).colorScheme.onSurfaceVariant,
                                                                ),
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ),
                                              if (actualVoiceNotePresent)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 4.0,
                                                      ),
                                                  child: ClipRect(
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          Icons.mic,
                                                          size:
                                                              isLandscape
                                                                  ? 12
                                                                  : 14,
                                                          color:
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .primary,
                                                        ),
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        Flexible(
                                                          child: Text(
                                                            'Voice note attached',
                                                            style: Theme.of(
                                                              context,
                                                            ).textTheme.bodySmall?.copyWith(
                                                              fontSize:
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
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              if (actualTextContent)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 4.0,
                                                      ),
                                                  child: Text(
                                                    firstTextItem,
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.bodyMedium?.copyWith(
                                                      fontSize: textFontSize,
                                                      fontFamily:
                                                          textFontFamily,
                                                      fontWeight:
                                                          textIsBold
                                                              ? FontWeight.bold
                                                              : FontWeight
                                                                  .normal,
                                                      fontStyle:
                                                          textIsItalic
                                                              ? FontStyle.italic
                                                              : FontStyle
                                                                  .normal,
                                                      decoration:
                                                          TextDecoration.combine([
                                                            if (textIsUnderline)
                                                              TextDecoration
                                                                  .underline,
                                                            if (textIsStrikethrough)
                                                              TextDecoration
                                                                  .lineThrough,
                                                          ]),
                                                      color:
                                                          Theme.of(context)
                                                              .textTheme
                                                              .bodyMedium
                                                              ?.color,
                                                    ),
                                                    maxLines:
                                                        isLandscape ? 1 : 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              if (actualChecklistPresent)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 4.0,
                                                      ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children:
                                                        checklists.expand<
                                                          Widget
                                                        >((checklistData) {
                                                          final items =
                                                              (checklistData['checklistItems']
                                                                      as List<
                                                                        dynamic
                                                                      >?)
                                                                  ?.map(
                                                                    (e) => Map<
                                                                      String,
                                                                      dynamic
                                                                    >.from(e),
                                                                  )
                                                                  .toList() ??
                                                              [];
                                                          return items.take(isLandscape ? 1 : 3).map<
                                                            Widget
                                                          >((item) {
                                                            final bool
                                                            isChecked =
                                                                item['checked'] ==
                                                                true;
                                                            final String
                                                            taskText =
                                                                item['text']
                                                                    ?.toString() ??
                                                                '';
                                                            if (taskText
                                                                .isEmpty) {
                                                              return const SizedBox.shrink();
                                                            }
                                                            return Padding(
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    vertical:
                                                                        1.0,
                                                                  ),
                                                              child: Row(
                                                                children: [
                                                                  Icon(
                                                                    isChecked
                                                                        ? Icons
                                                                            .check_box
                                                                        : Icons
                                                                            .check_box_outline_blank,
                                                                    size:
                                                                        isLandscape
                                                                            ? 12
                                                                            : 14,
                                                                    color:
                                                                        Theme.of(
                                                                          context,
                                                                        ).colorScheme.onSurfaceVariant,
                                                                  ),
                                                                  const SizedBox(
                                                                    width: 4,
                                                                  ),
                                                                  Flexible(
                                                                    child: Text(
                                                                      taskText,
                                                                      style: Theme.of(
                                                                        context,
                                                                      ).textTheme.bodySmall?.copyWith(
                                                                        fontSize:
                                                                            isLandscape
                                                                                ? 12
                                                                                : 14,
                                                                        color:
                                                                            Theme.of(
                                                                              context,
                                                                            ).colorScheme.onSurfaceVariant,
                                                                        decoration:
                                                                            isChecked
                                                                                ? TextDecoration.lineThrough
                                                                                : null,
                                                                      ),
                                                                      maxLines:
                                                                          1,
                                                                      overflow:
                                                                          TextOverflow
                                                                              .ellipsis,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            );
                                                          }).toList();
                                                        }).toList(),
                                                  ),
                                                ),
                                              // Placeholder logic was removed by the user in a previous step.
                                              // If placeholders are needed, they would go here.
                                              if (hasImages && showImagesInCard)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 4.0,
                                                      ),
                                                  child: Builder(
                                                    builder: (context) {
                                                      final imagePaths =
                                                          note['imagePaths']
                                                              as List;
                                                      final bool
                                                      shouldImageExpand =
                                                          !actualTextContent &&
                                                          !actualChecklistPresent &&
                                                          !actualVoiceNotePresent;

                                                      Widget imageWidget;
                                                      if (imagePaths.length ==
                                                          1) {
                                                        imageWidget = ClipRRect(
                                                          // Using ClipRRect directly for single image
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                          child: Container(
                                                            // Container helps with constraints for single image
                                                            width:
                                                                double.infinity,
                                                            constraints: BoxConstraints(
                                                              maxHeight:
                                                                  shouldImageExpand
                                                                      ? double
                                                                          .infinity
                                                                      : 120,
                                                            ), // Expand if it's the only content
                                                            child: Image.file(
                                                              File(
                                                                imagePaths[0],
                                                              ),
                                                              fit: BoxFit.cover,
                                                              errorBuilder:
                                                                  (
                                                                    context,
                                                                    error,
                                                                    stackTrace,
                                                                  ) => Icon(
                                                                    Icons
                                                                        .broken_image,
                                                                    size: 40,
                                                                    color:
                                                                        Theme.of(
                                                                          context,
                                                                        ).colorScheme.onSurfaceVariant,
                                                                  ),
                                                            ),
                                                          ),
                                                        );
                                                      } else {
                                                        // Multiple images
                                                        imageWidget = GridView.builder(
                                                          shrinkWrap: true,
                                                          physics:
                                                              const NeverScrollableScrollPhysics(),
                                                          gridDelegate:
                                                              SliverGridDelegateWithFixedCrossAxisCount(
                                                                crossAxisCount:
                                                                    2,
                                                                crossAxisSpacing:
                                                                    4,
                                                                mainAxisSpacing:
                                                                    4,
                                                                childAspectRatio:
                                                                    1,
                                                              ),
                                                          itemCount:
                                                              imagePaths.length >
                                                                      4
                                                                  ? 4
                                                                  : imagePaths
                                                                      .length, // Show max 4 images in grid preview
                                                          itemBuilder: (
                                                            context,
                                                            imgIndex,
                                                          ) {
                                                            return ClipRRect(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    8,
                                                                  ),
                                                              child: Image.file(
                                                                File(
                                                                  imagePaths[imgIndex],
                                                                ),
                                                                fit:
                                                                    BoxFit
                                                                        .cover,
                                                                errorBuilder:
                                                                    (
                                                                      context,
                                                                      error,
                                                                      stackTrace,
                                                                    ) => Icon(
                                                                      Icons
                                                                          .broken_image,
                                                                      size: 40,
                                                                      color:
                                                                          Theme.of(
                                                                            context,
                                                                          ).colorScheme.onSurfaceVariant,
                                                                    ),
                                                              ),
                                                            );
                                                          },
                                                        );
                                                        if (imagePaths.length >
                                                            4) {
                                                          // Add an overlay if more than 4 images
                                                          imageWidget = Stack(
                                                            alignment:
                                                                Alignment
                                                                    .center,
                                                            children: [
                                                              imageWidget,
                                                              Positioned.fill(
                                                                child: Container(
                                                                  decoration: BoxDecoration(
                                                                    color: Colors
                                                                        .black
                                                                        .withOpacity(
                                                                          0.3,
                                                                        ),
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                          8,
                                                                        ),
                                                                  ),
                                                                  child: Center(
                                                                    child: Text(
                                                                      '+${imagePaths.length - 4}',
                                                                      style: TextStyle(
                                                                        color:
                                                                            Colors.white,
                                                                        fontSize:
                                                                            20,
                                                                        fontWeight:
                                                                            FontWeight.bold,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          );
                                                        }
                                                      }

                                                      if (shouldImageExpand) {
                                                        return imageWidget; // Let it take available space if it's the main content
                                                      } else {
                                                        // This is the start of the block we are modifying: when shouldImageExpand is false
                                                        // Check if it's landscape AND there are multiple images
                                                        if (isLandscape &&
                                                            imagePaths.length >
                                                                1) {
                                                          // Yes: Landscape, multiple images, and other content is present.
                                                          // Use a SizedBox with a specific, smaller height for the image grid.
                                                          return SizedBox(
                                                            height:
                                                                75, // Specific height for landscape multi-image preview
                                                            width:
                                                                double.infinity,
                                                            child:
                                                                imageWidget, // imageWidget is already the GridView (possibly in a Stack for +N)
                                                          );
                                                        } else {
                                                          // No: It's either portrait with multiple images, OR it's a single image (in any orientation).
                                                          // In these cases, use the existing Container with BoxConstraints.
                                                          return Container(
                                                            constraints: BoxConstraints(
                                                              maxHeight:
                                                                  (imagePaths.length ==
                                                                          1)
                                                                      ? (isLandscape
                                                                          ? 80
                                                                          : 120) // Single image (landscape height is 80, portrait 120)
                                                                      : 180, // Multiple images, portrait only (height 180)
                                                            ),
                                                            width:
                                                                double.infinity,
                                                            child: imageWidget,
                                                          );
                                                        }
                                                      } // This is the end of the block we are modifying
                                                    },
                                                  ),
                                                ),
                                            ],
                                          ),
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
