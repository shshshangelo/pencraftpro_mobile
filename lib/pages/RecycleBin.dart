// ignore_for_file: use_build_context_synchronously, unused_element, library_private_types_in_public_api, deprecated_member_use, unused_local_variable

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pencraftpro/services/SyncService.dart';
import 'package:pencraftpro/view/ViewDeletedPage.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pencraftpro/services/profile_service.dart';

class RecycleBin extends StatefulWidget {
  const RecycleBin({super.key});

  @override
  _RecycleBinState createState() => _RecycleBinState();
}

class _RecycleBinState extends State<RecycleBin> {
  final TextEditingController _searchController = TextEditingController();
  bool isSearching = false;
  bool isEditing = false;
  List<String> selectedNotes = [];
  List<Map<String, dynamic>> notes = [];
  int _nextId = 1;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadNotesFromPrefs().then((_) => _autoDeleteOldNotes());
    _syncPendingDeletes();
    _showFirstTimeWarning();
  }

  Future<void> _syncPendingDeletes() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getStringList('pendingDeletes') ?? [];
    List<String> failed = [];

    for (final id in pending) {
      try {
        await FirebaseFirestore.instance.collection('notes').doc(id).delete();
      } catch (e) {
        print('Failed to delete pending ID $id: $e');
        failed.add(id);
      }
    }

    await prefs.setStringList('pendingDeletes', failed);
    if (pending.isNotEmpty && failed.isEmpty) {
      print('All pending deletes synced to Firestore.');
    }
  }

  Future<void> _loadNotesFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString('notes') ?? '[]';
      final List<dynamic> jsonList = jsonDecode(jsonString);

      setState(() {
        notes = jsonList.map((e) => Map<String, dynamic>.from(e)).toList();
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
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error loading notes: $e.',
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
    }
  }

  Future<void> _saveNotesToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('notes', jsonEncode(notes));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error saving notes: $e.',
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
    }
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
  }) {
    final plain = contentJson.map((op) => op['insert'] as String? ?? '').join();
    setState(() {
      if (id == null) {
        notes.add({
          'id': (_nextId++).toString(),
          'title': title,
          'contentJson': contentJson,
          'content': plain,
          'isPinned': isPinned,
          'isDeleted': isDeleted,
          'reminder': reminder?.toIso8601String(),
          'imagePaths': imagePaths ?? [],
          'voiceNote': voiceNote,
          'labels': labels ?? [],
          'isArchived': isArchived,
          'fontFamily': fontFamily,
          'createdAt': DateTime.now().toIso8601String(),
          'folderId': folderId,
          'folderColor': folderColor,
        });
      } else {
        final index = notes.indexWhere((note) => note['id'] == id);
        if (index != -1) {
          notes[index] = {
            'id': id,
            'title': title,
            'contentJson': contentJson,
            'content': plain,
            'isPinned': isPinned,
            'isDeleted': isDeleted,
            'reminder': reminder?.toIso8601String(),
            'imagePaths': imagePaths ?? [],
            'voiceNote': voiceNote,
            'labels': labels ?? [],
            'isArchived': isArchived,
            'fontFamily': fontFamily,
            'createdAt': notes[index]['createdAt'],
            'folderId': folderId,
            'folderColor': folderColor,
          };
        }
      }
      _saveNotesToPrefs();
    });
  }

  Future<void> _deleteNote(String id) async {
    try {
      final note = notes.firstWhere(
        (note) => note['id'] == id,
        orElse: () => {},
      );
      final firestoreId = note['firestoreId'] ?? note['id'];

      try {
        await FirebaseFirestore.instance
            .collection('notes')
            .doc(firestoreId)
            .delete();
      } catch (e) {
        print('Offline or failed to delete from Firestore: $e');

        final prefs = await SharedPreferences.getInstance();
        final pending = prefs.getStringList('pendingDeletes') ?? [];
        if (!pending.contains(firestoreId)) {
          pending.add(firestoreId);
          await prefs.setStringList('pendingDeletes', pending);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Offline: "$firestoreId" will be removed from cloud later.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        }
      }

      setState(() {
        notes.removeWhere((note) => note['id'] == id);
      });

      await _saveNotesToPrefs();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Note permanently deleted.',
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
    } catch (e) {
      print('Error deleting note: $e.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error deleting note: $e.',
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
    }
  }

  Future<void> _deleteSelectedNotes() async {
    if (selectedNotes.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              'Confirm Deletion',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            content: Text(
              'Are you sure you want to permanently delete the selected notes? This action cannot be undone.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  'Cancel',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  'Delete',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onError,
                  ),
                ),
              ),
            ],
          ),
    );

    if (confirm == true) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final pending = prefs.getStringList('pendingDeletes') ?? [];

        for (var id in selectedNotes) {
          final note = notes.firstWhere(
            (note) => note['id'] == id,
            orElse: () => {},
          );

          if (note.isNotEmpty && note['isDeleted'] == true) {
            final firestoreId = note['firestoreId'] ?? note['id'];

            try {
              await FirebaseFirestore.instance
                  .collection('notes')
                  .doc(firestoreId)
                  .delete();
            } catch (e) {
              print('Firestore delete failed for $firestoreId: $e');
              if (!pending.contains(firestoreId)) {
                pending.add(firestoreId);
              }

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Offline: "$firestoreId" will be removed from cloud later.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    duration: const Duration(seconds: 3),
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
        }

        await prefs.setStringList('pendingDeletes', pending);

        setState(() {
          notes.removeWhere(
            (note) =>
                selectedNotes.contains(note['id']) && note['isDeleted'] == true,
          );
          selectedNotes.clear();
          isEditing = false;
        });

        await _saveNotesToPrefs();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Notes permanently deleted.',
                style: TextStyle(color: Theme.of(context).colorScheme.onError),
              ),
              backgroundColor: Theme.of(context).colorScheme.error,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        }
      } catch (e) {
        print('Error deleting notes: $e.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Error deleting notes: $e.',
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
      }
    }
  }

  Future<void> _autoDeleteOldNotes() async {
    try {
      final now = DateTime.now();
      List<String> notesToDelete = [];

      for (var note in notes) {
        if (note['isDeleted'] == true) {
          final createdAt = note['createdAt'];
          if (createdAt != null) {
            final created = DateTime.tryParse(createdAt.toString());
            if (created != null) {
              final difference = now.difference(created).inDays;
              if (difference >= 30) {
                final firestoreId = note['firestoreId'] ?? note['id'];

                await FirebaseFirestore.instance
                    .collection('notes')
                    .doc(firestoreId)
                    .delete();

                final imagePaths =
                    (note['imagePaths'] as List<dynamic>?)?.cast<String>() ??
                    [];
                for (var path in imagePaths) {
                  final file = File(path);
                  if (await file.exists()) {
                    await file.delete();
                    print('🧹 Deleted image: $path');
                  }
                }

                final voiceNotePath = note['voiceNote'];
                if (voiceNotePath != null) {
                  final voiceFile = File(voiceNotePath);
                  if (await voiceFile.exists()) {
                    await voiceFile.delete();
                    print('🧹 Deleted voice note: $voiceNotePath');
                  }
                }

                notesToDelete.add(note['id']);
              }
            }
          }
        }
      }

      if (notesToDelete.isNotEmpty) {
        setState(() {
          notes.removeWhere((note) => notesToDelete.contains(note['id']));
        });
        await _saveNotesToPrefs();
        print(
          '✅ Auto-deleted ${notesToDelete.length} old notes and associated files.',
        );
      }
    } catch (e) {
      print('Error during auto-deletion: $e');
    }
  }

  void _restoreSelectedNotes() async {
    try {
      final confirm = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text(
                'Confirm Restoration',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              content: Text(
                'Are you sure you want to restore the selected notes?',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(
                    'Cancel',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(
                    'Restore',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
      );

      if (confirm != true) return;

      for (var id in selectedNotes) {
        final index = notes.indexWhere((note) => note['id'] == id);
        if (index != -1) {
          notes[index]['isDeleted'] = false;

          try {
            final firestoreId =
                notes[index]['firestoreId'] ?? notes[index]['id'];
            await FirebaseFirestore.instance
                .collection('notes')
                .doc(firestoreId)
                .update({'isDeleted': false});
          } catch (e) {
            print('Offline or failed to update Firestore: $e');
            final prefs = await SharedPreferences.getInstance();
            final pendingRestores =
                prefs.getStringList('pendingRestores') ?? [];
            if (!pendingRestores.contains(notes[index]['id'])) {
              pendingRestores.add(notes[index]['id']);
              await prefs.setStringList('pendingRestores', pendingRestores);
            }
          }
        }
      }

      setState(() {
        notes.removeWhere((note) => selectedNotes.contains(note['id']));
        selectedNotes.clear();
        isEditing = false;
      });

      await _saveNotesToPrefs();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Notes restored successfully.',
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
        Navigator.pushNamedAndRemoveUntil(context, '/notes', (route) => false);
      }
    } catch (e) {
      print('Error restoring notes: $e.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error restoring notes: $e.',
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
    }
  }

  void _selectAllNotes() {
    setState(() {
      selectedNotes =
          notes
              .where((note) => note['isDeleted'] == true)
              .map((note) => note['id'].toString())
              .toList();
    });
  }

  void _cancelSelection() {
    setState(() {
      selectedNotes.clear();
      isEditing = false;
    });
  }

  Future<void> _showFirstTimeWarning() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenWarning = prefs.getBool('seenRecycleBinWarning') ?? false;

    if (!hasSeenWarning) {
      int countdown = 5;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              Future.delayed(const Duration(seconds: 1), () {
                if (Navigator.of(context).canPop()) {
                  if (countdown > 1) {
                    setState(() => countdown--);
                  } else {
                    prefs.setBool('seenRecycleBinWarning', true);
                    Navigator.of(context).pop();
                  }
                }
              });

              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                backgroundColor: Theme.of(context).colorScheme.surface,
                title: Row(
                  children: [
                    Icon(
                      Icons.warning,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Reminder',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'PenCraft Pro will automatically delete your notes in 30 days.',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'This will auto-close in $countdown second${countdown > 1 ? 's' : ''}...',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor:
                          Theme.of(context).colorScheme.onPrimaryContainer,
                      backgroundColor: Theme.of(context).colorScheme.error,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () async {
                      await prefs.setBool('seenRecycleBinWarning', true);
                      Navigator.of(context).pop();
                    },
                    child: Text(
                      'OK',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onError,
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
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        body: Center(
          child: Text(
            'Please sign in to view deleted notes',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }

    final filteredNotes =
        notes.where((note) {
          if (note['isDeleted'] != true) return false;
          final createdAt = note['createdAt'];
          if (createdAt == null) return true;
          final created = DateTime.tryParse(createdAt.toString());
          if (created == null) return true;
          final now = DateTime.now();
          final difference = now.difference(created).inDays;
          if (difference >= 30) return false;
          final title = note['title']?.toString().toLowerCase() ?? '';
          final content = note['content']?.toString().toLowerCase() ?? '';
          final labels =
              (note['labels'] as List<dynamic>?)?.join(' ').toLowerCase() ?? '';
          final query = _searchController.text.toLowerCase();
          return title.contains(query) ||
              content.contains(query) ||
              labels.contains(query);
        }).toList();

    return WillPopScope(
      onWillPop: () async {
        // Prevent going back
        return false;
      },
      child: OrientationBuilder(
        builder: (context, orientation) {
          final isLandscape = orientation == Orientation.landscape;
          final screenWidth = MediaQuery.of(context).size.width;
          const minCardWidth = 150.0;
          final crossAxisCount = (screenWidth / minCardWidth).floor().clamp(
            2,
            4,
          );
          final padding = screenWidth * 0.03;
          final spacing = screenWidth * 0.02;

          return Scaffold(
            drawer: _buildDrawer(context),
            appBar: _buildAppBar(context),
            body: _buildBody(filteredNotes, padding, spacing, crossAxisCount),
            bottomNavigationBar: _buildBottomAppBar(),
          );
        },
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
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
          Divider(thickness: 2, color: Theme.of(context).colorScheme.onSurface),
          _buildDrawerItem(Icons.note, 'Notes', '/notes'),
          _buildDrawerItem(Icons.alarm, 'Reminders', '/reminders'),
          Divider(thickness: 1, color: Theme.of(context).colorScheme.onSurface),
          _buildDrawerItem(Icons.label, 'Labels', '/labels'),
          Divider(thickness: 1, color: Theme.of(context).colorScheme.onSurface),
          _buildDrawerItem(Icons.folder, 'Folders', '/folders'),
          _buildDrawerItem(Icons.archive, 'Archive', '/archive'),
          _buildDrawerItem(
            Icons.delete,
            'Recycle Bin',
            '/deleted',
            selected: true,
          ),
          _buildDrawerItem(
            Icons.settings,
            'Account Settings',
            '/accountsettings',
          ),
          Divider(thickness: 1, color: Theme.of(context).colorScheme.onSurface),
          _buildLogoutItem(context),
        ],
      ),
    );
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
        if (route != '/accountsettings') {
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
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.all(8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            );
            return;
          }
        }
        Navigator.pushNamed(context, route);
      },
    );
  }

  Widget _buildLogoutItem(BuildContext context) {
    return ListTile(
      leading: Icon(
        Icons.logout,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      title: Text(
        'Logout',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13),
      ),
      onTap: () async {
        bool? confirm = await showDialog(
          context: context,
          builder:
              (_) => AlertDialog(
                title: Text(
                  'Confirm Logout',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                content: Text(
                  'Are you sure you want to logout?',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
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
                    ),
                    child: Text(
                      'Logout',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onError,
                      ),
                    ),
                    onPressed: () => Navigator.pop(context, true),
                  ),
                ],
              ),
        );

        if (confirm == true) {
          await SyncService.clearLocalDataOnLogout();
          await FirebaseAuth.instance.signOut();

          if (context.mounted) {
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/login', (route) => false);
          }
        }
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Theme.of(context).colorScheme.primary,
      foregroundColor: Theme.of(context).colorScheme.onPrimary,
      leading: Builder(
        builder:
            (context) => IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
      ),
      title:
          isEditing
              ? Text(
                '${selectedNotes.length} selected',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 20,
                ),
              )
              : isSearching
              ? TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search deleted notes...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onPrimary.withOpacity(0.6),
                    fontSize: 16,
                  ),
                ),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
                onChanged: (_) => setState(() {}),
              )
              : Text(
                'Recycle Bin',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 20,
                ),
              ),
      actions:
          isEditing
              ? [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  onPressed: _selectAllNotes,
                ),
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: _cancelSelection,
                ),
                IconButton(
                  icon: const Icon(Icons.restore),
                  onPressed: _restoreSelectedNotes,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_forever),
                  onPressed: _deleteSelectedNotes,
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
                      isEditing = true;
                    });
                  },
                  child: Text(
                    'Edit',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontSize: 22,
                    ),
                  ),
                ),
              ],
    );
  }

  Widget _buildBody(
    List<Map<String, dynamic>> notes,
    double padding,
    double spacing,
    int crossAxisCount,
  ) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    if (notes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSearching ? Icons.search : Icons.delete,
              size: 100,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(height: 8),
            Text(
              isSearching
                  ? 'No matching deleted notes'
                  : 'Deleted notes appear here',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 15,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.all(padding),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
          childAspectRatio: isLandscape ? 0.8 : 0.65,
        ),
        itemCount: notes.length,
        itemBuilder: (context, index) {
          final note = notes[index];
          final isSelected = selectedNotes.contains(note['id']);
          final reminder =
              note['reminder'] != null
                  ? DateTime.tryParse(note['reminder'])
                  : null;
          final labels =
              (note['labels'] as List<dynamic>?)?.cast<String>() ?? [];
          final imagePaths = List<String>.from(note['imagePaths'] ?? []);
          final isPinned = note['isPinned'] ?? false;

          // Content Detection variables
          final hasImages = imagePaths.isNotEmpty;
          final contentList =
              (note['contentJson'] as List<dynamic>?)
                  ?.map((e) => Map<String, dynamic>.from(e))
                  .toList() ??
              [];
          bool actualTextContent = false;
          String firstTextItem = '';
          String textFontFamily = 'Roboto';
          double textFontSize = isLandscape ? 12 : 14;
          bool textIsBold = false;
          bool textIsItalic = false;
          bool textIsUnderline = false;
          bool textIsStrikethrough = false;
          if (contentList.isNotEmpty) {
            final textItems =
                contentList
                    .where(
                      (item) =>
                          (item['text'] as String?)?.trim().isNotEmpty ?? false,
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
              textIsStrikethrough = item['strikethrough'] == true;
            }
          }
          final actualVoiceNotePresent =
              note['voiceNote'] != null &&
              (note['voiceNote'] as String).trim().isNotEmpty;
          final actualTitlePresent =
              (note['title']?.toString() ?? '').trim().isNotEmpty;
          final actualReminderPresent = reminder != null;
          final actualLabelsPresent = labels.isNotEmpty;
          final List<Map<String, dynamic>> checklists =
              contentList
                  .where(
                    (item) =>
                        item['checklistItems'] != null &&
                        (item['checklistItems'] as List).isNotEmpty &&
                        (item['checklistItems'] as List).any(
                          (task) =>
                              (task['text']?.toString().trim().isNotEmpty ??
                                  false),
                        ),
                  )
                  .toList();
          final bool actualChecklistPresent = checklists.isNotEmpty;

          // Determine if images should be shown in landscape based on other content
          int landscapeContentScore = 0;
          if (actualTitlePresent) landscapeContentScore++;
          if (actualTextContent) landscapeContentScore++;
          if (actualChecklistPresent) landscapeContentScore++;
          if (actualLabelsPresent) landscapeContentScore++;
          if (actualReminderPresent) landscapeContentScore++;
          if (actualVoiceNotePresent) landscapeContentScore++;

          bool showImagesInCard = true;
          if (isLandscape && landscapeContentScore > 3) {
            showImagesInCard = false;
          }

          return GestureDetector(
            onTap: () {
              if (isEditing) {
                setState(() {
                  if (isSelected) {
                    selectedNotes.remove(note['id']);
                  } else {
                    selectedNotes.add(note['id']);
                  }
                });
              } else {
                print('RecycleBin - note: $note');
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => ViewDeletedPage(
                          title: note['title'] ?? 'Untitled',
                          contentJson:
                              (note['contentJson'] as List)
                                  .cast<Map<String, dynamic>>(),
                          imagePaths: imagePaths,
                          voiceNote: note['voiceNote'],
                          labels: labels,
                          fontFamily: note['fontFamily'],
                          folderId: note['folderId'],
                          folderColor: note['folderColor'],
                          reminder: reminder,
                        ),
                  ),
                );
              }
            },
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side:
                    isSelected
                        ? BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        )
                        : BorderSide.none,
              ),
              elevation: 5,
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.all(padding * 1.5),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SizedBox(
                          height: isLandscape ? 200 : 300,
                          child: SingleChildScrollView(
                            physics: const NeverScrollableScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ClipRect(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (hasImages)
                                        Icon(
                                          Icons.image,
                                          size: isLandscape ? 12 : 16,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                        ),
                                      if (actualVoiceNotePresent)
                                        Icon(
                                          Icons.mic,
                                          size: isLandscape ? 12 : 16,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                        ),
                                      if (actualChecklistPresent)
                                        Icon(
                                          Icons.checklist,
                                          size: isLandscape ? 12 : 16,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                        ),
                                      if (note['folderId'] != null)
                                        Icon(
                                          Icons.bookmark,
                                          size: isLandscape ? 12 : 16,
                                          color:
                                              note['folderColor'] != null
                                                  ? Color(note['folderColor'])
                                                  : Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                        ),
                                      if (isPinned)
                                        Icon(
                                          Icons.push_pin,
                                          size: isLandscape ? 12 : 16,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                        ),
                                    ].whereType<Icon>().fold<List<Widget>>([], (
                                      prev,
                                      elm,
                                    ) {
                                      if (prev.isNotEmpty) {
                                        prev.add(
                                          SizedBox(width: isLandscape ? 2 : 4),
                                        );
                                      }
                                      prev.add(elm);
                                      return prev;
                                    }),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                if (actualTitlePresent)
                                  Text(
                                    note['title']?.toString() ?? 'Untitled',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontSize: isLandscape ? 14 : 16,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                if (actualReminderPresent)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: ClipRect(
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.alarm,
                                            size: isLandscape ? 10 : 14,
                                            color:
                                                reminder.isBefore(
                                                      DateTime.now(),
                                                    )
                                                    ? Theme.of(
                                                      context,
                                                    ).colorScheme.error
                                                    : Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              DateFormat(
                                                'MMM dd, yyyy hh:mm a',
                                              ).format(reminder),
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall?.copyWith(
                                                fontSize: isLandscape ? 10 : 12,
                                                color:
                                                    reminder.isBefore(
                                                          DateTime.now(),
                                                        )
                                                        ? Theme.of(
                                                          context,
                                                        ).colorScheme.error
                                                        : Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (actualLabelsPresent)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Wrap(
                                      spacing: 4,
                                      runSpacing: 4,
                                      children:
                                          labels.take(2).map<Widget>((label) {
                                            return Chip(
                                              padding: EdgeInsets.zero,
                                              labelPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                  ),
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              label: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.label_important,
                                                    size: isLandscape ? 10 : 12,
                                                    color:
                                                        Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                  ),
                                                  const SizedBox(width: 2),
                                                  Text(
                                                    label,
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.bodySmall?.copyWith(
                                                      fontSize:
                                                          isLandscape ? 10 : 12,
                                                      color:
                                                          Theme.of(context)
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
                                if (actualVoiceNotePresent)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: ClipRect(
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.mic,
                                            size: isLandscape ? 10 : 14,
                                            color:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                          ),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              'Voice note attached',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall?.copyWith(
                                                fontSize: isLandscape ? 10 : 12,
                                                color:
                                                    Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (actualTextContent)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Text(
                                      firstTextItem,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium?.copyWith(
                                        fontSize: textFontSize,
                                        fontFamily: textFontFamily,
                                        fontWeight:
                                            textIsBold
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                        fontStyle:
                                            textIsItalic
                                                ? FontStyle.italic
                                                : FontStyle.normal,
                                        decoration: TextDecoration.combine([
                                          if (textIsUnderline)
                                            TextDecoration.underline,
                                          if (textIsStrikethrough)
                                            TextDecoration.lineThrough,
                                        ]),
                                        color:
                                            Theme.of(
                                              context,
                                            ).textTheme.bodyMedium?.color,
                                      ),
                                      maxLines: isLandscape ? 1 : 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                if (actualChecklistPresent)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children:
                                          checklists.expand<Widget>((
                                            checklistData,
                                          ) {
                                            final items =
                                                (checklistData['checklistItems']
                                                        as List<dynamic>?)
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
                                              final bool isChecked =
                                                  item['checked'] == true;
                                              final String taskText =
                                                  item['text']?.toString() ??
                                                  '';
                                              if (taskText.isEmpty) {
                                                return const SizedBox.shrink();
                                              }
                                              return Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 1.0,
                                                    ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      isChecked
                                                          ? Icons.check_box
                                                          : Icons
                                                              .check_box_outline_blank,
                                                      size:
                                                          isLandscape ? 12 : 14,
                                                      color:
                                                          Theme.of(context)
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                    ),
                                                    const SizedBox(width: 4),
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
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .onSurfaceVariant,
                                                          decoration:
                                                              isChecked
                                                                  ? TextDecoration
                                                                      .lineThrough
                                                                  : null,
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
                                            }).toList();
                                          }).toList(),
                                    ),
                                  ),
                                if (hasImages && showImagesInCard)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Builder(
                                      builder: (context) {
                                        final bool shouldImageExpand =
                                            !actualTextContent &&
                                            !actualChecklistPresent &&
                                            !actualVoiceNotePresent;

                                        Widget imageWidget;
                                        if (imagePaths.length == 1) {
                                          imageWidget = ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            child: Container(
                                              width: double.infinity,
                                              constraints: BoxConstraints(
                                                maxHeight:
                                                    shouldImageExpand
                                                        ? double.infinity
                                                        : 120,
                                              ),
                                              child: Image.file(
                                                File(imagePaths[0]),
                                                fit: BoxFit.cover,
                                                errorBuilder:
                                                    (
                                                      context,
                                                      error,
                                                      stackTrace,
                                                    ) => Icon(
                                                      Icons.broken_image,
                                                      size: 40,
                                                      color:
                                                          Theme.of(context)
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                    ),
                                              ),
                                            ),
                                          );
                                        } else {
                                          imageWidget = GridView.builder(
                                            shrinkWrap: true,
                                            physics:
                                                const NeverScrollableScrollPhysics(),
                                            gridDelegate:
                                                SliverGridDelegateWithFixedCrossAxisCount(
                                                  crossAxisCount: 2,
                                                  crossAxisSpacing: 4,
                                                  mainAxisSpacing: 4,
                                                  childAspectRatio: 1,
                                                ),
                                            itemCount:
                                                imagePaths.length > 4
                                                    ? 4
                                                    : imagePaths.length,
                                            itemBuilder: (context, imgIndex) {
                                              return ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                child: Image.file(
                                                  File(imagePaths[imgIndex]),
                                                  fit: BoxFit.cover,
                                                  errorBuilder:
                                                      (
                                                        context,
                                                        error,
                                                        stackTrace,
                                                      ) => Icon(
                                                        Icons.broken_image,
                                                        size: 40,
                                                        color:
                                                            Theme.of(context)
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                      ),
                                                ),
                                              );
                                            },
                                          );
                                          if (imagePaths.length > 4) {
                                            imageWidget = Stack(
                                              alignment: Alignment.center,
                                              children: [
                                                imageWidget,
                                                Positioned.fill(
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      color: Colors.black
                                                          .withOpacity(0.3),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                    ),
                                                    child: Center(
                                                      child: Text(
                                                        '+${imagePaths.length - 4}',
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 20,
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
                                          return imageWidget;
                                        } else {
                                          if (isLandscape &&
                                              imagePaths.length > 1) {
                                            return SizedBox(
                                              height: 75,
                                              width: double.infinity,
                                              child: imageWidget,
                                            );
                                          } else {
                                            return Container(
                                              constraints: BoxConstraints(
                                                maxHeight:
                                                    (imagePaths.length == 1)
                                                        ? (isLandscape
                                                            ? 80
                                                            : 120)
                                                        : 180,
                                              ),
                                              width: double.infinity,
                                              child: imageWidget,
                                            );
                                          }
                                        }
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (isSelected)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Icon(
                        Icons.check_circle,
                        color: Theme.of(context).colorScheme.primary,
                        size: 24,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomAppBar() {
    return BottomAppBar(
      color: Theme.of(context).colorScheme.error,
      shape: const CircularNotchedRectangle(),
      notchMargin: 10,
      child: IconButton(
        icon: Icon(Icons.home, color: Theme.of(context).colorScheme.onError),
        iconSize: 32,
        onPressed: () => Navigator.pushNamed(context, '/select'),
      ),
    );
  }
}
