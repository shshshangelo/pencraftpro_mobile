// ignore_for_file: deprecated_member_use, library_private_types_in_public_api, unused_field

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../view/ViewedFolderPage.dart';
import 'package:intl/intl.dart';

class ViewFolderPage extends StatefulWidget {
  final String folderId;

  const ViewFolderPage({super.key, required this.folderId});

  @override
  _ViewFolderPageState createState() => _ViewFolderPageState();
}

class _ViewFolderPageState extends State<ViewFolderPage> {
  List<Map<String, dynamic>> notes = [];

  @override
  void initState() {
    super.initState();
    _loadNotesForFolder();
  }

  Future<void> _loadNotesForFolder() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('notes');
    if (jsonString != null) {
      try {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        setState(() {
          notes =
              jsonList
                  .where(
                    (note) =>
                        note['folderId'] == widget.folderId &&
                        note['isDeleted'] != true,
                  )
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
        });
      } catch (e) {
        print('Error loading notes: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = isLandscape ? 4 : 2;
    final childAspectRatio = isLandscape ? 0.8 : 0.7;
    final padding = screenWidth * 0.02;
    final spacing = screenWidth * 0.02;
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Folder Dashboard',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Theme.of(context).colorScheme.onPrimary,
            fontSize: 22,
          ),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.all(padding),
          child:
              notes.isEmpty
                  ? SizedBox(
                    height: MediaQuery.of(context).size.height * 0.6,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.folder,
                            size: 100,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No notes found for this folder.',
                            style: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.copyWith(
                              fontSize: 15,
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
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: spacing,
                      mainAxisSpacing: spacing,
                      childAspectRatio: childAspectRatio,
                    ),
                    itemCount: notes.length,
                    itemBuilder: (context, index) {
                      final note = notes[index];
                      final reminder =
                          note['reminder'] != null
                              ? DateTime.tryParse(note['reminder'].toString())
                              : null;
                      final labels =
                          (note['labels'] as List?)?.cast<String>() ?? [];
                      final imagePaths =
                          (note['imagePaths'] as List?)?.cast<String>() ?? [];
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
                          (note['collaboratorEmails'] as List<dynamic>?)
                              ?.isNotEmpty ??
                          false;

                      final List<Map<String, dynamic>> checklists =
                          contentList
                              .where(
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
                          print(
                            'ViewFolderPage - note before navigation: $note',
                          );
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => ViewedFolderPage(
                                    title: note['title'] ?? 'Untitled',
                                    contentJson:
                                        (note['contentJson'] as List?)
                                            ?.map(
                                              (e) =>
                                                  Map<String, dynamic>.from(e),
                                            )
                                            .toList() ??
                                        [],
                                    imagePaths: imagePaths,
                                    voiceNote: note['voiceNote'],
                                    labels: labels,
                                    reminder: reminder,
                                    fontFamily: note['fontFamily'],
                                    folderId: note['folderId'],
                                    folderColor: note['folderColor'],
                                    folderName: note['folderName'],
                                  ),
                            ),
                          );
                        },
                        child: Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide.none,
                          ),
                          elevation: 5,
                          child: Stack(
                            children: [
                              Padding(
                                padding: EdgeInsets.all(padding),
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    return SizedBox(
                                      height: isLandscape ? 200 : 300,
                                      child: SingleChildScrollView(
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            ClipRect(
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (hasImages)
                                                    Icon(
                                                      Icons.image,
                                                      size:
                                                          isLandscape ? 12 : 14,
                                                      color:
                                                          Theme.of(context)
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                    ),
                                                  if (actualVoiceNotePresent)
                                                    Icon(
                                                      Icons.mic,
                                                      size:
                                                          isLandscape ? 12 : 14,
                                                      color:
                                                          Theme.of(context)
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                    ),
                                                  if (actualChecklistPresent)
                                                    Icon(
                                                      Icons.checklist,
                                                      size:
                                                          isLandscape ? 12 : 14,
                                                      color:
                                                          Theme.of(context)
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                    ),
                                                  if (note['folderId'] != null)
                                                    Icon(
                                                      Icons.bookmark,
                                                      size:
                                                          isLandscape ? 12 : 14,
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
                                                          isLandscape ? 12 : 14,
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
                                                            isLandscape ? 2 : 4,
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
                                                padding: const EdgeInsets.only(
                                                  top: 2,
                                                ),
                                                child: ClipRect(
                                                  child: Row(
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
                                                      const SizedBox(width: 4),
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
                                                padding: const EdgeInsets.only(
                                                  top: 2,
                                                ),
                                                child: Wrap(
                                                  spacing: 2,
                                                  runSpacing: 2,
                                                  children:
                                                      labels.take(2).map<
                                                        Widget
                                                      >((label) {
                                                        return Chip(
                                                          padding:
                                                              EdgeInsets.zero,
                                                          labelPadding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 4,
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
                                                                      ).colorScheme.onPrimaryContainer,
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
                                                padding: const EdgeInsets.only(
                                                  top: 2.0,
                                                ),
                                                child: Text(
                                                  note['title'] ?? 'Untitled',
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
                                                padding: const EdgeInsets.only(
                                                  top: 2.0,
                                                ),
                                                child: ClipRect(
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons.alarm,
                                                        size:
                                                            isLandscape
                                                                ? 10
                                                                : 12,
                                                        color:
                                                            reminder.isBefore(
                                                                  now,
                                                                )
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
                                                      const SizedBox(width: 2),
                                                      Expanded(
                                                        child: Text(
                                                          DateFormat(
                                                            'MMM dd, hh:mm a',
                                                          ).format(reminder),
                                                          style: Theme.of(
                                                            context,
                                                          ).textTheme.bodySmall?.copyWith(
                                                            fontSize:
                                                                isLandscape
                                                                    ? 8
                                                                    : 10,
                                                            color:
                                                                reminder.isBefore(
                                                                      now,
                                                                    )
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
                                                              TextOverflow
                                                                  .ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            if (actualVoiceNotePresent)
                                              Padding(
                                                padding: const EdgeInsets.only(
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
                                                      const SizedBox(width: 4),
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
                                                padding: const EdgeInsets.only(
                                                  top: 4.0,
                                                ),
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
                                                  maxLines: isLandscape ? 1 : 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            if (actualChecklistPresent)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 4.0,
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
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
                                                          final bool isChecked =
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
                                                                  vertical: 1.0,
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
                                                padding: const EdgeInsets.only(
                                                  top: 4.0,
                                                ),
                                                child: Builder(
                                                  builder: (context) {
                                                    final bool
                                                    shouldImageExpand =
                                                        !actualTextContent &&
                                                        !actualChecklistPresent &&
                                                        !actualVoiceNotePresent;

                                                    Widget imageWidget;
                                                    if (imagePaths.length ==
                                                        1) {
                                                      imageWidget = ClipRRect(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                        child: Container(
                                                          width:
                                                              double.infinity,
                                                          constraints: BoxConstraints(
                                                            maxHeight:
                                                                shouldImageExpand
                                                                    ? double
                                                                        .infinity
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
                                                      imageWidget = GridView.builder(
                                                        shrinkWrap: true,
                                                        physics:
                                                            const NeverScrollableScrollPhysics(),
                                                        gridDelegate:
                                                            SliverGridDelegateWithFixedCrossAxisCount(
                                                              crossAxisCount: 2,
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
                                                                    .length,
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
                                                          );
                                                        },
                                                      );
                                                      if (imagePaths.length >
                                                          4) {
                                                        imageWidget = Stack(
                                                          alignment:
                                                              Alignment.center,
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
                                                                          Colors
                                                                              .white,
                                                                      fontSize:
                                                                          20,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
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
                                                          imagePaths.length >
                                                              1) {
                                                        return SizedBox(
                                                          height: 75,
                                                          width:
                                                              double.infinity,
                                                          child: imageWidget,
                                                        );
                                                      } else {
                                                        return Container(
                                                          constraints: BoxConstraints(
                                                            maxHeight:
                                                                (imagePaths.length ==
                                                                        1)
                                                                    ? (isLandscape
                                                                        ? 80
                                                                        : 120)
                                                                    : 180,
                                                          ),
                                                          width:
                                                              double.infinity,
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
                            ],
                          ),
                        ),
                      );
                    },
                  ),
        ),
      ),
    );
  }
}
