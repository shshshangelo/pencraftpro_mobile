// ignore_for_file: unused_local_variable, unused_import

import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pencraftpro/services/logout_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../view/ViewArchivedPage.dart';

class Archive extends StatefulWidget {
  const Archive({super.key});

  @override
  State<Archive> createState() => _ArchiveState();
}

class _ArchiveState extends State<Archive> {
  final TextEditingController _searchController = TextEditingController();
  bool isSearching = false;
  bool isEditing = false;
  List<Map<String, dynamic>> notes = [];
  List<String> selectedNoteIds = [];

  @override
  void initState() {
    super.initState();
    _loadNotesFromPrefs();
  }

  Future<void> _loadNotesFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final notesString = prefs.getString('notes');
    if (notesString != null) {
      final List<dynamic> notesJson = jsonDecode(notesString);
      setState(() {
        notes =
            notesJson
                .map((e) => Map<String, dynamic>.from(e))
                .where(
                  (note) =>
                      note['isArchived'] == true && note['isDeleted'] != true,
                )
                .toList()
              ..sort((a, b) {
                if (a['isPinned'] == true && b['isPinned'] != true) return -1;
                if (a['isPinned'] != true && b['isPinned'] == true) return 1;
                final aDate =
                    DateTime.tryParse(a['createdAt'] ?? '') ?? DateTime.now();
                final bDate =
                    DateTime.tryParse(b['createdAt'] ?? '') ?? DateTime.now();
                return bDate.compareTo(aDate);
              });
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredNotes =
        notes.where((note) {
          final query = _searchController.text.toLowerCase();
          final title = (note['title'] ?? '').toLowerCase();
          final content = (note['content'] ?? '').toLowerCase();
          final labels =
              (note['labels'] as List?)?.join(' ').toLowerCase() ?? '';
          return title.contains(query) ||
              content.contains(query) ||
              labels.contains(query);
        }).toList();

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: _buildAppBar(),
        drawer: _buildDrawer(context),
        body: _buildBody(filteredNotes),
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Theme.of(context).colorScheme.primary,
      foregroundColor: Theme.of(context).colorScheme.onPrimary,
      title:
          isSearching
              ? TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search archived notes...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onPrimary.withOpacity(0.6),
                  ),
                ),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
                autofocus: true,
                onChanged: (_) => setState(() {}),
              )
              : Text(
                isEditing ? '${selectedNoteIds.length} selected' : 'Archive',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 20,
                ),
              ),
      actions: [
        if (!isEditing)
          IconButton(
            icon: Icon(isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                isSearching = !isSearching;
                if (!isSearching) _searchController.clear();
              });
            },
          ),
        if (isEditing)
          IconButton(
            icon: const Icon(Icons.restore),
            onPressed:
                selectedNoteIds.isNotEmpty ? _restoreSelectedNotes : null,
          ),
        if (isEditing)
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              setState(() {
                isEditing = false;
                selectedNoteIds.clear();
              });
            },
          ),
        if (!isEditing)
          TextButton(
            onPressed: () {
              setState(() => isEditing = true);
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
          _drawerItem(Icons.note, 'Notes', '/notes'),
          _drawerItem(Icons.alarm, 'Reminders', '/reminders'),
          Divider(thickness: 1, color: Theme.of(context).colorScheme.onSurface),
          _drawerItem(Icons.label, 'Labels', '/labels'),
          Divider(thickness: 1, color: Theme.of(context).colorScheme.onSurface),
          _drawerItem(Icons.folder, 'Folders', '/folders'),
          _drawerItem(Icons.archive, 'Archive', '/archive', selected: true),
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
      onTap: () => Navigator.pushNamed(context, route),
    );
  }

  Widget _buildBody(List<Map<String, dynamic>> notes) {
    if (notes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSearching ? Icons.search : Icons.archive,
              size: 100,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(height: 8),
            Text(
              isSearching
                  ? 'No matching archived notes'
                  : 'Archived notes appear here',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 15,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.75,
      ),
      itemCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[index];
        final id = note['id'].toString();
        final isSelected = selectedNoteIds.contains(id);
        final reminder =
            note['reminder'] != null
                ? DateTime.tryParse(note['reminder'])
                : null;
        final folderColor =
            note['folderColor'] != null
                ? Color(note['folderColor'])
                : Theme.of(context).colorScheme.primary;
        final labels = (note['labels'] as List?)?.cast<String>() ?? [];
        final imagePaths = (note['imagePaths'] as List?)?.cast<String>() ?? [];
        final now = DateTime.now();

        return GestureDetector(
          onTap: () {
            if (isEditing) {
              setState(() {
                if (isSelected) {
                  selectedNoteIds.remove(id);
                } else {
                  selectedNoteIds.add(id);
                }
              });
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (_) => ViewArchivedPage(
                        title: note['title'] ?? 'Untitled',
                        contentJson:
                            (note['contentJson'] as List?)
                                ?.cast<Map<String, dynamic>>() ??
                            [],
                        imagePaths: imagePaths,
                        voiceNote: note['voiceNote'],
                        labels: labels,
                        fontFamily: note['fontFamily'],
                        folderId: note['folderId'],
                        folderColor: note['folderColor'],
                        folderName: note['folderName'],
                      ),
                ),
              );
            }
          },
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side:
                  isSelected
                      ? BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      )
                      : BorderSide.none,
            ),
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (note['imagePaths'] != null &&
                            (note['imagePaths'] as List).isNotEmpty)
                          Icon(
                            Icons.image,
                            size: 16,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        if (note['voiceNote'] != null)
                          Icon(
                            Icons.mic,
                            size: 16,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        if (note['folderId'] != null)
                          Icon(
                            Icons.bookmark,
                            size: 16,
                            color:
                                note['folderColor'] != null
                                    ? Color(note['folderColor'])
                                    : Theme.of(context).colorScheme.primary,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      note['title'] ?? 'Untitled',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    if (reminder != null)
                      Row(
                        children: [
                          Icon(
                            Icons.alarm,
                            size: 16,
                            color:
                                reminder.isBefore(now)
                                    ? Theme.of(context).colorScheme.error
                                    : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
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
                                fontSize: 12,
                                color:
                                    reminder.isBefore(now)
                                        ? Theme.of(context).colorScheme.error
                                        : Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    if (labels.isNotEmpty)
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children:
                            labels.map((label) {
                              return Chip(
                                padding: EdgeInsets.zero,
                                labelPadding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                label: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.label_important,
                                      size: 12,
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      label,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall?.copyWith(
                                        fontSize: 10,
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
                                    ).colorScheme.primaryContainer,
                              );
                            }).toList(),
                      ),
                    const SizedBox(height: 8),
                    if (note['contentJson'] != null)
                      Text(
                        (note['contentJson'] as List)
                            .map((op) => op['text'] ?? '')
                            .join()
                            .trim(),
                        maxLines: 8,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 12,
                          fontFamily: note['fontFamily'] ?? 'Roboto',
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (note['imagePaths'] != null &&
                        (note['imagePaths'] as List).isNotEmpty)
                      SizedBox(
                        height: 100,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: note['imagePaths'].length,
                          itemBuilder: (context, imgIndex) {
                            final imgPath = note['imagePaths'][imgIndex];
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(imgPath),
                                  width: 100,
                                  height: 100,
                                  fit: BoxFit.cover,
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
          ),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    return BottomAppBar(
      color: Theme.of(context).colorScheme.error,
      shape: const CircularNotchedRectangle(),
      notchMargin: 8.0,
      child: IconButton(
        icon: Icon(Icons.home, color: Theme.of(context).colorScheme.onError),
        iconSize: 32,
        onPressed: () => Navigator.pushNamed(context, '/select'),
      ),
    );
  }

  void _restoreSelectedNotes() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(
              'Restore Notes',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            content: Text(
              'Are you sure you want to restore the selected notes?',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
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
                onPressed: () => Navigator.pop(ctx, true),
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

    final prefs = await SharedPreferences.getInstance();
    final notesString = prefs.getString('notes');
    if (notesString != null) {
      final List<dynamic> notesJson = jsonDecode(notesString);
      final updatedNotes =
          notesJson.map((note) {
            final map = Map<String, dynamic>.from(note);
            if (selectedNoteIds.contains(map['id'].toString())) {
              map['isArchived'] = false;
            }
            return map;
          }).toList();

      await prefs.setString('notes', jsonEncode(updatedNotes));
      setState(() {
        notes =
            updatedNotes
                .where((n) => n['isArchived'] == true)
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
        selectedNoteIds.clear();
        isEditing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notes restored'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}
