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

// Add these enums and classes
enum ShapeType { none, rectangle, circle, line }

enum BrushType { normal, calligraphy, dotted, airbrush, marker }

// Add this enum for font styles
enum FontStyleType { normal, bold, italic, boldItalic, monospace, cursive }

class DrawnShape {
  final ShapeType type;
  final Offset startPoint;
  final Offset endPoint;
  final Color color;
  final double strokeWidth;
  // Add other properties like fill color if needed later

  DrawnShape({
    required this.type,
    required this.startPoint,
    required this.endPoint,
    required this.color,
    required this.strokeWidth,
  });

  // Helper to create a copy with new points, useful for history
  DrawnShape copyWith({Offset? startPoint, Offset? endPoint}) {
    return DrawnShape(
      type: type,
      startPoint: startPoint ?? this.startPoint,
      endPoint: endPoint ?? this.endPoint,
      color: color,
      strokeWidth: strokeWidth,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.index,
    'startPoint': {'dx': startPoint.dx, 'dy': startPoint.dy},
    'endPoint': {'dx': endPoint.dx, 'dy': endPoint.dy},
    'color': color.value,
    'strokeWidth': strokeWidth,
  };

  static DrawnShape fromJson(Map<String, dynamic> json) => DrawnShape(
    type: ShapeType.values[json['type']],
    startPoint: Offset(
      (json['startPoint']['dx'] as num).toDouble(),
      (json['startPoint']['dy'] as num).toDouble(),
    ),
    endPoint: Offset(
      (json['endPoint']['dx'] as num).toDouble(),
      (json['endPoint']['dy'] as num).toDouble(),
    ),
    color: Color(json['color']),
    strokeWidth: (json['strokeWidth'] as num).toDouble(),
  );
}

// Add this class for Text elements
class DrawnText {
  final String text;
  final Offset position;
  final TextStyle style;
  final double fontSize;
  final Color color;
  final FontStyleType fontStyleType;

  DrawnText({
    required this.text,
    required this.position,
    required this.style,
    required this.fontSize,
    required this.color,
    this.fontStyleType = FontStyleType.normal,
  });

  DrawnText copyWith({
    String? text,
    Offset? position,
    TextStyle? style,
    double? fontSize,
    Color? color,
    FontStyleType? fontStyleType,
  }) {
    return DrawnText(
      text: text ?? this.text,
      position: position ?? this.position,
      style: style ?? this.style,
      fontSize: fontSize ?? this.fontSize,
      color: color ?? this.color,
      fontStyleType: fontStyleType ?? this.fontStyleType,
    );
  }

  Map<String, dynamic> toJson() => {
    'text': text,
    'position': {'dx': position.dx, 'dy': position.dy},
    'fontSize': fontSize,
    'color': color.value,
    'fontStyleType': fontStyleType.index,
  };

  static DrawnText fromJson(Map<String, dynamic> json) => DrawnText(
    text: json['text'],
    position: Offset(
      (json['position']['dx'] as num).toDouble(),
      (json['position']['dy'] as num).toDouble(),
    ),
    style: TextStyle(
      color: Color(json['color']),
      fontSize: (json['fontSize'] as num).toDouble(),
    ),
    fontSize: (json['fontSize'] as num).toDouble(),
    color: Color(json['color']),
    fontStyleType: FontStyleType.values[json['fontStyleType']],
  );
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
  List<DrawnShape> _shapes = [];
  List<DrawnText> _texts = []; // <-- Add this
  Color _selectedColor = Colors.black;
  double _strokeWidth = 4.0;
  double _eraserWidth = 4.0;
  bool _isErasing = false;
  Color? _backgroundColor;

  List<ImageData> _images = [];
  int? _activeImageIndex;
  bool _isAdjustingImage = false;
  bool _isEyedropperActive = false;

  // State for shape drawing
  ShapeType _currentShapeType = ShapeType.none;
  Offset? _shapeStartPoint;
  Offset? _currentShapePoint;
  bool _isDrawingShape = false;
  bool _isTextToolActive = false;
  BrushType _currentBrushType = BrushType.normal;

  Offset _initialFocalPoint = Offset.zero;
  Offset _initialOffset = Offset.zero;
  double _initialScale = 1.0;

  int? _selectedTextIndex;
  int? _editingTextIndex;
  TextEditingController? _editingTextController;
  FontStyleType _editingFontStyleType = FontStyleType.normal;
  double _editingFontSize = 32.0;
  Offset? _dragStartOffset;
  Offset? _textStartPosition;
  Offset? _eraserPointerPosition;

  @override
  void initState() {
    super.initState();

    if (widget.initialState != null) {
      // If we have an initial state, load it
      _loadInitialState(widget.initialState!);
    } else if (widget.loadedImage != null) {
      // Otherwise, load the image if provided
      _loadInitialImage(
        widget.loadedImage!,
        offsetX: widget.initialOffsetX,
        offsetY: widget.initialOffsetY,
        scale: widget.initialScale,
      );
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
      _shapes = state.shapes;
      _texts = state.texts;
      _backgroundColor = state.backgroundColor;
      _images = loadedImages;
      // Don't save initial state to history
      _history = [];
      _currentHistoryIndex = -1;
    });
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
          _shapes = state.shapes;
          _texts = state.texts;
          _backgroundColor = state.backgroundColor;
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
      _saveState();
    }
  }

  @override
  void dispose() {
    for (var image in _images) {
      image.image.dispose();
    }
    _editingTextController?.dispose();
    super.dispose();
  }

  void _saveState() {
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
      shapes: List.from(_shapes.map((s) => s.copyWith())),
      texts: List.from(_texts.map((t) => t.copyWith())),
    );

    // If this is the first state, just add it
    if (_history.isEmpty) {
      _history.add(currentState);
      _currentHistoryIndex = 0;
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
        a.images.length != b.images.length ||
        a.shapes.length != b.shapes.length ||
        a.texts.length != b.texts.length) {
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
    // Compare shapes
    for (int i = 0; i < a.shapes.length; i++) {
      if (a.shapes[i].type != b.shapes[i].type ||
          a.shapes[i].startPoint != b.shapes[i].startPoint ||
          a.shapes[i].endPoint != b.shapes[i].endPoint ||
          a.shapes[i].color != b.shapes[i].color ||
          a.shapes[i].strokeWidth != b.shapes[i].strokeWidth) {
        return false;
      }
    }
    // Compare texts
    for (int i = 0; i < a.texts.length; i++) {
      if (a.texts[i].text != b.texts[i].text ||
          a.texts[i].position != b.texts[i].position ||
          a.texts[i].fontSize != b.texts[i].fontSize ||
          a.texts[i].color != b.texts[i].color ||
          a.texts[i].fontStyleType != b.texts[i].fontStyleType) {
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
      _shapes = List.from(state.shapes.map((s) => s.copyWith()));
      _texts = List.from(state.texts.map((t) => t.copyWith()));
      _currentLine = null;
      _isAdjustingImage = false;
      _activeImageIndex = null;
      _isDrawingShape = false;
      _currentShapeType = ShapeType.none;
      _shapeStartPoint = null;
      _currentShapePoint = null;
      _selectedTextIndex = null;
      _editingTextIndex = null;
      _editingTextController?.dispose();
      _editingTextController = null;
      _isTextToolActive = false;
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (_isEyedropperActive || _isTextToolActive) {
      return; // Eyedropper or Text tool takes precedence
    }

    if (_isErasing) {
      setState(() {
        _eraserPointerPosition = details.localFocalPoint;
      });
    }
    if (_currentShapeType != ShapeType.none) {
      // Shape drawing mode
      setState(() {
        _isDrawingShape = true;
        _shapeStartPoint = details.localFocalPoint;
        _currentShapePoint = details.localFocalPoint;
        _isErasing = false;
        _isAdjustingImage = false;
        _currentLine = null; // Ensure not drawing lines
      });
    } else if (_isAdjustingImage && _activeImageIndex != null) {
      _initialFocalPoint = details.focalPoint;
      _initialOffset = _images[_activeImageIndex!].offset;
      _initialScale = _images[_activeImageIndex!].scale;
    } else if (!_isErasing) {
      _startDrawing(details.localFocalPoint);
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_isEyedropperActive || _isTextToolActive) return;

    if (_isErasing) {
      setState(() {
        _eraserPointerPosition = details.localFocalPoint;
      });
      _erase(details.localFocalPoint);
      return;
    }
    if (_isDrawingShape && _shapeStartPoint != null) {
      setState(() {
        _currentShapePoint = details.localFocalPoint;
      });
    } else if (_isAdjustingImage && _activeImageIndex != null) {
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
    if (_isEyedropperActive || _isTextToolActive) return;

    if (_isErasing) {
      setState(() {
        _eraserPointerPosition = null;
      });
    }
    if (_isDrawingShape &&
        _shapeStartPoint != null &&
        _currentShapePoint != null) {
      setState(() {
        final newShape = DrawnShape(
          type: _currentShapeType,
          startPoint: _shapeStartPoint!,
          endPoint: _currentShapePoint!,
          color: _selectedColor,
          strokeWidth: _strokeWidth,
        );
        _shapes.add(newShape);
        _isDrawingShape = false;
        _shapeStartPoint = null;
        _currentShapePoint = null;
        _saveState();
      });
    } else if (_isAdjustingImage && _activeImageIndex != null) {
      _saveState();
    } else if (!_isAdjustingImage) {
      _endDrawing();
    } else {
      // For image adjustment, state is saved when "Done Adjusting" is tapped or another tool is selected
      // _saveState(); // Consider if needed here or handled by other interactions
    }
  }

  void _startDrawing(Offset position) {
    if (!_isAdjustingImage &&
        _currentShapeType == ShapeType.none &&
        !_isTextToolActive) {
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
    if (!_isAdjustingImage &&
        _currentLine != null &&
        _currentShapeType == ShapeType.none &&
        !_isTextToolActive) {
      // Only draw if not in shape mode
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

  Future<void> _saveAsImage() async {
    PermissionStatus status;
    if (Platform.isAndroid && await _isAndroid13OrAbove()) {
      status = await Permission.photos.request();
    } else {
      status = await Permission.storage.request();
    }

    if (!status.isGranted) {
      if (status.isPermanentlyDenied) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Storage or Photos permission permanently denied. Please enable in settings.',
            ),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () => openAppSettings(),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Storage or Photos permission denied.')),
        );
      }
      return;
    }

    try {
      RenderRepaintBoundary boundary =
          _globalKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();
      print('PNG bytes length: ${pngBytes.length}');

      final cleanTitle = (widget.customTitle ?? 'drawing').trim().replaceAll(
        RegExp(r'\\s+'),
        '',
      );
      final fileName = '${cleanTitle}_${DateTime.now().millisecondsSinceEpoch}';

      await FlutterImageGallerySaver.saveImage(pngBytes);

      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final savedDrawings = prefs.getStringList('saved_drawings') ?? [];
      print('Before saving to SharedPreferences: $savedDrawings');
      if (savedDrawings.length >= 100) {
        savedDrawings.removeAt(savedDrawings.length - 1);
      }
      // Get current image offset and scale
      final img = _images.isNotEmpty ? _images[0] : null;
      final offsetX = img?.offset.dx ?? 0;
      final offsetY = img?.offset.dy ?? 0;
      final scale = img?.scale ?? 1.0;
      // Generate automatic name if customTitle is null or empty
      String drawingTitle =
          (widget.customTitle != null && widget.customTitle!.trim().isNotEmpty)
              ? widget.customTitle!
              : 'Drawing ${savedDrawings.length + 1}';
      savedDrawings.insert(
        0,
        '$fileName|${DateTime.now().toIso8601String()}|$drawingTitle|$offsetX|$offsetY|$scale',
      );
      bool success = await prefs.setStringList('saved_drawings', savedDrawings);
      print('SharedPreferences save success: $success');
      print(
        'After saving to SharedPreferences: ${prefs.getStringList('saved_drawings')}',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Drawing saved to gallery.')),
      );
    } catch (e, stackTrace) {
      print('Save failed: $e\n$stackTrace');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('❌ Save failed: $e')));
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
          const SnackBar(content: Text('Photo library permission denied.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load image: $e')));
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
          const SnackBar(content: Text('Camera permission denied.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to take picture: $e')));
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
            content: BlockPicker(
              pickerColor: _backgroundColor!,
              onColorChanged: (color) {
                setState(() {
                  _backgroundColor = color;
                  _saveState();
                });
              },
            ),
          ),
    );
  }

  void _clearCanvas() {
    setState(() {
      for (var image in _images) {
        image.image.dispose();
      }
      _lines.clear();
      _images.clear();
      _shapes.clear();
      _texts.clear(); // <-- Add this
      _backgroundColor = Theme.of(context).scaffoldBackgroundColor;
      _currentLine = null;
      _isAdjustingImage = false;
      _activeImageIndex = null;
      _isDrawingShape = false;
      _currentShapeType = ShapeType.none;
      _shapeStartPoint = null;
      _currentShapePoint = null;
      _isTextToolActive = false; // <-- Add this
      _saveState();
    });
  }

  Future<bool> _onWillPop() async {
    // Only show save dialog if there are actual changes (more than just the initial state)
    if (_history.length > 1) {
      final result = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Save Drawing?'),
              content: const Text(
                'Do you want to save your drawing before exiting?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.green,
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
      } else {
        return false;
      }
    }
    return true;
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
        shapes: _shapes,
        texts: _texts,
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
              : 'Drawing ${savedDrawings.length + 1}';

      savedDrawings.insert(
        0,
        '$fileName|${DateTime.now().toIso8601String()}|$drawingTitle|${_images.isNotEmpty ? _images[0].offset.dx : 0}|${_images.isNotEmpty ? _images[0].offset.dy : 0}|${_images.isNotEmpty ? _images[0].scale : 1.0}',
      );
      await prefs.setStringList('saved_drawings', savedDrawings);

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Drawing saved successfully.')),
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

      // Return true to indicate successful save
      return;
    } catch (e) {
      print('Save failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save drawing: $e')));
      }
      // Return false to indicate save failed
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

    final updatedQueue = <String>[];
    for (final item in syncQueue) {
      try {
        final data = jsonDecode(item) as Map<String, dynamic>;
        await FirebaseFirestore.instance
            .collection('drawings')
            .doc(data['fileName'])
            .set({
              'title': data['title'],
              'imageData': data['imageData'],
              'createdAt': FieldValue.serverTimestamp(),
              'state': data['state'],
              'uid': user.uid,
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
        _shapes = state.shapes;
        _texts = state.texts;
        _backgroundColor = state.backgroundColor;
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
              'Color picked: R:$r, G:$g, B:$b',
              style: TextStyle(
                color:
                    _selectedColor.computeLuminance() > 0.5
                        ? Colors.black
                        : Colors.white,
              ),
            ),
            backgroundColor: _selectedColor,
          ),
        );
      }
    } catch (e) {
      print('Error picking color: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('❌ Error picking color: $e')));
      }
      setState(() {
        _isEyedropperActive = false;
      });
    }
  }

  // Helper to get TextStyle from FontStyleType
  TextStyle _getTextStyle(Color color, double fontSize, FontStyleType type) {
    switch (type) {
      case FontStyleType.bold:
        return TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        );
      case FontStyleType.italic:
        return TextStyle(
          color: color,
          fontSize: fontSize,
          fontStyle: FontStyle.italic,
        );
      case FontStyleType.boldItalic:
        return TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          fontStyle: FontStyle.italic,
        );
      case FontStyleType.monospace:
        return TextStyle(
          color: color,
          fontSize: fontSize,
          fontFamily: 'monospace',
        );
      case FontStyleType.cursive:
        return TextStyle(
          color: color,
          fontSize: fontSize,
          fontFamily: 'cursive',
        );
      case FontStyleType.normal:
      default:
        return TextStyle(color: color, fontSize: fontSize);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final errorColor = theme.colorScheme.error;
    final onErrorColor = theme.colorScheme.onError;

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
                            title: const Text('Save Drawing?'),
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
                                  backgroundColor: Colors.green,
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
                      PopupMenuItem(value: 'save', child: Text('Save as JPEG')),
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
                          // Instagram-like text tool logic
                          if (_isTextToolActive) {
                            // If already editing, do nothing
                            if (_editingTextIndex != null) return;
                            // Add new text at tap position and enter edit mode
                            setState(() {
                              final newText = DrawnText(
                                text: '',
                                position: details.localPosition,
                                style: _getTextStyle(
                                  _selectedColor,
                                  _editingFontSize,
                                  _editingFontStyleType,
                                ),
                                fontSize: _editingFontSize,
                                color: _selectedColor,
                                fontStyleType: _editingFontStyleType,
                              );
                              _texts.add(newText);
                              _editingTextIndex = _texts.length - 1;
                              _editingTextController = TextEditingController(
                                text: '',
                              );
                              _editingFontStyleType = FontStyleType.normal;
                              _editingFontSize = 32.0;
                              _selectedTextIndex = null;
                            });
                            return;
                          }
                          // Text selection logic
                          for (int i = _texts.length - 1; i >= 0; i--) {
                            final dtext = _texts[i];
                            final textSpan = TextSpan(
                              text: dtext.text,
                              style: dtext.style,
                            );
                            final textPainter = TextPainter(
                              text: textSpan,
                              textAlign: TextAlign.left,
                              textDirection: TextDirection.ltr,
                            );
                            textPainter.layout();
                            final rect = Rect.fromLTWH(
                              dtext.position.dx,
                              dtext.position.dy,
                              textPainter.width,
                              textPainter.height,
                            );
                            if (rect.contains(details.localPosition)) {
                              setState(() {
                                _selectedTextIndex = i;
                                _editingTextIndex = null;
                              });
                              return;
                            }
                          }
                          setState(() {
                            _selectedTextIndex = null;
                            _editingTextIndex = null;
                          });
                          if (_isEyedropperActive) {
                            await _pickColorFromCanvas(details.localPosition);
                            return;
                          }
                          if (_currentShapeType != ShapeType.none ||
                              _isDrawingShape) {
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
                            shapes: _shapes,
                            currentShapeType: _currentShapeType,
                            shapeStartPoint: _shapeStartPoint,
                            currentShapePoint: _currentShapePoint,
                            isDrawingShape: _isDrawingShape,
                            selectedColor: _selectedColor,
                            strokeWidth: _strokeWidth,
                            texts: _texts,
                          ),
                          child: Container(),
                        ),
                      ),
                      if (_editingTextIndex != null)
                        _buildInPlaceTextEditor(context, _editingTextIndex!),
                      if (_selectedTextIndex != null &&
                          _editingTextIndex == null)
                        _buildTextEditorOverlay(context, _selectedTextIndex!),
                      if (_isErasing && _eraserPointerPosition != null)
                        Builder(
                          builder: (context) {
                            double scale = 1.0;
                            // If adjusting an image, use its scale for eraser circle
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
                          icon: Icon(Icons.undo, color: _iconColor),
                          onPressed: _undo,
                        ),
                      ),
                      Tooltip(
                        message: 'Redo',
                        child: IconButton(
                          icon: Icon(Icons.redo, color: _iconColor),
                          onPressed: _redo,
                        ),
                      ),
                      Tooltip(
                        message: 'Brush',
                        child: IconButton(
                          icon: Icon(
                            Icons.brush,
                            color:
                                !_isErasing &&
                                        !_isDrawingShape &&
                                        !_isEyedropperActive &&
                                        _currentShapeType == ShapeType.none &&
                                        !_isTextToolActive
                                    ? _iconColor
                                    : Colors.grey,
                          ),
                          onPressed: () {
                            setState(() {
                              _isErasing = false;
                              _isEyedropperActive = false;
                              _isDrawingShape = false;
                              _currentShapeType = ShapeType.none;
                              _isAdjustingImage = false;
                            });
                            _showBrushSlider();
                          },
                        ),
                      ),
                      Tooltip(
                        message: 'Eraser',
                        child: IconButton(
                          icon: Icon(
                            Icons.cleaning_services,
                            color:
                                _isErasing && !_isEyedropperActive
                                    ? _iconColor
                                    : Colors.grey,
                          ),
                          onPressed: () {
                            setState(() {
                              _isErasing = true;
                              _isEyedropperActive = false;
                              _isDrawingShape = false;
                              _currentShapeType = ShapeType.none;
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
                                _isEyedropperActive ? primaryColor : _iconColor,
                          ),
                          onPressed: () {
                            setState(() {
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
                        message: 'Color',
                        child: IconButton(
                          icon: Icon(Icons.color_lens, color: _iconColor),
                          onPressed: () {
                            setState(() {
                              _isEyedropperActive = false;
                            });
                            _showColorPicker();
                          },
                        ),
                      ),
                      Tooltip(
                        message: 'Background',
                        child: IconButton(
                          icon: Icon(
                            Icons.format_color_fill,
                            color: _iconColor,
                          ),
                          onPressed: _showBackgroundPicker,
                        ),
                      ),
                      Tooltip(
                        message: 'Clear',
                        child: IconButton(
                          icon: Icon(Icons.clear, color: _iconColor),
                          onPressed: _clearCanvas,
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
                              color: _iconColor,
                            ),
                            onPressed:
                                () => setState(
                                  () => _isAdjustingImage = !_isAdjustingImage,
                                ),
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

  // In-place text editor overlay for Instagram-like editing
  Widget _buildInPlaceTextEditor(BuildContext context, int index) {
    final dtext = _texts[index];
    final textField = Material(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.8,
            ),
            child: TextField(
              controller: _editingTextController,
              autofocus: true,
              style: _getTextStyle(
                _selectedColor,
                _editingFontSize,
                _editingFontStyleType,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: 'Type something...',
              ),
              onChanged: (value) {
                setState(() {
                  _texts[index] = dtext.copyWith(
                    text: value,
                    style: _getTextStyle(
                      _selectedColor,
                      _editingFontSize,
                      _editingFontStyleType,
                    ),
                    fontSize: _editingFontSize,
                    color: _selectedColor,
                    fontStyleType: _editingFontStyleType,
                  );
                  _saveState();
                });
              },
              onEditingComplete: () {
                setState(() {
                  _editingTextIndex = null;
                  _editingTextController?.dispose();
                  _editingTextController = null;
                  _saveState();
                });
              },
              textInputAction: TextInputAction.done,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8.0,
            children:
                FontStyleType.values.map((type) {
                  return ChoiceChip(
                    label: Text(type.toString().split('.').last),
                    selected: _editingFontStyleType == type,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _editingFontStyleType = type;
                          _texts[index] = dtext.copyWith(
                            style: _getTextStyle(
                              _selectedColor,
                              _editingFontSize,
                              _editingFontStyleType,
                            ),
                            fontStyleType: _editingFontStyleType,
                          );
                          _saveState();
                        });
                      }
                    },
                  );
                }).toList(),
          ),
        ],
      ),
    );
    return Positioned(
      left: dtext.position.dx,
      top: dtext.position.dy,
      child: textField,
    );
  }

  // Overlay for selected text: move, resize, delete
  Widget _buildTextEditorOverlay(BuildContext context, int index) {
    final dtext = _texts[index];
    final textSpan = TextSpan(text: dtext.text, style: dtext.style);
    final textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    return Positioned(
      left: dtext.position.dx,
      top: dtext.position.dy,
      child: GestureDetector(
        onPanStart: (details) {
          _dragStartOffset = details.localPosition;
          _textStartPosition = dtext.position;
        },
        onPanUpdate: (details) {
          setState(() {
            _texts[index] = dtext.copyWith(
              position:
                  _textStartPosition! +
                  (details.localPosition - _dragStartOffset!),
            );
            _saveState();
          });
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: textPainter.width,
              height: textPainter.height,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blue, width: 1),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Text(
                        dtext.text,
                        style: dtext.style,
                        maxLines: null,
                        overflow: TextOverflow.visible,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: -20,
              top: -20,
              child: IconButton(
                icon: Icon(Icons.close, color: Colors.red),
                onPressed: () {
                  setState(() {
                    _texts.removeAt(index);
                    _selectedTextIndex = null;
                    _saveState();
                  });
                },
              ),
            ),
            Positioned(
              left: 0,
              bottom: -40,
              child: Row(
                children: [
                  Text('Size:'),
                  Slider(
                    min: 8,
                    max: 120,
                    value: dtext.fontSize,
                    onChanged: (value) {
                      setState(() {
                        _texts[index] = dtext.copyWith(
                          fontSize: value,
                          style: _getTextStyle(
                            dtext.color,
                            value,
                            dtext.fontStyleType,
                          ),
                        );
                        _saveState();
                      });
                    },
                    divisions: 56,
                  ),
                ],
              ),
            ),
          ],
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

  // Add these for shapes
  final List<DrawnShape> shapes;
  final ShapeType currentShapeType;
  final Offset? shapeStartPoint;
  final Offset? currentShapePoint;
  final bool isDrawingShape;
  final Color selectedColor; // For preview
  final double strokeWidth; // For preview

  // Add for Text
  final List<DrawnText> texts; // <-- Add this

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
    // Add these to constructor
    required this.shapes,
    required this.currentShapeType,
    this.shapeStartPoint,
    this.currentShapePoint,
    required this.isDrawingShape,
    required this.selectedColor,
    required this.strokeWidth,
    required this.texts, // <-- Add this
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
        // If the image is disposed or invalid, skip drawing it
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

      // Draw completed shapes
      for (var shape in shapes) {
        final shapePaint =
            Paint()
              ..color = shape.color
              ..strokeWidth = shape.strokeWidth
              ..style = PaintingStyle.stroke; // For now, all shapes are stroke

        _drawShape(
          canvas,
          shape.type,
          shape.startPoint,
          shape.endPoint,
          shapePaint,
        );
      }

      // Draw current in-progress shape (preview)
      if (isDrawingShape &&
          shapeStartPoint != null &&
          currentShapePoint != null &&
          currentShapeType != ShapeType.none) {
        final previewPaint =
            Paint()
              ..color =
                  selectedColor // Use current selected color for preview
              ..strokeWidth =
                  strokeWidth // Use current stroke width
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round;
        _drawShape(
          canvas,
          currentShapeType,
          shapeStartPoint!,
          currentShapePoint!,
          previewPaint,
        );
      }

      canvas.restore();
    }

    // Draw Texts
    for (final dtext in texts) {
      final textSpan = TextSpan(
        text: dtext.text,
        style: TextStyle(
          color: dtext.color,
          fontSize: dtext.fontSize,
          fontWeight:
              dtext.fontStyleType == FontStyleType.bold ||
                      dtext.fontStyleType == FontStyleType.boldItalic
                  ? FontWeight.bold
                  : FontWeight.normal,
          fontStyle:
              dtext.fontStyleType == FontStyleType.italic ||
                      dtext.fontStyleType == FontStyleType.boldItalic
                  ? FontStyle.italic
                  : FontStyle.normal,
          fontFamily:
              dtext.fontStyleType == FontStyleType.monospace
                  ? 'monospace'
                  : dtext.fontStyleType == FontStyleType.cursive
                  ? 'cursive'
                  : null,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textAlign: TextAlign.left,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout(minWidth: 0, maxWidth: size.width - dtext.position.dx);
      textPainter.paint(canvas, dtext.position);
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
          final random = math.Random(
            line.seed ?? 0,
          ); // Use a fixed seed for static effect
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

  // Helper method to draw different shapes
  void _drawShape(
    Canvas canvas,
    ShapeType type,
    Offset p1,
    Offset p2,
    Paint paint,
  ) {
    switch (type) {
      case ShapeType.rectangle:
        canvas.drawRect(Rect.fromPoints(p1, p2), paint);
        break;
      case ShapeType.circle:
        final center = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        final radius = (p2 - p1).distance / 2;
        if (radius > 0) {
          canvas.drawCircle(center, radius.abs(), paint);
        }
        break;
      case ShapeType.line:
        canvas.drawLine(p1, p2, paint);
        break;
      case ShapeType.none:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
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
  final List<DrawnShape> shapes; // <-- Add this
  final List<DrawnText> texts; // <-- Add this

  CanvasState({
    required this.lines,
    required this.backgroundColor,
    required this.images,
    required this.shapes, // <-- Add this
    required this.texts, // <-- Add this
  });
}

class DrawingState {
  final List<DrawnLine> lines;
  final List<DrawnShape> shapes;
  final List<DrawnText> texts;
  final Color backgroundColor;
  final List<Map<String, dynamic>> images; // Store image data as base64
  final String? title;
  final DateTime timestamp;

  DrawingState({
    required this.lines,
    required this.shapes,
    required this.texts,
    required this.backgroundColor,
    required this.images,
    this.title,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'lines': lines.map((l) => l.toJson()).toList(),
    'shapes': shapes.map((s) => s.toJson()).toList(),
    'texts': texts.map((t) => t.toJson()).toList(),
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
      shapes:
          (json['shapes'] as List).map((s) => DrawnShape.fromJson(s)).toList(),
      texts: (json['texts'] as List).map((t) => DrawnText.fromJson(t)).toList(),
      backgroundColor: Color(json['backgroundColor']),
      images: imageData,
      title: json['title'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}
