// ignore_for_file: deprecated_member_use, unused_local_variable

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pencraftpro/services/logout_service.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'NotesByLabelScreen.dart';

class Labels extends StatefulWidget {
  const Labels({super.key});

  @override
  _LabelsState createState() => _LabelsState();
}

class _LabelsState extends State<Labels> {
  final TextEditingController _searchController = TextEditingController();
  bool isSearching = false;
  bool isEditing = false;
  List<Map<String, dynamic>> notes = [];
  Set<String> selectedLabels = {};

  @override
  void initState() {
    super.initState();
    _loadNotesFromPrefs();
  }

  Future<void> _loadNotesFromPrefs() async {
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
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _deleteSelectedLabels() async {
    if (selectedLabels.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              'Confirm Deletion',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            content: Text(
              'Are you sure you want to delete the selected labels? This will remove them from all notes.',
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
      setState(() {
        for (var note in notes) {
          note['labels'] =
              (note['labels'] as List<dynamic>?)
                  ?.where((label) => !selectedLabels.contains(label))
                  .toList() ??
              [];
        }
        selectedLabels.clear();
        isEditing = false;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('notes', jsonEncode(notes));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Labels deleted')));
    }
  }

  void _selectAllLabels(Set<String> allLabels) {
    setState(() {
      selectedLabels = allLabels;
    });
  }

  void _cancelSelection() {
    setState(() {
      selectedLabels.clear();
      isEditing = false;
    });
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

    final Set<String> allLabels = {};
    for (var note in notes) {
      final labels = (note['labels'] as List<dynamic>?) ?? [];
      allLabels.addAll(labels.map((e) => e.toString()));
    }

    final filteredLabels =
        allLabels.where((label) {
          final query = _searchController.text.toLowerCase();
          return label.toLowerCase().contains(query);
        }).toList();

    return WillPopScope(
      onWillPop: () async {
        Navigator.pushNamed(context, '/notes');
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
            appBar: _buildAppBar(context, filteredLabels.toSet()),
            body:
                filteredLabels.isEmpty
                    ? _buildEmptyState()
                    : _buildLabelsGrid(
                      filteredLabels,
                      padding,
                      spacing,
                      crossAxisCount,
                    ),
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
          ListTile(
            leading: Icon(
              Icons.note,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            title: Text(
              'Notes',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontSize: 13),
            ),
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
          Divider(thickness: 1, color: Theme.of(context).colorScheme.onSurface),
          ListTile(
            leading: Icon(
              Icons.label,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(
              'Labels',
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
            onTap: () => Navigator.pushNamed(context, '/labels'),
          ),
          Divider(thickness: 1, color: Theme.of(context).colorScheme.onSurface),
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
            onTap: () => Navigator.pushNamed(context, '/accountsettings'),
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
            onTap: () => showLogoutDialog(context),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    Set<String> allLabels,
  ) {
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
                '${selectedLabels.length} selected',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 20,
                ),
              )
              : isSearching
              ? TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search labels...',
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
                'Labels',
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
                  onPressed: () => _selectAllLabels(allLabels),
                ),
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: _cancelSelection,
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed:
                      selectedLabels.isNotEmpty ? _deleteSelectedLabels : null,
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
                      fontSize: 20,
                    ),
                  ),
                ),
              ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.label,
            size: 100,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(height: 8),
          Text(
            'No labels yet',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: 15,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabelsGrid(
    List<String> labels,
    double padding,
    double spacing,
    int crossAxisCount,
  ) {
    return GridView.builder(
      padding: EdgeInsets.all(padding),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
        childAspectRatio: 0.65,
      ),
      itemCount: labels.length,
      itemBuilder: (context, index) {
        final label = labels[index];
        final isSelected = selectedLabels.contains(label);

        return GestureDetector(
          onTap: () {
            if (isEditing) {
              setState(() {
                if (isSelected) {
                  selectedLabels.remove(label);
                } else {
                  selectedLabels.add(label);
                }
              });
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (_) => NotesByLabelScreen(label: label, notes: notes),
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
            child: SizedBox(
              height: 300,
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.label,
                          size: 50,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          label,
                          style: Theme.of(
                            context,
                          ).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ],
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
          ),
        );
      },
    );
  }

  Widget _buildBottomAppBar() {
    return BottomAppBar(
      color: Theme.of(context).colorScheme.error,
      shape: const CircularNotchedRectangle(),
      notchMargin: 10.0,
      child: IconButton(
        icon: Icon(Icons.home, color: Theme.of(context).colorScheme.onError),
        iconSize: 32,
        onPressed: () => Navigator.pushNamed(context, '/select'),
      ),
    );
  }
}
