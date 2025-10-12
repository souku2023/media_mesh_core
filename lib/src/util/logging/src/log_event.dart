part of '../logging.dart';

/// Represents a single log entry with all relevant metadata.
///
/// Passed through the controller queue to be formatted and written.
class _LogEvent {
  /// Severity level (DEBUG, INFO, WARNING, ERROR, FATAL).
  final Level level;

  /// The user-provided message string.
  final String message;

  /// Optional error object or exception.
  final dynamic error;

  /// Log tag of the LogRecord. By default, this is className.methodName, If
  /// a tag is provided, it will be used instead.
  final String tag;

  /// Timestamp when this event was created.
  final DateTime timestamp;

  /// Optional file path and line number where the call originated.
  final String? fileInfo;

  /// Full stack trace at the moment of logging.
  final StackTrace? stackTrace;

  _LogEvent({
    required this.level,
    required this.message,
    this.error,
    required this.tag,
    required this.timestamp,
    this.fileInfo,
    this.stackTrace,
  });
}
