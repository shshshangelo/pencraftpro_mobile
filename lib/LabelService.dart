import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

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

  static Future<void> deleteLabel(String id) async {
    final labels = await loadLabels();
    labels.removeWhere((label) => label.id == id);
    await saveLabels(labels);
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
