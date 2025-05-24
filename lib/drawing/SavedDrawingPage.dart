// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pencraftpro/drawing/DrawingPage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SavedDrawingsPage extends StatefulWidget {
  const SavedDrawingsPage({super.key});

  @override
  State<SavedDrawingsPage> createState() => _SavedDrawingsPageState();
}

class _SavedDrawingsPageState extends State<SavedDrawingsPage> {
  List<String> _savedDrawings = [];

  @override
  void initState() {
    super.initState();
    _loadSavedDrawings();
  }

  Future<void> _loadSavedDrawings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _savedDrawings = prefs.getStringList('saved_drawings') ?? [];
    });
  }

  Future<String> _getImagePath(String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$fileName.png';
  }

  Future<void> _confirmDelete(int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text(
              'Remove Drawing',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: const Text(
              'This drawing will be permanently removed. Are you sure?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.red,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove'),
              ),
            ],
          ),
    );

    if (confirm == true) {
      await _deleteDrawing(index);
    }
  }

  Future<void> _deleteDrawing(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final drawingData = _savedDrawings[index].split('|');
    final fileName = drawingData[0];

    // Delete local file
    final path = await _getImagePath(fileName);
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }

    // Delete from Firestore
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('drawings')
            .doc(fileName)
            .delete();
        print('Successfully removed drawing from Firestore.');
      }
    } catch (e) {
      print('Failed to remove from Firestore: $e');
      // Continue with local deletion even if Firestore deletion fails
    }

    _savedDrawings.removeAt(index);
    await prefs.setStringList('saved_drawings', _savedDrawings);

    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Drawing removed.',
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

  Future<void> _renameDrawing(int index) async {
    final drawingData = _savedDrawings[index].split('|');
    final currentTitle =
        drawingData.length > 2 ? drawingData[2] : 'Drawing ${index + 1}';

    final controller = TextEditingController(text: currentTitle);
    final newTitle = await showDialog<String?>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text(
              'Rename Drawing',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Enter new title',
                hintStyle: TextStyle(fontSize: 14),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(fontSize: 14)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Confirm', style: TextStyle(fontSize: 14)),
              ),
            ],
          ),
    );

    if (newTitle != null && newTitle.isNotEmpty) {
      while (drawingData.length < 6) {
        drawingData.add('');
      }
      drawingData[2] = newTitle;

      _savedDrawings[index] = drawingData.join('|');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('saved_drawings', _savedDrawings);
      setState(() {});

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Title updated.',
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
    }
  }

  Future<void> _loadDrawing(int index) async {
    final drawingData = _savedDrawings[index].split('|');
    final fileName = drawingData[0];
    final title =
        drawingData.length > 2 ? drawingData[2] : 'Drawing ${index + 1}';

    final directory = await getApplicationDocumentsDirectory();
    final statePath = '${directory.path}/$fileName.json';

    if (await File(statePath).exists()) {
      // If state file exists, load the complete state
      final file = File(statePath);
      final jsonString = await file.readAsString();
      final json = jsonDecode(jsonString);
      final state = await DrawingState.fromJson(json);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => DrawingCanvasPage(
                customTitle: title,
                initialOffsetX:
                    state.images.isNotEmpty ? state.images[0]['offsetX'] : 0,
                initialOffsetY:
                    state.images.isNotEmpty ? state.images[0]['offsetY'] : 0,
                initialScale:
                    state.images.isNotEmpty ? state.images[0]['scale'] : 1.0,
                initialState: state, // Pass the complete state
              ),
        ),
      );
    } else {
      // Fallback: Try to fetch from Firestore
      await _loadDrawingFromFirestore(fileName, title);
    }
  }

  Future<void> _loadDrawingFromFirestore(String drawingId, String title) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('User not authenticated, cannot load from Firestore');
        return;
      }

      final doc =
          await FirebaseFirestore.instance
              .collection('drawings')
              .doc(drawingId)
              .get();

      if (!doc.exists) {
        print('Drawing document does not exist');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Drawing not found in Firestore.')),
        );
        return;
      }

      // Check if user has access to this drawing
      final data = doc.data()!;
      if (data['uid'] != user.uid) {
        print('User does not have access to this drawing');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You do not have access to this drawing.')),
        );
        return;
      }

      final state = await DrawingState.fromJson(data['state']);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => DrawingCanvasPage(
                customTitle: title,
                initialOffsetX:
                    state.images.isNotEmpty ? state.images[0]['offsetX'] : 0,
                initialOffsetY:
                    state.images.isNotEmpty ? state.images[0]['offsetY'] : 0,
                initialScale:
                    state.images.isNotEmpty ? state.images[0]['scale'] : 1.0,
                initialState: state,
              ),
        ),
      );
    } catch (e) {
      print('Failed to load from Firestore: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load drawing from Firestore.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Saved Drawings'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child:
              _savedDrawings.isEmpty
                  ? const Center(
                    child: Text(
                      'No saved drawings yet.',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  )
                  : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16.0),
                        child: Text(
                          'Recent Drawings',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: null,
                          ),
                        ),
                      ),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: () async {
                            await _loadSavedDrawings();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Drawings refreshed successfully.',
                                    style: TextStyle(
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onPrimary,
                                    ),
                                  ),
                                  backgroundColor:
                                      Theme.of(context).colorScheme.primary,
                                  behavior: SnackBarBehavior.floating,
                                  margin: const EdgeInsets.all(8),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              );
                            }
                          },
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: _savedDrawings.length,
                            itemBuilder: (context, index) {
                              final drawingData = _savedDrawings[index].split(
                                '|',
                              );
                              // Robust parsing with defaults
                              final fileName =
                                  drawingData.isNotEmpty ? drawingData[0] : '';
                              final dateTime =
                                  drawingData.length > 1
                                      ? DateTime.tryParse(drawingData[1]) ??
                                          DateTime.now()
                                      : DateTime.now();
                              // Drawing data format: [fileName|dateTime|title|offsetX|offsetY|scale]
                              // Extract title from position 2 if available, otherwise use default naming
                              final title =
                                  drawingData.length > 2
                                      ? drawingData[2].isNotEmpty
                                          ? drawingData[2]
                                          : 'Drawing ${index + 1}'
                                      : 'Drawing ${index + 1}';
                              final offsetX =
                                  drawingData.length > 3
                                      ? double.tryParse(drawingData[3]) ?? 0.0
                                      : 0.0;
                              final offsetY =
                                  drawingData.length > 4
                                      ? double.tryParse(drawingData[4]) ?? 0.0
                                      : 0.0;
                              final scale =
                                  drawingData.length > 5
                                      ? double.tryParse(drawingData[5]) ?? 1.0
                                      : 1.0;

                              // Debug print to verify parameters
                              debugPrint(
                                'Opening drawing: title=$title, fileName=$fileName, '
                                'offsetX=$offsetX, offsetY=$offsetY, scale=$scale',
                              );

                              return FutureBuilder<String>(
                                future: _getImagePath(fileName),
                                builder: (context, snapshot) {
                                  final path = snapshot.data;
                                  final exists =
                                      path != null && File(path).existsSync();
                                  return InkWell(
                                    onTap: () {
                                      if (exists) {
                                        _loadDrawing(index);
                                      } else {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Drawing file "$title" not found.',
                                              style: TextStyle(
                                                color:
                                                    Theme.of(context)
                                                        .colorScheme
                                                        .onErrorContainer,
                                              ),
                                            ),
                                            backgroundColor:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.errorContainer,
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
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 16.0,
                                      ),
                                      child: Card(
                                        elevation: 4,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Container(
                                          height: 150,
                                          padding: const EdgeInsets.all(16.0),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 100,
                                                height: 100,
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  color: Colors.grey[200],
                                                ),
                                                child:
                                                    exists
                                                        ? ClipRRect(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                          child: Image.file(
                                                            File(path),
                                                            fit: BoxFit.cover,
                                                          ),
                                                        )
                                                        : const Icon(
                                                          Icons.image,
                                                          size: 50,
                                                          color: Colors.grey,
                                                        ),
                                              ),
                                              const SizedBox(width: 16),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Text(
                                                      title,
                                                      style: TextStyle(
                                                        fontSize:
                                                            title ==
                                                                    'Edit Title Name'
                                                                ? 14
                                                                : 14,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      'Created on: ${dateTime.toLocal().toString().split('.')[0]}',
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        color: Colors.grey[600],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.edit,
                                                    ),
                                                    onPressed:
                                                        () => _renameDrawing(
                                                          index,
                                                        ),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.delete,
                                                    ),
                                                    color: Colors.red,
                                                    onPressed:
                                                        () => _confirmDelete(
                                                          index,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
        ),
        bottomNavigationBar: BottomAppBar(
          color: Theme.of(context).colorScheme.error,
          shape: const CircularNotchedRectangle(),
          notchMargin: 10.0,
          child: IconButton(
            icon: Icon(
              Icons.home,
              color: Theme.of(context).colorScheme.onError,
            ),
            iconSize: 32,
            onPressed: () {
              Navigator.pop(context);
            },
            tooltip: 'Go to Home',
          ),
        ),
      ),
    );
  }
}
