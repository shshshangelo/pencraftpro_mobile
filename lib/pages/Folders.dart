// ignore_for_file: use_build_context_synchronously, deprecated_member_use, library_private_types_in_public_api

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:pencraftpro/FolderService.dart';
import 'package:pencraftpro/services/LogoutService.dart';
import 'package:pencraftpro/view/ViewFolderPage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pencraftpro/services/ProfileService.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class Folders extends StatefulWidget {
  const Folders({super.key});

  @override
  _FoldersState createState() => _FoldersState();
}

class _FoldersState extends State<Folders> {
  final TextEditingController _searchController = TextEditingController();
  bool isSearching = false;
  bool isSelecting = false;
  List<Folder> folders = [];
  Set<String> selectedFolderIds = {};

  final List<Color> _folderColors = [
    Colors.lightBlue.shade100,
    Colors.pink.shade100,
    Colors.green.shade100,
    Colors.amber.shade100,
    Colors.purple.shade100,
    Colors.cyan.shade100,
    Colors.orange.shade100,
    Colors.red,
    Colors.green,
    Colors.blue,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.cyan,
    Colors.amber,
    Colors.indigo,
    Colors.pink,
  ];

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showRenameFolderDialog(Folder folder) async {
    final controller = TextEditingController(text: folder.name);

    final newName = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              'Rename Folder',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              style: Theme.of(context).textTheme.bodyMedium,
              decoration: const InputDecoration(
                hintText: 'New folder name',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('Save'),
              ),
            ],
          ),
    );

    if (newName != null && newName.isNotEmpty && newName != folder.name) {
      final index = folders.indexWhere((f) => f.id == folder.id);
      if (index != -1) {
        folders[index] = Folder(id: folder.id, name: newName);
        await FolderService.saveFolders(folders);
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Folder renamed to "$newName".',
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

  Future<void> _loadFolders() async {
    final loaded = await FolderService.loadFolders();
    setState(() => folders = loaded);
  }

  Future<void> _createNewFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              'Create New Folder',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Folder Name',
                hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 12,
                ),
              ),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
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
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: Text(
                  'Create',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
            ],
          ),
    );

    if (name != null && name.isNotEmpty) {
      await FolderService.addFolder(name);
      await _loadFolders();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Folder "$name" created.',
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

  Future<void> _deleteSelectedFolders() async {
    final count = selectedFolderIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              count > 1 ? 'Delete $count Folders' : 'Remove Folder',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            content: Text(
              count > 1
                  ? 'Are you sure you want to remove these $count folders? Notes inside will stay but unassigned.'
                  : 'Are you sure you want to remove this folder? Notes inside will stay but unassigned.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontSize: 16),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
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
                  foregroundColor: Theme.of(context).colorScheme.onError,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  'Remove',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onError,
                  ),
                ),
              ),
            ],
          ),
    );
    if (confirm != true) return;

    final remaining =
        folders.where((f) => !selectedFolderIds.contains(f.id)).toList();
    await FolderService.saveFolders(remaining);

    await _removeFolderIdFromNotes(selectedFolderIds.toList());

    setState(() {
      folders = remaining;
      isSelecting = false;
      selectedFolderIds.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count > 1 ? '$count folders removed.' : 'Folder removed.',
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

  Future<void> _removeFolderIdFromNotes(List<String> deletedFolderIds) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('notes') ?? '[]';
    final List<dynamic> jsonList = jsonDecode(jsonString);

    final updatedNotes =
        jsonList.map<Map<String, dynamic>>((note) {
          if (deletedFolderIds.contains(note['folderId'])) {
            // Create a new map without folder-related fields
            final Map<String, dynamic> newNote = Map<String, dynamic>.from(
              note,
            );
            newNote.remove('folderId');
            newNote.remove('folderColor');
            newNote.remove('folderName');
            return newNote;
          }
          return Map<String, dynamic>.from(note);
        }).toList();

    // Update SharedPreferences
    await prefs.setString('notes', jsonEncode(updatedNotes));

    // Update Firestore
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (var note in updatedNotes) {
        if (deletedFolderIds.contains(note['folderId'])) {
          final noteRef = FirebaseFirestore.instance
              .collection('notes')
              .doc(note['id']);
          batch.update(noteRef, {
            'folderId': FieldValue.delete(),
            'folderColor': FieldValue.delete(),
            'folderName': FieldValue.delete(),
            'updatedAt': DateTime.now().toIso8601String(),
          });
        }
      }
      await batch.commit();
    } catch (e) {
      print('Error updating Firestore: $e');
      // Continue even if Firestore update fails - local changes are saved
    }
  }

  void _toggleSelectFolder(String id) {
    setState(() {
      if (selectedFolderIds.contains(id)) {
        selectedFolderIds.remove(id);
      } else {
        selectedFolderIds.add(id);
      }
    });
  }

  void _selectAllFolders() {
    setState(() {
      if (selectedFolderIds.length == folders.length) {
        selectedFolderIds.clear();
      } else {
        selectedFolderIds = folders.map((f) => f.id).toSet();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered =
        folders.where((f) {
          final q = _searchController.text.toLowerCase();
          return f.name.toLowerCase().contains(q);
        }).toList();

    return WillPopScope(
      onWillPop: () async {
        // Prevent going back
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          title:
              isSelecting
                  ? Text(
                    '${selectedFolderIds.length} selected',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontSize: 20,
                    ),
                  )
                  : isSearching
                  ? TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search folders...',
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
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                  )
                  : Text(
                    'Folders',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontSize: 20,
                    ),
                  ),
          actions:
              isSelecting
                  ? [
                    IconButton(
                      icon: const Icon(Icons.select_all),
                      onPressed: _selectAllFolders,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        setState(() {
                          isSelecting = false;
                          selectedFolderIds.clear();
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed:
                          selectedFolderIds.isEmpty
                              ? null
                              : _deleteSelectedFolders,
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
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontSize: 20,
                        ),
                      ),
                    ),
                  ],
        ),
        drawer: _buildDrawer(),
        body:
            filtered.isEmpty
                ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSearching ? Icons.search : Icons.folder,
                        size: 100,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isSearching ? 'No matching folders' : 'No folders yet',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 15,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
                : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) {
                    final folder = filtered[i];
                    final color = _folderColors[i % _folderColors.length];
                    final isSelected = selectedFolderIds.contains(folder.id);
                    return GestureDetector(
                      onTap: () {
                        if (isSelecting) {
                          _toggleSelectFolder(folder.id);
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (_) => ViewFolderPage(folderId: folder.id),
                            ),
                          );
                        }
                      },
                      child: Card(
                        color: color,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side:
                              isSelected
                                  ? BorderSide(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    width: 2,
                                  )
                                  : BorderSide.none,
                        ),
                        margin: const EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 8,
                        ),
                        elevation: 2,
                        child: Stack(
                          children: [
                            ListTile(
                              leading: Icon(
                                Icons.folder,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              title: Text(
                                folder.name,
                                style: Theme.of(
                                  context,
                                ).textTheme.bodyMedium?.copyWith(fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing:
                                  isSelecting
                                      ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(
                                              Icons.edit,
                                              size: 20,
                                            ),
                                            onPressed:
                                                () => _showRenameFolderDialog(
                                                  folder,
                                                ),
                                          ),
                                          if (isSelected)
                                            Icon(
                                              Icons.check_circle,
                                              color:
                                                  Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                              size: 24,
                                            ),
                                        ],
                                      )
                                      : null,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        floatingActionButton: FloatingActionButton(
          onPressed: _createNewFolder,
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          child: const Icon(Icons.create_new_folder),
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

  Drawer _buildDrawer() {
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
          _drawerItem(Icons.note, 'Notes', '/notes'),
          _drawerItem(Icons.alarm, 'Reminders', '/reminders'),
          Divider(thickness: 1, color: Theme.of(context).colorScheme.onSurface),
          _drawerItem(Icons.label, 'Labels', '/labels'),
          Divider(thickness: 1, color: Theme.of(context).colorScheme.onSurface),
          _drawerItem(Icons.folder, 'Folders', '/folders', selected: true),
          _drawerItem(Icons.archive, 'Archive', '/archive'),
          _drawerItem(Icons.delete, 'Recycle Bin', '/deleted'),
          _drawerItem(Icons.settings, 'Account Settings', '/accountsettings'),
          Divider(thickness: 1, color: Theme.of(context).colorScheme.onSurface),
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
    );
  }

  ListTile _drawerItem(
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
        // Skip profile check for account settings and logout
        if (route == '/accountsettings' || route == '/logout') {
          Navigator.pushNamed(context, route);
          return;
        }

        // Skip profile check for basic features
        if (route == '/notes' ||
            route == '/reminders' ||
            route == '/labels' ||
            route == '/folders' ||
            route == '/archive' ||
            route == '/deleted') {
          Navigator.pushNamed(context, route);
          return;
        }

        // For other features that might need profile completion
        final isComplete = await ProfileService.isProfileComplete();
        if (!isComplete) {
          if (!mounted) return;

          // Show dialog instead of forcing navigation
          final shouldGoToSettings = await showDialog<bool>(
            context: context,
            builder:
                (context) => AlertDialog(
                  title: Text(
                    'Complete Profile Setup',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  content: Text(
                    'Would you like to complete your profile setup now?',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(
                        'Later',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(
                        'Complete Setup',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
          );

          if (shouldGoToSettings == true) {
            Navigator.pushNamed(context, '/accountsettings');
          }
          return;
        }
        Navigator.pushNamed(context, route);
      },
    );
  }
}
