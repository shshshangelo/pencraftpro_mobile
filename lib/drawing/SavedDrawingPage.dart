import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: Card(
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Container(
                                height: 150, // Larger card size
                                padding: const EdgeInsets.all(16.0),
                                child: Row(
                                  children: [
                                    // Placeholder for drawing preview
                                    Container(
                                      width: 100,
                                      height: 100,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[200],
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.image,
                                        size: 50,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    // Drawing details
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            'Drawing ${index + 1}',
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
                                  ],
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
    );
  }
}
