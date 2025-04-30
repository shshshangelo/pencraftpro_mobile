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
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Notes in Folder',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Theme.of(context).colorScheme.onPrimary,
            fontSize: 20,
          ),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body:
          notes.isEmpty
              ? Center(
                child: Text(
                  'No notes in this folder',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
              )
              : GridView.builder(
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
                  final reminder =
                      note['reminder'] != null
                          ? DateTime.tryParse(note['reminder'])
                          : null;
                  final labels =
                      (note['labels'] as List?)?.cast<String>() ?? [];
                  final imagePaths =
                      (note['imagePaths'] as List?)?.cast<String>() ?? [];

                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (context) => ViewedFolderPage(
                                title: note['title'] ?? 'Untitled',
                                contentJson:
                                    (note['contentJson'] as List?)
                                        ?.map(
                                          (e) => Map<String, dynamic>.from(e),
                                        )
                                        .toList() ??
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
                              // Icons
                              Row(
                                children: [
                                  if (imagePaths.isNotEmpty)
                                    Icon(
                                      Icons.image,
                                      size: 16,
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                    ),
                                  if (note['voiceNote'] != null)
                                    Icon(
                                      Icons.mic,
                                      size: 16,
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                    ),
                                  if ((note['contentJson'] as List?)?.any(
                                        (e) =>
                                            (e['checklistItems'] as List?)
                                                ?.isNotEmpty ==
                                            true,
                                      ) ==
                                      true)
                                    Icon(
                                      Icons.checklist,
                                      size: 16,
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                    ),
                                  if (note['folderId'] != null)
                                    Icon(
                                      Icons.bookmark,
                                      size: 16,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // Labels
                              if (labels.isNotEmpty)
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children:
                                      labels.map((label) {
                                        return Chip(
                                          padding: EdgeInsets.zero,
                                          labelPadding:
                                              const EdgeInsets.symmetric(
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
                                                  fontSize: 10,
                                                  color:
                                                      Theme.of(context)
                                                          .colorScheme
                                                          .onPrimaryContainer,
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

                              // Title
                              Text(
                                note['title'] ?? 'Untitled',
                                style: Theme.of(
                                  context,
                                ).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),

                              // Reminder
                              if (reminder != null)
                                Row(
                                  children: [
                                    Icon(
                                      Icons.alarm,
                                      size: 16,
                                      color:
                                          reminder.isBefore(now)
                                              ? Theme.of(
                                                context,
                                              ).colorScheme.error
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
                                                  ? Theme.of(
                                                    context,
                                                  ).colorScheme.error
                                                  : Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              const SizedBox(height: 8),

                              // Content
                              if (note['contentJson'] != null)
                                Text(
                                  (note['contentJson'] as List)
                                      .map((op) => op['text'] ?? '')
                                      .join()
                                      .trim(),
                                  maxLines: 8,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.bodyMedium?.copyWith(
                                    fontSize: 12,
                                    color:
                                        Theme.of(
                                          context,
                                        ).textTheme.bodyMedium?.color,
                                    fontFamily: note['fontFamily'] ?? 'Roboto',
                                  ),
                                ),
                              const SizedBox(height: 8),

                              // Image Preview
                              if (imagePaths.isNotEmpty)
                                SizedBox(
                                  height: 100,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: imagePaths.length,
                                    itemBuilder: (context, imgIndex) {
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8.0,
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: Image.file(
                                            File(imagePaths[imgIndex]),
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
              ),
    );
  }
}
