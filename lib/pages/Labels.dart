// ignore_for_file: deprecated_member_use, unused_local_variable

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pencraftpro/LabelService.dart';
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
  List<String> availableLabels = [];

  @override
  void initState() {
    super.initState();
    _loadNotesFromPrefs();
    _syncNoteLabelsToLabelService();
  }

  void _showRenameDialog(String oldName) async {
    final controller = TextEditingController(text: oldName);

    final newName = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              'Rename Label',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: TextField(
              controller: controller,
              style:
                  Theme.of(
                    context,
                  ).textTheme.bodyMedium, // <-- default font size for input
              decoration: InputDecoration(
                hintText: 'New label name',
                hintStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).hintColor,
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: Text(
                  'Save',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
            ],
          ),
    );

    if (newName != null && newName.isNotEmpty && newName != oldName) {
      try {
        await LabelService.updateLabel(oldName, newName);
        setState(() {
          final index = availableLabels.indexWhere((l) => l == oldName);
          if (index != -1) {
            availableLabels[index] = newName;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Label renamed to "$newName".',
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
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error updating label: $e.',
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

  void _loadLabelsFromService() async {
    final labelObjects = await LabelService.loadLabels();
    setState(() {
      availableLabels = labelObjects.map((label) => label.name).toList();
    });
  }

  Future<void> _syncNoteLabelsToLabelService() async {
    final prefs = await SharedPreferences.getInstance();
    final notesJson = prefs.getString('notes') ?? '[]';
    final List<dynamic> noteList = jsonDecode(notesJson);

    final Set<String> labelsInNotes = {};
    for (var note in noteList) {
      final labels = (note['labels'] as List<dynamic>?) ?? [];
      labelsInNotes.addAll(labels.map((e) => e.toString()));
    }

    final existing = await LabelService.loadLabels();
    final existingNames = existing.map((e) => e.name).toSet();

    for (final name in labelsInNotes) {
      if (!existingNames.contains(name)) {
        await LabelService.addLabel(name);
      }
    }
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
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),

            content: Text(
              'Are you sure you want to delete the selected labels? This will remove them from all notes and label list.',
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
        for (String labelName in selectedLabels) {
          await LabelService.deleteLabel(labelName);
        }

        final updatedLabels = await LabelService.loadLabels();
        setState(() {
          availableLabels = updatedLabels.map((l) => l.name).toList();
          selectedLabels.clear();
          isEditing = false;
        });

        await _loadNotesFromPrefs();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Labels deleted.',
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
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error deleting labels: $e.',
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

  void _deleteLabel(Label label) async {
    try {
      await LabelService.deleteLabel(label.name);

      final updatedLabels = await LabelService.loadLabels();

      setState(() {
        availableLabels = updatedLabels.map((l) => l.name).toList();
      });

      await _loadNotesFromPrefs();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Label "${label.name}" deleted.',
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error deleting label: $e.',
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

  void _editLabel(Label label) async {
    final controller = TextEditingController(text: label.name);
    final newName = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              'Edit Label',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              style:
                  Theme.of(
                    context,
                  ).textTheme.bodyMedium, // <-- default font size for input
              decoration: const InputDecoration(
                hintText: 'Label name',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: Text(
                  'Save',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
            ],
          ),
    );

    if (newName != null && newName.isNotEmpty && newName != label.name) {
      try {
        await LabelService.updateLabel(label.name, newName);
        setState(() {
          final index = availableLabels.indexWhere((l) => l == label.name);
          if (index != -1) {
            availableLabels[index] = newName;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Label updated to "$newName".',
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
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error updating label: $e.',
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Label>>(
      future: LabelService.loadLabels(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final allLabels = snapshot.data!.map((e) => e.name).toSet();

        final filteredLabels =
            allLabels
                .where(
                  (label) => label.toLowerCase().contains(
                    _searchController.text.toLowerCase(),
                  ),
                )
                .toList();

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

        return WillPopScope(
          onWillPop: () async {
            // Prevent going back to /notes
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
                floatingActionButton: FloatingActionButton(
                  onPressed: () async {
                    final controller = TextEditingController();
                    final newLabel = await showDialog<String>(
                      context: context,
                      builder:
                          (ctx) => AlertDialog(
                            title: Text(
                              'Create New Label',
                              style: Theme.of(
                                context,
                              ).textTheme.titleLarge?.copyWith(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            content: TextField(
                              controller: controller,
                              autofocus: true,
                              style:
                                  Theme.of(context)
                                      .textTheme
                                      .bodyMedium, // default size for input
                              decoration: InputDecoration(
                                hintText: 'Label name',
                                hintStyle: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).hintColor,
                                ),
                                border: const OutlineInputBorder(),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: Text(
                                  'Cancel',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                              ),
                              ElevatedButton(
                                onPressed:
                                    () => Navigator.pop(
                                      ctx,
                                      controller.text.trim(),
                                    ),
                                child: Text(
                                  'Create',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelLarge?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.onPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                    );

                    if (newLabel != null && newLabel.isNotEmpty) {
                      await LabelService.addLabel(newLabel);
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Label "$newLabel" created.',
                            style: TextStyle(
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                            ),
                          ),
                          backgroundColor:
                              Theme.of(context).colorScheme.primaryContainer,
                          behavior: SnackBarBehavior.floating,
                          margin: const EdgeInsets.all(8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      );
                    }
                  },
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  child: const Icon(Icons.add),
                ),
              );
            },
          ),
        );
      },
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
    return ListView.builder(
      padding: EdgeInsets.all(padding),
      itemCount: labels.length,
      itemBuilder: (context, index) {
        final label = labels[index];
        final isSelected = selectedLabels.contains(label);

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: ListTile(
            leading: const Icon(Icons.label),
            title: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
            trailing:
                isEditing
                    ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          onPressed:
                              () => _editLabel(
                                Label(
                                  id:
                                      DateTime.now().millisecondsSinceEpoch
                                          .toString(),
                                  name: label,
                                ),
                              ),
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        if (isSelected)
                          Icon(
                            Icons.check_circle,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                      ],
                    )
                    : null,
            selected: isSelected,
            onTap: () {
              if (isEditing) {
                setState(() {
                  isSelected
                      ? selectedLabels.remove(label)
                      : selectedLabels.add(label);
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
