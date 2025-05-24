// ignore_for_file: deprecated_member_use, use_build_context_synchronously, unused_element, unused_local_variable

import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_image_gallery_saver/flutter_image_gallery_saver.dart';
import 'package:pencraftpro/drawing/SavedDrawingPage.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

// Add these enums and classes
enum BrushType { normal, calligraphy, dotted, airbrush, marker }

// Update this enum to include all toolbar buttons and a none option
enum ActiveTool {
  none,
  brush,
  eraser,
  eyedropper,
  image,
  colorPicker,
  background,
  clear,
  undo,
  redo,
}

class DrawnLine {
  List<Offset> path;
  Color color;
  double width;
  BrushType brushType;
  int? seed;

  DrawnLine(this.path, this.color, this.width, this.brushType, {this.seed});

  Map<String, dynamic> toJson() => {
    'path': path.map((o) => {'dx': o.dx, 'dy': o.dy}).toList(),
    'color': color.value,
    'width': width,
    'brushType': brushType.index,
    'seed': seed,
  };

  static DrawnLine fromJson(Map<String, dynamic> json) => DrawnLine(
    (json['path'] as List)
        .map(
          (p) =>
              Offset((p['dx'] as num).toDouble(), (p['dy'] as num).toDouble()),
        )
        .toList(),
    Color(json['color']),
    (json['width'] as num).toDouble(),
    BrushType.values[json['brushType']],
    seed: json['seed'],
  );

  DrawnLine copyWith({
    List<Offset>? path,
    Color? color,
    double? width,
    BrushType? brushType,
    int? seed,
  }) {
    return DrawnLine(
      path ?? this.path,
      color ?? this.color,
      width ?? this.width,
      brushType ?? this.brushType,
      seed: seed ?? this.seed,
    );
  }
}

class DrawingCanvasPage extends StatefulWidget {
  final File? loadedImage;
  final String? customTitle;
  final double? initialOffsetX;
  final double? initialOffsetY;
  final double? initialScale;
  final DrawingState? initialState;

  const DrawingCanvasPage({
    super.key,
    this.loadedImage,
    this.customTitle,
    this.initialOffsetX,
    this.initialOffsetY,
    this.initialScale,
    this.initialState,
  });

  @override
  State<DrawingCanvasPage> createState() => _DrawingCanvasPageState();
}

class _DrawingCanvasPageState extends State<DrawingCanvasPage> {
  final GlobalKey _globalKey = GlobalKey();
  List<CanvasState> _history = [];
  int _currentHistoryIndex = -1;
  List<DrawnLine> _lines = [];
  DrawnLine? _currentLine;
  Color _selectedColor = Colors.black;
  double _strokeWidth = 4.0;
  double _eraserWidth = 4.0;
  bool _isErasing = false;
  Color? _backgroundColor;
  bool _isModified = false;
  ActiveTool _activeTool = ActiveTool.brush;

  List<ImageData> _images = [];
  int? _activeImageIndex;
  bool _isAdjustingImage = false;
  bool _isEyedropperActive = false;

  Offset _initialFocalPoint = Offset.zero;
  Offset _initialOffset = Offset.zero;
  double _initialScale = 1.0;
  Offset? _eraserPointerPosition;
  BrushType _currentBrushType = BrushType.normal;

  @override
  void initState() {
    super.initState();

    if (widget.initialState != null) {
      // If we have an initial state, load it
      _loadInitialState(widget.initialState!);
      _isModified = false; // Reset modified flag when loading existing state
    } else if (widget.loadedImage != null) {
      // Otherwise, load the image if provided
      _loadInitialImage(
        widget.loadedImage!,
        offsetX: widget.initialOffsetX,
        offsetY: widget.initialOffsetY,
        scale: widget.initialScale,
      );
      _isModified = false; // Reset modified flag when loading existing image
    }

    // Try to sync any pending drawings
    _syncToFirestore();
  }

  Future<void> _loadInitialImage(
    File imageFile, {
    double? offsetX,
    double? offsetY,
    double? scale,
  }) async {
    final data = await imageFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(data);
    final frame = await codec.getNextFrame();

    final screenSize = MediaQuery.of(context).size;
    final imageSize = Size(
      frame.image.width.toDouble(),
      frame.image.height.toDouble(),
    );

    final double usedScale =
        scale ?? (screenSize.width * 0.6) / imageSize.width;
    final Offset usedOffset = Offset(
      offsetX ?? (screenSize.width - (imageSize.width * usedScale)) / 2,
      offsetY ?? (screenSize.height - (imageSize.height * usedScale)) / 2,
    );

    setState(() {
      _images.add(
        ImageData(image: frame.image, offset: usedOffset, scale: usedScale),
      );
      _activeImageIndex = _images.length - 1;
      _isAdjustingImage = false;
      // Don't save initial state to history
      _history = [];
      _currentHistoryIndex = -1;
    });
  }

  Future<void> _loadInitialState(DrawingState state) async {
    // Load all images first
    final loadedImages = await Future.wait(
      state.images.map((imgData) async {
        final bytes = base64Decode(imgData['data']);
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        return ImageData(
          image: frame.image,
          offset: Offset(
            (imgData['offsetX'] as num).toDouble(),
            (imgData['offsetY'] as num).toDouble(),
          ),
          scale: (imgData['scale'] as num).toDouble(),
        );
      }),
    );

    setState(() {
      _lines = state.lines;
      _images = loadedImages;
      // Don't save initial state to history
      _history = [];
      _currentHistoryIndex = -1;
      _isModified = false; // Set to false when loading existing drawing
    });
    _saveState(
      markModified: false,
    ); // Save initial state but don't mark as modified
  }

  Future<void> _loadDrawingState() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = widget.loadedImage!.path
          .split('/')
          .last
          .replaceAll('.png', '');
      final statePath = '${directory.path}/$fileName.json';

      if (await File(statePath).exists()) {
        final file = File(statePath);
        final jsonString = await file.readAsString();
        final json = jsonDecode(jsonString);
        final state = await DrawingState.fromJson(json);

        // Load all images first
        final loadedImages = await Future.wait(
          state.images.map((imgData) async {
            final bytes = base64Decode(imgData['data']);
            final codec = await ui.instantiateImageCodec(bytes);
            final frame = await codec.getNextFrame();
            return ImageData(
              image: frame.image,
              offset: Offset(
                (imgData['offsetX'] as num).toDouble(),
                (imgData['offsetY'] as num).toDouble(),
              ),
              scale: (imgData['scale'] as num).toDouble(),
            );
          }),
        );

        setState(() {
          _lines = state.lines;
          _images = loadedImages;
        });
      }
    } catch (e) {
      print('Failed to load drawing state: $e');
      // Don't show error to user as this is just an enhancement
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_backgroundColor == null) {
      _backgroundColor = Theme.of(context).scaffoldBackgroundColor;
      _saveState(
        markModified: false,
      ); // Set to false so initial background color doesn't count as a modification
    }
  }

  @override
  void dispose() {
    for (var image in _images) {
      image.image.dispose();
    }
    super.dispose();
  }

  void _saveState({bool markModified = true}) {
    // Create current state
    final currentState = CanvasState(
      lines: List.from(_lines.map((l) => l.copyWith())),
      backgroundColor: _backgroundColor!,
      images: List.from(
        _images.map(
          (img) =>
              ImageData(image: img.image, offset: img.offset, scale: img.scale),
        ),
      ),
    );

    // If this is the first state, just add it
    if (_history.isEmpty) {
      _history.add(currentState);
      _currentHistoryIndex = 0;
      if (markModified) {
        setState(() {
          _isModified = true;
          print('Drawing modified: [32m[1m[4m[7m$_isModified[0m');
        });
      }
      return;
    }

    // Prevent duplicate states
    if (_currentHistoryIndex >= 0) {
      final last = _history[_currentHistoryIndex];
      if (_areCanvasStatesEqual(last, currentState)) {
        return;
      }
    }

    // Remove any future states if we're not at the end
    if (_currentHistoryIndex < _history.length - 1) {
      _history = _history.sublist(0, _currentHistoryIndex + 1);
    }

    // Add new state
    _history.add(currentState);
    _currentHistoryIndex++;
    if (markModified) {
      setState(() {
        _isModified = true;
        print('Drawing modified: $_isModified');
      });
    }

    // Limit history size
    if (_history.length > 50) {
      // Dispose images not referenced in any remaining history state
      final allImages = <ui.Image>{};
      for (final state in _history) {
        for (final img in state.images) {
          allImages.add(img.image);
        }
      }
      final toDispose = <ui.Image>[];
      for (final img in _images) {
        if (!allImages.contains(img.image)) {
          toDispose.add(img.image);
        }
      }
      for (final img in toDispose) {
        img.dispose();
      }
      _history.removeAt(0);
      _currentHistoryIndex--;
    }
  }

  // Helper to compare two CanvasState objects (shallow compare)
  bool _areCanvasStatesEqual(CanvasState a, CanvasState b) {
    if (a.lines.length != b.lines.length ||
        a.backgroundColor != b.backgroundColor ||
        a.images.length != b.images.length) {
      return false;
    }
    // Compare lines
    for (int i = 0; i < a.lines.length; i++) {
      if (a.lines[i].color != b.lines[i].color ||
          a.lines[i].width != b.lines[i].width ||
          a.lines[i].brushType != b.lines[i].brushType ||
          a.lines[i].path.length != b.lines[i].path.length ||
          a.lines[i].seed != b.lines[i].seed) {
        return false;
      }
      for (int j = 0; j < a.lines[i].path.length; j++) {
        if (a.lines[i].path[j] != b.lines[i].path[j]) return false;
      }
    }
    // Compare images (by offset/scale only)
    for (int i = 0; i < a.images.length; i++) {
      if (a.images[i].offset != b.images[i].offset ||
          a.images[i].scale != b.images[i].scale) {
        return false;
      }
    }
    return true;
  }

  void _undo() {
    if (_currentHistoryIndex > 0) {
      setState(() {
        _currentHistoryIndex--;
        _applyState(_history[_currentHistoryIndex]);
      });
    }
  }

  void _redo() {
    if (_currentHistoryIndex < _history.length - 1) {
      setState(() {
        _currentHistoryIndex++;
        _applyState(_history[_currentHistoryIndex]);
      });
    }
  }

  void _applyState(CanvasState state) {
    setState(() {
      _lines = List.from(state.lines.map((l) => l.copyWith()));
      _backgroundColor = state.backgroundColor;
      _images = List.from(
        state.images.map(
          (img) =>
              ImageData(image: img.image, offset: img.offset, scale: img.scale),
        ),
      );
      _currentLine = null;
      _isAdjustingImage = false;
      _activeImageIndex = null;
      _saveState();
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (_isEyedropperActive) {
      return; // Eyedropper takes precedence
    }

    if (_isErasing) {
      setState(() {
        _eraserPointerPosition = details.localFocalPoint;
      });
    }
    if (_isAdjustingImage && _activeImageIndex != null) {
      _initialFocalPoint = details.focalPoint;
      _initialOffset = _images[_activeImageIndex!].offset;
      _initialScale = _images[_activeImageIndex!].scale;
    } else if (!_isErasing) {
      _startDrawing(details.localFocalPoint);
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_isEyedropperActive) return;

    if (_isErasing) {
      setState(() {
        _eraserPointerPosition = details.localFocalPoint;
      });
      _erase(details.localFocalPoint);
      return;
    }
    if (_isAdjustingImage && _activeImageIndex != null) {
      setState(() {
        _images[_activeImageIndex!].scale = _initialScale * details.scale;
        _images[_activeImageIndex!].offset =
            _initialOffset + (details.focalPoint - _initialFocalPoint);
      });
    } else if (!_isErasing) {
      _keepDrawing(details.localFocalPoint);
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_isEyedropperActive) return;

    if (_isErasing) {
      setState(() {
        _eraserPointerPosition = null;
      });
    }
    if (_isAdjustingImage && _activeImageIndex != null) {
      _saveState();
    } else if (!_isAdjustingImage) {
      _endDrawing();
    }
  }

  void _startDrawing(Offset position) {
    if (!_isAdjustingImage) {
      setState(() {
        _currentLine = DrawnLine(
          [position],
          _selectedColor,
          _strokeWidth,
          _currentBrushType,
          seed:
              DateTime.now().millisecondsSinceEpoch +
              position.dx.toInt() +
              position.dy.toInt(),
        );
      });
    }
  }

  void _keepDrawing(Offset position) {
    if (!_isAdjustingImage && _currentLine != null) {
      setState(() {
        if (_currentLine!.path.isEmpty ||
            (_currentLine!.path.last - position).distance > 2.0) {
          _currentLine!.path.add(position);
        }
      });
    }
  }

  void _erase(Offset position) {
    setState(() {
      List<DrawnLine> newLines = [];
      for (var line in _lines) {
        List<Offset> remaining = [];
        bool inErasedSegment = false;
        for (int i = 0; i < line.path.length; i++) {
          if ((line.path[i] - position).distance < _eraserWidth / 2) {
            inErasedSegment = true;
            if (remaining.isNotEmpty) {
              newLines.add(
                DrawnLine(
                  List.from(remaining),
                  line.color,
                  line.width,
                  line.brushType,
                  seed: line.seed,
                ),
              );
              remaining.clear();
            }
          } else {
            remaining.add(line.path[i]);
          }
        }
        if (remaining.isNotEmpty) {
          newLines.add(
            DrawnLine(
              List.from(remaining),
              line.color,
              line.width,
              line.brushType,
              seed: line.seed,
            ),
          );
        }
      }
      _lines = newLines;
      _saveState();
    });
  }

  void _endDrawing() {
    setState(() {
      if (_currentLine != null) {
        _lines.add(_currentLine!);
        _currentLine = null;
        _saveState();
      }
    });
  }

  Future<bool> _isAndroid13OrAbove() async {
    if (Platform.isAndroid) {
      try {
        var androidInfo = await DeviceInfoPlugin().androidInfo;
        return androidInfo.version.sdkInt >= 33;
      } catch (e) {
        return false;
      }
    }
    return false;
  }

  Future<ui.Image> _addWatermark(ui.Image image) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Draw the original image
    canvas.drawImage(image, Offset.zero, Paint());

    // Load the app icon
    final ByteData iconData = await rootBundle.load('assets/icon.png');
    final Uint8List iconBytes = iconData.buffer.asUint8List();
    final ui.Codec iconCodec = await ui.instantiateImageCodec(iconBytes);
    final ui.FrameInfo iconFrame = await iconCodec.getNextFrame();
    final ui.Image iconImage = iconFrame.image;

    // Sample background color at watermark position
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return image;

    // Sample color from bottom right corner
    final int x = (image.width - 50).clamp(0, image.width - 1).toInt();
    final int y = (image.height - 50).clamp(0, image.height - 1).toInt();
    final int offset = (y * image.width + x) * 4;
    final int r = byteData.getUint8(offset);
    final int g = byteData.getUint8(offset + 1);
    final int b = byteData.getUint8(offset + 2);

    // Calculate background brightness
    final double brightness = (r * 0.299 + g * 0.587 + b * 0.114) / 255;

    // Determine watermark colors based on background brightness
    final Color textColor = brightness > 0.5 ? Colors.black : Colors.white;

    // Add watermark text
    final textSpan = TextSpan(
      text: 'Made with PenCraft Pro',
      style: TextStyle(
        color: textColor.withOpacity(
          0.85,
        ), // Increased opacity for better visibility
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    // Calculate icon size
    final double iconSize = textPainter.height * 2.5;

    // Position watermark in bottom right corner with padding
    final textPosition = Offset(
      image.width - textPainter.width - 20,
      image.height - textPainter.height - 20,
    );

    // Position icon above text
    final iconPosition = Offset(
      textPosition.dx + (textPainter.width - iconSize) / 2,
      textPosition.dy - iconSize - 15,
    );

    // Draw icon with adjusted color
    canvas.drawImageRect(
      iconImage,
      Rect.fromLTWH(
        0,
        0,
        iconImage.width.toDouble(),
        iconImage.height.toDouble(),
      ),
      Rect.fromLTWH(iconPosition.dx, iconPosition.dy, iconSize, iconSize),
      Paint()
        ..color = textColor.withOpacity(
          0.85,
        ), // Increased opacity for better visibility
    );

    // Draw text
    textPainter.paint(canvas, textPosition);

    return await recorder.endRecording().toImage(image.width, image.height);
  }

  Future<void> _saveAsImage() async {
    try {
      RenderRepaintBoundary boundary =
          _globalKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);

      // Add watermark to the image
      final watermarkedImage = await _addWatermark(image);

      final byteData = await watermarkedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      final pngBytes = byteData!.buffer.asUint8List();

      await FlutterImageGallerySaver.saveImage(pngBytes);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Drawing saved to gallery.',
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
      print('Save failed: $e\n$stackTrace');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '❌ Save failed: $e.',
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

  Future<void> _importImage() async {
    try {
      final status = await Permission.photos.request();
      if (status.isGranted) {
        final picker = ImagePicker();
        final picked = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
        );

        if (picked != null) {
          final data = await picked.readAsBytes();
          final codec = await ui.instantiateImageCodec(data);
          final frame = await codec.getNextFrame();
          setState(() {
            _images.add(
              ImageData(image: frame.image, offset: Offset.zero, scale: 1.0),
            );

            final screenSize = MediaQuery.of(context).size;
            final imageSize = Size(
              frame.image.width.toDouble(),
              frame.image.height.toDouble(),
            );

            final scale = (screenSize.width * 0.6) / imageSize.width;
            final offset = Offset(
              (screenSize.width - (imageSize.width * scale)) / 2,
              (screenSize.height - (imageSize.height * scale)) / 2,
            );

            _activeImageIndex = _images.length - 1;
            _isAdjustingImage = true;
            _activeTool = ActiveTool.image;
            _isErasing = false;
            _isEyedropperActive = false;
            _images[_activeImageIndex!] = ImageData(
              image: frame.image,
              offset: offset,
              scale: scale,
            );
            _saveState();
          });
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Photo library permission denied.',
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
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to load image: $e.',
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

  Future<void> _takePicture() async {
    try {
      final status = await Permission.camera.request();
      if (status.isGranted) {
        final picker = ImagePicker();
        final picked = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1024,
          maxHeight: 1024,
        );
        if (picked != null) {
          final data = await picked.readAsBytes();
          final codec = await ui.instantiateImageCodec(data);
          final frame = await codec.getNextFrame();
          setState(() {
            _images.add(
              ImageData(image: frame.image, offset: Offset.zero, scale: 1.0),
            );

            final screenSize = MediaQuery.of(context).size;
            final imageSize = Size(
              frame.image.width.toDouble(),
              frame.image.height.toDouble(),
            );

            final scale = (screenSize.width * 0.6) / imageSize.width;
            final offset = Offset(
              (screenSize.width - (imageSize.width * scale)) / 2,
              (screenSize.height - (imageSize.height * scale)) / 2,
            );

            _activeImageIndex = _images.length - 1;
            _isAdjustingImage = true;
            _activeTool = ActiveTool.image;
            _isErasing = false;
            _isEyedropperActive = false;
            _images[_activeImageIndex!] = ImageData(
              image: frame.image,
              offset: offset,
              scale: scale,
            );
            _saveState();
          });
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Camera permission denied.',
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
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to take picture: $e.',
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

  void _removeImage(int index) {
    setState(() {
      _images[index].image.dispose();
      _images.removeAt(index);
      _isAdjustingImage = false;
      _activeImageIndex = null;
      _saveState();
    });
  }

  void _showColorPicker() {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Pick a Color'),
            content: SingleChildScrollView(
              child: BlockPicker(
                pickerColor: _selectedColor,
                onColorChanged: (color) {
                  setState(() {
                    _selectedColor = color;
                  });
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          ),
    );
  }

  void _showBrushSlider() {
    showModalBottomSheet(
      context: context,
      builder:
          (_) => StatefulBuilder(
            builder:
                (context, setModalState) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Brush size: ${_strokeWidth.toInt()}'),
                      Slider(
                        min: 1,
                        max: 20,
                        value: _strokeWidth,
                        onChanged: (value) {
                          setModalState(() {
                            setState(() {
                              _strokeWidth = value;
                            });
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text('Brush type:'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8.0,
                        runSpacing: 4.0,
                        children:
                            BrushType.values.map((BrushType type) {
                              return ChoiceChip(
                                label: Text(type.toString().split('.').last),
                                selected: _currentBrushType == type,
                                onSelected: (bool selected) {
                                  if (selected) {
                                    setModalState(() {
                                      setState(() {
                                        _currentBrushType = type;
                                      });
                                    });
                                  }
                                },
                              );
                            }).toList(),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  void _showEraserSlider() {
    showModalBottomSheet(
      context: context,
      builder:
          (_) => StatefulBuilder(
            builder:
                (context, setModalState) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Eraser size: ${_eraserWidth.toInt()}'),
                      Slider(
                        min: 1,
                        max: 50,
                        value: _eraserWidth,
                        onChanged: (value) {
                          setModalState(() {
                            setState(() {
                              _eraserWidth = value;
                            });
                          });
                        },
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  void _showBackgroundPicker() {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Background Color'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                BlockPicker(
                  pickerColor: _backgroundColor!,
                  onColorChanged: (color) {
                    setState(() {
                      _backgroundColor = color;
                      _saveState();
                    });
                  },
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
    );
  }

  void _clearCanvas() {
    // Remove the empty check here since the button will be disabled when empty
    setState(() {
      for (var image in _images) {
        image.image.dispose();
      }
      _lines.clear();
      _images.clear();
      _backgroundColor = Theme.of(context).scaffoldBackgroundColor;
      _currentLine = null;
      _isAdjustingImage = false;
      _activeImageIndex = null;
      _isModified =
          false; // Set modified flag to FALSE after clearing canvas - nothing to save
      _saveState(markModified: false); // Save state without marking as modified
    });

    // Show confirmation to user
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Canvas cleared.',
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

  Future<bool> _onWillPop() async {
    print('Checking will pop, isModified: $_isModified'); // Debug print

    // Don't show confirmation if the canvas is empty from the beginning (was never modified)
    bool isCanvasEmpty =
        _lines.isEmpty &&
        _images.isEmpty &&
        _backgroundColor == Theme.of(context).scaffoldBackgroundColor;

    if (_isModified) {
      final result = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text(
                'Exit Drawing',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: const Text(
                'You have unsaved changes. Would you like to save your drawing before exiting?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Save'),
                ),
              ],
            ),
      );

      if (result == true) {
        await _saveDrawingToLocal();
        if (!mounted) return false;
        Navigator.pop(context);
        return false;
      }
      return false; // Stay on the page if user cancels
    }
    return true; // Allow back navigation if no changes
  }

  Color get _iconColor => Theme.of(context).colorScheme.onSurface;

  Future<void> _saveDrawingToLocal() async {
    try {
      // First save the image
      RenderRepaintBoundary boundary =
          _globalKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'drawing_${DateTime.now().millisecondsSinceEpoch}';
      final filePath = '${directory.path}/$fileName.png';
      final file = File(filePath);
      await file.writeAsBytes(pngBytes);

      // Save the complete state
      final state = DrawingState(
        lines: _lines,
        backgroundColor: _backgroundColor!,
        images: await Future.wait(
          _images.map((img) async {
            final byteData = await img.image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            return {
              'data': base64Encode(byteData!.buffer.asUint8List()),
              'offsetX': img.offset.dx,
              'offsetY': img.offset.dy,
              'scale': img.scale,
            };
          }),
        ),
        title: widget.customTitle,
      );

      final stateJson = state.toJson();
      final statePath = '${directory.path}/$fileName.json';
      await File(statePath).writeAsString(jsonEncode(stateJson));

      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final savedDrawings = prefs.getStringList('saved_drawings') ?? [];
      if (savedDrawings.length >= 100) {
        savedDrawings.removeAt(savedDrawings.length - 1);
      }

      String drawingTitle =
          (widget.customTitle != null && widget.customTitle!.trim().isNotEmpty)
              ? widget.customTitle!
              : 'Edit Title Name';

      savedDrawings.insert(
        0,
        '$fileName|${DateTime.now().toIso8601String()}|$drawingTitle|${_images.isNotEmpty ? _images[0].offset.dx : 0}|${_images.isNotEmpty ? _images[0].offset.dy : 0}|${_images.isNotEmpty ? _images[0].scale : 1.0}',
      );
      await prefs.setStringList('saved_drawings', savedDrawings);

      setState(() {
        _isModified = false; // Reset modified flag after saving
        print('Drawing saved, isModified set to: $_isModified'); // Debug print
      });

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Drawing saved successfully.',
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

      // Try to sync to Firestore in the background without blocking
      _saveDrawingToFirestore(
        fileName,
        drawingTitle,
        stateJson,
        pngBytes,
      ).catchError((e) {
        print('Firestore sync failed (possibly offline): $e');
        // Don't show error to user as this is just a backup
      });

      // Update the saved drawings list in the parent page
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const SavedDrawingsPage()),
        );
      }

      return;
    } catch (e) {
      print('Save failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to save drawing: $e.',
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
      }
      return;
    }
  }

  Future<void> _saveDrawingToFirestore(
    String fileName,
    String title,
    Map<String, dynamic> stateJson,
    List<int> imageBytes,
  ) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('User not authenticated, skipping Firestore save');
        return;
      }

      // Fetch user data to include email and fullName
      String userEmail = user.email ?? '';
      String fullName = '';
      try {
        final userDoc =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get();

        if (userDoc.exists) {
          final userData = userDoc.data()!;
          fullName = userData['fullName'] ?? '';
          // Use the stored email if available, otherwise use the auth email
          userEmail = userData['email'] ?? userEmail;
        }
      } catch (e) {
        print('Error fetching user data: $e');
        // Continue with sync even if user data fetch fails
      }

      // Add to sync queue
      final prefs = await SharedPreferences.getInstance();
      final syncQueue = prefs.getStringList('firestore_sync_queue') ?? [];
      syncQueue.add(
        jsonEncode({
          'fileName': fileName,
          'title': title,
          'state': stateJson,
          'imageData': base64Encode(imageBytes),
          'timestamp': DateTime.now().toIso8601String(),
          'email': userEmail,
          'fullName': fullName,
        }),
      );
      await prefs.setStringList('firestore_sync_queue', syncQueue);

      // Try to sync immediately
      await _syncToFirestore();
    } catch (e) {
      print('Failed to save to Firestore: $e');
      // Don't show error to user as this is just a backup
    }
  }

  Future<void> _syncToFirestore() async {
    final prefs = await SharedPreferences.getInstance();
    final syncQueue = prefs.getStringList('firestore_sync_queue') ?? [];
    if (syncQueue.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('User not authenticated, skipping Firestore sync');
      return;
    }

    // Fetch user data to include email and fullName
    String userEmail = user.email ?? '';
    String fullName = '';
    try {
      final userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

      if (userDoc.exists) {
        final userData = userDoc.data()!;
        fullName = userData['fullName'] ?? '';
        // Use the stored email if available, otherwise use the auth email
        userEmail = userData['email'] ?? userEmail;
      }
    } catch (e) {
      print('Error fetching user data: $e');
      // Continue with sync even if user data fetch fails
    }

    final updatedQueue = <String>[];
    for (final item in syncQueue) {
      try {
        final data = jsonDecode(item) as Map<String, dynamic>;

        // Use email and fullName from data if available, otherwise use the ones fetched above
        final String drawingEmail = data['email'] ?? userEmail;
        final String drawingFullName = data['fullName'] ?? fullName;

        await FirebaseFirestore.instance
            .collection('drawings')
            .doc(data['fileName'])
            .set({
              'title': data['title'],
              'imageData': data['imageData'],
              'createdAt': FieldValue.serverTimestamp(),
              'state': data['state'],
              'uid': user.uid,
              'email': drawingEmail,
              'fullName': drawingFullName,
            });
        print('Successfully synced drawing ${data['fileName']} to Firestore');
      } catch (e) {
        print('Failed to sync drawing: $e');
        // Keep failed items in the queue
        updatedQueue.add(item);
      }
    }

    // Update the queue with remaining items
    await prefs.setStringList('firestore_sync_queue', updatedQueue);
  }

  Future<void> _loadDrawingFromFirestore(String drawingId) async {
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
        return;
      }

      // Check if user has access to this drawing
      final data = doc.data()!;
      if (data['uid'] != user.uid) {
        print('User does not have access to this drawing');
        return;
      }

      final state = await DrawingState.fromJson(data['state']);

      // Load all images first
      final loadedImages = await Future.wait(
        state.images.map((imgData) async {
          final bytes = base64Decode(imgData['data']);
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          return ImageData(
            image: frame.image,
            offset: Offset(
              (imgData['offsetX'] as num).toDouble(),
              (imgData['offsetY'] as num).toDouble(),
            ),
            scale: (imgData['scale'] as num).toDouble(),
          );
        }),
      );

      setState(() {
        _lines = state.lines;
        _images = loadedImages;
      });

      print('Successfully loaded drawing from Firestore');
    } catch (e) {
      print('Failed to load from Firestore: $e');
      // Don't show error to user as this is just a backup
    }
  }

  Future<void> _pickColorFromCanvas(Offset position) async {
    if (_globalKey.currentContext == null) return;

    try {
      RenderRepaintBoundary boundary =
          _globalKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);

      final int x = position.dx.clamp(0, image.width - 1).toInt();
      final int y = position.dy.clamp(0, image.height - 1).toInt();

      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      image.dispose(); // Dispose the image resource

      if (byteData == null) return;

      final offset = (y * image.width + x) * 4;
      final r = byteData.getUint8(offset);
      final g = byteData.getUint8(offset + 1);
      final b = byteData.getUint8(offset + 2);
      // final a = byteData.getUint8(offset + 3); // Alpha could be used if needed

      setState(() {
        _selectedColor = Color.fromRGBO(r, g, b, 1.0);
        _isEyedropperActive = false;
        _isErasing = false; // Ensure drawing mode is active
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Color picked: R:$r, G:$g, B:$b.',
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
      print('Error picking color: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error picking color: $e.',
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
      }
      setState(() {
        _isEyedropperActive = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final errorColor = theme.colorScheme.error;
    final onErrorColor = theme.colorScheme.onError;

    // Check if there's content to clear - for the clear button
    bool hasContent =
        _lines.isNotEmpty ||
        _images.isNotEmpty ||
        (_backgroundColor != null &&
            _backgroundColor != theme.scaffoldBackgroundColor);

    return WillPopScope(
      onWillPop: _onWillPop,
      child: TooltipTheme(
        data: TooltipThemeData(
          textStyle: TextStyle(color: theme.colorScheme.secondary),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border.fromBorderSide(
              BorderSide(color: theme.colorScheme.secondary),
            ),
          ),
        ),
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              'Draw',
              style: TextStyle(color: theme.colorScheme.onPrimary),
            ),
            backgroundColor: theme.colorScheme.primary,
            leading: IconButton(
              icon: Icon(Icons.home, color: theme.colorScheme.onPrimary),
              onPressed: () async {
                if (await _onWillPop()) {
                  Navigator.pop(context);
                }
              },
            ),
            actions: [
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: theme.colorScheme.onPrimary),
                onSelected: (value) async {
                  if (value == 'saved') {
                    final shouldSave = await showDialog<bool>(
                      context: context,
                      builder:
                          (context) => AlertDialog(
                            title: const Text(
                              'Save Drawing',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            content: const Text(
                              'Do you want to save your drawing now?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: TextButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Save'),
                              ),
                            ],
                          ),
                    );

                    if (shouldSave == true) {
                      await _saveDrawingToLocal();
                      if (!mounted) return;
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SavedDrawingsPage(),
                        ),
                      );
                    }
                  }

                  if (value == 'import') _importImage();
                  if (value == 'camera') _takePicture();
                  if (value == 'save') _saveAsImage();
                },
                itemBuilder:
                    (_) => const [
                      PopupMenuItem(
                        value: 'saved',
                        child: Text('Save Drawing'),
                      ),
                      PopupMenuItem(
                        value: 'import',
                        child: Text('Import Image'),
                      ),
                      PopupMenuItem(
                        value: 'camera',
                        child: Text('Take Picture'),
                      ),
                      PopupMenuItem(value: 'save', child: Text('Save as PNG')),
                    ],
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: RepaintBoundary(
                  key: _globalKey,
                  child: Stack(
                    children: [
                      GestureDetector(
                        onScaleStart: _onScaleStart,
                        onScaleUpdate: _onScaleUpdate,
                        onScaleEnd: _onScaleEnd,
                        onTapDown: (details) async {
                          if (_isEyedropperActive) {
                            await _pickColorFromCanvas(details.localPosition);
                            return;
                          }
                          for (int i = _images.length - 1; i >= 0; i--) {
                            final image = _images[i];
                            final imageRect = Rect.fromLTWH(
                              image.offset.dx,
                              image.offset.dy,
                              image.image.width.toDouble() * image.scale,
                              image.image.height.toDouble() * image.scale,
                            );
                            final xButtonRect = Rect.fromLTWH(
                              imageRect.right - 30,
                              imageRect.top,
                              30,
                              30,
                            );
                            if (xButtonRect.contains(details.localPosition) &&
                                _isAdjustingImage &&
                                _activeImageIndex == i) {
                              _removeImage(i);
                              return;
                            } else if (imageRect.contains(
                              details.localPosition,
                            )) {
                              setState(() {
                                _activeImageIndex = i;
                                _isAdjustingImage = true;
                              });
                              return;
                            }
                          }
                          setState(() {
                            _isAdjustingImage = false;
                            _activeImageIndex = null;
                          });
                        },
                        child: CustomPaint(
                          painter: DrawingPainter(
                            _lines,
                            _currentLine,
                            _images,
                            _activeImageIndex,
                            _isAdjustingImage,
                            _backgroundColor!,
                            primaryColor: primaryColor,
                            errorColor: errorColor,
                            onErrorColor: onErrorColor,
                          ),
                          child: Container(),
                        ),
                      ),
                      if (_isErasing && _eraserPointerPosition != null)
                        Builder(
                          builder: (context) {
                            double scale = 1.0;
                            if (_isAdjustingImage &&
                                _activeImageIndex != null &&
                                _activeImageIndex! < _images.length) {
                              scale = _images[_activeImageIndex!].scale;
                            }
                            final eraserVisualSize = _eraserWidth * scale;
                            return Positioned(
                              left:
                                  _eraserPointerPosition!.dx -
                                  eraserVisualSize / 2,
                              top:
                                  _eraserPointerPosition!.dy -
                                  eraserVisualSize / 2,
                              child: IgnorePointer(
                                child: Container(
                                  width: eraserVisualSize,
                                  height: eraserVisualSize,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.grey.shade700,
                                      width: 1.5,
                                    ),
                                    color: Colors.grey.withOpacity(0.18),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
              Container(
                color: theme.colorScheme.surface,
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 8,
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Tooltip(
                        message: 'Undo',
                        child: IconButton(
                          icon: Icon(
                            Icons.undo,
                            color:
                                _activeTool == ActiveTool.undo
                                    ? primaryColor
                                    : _iconColor,
                          ),
                          onPressed: () {
                            setState(() {
                              _activeTool = ActiveTool.undo;
                            });
                            _undo();
                          },
                        ),
                      ),
                      Tooltip(
                        message: 'Redo',
                        child: IconButton(
                          icon: Icon(
                            Icons.redo,
                            color:
                                _activeTool == ActiveTool.redo
                                    ? primaryColor
                                    : _iconColor,
                          ),
                          onPressed: () {
                            setState(() {
                              _activeTool = ActiveTool.redo;
                            });
                            _redo();
                          },
                        ),
                      ),
                      Tooltip(
                        message: 'Brush',
                        child: IconButton(
                          icon: Icon(
                            Icons.brush,
                            color:
                                _activeTool == ActiveTool.brush
                                    ? primaryColor
                                    : _iconColor,
                          ),
                          onPressed: () {
                            setState(() {
                              _activeTool = ActiveTool.brush;
                              _isErasing = false;
                              _isEyedropperActive = false;
                              _isAdjustingImage = false;
                            });
                            _showBrushSlider();
                          },
                        ),
                      ),
                      Tooltip(
                        message: 'Pick Color',
                        child: IconButton(
                          icon: Icon(
                            Icons.color_lens,
                            color:
                                _activeTool == ActiveTool.colorPicker
                                    ? primaryColor
                                    : _iconColor,
                          ),
                          onPressed: () {
                            setState(() {
                              _activeTool = ActiveTool.colorPicker;
                              _isEyedropperActive = false;
                              _isErasing = false;
                              _isAdjustingImage = false;
                            });
                            _showColorPicker();
                          },
                        ),
                      ),
                      Tooltip(
                        message: 'Eraser',
                        child: IconButton(
                          icon: Icon(
                            Icons.cleaning_services,
                            color:
                                _activeTool == ActiveTool.eraser
                                    ? primaryColor
                                    : _iconColor,
                          ),
                          onPressed: () {
                            setState(() {
                              _activeTool = ActiveTool.eraser;
                              _isErasing = true;
                              _isEyedropperActive = false;
                              _isAdjustingImage = false;
                            });
                            _showEraserSlider();
                          },
                        ),
                      ),
                      Tooltip(
                        message: 'Eyedropper',
                        child: IconButton(
                          icon: Icon(
                            Icons.colorize,
                            color:
                                _activeTool == ActiveTool.eyedropper
                                    ? primaryColor
                                    : _iconColor,
                          ),
                          onPressed: () {
                            setState(() {
                              _activeTool = ActiveTool.eyedropper;
                              _isEyedropperActive = !_isEyedropperActive;
                              if (_isEyedropperActive) {
                                _isErasing = false;
                                _isAdjustingImage = false;
                              }
                            });
                          },
                        ),
                      ),
                      Tooltip(
                        message: 'Background',
                        child: IconButton(
                          icon: Icon(
                            Icons.format_color_fill,
                            color:
                                _activeTool == ActiveTool.background
                                    ? primaryColor
                                    : _iconColor,
                          ),
                          onPressed: () {
                            setState(() {
                              _activeTool = ActiveTool.background;
                              _isEyedropperActive = false;
                              _isErasing = false;
                              _isAdjustingImage = false;
                            });
                            _showBackgroundPicker();
                          },
                        ),
                      ),
                      Tooltip(
                        message: 'Clear',
                        child: IconButton(
                          icon: Icon(
                            Icons.clear,
                            color:
                                _activeTool == ActiveTool.clear && hasContent
                                    ? primaryColor
                                    : hasContent
                                    ? _iconColor
                                    : theme.disabledColor,
                          ),
                          onPressed:
                              hasContent
                                  ? () {
                                    setState(() {
                                      _activeTool = ActiveTool.clear;
                                    });
                                    _clearCanvas();
                                  }
                                  : null, // Disable button when no drawing or content
                        ),
                      ),
                      if (_images.isNotEmpty)
                        Tooltip(
                          message:
                              _isAdjustingImage
                                  ? 'Done Adjusting'
                                  : 'Edit Image',
                          child: IconButton(
                            icon: Icon(
                              _isAdjustingImage ? Icons.check : Icons.edit,
                              color:
                                  _activeTool == ActiveTool.image
                                      ? primaryColor
                                      : _iconColor,
                            ),
                            onPressed: () {
                              setState(() {
                                _activeTool = ActiveTool.image;
                                _isAdjustingImage = !_isAdjustingImage;
                                if (_isAdjustingImage) {
                                  _isErasing = false;
                                  _isEyedropperActive = false;
                                }
                              });
                            },
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
    );
  }
}

class DrawingPainter extends CustomPainter {
  final List<DrawnLine> lines;
  final DrawnLine? currentLine;
  final List<ImageData> images;
  final int? activeImageIndex;
  final bool isAdjustingImage;
  final Color backgroundColor;
  final Color primaryColor;
  final Color errorColor;
  final Color onErrorColor;

  DrawingPainter(
    this.lines,
    this.currentLine,
    this.images,
    this.activeImageIndex,
    this.isAdjustingImage,
    this.backgroundColor, {
    required this.primaryColor,
    required this.errorColor,
    required this.onErrorColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = backgroundColor;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    for (int i = 0; i < images.length; i++) {
      final image = images[i];
      final paint = Paint();
      final src = Rect.fromLTWH(
        0,
        0,
        image.image.width.toDouble(),
        image.image.height.toDouble(),
      );
      final imageWidth = image.image.width.toDouble() * image.scale;
      final imageHeight = image.image.height.toDouble() * image.scale;
      final dst = Rect.fromLTWH(
        image.offset.dx,
        image.offset.dy,
        imageWidth,
        imageHeight,
      );
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
      try {
        canvas.drawImageRect(image.image, src, dst, paint);
      } catch (e) {
        debugPrint('Error drawing image: $e');
      }

      if (i == activeImageIndex && isAdjustingImage) {
        final outlinePaint =
            Paint()
              ..color = primaryColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.0;
        canvas.drawRect(dst, outlinePaint);

        final highlightPaint =
            Paint()
              ..color = primaryColor.withOpacity(0.2)
              ..style = PaintingStyle.fill;
        canvas.drawRect(dst, highlightPaint);

        final xButtonPaint =
            Paint()
              ..color = errorColor
              ..style = PaintingStyle.fill;
        final xButtonRect = Rect.fromLTWH(dst.right - 30, dst.top, 30, 30);
        canvas.drawRect(xButtonRect, xButtonPaint);
        final xTextPainter = TextPainter(
          text: TextSpan(
            text: 'X',
            style: TextStyle(color: onErrorColor, fontSize: 20),
          ),
          textDirection: TextDirection.ltr,
        );
        xTextPainter.layout();
        xTextPainter.paint(
          canvas,
          Offset(xButtonRect.left + 8, xButtonRect.top + 5),
        );
      }

      canvas.restore();
    }

    for (var line in [...lines, if (currentLine != null) currentLine!]) {
      final paint =
          Paint()
            ..color = line.color
            ..strokeWidth = line.width
            ..style = PaintingStyle.stroke;

      // Apply brush type specifics
      switch (line.brushType) {
        case BrushType.normal:
          paint.strokeCap = StrokeCap.round;
          for (int i = 0; i < line.path.length - 1; i++) {
            canvas.drawLine(line.path[i], line.path[i + 1], paint);
          }
          break;
        case BrushType.calligraphy:
          paint.strokeCap = StrokeCap.square;
          for (int i = 0; i < line.path.length - 1; i++) {
            canvas.drawLine(line.path[i], line.path[i + 1], paint);
          }
          break;
        case BrushType.dotted:
          paint.strokeCap = StrokeCap.round;
          const double dotSpacing = 10.0;
          for (int i = 0; i < line.path.length - 1; i++) {
            final Offset p1 = line.path[i];
            final Offset p2 = line.path[i + 1];
            if (p1 == p2 && line.path.length == 1) {
              canvas.drawCircle(
                p1,
                line.width / 2,
                paint..style = PaintingStyle.fill,
              );
              break;
            }
            final double distance = (p2 - p1).distance;
            if (distance == 0) continue;
            final Offset direction = (p2 - p1) / distance;
            double currentDist = 0;
            while (currentDist < distance) {
              final Offset dotCenter = p1 + direction * currentDist;
              canvas.drawCircle(
                dotCenter,
                line.width / 2,
                paint..style = PaintingStyle.fill,
              );
              currentDist += line.width + dotSpacing;
            }
          }
          if (line.path.length == 1) {
            canvas.drawCircle(
              line.path[0],
              line.width / 2,
              paint..style = PaintingStyle.fill,
            );
          }
          paint.style = PaintingStyle.stroke;
          break;
        case BrushType.airbrush:
          paint.strokeCap = StrokeCap.round;
          const int density = 5;
          final double spreadFactor = line.width * 0.5;
          final random = math.Random(line.seed ?? 0);
          for (int i = 0; i < line.path.length; i++) {
            for (int j = 0; j < density; j++) {
              final double offsetX =
                  (random.nextDouble() - 0.5) * spreadFactor * 2;
              final double offsetY =
                  (random.nextDouble() - 0.5) * spreadFactor * 2;
              final Offset point = line.path[i] + Offset(offsetX, offsetY);
              final airbrushPaint =
                  Paint()
                    ..color = line.color.withOpacity(0.1)
                    ..style = PaintingStyle.fill;
              canvas.drawCircle(point, line.width / 2, airbrushPaint);
            }
          }
          break;
        case BrushType.marker:
          paint.strokeCap = StrokeCap.square;
          paint.color = line.color.withOpacity(0.5);
          final random = math.Random(line.seed ?? 0);
          for (int i = 0; i < line.path.length - 1; i++) {
            jitter() => (random.nextDouble() - 0.5) * line.width * 0.1;
            final p1 = line.path[i] + Offset(jitter(), jitter());
            final p2 = line.path[i + 1] + Offset(jitter(), jitter());
            canvas.drawLine(p1, p2, paint);
          }
          break;
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class ImageData {
  final ui.Image image;
  Offset offset;
  double scale;

  ImageData({required this.image, required this.offset, required this.scale});
}

class CanvasState {
  final List<DrawnLine> lines;
  final Color backgroundColor;
  final List<ImageData> images;

  CanvasState({
    required this.lines,
    required this.backgroundColor,
    required this.images,
  });
}

class DrawingState {
  final List<DrawnLine> lines;
  final Color backgroundColor;
  final List<Map<String, dynamic>> images;
  final String? title;
  final DateTime timestamp;

  DrawingState({
    required this.lines,
    required this.backgroundColor,
    required this.images,
    this.title,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'lines': lines.map((l) => l.toJson()).toList(),
    'backgroundColor': backgroundColor.value,
    'images': images,
    'title': title,
    'timestamp': timestamp.toIso8601String(),
  };

  static Future<DrawingState> fromJson(Map<String, dynamic> json) async {
    final List<Map<String, dynamic>> imageData =
        List<Map<String, dynamic>>.from(json['images']);
    final List<ImageData> images = [];

    for (var imgData in imageData) {
      final bytes = base64Decode(imgData['data']);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      images.add(
        ImageData(
          image: frame.image,
          offset: Offset(
            (imgData['offsetX'] as num).toDouble(),
            (imgData['offsetY'] as num).toDouble(),
          ),
          scale: (imgData['scale'] as num).toDouble(),
        ),
      );
    }

    return DrawingState(
      lines: (json['lines'] as List).map((l) => DrawnLine.fromJson(l)).toList(),
      backgroundColor: Color(json['backgroundColor']),
      images: imageData,
      title: json['title'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}
