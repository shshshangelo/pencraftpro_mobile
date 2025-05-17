import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class LabelService {
  static const _key = 'labels';

  static Future<List<Label>> loadLabels() async {
    final prefs = await SharedPreferences.getInstance();
    final labelsJson = prefs.getString(_key);
    if (labelsJson == null) return [];
    final List decoded = jsonDecode(labelsJson);
    return decoded.map((e) => Label.fromJson(e)).toList();
  }

  static Future<void> saveLabels(List<Label> labels) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(labels.map((e) => e.toJson()).toList());
    await prefs.setString(_key, encoded);
  }

  static Future<void> addLabel(String name) async {
    final labels = await loadLabels();
    final newLabel = Label(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
    );
    labels.add(newLabel);
    await saveLabels(labels);
  }

  static Future<void> updateLabel(String oldName, String newName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? labelsString = prefs.getString(_key);
      if (labelsString == null) return;

      // Update in labels list
      List<dynamic> labels = jsonDecode(labelsString);
      for (var label in labels) {
        if (label['name'] == oldName) {
          label['name'] = newName;
        }
      }
      await prefs.setString(_key, jsonEncode(labels));

      // Get current user
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      // Update in notes (SharedPreferences)
      final String? notesString = prefs.getString('notes');
      if (notesString != null) {
        List<dynamic> notes = jsonDecode(notesString);
        for (var note in notes) {
          if (note['labels'] != null) {
            List<String> noteLabels = List<String>.from(note['labels']);
            if (noteLabels.contains(oldName)) {
              noteLabels.remove(oldName);
              noteLabels.add(newName);
              note['labels'] = noteLabels;
            }
          }
        }
        await prefs.setString('notes', jsonEncode(notes));
      }

      // Update in Firestore
      final notesRef = FirebaseFirestore.instance.collection('notes');

      // Get all notes where user is owner or collaborator
      final notesSnapshot =
          await notesRef.where('owner', isEqualTo: currentUser.uid).get();

      final collaboratorNotesSnapshot =
          await notesRef
              .where('collaborators', arrayContains: currentUser.uid)
              .get();

      // Combine both query results
      final allNotes = [
        ...notesSnapshot.docs,
        ...collaboratorNotesSnapshot.docs,
      ];

      // Update each note that contains the label
      for (var doc in allNotes) {
        final noteData = doc.data();
        if (noteData['labels'] != null) {
          List<String> noteLabels = List<String>.from(noteData['labels']);
          if (noteLabels.contains(oldName)) {
            noteLabels.remove(oldName);
            noteLabels.add(newName);
            await doc.reference.update({
              'labels': noteLabels,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }
      }

      debugPrint('✅ Label "$oldName" updated to "$newName" in all notes');
    } catch (e) {
      debugPrint('❌ Error updating label: $e');
      rethrow;
    }
  }

  static Future<void> deleteLabel(String labelName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? labelsString = prefs.getString(_key);
      if (labelsString == null) return;

      // Remove from labels list
      List<dynamic> labels = jsonDecode(labelsString);
      labels.removeWhere((label) => label['name'] == labelName);
      await prefs.setString(_key, jsonEncode(labels));

      // Get current user
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      // Update notes in SharedPreferences
      final String? notesString = prefs.getString('notes');
      if (notesString != null) {
        List<dynamic> notes = jsonDecode(notesString);
        for (var note in notes) {
          if (note['labels'] != null) {
            List<String> noteLabels = List<String>.from(note['labels']);
            if (noteLabels.contains(labelName)) {
              noteLabels.remove(labelName);
              note['labels'] = noteLabels;
            }
          }
        }
        await prefs.setString('notes', jsonEncode(notes));
      }

      // Update notes in Firestore
      final notesRef = FirebaseFirestore.instance.collection('notes');

      // Get all notes where user is owner or collaborator
      final notesSnapshot =
          await notesRef.where('owner', isEqualTo: currentUser.uid).get();

      final collaboratorNotesSnapshot =
          await notesRef
              .where('collaborators', arrayContains: currentUser.uid)
              .get();

      // Combine both query results
      final allNotes = [
        ...notesSnapshot.docs,
        ...collaboratorNotesSnapshot.docs,
      ];

      // Update each note that contains the label
      for (var doc in allNotes) {
        final noteData = doc.data();
        if (noteData['labels'] != null) {
          List<String> noteLabels = List<String>.from(noteData['labels']);
          if (noteLabels.contains(labelName)) {
            noteLabels.remove(labelName);
            await doc.reference.update({
              'labels': noteLabels,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }
      }

      debugPrint('✅ Label "$labelName" deleted and removed from all notes');
    } catch (e) {
      debugPrint('❌ Error deleting label: $e');
      rethrow;
    }
  }
}

class Label {
  final String id;
  final String name;

  Label({required this.id, required this.name});

  factory Label.fromJson(Map<String, dynamic> json) =>
      Label(id: json['id'], name: json['name']);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}
