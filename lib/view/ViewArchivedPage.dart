import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:pencraftpro/FolderService.dart';

class ViewArchivedPage extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> contentJson;
  final List<String> imagePaths;
  final String? voiceNote;
  final List<String> labels;
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
    this.fontFamily,
    this.folderId,
    this.folderColor,
    this.folderName,
  });

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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'View Mode Only - Archived',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Theme.of(context).colorScheme.onPrimary,
            fontSize: 22,
          ),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title.isNotEmpty ? widget.title : 'Untitled',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            if (_folderName != null)
              Row(
                children: [
                  Icon(
                    Icons.folder,
                    size: 24,
                    color:
                        widget.folderColor != null
                            ? Color(widget.folderColor!)
                            : Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _folderName!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 14),
            if (widget.labels.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    widget.labels.map((label) {
                      return Chip(
                        label: Text(
                          label,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(
                            fontSize: 14,
                            color:
                                Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                          ),
                        ),
                        backgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                      );
                    }).toList(),
              ),
            const SizedBox(height: 20),
            ...widget.contentJson.map((item) {
              final checklistItems =
                  item['checklistItems'] as List<dynamic>? ?? [];
              if (checklistItems.isNotEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children:
                      checklistItems.map((task) {
                        final checked = task['checked'] ?? false;
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
                                  decoration:
                                      checked
                                          ? TextDecoration.lineThrough
                                          : null,
                                  fontSize: 16,
                                  fontFamily: widget.fontFamily ?? 'Roboto',
                                  color:
                                      Theme.of(
                                        context,
                                      ).textTheme.bodyMedium?.color,
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                );
              } else {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    item['text'] ?? '',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: (item['fontSize'] ?? 18).toDouble(),
                      fontWeight:
                          item['bold'] == true
                              ? FontWeight.bold
                              : FontWeight.normal,
                      fontStyle:
                          item['italic'] == true
                              ? FontStyle.italic
                              : FontStyle.normal,
                      decoration: TextDecoration.combine([
                        if (item['underline'] == true) TextDecoration.underline,
                        if (item['strikethrough'] == true)
                          TextDecoration.lineThrough,
                      ]),
                      fontFamily: widget.fontFamily ?? 'Roboto',
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                  ),
                );
              }
            }),
            const SizedBox(height: 20),
            if (widget.imagePaths.isNotEmpty)
              SizedBox(
                height: 240,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.imagePaths.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 10.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(widget.imagePaths[index]),
                          width: 220,
                          height: 240,
                          fit: BoxFit.cover,
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 20),
            if (widget.voiceNote != null)
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
                      value: _currentPosition.inMilliseconds.toDouble().clamp(
                        0,
                        _totalDuration.inMilliseconds.toDouble(),
                      ),
                      activeColor: Theme.of(context).colorScheme.primary,
                      inactiveColor: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.3),
                      onChanged: (value) async {
                        final position = Duration(milliseconds: value.toInt());
                        await _audioPlayer.seek(position);
                      },
                    ),
                  ),
                  Text(
                    '${_formatDuration(_currentPosition)} / ${_formatDuration(_totalDuration)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 14,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
