part of '../logging.dart';

/// Logging utility that captures, queues, and writes log entries to both
/// console (in debug mode) and a timestamped file. Ensures FIFO ordering
/// of entries using an async queue, and automatically extracts caller
/// information (class, method, file, line) for richer context.
///
/// Usage:
/// ```dart
/// await Log.init(
///   logDirectory: Directory('MyLogDirectory'),
///   shouldLogToDirectory: true,
///   shouldLogToConsole: true,
/// );
/// Log.d('Debug message');
/// Log.i('Info message');
/// Log.e('Error message', e: exception);
/// await Log.shutdown();
/// ```
class Log {
  /// File sink for appending log lines to disk.
  static late final IOSink _logSink;

  /// Queue controller for serializing [_LogEvent] entries.
  static late final StreamController<_LogEvent> _controller;

  /// Pretty-printer console logger for non-Android platforms.
  static late final console_logger.Logger _consoleLogger;

  /// Ensures init() is only run once.
  static bool _initialized = false;

  /// The Directory in which the logs will be created
  static late final Directory logDir;

  /// Enable file logging
  static late final bool logToDirectory;

  /// Enable console logging
  static late final bool logToConsole;

  /// The current log filename
  static late final String logFilename;

  /// Initialize the logging subsystem.
  ///
  /// - Creates `logs/` directory if missing.
  /// - Opens a timestamped log file for append.
  /// - Configures console logger and Android Logcat bridge.
  /// - Sets up a FIFO queue to process all entries.
  static Future<void> init({
    Directory? logDirectory,
    bool shouldLogToDirectory = true,
    bool shouldLogToConsole = true,
  }) async {
    if (_initialized) return;
    _initialized = true;

    logToDirectory = shouldLogToDirectory;
    logToConsole = shouldLogToConsole;

    if (logToDirectory) {
      logDir =
          logDirectory ??
          Directory(
            path.join((await getApplicationSupportDirectory()).path, 'logs'),
          );

      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }

      final String timestamp = DateFormat(
        'yyyy-MM-dd_HH-mm-ss',
      ).format(DateTime.now());
      _logSink = File(
        '${logDir.path}/App_$timestamp.log',
      ).openWrite(mode: FileMode.append);
    }

    // Use ANSI colors on desktop; disable them on Android (Logcat can’t render ANSI).
    if (logToConsole) {
      _consoleLogger = console_logger.Logger(
        printer: console_logger.PrettyPrinter(
          methodCount: 0,
          errorMethodCount: 0,
          lineLength: 128,
          colors: !Platform.isAndroid,
          dateTimeFormat: console_logger.DateTimeFormat.onlyTime,
        ),
      );

      // Dart `logging` → Android Logcat bridge
      Logger.root.level = Level.ALL;
      if (Platform.isAndroid && logToDirectory) {
        // Binds Logger.root.onRecord → android.util.Log.*
        await Logger.root.activateLogcat();
      }
    }

    // Event queue for console/Logcat & file output
    _controller = StreamController<_LogEvent>();
    _controller.stream
        .asyncMap((_LogEvent event) async {
          if (logToDirectory) {
            if (Platform.isAndroid) {
              // On Android: send via the `logging` package, which the plugin
              // maps to Logcat at the correct priority & tag.
              final Logger tagLogger = Logger(event.tag);
              tagLogger.log(
                event.level,
                event.message,
                event.error,
                event.stackTrace,
              );
            } else {
              // On desktop/web: pretty-print via console_logger
              switch (event.level) {
                case Level.INFO:
                  _consoleLogger.i(
                    '${event.tag}: ${event.message}',
                    error: event.error,
                  );
                  break;
                case Level.WARNING:
                  _consoleLogger.w(
                    '${event.tag}: ${event.message}',
                    error: event.error,
                  );
                  break;
                case Level.SEVERE:
                case Level.SHOUT:
                  _consoleLogger.e(
                    '${event.tag}: ${event.message}',
                    error: event.error,
                  );
                  break;
                default:
                  // Treat all finer levels as DEBUG
                  _consoleLogger.d(
                    '${event.tag}: ${event.message}',
                    error: event.error,
                  );
              }
            }
          }

          if (logToDirectory) {
            final String fileLine = _formatLogEvent(event);
            _logSink.writeln('$fileLine\n');
            await _logSink.flush();
          }
        })
        .listen((_) {});
  }

  /// Shutdown the logging subsystem.
  ///
  /// - Closes the queue to stop accepting new events.
  /// - Closes the file sink, flushing any buffered data.
  /// - Allows `init()` to be called again if desired.
  static Future<void> shutdown() async {
    await _controller.close();
    await _logSink.close();
    _initialized = false;
  }

  /// Debug-level log. Mapped to `Level.FINE`.
  static void d(String msg, {String? tag}) => _log(Level.FINE, msg, tag: tag);

  /// Info-level log. Mapped to `Level.INFO`.
  static void i(String msg, {String? tag}) => _log(Level.INFO, msg, tag: tag);

  /// Warning-level log. Mapped to `Level.WARNING`.
  static void w(String msg, {dynamic e, dynamic st, String? tag}) =>
      _log(Level.WARNING, msg, tag: tag, error: e, stackTrace: st);

  /// Error-level log. Mapped to `Level.SEVERE`.
  static void e(String msg, {dynamic e, dynamic st, String? tag}) =>
      _log(Level.SEVERE, msg, tag: tag, error: e, stackTrace: st);

  /// Fatal-level log. Mapped to `Level.SHOUT`.
  static void f(String msg, {dynamic e, dynamic st, String? tag}) =>
      _log(Level.SHOUT, msg, tag: tag, error: e, stackTrace: st);

  //───────────────────────────────────────────────────────────────────────────
  // Internal implementation
  //───────────────────────────────────────────────────────────────────────────

  /// Core logging routine.
  ///
  /// - Validates `init()` was called.
  /// - Derives the `tag` (override or Class.method).
  /// - Enqueues a [_LogEvent] for async processing.
  static Future<void> _log(
    Level level,
    String message, {
    dynamic error,
    String? tag,
    dynamic stackTrace,
  }) async {
    if (!_initialized) {
      throw StateError('Log not initialized. Call Log.init() first.');
    }

    // Determine effective tag
    final String tagString = tag != null
        ? tag.toString()
        : _deriveTagFromFrame();

    // Capture file:line context
    final String? fileInfo = _captureFileInfo();

    // Only include the provided exception’s stack trace, if any
    final StackTrace? stack;
    if (stackTrace == null) {
      stack = (error is Error) ? error.stackTrace : null;
    } else {
      stack = stackTrace;
    }

    // Enqueue the event for console/Logcat & file processing
    _controller.add(
      _LogEvent(
        level: level,
        message: message,
        error: error,
        tag: tagString,
        timestamp: DateTime.now(),
        fileInfo: fileInfo,
        stackTrace: stack,
      ),
    );
  }

  /// Reads the current stack to produce a `Class.method` tag.
  static String _deriveTagFromFrame() {
    final Trace trace = Chain.current().toTrace();
    for (final Frame frame in trace.frames) {
      final String? m = frame.member;
      if (m != null && !m.startsWith('Log.')) {
        final List<String> parts = m.split('.');
        final String className = parts.first;
        final String methodName = (parts.length > 1)
            ? parts[1].split('(')[0]
            : parts[0];
        return '$className.$methodName';
      }
    }
    return 'unknown.unknown';
  }

  /// Captures “uri:line” from the calling context for file logs.
  static String? _captureFileInfo() {
    final Trace trace = Chain.current().toTrace();
    for (final Frame frame in trace.frames) {
      if (frame.member != null &&
          !frame.member!.startsWith('Log.') &&
          frame.line != null) {
        return '${frame.uri}:${frame.line}';
      }
    }
    return null;
  }

  /// Formats a single [_LogEvent] into a consistent block for file output:
  /// ```
  /// ---
  /// File: path/to/file.dart:123
  /// HH:mm:ss.SS, LEVEL  , Tag: message — optionalError
  /// optional terse stack trace
  /// ---
  /// ```
  static String _formatLogEvent(_LogEvent e) {
    final String time = DateFormat('HH:mm:ss').format(e.timestamp);
    final String hund = (e.timestamp.millisecond ~/ 10).toString().padLeft(
      2,
      '0',
    );
    final String lvl = e.level.name.padRight(7);
    final String loc = e.fileInfo != null ? 'File: ${e.fileInfo}\n' : '';

    String msg = e.message;
    if (e.error != null) {
      msg += ' — ${e.error}';
      if (e.stackTrace != null) {
        msg += '\n${Trace.from(e.stackTrace!).terse}';
      }
    }

    if (e.level.value >= Level.WARNING.value) {
      return '''
---
$loc$time.$hund, $lvl, ${e.tag}: $msg
---''';
    } else {
      return '''
---
$time.$hund, $lvl, ${e.tag}: $msg
---''';
    }
  }
}
