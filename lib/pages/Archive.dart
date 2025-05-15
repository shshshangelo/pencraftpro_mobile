// ignore_for_file: unused_local_variable, unused_import

import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pencraftpro/services/logout_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../view/ViewArchivedPage.dart';
import 'package:pencraftpro/services/profile_service.dart';

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
              ),
            );
            return;
          }
        }
        Navigator.pushNamed(context, route);
      },
    );
  }

  Widget _buildBody(List<Map<String, dynamic>> notes) {
    if (notes.isEmpty) {
      return SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return OrientationBuilder(
      builder: (context, orientation) {
        final isLandscape = orientation == Orientation.landscape;
        final screenWidth = MediaQuery.of(context).size.width;
        final crossAxisCount = isLandscape ? 4 : 2;
        final childAspectRatio = isLandscape ? 0.8 : 0.7;
        final padding = screenWidth * 0.02;
        final spacing = screenWidth * 0.02;

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
              childAspectRatio: childAspectRatio,
            ),
            itemCount: notes.length,
            itemBuilder: (context, index) {
              final note = notes[index];
              final id = note['id'].toString();
              final isSelected = selectedNoteIds.contains(id);
              final reminder =
                  note['reminder'] != null
                      ? DateTime.tryParse(note['reminder'].toString())
                      : null;
              final folderColor =
                  note['folderColor'] != null
                      ? Color(note['folderColor'])
                      : Theme.of(context).colorScheme.primary;
              final labels = (note['labels'] as List?)?.cast<String>() ?? [];
              final imagePaths =
                  (note['imagePaths'] as List?)?.cast<String>() ?? [];
              final isPinned = note['isPinned'] ?? false;
              final now = DateTime.now();

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
                              (item['text'] as String?)?.trim().isNotEmpty ??
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
              final actualCollaboratorsPresent =
                  (note['collaboratorEmails'] as List<dynamic>?)?.isNotEmpty ??
                  false;

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
              if (actualCollaboratorsPresent) landscapeContentScore++;

              bool showImagesInCard = true;
              if (isLandscape && landscapeContentScore > 3) {
                showImagesInCard = false;
              }

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
                        padding: EdgeInsets.all(padding),
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: isLandscape ? 200 : 300,
                            ),
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
                                          size: isLandscape ? 12 : 14,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                        ),
                                      if (actualVoiceNotePresent)
                                        Icon(
                                          Icons.mic,
                                          size: isLandscape ? 12 : 14,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                        ),
                                      if (actualChecklistPresent)
                                        Icon(
                                          Icons.checklist,
                                          size: isLandscape ? 12 : 14,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                        ),
                                      if (note['folderId'] != null)
                                        Icon(
                                          Icons.bookmark,
                                          size: isLandscape ? 12 : 14,
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
                                          size: isLandscape ? 12 : 14,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                        ),
                                    ].where((widget) => widget is Icon).fold<
                                      List<Widget>
                                    >([], (prev, elm) {
                                      if (prev.isNotEmpty)
                                        prev.add(
                                          SizedBox(width: isLandscape ? 2 : 4),
                                        );
                                      prev.add(elm);
                                      return prev;
                                    }),
                                  ),
                                ),
                                if (actualCollaboratorsPresent)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: ClipRect(
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.people,
                                            size: isLandscape ? 12 : 14,
                                            color:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              'Shared Notes',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall?.copyWith(
                                                fontSize: isLandscape ? 8 : 10,
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
                                if (actualLabelsPresent)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Wrap(
                                      spacing: 2,
                                      runSpacing: 2,
                                      children:
                                          labels.take(2).map<Widget>((label) {
                                            return Chip(
                                              padding: EdgeInsets.zero,
                                              labelPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                  ),
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              label: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.label_important,
                                                    size: isLandscape ? 8 : 10,
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
                                                          isLandscape ? 8 : 10,
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
                                if (actualTitlePresent)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2.0),
                                    child: Text(
                                      note['title'] ?? 'Untitled',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        fontSize: isLandscape ? 14 : 16,
                                        fontFamily:
                                            note['fontFamily'] ?? 'Roboto',
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                if (actualReminderPresent)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2.0),
                                    child: ClipRect(
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.alarm,
                                            size: isLandscape ? 10 : 12,
                                            color:
                                                reminder!.isBefore(now)
                                                    ? Theme.of(
                                                      context,
                                                    ).colorScheme.error
                                                    : Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 2),
                                          Expanded(
                                            child: Text(
                                              DateFormat(
                                                'MMM dd, hh:mm a',
                                              ).format(reminder),
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall?.copyWith(
                                                fontSize: isLandscape ? 8 : 10,
                                                color:
                                                    reminder.isBefore(now)
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
                                if (actualVoiceNotePresent)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: ClipRect(
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.mic,
                                            size: isLandscape ? 12 : 14,
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
                                              if (taskText.isEmpty)
                                                return const SizedBox.shrink();
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
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
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
              map['updatedAt'] =
                  DateTime.now().toIso8601String(); // update timestamp
            }
            return map;
          }).toList();

      await prefs.setString('notes', jsonEncode(updatedNotes));

      // 🔥 Firestore update here
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        for (final id in selectedNoteIds) {
          try {
            await FirebaseFirestore.instance.collection('notes').doc(id).update(
              {
                'isArchived': false,
                'updatedAt': DateTime.now().toIso8601String(),
              },
            );
          } catch (e) {
            // Optional: store pending updates if offline
          }
        }
      }

      setState(() {
        selectedNoteIds.clear();
        isEditing = false;
      });

      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/notes', (route) => false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notes restored'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }
}
