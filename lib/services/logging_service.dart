import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';

enum LogLevel {
  debug,
  info,
  warning,
  error,
  critical,
}

class LoggingService {
  static final LoggingService _instance = LoggingService._internal();
  factory LoggingService() => _instance;
  LoggingService._internal();

  static const String _logFileName = 'sheshield.log';
  static const int _maxLogSize = 5 * 1024 * 1024; // 5MB
  static const int _maxLogFiles = 5;
  
  File? _logFile;
  bool _isInitialized = false;
  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');

  // Add new log categories
  static const String _categoryUI = 'UI';
  static const String _categoryNavigation = 'Navigation';
  static const String _categoryLifecycle = 'Lifecycle';
  static const String _categoryEmergency = 'Emergency';
  static const String _categoryLocation = 'Location';
  static const String _categoryMedia = 'Media';
  static const String _categoryAudio = 'Audio';
  static const String _categoryPermission = 'Permission';
  static const String _categoryNetwork = 'Network';

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final logDir = Directory('${appDir.path}/logs');
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }

      _logFile = File('${logDir.path}/$_logFileName');
      await _rotateLogsIfNeeded();
      _isInitialized = true;
      
      log(LogLevel.info, 'LoggingService', 'Logging service initialized');
    } catch (e) {
      debugPrint('Error initializing logging service: $e');
      rethrow;
    }
  }

  Future<void> _rotateLogsIfNeeded() async {
    if (_logFile == null) return;

    try {
      if (await _logFile!.exists()) {
        final size = await _logFile!.length();
        if (size >= _maxLogSize) {
          // Rotate existing logs
          final logDir = _logFile!.parent;
          for (var i = _maxLogFiles - 1; i > 0; i--) {
            final oldFile = File('${logDir.path}/${_logFileName}.$i');
            final newFile = File('${logDir.path}/${_logFileName}.${i + 1}');
            if (await oldFile.exists()) {
              if (i == _maxLogFiles - 1) {
                await oldFile.delete();
              } else {
                await oldFile.rename(newFile.path);
              }
            }
          }
          await _logFile!.rename('${logDir.path}/${_logFileName}.1');
          _logFile = File('${logDir.path}/$_logFileName');
          await _logFile!.create();
        }
      } else {
        await _logFile!.create();
      }
    } catch (e) {
      debugPrint('Error rotating logs: $e');
    }
  }

  // Add new logging methods for specific categories
  Future<void> logUIInteraction(String action, {Map<String, dynamic>? details}) async {
    final message = 'UI Interaction: $action${details != null ? ' - ${json.encode(details)}' : ''}';
    await log(LogLevel.info, _categoryUI, message);
  }

  Future<void> logNavigation(String from, String to, {Map<String, dynamic>? details}) async {
    final message = 'Navigation: $from -> $to${details != null ? ' - ${json.encode(details)}' : ''}';
    await log(LogLevel.info, _categoryNavigation, message);
  }

  Future<void> logAppLifecycle(String state, {Map<String, dynamic>? details}) async {
    final message = 'App Lifecycle: $state${details != null ? ' - ${json.encode(details)}' : ''}';
    await log(LogLevel.info, _categoryLifecycle, message);
  }

  Future<void> logEmergencyEvent(String event, [Map<String, dynamic>? details]) async {
    final message = 'Emergency Event: $event${details != null ? ' - ${json.encode(details)}' : ''}';
    await log(LogLevel.info, _categoryEmergency, message);
  }

  Future<void> logLocationUpdate(Position position, {String? context}) async {
    final details = {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
      'altitude': position.altitude,
      'speed': position.speed,
      'heading': position.heading,
      'timestamp': position.timestamp?.toIso8601String(),
      if (context != null) 'context': context,
    };
    await log(LogLevel.debug, _categoryLocation, 'Location Update', null, null, details);
  }

  Future<void> logPermissionRequest(String permission, bool granted, {String? reason}) async {
    final message = 'Permission $permission ${granted ? 'granted' : 'denied'}${reason != null ? ' - $reason' : ''}';
    await log(granted ? LogLevel.info : LogLevel.warning, _categoryPermission, message);
  }

  Future<void> logNetworkRequest(String endpoint, String method, {Map<String, dynamic>? request, Map<String, dynamic>? response, dynamic error}) async {
    final details = {
      'endpoint': endpoint,
      'method': method,
      if (request != null) 'request': request,
      if (response != null) 'response': response,
    };
    if (error != null) {
      await log(LogLevel.error, _categoryNetwork, 'Network Request Failed', error, null, details);
    } else {
      await log(LogLevel.info, _categoryNetwork, 'Network Request', null, null, details);
    }
  }

  // Override existing log method to include details
  Future<void> log(LogLevel level, String source, String message, [dynamic error, StackTrace? stackTrace, Map<String, dynamic>? details]) async {
    if (!_isInitialized) {
      await initialize();
    }

    final timestamp = _dateFormat.format(DateTime.now());
    final levelStr = level.toString().split('.').last.toUpperCase();
    final logEntry = '[$timestamp] [$levelStr] [$source] $message';
    
    // Always print to debug console
    debugPrint(logEntry);
    if (details != null) {
      debugPrint('Details: ${json.encode(details)}');
    }
    if (error != null) {
      debugPrint('Error: $error');
      if (stackTrace != null) {
        debugPrint('Stack trace: $stackTrace');
      }
    }

    // Write to file if not in debug mode
    if (!kDebugMode && _logFile != null) {
      try {
        await _rotateLogsIfNeeded();
        final logContent = [
          logEntry,
          if (details != null) 'Details: ${json.encode(details)}',
          if (error != null) 'Error: $error',
          if (stackTrace != null) 'Stack trace: $stackTrace',
          '', // Empty line for readability
        ].join('\n');
        
        await _logFile!.writeAsString(logContent, mode: FileMode.append);
      } catch (e) {
        debugPrint('Error writing to log file: $e');
      }
    }
  }

  Future<String> getLogs() async {
    if (!_isInitialized || _logFile == null) return '';

    try {
      if (await _logFile!.exists()) {
        return await _logFile!.readAsString();
      }
    } catch (e) {
      debugPrint('Error reading log file: $e');
    }
    return '';
  }

  Future<void> clearLogs() async {
    if (!_isInitialized || _logFile == null) return;

    try {
      if (await _logFile!.exists()) {
        await _logFile!.delete();
        await _logFile!.create();
      }
    } catch (e) {
      debugPrint('Error clearing logs: $e');
    }
  }
} 