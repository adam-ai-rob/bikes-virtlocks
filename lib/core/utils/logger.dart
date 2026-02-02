import 'package:logging/logging.dart';

/// Application-wide logger utility
class AppLogger {
  static final Logger _logger = Logger('BikesVirtLocks');
  static bool _initialized = false;

  /// Initialize the logger with appropriate handlers
  static void init() {
    if (_initialized) return;

    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) {
      // ignore: avoid_print
      print(
        '${record.time} [${record.level.name}] ${record.loggerName}: ${record.message}',
      );
      if (record.error != null) {
        // ignore: avoid_print
        print('Error: ${record.error}');
      }
      if (record.stackTrace != null) {
        // ignore: avoid_print
        print('Stack trace:\n${record.stackTrace}');
      }
    });

    _initialized = true;
  }

  /// Log a debug message
  static void debug(String message) {
    _logger.fine(message);
  }

  /// Log an info message
  static void info(String message) {
    _logger.info(message);
  }

  /// Log a warning message
  static void warning(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.warning(message, error, stackTrace);
  }

  /// Log an error message
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.severe(message, error, stackTrace);
  }
}
