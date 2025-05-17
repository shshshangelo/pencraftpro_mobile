// ignore_for_file: unused_import, unused_element
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
  int _notificationIdCounter = 0;
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
  final List<Map<String, dynamic>> _elementOrder = [];
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
    _imagePaths = widget.imagePaths?.toList() ?? [];
    _voiceNotePath = widget.voiceNote;
    _labels = widget.labels?.toList() ?? [];
    _isArchived = widget.isArchived;

    // Initialize element order with existing elements in reverse order
    // First add images (they should be at the bottom)
    if (widget.imagePaths != null) {
      for (var path in widget.imagePaths!) {
        _elementOrder.add({'type': 'image', 'path': path});
      }
    }
    // Then add voice note (it should be above images)
    if (widget.voiceNote != null) {
      _elementOrder.insert(0, {'type': 'voice', 'path': widget.voiceNote});
    }
    // Finally add checklist items (they should be at the top)
    if (widget.contentJson != null) {
      for (var item in widget.contentJson!) {
        if (item['checklistItems'] != null) {
          final checklistItems = List<Map<String, dynamic>>.from(
            item['checklistItems'],
          );
          for (var i = 0; i < checklistItems.length; i++) {
            _elementOrder.insert(0, {'type': 'checklist', 'index': i});
          }
        }
      }
    }

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

    // 🔥 ADDITION para sa Collaborators
    _collaboratorEmails = widget.collaboratorEmails?.toList() ?? [];
    if (widget.noteId != null) {
      _fetchCollaboratorsFromFirestore();
      // Add real-time listener for note updates
      _setupNoteListener();
    }

    // Store the initial state after all fields are loaded
    _initialNoteState = _getCurrentNoteState();
  }

  StreamSubscription? _noteListener;

  void _setupNoteListener() {
    if (widget.noteId == null) return;

    _noteListener = FirebaseFirestore.instance
        .collection('notes')
        .doc(widget.noteId)
        .snapshots()
        .listen((snapshot) {
          if (!snapshot.exists) return;

          final data = snapshot.data()!;
          final currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser == null) return;

          // Only update if the change was made by another user
          if (data['lastModifiedBy'] != currentUser.uid) {
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
              _imagePaths = List<String>.from(data['imagePaths'] ?? []);
              _voiceNotePath = data['voiceNote'];
              _labels = List<String>.from(data['labels'] ?? []);
              _isArchived = data['isArchived'] ?? false;
              _selectedFolderId = data['folderId'];
              if (data['folderColor'] != null) {
                _folderColorMap[_selectedFolderId!] = Color(
                  data['folderColor'],
                );
              }
              _collaboratorEmails = List<String>.from(
                data['collaboratorEmails'] ?? [],
              );
            });
          }
        });
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
      debugPrint('❌ Failed to fetch collaborators: $e');
    }
  }

  Future<void> _loadFolderName(String folderId) async {
    try {
      final folders = await FolderService.loadFolders();
      final matchedFolder = folders.firstWhere(
        (f) => f.id.toString() == folderId,
        orElse: () => Folder(id: folderId, name: 'Unknown Folder'),
      );

      setState(() {
        _selectedFolderId = matchedFolder.id.toString();
        _selectedFolderName = matchedFolder.name;
      });
    } catch (e) {
      debugPrint('Failed to load folder: $e');
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

      final noteData = {
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
        'imagePaths': _imagePaths,
        'voiceNote': _voiceNotePath,
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
        'createdAt':
            existingNote?['createdAt'] ?? DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
        'lastModifiedBy':
            currentUser.uid, // Add this field to track who made the last change
      };

      // Update local storage
      final existingIndex = notes.indexWhere((note) => note['id'] == noteId);
      if (existingIndex != -1) {
        notes[existingIndex] = noteData;
      } else {
        notes.add(noteData);
      }
      await prefs.setString('notes', jsonEncode(notes));

      // Try to save to Firestore (will be queued if offline)
      final noteRef = FirebaseFirestore.instance
          .collection('notes')
          .doc(noteId);
      await noteRef.set(noteData, SetOptions(merge: true));

      debugPrint('✅ Note saved locally and queued for Firestore sync: $noteId');

      widget.onSave(
        id: noteId,
        title: noteData['title'] as String,
        contentJson:
            (noteData['contentJson'] as List).cast<Map<String, dynamic>>(),
        isPinned: _isPinned,
        isDeleted: false,
        reminder: _reminder,
        imagePaths: _imagePaths,
        voiceNote: _voiceNotePath,
        labels: _labels,
        isArchived: _isArchived,
        fontFamily: _selectedFontFamily,
        folderId: _selectedFolderId,
        folderColor: noteData['folderColor'] as int?,
        collaboratorEmails: _collaboratorEmails,
      );
    } catch (e) {
      debugPrint('⚠️ Note saved locally but Firestore sync pending: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
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
      // Add to element order at the beginning
      _elementOrder.insert(0, {'type': 'checklist', 'index': index});
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
      SnackBar(content: Text('Note moved to folder: ${matchedFolder.name}.')),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reminder has been successfully set.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _scheduleNotification(DateTime dateTime) async {
    try {
      final notificationPermission = await Permission.notification.request();
      debugPrint('📱 Notification permission status: $notificationPermission');

      if (!notificationPermission.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Notification permission denied.'),
            backgroundColor: Colors.red,
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

      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final isAndroid12OrHigher = androidInfo.version.sdkInt >= 31;
      debugPrint('📱 Android SDK version: ${androidInfo.version.sdkInt}');

      if (isAndroid12OrHigher) {
        final scheduleExactAlarmStatus =
            await Permission.scheduleExactAlarm.request();
        debugPrint(
          '⏰ Schedule exact alarm permission status: $scheduleExactAlarmStatus',
        );

        if (!scheduleExactAlarmStatus.isGranted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Exact Alarm permission denied. Cannot schedule notification.',
              ),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      // Convert to TZDateTime and validate
      final scheduledDate = tz.TZDateTime.from(dateTime, tz.local);
      final now = tz.TZDateTime.now(tz.local);
      debugPrint('⏰ Current time: $now');
      debugPrint('⏰ Scheduled time: $scheduledDate');

      if (scheduledDate.isBefore(now)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot schedule notification for past time.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Create notification details
      const androidDetails = AndroidNotificationDetails(
        'note_reminder',
        'Note Reminders',
        channelDescription: 'Notifications for note reminders',
        importance: Importance.max,
        priority: Priority.high,
        enableVibration: true,
        playSound: true,
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.public,
      );

      const notificationDetails = NotificationDetails(android: androidDetails);

      // Schedule the notification
      await _notificationsPlugin.zonedSchedule(
        _notificationIdCounter++,
        'Note Reminder',
        _titleController.text.isNotEmpty
            ? _titleController.text
            : 'Untitled Note',
        scheduledDate,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dateAndTime,
        payload: 'Reminder Notification',
      );

      debugPrint('✅ Notification scheduled successfully for $scheduledDate');

      // Save notification ID for later reference
      final prefs = await SharedPreferences.getInstance();
      final notificationIds = prefs.getStringList('notification_ids') ?? [];
      notificationIds.add(_notificationIdCounter.toString());
      await prefs.setStringList('notification_ids', notificationIds);
    } catch (e, stackTrace) {
      debugPrint('❌ Error scheduling notification: $e');
      debugPrint('Stack trace: $stackTrace');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to schedule notification: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // Add this method to initialize notifications
  Future<void> _initializeNotifications() async {
    try {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const initSettings = InitializationSettings(android: androidSettings);

      final initialized = await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (details) {
          debugPrint('📱 Notification clicked: ${details.payload}');
        },
      );

      debugPrint('📱 Notifications initialized: $initialized');
    } catch (e) {
      debugPrint('❌ Error initializing notifications: $e');
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
          content: Text('Camera permission denied.'),
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
        // Add to element order at the beginning
        _elementOrder.insert(0, {'type': 'image', 'path': image.path});
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
          // Add to element order at the beginning
          _elementOrder.insert(0, {'type': 'image', 'path': image.path});
        });
      }
    } else if (galleryPermission.isPermanentlyDenied) {
      _showPermissionSettingsDialog('Gallery');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gallery permission denied.'),
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
          _voiceNotePath = path;
          // Add to element order at the beginning
          _elementOrder.insert(0, {'type': 'voice', 'path': path});
          if (_titleController.text.trim().isEmpty) {
            _titleController.text = 'Voice Note $_voiceNoteCounter';
            _voiceNoteCounter++;
          }
        });

        await _audioPlayer.setFilePath(_voiceNotePath!);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Voice note recorded.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception('Voice note file was not created');
      }
    } catch (e) {
      timer?.cancel();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to record voice note: $e'),
          backgroundColor: Colors.red,
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
      debugPrint('Error playing voice note: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error playing voice note: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildVoiceNotePlayer() {
    if (_voiceNotePath == null) return SizedBox.shrink();

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
                                  title: const Text('Delete Voice Note?'),
                                  content: const Text(
                                    'Are you sure you want to delete this voice note?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed:
                                          () => Navigator.pop(context, false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed:
                                          () => Navigator.pop(context, true),
                                      child: const Text(
                                        'Delete',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ),
                          );

                          if (confirm == true) {
                            setState(() {
                              _voiceNotePath = null;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Voice note deleted.'),
                                backgroundColor: Colors.black,
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
                                            ).colorScheme.onPrimary,
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
                              content: Text('Label "$labelName" created.'),
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
                                  content: Text('Label "${label.name}" added.'),
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
      const SnackBar(
        content: Text('Note moved to archive.'),
        backgroundColor: Colors.green,
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
      const SnackBar(
        content: Text('Note copied.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _addCollaborator(String email) async {
    if (widget.noteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Save the note first before adding collaborators.'),
        ),
      );
      return;
    }

    try {
      // Normalize email
      final normalizedEmail = email.toLowerCase().trim();
      if (normalizedEmail.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid email.')),
        );
        return;
      }

      // Check if the email is already a collaborator
      if (_collaboratorEmails.contains(normalizedEmail)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This user is already a collaborator.')),
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
          const SnackBar(content: Text('No user found with this email.')),
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

      // Add the new collaborator
      currentCollaborators.add(collaboratorUid);
      currentCollaboratorEmails.add(normalizedEmail);

      // Update the note with the new collaborators
      await noteRef.update({
        'collaborators': currentCollaborators,
        'collaboratorEmails': currentCollaboratorEmails,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update local state
      setState(() {
        _collaboratorEmails.add(normalizedEmail);
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Note shared with $email')));
    } on FirebaseException catch (e) {
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unexpected error: $e')));
    }
  }

  Future<void> _removeCollaboratorByEmail(String email) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('No authenticated user found.');
      }

      final userQuery =
          await FirebaseFirestore.instance
              .collection('users')
              .where('email', isEqualTo: email.toLowerCase())
              .get();

      if (userQuery.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Collaborator not found.')),
        );
        return;
      }

      final collaboratorUid = userQuery.docs.first.id;
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

      // Check if the current user is the owner or the collaborator being removed
      if (owner != currentUser.uid &&
          email.toLowerCase() != currentUser.email?.toLowerCase()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only the owner can remove other collaborators.'),
          ),
        );
        return;
      }

      // Remove the collaborator
      currentCollaborators.remove(collaboratorUid);
      currentCollaboratorEmails.remove(email.toLowerCase());

      // Update the note
      await noteRef.update({
        'collaborators': currentCollaborators,
        'collaboratorEmails': currentCollaboratorEmails,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastModifiedBy': currentUser.uid,
      });

      setState(() {
        _collaboratorEmails.remove(email.toLowerCase());
      });

      // If the current user removed themselves, close the note
      if (email.toLowerCase() == currentUser.email?.toLowerCase()) {
        Navigator.pop(context);
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Removed collaborator: $email')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove collaborator: $e')),
      );
    }
  }

  void _confirmRemoveCollaborator(String email) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remove Collaborator'), // default size
          content: Text('Are you sure you want to remove $email?'),
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
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
  }

  void _openCollaboratorOptions() {
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
                  style:
                      Theme.of(
                        context,
                      ).textTheme.bodyMedium, // default text size
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
                  style:
                      Theme.of(
                        context,
                      ).textTheme.bodyMedium, // default text size
                ),
                onTap: () {
                  Navigator.pop(context);
                  _viewCollaborators();
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
            'Share Note',
            style:
                Theme.of(context).textTheme.titleMedium, // ✅ default size title
          ),
          content: TextField(
            controller: emailController,
            decoration: InputDecoration(
              labelText: 'Collaborator Email',
              hintText: 'Enter collaborator email',
              labelStyle: Theme.of(context).textTheme.bodyMedium, // ✅ default
              hintStyle: Theme.of(context).textTheme.bodyMedium, // ✅ default
            ),
            keyboardType: TextInputType.emailAddress,
            style: Theme.of(context).textTheme.bodyMedium, // ✅ typing default
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style:
                    Theme.of(context).textTheme.bodyMedium, // ✅ button default
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _addCollaborator(emailController.text.trim());
              },
              child: const Text('Share'),
            ),
          ],
        );
      },
    );
  }

  void _viewCollaborators() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Collaborators'),
          content:
              _collaboratorEmails.isEmpty
                  ? const Text('No collaborators yet.')
                  : SizedBox(
                    width: double.maxFinite,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _collaboratorEmails.length,
                      itemBuilder: (context, index) {
                        final email = _collaboratorEmails[index];
                        return ListTile(
                          title: Text(
                            email,
                            style: const TextStyle(fontSize: 14),
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.remove_circle,
                              color: Colors.red,
                            ),
                            onPressed: () {
                              Navigator.pop(context);
                              _confirmRemoveCollaborator(email);
                            },
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
                  'Exported on: ${intl.DateFormat('MMM dd, yyyy hh:mm a').format(DateTime.now())}',
                  style: pw.TextStyle(
                    font: fontMap['Roboto'],
                    fontSize: 12,
                    color: PdfColors.grey600,
                  ),
                ),
                pw.SizedBox(height: 16),
                pw.Text(
                  _titleController.text.isNotEmpty
                      ? _titleController.text
                      : 'Untitled Note',
                  style: pw.TextStyle(
                    font: fontMap['Roboto'],
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                ..._buildNoteContent(fontMap),
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
                if (_reminder != null) ...[
                  pw.Text(
                    'Reminder: ${intl.DateFormat('MMM dd, yyyy hh:mm a').format(_reminder!)}',
                    style: pw.TextStyle(
                      font: fontMap['Roboto'],
                      fontSize: 14,
                      color: PdfColors.blueGrey,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                ],
                if (_labels.isNotEmpty) ...[
                  pw.Wrap(
                    spacing: 8,
                    children:
                        _labels.map((label) {
                          return pw.Container(
                            padding: const pw.EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: pw.BoxDecoration(
                              color: PdfColors.amber100,
                              borderRadius: pw.BorderRadius.circular(8),
                            ),
                            child: pw.Text(
                              '#$label',
                              style: pw.TextStyle(
                                font: fontMap['Roboto'],
                                fontSize: 12,
                              ),
                            ),
                          );
                        }).toList(),
                  ),
                  pw.SizedBox(height: 12),
                ],
                if (_imagePaths.isNotEmpty) ...[
                  pw.SizedBox(height: 16),
                  ..._buildImages(),
                ],
                if (_voiceNotePath != null) ...[
                  pw.SizedBox(height: 12),
                  pw.Text(
                    'Voice Note Attached',
                    style: pw.TextStyle(
                      font: fontMap['Roboto'],
                      fontSize: 14,
                      fontStyle: pw.FontStyle.italic,
                      color: PdfColors.deepOrange,
                    ),
                  ),
                ],
                pw.Spacer(),
                pw.Center(
                  child: pw.Text(
                    'Made with PenCraft Pro',
                    style: pw.TextStyle(
                      font: fontMap['Roboto'],
                      fontSize: 18,
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
            content: Text('Note exported as PDF: $fileName.pdf'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to export PDF: $e'),
          backgroundColor: Colors.red,
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
      final checklistItems =
          (item['checklistItems'] as List<dynamic>? ?? [])
              .where(
                (task) => (task['text']?.toString().trim().isNotEmpty ?? false),
              )
              .toList();
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

      if (checklistItems.isNotEmpty) {
        widgets.add(
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children:
                checklistItems.map((check) {
                  return pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: 12,
                        height: 12,
                        margin: const pw.EdgeInsets.only(top: 4),
                        decoration: pw.BoxDecoration(
                          shape: pw.BoxShape.circle,
                          border: pw.Border.all(color: PdfColors.black),
                          color:
                              check['checked'] == true
                                  ? PdfColors.black
                                  : PdfColors.white,
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Expanded(
                        child: pw.Text(
                          check['text'] ?? '',
                          style: pw.TextStyle(
                            font: selectedFont,
                            fontSize: fontSize,
                            fontWeight:
                                isBold
                                    ? pw.FontWeight.bold
                                    : pw.FontWeight.normal,
                            fontStyle:
                                isItalic
                                    ? pw.FontStyle.italic
                                    : pw.FontStyle.normal,
                            decoration: pw.TextDecoration.combine([
                              if (isUnderline) pw.TextDecoration.underline,
                              if (isStrikethrough)
                                pw.TextDecoration.lineThrough,
                            ]),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
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
                                        'New Folder',
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
                                              await _saveNoteToFirestore();
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
                    'Collaboration',
                    style: TextStyle(fontSize: 14.0),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _openCollaboratorOptions(); // ✅ TAMANG FUNCTION NA
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
      'imagePaths': List<String>.from(_imagePaths),
      'voiceNotePath': _voiceNotePath,
      'checklistItems':
          _checklistItems
              .map((item) => Map<String, dynamic>.from(item))
              .toList(),
      'isPinned': _isPinned,
      'reminder': _reminder?.toIso8601String(),
      'labels': List<String>.from(_labels),
      'isArchived': _isArchived,
      'fontFamily': _selectedFontFamily,
      'folderId': _selectedFolderId,
      'folderColor':
          _selectedFolderId != null
              ? _folderColorMap[_selectedFolderId]?.value
              : null,
      'collaboratorEmails': List<String>.from(_collaboratorEmails),
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
                title: const Text('Save your changes?'),
                content: const Text(
                  'You have unsaved changes. Save before exiting?',
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
            overflow: TextOverflow.ellipsis, // 🔥 important
            maxLines: 1, // 🔥 important
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
                if (widget.collaboratorEmails != null &&
                    widget.collaboratorEmails!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Shared Note',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    ),
                  ),
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
                              onTap:
                                  _setReminder, // Tap text/icon to edit reminder
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.alarm,
                                    size: 16,
                                    color: Colors.grey[600],
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: RichText(
                                      text: TextSpan(
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: Colors.blue[600],
                                        ),
                                        children: [
                                          TextSpan(
                                            text: DateFormat(
                                              'MMM dd, yyyy hh:mm a',
                                            ).format(_reminder!),
                                            style: TextStyle(
                                              fontStyle: FontStyle.italic,
                                            ),
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
                                      title: const Text('Remove Reminder?'),
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
                                  const SnackBar(
                                    content: Text('Reminder removed.'),
                                    backgroundColor: Colors.black,
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
                                title: const Text('Remove Folder?'),
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
                            const SnackBar(
                              content: Text('Folder removed from note.'),
                              backgroundColor: Colors.black,
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
                                                  ),
                                                  backgroundColor:
                                                      Colors.orange,
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
                                                        'Confirm Delete',
                                                      ),
                                                      content: Text(
                                                        'Are you sure you want to delete "$label"?',
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
                                                            'Delete',
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
                                                    ),
                                                    backgroundColor:
                                                        Colors.black,
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
                    decoration:
                        _isStrikethrough ? TextDecoration.lineThrough : null,
                  ),
                  onChanged: (text) {
                    setState(() {});
                  },
                ),
                const SizedBox(height: 16),
                // Render elements in order (newest first)
                ..._elementOrder.map((element) {
                  switch (element['type']) {
                    case 'image':
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
                                            element['path'],
                                          ),
                                        ),
                                  ),
                                );
                              },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(
                                  File(element['path']),
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
                                            title: const Text('Delete Image?'),
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
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.red,
                                                ),
                                                child: const Text('Delete'),
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
                                        _imagePaths.remove(element['path']);
                                        _elementOrder.remove(element);
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    case 'voice':
                      return _buildVoiceNotePlayer();
                    case 'checklist':
                      final index = element['index'];
                      if (index < _checklistItems.length) {
                        // Show all checklist items, but track if they're empty
                        // Ensure controller exists
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
                                // Remove empty checklist items from element order after editing
                                if (text.trim().isEmpty &&
                                    _checklistControllers[index]?.text != '') {
                                  _elementOrder.remove(element);
                                }
                              });
                            },
                            decoration: const InputDecoration(
                              hintText: 'Input List Item',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 5.0,
                              ),
                            ),
                            style: TextStyle(
                              fontSize: _contentFontSize,
                              fontFamily: _selectedFontFamily,
                              fontWeight: _selectedFontWeight,
                              fontStyle:
                                  _isItalic
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                              decoration: TextDecoration.combine([
                                if (_checklistItems[index]['checked'])
                                  TextDecoration.lineThrough,
                                if (_isUnderline) TextDecoration.underline,
                              ]),
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.red,
                            ),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder:
                                    (context) => AlertDialog(
                                      title: const Text(
                                        'Delete Checklist Item',
                                      ),
                                      content: const Text(
                                        'Are you sure you want to delete this item?',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed:
                                              () =>
                                                  Navigator.pop(context, false),
                                          child: const Text('Cancel'),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red,
                                          ),
                                          onPressed:
                                              () =>
                                                  Navigator.pop(context, true),
                                          child: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                              );

                              if (confirm == true) {
                                setState(() {
                                  _checklistItems.removeAt(index);
                                  _elementOrder.remove(element);
                                  // Update indices of remaining checklist items
                                  for (
                                    var i = 0;
                                    i < _elementOrder.length;
                                    i++
                                  ) {
                                    if (_elementOrder[i]['type'] ==
                                            'checklist' &&
                                        _elementOrder[i]['index'] > index) {
                                      _elementOrder[i]['index']--;
                                    }
                                  }
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Checklist item deleted.'),
                                    backgroundColor: Colors.black,
                                  ),
                                );
                                await _saveNoteToFirestore();
                              }
                            },
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    default:
                      return const SizedBox.shrink();
                  }
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
