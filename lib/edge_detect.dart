import 'dart:typed_data';

/// A Dart port of the original `Edgedetect.py` class.
///
/// The original implementation relies heavily on OpenCV and the
/// Kivy UI framework to provide augmented reality feedback based on
/// detected faces and pedestrians.  This port retains the structure
/// and public API of the Python version while using simple placeholders
/// for image processing and rendering logic.
///
/// The actual computer vision operations (face and people detection)
/// are not implemented and should be provided by suitable packages or
/// platform code when integrating into a full Flutter application.
class EdgeDetect {
  static dynamic g;
  static dynamic mainApp;
  static dynamic voicePromptQueue;
  static dynamic cvVoice;
  static dynamic logViewer;
  static dynamic speedL;

  static const int triggerTimeArSoundMax = 3;

  Uint8List? analyzedTexture;
  Uint8List? overlayTexture;
  List<List<int>>? backupFaces;
  List<List<int>>? backupPeople;
  bool freeflow = false;
  DateTime lastArSoundTime = DateTime.fromMillisecondsSinceEpoch(0);

  EdgeDetect();

  /// Initializes shared references used by the detector.
  static void init(
    dynamic gps,
    dynamic mainAppParam,
    dynamic voiceQueue,
    dynamic cvVoiceParam,
    dynamic speedLParam,
  ) {
    g = gps;
    mainApp = mainAppParam;
    voicePromptQueue = voiceQueue;
    cvVoice = cvVoiceParam;
    speedL = speedLParam;
  }

  void setLogViewer(dynamic viewer) {
    logViewer = viewer;
  }

  /// Sets up resources required for AR detection.
  ///
  /// In the original Python code this loads OpenCV cascade files and
  /// configures a HOG detector.  Those operations are omitted here and
  /// should be implemented using a suitable Dart library if needed.
  void initArDetection() {
    freeflow = false;
  }

  /// Analyzes camera frame pixels.  This method mirrors the behaviour of
  /// `analyze_pixels_callback` in the Python implementation.
  void analyzePixelsCallback(
    Uint8List pixels,
    List<int> imageSize,
    List<int> imagePos,
    double scale,
    bool mirror,
  ) {
    if (pixels.isEmpty) {
      _log('AR Frame is empty!', level: 'ERROR');
      return;
    }

    // Placeholder detection calls.  Actual implementations should return
    // lists of rectangles `[x, y, w, h]` for each detected face/person.
    final faces = detectFaces(pixels, imageSize);
    final people = detectPeople(pixels, imageSize);

    final resultsFound = updateResults(faces, people);

    if (resultsFound) {
      freeflow = false;
      speedL?.updateAr('!!!');
      final currentTime = DateTime.now();
      if (currentTime.difference(lastArSoundTime).inSeconds >=
          triggerTimeArSoundMax) {
        _log('AR detection successful', logViewer: logViewer);
        playArSound();
        lastArSoundTime = currentTime;
      }
      if (!(g?.cameraInProgress() ?? false)) {
        if (!(g?.cameraIsArHuman() ?? false)) {
          g?.updateAr();
        }
      }
    } else {
      speedL?.updateAr('OK');
      if (!(g?.cameraInProgress() ?? false) && !freeflow) {
        g?.updateSpeedCamera('FREEFLOW');
        freeflow = true;
      }
    }

    // The original code draws rectangles on the frame and updates Kivy
    // textures.  That behaviour is not implemented here.
  }

  /// Very naive face detection based on luminance in the center region.
  ///
  /// This is **not** a production ready detector. It simply inspects the
  /// middle portion of the frame and, if more than half of the pixels are
  /// considered "dark", reports that region as a potential face. The return
  /// value mirrors the OpenCV API used in the original Python code and
  /// consists of rectangles in `[x, y, w, h]` format.
  List<List<int>> detectFaces(Uint8List frame, List<int> imageSize) {
    const bytesPerPixel = 4; // Expecting RGBA/BGRA input
    final width = imageSize[0];
    final height = imageSize[1];
    final startX = (width * 0.25).round();
    final startY = (height * 0.25).round();
    final boxW = (width * 0.5).round();
    final boxH = (height * 0.5).round();

    var darkPixels = 0;
    for (var y = startY; y < startY + boxH; y++) {
      final rowStart = y * width * bytesPerPixel;
      for (var x = startX; x < startX + boxW; x++) {
        final idx = rowStart + x * bytesPerPixel;
        final r = frame[idx];
        final g = frame[idx + 1];
        final b = frame[idx + 2];
        final luminance = 0.299 * r + 0.587 * g + 0.114 * b;
        if (luminance < 80) {
          darkPixels++;
        }
      }
    }

    final totalPixels = boxW * boxH;
    if (darkPixels / totalPixels > 0.5) {
      return [
        [startX, startY, boxW, boxH],
      ];
    }
    return <List<int>>[];
  }

  /// Simplistic people detection using vertical edge count.
  ///
  /// The algorithm checks for a high number of vertical intensity changes
  /// which roughly approximates the presence of a person. When the edge
  /// density exceeds a threshold, the entire frame is returned as a detected
  /// region. This mirrors the structure of the Python HOG based detector but
  /// is intentionally lightweight for environments without OpenCV.
  List<List<int>> detectPeople(Uint8List frame, List<int> imageSize) {
    const bytesPerPixel = 4; // Expecting RGBA/BGRA input
    final width = imageSize[0];
    final height = imageSize[1];

    var edgeCount = 0;
    for (var y = 0; y < height - 1; y++) {
      var rowStart = y * width * bytesPerPixel;
      var nextRowStart = (y + 1) * width * bytesPerPixel;
      for (var x = 0; x < width; x++) {
        final idx = rowStart + x * bytesPerPixel;
        final idxNext = nextRowStart + x * bytesPerPixel;
        final r = frame[idx];
        final g = frame[idx + 1];
        final b = frame[idx + 2];
        final rn = frame[idxNext];
        final gn = frame[idxNext + 1];
        final bn = frame[idxNext + 2];
        final lum = 0.299 * r + 0.587 * g + 0.114 * b;
        final lumNext = 0.299 * rn + 0.587 * gn + 0.114 * bn;
        if ((lum - lumNext).abs() > 40) {
          edgeCount++;
        }
      }
    }

    final totalPixels = width * height;
    if (edgeCount / totalPixels > 0.1) {
      return [
        [0, 0, width, height],
      ];
    }
    return <List<int>>[];
  }

  /// Updates cached results and returns true if new detections are found.
  bool updateResults(List<List<int>> faces, List<List<int>> people) {
    var resultsFound = false;

    if (faces.isNotEmpty) {
      if (backupFaces == null || !_listEquals(backupFaces!, faces)) {
        backupFaces = _deepCopy(faces);
        resultsFound = true;
      }
    }

    if (people.isNotEmpty) {
      if (backupPeople == null || !_listEquals(backupPeople!, people)) {
        backupPeople = _deepCopy(people);
        resultsFound = true;
      }
    }

    return resultsFound;
  }

  /// Plays the AR detection sound using the voice prompt queue.
  void playArSound() {
    voicePromptQueue?.produceArStatus(cvVoice, 'AR_HUMAN');
  }

  void _log(String message, {String level = 'INFO', dynamic logViewer}) {
    // Basic logger used in place of the Python Logger class.
    print('$level: $message');
    if (logViewer != null) {
      try {
        logViewer.log(message);
      } catch (_) {
        // Ignore logging errors from the viewer.
      }
    }
  }

  List<List<int>> _deepCopy(List<List<int>> source) {
    return source.map((inner) => List<int>.from(inner)).toList();
  }

  bool _listEquals(List<List<int>> a, List<List<int>> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final ai = a[i];
      final bi = b[i];
      if (ai.length != bi.length) return false;
      for (var j = 0; j < ai.length; j++) {
        if (ai[j] != bi[j]) return false;
      }
    }
    return true;
  }
}
