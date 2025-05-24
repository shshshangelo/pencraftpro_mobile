// ignore_for_file: library_private_types_in_public_api

import 'dart:io';
import 'package:flutter/material.dart';

class FullScreenGallery extends StatefulWidget {
  final List<String> imagePaths;
  final int initialIndex;

  const FullScreenGallery({
    super.key,
    required this.imagePaths,
    required this.initialIndex,
  });

  @override
  _FullScreenGalleryState createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<FullScreenGallery> {
  late PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.imagePaths.length,
        itemBuilder: (context, index) {
          final path = widget.imagePaths[index];
          return GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Center(
              child: Image.file(
                File(path),
                fit: BoxFit.contain,
                errorBuilder:
                    (context, error, stackTrace) => Icon(
                      Icons.broken_image,
                      size: 100,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          );
        },
      ),
    );
  }
}
