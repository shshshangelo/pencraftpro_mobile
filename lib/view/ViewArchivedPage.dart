import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:pencraftpro/FolderService.dart';

class ViewArchivedPage extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> contentJson;
  final List<String> imagePaths;
  final String? voiceNote;
  final List<String> labels;
  final DateTime? reminder;
  final String? fontFamily;
  final String? folderId;
  final int? folderColor;
  final String? folderName;

  const ViewArchivedPage({
    super.key,
    required this.title,
    required this.contentJson,
    required this.imagePaths,
    this.voiceNote,
    required this.labels,
    this.reminder,
    this.fontFamily,
    this.folderId,
    this.folderColor,
    this.folderName,
  });

  factory ViewArchivedPage.fromJson(Map<String, dynamic> json) {
    return ViewArchivedPage(
      title: json['title'] ?? 'Untitled',
      contentJson:
          (json['contentJson'] as List<dynamic>).cast<Map<String, dynamic>>(),
      imagePaths: (json['imagePaths'] as List<dynamic>).cast<String>(),
      voiceNote: json['voiceNote'],
      labels: (json['labels'] as List<dynamic>).cast<String>(),
      reminder:
          json['reminder'] != null ? DateTime.parse(json['reminder']) : null,
      fontFamily: json['fontFamily'],
      folderId: json['folderId'],
      folderColor: json['folderColor'],
      folderName: json['folderName'],
    );
  }

  @override
  State<ViewArchivedPage> createState() => _ViewArchivedPageState();
}

class _ViewArchivedPageState extends State<ViewArchivedPage> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  String? _folderName;

  @override
  void initState() {
    super.initState();
    _setupAudio();
    _loadFolderNameIfNeeded();
  }

  Future<void> _loadFolderNameIfNeeded() async {
    if (widget.folderName != null) {
      setState(() {
        _folderName = widget.folderName;
      });
    } else if (widget.folderId != null) {
      try {
        final folders = await FolderService.loadFolders();
        final matched = folders.firstWhere(
          (f) => f.id.toString() == widget.folderId,
          orElse: () => Folder(id: widget.folderId!, name: 'Unknown Folder'),
        );
        setState(() {
          _folderName = matched.name;
        });
      } catch (e) {
        debugPrint('Error loading folder name: $e');
      }
    }
  }

  Future<void> _setupAudio() async {
    if (widget.voiceNote != null) {
      await _audioPlayer.setFilePath(widget.voiceNote!);
    }

    _audioPlayer.positionStream.listen((position) {
      setState(() => _currentPosition = position);
    });

    _audioPlayer.durationStream.listen((duration) {
      setState(() => _totalDuration = duration ?? Duration.zero);
    });

    _audioPlayer.playerStateStream.listen((state) async {
      if (state.processingState == ProcessingState.completed) {
        await _audioPlayer.pause();
        await _audioPlayer.seek(Duration.zero);
        setState(() => _isPlaying = false);
      } else {
        setState(() => _isPlaying = state.playing);
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(duration.inHours)}:${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'View Mode Only - Archived',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Theme.of(context).colorScheme.onPrimary,
            fontSize: 20,
          ),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title.isNotEmpty ? widget.title : 'Untitled',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (widget.reminder != null)
              Row(
                children: [
                  Icon(
                    Icons.alarm,
                    size: 20,
                    color:
                        widget.reminder!.isBefore(now)
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('MMM dd, yyyy hh:mm a').format(widget.reminder!),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 14,
                      color:
                          widget.reminder!.isBefore(now)
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            if (_folderName != null)
              Row(
                children: [
                  Icon(
                    Icons.folder,
                    size: 20,
                    color:
                        widget.folderColor != null
                            ? Color(widget.folderColor!)
                            : Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _folderName!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            if (widget.labels.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children:
                    widget.labels.map((label) {
                      return Chip(
                        padding: EdgeInsets.zero,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.label_important,
                              size: 14,
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
                                fontSize: 12,
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ],
                        ),
                        backgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                      );
                    }).toList(),
              ),
            const SizedBox(height: 16),
            ...widget.contentJson.map((item) {
              final checklistItems =
                  item['checklistItems'] as List<dynamic>? ?? [];
              final hasChecklist = checklistItems.isNotEmpty;
              final hasText = (item['text'] ?? '').toString().trim().isNotEmpty;
              List<Widget> children = [];
              if (hasText) {
                children.add(
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Text(
                      item['text'] ?? '',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize:
                            (item['fontSize'] != null)
                                ? (item['fontSize'] as num).toDouble()
                                : 16,
                        fontFamily:
                            item['fontFamily'] ?? widget.fontFamily ?? 'Roboto',
                        fontWeight:
                            item['bold'] == true
                                ? FontWeight.bold
                                : FontWeight.normal,
                        fontStyle:
                            item['italic'] == true
                                ? FontStyle.italic
                                : FontStyle.normal,
                        decoration: TextDecoration.combine([
                          if (item['underline'] == true)
                            TextDecoration.underline,
                          if (item['strikethrough'] == true)
                            TextDecoration.lineThrough,
                        ]),
                        color: Theme.of(context).textTheme.bodyMedium?.color,
                      ),
                    ),
                  ),
                );
              }
              if (hasChecklist) {
                children.add(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children:
                        checklistItems
                            .where(
                              (task) => (task['text'] ?? '').trim().isNotEmpty,
                            )
                            .map((task) {
                              final checked = task['checked'] ?? false;
                              final fontSize = 16.0;
                              final isBold = false;
                              final isItalic = false;
                              final isUnderline = false;
                              final isStrikethrough = checked;
                              return Row(
                                children: [
                                  Checkbox(
                                    value: checked,
                                    onChanged: null,
                                    activeColor:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                  Expanded(
                                    child: Text(
                                      task['text'] ?? '',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium?.copyWith(
                                        fontSize: fontSize,
                                        fontWeight:
                                            isBold
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                        fontStyle:
                                            isItalic
                                                ? FontStyle.italic
                                                : FontStyle.normal,
                                        decoration:
                                            checked
                                                ? TextDecoration.lineThrough
                                                : null,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            })
                            .toList(),
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              );
            }),
            if (widget.voiceNote != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          _isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        onPressed: () async {
                          if (_isPlaying) {
                            await _audioPlayer.pause();
                          } else {
                            await _audioPlayer.play();
                          }
                        },
                      ),
                      Expanded(
                        child: Slider(
                          min: 0,
                          max: _totalDuration.inMilliseconds.toDouble(),
                          value: _currentPosition.inMilliseconds
                              .toDouble()
                              .clamp(
                                0,
                                _totalDuration.inMilliseconds.toDouble(),
                              ),
                          activeColor: Theme.of(context).colorScheme.primary,
                          inactiveColor: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.3),
                          onChanged: (value) async {
                            final position = Duration(
                              milliseconds: value.toInt(),
                            );
                            await _audioPlayer.seek(position);
                          },
                        ),
                      ),
                      Text(
                        '${_formatDuration(_currentPosition)} / ${_formatDuration(_totalDuration)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            if (widget.imagePaths.isNotEmpty)
              Column(
                children:
                    widget.imagePaths.map((path) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Stack(
                          children: [
                            GestureDetector(
                              onTap: () {
                                _showImageViewer(
                                  context,
                                  widget.imagePaths,
                                  widget.imagePaths.indexOf(path),
                                );
                              },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(
                                  File(path),
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder:
                                      (context, error, stackTrace) => Icon(
                                        Icons.broken_image,
                                        size: 40,
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  void _showImageViewer(
    BuildContext context,
    List<String> images,
    int initialIndex,
  ) {
    showDialog(
      context: context,
      builder:
          (_) => Dialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            insetPadding: EdgeInsets.zero,
            child: PageView.builder(
              controller: PageController(initialPage: initialIndex),
              itemCount: images.length,
              itemBuilder:
                  (context, index) => InteractiveViewer(
                    child: Image.file(File(images[index]), fit: BoxFit.contain),
                  ),
            ),
          ),
    );
  }
}
