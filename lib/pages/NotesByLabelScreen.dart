import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../view/ViewLabelsPage.dart';

class NotesByLabelScreen extends StatefulWidget {
  final String label;
  final List<Map<String, dynamic>> notes;

  const NotesByLabelScreen({
    super.key,
    required this.label,
    required this.notes,
  });

  @override
  _NotesByLabelScreenState createState() => _NotesByLabelScreenState();
}

class _NotesByLabelScreenState extends State<NotesByLabelScreen> {
  late List<Map<String, dynamic>> filteredNotes;

  @override
  void initState() {
    super.initState();
    _filterNotes();
  }

  void _filterNotes() {
    filteredNotes =
        widget.notes.where((note) {
          final labels =
              (note['labels'] as List?)?.map((e) => e.toString()) ?? [];
          final isDeleted = note['isDeleted'] == true;
          return labels.contains(widget.label) && !isDeleted;
        }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final screenWidth = MediaQuery.of(context).size.width;
    const minCardWidth = 150.0;
    final crossAxisCount = (screenWidth / minCardWidth).floor().clamp(2, 4);
    final padding = screenWidth * 0.03;
    final spacing = screenWidth * 0.02;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.label,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Theme.of(context).colorScheme.onPrimary,
            fontSize: 20,
          ),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: Padding(
        padding: EdgeInsets.all(padding),
        child:
            filteredNotes.isEmpty
                ? Center(
                  child: Text(
                    'No notes found for this label.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
                : GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: isLandscape ? 1.0 : 0.75,
                    crossAxisSpacing: spacing,
                    mainAxisSpacing: spacing,
                  ),
                  itemCount: filteredNotes.length,
                  itemBuilder: (context, index) {
                    final note = filteredNotes[index];
                    final title = note['title'] ?? 'Untitled';
                    final contentList =
                        (note['contentJson'] as List<dynamic>?)
                            ?.map((e) => Map<String, dynamic>.from(e))
                            .toList() ??
                        [];
                    final reminder =
                        note['reminder'] != null
                            ? DateTime.tryParse(note['reminder'].toString())
                            : null;
                    final imagePaths =
                        (note['imagePaths'] as List<dynamic>?)
                            ?.map((e) => e.toString())
                            .toList() ??
                        [];
                    final voiceNote = note['voiceNote'] as String?;
                    final labels =
                        (note['labels'] as List<dynamic>?)
                            ?.map((e) => e.toString())
                            .toList() ??
                        [];
                    final fontFamily = note['fontFamily'] ?? 'Roboto';
                    final isPinned = note['isPinned'] ?? false;

                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (_) => ViewLabelPage(
                                  title: note['title'] ?? '',
                                  contentJson:
                                      (note['contentJson'] as List<dynamic>)
                                          .cast<Map<String, dynamic>>(),
                                  imagePaths: List<String>.from(
                                    note['imagePaths'] ?? [],
                                  ),
                                  voiceNote: note['voiceNote'],
                                  labels:
                                      (note['labels'] as List<dynamic>)
                                          .cast<String>(),
                                  fontFamily: note['fontFamily'],
                                  reminder:
                                      note['reminder'] != null
                                          ? DateTime.tryParse(
                                            note['reminder'].toString(),
                                          )
                                          : null,
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
                        ),
                        elevation: 5,
                        child: Padding(
                          padding: EdgeInsets.all(padding * 1.5),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    if (imagePaths.isNotEmpty)
                                      Icon(
                                        Icons.image,
                                        size: isLandscape ? 14 : 16,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                      ),
                                    if (voiceNote != null)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 4),
                                        child: Icon(
                                          Icons.mic,
                                          size: isLandscape ? 14 : 16,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    if (isPinned)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 4),
                                        child: Icon(
                                          Icons.push_pin,
                                          size: isLandscape ? 14 : 16,
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    if (note['folderId'] != null)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 4),
                                        child: Icon(
                                          Icons.bookmark,
                                          size: isLandscape ? 14 : 16,
                                          color:
                                              note['folderColor'] != null
                                                  ? Color(note['folderColor'])
                                                  : Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                        ),
                                      ),
                                    const Spacer(),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  title,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: isLandscape ? 14 : 16,
                                    fontFamily: fontFamily,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
                                                Theme.of(
                                                  context,
                                                ).colorScheme.primaryContainer,
                                          );
                                        }).toList(),
                                  ),
                                const SizedBox(height: 8),
                                if (reminder != null)
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.alarm,
                                        size: isLandscape ? 12 : 14,
                                        color:
                                            reminder.isBefore(DateTime.now())
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
                                            'MMM dd, hh:mm a',
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
                                const SizedBox(height: 4),
                                Text(
                                  contentList.isNotEmpty
                                      ? (contentList[0]['text'] ?? '')
                                      : '',
                                  maxLines: isLandscape ? 4 : 8,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.bodyMedium?.copyWith(
                                    fontSize: isLandscape ? 12 : 14,
                                    fontFamily: fontFamily,
                                    color:
                                        Theme.of(
                                          context,
                                        ).textTheme.bodyMedium?.color,
                                  ),
                                ),
                                if (imagePaths.isNotEmpty)
                                  Container(
                                    height: 100,
                                    margin: const EdgeInsets.only(top: 8),
                                    child: ListView.builder(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: imagePaths.length,
                                      itemBuilder: (context, imgIndex) {
                                        final imgPath = imagePaths[imgIndex];
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            right: 8,
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            child: Image.file(
                                              File(imgPath),
                                              width: 100,
                                              height: 100,
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (
                                                    context,
                                                    error,
                                                    stackTrace,
                                                  ) => Icon(
                                                    Icons.broken_image,
                                                    size: 100,
                                                    color:
                                                        Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant,
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
                ),
      ),
    );
  }
}
