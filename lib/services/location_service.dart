import 'dart:async';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'logging_service.dart';

// Base interface for location services
abstract class ILocationService {
  Future<void> initialize();
  Future<void> startLocationSharing();
  Future<void> stopLocationSharing();
  Future<String> getTrackingUrl();
  Future<Position> getCurrentPosition();
  bool get isInitialized;
  bool get isSharing;
}

class LocationService implements ILocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  final LoggingService _logger = LoggingService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  bool _isInitialized = false;
  bool _isSharing = false;
  Timer? _locationUpdateTimer;
  Position? _lastPosition;
  DateTime? _lastUpdateTime;
  
  @override
  bool get isInitialized => _isInitialized;
  @override
  bool get isSharing => _isSharing;

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _logger.initialize();
      await _logger.log(LogLevel.info, 'LocationService', 'Initializing location service...');
      
      // Initialize foreground task
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'sheshield_location_channel',
          channelName: 'Location Sharing',
          channelDescription: 'This notification is used for location sharing.',
          channelImportance: NotificationChannelImportance.HIGH,
          priority: NotificationPriority.HIGH,
          iconData: const NotificationIconData(
            resType: ResourceType.mipmap,
            resPrefix: ResourcePrefix.ic,
            name: 'launcher',
          ),
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: true,
          playSound: false,
        ),
        foregroundTaskOptions: const ForegroundTaskOptions(
          interval: 5000,
          isOnceEvent: false,
          autoRunOnBoot: false,
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );

      _isInitialized = true;
      await _logger.log(LogLevel.info, 'LocationService', 'Location service initialized successfully');
    } catch (e, stackTrace) {
      await _logger.log(LogLevel.error, 'LocationService', 'Failed to initialize location service', e, stackTrace);
      rethrow;
    }
  }

  @override
  Future<void> startLocationSharing() async {
    if (!_isInitialized) {
      throw Exception('Location service not initialized');
    }

    if (_isSharing) {
      await _logger.log(LogLevel.warning, 'LocationService', 'Location sharing already active');
      return;
    }

    try {
      await _logger.log(LogLevel.info, 'LocationService', 'Starting location sharing...');
      
      // Check location permission
      final permission = await Permission.location.request();
      if (!permission.isGranted) {
        throw Exception('Location permission not granted');
      }

      // Start foreground task
      await FlutterForegroundTask.startService(
        notificationTitle: 'SheShield Location Sharing',
        notificationText: 'Your location is being shared for safety.',
      );
      
      // Start periodic location updates
      _locationUpdateTimer?.cancel();
      _locationUpdateTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        _updateLocation();
      });

      _isSharing = true;
      await _logger.log(LogLevel.info, 'LocationService', 'Location sharing started successfully');
    } catch (e, stackTrace) {
      await _logger.log(LogLevel.error, 'LocationService', 'Error starting location sharing', e, stackTrace);
      rethrow;
    }
  }

  @override
  Future<void> stopLocationSharing() async {
    if (!_isSharing) {
      await _logger.log(LogLevel.info, 'LocationService', 'Location sharing not active');
      return;
    }

    try {
      await _logger.log(LogLevel.info, 'LocationService', 'Stopping location sharing...');
      
      // Stop foreground task
      await FlutterForegroundTask.stopService();
      
      // Stop location updates
      _locationUpdateTimer?.cancel();
      _locationUpdateTimer = null;
      
      _isSharing = false;
      await _logger.log(LogLevel.info, 'LocationService', 'Location sharing stopped successfully');
    } catch (e, stackTrace) {
      await _logger.log(LogLevel.error, 'LocationService', 'Error stopping location sharing', e, stackTrace);
      rethrow;
    }
  }

  @override
  Future<String> getTrackingUrl() async {
    if (!_isSharing) {
      throw Exception('Location sharing not active');
    }

    try {
      final position = await getCurrentPosition();
      return 'https://maps.google.com/?q=${position.latitude},${position.longitude}';
    } catch (e, stackTrace) {
      await _logger.log(LogLevel.error, 'LocationService', 'Error getting tracking URL', e, stackTrace);
      rethrow;
    }
  }

  @override
  Future<Position> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (e, stackTrace) {
      await _logger.log(LogLevel.error, 'LocationService', 'Error getting current position', e, stackTrace);
      rethrow;
    }
  }

  Future<void> _updateLocation() async {
    if (!_isSharing) return;

    try {
      final position = await getCurrentPosition();
      final now = DateTime.now();

      // Update last known position
      _lastPosition = position;
      _lastUpdateTime = now;

      await _logger.log(LogLevel.debug, 'LocationService', 'Location updated: ${position.latitude}, ${position.longitude}');
    } catch (e, stackTrace) {
      await _logger.log(LogLevel.error, 'LocationService', 'Error updating location', e, stackTrace);
    }
  }

  @override
  void dispose() {
    stopLocationSharing();
    _locationUpdateTimer?.cancel();
  }
} 