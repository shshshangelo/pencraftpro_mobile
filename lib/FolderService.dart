import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class FolderService {
  static const _key = 'folders';

  static Future<List<Folder>> loadFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final foldersJson = prefs.getString(_key);
    if (foldersJson == null) return [];
    final List decoded = jsonDecode(foldersJson);
    return decoded.map((e) => Folder.fromJson(e)).toList();
  }

  static Future<void> saveFolders(List<Folder> folders) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(folders.map((e) => e.toJson()).toList());
    await prefs.setString(_key, encoded);
  }

  static Future<void> addFolder(String name) async {
    final folders = await loadFolders();
    final newFolder = Folder(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
    );
    folders.add(newFolder);
    await saveFolders(folders);
  }
}

class Folder {
  final String id;
  final String name;

  Folder({required this.id, required this.name});

  factory Folder.fromJson(Map<String, dynamic> json) =>
      Folder(id: json['id'], name: json['name']);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}
