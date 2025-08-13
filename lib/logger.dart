import 'dart:async';
import 'config.dart';

/// ANSI color codes used for stdout logging.
class BColors {
  static const String header = '\x1b[95m';
  static const String blue = '\x1b[94m';
  static const String green = '\x1b[92m';
  static const String yellow = '\x1b[93m';
  static const String purple = '\x1b[95m';
  static const String lightgreen = '\x1b[96m';
  static const String black = '\x1b[97m';
  static const String red = '\x1b[91m';
  static const String endc = '\x1b[0m';
  static const String bold = '\x1b[1m';
  static const String underline = '\x1b[4m';
}

/// Available log levels that can be highlighted in the log viewer.
enum LogLevel {
  warning('WARNING'),
  error('ERROR');

  const LogLevel(this.value);
  final String value;
}

/// Adds a log line to the log viewer if it contains WARNING or ERROR.
void addLogLineToLogViewer(String logLine, StreamController<String> logViewer) {
  if (logLine.contains(LogLevel.warning.value) ||
      logLine.contains(LogLevel.error.value)) {
    Future.microtask(() => logViewer.add(logLine));
  }
}

/// Prints a log line to stdout with optional ANSI color formatting.
void printLogLineToStdout(String logLine, {String? color}) {
  switch (color) {
    case 'BLUE':
      print('${BColors.blue}$logLine${BColors.endc}');
      break;
    case 'GREEN':
      print('${BColors.green}$logLine${BColors.endc}');
      break;
    case 'LIGHTGREEN':
      print('${BColors.lightgreen}$logLine${BColors.endc}');
      break;
    case 'WHITE':
      print('${BColors.black}$logLine${BColors.endc}');
      break;
    case 'YELLOW':
      print('${BColors.yellow}$logLine${BColors.endc}');
      break;
    case 'RED':
      print('${BColors.red}$logLine${BColors.endc}');
      break;
    case 'BOLD':
      print('${BColors.bold}$logLine${BColors.endc}');
      break;
    case 'HEADER':
      print('${BColors.header}$logLine${BColors.endc}');
      break;
    case 'UNDERLINE':
      print('${BColors.underline}$logLine${BColors.endc}');
      break;
    case 'PURPLE':
      print('${BColors.purple}$logLine${BColors.endc}');
      break;
    default:
      print(logLine);
  }
}

/// Logger that logs either to stdout or to a log viewer.
class Logger {
  final String moduleName;
  StreamController<String>? logViewer;
  bool alwaysLogToStdOut = false;

  Logger(this.moduleName, {this.logViewer}) {
    setConfigs();
  }

  void setLogViewer(StreamController<String> logViewer) {
    this.logViewer = logViewer;
  }

  void setConfigs() {
    // Call this to disable logs to stdout when a log viewer is used.
    alwaysLogToStdOut =
        AppConfig.get<bool>('logger.always_log_to_stdout') ?? false;
  }

  String createLogLinePrefix(String logLevel) {
    final now = DateTime.now();
    final ms = now.millisecond.toString().padLeft(3, '0');
    var logTime =
        '${now.toIso8601String().split(".").first}.$ms'.padRight(23, '0');
    final paddedLevel = logLevel.padRight(2);
    final paddedModule = moduleName.padRight(40);
    return '$logTime - [SPEEDMASTER] - $paddedLevel - $paddedModule - ';
  }

  String createFormattedLogLine(String logString, {String logLevel = 'INFO'}) {
    final prefix = createLogLinePrefix(logLevel);
    return '$prefix$logString';
  }

  /// Main function to print a log line to a file and/or stdout.
  void printLogLine(
    String logString, {
    String logLevel = 'INFO',
    String? color,
    StreamController<String>? logViewer,
  }) {
    logViewer ??= this.logViewer;
    final logLine = createFormattedLogLine(logString, logLevel: logLevel);
    if (logViewer == null) {
      printLogLineToStdout(logLine, color: color);
    } else {
      addLogLineToLogViewer(logLine, logViewer);
    }
    if (logViewer != null && alwaysLogToStdOut) {
      printLogLineToStdout(logLine, color: color);
    }
  }
}

