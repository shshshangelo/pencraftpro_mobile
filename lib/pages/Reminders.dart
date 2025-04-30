import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../view/ViewRemindersPage.dart';

class Reminders extends StatefulWidget {
  const Reminders({super.key});

  @override
  State<Reminders> createState() => _RemindersState();
}

class _RemindersState extends State<Reminders> {
  final TextEditingController _searchController = TextEditingController();
  bool isSearching = false;
  List<Map<String, dynamic>> notes = [];

  @override
  void initState() {
    super.initState();
    _loadNotesFromPrefs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadNotesFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('notes');
    if (jsonString != null) {
      try {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        setState(() {
          notes = jsonList.map((e) => Map<String, dynamic>.from(e)).toList();
          notes.sort((a, b) {
            final aDate =
                a['createdAt'] != null
                    ? DateTime.tryParse(a['createdAt'].toString()) ??
                        DateTime.now()
                    : DateTime.now();
            final bDate =
                b['createdAt'] != null
                    ? DateTime.tryParse(b['createdAt'].toString()) ??
                        DateTime.now()
                    : DateTime.now();
            if (a['isPinned'] == true && b['isPinned'] != true) return -1;
            if (a['isPinned'] != true && b['isPinned'] == true) return 1;
            return bDate.compareTo(aDate);
          });
        });
      } catch (e) {
        print('Error loading notes: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        body: Center(
          child: Text(
            'Please sign in to view reminders',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }

    final filteredNotes =
        notes.where((note) {
          if (note['isDeleted'] == true || note['reminder'] == null) {
            return false;
          }
          final q = _searchController.text.toLowerCase();
          final t = (note['title'] ?? '').toLowerCase();
          final c =
              (note['contentJson'] ?? [])
                  .map((op) => op['text'] as String? ?? '')
                  .join()
                  .toLowerCase();
          final l = (note['labels'] as List?)?.join(' ').toLowerCase() ?? '';
          return t.contains(q) || c.contains(q) || l.contains(q);
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
      leading: Builder(
        builder:
            (context) => IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
      ),
      title:
          isSearching
              ? TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search reminders...',
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
                'Reminders',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 20,
                ),
              ),
      actions: [
        IconButton(
          icon: Icon(isSearching ? Icons.close : Icons.search),
          onPressed: () {
            setState(() {
              isSearching = !isSearching;
              if (!isSearching) _searchController.clear();
            });
          },
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
          _buildDrawerItem(Icons.note, 'Notes', '/notes'),
          _buildDrawerItem(
            Icons.alarm,
            'Reminders',
            '/reminders',
            selected: true,
          ),
          Divider(thickness: 1, color: Theme.of(context).colorScheme.onSurface),
          _buildDrawerItem(Icons.label, 'Labels', '/labels'),
          Divider(thickness: 1, color: Theme.of(context).colorScheme.onSurface),
          _buildDrawerItem(Icons.folder, 'Folders', '/folders'),
          _buildDrawerItem(Icons.archive, 'Archive', '/archive'),
          _buildDrawerItem(Icons.delete, 'Recycle Bin', '/deleted'),
          _buildDrawerItem(
            Icons.settings,
            'Account Settings',
            '/accountsettings',
          ),
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
                            style: Theme.of(
                              context,
                            ).textTheme.labelLarge?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          onPressed: () => Navigator.pop(context, false),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.error,
                          ),
                          child: Text(
                            'Logout',
                            style: Theme.of(
                              context,
                            ).textTheme.labelLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onError,
                            ),
                          ),
                          onPressed: () => Navigator.pop(context, true),
                        ),
                      ],
                    ),
              );
              if (confirm == true) {
                await FirebaseAuth.instance.signOut();
                if (context.mounted) {
                  Navigator.of(
                    context,
                  ).pushNamedAndRemoveUntil('/login', (route) => false);
                }
              }
            },
          ),
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
      onTap: () => Navigator.pushNamed(context, route),
    );
  }

  Widget _buildBody(List<Map<String, dynamic>> notes) {
    if (notes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSearching ? Icons.search : Icons.alarm,
              size: 100,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(height: 8),
            Text(
              isSearching ? 'No matching reminders' : 'Reminders appear here',
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
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.75,
      ),
      itemCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[index];
        final labels = (note['labels'] as List<dynamic>?)?.cast<String>() ?? [];
        final reminder =
            note['reminder'] != null
                ? (note['reminder'] is String
                    ? DateTime.tryParse(note['reminder'])
                    : note['reminder'])
                : null;
        final now = DateTime.now();

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder:
                    (context) => ViewRemindersPage(
                      title: note['title'] ?? 'Untitled',
                      contentJson:
                          (note['contentJson'] as List<dynamic>?)
                              ?.map((e) => Map<String, dynamic>.from(e))
                              .toList() ??
                          [],
                      imagePaths:
                          (note['imagePaths'] as List<dynamic>?)
                              ?.map((e) => e.toString())
                              .toList() ??
                          [],
                      voiceNote: note['voiceNote'],
                      labels: labels,
                      reminder: reminder,
                      fontFamily: note['fontFamily'] ?? 'Roboto',
                      folderId: note['folderId'],
                      folderColor: note['folderColor'],
                      folderName: note['folderName'],
                    ),
              ),
            );
          },
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
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
                                  errorBuilder:
                                      (context, error, stackTrace) => Icon(
                                        Icons.broken_image,
                                        size: 100,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
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
          ),
        );
      },
    );
  }

  Widget _buildBottomBar() {
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
