import 'dart:async';

class Logger {
  final String moduleName;
  final StreamController<String>? logViewer;
  bool alwaysLogToStdOut = true;

  Logger(this.moduleName, {this.logViewer});

  String _createLogLinePrefix(String level) {
    final now = DateTime.now();
    final logTime = now.toIso8601String();
    final paddedModule = moduleName.padRight(40);
    final paddedLevel = level.padRight(7);
    return '$logTime - [SPEEDMASTER] - $paddedLevel - $paddedModule - ';
  }

  String createFormattedLogLine(String logString, {String level = 'INFO'}) {
    return '${_createLogLinePrefix(level)}$logString';
  }

  void printLogLine(String logString, {String level = 'INFO'}) {
    final line = createFormattedLogLine(logString, level: level);
    if (logViewer != null) {
      logViewer!.add(line);
    }
    if (logViewer == null || alwaysLogToStdOut) {
      print(line);
    }
  }
}
