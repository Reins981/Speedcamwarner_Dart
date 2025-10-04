import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/scheduler.dart';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'voice_prompt_events.dart';
import 'app_controller.dart';

/// Widget that manages the augmented reality camera preview and detection logic.
class EdgeDetect extends StatefulWidget {
  EdgeDetect({super.key, this.aspectRatio = '16:9', this.statusNotifier});

  final String aspectRatio;
  final ValueNotifier<String>? statusNotifier;

  @override
  EdgeDetectState createState() => EdgeDetectState();
}

class EdgeDetectState extends State<EdgeDetect> {
  CameraController? _controller;
  FaceDetector? _faceDetector;
  ObjectDetector? _objectDetector;
  PoseDetector? _poseDetector;
  bool cameraConnected = false;
  String _cameraDirection = 'back';

  late VoicePromptEvents voicePromptEvents;
  dynamic g;
  dynamic speedL;
  Function(String message)? _logViewer;

  List<Rect> _faces = <Rect>[];
  List<Rect> _people = <Rect>[];
  bool _freeflow = false;
  int _lastArSoundTime = 0;
  bool _isProcessingImage = false;
  bool _alertShown = false;
  bool _detectionStarted = false;
  bool _warnedDetectorsNotReady = false;

  static const int _triggerTimeArSoundMax = 3;

  @override
  void initState() {
    super.initState();
    unawaited(initArDetection());
  }

  @override
  void dispose() {
    _disposeResources();
    super.dispose();
  }

  void _disposeResources() {
    _controller?.dispose();
    _controller = null;
    unawaited(_faceDetector?.close());
    unawaited(_objectDetector?.close());
    unawaited(_poseDetector?.close());
    _faceDetector = null;
    _objectDetector = null;
    _poseDetector = null;
    cameraConnected = false;
    _detectionStarted = false;
    _isProcessingImage = false;
    _warnedDetectorsNotReady = false;
  }

  void init(
    dynamic gps,
    dynamic mainApp,
    VoicePromptEvents voiceQueue,
    dynamic speedL,
  ) {
    voicePromptEvents = voiceQueue;
    g = gps;
    this.speedL = speedL;
  }

  void setLogViewer(Function(String message)? logViewer) {
    _logViewer = logViewer;
  }

  Future<void> captureScreenshot() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final XFile file = await _controller!.takePicture();
    final Directory dir = await getApplicationDocumentsDirectory();
    final String path = p.join(
        dir.path, 'screenshot_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await file.saveTo(path);
    _logViewer?.call('Screenshot saved to $path');
  }

  Future<void> selectCamera(String cameraDirection) async {
    _cameraDirection = cameraDirection;
    if (cameraConnected) {
      await disconnectCamera();
      await connectCamera();
    }
  }

  Future<void> disconnectCamera() async {
    if (_controller != null) {
      await _controller!.stopImageStream();
      await _controller!.dispose();
      _controller = null;
    }
    cameraConnected = false;
    _detectionStarted = false;
    _isProcessingImage = false;
    _warnedDetectorsNotReady = false;
    setState(() {
      _faces = <Rect>[];
      _people = <Rect>[];
    });
  }

  Future<void> initArDetection() async {
    await _faceDetector?.close();
    await _objectDetector?.close();
    await _poseDetector?.close();

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableTracking: true,
      ),
    );
    _objectDetector = ObjectDetector(
      options: ObjectDetectorOptions(
        classifyObjects: true,
        multipleObjects: true,
        mode: DetectionMode.stream,
      ),
    );
    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
    );
    _detectionStarted = false;
    _freeflow = false;
    _warnedDetectorsNotReady = false;
    _logViewer?.call('AR detectors initialised');
  }

  Future<void> connectCamera({
    int analyzePixelsResolution = 720,
    bool enableAnalyzePixels = true,
    bool enableVideo = false,
  }) async {
    if (_faceDetector == null ||
        _objectDetector == null ||
        _poseDetector == null) {
      await initArDetection();
    }

    final List<CameraDescription> cameras = await availableCameras();
    final CameraDescription description = cameras.firstWhere(
      (CameraDescription d) => _cameraDirection == 'front'
          ? d.lensDirection == CameraLensDirection.front
          : d.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    _controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _controller!.initialize();
    cameraConnected = true;

    await _controller!.startImageStream(_processImage);
    setState(() {});
  }

  Future<void> _processImage(CameraImage image) async {
    if (_faceDetector == null ||
        _objectDetector == null ||
        _poseDetector == null) {
      if (!_warnedDetectorsNotReady) {
        _logViewer?.call('Detectors not ready yet');
        _warnedDetectorsNotReady = true;
      }
      return;
    }
    _warnedDetectorsNotReady = false;
    if (_isProcessingImage) return;
    _isProcessingImage = true;
    if (!_detectionStarted) {
      _logViewer?.call('AR detection stream started');
      _detectionStarted = true;
    }

    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final Uint8List bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize =
          Size(image.width.toDouble(), image.height.toDouble());
      final InputImageRotation rotation = InputImageRotationValue.fromRawValue(
              _controller?.description.sensorOrientation ?? 0) ??
          InputImageRotation.rotation0deg;
      final InputImageFormat format =
          InputImageFormatValue.fromRawValue(image.format.raw) ??
              InputImageFormat.nv21;

      final InputImageMetadata metadata = InputImageMetadata(
        size: imageSize,
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      );

      final InputImage inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: metadata,
      );

      final List<Face> faces = await _faceDetector!.processImage(inputImage);
      final List<DetectedObject> objects =
          await _objectDetector!.processImage(inputImage);
      final List<Pose> poses = await _poseDetector!.processImage(inputImage);

      final List<Rect> people = <Rect>[];
      for (final DetectedObject obj in objects) {
        if (obj.labels.any((Label l) => l.text.toLowerCase() == 'person')) {
          people.add(obj.boundingBox);
        }
      }

      final List<Rect> poseBounds = poses
          .map(_poseBoundingBox)
          .whereType<Rect>()
          .where((Rect rect) => rect.width > 0 && rect.height > 0)
          .toList();
      if (poseBounds.isNotEmpty) {
        people.addAll(poseBounds);
      }

      final bool resultsFound = faces.isNotEmpty || people.isNotEmpty;
      if (resultsFound) {
        _freeflow = false;
        _logViewer?.call(
            'Detections - faces: ${faces.length}, bodies: ${people.length}');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          speedL?.updateAr('!!!');
          widget.statusNotifier?.value = 'HUMAN';
          _showDetectionAlert();
        });
        final int currentTime = DateTime.now().millisecondsSinceEpoch;
        if (currentTime - _lastArSoundTime >= _triggerTimeArSoundMax * 1000) {
          _playArSound();
          _logViewer?.call('AR detection successful');
          _lastArSoundTime = currentTime;
        }
        if (!(g?.cameraInProgress() ?? true)) {
          if (!(g?.cameraIsArHuman() ?? false)) {
            g?.updateAr();
          }
        }
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          speedL?.updateAr('OK');
          widget.statusNotifier?.value = 'FREEFLOW';
          _dismissDetectionAlert();
        });
        if (!(g?.cameraInProgress() ?? true) && !_freeflow) {
          g?.updateSpeedCamera('FREEFLOW');
          _freeflow = true;
        }
      }

      if (mounted) {
        setState(() {
          _faces = faces.map((Face f) => f.boundingBox).toList();
          _people = people;
        });
      }
    } on PlatformException catch (e) {
      _logViewer?.call('Image processing failed: ${e.message}');
    } catch (e) {
      _logViewer?.call('Image processing error: $e');
    } finally {
      _isProcessingImage = false;
    }
  }

  Rect? _poseBoundingBox(Pose pose) {
    if (pose.landmarks.isEmpty) {
      return null;
    }

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = -double.infinity;
    double maxY = -double.infinity;

    for (final PoseLandmark landmark in pose.landmarks.values) {
      final double x = landmark.x;
      final double y = landmark.y;
      if (x.isNaN || y.isNaN) {
        continue;
      }
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      maxX = math.max(maxX, x);
      maxY = math.max(maxY, y);
    }

    if (minX == double.infinity ||
        minY == double.infinity ||
        maxX == -double.infinity ||
        maxY == -double.infinity) {
      return null;
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  void _showDetectionAlert() {
    if (Platform.isAndroid && !_alertShown && mounted) {
      showDialog(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Alert'),
          content: const Text('Face or body detected'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      _alertShown = true;
    }
  }

  void _dismissDetectionAlert() {
    if (Platform.isAndroid && _alertShown && mounted) {
      final navigator = Navigator.of(context, rootNavigator: true);
      if (navigator.canPop()) {
        navigator.pop();
      }
      _alertShown = false;
    }
  }

  void _playArSound() {
    voicePromptEvents.emit('AR_HUMAN');
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return Container(color: Colors.black);
    }

    final previewSize = _controller!.value.previewSize!;

    return AspectRatio(
      aspectRatio: previewSize.width / previewSize.height,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          CameraPreview(_controller!),
          CustomPaint(
            painter: _DetectionPainter(
              faces: _faces,
              people: _people,
              previewSize: previewSize,
              isFrontCamera: _controller!.description.lensDirection ==
                  CameraLensDirection.front,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetectionPainter extends CustomPainter {
  _DetectionPainter({
    required this.faces,
    required this.people,
    required this.previewSize,
    required this.isFrontCamera,
  });

  final List<Rect> faces;
  final List<Rect> people;
  final Size previewSize;
  final bool isFrontCamera;

  @override
  void paint(Canvas canvas, Size size) {
    final double scaleX = size.width / previewSize.width;
    final double scaleY = size.height / previewSize.height;

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.red;

    void drawRect(Rect rect) {
      final double left = rect.left * scaleX;
      final double top = rect.top * scaleY;
      final double right = rect.right * scaleX;
      final double bottom = rect.bottom * scaleY;
      final Rect scaled = Rect.fromLTRB(left, top, right, bottom);

      if (isFrontCamera) {
        final double centerX = size.width / 2;
        final Rect mirrored = Rect.fromLTRB(
          centerX - (scaled.right - centerX),
          scaled.top,
          centerX + (centerX - scaled.left),
          scaled.bottom,
        );
        canvas.drawRect(mirrored, paint);
      } else {
        canvas.drawRect(scaled, paint);
      }
    }

    for (final Rect face in faces) {
      drawRect(face);
    }
    for (final Rect person in people) {
      drawRect(person);
    }
  }

  @override
  bool shouldRepaint(covariant _DetectionPainter oldDelegate) {
    return !listEquals(oldDelegate.faces, faces) ||
        !listEquals(oldDelegate.people, people);
  }
}

class ARLayout extends StatefulWidget {
  const ARLayout({
    super.key,
    this.sm,
    this.mainApp,
    this.initArgs,
    this.onReturn,
  });

  final dynamic sm;
  final AppController? mainApp;
  final List<dynamic>? initArgs;
  final VoidCallback? onReturn;

  @override
  State<ARLayout> createState() => _ARLayoutState();
}

class _ARLayoutState extends State<ARLayout> {
  final GlobalKey<EdgeDetectState> _edgeKey = GlobalKey<EdgeDetectState>();
  String cameraDirection = 'front';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initArgs != null && widget.initArgs!.length >= 4) {
        _edgeKey.currentState?.init(
          widget.initArgs![0],
          widget.initArgs![1],
          widget.initArgs![2],
          widget.initArgs![3],
        );
      }
    });
  }

  void setLogViewer(Function(String message)? logViewer) {
    _edgeKey.currentState?.setLogViewer(logViewer);
  }

  void callbackReturn() {
    Navigator.of(context).pop();
  }

  void _selectCamera() {
    _edgeKey.currentState?.selectCamera(cameraDirection);
    setState(() {
      cameraDirection = cameraDirection == 'front' ? 'back' : 'front';
    });
  }

  void _connectCamera() {
    final EdgeDetectState? state = _edgeKey.currentState;
    if (state?.cameraConnected ?? false) {
      state?.disconnectCamera();
      widget.mainApp?.arStatusNotifier.value = 'Idle';
      widget.mainApp?.startDeviationCheckerThread();
    } else {
      widget.mainApp?.stopDeviationCheckerThread();
      state?.initArDetection();
      state?.connectCamera();
      widget.mainApp?.arStatusNotifier.value = 'Scanning';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(
            child: EdgeDetect(
                key: _edgeKey,
                statusNotifier: widget.mainApp?.arStatusNotifier)),
        Positioned.fill(
          child: ButtonsLayout(
            onReturn: widget.onReturn ?? callbackReturn,
            onScreenshot: () => _edgeKey.currentState?.captureScreenshot(),
            onSelectCamera: _selectCamera,
            onConnectCamera: _connectCamera,
          ),
        ),
      ],
    );
  }
}

class ButtonsLayout extends StatelessWidget {
  const ButtonsLayout({
    super.key,
    required this.onReturn,
    required this.onScreenshot,
    required this.onSelectCamera,
    required this.onConnectCamera,
  });

  final VoidCallback onReturn;
  final VoidCallback onScreenshot;
  final VoidCallback onSelectCamera;
  final VoidCallback onConnectCamera;

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    final bool isPortrait = size.width < size.height;
    late final Widget layout;
    if (isPortrait) {
      final double buttonSize = math.min(size.width / 4, size.height * 0.2);
      layout = Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: buttonSize * 4,
          height: buttonSize,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              _button(
                  icon: Icons.screen_share,
                  onPressed: onConnectCamera,
                  size: buttonSize),
              _button(
                  icon: Icons.camera_alt,
                  onPressed: onScreenshot,
                  size: buttonSize),
              _button(
                  icon: Icons.arrow_back,
                  onPressed: onReturn,
                  size: buttonSize),
              _button(
                  icon: Icons.cameraswitch,
                  onPressed: onSelectCamera,
                  size: buttonSize),
            ],
          ),
        ),
      );
    } else {
      final double buttonSize = math.min(size.width * 0.2, size.height / 4);
      layout = Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: buttonSize,
          height: buttonSize * 4,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              _button(
                  icon: Icons.cameraswitch,
                  onPressed: onSelectCamera,
                  size: buttonSize),
              _button(
                  icon: Icons.arrow_back,
                  onPressed: onReturn,
                  size: buttonSize),
              _button(
                  icon: Icons.camera_alt,
                  onPressed: onScreenshot,
                  size: buttonSize),
              _button(
                  icon: Icons.screen_share,
                  onPressed: onConnectCamera,
                  size: buttonSize),
            ],
          ),
        ),
      );
    }

    return SafeArea(child: layout);
  }

  Widget _button(
      {required IconData icon,
      required VoidCallback onPressed,
      required double size}) {
    return SizedBox(
      width: size,
      height: size,
      child: ElevatedButton(
        onPressed: onPressed,
        child: Icon(icon),
      ),
    );
  }
}
