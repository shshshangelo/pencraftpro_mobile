import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pencraftpro/drawing/DrawingPage.dart';

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
    final drawings = prefs.getStringList('saved_drawings') ?? [];

    // Assign default titles if missing
    for (int i = 0; i < drawings.length; i++) {
      final parts = drawings[i].split('|');
      while (parts.length < 3) {
        parts.add('');
      }
      if (parts[2].trim().isEmpty) {
        parts[2] = 'Drawing ${i + 1}';
        drawings[i] = parts.join('|');
      }
    }

    await prefs.setStringList('saved_drawings', drawings);

    setState(() {
      _savedDrawings = drawings;
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
            title: const Text('Delete Drawing?'),
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
                child: const Text('Delete'),
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

    final path = await _getImagePath(fileName);
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }

    _savedDrawings.removeAt(index);
    await prefs.setStringList('saved_drawings', _savedDrawings);

    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('🗑️ Drawing deleted')));
  }

  Future<void> _renameDrawing(int index) async {
    final drawingData = _savedDrawings[index].split('|');
    final currentTitle = drawingData.length > 2 ? drawingData[2] : '';

    final controller = TextEditingController(text: currentTitle);
    final newTitle = await showDialog<String?>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Rename Drawing', style: TextStyle(fontSize: 16)),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Enter new title',
                hintStyle: TextStyle(fontSize: 14),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: const Text('Save'),
              ),
            ],
          ),
    );

    if (newTitle != null && newTitle.isNotEmpty) {
      while (drawingData.length < 6) {
        drawingData.add('');
      }
      drawingData[2] = newTitle;

      final path = await _getImagePath(drawingData[0]);
      final file = File(path);
      if (await file.exists()) {
        final image = await decodeImageFromList(await file.readAsBytes());
        drawingData[3] =
            ((MediaQuery.of(context).size.width - image.width * 0.6) / 2)
                .toString();
        drawingData[4] =
            ((MediaQuery.of(context).size.height - image.height * 0.6) / 2)
                .toString();
        drawingData[5] = (0.6).toString();
      }

      _savedDrawings[index] = drawingData.join('|');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('saved_drawings', _savedDrawings);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Drawings'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
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
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _savedDrawings.length,
                        itemBuilder: (context, index) {
                          final drawingData = _savedDrawings[index].split('|');
                          final fileName = drawingData[0];
                          final dateTime = DateTime.parse(drawingData[1]);
                          final title =
                              drawingData.length > 2 ? drawingData[2] : '';

                          return FutureBuilder<String>(
                            future: _getImagePath(fileName),
                            builder: (context, snapshot) {
                              final path = snapshot.data;
                              final exists =
                                  path != null && File(path).existsSync();
                              return InkWell(
                                onTap: () {
                                  if (exists) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder:
                                            (_) => DrawingCanvasPage(
                                              loadedImage: File(path),
                                              customTitle: title,
                                            ),
                                      ),
                                    );
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 16.0),
                                  child: Card(
                                    elevation: 4,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
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
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                  ),
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
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.edit),
                                                onPressed:
                                                    () => _renameDrawing(index),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.delete),
                                                color: Colors.red,
                                                onPressed:
                                                    () => _confirmDelete(index),
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
                  ],
                ),
      ),
    );
  }
}
