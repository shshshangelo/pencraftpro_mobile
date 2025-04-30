import 'dart:io';
import 'dart:ui' as ui;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/rendering.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_image_gallery_saver/flutter_image_gallery_saver.dart';

class DrawingCanvasPage extends StatefulWidget {
  const DrawingCanvasPage({super.key});

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

  List<ImageData> _images = [];
  int? _activeImageIndex;
  bool _isAdjustingImage = false;

  Offset _initialFocalPoint = Offset.zero;
  Offset _initialOffset = Offset.zero;
  double _initialScale = 1.0;

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  void _saveState() {
    if (_currentHistoryIndex < _history.length - 1) {
      _history = _history.sublist(0, _currentHistoryIndex + 1);
    }
    _history.add(
      CanvasState(
        lines: List.from(_lines),
        backgroundColor: _backgroundColor!,
        images: List.from(
          _images.map(
            (img) => ImageData(
              image: img.image,
              offset: img.offset,
              scale: img.scale,
            ),
          ),
        ),
      ),
    );
    _currentHistoryIndex++;
    if (_history.length > 50) {
      _history.removeAt(0);
      _currentHistoryIndex--;
    }
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
      _lines = List.from(state.lines);
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
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (_isAdjustingImage && _activeImageIndex != null) {
      _initialFocalPoint = details.focalPoint;
      _initialOffset = _images[_activeImageIndex!].offset;
      _initialScale = _images[_activeImageIndex!].scale;
    } else if (!_isErasing) {
      _startDrawing(details.localFocalPoint);
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_isAdjustingImage && _activeImageIndex != null) {
      setState(() {
        _images[_activeImageIndex!].scale = _initialScale * details.scale;
        _images[_activeImageIndex!].offset =
            _initialOffset + (details.focalPoint - _initialFocalPoint);
      });
    } else if (!_isErasing) {
      _keepDrawing(details.localFocalPoint);
    } else {
      _erase(details.localFocalPoint);
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (!_isAdjustingImage) {
      _endDrawing();
    } else {
      _saveState();
    }
  }

  void _startDrawing(Offset position) {
    if (!_isAdjustingImage) {
      setState(() {
        _currentLine = DrawnLine([position], _selectedColor, _strokeWidth);
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
      _lines.removeWhere((line) {
        for (var point in line.path) {
          if ((point - position).distance < _eraserWidth / 2) {
            return true;
          }
        }
        return false;
      });
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
          const SnackBar(content: Text('Storage or Photos permission denied')),
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

      final fileName = 'drawing_${DateTime.now().millisecondsSinceEpoch}';

      await FlutterImageGallerySaver.saveImage(pngBytes);

      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final savedDrawings = prefs.getStringList('saved_drawings') ?? [];
      print('Before saving to SharedPreferences: $savedDrawings');
      if (savedDrawings.length >= 100) {
        savedDrawings.removeAt(0);
      }
      savedDrawings.add('$fileName|${DateTime.now().toIso8601String()}');
      bool success = await prefs.setStringList('saved_drawings', savedDrawings);
      print('SharedPreferences save success: $success');
      print(
        'After saving to SharedPreferences: ${prefs.getStringList('saved_drawings')}',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Drawing saved to gallery.')),
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
            _activeImageIndex = _images.length - 1;
            _isAdjustingImage = true;
            _saveState();
          });
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo library permission denied')),
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
            _activeImageIndex = _images.length - 1;
            _isAdjustingImage = true;
            _saveState();
          });
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera permission denied')),
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
                        max: 20,
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
      _backgroundColor = Theme.of(context).scaffoldBackgroundColor;
      _currentLine = null;
      _isAdjustingImage = false;
      _activeImageIndex = null;
      _saveState();
    });
  }

  Future<bool> _onWillPop() async {
    if (_lines.isNotEmpty || _images.isNotEmpty) {
      final shouldSave = await showDialog<bool?>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Save Drawing?'),
              content: const Text(
                'Do you want to save your drawing before exiting?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.red, // 🔴 Red background
                    foregroundColor: Colors.white, // White text para kita
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Save'),
                ),
              ],
            ),
      );

      if (shouldSave == true) {
        await _saveAsImage();
        return true;
      } else if (shouldSave == false) {
        return true;
      } else {
        return false;
      }
    }
    return true;
  }

  Color get _iconColor => Theme.of(context).colorScheme.onSurface;

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
                onSelected: (value) {
                  if (value == 'saved') {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Drawing saved successfully!'),
                      ),
                    );
                    _saveAsImage();
                  }
                  if (value == 'import') _importImage();
                  if (value == 'camera') _takePicture();
                  if (value == 'save') _saveAsImage();
                },
                itemBuilder:
                    (_) => const [
                      //(
                      //   value: 'saved',
                      //   child: Text('Saved Drawings'),
                      // ),
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
                  child: GestureDetector(
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    onScaleEnd: _onScaleEnd,
                    onTapDown: (details) {
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
                        } else if (imageRect.contains(details.localPosition)) {
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
                            color: _isErasing ? Colors.grey : _iconColor,
                          ),
                          onPressed: () {
                            _isErasing = false;
                            _showBrushSlider();
                          },
                        ),
                      ),
                      Tooltip(
                        message: 'Eraser',
                        child: IconButton(
                          icon: Icon(
                            Icons.cleaning_services,
                            color: _isErasing ? _iconColor : Colors.grey,
                          ),
                          onPressed: () {
                            _isErasing = true;
                            _showEraserSlider();
                          },
                        ),
                      ),
                      Tooltip(
                        message: 'Color',
                        child: IconButton(
                          icon: Icon(Icons.color_lens, color: _iconColor),
                          onPressed: _showColorPicker,
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
      canvas.drawImageRect(image.image, src, dst, paint);

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
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke;

      for (int i = 0; i < line.path.length - 1; i++) {
        canvas.drawLine(line.path[i], line.path[i + 1], paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class DrawnLine {
  List<Offset> path;
  Color color;
  double width;

  DrawnLine(this.path, this.color, this.width);
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
