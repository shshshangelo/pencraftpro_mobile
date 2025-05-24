// ignore_for_file: unused_import, unused_element, body_might_complete_normally_catch_error, unused_local_variable, use_build_context_synchronously, deprecated_member_use, library_private_types_in_public_api, unused_field
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' as intl;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:pdf/pdf.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'dart:io';
import 'package:uuid/uuid.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:just_audio/just_audio.dart';
import 'package:pencraftpro/FolderService.dart';
import 'package:pencraftpro/LabelService.dart';

import 'FullScreenImageViewer.dart';
import '../notes/FullScreenGallery.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:typed_data';

class AddNotePage extends StatefulWidget {
  final String? noteId;
  final String? title;
  final List<Map<String, dynamic>>? contentJson;
  final bool isPinned;
  final DateTime? reminder;
  final List<String>? imagePaths;
  final String? voiceNote;
  final List<String>? labels;
  final bool isArchived;
  final String? fontFamily;
  final String? folderId;
  final int? folderColor;
  final List<String>? collaboratorEmails;

  final Function({
    String? id,
    required String title,
    required List<Map<String, dynamic>> contentJson,
    required bool isPinned,
    required bool isDeleted,
    DateTime? reminder,
    List<String>? imagePaths,
    String? voiceNote,
    List<String>? labels,
    bool isArchived,
    String? fontFamily,
    String? folderId,
    int? folderColor,
    List<String>? collaboratorEmails,
  })
  onSave;

  final Function(String id) onDelete;

  const AddNotePage({
    super.key,
    this.noteId,
    this.title,
    this.contentJson,
    this.isPinned = false,
    this.reminder,
    this.imagePaths,
    this.voiceNote,
    this.labels,
    this.isArchived = false,
    this.fontFamily,
    this.folderId,
    this.folderColor,
    this.collaboratorEmails,
    required this.onSave,
    required this.onDelete,
  });

  @override
  _AddNotePageState createState() => _AddNotePageState();
}

int _voiceNoteCounter = 1;

class _AddNotePageState extends State<AddNotePage> {
  List<String> _collaboratorEmails = [];
  final TextEditingController _collaboratorEmailController =
      TextEditingController();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  bool _isPinned = false;
  double _contentFontSize = 16.0;
  DateTime? _reminder;
  List<String> _imagePaths = [];
  String? _voiceNotePath;
  List<String> _labels = [];
  bool _isArchived = false;
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final int _notificationIdCounter = 0;
  FontWeight _selectedFontWeight = FontWeight.normal;
  bool _isItalic = false;
  bool _isUnderline = false;
  bool _isStrikethrough = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _isPlaying = false;
  String? _selectedFolderId;
  String? _selectedFolderName;
  // Add new list to track element order
  List<Map<String, dynamic>> _elementOrder = [];
  // Add map to store checklist controllers
  final Map<int, TextEditingController> _checklistControllers = {};

  final List<Color> _folderColors = [
    Colors.red,
    Colors.green,
    Colors.blue,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.cyan,
    Colors.amber,
    Colors.indigo,
    Colors.pink,
    Colors.lightBlue.shade100,
    Colors.pink.shade100,
    Colors.green.shade100,
    Colors.amber.shade100,
    Colors.purple.shade100,
    Colors.cyan.shade100,
    Colors.orange.shade100,
  ];

  final Map<String, Color> _folderColorMap = {};
  int _colorIndex = 0;

  List<Map<String, String>> _history = [];
  int _historyIndex = -1;
  List<Map<String, dynamic>> _checklistItems = [];

  // Track the initial state of the note for change detection
  Map<String, dynamic>? _initialNoteState;

  @override
  void initState() {
    super.initState();
    _initializeNotifications();

    _titleController.text = widget.title ?? '';
    _isPinned = widget.isPinned;
    _reminder = widget.reminder;
    _labels = widget.labels?.toList() ?? [];
    _isArchived = widget.isArchived;

    // Initialize element order with existing elements in the correct order
    if (widget.contentJson != null) {
      for (var item in widget.contentJson!) {
        if (item['checklistItems'] != null) {
          final checklistItems = List<Map<String, dynamic>>.from(
            item['checklistItems'],
          );
          for (var i = 0; i < checklistItems.length; i++) {
            _elementOrder.add({'type': 'checklist', 'index': i});
          }
        }
      }
    }

    _initializeMediaFiles().then((_) {
      if (mounted) {
        setState(() {
          _initialNoteState = _getCurrentNoteState();
        });
      }
    });

    if (widget.noteId != null && widget.folderId != null) {
      _loadFolderName(widget.folderId!);
      _selectedFolderId = widget.folderId;
      if (widget.folderColor != null) {
        _folderColorMap[_selectedFolderId!] = Color(widget.folderColor!);
      }
    }

    if (widget.contentJson != null) {
      final textBuffer = StringBuffer();
      bool bold = false;
      bool italic = false;
      bool underline = false;
      bool strikethrough = false;
      String fontFamily = 'Roboto';

      for (final item in widget.contentJson!) {
        textBuffer.write(item['text'] ?? '');
        bold = item['bold'] == true;
        italic = item['italic'] == true;
        underline = item['underline'] == true;
        strikethrough = item['strikethrough'] == true;
        fontFamily = item['fontFamily'] ?? 'Roboto';
        _contentFontSize = (item['fontSize'] as num?)?.toDouble() ?? 16.0;

        if (item['checklistItems'] != null) {
          _checklistItems = List<Map<String, dynamic>>.from(
            item['checklistItems'],
          );
        }
      }

      _contentController.text = textBuffer.toString();

      setState(() {
        _selectedFontWeight = bold ? FontWeight.bold : FontWeight.normal;
        _isItalic = italic;
        _isUnderline = underline;
        _isStrikethrough = strikethrough;
        _selectedFontFamily = fontFamily;
      });
    }

    _audioPlayer.positionStream.listen((position) {
      setState(() {
        _currentPosition = position;
      });
    });
    _audioPlayer.durationStream.listen((duration) {
      setState(() {
        _totalDuration = duration ?? Duration.zero;
      });
    });
    _audioPlayer.playerStateStream.listen((state) {
      setState(() {
        _isPlaying = state.playing;
      });
    });

    if (_voiceNotePath != null) {
      _audioPlayer.setFilePath(_voiceNotePath!).catchError((e) {
        debugPrint('Error setting audio file path: $e');
      });
    }

    _saveToHistory();
    _titleController.addListener(_handleTextChange);
    _contentController.addListener(_handleTextChange);

    _collaboratorEmails = widget.collaboratorEmails?.toList() ?? [];
    if (widget.noteId != null) {
      _fetchCollaboratorsFromFirestore();
      _setupNoteListener();
    }
  }

  Future<void> _initializeMediaFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();

      // Initialize images from Firestore
      if (widget.noteId != null) {
        final noteDoc =
            await FirebaseFirestore.instance
                .collection('notes')
                .doc(widget.noteId)
                .get();

        if (noteDoc.exists) {
          final data = noteDoc.data();
          if (data != null) {
            // Handle base64 images
            List<String> newImagePaths = [];
            List<String> base64Images = List<String>.from(
              data['base64Images'] ?? [],
            );

            for (var i = 0; i < base64Images.length; i++) {
              try {
                final String base64Image = base64Images[i];
                if (base64Image.isNotEmpty) {
                  final String fileName = 'image_${widget.noteId}_$i.jpg';
                  final String filePath = '${tempDir.path}/$fileName';

                  // Check if file already exists
                  final File imageFile = File(filePath);
                  // Always decode and write the image file (overwrite if exists)
                  try {
                    final imageBytes = base64Decode(base64Image);
                    await imageFile.writeAsBytes(imageBytes);
                    debugPrint('Successfully saved image: $fileName');
                  } catch (e) {
                    debugPrint('Error decoding base64 image: $e');
                    continue;
                  }
                  newImagePaths.add(filePath);
                }
              } catch (e) {
                debugPrint('Error processing image $i: $e');
              }
            }

            // Handle base64 voice note
            String? newVoiceNotePath;
            if (data['base64VoiceNote'] != null) {
              try {
                final String base64VoiceNote = data['base64VoiceNote'];
                final String fileName = 'voice_${widget.noteId}.m4a';
                final String filePath = '${tempDir.path}/$fileName';

                final File voiceFile = File(filePath);
                if (!await voiceFile.exists()) {
                  await voiceFile.writeAsBytes(base64Decode(base64VoiceNote));
                }
                newVoiceNotePath = filePath;
              } catch (e) {
                debugPrint('Error decoding base64 voice note: $e');
              }
            }

            if (data['elementOrder'] != null) {
              _elementOrder = List<Map<String, dynamic>>.from(
                data['elementOrder'],
              );
              // Map 'data' to 'path' for images if needed
              int imageIdx = 0;
              for (var element in _elementOrder) {
                if (element['type'] == 'image' &&
                    (element['path'] == null ||
                        element['path'].toString().isEmpty)) {
                  if (imageIdx < newImagePaths.length) {
                    element['path'] = newImagePaths[imageIdx];
                    imageIdx++;
                  }
                }
              }
            } else {
              // No elementOrder present; leave _elementOrder empty and log a warning
              debugPrint(
                'Warning: No elementOrder found for this note. Element order will be empty.',
              );
            }

            setState(() {
              _imagePaths = newImagePaths;
              _voiceNotePath = newVoiceNotePath;
            });
          }
        }
      } else {
        // Initialize from widget parameters for new notes
        setState(() {
          _imagePaths = widget.imagePaths?.toList() ?? [];
          _voiceNotePath = widget.voiceNote;

          // Clear and rebuild element order
          _elementOrder.clear();

          // Add checklist items (at the end)
          for (var i = 0; i < _checklistItems.length; i++) {
            _elementOrder.add({'type': 'checklist', 'index': i});
          }

          // Add voice note if exists (after checklist items)
          if (_voiceNotePath != null) {
            _elementOrder.add({'type': 'voice', 'path': _voiceNotePath});
          }

          // Add images (after voice note)
          for (var path in _imagePaths) {
            _elementOrder.add({'type': 'image', 'path': path});
          }
        });
      }
    } catch (e) {
      debugPrint('❌ Error initializing media files: $e');
    }
  }

  StreamSubscription? _noteListener;

  void _setupNoteListener() {
    if (widget.noteId == null) return;

    if (_noteListener != null) {
      _noteListener!.cancel();
    }

    _noteListener = FirebaseFirestore.instance
        .collection('notes')
        .doc(widget.noteId)
        .snapshots()
        .listen((snapshot) async {
          if (!snapshot.exists) return;

          final data = snapshot.data()!;
          final currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser == null) return;

          // Get modifier information for display
          String modifierEmail = data['lastModifiedByEmail'] ?? 'Someone';
          final lastModifiedBy = data['lastModifiedBy'];
          final lastModifiedTime =
              data['updatedAt'] != null
                  ? DateTime.parse(data['updatedAt']).toLocal()
                  : DateTime.now();
          bool wasModifiedByCurrentUser = lastModifiedBy == currentUser.uid;

          // Only show notification if modified by someone else
          if (!wasModifiedByCurrentUser) {
            // Show toast of the update
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'This note was updated by $modifierEmail at ${DateFormat('hh:mm a').format(lastModifiedTime)}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  duration: const Duration(seconds: 3),
                  behavior: SnackBarBehavior.floating,
                  margin: const EdgeInsets.all(8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              );
            }
          }

          // Always update the UI with the latest data (improved real-time sync)
          try {
            // Get the app's temporary directory
            final tempDir = await getTemporaryDirectory();

            // Handle base64 images
            List<String> newImagePaths = [];
            List<String> base64Images = List<String>.from(
              data['base64Images'] ?? [],
            );
            for (var i = 0; i < base64Images.length; i++) {
              try {
                final String base64Image = base64Images[i];
                if (base64Image.isEmpty) continue;

                final String fileName = 'image_${widget.noteId}_$i.jpg';
                final String filePath = '${tempDir.path}/$fileName';

                final File imageFile = File(filePath);
                try {
                  await imageFile.writeAsBytes(base64Decode(base64Image));
                  newImagePaths.add(filePath);
                } catch (e) {
                  debugPrint('Error writing image file: $e');
                }
              } catch (e) {
                debugPrint('Error decoding base64 image: $e');
              }
            }

            // Handle base64 voice note
            String? newVoiceNotePath;
            if (data['base64VoiceNote'] != null) {
              try {
                final String base64VoiceNote = data['base64VoiceNote'];
                final String fileName = 'voice_${widget.noteId}.m4a';
                final String filePath = '${tempDir.path}/$fileName';

                final File voiceFile = File(filePath);
                await voiceFile.writeAsBytes(base64Decode(base64VoiceNote));
                newVoiceNotePath = filePath;
              } catch (e) {
                debugPrint('Error decoding base64 voice note: $e');
              }
            }

            final elementOrder = data['elementOrder'] ?? [];

            // Always update the collaboratorEmails list to ensure it's in sync
            // This ensures all users have the same collaborator information
            final updatedCollaboratorEmails = List<String>.from(
              data['collaboratorEmails'] ?? [],
            );

            // If changes were made by others, update the UI
            if (data['lastModifiedBy'] != currentUser.uid ||
                !_areCollaboratorListsEqual(
                  _collaboratorEmails,
                  updatedCollaboratorEmails,
                )) {
              setState(() {
                _titleController.text = data['title'] ?? '';
                if (data['contentJson'] != null &&
                    data['contentJson'].isNotEmpty) {
                  final content = data['contentJson'][0];
                  _contentController.text = content['text'] ?? '';
                  _selectedFontWeight =
                      content['bold'] == true
                          ? FontWeight.bold
                          : FontWeight.normal;
                  _isItalic = content['italic'] == true;
                  _isUnderline = content['underline'] == true;
                  _isStrikethrough = content['strikethrough'] == true;
                  _selectedFontFamily = content['fontFamily'] ?? 'Roboto';
                  _contentFontSize =
                      (content['fontSize'] as num?)?.toDouble() ?? 16.0;
                  if (content['checklistItems'] != null) {
                    _checklistItems = List<Map<String, dynamic>>.from(
                      content['checklistItems'],
                    );
                  }
                }
                _isPinned = data['isPinned'] ?? false;
                _reminder =
                    data['reminder'] != null
                        ? DateTime.parse(data['reminder'])
                        : null;
                _imagePaths = newImagePaths;
                _voiceNotePath = newVoiceNotePath;
                _labels = List<String>.from(data['labels'] ?? []);
                _isArchived = data['isArchived'] ?? false;
                _selectedFolderId = data['folderId'];
                if (data['folderColor'] != null) {
                  _folderColorMap[_selectedFolderId!] = Color(
                    data['folderColor'],
                  );
                }

                // Always update collaborator list from server
                _collaboratorEmails = updatedCollaboratorEmails;
                _elementOrder = List<Map<String, dynamic>>.from(elementOrder);

                // Update audio player if voice note changed
                if (newVoiceNotePath != null) {
                  _audioPlayer.setFilePath(newVoiceNotePath).catchError((e) {
                    debugPrint('Error setting audio file path: $e');
                  });
                }
              });
            }

            // If our email is no longer in collaboratorEmails, we've been removed
            final userEmail = currentUser.email?.toLowerCase().trim();
            final isStillCollaborator =
                data['collaboratorEmails']?.any(
                  (email) => email.toString().toLowerCase().trim() == userEmail,
                ) ??
                false;
            final isOwner = data['owner'] == currentUser.uid;

            if (!isStillCollaborator && !isOwner) {
              // We've been removed from the collaboration, exit the note
              if (mounted) {
                // Remove note from local storage
                try {
                  final prefs = await SharedPreferences.getInstance();
                  final String? notesString = prefs.getString('notes');
                  if (notesString != null) {
                    List<dynamic> notesList = jsonDecode(notesString);
                    notesList =
                        notesList
                            .where((note) => note['id'] != widget.noteId)
                            .toList();
                    await prefs.setString('notes', jsonEncode(notesList));
                  }
                } catch (e) {
                  debugPrint('Error removing note from local storage: $e');
                }

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'You are no longer a collaborator on this note',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onError,
                      ),
                    ),
                    backgroundColor: Theme.of(context).colorScheme.error,
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.all(8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                );

                // Return to previous screen
                Navigator.pop(context, {
                  'id': widget.noteId,
                  'isNew': false,
                  'delete': false,
                  'updated': true,
                  'leftCollaboration': true,
                });
              }
            }
          } catch (e) {
            debugPrint('Error updating note from snapshot: $e');
          }
        });
  }

  // Helper method to compare collaborator lists case-insensitively
  bool _areCollaboratorListsEqual(List<String> list1, List<String> list2) {
    if (list1.length != list2.length) return false;

    final normalizedList1 =
        list1.map((e) => e.toLowerCase().trim()).toList()..sort();
    final normalizedList2 =
        list2.map((e) => e.toLowerCase().trim()).toList()..sort();

    for (var i = 0; i < normalizedList1.length; i++) {
      if (normalizedList1[i] != normalizedList2[i]) return false;
    }

    return true;
  }

  Future<void> _fetchCollaboratorsFromFirestore() async {
    try {
      final noteRef = FirebaseFirestore.instance
          .collection('notes')
          .doc(widget.noteId);
      final snapshot = await noteRef.get();
      final data = snapshot.data();

      if (data != null) {
        final List<dynamic> emails = data['collaboratorEmails'] ?? [];
        setState(() {
          _collaboratorEmails = emails.cast<String>();
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch collaborators: $e');
    }
  }

  Future<void> _loadFolderName(String folderId) async {
    try {
      final folders = await FolderService.loadFolders();
      Folder? matchedFolder;
      try {
        matchedFolder = folders.firstWhere((f) => f.id.toString() == folderId);
      } catch (e) {
        matchedFolder = null;
      }

      if (matchedFolder == null) {
        // If folder doesn't exist, clear folder information
        setState(() {
          _selectedFolderId = null;
          _selectedFolderName = null;
        });
        // Save the note without folder information
        await _saveNoteToFirestore();
      } else {
        setState(() {
          _selectedFolderId = matchedFolder!.id.toString();
          _selectedFolderName = matchedFolder.name;
        });
      }
    } catch (e) {
      debugPrint('Failed to load folder: $e');
      // Clear folder information on error
      setState(() {
        _selectedFolderId = null;
        _selectedFolderName = null;
      });
    }
  }

  @override
  void dispose() {
    // Dispose all checklist controllers
    for (var controller in _checklistControllers.values) {
      controller.dispose();
    }
    _checklistControllers.clear();
    _noteListener?.cancel();
    _audioPlayer.stop();
    _audioPlayer.dispose();
    _titleController.dispose();
    _contentController.dispose();
    _collaboratorEmailController.dispose();
    super.dispose();
  }

  void _handleTextChange() {
    if (_history.isEmpty ||
        _history[_historyIndex]['title'] != _titleController.text ||
        _history[_historyIndex]['content'] != _contentController.text) {
      _saveToHistory();
    }
  }

  void _saveToHistory() {
    if (_historyIndex < _history.length - 1) {
      _history = _history.sublist(0, _historyIndex + 1);
    }
    _history.add({
      'title': _titleController.text,
      'content': _contentController.text,
    });
    _historyIndex++;
    if (_history.length > 20) {
      _history.removeAt(0);
      _historyIndex--;
    }
  }

  void _undo() {
    if (_historyIndex > 0) {
      setState(() {
        _historyIndex--;
        _titleController.text = _history[_historyIndex]['title']!;
        _contentController.text = _history[_historyIndex]['content']!;
      });
    }
  }

  void _redo() {
    if (_historyIndex < _history.length - 1) {
      setState(() {
        _historyIndex++;
        _titleController.text = _history[_historyIndex]['title']!;
        _contentController.text = _history[_historyIndex]['content']!;
      });
    }
  }

  Future<void> _saveNoteToFirestore() async {
    try {
      final noteId = widget.noteId ?? const Uuid().v4();
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('No authenticated user found.');
      }

      // Check if user has permission to edit
      if (widget.noteId != null) {
        final noteRef = FirebaseFirestore.instance
            .collection('notes')
            .doc(widget.noteId);
        final noteDoc = await noteRef.get();
        if (noteDoc.exists) {
          final noteData = noteDoc.data();
          final owner = noteData?['owner'] as String?;
          final collaborators = List<String>.from(
            noteData?['collaborators'] ?? [],
          );

          if (owner != currentUser.uid &&
              !collaborators.contains(currentUser.uid)) {
            throw Exception('You do not have permission to edit this note.');
          }
        }
      }

      // Convert images to base64
      List<String> base64Images = [];
      for (String imagePath in _imagePaths) {
        try {
          File imageFile = File(imagePath);
          if (await imageFile.exists()) {
            List<int> imageBytes = await imageFile.readAsBytes();
            String base64Image = base64Encode(imageBytes);
            base64Images.add(base64Image);
          }
        } catch (e) {
          debugPrint('Error converting image to base64: $e');
        }
      }

      // Convert voice note to base64
      String? base64VoiceNote;
      if (_voiceNotePath != null) {
        try {
          File voiceFile = File(_voiceNotePath!);
          if (await voiceFile.exists()) {
            List<int> voiceBytes = await voiceFile.readAsBytes();
            base64VoiceNote = base64Encode(voiceBytes);
          }
        } catch (e) {
          debugPrint('Error converting voice note to base64: $e');
        }
      }

      // Save to local storage first
      final prefs = await SharedPreferences.getInstance();
      final String? notesString = prefs.getString('notes');
      final List<dynamic> notes =
          notesString != null ? jsonDecode(notesString) : [];

      // Get existing note data if it exists
      final existingNote = notes.firstWhere(
        (note) => note['id'] == noteId,
        orElse: () => null,
      );

      // Preserve existing collaborators if this is an update
      List<String> existingCollaborators = [];
      if (existingNote != null) {
        existingCollaborators = List<String>.from(
          existingNote['collaborators'] ?? [],
        );
      }

      // Filter out empty checklist items
      final filteredChecklistItems =
          _checklistItems
              .where(
                (item) => (item['text'] as String?)?.trim().isNotEmpty ?? false,
              )
              .toList();

      // Careful handling of element order to preserve media files during collaboration
      List<Map<String, dynamic>> elementOrder = [];

      // First get the existing element order from Firestore if this is a collaborative edit
      if (widget.noteId != null) {
        try {
          final noteRef = FirebaseFirestore.instance
              .collection('notes')
              .doc(widget.noteId);
          final noteDoc = await noteRef.get();

          if (noteDoc.exists) {
            // Get existing element order from Firestore
            final existingData = noteDoc.data();
            if (existingData != null && existingData['elementOrder'] != null) {
              final existingOrder = List<Map<String, dynamic>>.from(
                existingData['elementOrder'],
              );

              // Check if we need to preserve voice notes and images
              final bool hasExistingVoice = existingOrder.any(
                (element) => element['type'] == 'voice',
              );
              final List<Map<String, dynamic>> existingImages =
                  existingOrder
                      .where((element) => element['type'] == 'image')
                      .toList();

              print(
                'Existing order has voice: $hasExistingVoice, images: ${existingImages.length}',
              );

              // If local data matches remote data, use our current _elementOrder
              if (_elementOrder.isNotEmpty &&
                  (_elementOrder.length >= existingOrder.length ||
                      (_voiceNotePath != null && hasExistingVoice) ||
                      (_imagePaths.length >= existingImages.length))) {
                print(
                  'Using local _elementOrder: ${_elementOrder.length} elements',
                );
                elementOrder = List<Map<String, dynamic>>.from(_elementOrder);

                // Update data references for serialization
                for (var i = 0; i < elementOrder.length; i++) {
                  final element = elementOrder[i];
                  // Convert local paths to base64 for media elements
                  if (element['type'] == 'voice' &&
                      element['path'] != null &&
                      base64VoiceNote != null) {
                    element['data'] = base64VoiceNote;
                    element.remove('path');
                  } else if (element['type'] == 'image' &&
                      element['path'] != null) {
                    final imagePath = element['path'];
                    final imageIndex = _imagePaths.indexOf(imagePath);
                    if (imageIndex >= 0 && imageIndex < base64Images.length) {
                      element['data'] = base64Images[imageIndex];
                      element.remove('path');
                    }
                  }
                }
              } else {
                // Preserve existing order but update with our local changes
                elementOrder = List<Map<String, dynamic>>.from(existingOrder);

                // Add new checklist items or update existing ones
                int checklistIndex = 0;
                final existingChecklist =
                    elementOrder
                        .where((e) => e['type'] == 'checklist')
                        .toList();

                // Remove existing checklist items from element order
                elementOrder.removeWhere((e) => e['type'] == 'checklist');

                // Add updated checklist items
                for (var i = 0; i < filteredChecklistItems.length; i++) {
                  elementOrder.add({'type': 'checklist', 'index': i});
                  checklistIndex++;
                }

                print(
                  'Preserved element order with ${elementOrder.length} elements',
                );
              }

              // Make sure we preserve voice and images if they exist
              bool hasVoiceInOrder = elementOrder.any(
                (element) => element['type'] == 'voice',
              );
              if (!hasVoiceInOrder && base64VoiceNote != null) {
                elementOrder.add({'type': 'voice', 'data': base64VoiceNote});
              }

              // Handle images more carefully
              final imageElementsCount =
                  elementOrder.where((e) => e['type'] == 'image').length;
              if (imageElementsCount < base64Images.length) {
                // Add missing images
                for (var i = imageElementsCount; i < base64Images.length; i++) {
                  elementOrder.add({'type': 'image', 'data': base64Images[i]});
                }
              }

              // Finish processing the element order here instead of returning
              print(
                'Finished processing element order for Firebase: ${elementOrder.length} elements',
              );
            }
          }
        } catch (e) {
          debugPrint('Error getting existing element order: $e');
          // Continue with fallback approach
        }
      }

      // Fallback: Create a new element order from scratch
      print('Creating new element order from scratch');

      // Add checklist items first
      for (var i = 0; i < filteredChecklistItems.length; i++) {
        elementOrder.add({'type': 'checklist', 'index': i});
      }

      // Add voice note if exists
      if (base64VoiceNote != null) {
        elementOrder.add({'type': 'voice', 'data': base64VoiceNote});
      }

      // Add images
      for (var i = 0; i < base64Images.length; i++) {
        elementOrder.add({'type': 'image', 'data': base64Images[i]});
      }

      // Add timestamp and modifier information for real-time collaboration
      final now = DateTime.now();
      final timestamp = now.toIso8601String();

      // Create base note data without FieldValue operations (for local storage)
      final localNoteData = {
        'id': noteId,
        'title': _titleController.text.trim(),
        'contentJson': [
          {
            'text': _contentController.text,
            'bold': _selectedFontWeight == FontWeight.bold,
            'italic': _isItalic,
            'underline': _isUnderline,
            'strikethrough': _isStrikethrough,
            'fontFamily': _selectedFontFamily,
            'fontSize': _contentFontSize,
            'checklistItems': filteredChecklistItems,
          },
        ],
        'isPinned': _isPinned,
        'isDeleted': false,
        'reminder': _reminder?.toIso8601String(),
        'base64Images': base64Images,
        'base64VoiceNote': base64VoiceNote,
        'labels': _labels,
        'isArchived': _isArchived,
        'fontFamily': _selectedFontFamily,
        'folderId': _selectedFolderId,
        'folderColor':
            _selectedFolderId != null
                ? _folderColorMap[_selectedFolderId]?.value
                : null,
        'owner':
            widget.noteId == null
                ? currentUser.uid
                : existingNote?['owner'] ?? currentUser.uid,
        'ownerEmail': currentUser.email ?? 'no-email',
        'collaborators':
            existingNote == null ? [currentUser.uid] : existingCollaborators,
        'collaboratorEmails': _collaboratorEmails,
        'createdAt': existingNote?['createdAt'] ?? timestamp,
        'updatedAt': timestamp,
        'lastModifiedBy': currentUser.uid,
        'lastModifiedByEmail': currentUser.email ?? 'Unknown',
        'lastModifiedAt': timestamp,
        'elementOrder': elementOrder,
        // Don't include editHistory for local storage since we're not using FieldValue for it
        'editHistory': existingNote?['editHistory'] ?? [],
      };

      // Add the current edit to the local history
      localNoteData['editHistory'].add({
        'userId': currentUser.uid,
        'userEmail': currentUser.email,
        'timestamp': timestamp,
        'action': 'edit',
      });

      // Update local storage
      final existingIndex = notes.indexWhere((note) => note['id'] == noteId);
      if (existingIndex != -1) {
        notes[existingIndex] = localNoteData;
      } else {
        notes.add(localNoteData);
      }
      await prefs.setString('notes', jsonEncode(notes));

      // Create a separate object for Firestore with FieldValue operations
      final firestoreNoteData = {
        'id': noteId,
        'title': _titleController.text.trim(),
        'contentJson': [
          {
            'text': _contentController.text,
            'bold': _selectedFontWeight == FontWeight.bold,
            'italic': _isItalic,
            'underline': _isUnderline,
            'strikethrough': _isStrikethrough,
            'fontFamily': _selectedFontFamily,
            'fontSize': _contentFontSize,
            'checklistItems': filteredChecklistItems,
          },
        ],
        'isPinned': _isPinned,
        'isDeleted': false,
        'reminder': _reminder?.toIso8601String(),
        'base64Images': base64Images,
        'base64VoiceNote': base64VoiceNote,
        'labels': _labels,
        'isArchived': _isArchived,
        'fontFamily': _selectedFontFamily,
        'folderId': _selectedFolderId,
        'folderColor':
            _selectedFolderId != null
                ? _folderColorMap[_selectedFolderId]?.value
                : null,
        'owner':
            widget.noteId == null
                ? currentUser.uid
                : existingNote?['owner'] ?? currentUser.uid,
        'ownerEmail': currentUser.email ?? 'no-email',
        'collaborators':
            existingNote == null ? [currentUser.uid] : existingCollaborators,
        'collaboratorEmails': _collaboratorEmails,
        'createdAt': existingNote?['createdAt'] ?? timestamp,
        'updatedAt': timestamp,
        'lastModifiedBy': currentUser.uid,
        'lastModifiedByEmail': currentUser.email ?? 'Unknown',
        'lastModifiedAt': timestamp,
        'elementOrder': elementOrder,
        // Use FieldValue for Firestore
        'editHistory': FieldValue.arrayUnion([
          {
            'userId': currentUser.uid,
            'userEmail': currentUser.email,
            'timestamp': timestamp,
            'action': 'edit',
          },
        ]),
      };

      // Try to save to Firestore (will be queued if offline)
      final noteRef = FirebaseFirestore.instance
          .collection('notes')
          .doc(noteId);
      await noteRef.set(firestoreNoteData, SetOptions(merge: true));

      debugPrint('Note saved locally and queued for Firestore sync: $noteId');

      widget.onSave(
        id: noteId,
        title: localNoteData['title'] as String,
        contentJson:
            (localNoteData['contentJson'] as List).cast<Map<String, dynamic>>(),
        isPinned: _isPinned,
        isDeleted: false,
        reminder: _reminder,
        imagePaths: _imagePaths,
        voiceNote: _voiceNotePath,
        labels: _labels,
        isArchived: _isArchived,
        fontFamily: _selectedFontFamily,
        folderId: _selectedFolderId,
        folderColor: localNoteData['folderColor'] as int?,
        collaboratorEmails: _collaboratorEmails,
      );
    } catch (e) {
      debugPrint('⚠️ Note saved locally but Firestore sync pending: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error: ${e.toString()}.',
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

  void _saveNote() {
    // Check if the note is empty
    final isEmpty =
        _titleController.text.trim().isEmpty &&
        _contentController.text.trim().isEmpty &&
        _imagePaths.isEmpty &&
        _voiceNotePath == null &&
        _checklistItems.every(
          (item) =>
              (item['text'] as String?)?.trim().isEmpty ??
              true && item['checked'] == false,
        );

    if (isEmpty) {
      Navigator.pop(context, {
        'id': widget.noteId,
        'isNew': false,
        'delete': false,
        'updated': false,
      });
      return;
    }

    _saveNoteToFirestore();

    FocusScope.of(context).unfocus();
    Navigator.pop(context, {
      'id': widget.noteId,
      'isNew': widget.noteId == null,
      'delete': false,
      'updated': widget.noteId != null,
    });
  }

  final List<String> _fontFamilies = [
    'Roboto',
    'Times New Roman',
    'Courier New',
    'Cursive',
    'Space Mono',
    'Dancing Script',
    'Pacifico',
    'Great Vibes',
    'Shadows Into Light',
    'Gloria Hallelujah',
    'Indie Flower',
    'Satisfy',
    'Homemade Apple',
    'Reenie Beanie',
    'Handlee',
  ];
  String _selectedFontFamily = 'Roboto';

  void _showFontSelectionOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        String tempSelectedFont = _selectedFontFamily;
        return StatefulBuilder(
          builder:
              (ctx, setSheetState) => SizedBox(
                height: 300,
                child: ListView.separated(
                  itemCount: _fontFamilies.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final family = _fontFamilies[index];
                    final selected = tempSelectedFont == family;
                    return ListTile(
                      title: Text(
                        family,
                        style: TextStyle(fontFamily: family, fontSize: 18),
                      ),
                      trailing:
                          selected
                              ? Icon(
                                Icons.check,
                                color: Theme.of(context).colorScheme.primary,
                              )
                              : null,
                      onTap: () {
                        setState(() {
                          _selectedFontFamily = family;
                        });
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
        );
      },
    );
  }

  void _addChecklistItem() {
    setState(() {
      final index = _checklistItems.length;
      _checklistItems.add({'text': '', 'checked': false});
      _checklistControllers[index] = TextEditingController();
      // Add to element order at the end
      _elementOrder.add({'type': 'checklist', 'index': index});
    });
  }

  Future<String?> _showCreateFolderDialog() async {
    final controller = TextEditingController(text: "New Folder");

    return showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              'Create New Folder',
              style: TextStyle(fontSize: 18),
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Folder Name',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(fontSize: 14)),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context, controller.text);
                },
                child: const Text('Create', style: TextStyle(fontSize: 14)),
              ),
            ],
          ),
    );
  }

  Future<void> _moveNoteToFolder(String folderId) async {
    setState(() {
      _selectedFolderId = folderId;
    });

    final folders = await FolderService.loadFolders();
    final matchedFolder = folders.firstWhere(
      (f) => f.id.toString() == folderId,
      orElse: () => Folder(id: folderId, name: 'Unknown Folder'),
    );

    setState(() {
      _selectedFolderName = matchedFolder.name;
    });

    await _saveNoteToFirestore();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Note moved to folder: ${matchedFolder.name}.',
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
  }

  Future<void> _setReminder() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            textTheme: const TextTheme(
              titleMedium: TextStyle(fontSize: 16),
              bodyMedium: TextStyle(fontSize: 14),
              bodySmall: TextStyle(fontSize: 12),
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              textTheme: const TextTheme(
                titleMedium: TextStyle(fontSize: 16),
                bodyMedium: TextStyle(fontSize: 14),
                bodySmall: TextStyle(fontSize: 12),
              ),
              timePickerTheme: const TimePickerThemeData(
                hourMinuteTextStyle: TextStyle(fontSize: 30),
                dayPeriodTextStyle: TextStyle(fontSize: 14),
                helpTextStyle: TextStyle(fontSize: 14),
              ),
            ),
            child: child!,
          );
        },
      );

      if (pickedTime != null) {
        final reminderDateTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
        setState(() {
          _reminder = reminderDateTime;
        });
        await _scheduleNotification(reminderDateTime);
      }
    }
  }

  Future<void> _scheduleNotification(DateTime dateTime) async {
    try {
      // Initialize timezone data
      tz.initializeTimeZones();

      // Get the Philippines timezone
      final philippines = tz.getLocation('Asia/Manila');

      // Convert the reminder time to Philippines timezone
      final scheduledDate = tz.TZDateTime.from(dateTime, philippines);
      final now = tz.TZDateTime.now(philippines);

      debugPrint('Current time: $now');
      debugPrint('Scheduled time: $scheduledDate');

      if (scheduledDate.isBefore(now)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Cannot schedule notification for past time.',
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
        return;
      }

      // Request notification permission
      final notificationPermission = await Permission.notification.request();
      debugPrint('Notification permission status: $notificationPermission');

      if (!notificationPermission.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Notification permission denied.',
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
            action:
                notificationPermission.isPermanentlyDenied
                    ? SnackBarAction(
                      label: 'Settings',
                      textColor: Colors.white,
                      onPressed: openAppSettings,
                    )
                    : null,
          ),
        );
        return;
      }

      // Request exact alarm permission for Android 12+
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 31) {
        final scheduleExactAlarmStatus =
            await Permission.scheduleExactAlarm.request();
        debugPrint(
          'Schedule exact alarm permission status: $scheduleExactAlarmStatus',
        );

        if (!scheduleExactAlarmStatus.isGranted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Exact Alarm permission denied. Cannot schedule notification.',
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
          return;
        }
      }

      // Create notification details
      const androidDetails = AndroidNotificationDetails(
        'note_reminder_channel',
        'Note Reminders',
        channelDescription: 'Notifications for note reminders',
        importance: Importance.max,
        priority: Priority.high,
        enableVibration: true,
        playSound: true,
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.public,
        icon: '@mipmap/ic_launcher_foreground',
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        styleInformation: BigTextStyleInformation(''),
        fullScreenIntent: true,
        showWhen: true,
        enableLights: true,
        channelShowBadge: true,
      );

      const notificationDetails = NotificationDetails(android: androidDetails);

      // Generate a unique notification ID
      final notificationId = dateTime.millisecondsSinceEpoch ~/ 1000;

      // Calculate the delay until the scheduled time
      final delay = scheduledDate.difference(now);

      // Format the time for the notification
      final formattedTime = DateFormat('hh:mm a').format(dateTime);
      final formattedDate = DateFormat('MMM dd, yyyy').format(dateTime);

      // Schedule the notification using a delayed Future
      Future.delayed(delay, () async {
        await _notificationsPlugin.show(
          notificationId,
          '⏰ Reminder • $formattedDate $formattedTime',
          _titleController.text.isNotEmpty
              ? '📝 ${_titleController.text}'
              : '📝 Untitled Note',
          notificationDetails,
        );
      });

      debugPrint('Notification scheduled successfully for $scheduledDate');

      // Save notification ID for later reference
      final prefs = await SharedPreferences.getInstance();
      final notificationIds = prefs.getStringList('notification_ids') ?? [];
      notificationIds.add(notificationId.toString());
      await prefs.setStringList('notification_ids', notificationIds);

      // Show confirmation for successful reminder
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reminder set for ${DateFormat('MMM dd, yyyy hh:mm a').format(dateTime)}.',
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
    } catch (e, stackTrace) {
      debugPrint('❌ Error scheduling notification: $e');
      debugPrint('Stack trace: $stackTrace');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to schedule notification: $e.',
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

  // Add this method to initialize notifications
  Future<void> _initializeNotifications() async {
    try {
      // Initialize timezone data
      tz.initializeTimeZones();

      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const initSettings = InitializationSettings(android: androidSettings);

      final initialized = await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (details) {
          debugPrint('Notification clicked: ${details.payload}');
        },
      );

      debugPrint('Notifications initialized: $initialized');

      // Create notification channel for Android
      const androidChannel = AndroidNotificationChannel(
        'note_reminder_channel',
        'Note Reminders',
        description: 'Notifications for note reminders',
        importance: Importance.max,
        enableVibration: true,
        playSound: true,
      );

      // Create the Android notification channel
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(androidChannel);
    } catch (e) {
      debugPrint('Error initializing notifications: $e');
    }
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text(
                  'Take a Picture',
                  style: TextStyle(fontSize: 14),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _takePicture();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text(
                  'Import from Gallery',
                  style: TextStyle(fontSize: 14),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _importImage();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _takePicture() async {
    final permissionStatus = await Permission.camera.request();

    if (!permissionStatus.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Camera permission denied.',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1080,
      maxHeight: 1920,
      imageQuality: 85,
    );

    if (image != null) {
      setState(() {
        _imagePaths.add(image.path);
        // Add to element order at the end
        _elementOrder.add({'type': 'image', 'path': image.path});
      });
    }
  }

  Future<void> _importImage() async {
    final galleryPermission = await Permission.photos.request();

    if (galleryPermission.isGranted) {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1080,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() {
          _imagePaths.add(image.path);
          // Add to element order at the end
          _elementOrder.add({'type': 'image', 'path': image.path});
        });
      }
    } else if (galleryPermission.isPermanentlyDenied) {
      _showPermissionSettingsDialog('Gallery');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Gallery permission denied.',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showPermissionSettingsDialog(String permissionName) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('$permissionName Permission Required'),
          content: Text(
            'Please enable $permissionName permission in app settings to continue.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                openAppSettings();
                Navigator.pop(context);
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _recordVoiceNote() async {
    // Check if there's already a voice note
    if (_voiceNotePath != null) {
      final confirm = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text(
                'Voice Note Already Exists',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: const Text(
                'There is already a voice note attached to this note. Would you like to replace it?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    // Store the old voice note path before clearing
                    final oldVoiceNotePath = _voiceNotePath;

                    // Delete the existing voice note file
                    try {
                      final existingFile = File(_voiceNotePath!);
                      if (await existingFile.exists()) {
                        await existingFile.delete();
                      }
                      Navigator.pop(context, true);
                      // Clear the voice note path and remove from element order
                      // Do this after navigation to avoid concurrent modification
                      if (mounted) {
                        setState(() {
                          _voiceNotePath = null;
                          // Create a new list without voice elements
                          _elementOrder =
                              _elementOrder
                                  .where(
                                    (element) => element['type'] != 'voice',
                                  )
                                  .toList();
                        });
                      }
                    } catch (e) {
                      debugPrint('Error deleting existing voice note: $e');
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Error removing existing voice note: $e',
                            style: TextStyle(
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.onErrorContainer,
                            ),
                          ),
                          backgroundColor:
                              Theme.of(context).colorScheme.errorContainer,
                          behavior: SnackBarBehavior.floating,
                          margin: const EdgeInsets.all(8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      );
                      Navigator.pop(context, false);
                    }
                  },
                  child: const Text('Replace'),
                ),
              ],
            ),
      );

      if (confirm != true) {
        return;
      }
    }

    final permissionStatus = await Permission.microphone.request();
    if (!permissionStatus.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Microphone permission denied.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final recorder = AudioRecorder();
    Timer? timer;
    int elapsedSeconds = 0;
    double amplitude = 0.0;
    late StateSetter dialogSetState;

    try {
      final directory = await getTemporaryDirectory();
      final fileName = 'voice_${Uuid().v4()}.m4a';
      final path = '${directory.path}/$fileName';

      await recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );

      timer = Timer.periodic(const Duration(milliseconds: 300), (
        Timer t,
      ) async {
        if (await recorder.isRecording()) {
          final amp = await recorder.getAmplitude();
          dialogSetState(() {
            elapsedSeconds++;
            amplitude = amp.current;
          });
        }
      });

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              dialogSetState = setState;
              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: const Text('Recording...', textAlign: TextAlign.center),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.6),
                        shape: BoxShape.circle,
                      ),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 1.0, end: 1.5),
                        duration: const Duration(milliseconds: 800),
                        curve: Curves.easeInOut,
                        builder: (context, value, child) {
                          return Transform.scale(
                            scale: 1 + (amplitude / 40).clamp(0.0, 1.0) * value,
                            child: Icon(
                              Icons.mic,
                              size: 60,
                              color: Colors.white,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${(elapsedSeconds / 3).toStringAsFixed(1)}s',
                      style: const TextStyle(fontSize: 24),
                    ),
                  ],
                ),
                actionsAlignment: MainAxisAlignment.center,
                actions: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      await recorder.stop();
                      timer?.cancel();
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      );

      if (await File(path).exists()) {
        setState(() {
          // Clear any existing voice notes from element order
          _elementOrder.removeWhere((element) => element['type'] == 'voice');
          _voiceNotePath = path;
          // Add new voice note to element order at the end
          _elementOrder.add({'type': 'voice', 'path': path});
          if (_titleController.text.trim().isEmpty) {
            _titleController.text = 'Voice Note $_voiceNoteCounter';
            _voiceNoteCounter++;
          }
        });

        await _audioPlayer.setFilePath(_voiceNotePath!);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Voice note recorded.',
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
      } else {
        throw Exception('Voice note file was not created');
      }
    } catch (e) {
      timer?.cancel();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to record voice note: $e.',
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
    } finally {
      recorder.dispose();
    }
  }

  Future<void> _toggleVoiceNote() async {
    if (_voiceNotePath == null) return;

    try {
      if (_audioPlayer.playerState.processingState ==
          ProcessingState.completed) {
        await _audioPlayer.seek(Duration.zero);
      }

      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        if (_audioPlayer.processingState == ProcessingState.idle ||
            _audioPlayer.processingState == ProcessingState.completed) {
          await _audioPlayer.setFilePath(_voiceNotePath!);
        }
        await _audioPlayer.play();
      }

      setState(() {
        _isPlaying = !_isPlaying;
      });
    } catch (e) {
      debugPrint('Error playing voice note: $e.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error playing voice note: $e.',
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

  Widget _buildVoiceNotePlayer() {
    if (_voiceNotePath == null || !File(_voiceNotePath!).existsSync()) {
      // Clean up element order if voice note file doesn't exist
      Future.microtask(() {
        if (mounted) {
          setState(() {
            _voiceNotePath = null;
            // Remove all elements from the list while keeping the same reference
            _elementOrder.removeWhere((element) => true);
            // Add back all elements except voice notes
            _elementOrder.addAll([
              ..._checklistItems.asMap().entries.map(
                (e) => {'type': 'checklist', 'index': e.key},
              ),
              ..._imagePaths.map((path) => {'type': 'image', 'path': path}),
            ]);
          });
        }
      });
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                onPressed: _toggleVoiceNote,
              ),
              Expanded(
                child: Slider(
                  min: 0,
                  max: _totalDuration.inMilliseconds.toDouble(),
                  value: _currentPosition.inMilliseconds.toDouble().clamp(
                    0,
                    _totalDuration.inMilliseconds.toDouble(),
                  ),
                  onChanged: (value) async {
                    final position = Duration(milliseconds: value.toInt());
                    await _audioPlayer.seek(position);
                  },
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_formatDuration(_currentPosition)} / ${_formatDuration(_totalDuration)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete,
                          size: 22,
                          color: Colors.red,
                        ),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder:
                                (context) => AlertDialog(
                                  title: const Text(
                                    'Remove Voice Note',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  content: const Text(
                                    'Are you sure you want to remove this voice note?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed:
                                          () => Navigator.pop(context, false),
                                      child: const Text('Cancel'),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        foregroundColor:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onErrorContainer,
                                      ),
                                      onPressed:
                                          () => Navigator.pop(context, true),
                                      child: const Text('Remove'),
                                    ),
                                  ],
                                ),
                          );

                          if (confirm == true) {
                            // First close the dialog
                            if (_voiceNotePath != null) {
                              try {
                                final file = File(_voiceNotePath!);
                                if (await file.exists()) {
                                  await file.delete();
                                }
                              } catch (e) {
                                debugPrint(
                                  'Error deleting voice note file: $e',
                                );
                              }
                            }

                            // Update state in the next frame
                            if (mounted) {
                              Future.microtask(() {
                                setState(() {
                                  _voiceNotePath = null;
                                  // Create a new list without voice elements
                                  _elementOrder =
                                      _elementOrder
                                          .where(
                                            (element) =>
                                                element['type'] != 'voice',
                                          )
                                          .toList();
                                });
                              });
                            }

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Voice note removed.',
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.onError,
                                  ),
                                ),
                                backgroundColor:
                                    Theme.of(context).colorScheme.error,
                                behavior: SnackBarBehavior.floating,
                                margin: const EdgeInsets.all(8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    final twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    return '${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds';
  }

  void _addLabel() async {
    // Always get fresh labels from LabelService
    List<Label> labels = await LabelService.loadLabels();
    labels = labels.reversed.toList();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.add),
                      title: Text(
                        'New Label',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      onTap: () async {
                        final controller = TextEditingController(
                          text: "New Label",
                        );
                        final labelName = await showDialog<String>(
                          context: context,
                          builder:
                              (context) => AlertDialog(
                                title: Text(
                                  'Create New Label',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                content: TextField(
                                  controller: controller,
                                  autofocus: true,
                                  style: Theme.of(context).textTheme.bodyMedium,
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
                                      style:
                                          Theme.of(
                                            context,
                                          ).textTheme.bodyMedium,
                                    ),
                                  ),
                                  ElevatedButton(
                                    onPressed: () {
                                      Navigator.pop(
                                        context,
                                        controller.text.trim(),
                                      );
                                    },
                                    child: Text(
                                      'Create',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium?.copyWith(
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                        );

                        if (labelName != null && labelName.isNotEmpty) {
                          await LabelService.addLabel(labelName);
                          // Get fresh labels after adding new one
                          final updatedLabels = await LabelService.loadLabels();
                          setSheetState(() {
                            labels = updatedLabels.reversed.toList();
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Label "$labelName" created.',
                                style: TextStyle(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.onPrimaryContainer,
                                ),
                              ),
                              backgroundColor:
                                  Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                              behavior: SnackBarBehavior.floating,
                              margin: const EdgeInsets.all(8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          );
                        }
                      },
                    ),
                    const Divider(),
                    SizedBox(
                      height: 300,
                      child: ListView.builder(
                        itemCount: labels.length,
                        itemBuilder: (context, index) {
                          final label = labels[index];
                          return ListTile(
                            leading: const Icon(Icons.label),
                            title: Text(
                              label.name,
                              style: Theme.of(context).textTheme.bodyMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              setState(() {
                                if (!_labels.contains(label.name)) {
                                  _labels.add(label.name);
                                }
                              });
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Label "${label.name}" added.',
                                    style: TextStyle(
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                  backgroundColor:
                                      Theme.of(
                                        context,
                                      ).colorScheme.primaryContainer,
                                  behavior: SnackBarBehavior.floating,
                                  margin: const EdgeInsets.all(8),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _moveToArchive() {
    setState(() {
      _isArchived = true;
    });
    _saveNote();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Note moved to archive.',
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
  }

  void _makeCopy() {
    final List<Map<String, dynamic>> contentJson = [
      {
        'text': _contentController.text,
        'bold': _selectedFontWeight == FontWeight.bold,
        'italic': _isItalic,
        'underline': _isUnderline,
        'strikethrough': _isStrikethrough,
        'fontFamily': _selectedFontFamily,
        'fontSize': _contentFontSize,
        'checklistItems': _checklistItems,
      },
    ];

    widget.onSave(
      id: null,
      title: '${_titleController.text} (Copy)',
      contentJson: contentJson,
      isPinned: _isPinned,
      isDeleted: false,
      reminder: _reminder,
      imagePaths: _imagePaths,
      voiceNote: _voiceNotePath,
      labels: _labels,
      isArchived: _isArchived,
      fontFamily: _selectedFontFamily,
      folderId: _selectedFolderId,
      folderColor:
          _selectedFolderId != null
              ? _folderColorMap[_selectedFolderId]?.value
              : null,
      collaboratorEmails: _collaboratorEmails,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Note copied.',
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
  }

  Future<void> _addCollaborator(String email) async {
    if (widget.noteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Save the note first before adding collaborators.',
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
      return;
    }

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('No authenticated user found.');
      }

      // Normalize email
      final normalizedEmail = email.toLowerCase().trim();
      if (normalizedEmail.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Please enter a valid email.',
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
        return;
      }

      // Check if the email is already a collaborator
      if (_collaboratorEmails.contains(normalizedEmail)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'This user is already a collaborator.',
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
        return;
      }

      // Query the users collection
      final userQuery =
          await FirebaseFirestore.instance
              .collection('users')
              .where('email', isEqualTo: normalizedEmail)
              .get();

      if (userQuery.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No user found with this email.',
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
        return;
      }

      final collaboratorUid = userQuery.docs.first.id;

      // Get the current note data first
      final noteRef = FirebaseFirestore.instance
          .collection('notes')
          .doc(widget.noteId);
      final noteDoc = await noteRef.get();

      if (!noteDoc.exists) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Note not found.')));
        return;
      }

      final noteData = noteDoc.data()!;
      final currentCollaborators = List<String>.from(
        noteData['collaborators'] ?? [],
      );
      final currentCollaboratorEmails = List<String>.from(
        noteData['collaboratorEmails'] ?? [],
      );
      final collaboratorHistory = List<Map<String, dynamic>>.from(
        noteData['collaboratorHistory'] ?? [],
      );

      // Add the new collaborator
      currentCollaborators.add(collaboratorUid);
      currentCollaboratorEmails.add(normalizedEmail);

      // Update local state immediately
      setState(() {
        _collaboratorEmails.add(normalizedEmail);
      });

      // Update Firestore with the new collaborator and history
      await noteRef.update({
        'collaborators': currentCollaborators,
        'collaboratorEmails': currentCollaboratorEmails,
        'collaboratorHistory': FieldValue.arrayUnion([
          {
            'email': normalizedEmail,
            'action': 'added',
            'timestamp': DateTime.now().toIso8601String(),
            'user': currentUser.email ?? 'Unknown',
          },
        ]),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastModifiedBy': currentUser.uid,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Note collaborated with $email',
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
    } on FirebaseException catch (e) {
      // Revert local state if Firestore update fails
      setState(() {
        _collaboratorEmails.remove(email.toLowerCase());
      });

      String message;
      switch (e.code) {
        case 'permission-denied':
          message = 'Permission denied. Please check Firestore rules.';
          break;
        case 'unavailable':
          message = 'Network error. Please check your connection.';
          break;
        default:
          message = 'Failed to add collaborator: ${e.message}';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
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
    } catch (e) {
      // Revert local state if any error occurs
      setState(() {
        _collaboratorEmails.remove(email.toLowerCase());
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unexpected error: $e',
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

  Future<void> _removeCollaboratorByEmail(String email) async {
    // Store the current state in case we need to revert
    final previousCollaboratorEmails = List<String>.from(_collaboratorEmails);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('No authenticated user found.');
      }

      // Normalize emails for comparison
      final normalizedEmail = email.toLowerCase().trim();
      final currentUserEmail = currentUser.email?.toLowerCase().trim() ?? '';

      // Check if user is removing themselves
      final bool isSelfRemoval = currentUserEmail == normalizedEmail;

      // Print debug info
      print('Removing email: $normalizedEmail');
      print('Current user email: $currentUserEmail');
      print('Is self removal: $isSelfRemoval');

      final noteRef = FirebaseFirestore.instance
          .collection('notes')
          .doc(widget.noteId);
      final noteDoc = await noteRef.get();

      if (!noteDoc.exists) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Note not found.')));
        return;
      }

      final noteData = noteDoc.data()!;
      final owner = noteData['owner'] as String?;
      final currentCollaborators = List<String>.from(
        noteData['collaborators'] ?? [],
      );
      final currentCollaboratorEmails = List<String>.from(
        noteData['collaboratorEmails'] ?? [],
      );

      print('Current collaborator emails: $currentCollaboratorEmails');

      // If user is not the owner and not removing themselves, deny the operation
      if (owner != currentUser.uid && !isSelfRemoval) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only the owner can remove other collaborators.'),
          ),
        );
        return;
      }

      String? collaboratorUid;

      // If removing self, use current user's UID directly
      if (isSelfRemoval) {
        collaboratorUid = currentUser.uid;
        print('Self removal - Using current UID: $collaboratorUid');
      } else {
        // For other users, query Firestore
        final userQuery =
            await FirebaseFirestore.instance
                .collection('users')
                .where('email', isEqualTo: normalizedEmail)
                .get();

        if (userQuery.docs.isEmpty) {
          print('User not found in Firestore. Will remove by email only.');
        } else {
          collaboratorUid = userQuery.docs.first.id;
          print('Found collaborator UID: $collaboratorUid');
        }
      }

      // Update local state immediately
      setState(() {
        _collaboratorEmails.removeWhere(
          (e) => e.toLowerCase().trim() == normalizedEmail,
        );
      });

      // Remove from collaborators list if UID was found
      if (collaboratorUid != null) {
        currentCollaborators.remove(collaboratorUid);
      }

      // Always remove from email list (case insensitive)
      currentCollaboratorEmails.removeWhere(
        (e) => e.toLowerCase().trim() == normalizedEmail,
      );

      print('Updated collaborator emails: $currentCollaboratorEmails');

      // Create a new array without the removed email for a clean update
      final cleanedCollaboratorEmails = List<String>.from(
        currentCollaboratorEmails.where(
          (e) => e.toLowerCase().trim() != normalizedEmail,
        ),
      );

      // Use arrayRemove operation for guaranteed email removal
      // This is more reliable than setting the array directly
      await noteRef.update({
        'collaborators': currentCollaborators,
        'collaboratorEmails': cleanedCollaboratorEmails,
        'collaboratorHistory': FieldValue.arrayUnion([
          {
            'email': normalizedEmail,
            'action': 'removed',
            'timestamp': DateTime.now().toIso8601String(),
            'user': currentUser.email ?? 'Unknown',
          },
        ]),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastModifiedBy': currentUser.uid,
      });

      // Force a second check and update to ensure the email is completely removed
      await noteRef.update({
        'collaboratorEmails': FieldValue.arrayRemove([normalizedEmail]),
      });

      // If the current user removed themselves, completely remove from both local storage and Firestore
      if (isSelfRemoval) {
        try {
          // 1. Remove from local storage
          final prefs = await SharedPreferences.getInstance();
          final String? notesString = prefs.getString('notes');
          if (notesString != null) {
            List<dynamic> notesList = jsonDecode(notesString);

            // Remove note for this user
            notesList =
                notesList.where((note) => note['id'] != widget.noteId).toList();

            // Save back to SharedPreferences
            await prefs.setString('notes', jsonEncode(notesList));
            print(
              'Successfully removed note ${widget.noteId} from local storage',
            );
          }

          // 2. Extra: Update the user's personal record in Firestore if such data exists
          try {
            final userDoc = FirebaseFirestore.instance
                .collection('users')
                .doc(currentUser.uid);

            // Remove this note from the user's collaborations list if it exists
            await userDoc.update({
              'collaboratedNotes': FieldValue.arrayRemove([widget.noteId]),
              'sharedNotes': FieldValue.arrayRemove([widget.noteId]),
            });
            print('Successfully removed note reference from user document');
          } catch (e) {
            // This is optional, so we'll just log and continue if it fails
            print('Optional user document update error (non-critical): $e');
          }

          // 3. One final verification to ensure all traces of this user are removed
          final verifySnapshot = await noteRef.get();
          if (verifySnapshot.exists) {
            final updatedNoteData = verifySnapshot.data()!;
            final collaboratorEmails = List<String>.from(
              updatedNoteData['collaboratorEmails'] ?? [],
            );

            if (collaboratorEmails.any(
              (e) => e.toLowerCase().trim() == currentUserEmail,
            )) {
              print(
                'Final cleanup: Email still found in collaboratorEmails, forcing direct array removal',
              );

              // Create a clean list without the current user's email
              final finalCleanedList =
                  collaboratorEmails
                      .where((e) => e.toLowerCase().trim() != currentUserEmail)
                      .toList();

              // Set the array directly to ensure the email is removed
              await noteRef.update({'collaboratorEmails': finalCleanedList});
            }
          }
        } catch (e) {
          print('Error completely removing collaboration: $e');
        }

        // Return to previous screen with result to indicate left collaboration
        Navigator.pop(context, {
          'id': widget.noteId,
          'isNew': false,
          'delete': false,
          'updated': true,
          'leftCollaboration': true, // Flag to refresh notes list
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isSelfRemoval
                ? 'You left the collaboration'
                : 'Removed collaborator: $email',
            style: TextStyle(color: Theme.of(context).colorScheme.onError),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    } catch (e) {
      // Revert local state if any error occurs
      setState(() {
        _collaboratorEmails = previousCollaboratorEmails;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to remove collaborator: $e',
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

  void _confirmRemoveCollaborator(String email) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final isRemovingSelf =
        currentUser?.email?.toLowerCase().trim() == email.toLowerCase().trim();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            isRemovingSelf ? 'Leave Collaboration' : 'Remove Collaborator',
          ),
          content: Text(
            isRemovingSelf
                ? 'Are you sure you want to leave this collaboration?'
                : 'Are you sure you want to remove $email?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                Navigator.pop(context);
                await _removeCollaboratorByEmail(email);
              },
              child: Text(isRemovingSelf ? 'Leave' : 'Remove'),
            ),
          ],
        );
      },
    );
  }

  void _openCollaboratorOptions() {
    final currentUser = FirebaseAuth.instance.currentUser;
    final isCollaborator =
        currentUser != null &&
        _collaboratorEmails.any(
          (email) =>
              email.toLowerCase().trim() ==
              currentUser.email?.toLowerCase().trim(),
        );
    final isOwner =
        widget.noteId != null &&
        FirebaseAuth.instance.currentUser?.uid ==
            widget.onSave.toString().split('owner:')[1].split(',')[0].trim();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.person_add),
                title: Text(
                  'Add Collaborator',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                onTap: () {
                  Navigator.pop(context);
                  _promptAddCollaborator();
                },
              ),
              ListTile(
                leading: const Icon(Icons.people),
                title: Text(
                  'View Collaborators',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                onTap: () {
                  Navigator.pop(context);
                  _viewCollaborators();
                },
              ),
              // Add a direct option for collaborators to leave
              if (isCollaborator && !isOwner)
                ListTile(
                  leading: const Icon(Icons.exit_to_app, color: Colors.red),
                  title: Text(
                    'Leave Collaboration',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.red),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    if (currentUser.email != null) {
                      _confirmRemoveCollaborator(currentUser.email!);
                    }
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _promptAddCollaborator() {
    final TextEditingController emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Collaborate with others',
            style:
                Theme.of(context).textTheme.titleMedium, // default size title
          ),
          content: TextField(
            controller: emailController,
            decoration: InputDecoration(
              labelText: 'Collaborator Email',
              hintText: 'Enter collaborator email',
              labelStyle: Theme.of(context).textTheme.bodyMedium, // default
              hintStyle: Theme.of(context).textTheme.bodyMedium, // default
            ),
            keyboardType: TextInputType.emailAddress,
            style: Theme.of(context).textTheme.bodyMedium, // typing default
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: Theme.of(context).textTheme.bodyMedium, // button default
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _addCollaborator(emailController.text.trim());
              },
              child: const Text('Collaborate'),
            ),
          ],
        );
      },
    );
  }

  void _viewCollaborators() {
    final currentUser = FirebaseAuth.instance.currentUser;
    final currentUserEmail = currentUser?.email?.toLowerCase() ?? '';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Collaborators'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_collaboratorEmails.isEmpty)
                const Text('No collaborators yet.')
              else
                SizedBox(
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _collaboratorEmails.length,
                    itemBuilder: (context, index) {
                      final email = _collaboratorEmails[index];
                      final isCurrentUser =
                          email.toLowerCase().trim() == currentUserEmail.trim();

                      return ListTile(
                        title: Text(
                          email + (isCurrentUser ? ' (You)' : ''),
                          style: const TextStyle(fontSize: 14),
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.remove_circle,
                            color: Colors.red,
                          ),
                          tooltip:
                              isCurrentUser
                                  ? 'Leave collaboration'
                                  : 'Remove collaborator',
                          onPressed: () {
                            Navigator.pop(context);
                            _confirmRemoveCollaborator(email);
                          },
                        ),
                      );
                    },
                  ),
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text(
                  'Recent Collaborators',
                  style: TextStyle(fontSize: 14),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _viewRecentCollaborators();
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _viewRecentCollaborators() async {
    try {
      final noteRef = FirebaseFirestore.instance
          .collection('notes')
          .doc(widget.noteId);
      final noteDoc = await noteRef.get();

      if (!noteDoc.exists) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Note not found.')));
        return;
      }

      final noteData = noteDoc.data()!;
      final collaboratorHistory = List<Map<String, dynamic>>.from(
        noteData['collaboratorHistory'] ?? [],
      );

      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Recent Collaborators'),
            content: SizedBox(
              width: double.maxFinite,
              child:
                  collaboratorHistory.isEmpty
                      ? const Text('No collaborator history available.')
                      : ListView.builder(
                        shrinkWrap: true,
                        itemCount: collaboratorHistory.length,
                        itemBuilder: (context, index) {
                          final entry = collaboratorHistory[index];
                          final email = entry['email'] as String;
                          final action = entry['action'] as String;
                          final timestamp = DateTime.parse(
                            entry['timestamp'] as String,
                          );
                          final user = entry['user'] as String;

                          return ListTile(
                            leading: Icon(
                              action == 'added'
                                  ? Icons.person_add
                                  : Icons.person_remove,
                              color:
                                  action == 'added' ? Colors.green : Colors.red,
                            ),
                            title: Text(
                              email,
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle: Text(
                              '${action == 'added' ? 'Added' : 'Removed'} by $user\n${DateFormat('MMM dd, yyyy hh:mm a').format(timestamp)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          );
                        },
                      ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to load collaborator history: $e',
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

  Future<void> _exportNote() async {
    final pdf = pw.Document();

    try {
      final logo = pw.MemoryImage(
        (await rootBundle.load('assets/logo.png')).buffer.asUint8List(),
      );

      final fontMap = {
        'Roboto': pw.Font.ttf(
          await DefaultAssetBundle.of(
            context,
          ).load('assets/fonts/Roboto-Regular.ttf'),
        ),
        'Times New Roman': pw.Font.ttf(
          await DefaultAssetBundle.of(
            context,
          ).load('assets/fonts/TimesNewRoman-Regular.ttf'),
        ),
        'Courier New': pw.Font.ttf(
          await DefaultAssetBundle.of(
            context,
          ).load('assets/fonts/courier-normal.ttf'),
        ),
        'Dancing Script': pw.Font.ttf(
          await DefaultAssetBundle.of(
            context,
          ).load('assets/fonts/DancingScript-Regular.ttf'),
        ),
        'Pacifico': pw.Font.ttf(
          await DefaultAssetBundle.of(
            context,
          ).load('assets/fonts/Pacifico-Regular.ttf'),
        ),
        'Space Mono': pw.Font.ttf(
          await DefaultAssetBundle.of(
            context,
          ).load('assets/fonts/SpaceMono-Regular.ttf'),
        ),
        'Great Vibes': pw.Font.ttf(
          await DefaultAssetBundle.of(
            context,
          ).load('assets/fonts/GreatVibes-Regular.ttf'),
        ),
        'Shadows Into Light': pw.Font.ttf(
          await DefaultAssetBundle.of(
            context,
          ).load('assets/fonts/ShadowsIntoLight-Regular.ttf'),
        ),
        'Gloria Hallelujah': pw.Font.ttf(
          await DefaultAssetBundle.of(
            context,
          ).load('assets/fonts/GloriaHallelujah-Regular.ttf'),
        ),
        'Indie Flower': pw.Font.ttf(
          await DefaultAssetBundle.of(
            context,
          ).load('assets/fonts/IndieFlower-Regular.ttf'),
        ),
        'Satisfy': pw.Font.ttf(
          await DefaultAssetBundle.of(
            context,
          ).load('assets/fonts/Satisfy-Regular.ttf'),
        ),
        'Homemade Apple': pw.Font.ttf(
          await DefaultAssetBundle.of(
            context,
          ).load('assets/fonts/HomemadeApple-Regular.ttf'),
        ),
        'Reenie Beanie': pw.Font.ttf(
          await DefaultAssetBundle.of(
            context,
          ).load('assets/fonts/ReenieBeanie-Regular.ttf'),
        ),
        'Handlee': pw.Font.ttf(
          await DefaultAssetBundle.of(
            context,
          ).load('assets/fonts/Handlee-Regular.ttf'),
        ),
      };

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build:
              (pw.Context context) => [
                pw.Center(child: pw.Image(logo, width: 200, height: 100)),
                pw.SizedBox(height: 16),
                pw.Text(
                  'Note Exported on: ${intl.DateFormat('MMM dd, yyyy hh:mm a').format(DateTime.now())}',
                  style: pw.TextStyle(
                    font: fontMap['Roboto'],
                    fontSize: 12,
                    color: PdfColors.grey600,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Note Created on: ${intl.DateFormat('MMM dd, yyyy hh:mm a').format(DateTime.now())}',
                  style: pw.TextStyle(
                    font: fontMap['Roboto'],
                    fontSize: 12,
                    color: PdfColors.grey600,
                  ),
                ),
                pw.SizedBox(height: 16),
                if (_selectedFolderName != null) ...[
                  pw.Text(
                    'Folder: $_selectedFolderName',
                    style: pw.TextStyle(
                      font: fontMap['Roboto'],
                      fontSize: 14,
                      color: PdfColors.teal600,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                ],
                if (_labels.isNotEmpty) ...[
                  pw.Text(
                    'Labels: ${_labels.map((label) => "#$label").join(", ")}',
                    style: pw.TextStyle(
                      font: fontMap['Roboto'],
                      fontSize: 14,
                      color: PdfColors.blue600,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                ],
                if (_reminder != null) ...[
                  pw.Text(
                    'Reminder: ${intl.DateFormat('MMM dd, yyyy hh:mm a').format(_reminder!)}',
                    style: pw.TextStyle(
                      font: fontMap['Roboto'],
                      fontSize: 14,
                      color: PdfColors.orange600,
                    ),
                  ),
                  pw.SizedBox(height: 16),
                ],
                pw.Text(
                  'Title:',
                  style: pw.TextStyle(
                    font: fontMap['Roboto'],
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  _titleController.text.isNotEmpty
                      ? _titleController.text
                      : 'Untitled Note',
                  style: pw.TextStyle(font: fontMap['Roboto'], fontSize: 20),
                ),
                pw.SizedBox(height: 16),
                pw.Text(
                  'Note:',
                  style: pw.TextStyle(
                    font: fontMap['Roboto'],
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                ..._buildNoteContent(fontMap),
                if (_checklistItems.isNotEmpty) ...[
                  pw.SizedBox(height: 16),
                  pw.Text(
                    'Checklist:',
                    style: pw.TextStyle(
                      font: fontMap['Roboto'],
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children:
                        _checklistItems
                            .asMap()
                            .entries
                            .where(
                              (entry) =>
                                  (entry.value['text'] ?? '').trim().isNotEmpty,
                            )
                            .toList()
                            .reversed
                            .map(
                              (entry) => pw.Row(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Container(
                                    width: 12,
                                    height: 12,
                                    margin: const pw.EdgeInsets.only(top: 4),
                                    decoration: pw.BoxDecoration(
                                      shape: pw.BoxShape.circle,
                                      border: pw.Border.all(
                                        color: PdfColors.black,
                                      ),
                                      color:
                                          entry.value['checked'] == true
                                              ? PdfColors.black
                                              : PdfColors.white,
                                    ),
                                  ),
                                  pw.SizedBox(width: 8),
                                  pw.Expanded(
                                    child: pw.Text(
                                      entry.value['text'] ?? '',
                                      style: pw.TextStyle(
                                        font: fontMap['Roboto'],
                                        fontSize: 16.0,
                                        fontWeight: pw.FontWeight.normal,
                                        fontStyle: pw.FontStyle.normal,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                            .toList(),
                  ),
                ],
                if (_voiceNotePath != null) ...[
                  pw.SizedBox(height: 16),
                  pw.Row(
                    children: [
                      pw.Text(
                        'Voice Note Attached',
                        style: pw.TextStyle(
                          font: fontMap['Roboto'],
                          fontSize: 14,
                          color: PdfColors.red600,
                        ),
                      ),
                    ],
                  ),
                ],
                if (_imagePaths.isNotEmpty) ...[
                  pw.SizedBox(height: 16),
                  pw.Text(
                    'Images:',
                    style: pw.TextStyle(
                      font: fontMap['Roboto'],
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  ..._buildImages(),
                ],
                pw.Spacer(),
                pw.Center(
                  child: pw.Text(
                    'Made with PenCraft Pro',
                    style: pw.TextStyle(
                      font: fontMap['Roboto'],
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      fontStyle: pw.FontStyle.italic,
                      color: PdfColors.grey600,
                    ),
                  ),
                ),
              ],
          footer:
              (pw.Context context) => pw.Container(
                alignment: pw.Alignment.center,
                margin: const pw.EdgeInsets.only(top: 10),
                child: pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: pw.TextStyle(
                    font: fontMap['Roboto'],
                    fontSize: 12,
                    color: PdfColors.grey,
                  ),
                ),
              ),
        ),
      );

      final directory = await getExternalStorageDirectory();
      final path = directory!.path;
      final fileName =
          _titleController.text.isNotEmpty
              ? _titleController.text
              : 'Untitled_Note';
      final file = File('$path/$fileName.pdf');

      await file.writeAsBytes(await pdf.save());

      // Await the PDF layout before showing the SnackBar
      final bool exportSuccessful = await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: fileName,
      );

      // Show SnackBar only if export was successful (user didn't cancel)
      if (exportSuccessful) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Note exported as PDF: $fileName.pdf.',
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
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to export PDF: $e.',
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

  List<pw.Widget> _buildNoteContent(Map<String, pw.Font> fontMap) {
    List<pw.Widget> widgets = [];

    for (var item in widget.contentJson ?? []) {
      final text = item['text'] ?? '';
      final isBold = item['bold'] == true;
      final isItalic = item['italic'] == true;
      final isUnderline = item['underline'] == true;
      final isStrikethrough = item['strikethrough'] == true;
      final fontSize = (item['fontSize'] as num?)?.toDouble() ?? 16.0;
      final fontFamily = item['fontFamily'] ?? 'Roboto';
      final selectedFont = fontMap[fontFamily] ?? fontMap['Roboto']!;

      if (text.isNotEmpty) {
        widgets.add(
          pw.Text(
            text,
            style: pw.TextStyle(
              font: selectedFont,
              fontSize: fontSize,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              fontStyle: isItalic ? pw.FontStyle.italic : pw.FontStyle.normal,
              decoration: pw.TextDecoration.combine([
                if (isUnderline) pw.TextDecoration.underline,
                if (isStrikethrough) pw.TextDecoration.lineThrough,
              ]),
            ),
          ),
        );
        widgets.add(pw.SizedBox(height: 8));
      }
    }
    return widgets;
  }

  List<pw.Widget> _buildImages() {
    return _imagePaths
        .map(
          (path) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 10),
            child: pw.Image(
              pw.MemoryImage(File(path).readAsBytesSync()),
              width: 250,
              height: 250,
              fit: pw.BoxFit.cover,
            ),
          ),
        )
        .toList();
  }

  bool _hasChecklist() {
    for (var item in widget.contentJson ?? []) {
      final checklistItems =
          (item['checklistItems'] as List<dynamic>? ?? [])
              .where(
                (task) => (task['text']?.toString().trim().isNotEmpty ?? false),
              )
              .toList();
      if (checklistItems.isNotEmpty) return true;
    }
    return false;
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      builder:
          (context) => Padding(
            padding: const EdgeInsets.all(1.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.label),
                  title: const Text(
                    'Add Labels',
                    style: TextStyle(fontSize: 14.0),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _addLabel();
                  },
                ),

                ListTile(
                  leading: const Icon(Icons.folder),
                  title: const Text(
                    'Move To Folder',
                    style: TextStyle(fontSize: 14.0),
                  ),
                  onTap: () async {
                    Navigator.pop(context);

                    List<Folder> folders = await FolderService.loadFolders();
                    folders = folders.reversed.toList();

                    await showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (context) {
                        return StatefulBuilder(
                          builder: (context, setStateBottomSheet) {
                            return SafeArea(
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ListTile(
                                      leading: const Icon(
                                        Icons.create_new_folder,
                                      ),
                                      title: const Text(
                                        'Add Folder',
                                        style: TextStyle(fontSize: 14),
                                      ),
                                      onTap: () async {
                                        final folderName =
                                            await _showCreateFolderDialog();
                                        if (folderName != null &&
                                            folderName.trim().isNotEmpty) {
                                          await FolderService.addFolder(
                                            folderName.trim(),
                                          );
                                          final updatedFolders =
                                              await FolderService.loadFolders();
                                          setStateBottomSheet(() {
                                            folders =
                                                updatedFolders.reversed
                                                    .toList();
                                          });
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Folder "$folderName" created.',
                                                style: TextStyle(
                                                  color:
                                                      Theme.of(context)
                                                          .colorScheme
                                                          .onPrimaryContainer,
                                                ),
                                              ),
                                              backgroundColor:
                                                  Theme.of(context)
                                                      .colorScheme
                                                      .primaryContainer,
                                              behavior:
                                                  SnackBarBehavior.floating,
                                              margin: const EdgeInsets.all(8),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                    const Divider(),
                                    SizedBox(
                                      height: 300,
                                      child: ListView.builder(
                                        shrinkWrap: true,
                                        itemCount: folders.length,
                                        itemBuilder: (context, index) {
                                          final folder = folders[index];
                                          final folderId = folder.id.toString();
                                          final folderColor = _folderColorMap
                                              .putIfAbsent(folderId, () {
                                                final color =
                                                    _folderColors[_colorIndex %
                                                        _folderColors.length];
                                                _colorIndex++;
                                                return color;
                                              });

                                          return ListTile(
                                            leading: Icon(
                                              Icons.folder,
                                              color: folderColor,
                                            ),
                                            title: Text(
                                              folder.name,
                                              style: const TextStyle(
                                                fontSize: 14,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            onTap: () async {
                                              setState(() {
                                                _selectedFolderId = folderId;
                                                _selectedFolderName =
                                                    folder.name;
                                              });

                                              // Update both Firestore and local storage
                                              if (widget.noteId != null) {
                                                // Update Firestore
                                                final noteRef =
                                                    FirebaseFirestore.instance
                                                        .collection('notes')
                                                        .doc(widget.noteId);
                                                await noteRef.update({
                                                  'folderId': folderId,
                                                  'folderColor':
                                                      _folderColorMap[folderId]
                                                          ?.value,
                                                  'folderName': folder.name,
                                                  'updatedAt':
                                                      DateTime.now()
                                                          .toIso8601String(),
                                                });

                                                // Update local storage
                                                final prefs =
                                                    await SharedPreferences.getInstance();
                                                final String? notesString =
                                                    prefs.getString('notes');
                                                if (notesString != null) {
                                                  final List<dynamic> notes =
                                                      jsonDecode(notesString);
                                                  final noteIndex = notes
                                                      .indexWhere(
                                                        (note) =>
                                                            note['id'] ==
                                                            widget.noteId,
                                                      );
                                                  if (noteIndex != -1) {
                                                    notes[noteIndex]['folderId'] =
                                                        folderId;
                                                    notes[noteIndex]['folderColor'] =
                                                        _folderColorMap[folderId]
                                                            ?.value;
                                                    notes[noteIndex]['folderName'] =
                                                        folder.name;
                                                    notes[noteIndex]['updatedAt'] =
                                                        DateTime.now()
                                                            .toIso8601String();
                                                    await prefs.setString(
                                                      'notes',
                                                      jsonEncode(notes),
                                                    );
                                                  }
                                                }
                                              }
                                              Navigator.pop(context);
                                            },
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.archive),
                  title: const Text(
                    'Move to Archive',
                    style: TextStyle(fontSize: 14.0),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _moveToArchive();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.copy),
                  title: const Text(
                    'Make a Copy',
                    style: TextStyle(fontSize: 14.0),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _makeCopy();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.group),
                  title: const Text(
                    'Collaboration with others',
                    style: TextStyle(fontSize: 14.0),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _openCollaboratorOptions();
                  },
                ),

                ListTile(
                  leading: const Icon(Icons.share),
                  title: const Text('Export', style: TextStyle(fontSize: 14.0)),
                  onTap: () {
                    Navigator.pop(context);
                    _exportNote();
                  },
                ),
              ],
            ),
          ),
    );
  }

  // Helper to get the current note state for comparison
  Map<String, dynamic> _getCurrentNoteState() {
    return {
      'title': _titleController.text.trim(),
      'content': _contentController.text.trim(),
      'isPinned': _isPinned,
      'reminder': _reminder?.toIso8601String(),
      'labels': List<String>.from(_labels),
      'isArchived': _isArchived,
      'fontFamily': _selectedFontFamily,
      'folderId': _selectedFolderId,
      'collaboratorEmails': List<String>.from(_collaboratorEmails),
      // Only include media paths if they exist
      if (_imagePaths.isNotEmpty) 'imagePaths': List<String>.from(_imagePaths),
      if (_voiceNotePath != null) 'voiceNotePath': _voiceNotePath,
      if (_checklistItems.isNotEmpty)
        'checklistItems':
            _checklistItems
                .where(
                  (item) =>
                      (item['text'] as String?)?.trim().isNotEmpty ?? false,
                )
                .map((item) => Map<String, dynamic>.from(item))
                .toList(),
      if (_selectedFolderId != null &&
          _folderColorMap[_selectedFolderId] != null)
        'folderColor': _folderColorMap[_selectedFolderId]?.value,
    };
  }

  // Helper to check if the note has changed from its initial state
  bool _hasNoteChanged() {
    if (_initialNoteState == null) return false;
    final current = _getCurrentNoteState();
    // Deep compare all fields
    return !_deepEquals(_initialNoteState!, current);
  }

  // Deep equality check for maps/lists
  bool _deepEquals(dynamic a, dynamic b) {
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
      }
      return true;
    } else if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (int i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    } else {
      return a == b;
    }
  }

  Future<bool> _onWillPop() async {
    // Only show dialog if the note has actually changed
    if (!_hasNoteChanged()) return true;

    final shouldExit =
        await showDialog<bool>(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: Text(
                  'Save your changes',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                content: Text(
                  'Do you want to save the changes you made?',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontSize: 16),
                ),
                actions: [
                  TextButton(
                    child: const Text('No'),
                    onPressed: () => Navigator.of(ctx).pop(false),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                    ),
                    child: const Text('Yes'),
                    onPressed: () => Navigator.of(ctx).pop(true),
                  ),
                ],
              ),
        ) ??
        false;

    if (shouldExit) {
      _saveNote();
    }

    return shouldExit;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final formattedDate = intl.DateFormat('MMM dd, yyyy').format(now);
    final formattedTime = intl.DateFormat('hh:mm a').format(now);
    final formattedDay = intl.DateFormat('EEEE').format(now);

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          title: const Text(
            'Add Note',
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          actions: [
            IconButton(
              icon: Icon(_isPinned ? Icons.push_pin : Icons.push_pin_outlined),
              onPressed: () {
                setState(() => _isPinned = !_isPinned);
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        Icon(
                          _isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                          color: Theme.of(context).colorScheme.onPrimary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isPinned ? 'Note pinned.' : 'Note unpinned.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    margin: const EdgeInsets.all(8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.undo),
              onPressed: _historyIndex > 0 ? _undo : null,
            ),
            IconButton(
              icon: const Icon(Icons.redo),
              onPressed: _historyIndex < _history.length - 1 ? _redo : null,
            ),
            IconButton(icon: const Icon(Icons.check), onPressed: _saveNote),
          ],
        ),

        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(width: 8),
                if (_collaboratorEmails.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20.0, top: 4.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Collaborated Notes',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: _titleController,
                  autofocus: false,
                  decoration: InputDecoration(
                    hintText: 'Title',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                  ),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$formattedDate, $formattedTime, $formattedDay',
                      style: TextStyle(fontSize: 15, color: Colors.grey[600]),
                    ),
                    if (_reminder != null)
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: _setReminder,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.alarm,
                                    size: 16,
                                    color:
                                        _reminder!.isBefore(DateTime.now())
                                            ? Colors.red
                                            : Colors.grey[600],
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: RichText(
                                      text: TextSpan(
                                        style: TextStyle(
                                          fontSize: 15,
                                          color:
                                              _reminder!.isBefore(
                                                    DateTime.now(),
                                                  )
                                                  ? Colors.red
                                                  : Colors.blue[600],
                                        ),
                                        children: [
                                          TextSpan(
                                            text: DateFormat(
                                              'MMM dd, yyyy hh:mm a',
                                            ).format(_reminder!),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          IconButton(
                            icon: Icon(
                              Icons.close,
                              size: 18,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.7),
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Remove Reminder',
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder:
                                    (ctx) => AlertDialog(
                                      title: const Text(
                                        'Remove Reminder',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      content: const Text(
                                        'Are you sure you want to remove this reminder?',
                                      ),
                                      actions: [
                                        TextButton(
                                          child: const Text('No'),
                                          onPressed:
                                              () => Navigator.pop(ctx, false),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red,
                                          ),
                                          child: const Text('Remove'),
                                          onPressed:
                                              () => Navigator.pop(ctx, true),
                                        ),
                                      ],
                                    ),
                              );
                              if (confirm == true) {
                                setState(() {
                                  _reminder = null;
                                });
                                await _saveNoteToFirestore();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor:
                                        Theme.of(context).colorScheme.error,
                                    content: Text(
                                      'Reminder removed.',
                                      style: TextStyle(
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onError,
                                      ),
                                    ),
                                    behavior: SnackBarBehavior.floating,
                                    margin: const EdgeInsets.all(8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                  ],
                ),
                if (_selectedFolderName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Chip(
                      avatar: Icon(
                        Icons.folder,
                        size: 18,
                        color:
                            _selectedFolderId != null
                                ? _folderColorMap[_selectedFolderId] ??
                                    Colors.blue
                                : Colors.blue,
                      ),
                      label: Text(_selectedFolderName!),
                      backgroundColor: Colors.blue.withOpacity(0.15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      deleteIcon: const Icon(Icons.close, size: 18),
                      deleteIconColor: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.7),
                      onDeleted: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder:
                              (context) => AlertDialog(
                                title: const Text(
                                  'Remove Folder',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                content: Text(
                                  'Are you sure you want to remove this note from the folder "$_selectedFolderName"?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed:
                                        () => Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                    ),
                                    onPressed:
                                        () => Navigator.pop(context, true),
                                    child: const Text('Remove'),
                                  ),
                                ],
                              ),
                        );

                        if (confirm == true) {
                          setState(() {
                            _selectedFolderId = null;
                            _selectedFolderName = null;
                          });
                          await _saveNoteToFirestore();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Folder removed from note.',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onError,
                                ),
                              ),
                              backgroundColor:
                                  Theme.of(context).colorScheme.error,
                              behavior: SnackBarBehavior.floating,
                              margin: const EdgeInsets.all(8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                if (_labels.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child:
                        _labels.isEmpty
                            ? Center(
                              child: Text(
                                'No labels yet',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            )
                            : Wrap(
                              spacing: 8.0,
                              children:
                                  _labels
                                      .map(
                                        (label) => GestureDetector(
                                          onTap: () async {
                                            final updatedLabelController =
                                                TextEditingController(
                                                  text: label,
                                                );

                                            final updated = await showDialog<
                                              String
                                            >(
                                              context: context,
                                              builder:
                                                  (context) => AlertDialog(
                                                    title: const Text(
                                                      'Edit Label',
                                                    ),
                                                    content: TextField(
                                                      controller:
                                                          updatedLabelController,
                                                      decoration:
                                                          const InputDecoration(
                                                            hintText:
                                                                'Update label',
                                                          ),
                                                      autofocus: true,
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed:
                                                            () => Navigator.pop(
                                                              context,
                                                              null,
                                                            ),
                                                        child: const Text(
                                                          'Cancel',
                                                        ),
                                                      ),
                                                      ElevatedButton(
                                                        onPressed: () {
                                                          Navigator.pop(
                                                            context,
                                                            updatedLabelController
                                                                .text
                                                                .trim(),
                                                          );
                                                        },
                                                        child: const Text(
                                                          'Save',
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                            );

                                            if (updated != null &&
                                                updated.isNotEmpty &&
                                                updated != label) {
                                              setState(() {
                                                final index = _labels.indexOf(
                                                  label,
                                                );
                                                if (index != -1) {
                                                  _labels[index] = updated;
                                                }
                                              });
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    "Label '$updated' updated.",
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                  backgroundColor:
                                                      Theme.of(
                                                        context,
                                                      ).colorScheme.primary,
                                                  behavior:
                                                      SnackBarBehavior.floating,
                                                  margin: const EdgeInsets.all(
                                                    8,
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                ),
                                              );
                                            }
                                          },
                                          child: Chip(
                                            label: Text(
                                              label,
                                              style: TextStyle(
                                                color:
                                                    Theme.of(
                                                      context,
                                                    ).colorScheme.onSurface,
                                              ),
                                            ),
                                            backgroundColor: Colors.blue
                                                .withOpacity(0.15),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            deleteIcon: const Icon(
                                              Icons.close,
                                              size: 18,
                                            ),
                                            deleteIconColor: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withOpacity(0.7),
                                            onDeleted: () async {
                                              final confirm = await showDialog<
                                                bool
                                              >(
                                                context: context,
                                                builder:
                                                    (context) => AlertDialog(
                                                      title: const Text(
                                                        'Remove Label',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      content: Text(
                                                        'Are you sure you want to remove "$label"?',
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed:
                                                              () =>
                                                                  Navigator.pop(
                                                                    context,
                                                                    false,
                                                                  ),
                                                          child: const Text(
                                                            'Cancel',
                                                          ),
                                                        ),
                                                        ElevatedButton(
                                                          style:
                                                              ElevatedButton.styleFrom(
                                                                backgroundColor:
                                                                    Colors.red,
                                                                foregroundColor:
                                                                    Colors
                                                                        .white,
                                                              ),
                                                          onPressed:
                                                              () =>
                                                                  Navigator.pop(
                                                                    context,
                                                                    true,
                                                                  ),
                                                          child: const Text(
                                                            'Remove',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                              );

                                              if (confirm == true) {
                                                setState(() {
                                                  _labels.remove(label);
                                                });
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      "Label '$label' removed.",
                                                      style: TextStyle(
                                                        color:
                                                            Theme.of(context)
                                                                .colorScheme
                                                                .onError,
                                                      ),
                                                    ),
                                                    backgroundColor:
                                                        Theme.of(
                                                          context,
                                                        ).colorScheme.error,
                                                    behavior:
                                                        SnackBarBehavior
                                                            .floating,
                                                    margin:
                                                        const EdgeInsets.all(8),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                    ),
                                                  ),
                                                );
                                              }
                                            },
                                          ),
                                        ),
                                      )
                                      .toList(),
                            ),
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _contentController,
                  maxLines: null,
                  textAlign: TextAlign.left,
                  decoration: InputDecoration(
                    hintText: 'Type your note here...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                  ),
                  style: TextStyle(
                    fontSize: _contentFontSize,
                    fontFamily: _selectedFontFamily,
                    fontWeight: _selectedFontWeight,
                    fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
                    decoration: TextDecoration.combine([
                      if (_isUnderline) TextDecoration.underline,
                      if (_isStrikethrough) TextDecoration.lineThrough,
                    ]),
                  ),
                  onChanged: (text) {
                    setState(() {});
                  },
                ),
                const SizedBox(height: 16),
                // Render elements in order (newest first)
                ..._elementOrder.map((element) {
                  final type = element['type'] as String?;
                  if (type == 'image') {
                    final path = element['path'];
                    if (path != null && path is String && path.isNotEmpty) {
                      final fileExists = File(path).existsSync();
                      debugPrint('Image path: $path | Exists: $fileExists');
                      if (fileExists) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Stack(
                            children: [
                              GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (_) => FullScreenGallery(
                                            imagePaths: _imagePaths,
                                            initialIndex: _imagePaths.indexOf(
                                              path,
                                            ),
                                          ),
                                    ),
                                  );
                                },
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(
                                    File(path),
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.5),
                                    shape: BoxShape.circle,
                                  ),
                                  child: IconButton(
                                    icon: const Icon(
                                      Icons.close,
                                      size: 20,
                                      color: Colors.white,
                                    ),
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder:
                                            (context) => AlertDialog(
                                              title: const Text(
                                                'Remove Image',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              content: const Text(
                                                'Are you sure you want to remove this image?',
                                              ),
                                              actions: [
                                                TextButton(
                                                  child: const Text('Cancel'),
                                                  onPressed:
                                                      () => Navigator.of(
                                                        context,
                                                      ).pop(false),
                                                ),
                                                ElevatedButton(
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                        backgroundColor:
                                                            Colors.red,
                                                      ),
                                                  child: const Text('Remove'),
                                                  onPressed:
                                                      () => Navigator.of(
                                                        context,
                                                      ).pop(true),
                                                ),
                                              ],
                                            ),
                                      );

                                      if (confirm == true) {
                                        setState(() {
                                          _imagePaths.remove(path);
                                          _elementOrder.remove(element);
                                        });
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Image removed.',
                                              style: TextStyle(
                                                color:
                                                    Theme.of(
                                                      context,
                                                    ).colorScheme.onError,
                                              ),
                                            ),
                                            backgroundColor:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.error,
                                            behavior: SnackBarBehavior.floating,
                                            margin: const EdgeInsets.all(8),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      } else {
                        debugPrint('Image file does not exist: $path');
                        return const SizedBox.shrink();
                      }
                    } else {
                      debugPrint('Image path is null or empty');
                      return const SizedBox.shrink();
                    }
                  } else if (type == 'voice') {
                    return _buildVoiceNotePlayer();
                  } else if (type == 'checklist') {
                    final index = element['index'];
                    if (index != null &&
                        index is int &&
                        index < _checklistItems.length) {
                      _checklistControllers.putIfAbsent(index, () {
                        final controller = TextEditingController(
                          text: _checklistItems[index]['text'],
                        );
                        return controller;
                      });

                      return ListTile(
                        leading: Checkbox(
                          value: _checklistItems[index]['checked'],
                          onChanged: (bool? value) {
                            setState(() {
                              _checklistItems[index]['checked'] = value!;
                            });
                          },
                        ),
                        title: TextField(
                          controller: _checklistControllers[index],
                          onChanged: (text) {
                            setState(() {
                              _checklistItems[index]['text'] = text;
                              if (text.trim().isEmpty &&
                                  _checklistControllers[index]?.text != '') {
                                _elementOrder.remove(element);
                              }
                            });
                          },
                          decoration: const InputDecoration(
                            hintText: 'Input List Item',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 5.0),
                          ),
                          style: TextStyle(
                            fontSize: 16.0,
                            fontWeight: FontWeight.normal,
                            fontStyle: FontStyle.normal,
                            decoration:
                                _checklistItems[index]['checked']
                                    ? TextDecoration.lineThrough
                                    : null,
                            fontFamily: 'Roboto',
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder:
                                  (context) => AlertDialog(
                                    title: const Text(
                                      'Remove Checklist Item',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    content: const Text(
                                      'Are you sure you want to remove this item?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed:
                                            () => Navigator.pop(context, false),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                        ),
                                        onPressed:
                                            () => Navigator.pop(context, true),
                                        child: const Text('Remove'),
                                      ),
                                    ],
                                  ),
                            );

                            if (confirm == true) {
                              setState(() {
                                _checklistItems.removeAt(index);
                                _elementOrder.remove(element);
                                for (var i = 0; i < _elementOrder.length; i++) {
                                  if (_elementOrder[i]['type'] == 'checklist' &&
                                      _elementOrder[i]['index'] > index) {
                                    _elementOrder[i]['index']--;
                                  }
                                }
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Checklist item removed.',
                                    style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.onError,
                                    ),
                                  ),
                                  backgroundColor:
                                      Theme.of(context).colorScheme.error,
                                  behavior: SnackBarBehavior.floating,
                                  margin: const EdgeInsets.all(8),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              );
                              await _saveNoteToFirestore();
                            }
                          },
                        ),
                      );
                    } else {
                      return const SizedBox.shrink();
                    }
                  }
                  return const SizedBox.shrink();
                }),
              ],
            ),
          ),
        ),
        bottomNavigationBar: BottomAppBar(
          height: 70.0,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: IconButton(
                      icon: const Icon(Icons.font_download),
                      onPressed: _showFontSelectionOptions,
                      tooltip: 'Select font',
                    ),
                  ),
                  Flexible(
                    child: IconButton(
                      icon: const Icon(Icons.font_download_outlined),
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(20),
                            ),
                          ),
                          builder: (BuildContext context) {
                            return Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'Text Options',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 20,
                                    runSpacing: 20,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.format_size),
                                        tooltip: 'Increase Font Size',
                                        onPressed: () {
                                          showModalBottomSheet(
                                            context: context,
                                            shape: const RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.vertical(
                                                    top: Radius.circular(20),
                                                  ),
                                            ),
                                            builder: (BuildContext context) {
                                              double tempFontSize =
                                                  _contentFontSize;

                                              return StatefulBuilder(
                                                builder: (
                                                  context,
                                                  setModalState,
                                                ) {
                                                  return Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                          16.0,
                                                        ),
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        const Text(
                                                          'Adjust Font Size',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize: 18,
                                                          ),
                                                        ),
                                                        Slider(
                                                          min: 10,
                                                          max: 50,
                                                          value: tempFontSize,
                                                          divisions: 40,
                                                          label:
                                                              tempFontSize
                                                                  .round()
                                                                  .toString(),
                                                          onChanged: (value) {
                                                            setModalState(() {
                                                              tempFontSize =
                                                                  value;
                                                            });
                                                          },
                                                        ),
                                                        Text(
                                                          '${tempFontSize.toStringAsFixed(1)} pt',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 16,
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          height: 16,
                                                        ),
                                                        ElevatedButton(
                                                          onPressed: () {
                                                            setState(() {
                                                              _contentFontSize =
                                                                  tempFontSize;
                                                            });
                                                            Navigator.pop(
                                                              context,
                                                            );
                                                          },
                                                          child: const Text(
                                                            'Apply Font Size',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                },
                                              );
                                            },
                                          );
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.format_bold),
                                        tooltip: 'Toggle Bold',
                                        onPressed: () {
                                          setState(() {
                                            _selectedFontWeight =
                                                _selectedFontWeight ==
                                                        FontWeight.bold
                                                    ? FontWeight.normal
                                                    : FontWeight.bold;
                                          });
                                          Navigator.pop(context);
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.format_italic),
                                        tooltip: 'Toggle Italic',
                                        onPressed: () {
                                          setState(() {
                                            _isItalic = !_isItalic;
                                          });
                                          Future.delayed(
                                            const Duration(milliseconds: 100),
                                            () {
                                              Navigator.pop(context);
                                            },
                                          );
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.format_underline,
                                        ),
                                        tooltip: 'Toggle Underline',
                                        onPressed: () {
                                          setState(() {
                                            _isUnderline = !_isUnderline;
                                          });
                                          Navigator.pop(context);
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.format_strikethrough,
                                        ),
                                        tooltip: 'Toggle Strikethrough',
                                        onPressed: () {
                                          setState(() {
                                            _isStrikethrough =
                                                !_isStrikethrough;
                                          });
                                          Navigator.pop(context);
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: () {
                                      Navigator.pop(context);
                                    },
                                    child: const Text('Close'),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                      tooltip: 'Text Options',
                    ),
                  ),
                  Flexible(
                    child: IconButton(
                      icon: const Icon(Icons.image),
                      onPressed: _showImageOptions,
                      tooltip: 'Add Image',
                    ),
                  ),
                  Flexible(
                    child: IconButton(
                      icon: const Icon(Icons.mic),
                      onPressed: _recordVoiceNote,
                      tooltip: 'Record Voice Note',
                    ),
                  ),
                  Flexible(
                    child: IconButton(
                      icon: const Icon(Icons.check_box),
                      onPressed: _addChecklistItem,
                      tooltip: 'Add Checklist Item',
                    ),
                  ),
                  Flexible(
                    child: IconButton(
                      icon: const Icon(Icons.alarm),
                      onPressed: _setReminder,
                      tooltip: 'Set/Edit Reminder',
                    ),
                  ),
                  Flexible(
                    child: IconButton(
                      icon: const Icon(Icons.more_vert),
                      onPressed: _showMoreOptions,
                      tooltip: 'More Options',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
