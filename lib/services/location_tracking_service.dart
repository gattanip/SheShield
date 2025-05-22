import 'dart:async';
import 'dart:math';
import 'dart:isolate';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';  // Add this for AppLifecycleState
import 'package:geolocator_android/geolocator_android.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'logging_service.dart';
import 'location_service.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(LocationTaskHandler());
}

class LocationTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {
    // Initialize any resources needed for location tracking
  }

  @override
  Future<void> onEvent(DateTime timestamp, SendPort? sendPort) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      // Get tracking ID from task data
      final trackingId = await FlutterForegroundTask.getData<String>(key: 'trackingId');
      if (trackingId != null) {
        await FirebaseFirestore.instance
            .collection('locations')
            .doc(trackingId)
            .set({
          'latitude': position.latitude,
          'longitude': position.longitude,
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'active',
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Error in location task handler: $e');
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {
    // Clean up any resources
  }
}

class LocationTrackingService implements ILocationService {
  static final LocationTrackingService _instance = LocationTrackingService._internal();
  factory LocationTrackingService() => _instance;
  LocationTrackingService._internal();

  final LoggingService _logger = LoggingService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isInitialized = false;
  bool _isSharing = false;
  String? _trackingId;
  Timer? _locationUpdateTimer;
  StreamSubscription<Position>? _positionStreamSubscription;

  @override
  bool get isInitialized => _isInitialized;
  @override
  bool get isSharing => _isSharing;

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _logger.initialize();
      await _logger.log(LogLevel.info, 'LocationTrackingService', 'Initializing location tracking service...');
      
      // Check location permission
      final permission = await Permission.location.request();
      if (!permission.isGranted) {
        throw Exception('Location permission not granted');
      }

      // Check if location services are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled');
      }

      _isInitialized = true;
      await _logger.log(LogLevel.info, 'LocationTrackingService', 'Location tracking service initialized successfully');
    } catch (e, stackTrace) {
      await _logger.log(LogLevel.error, 'LocationTrackingService', 'Failed to initialize location tracking service', e, stackTrace);
      rethrow;
    }
  }

  @override
  Future<void> startLocationSharing() async {
    if (!_isInitialized) {
      throw Exception('Location tracking service not initialized');
    }

    if (_isSharing) {
      await _logger.log(LogLevel.warning, 'LocationTrackingService', 'Location tracking already active');
      return;
    }

    try {
      await _logger.log(LogLevel.info, 'LocationTrackingService', 'Starting location tracking...');
      
      // Generate tracking ID
      _trackingId = DateTime.now().millisecondsSinceEpoch.toString();
      
      // Start position stream
      _positionStreamSubscription?.cancel();
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen(
        (Position position) => _updateLocation(position),
        onError: (e) => _logger.log(LogLevel.error, 'LocationTrackingService', 'Error in position stream', e),
      );

      _isSharing = true;
      await _logger.log(LogLevel.info, 'LocationTrackingService', 'Location tracking started successfully');
    } catch (e, stackTrace) {
      await _logger.log(LogLevel.error, 'LocationTrackingService', 'Error starting location tracking', e, stackTrace);
      rethrow;
    }
  }

  @override
  Future<void> stopLocationSharing() async {
    if (!_isSharing) {
      await _logger.log(LogLevel.info, 'LocationTrackingService', 'Location tracking not active');
              return;
            }

    try {
      await _logger.log(LogLevel.info, 'LocationTrackingService', 'Stopping location tracking...');
      
      // Stop position stream
      await _positionStreamSubscription?.cancel();
      _positionStreamSubscription = null;
      
      // Clear tracking data
      if (_trackingId != null) {
        await _firestore.collection('tracking').doc(_trackingId).delete();
        _trackingId = null;
      }
      
      _isSharing = false;
      await _logger.log(LogLevel.info, 'LocationTrackingService', 'Location tracking stopped successfully');
    } catch (e, stackTrace) {
      await _logger.log(LogLevel.error, 'LocationTrackingService', 'Error stopping location tracking', e, stackTrace);
      rethrow;
    }
  }

  @override
  Future<String> getTrackingUrl() async {
    if (!_isSharing || _trackingId == null) {
      throw Exception('Location tracking not active');
    }
    return 'https://sheshield-f0cc6.web.app/track.html?uid=$_trackingId';
  }

  @override
  Future<Position> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
    } catch (e, stackTrace) {
      await _logger.log(LogLevel.error, 'LocationTrackingService', 'Error getting current position', e, stackTrace);
      rethrow;
    }
  }

  Future<void> _updateLocation(Position position) async {
    if (!_isSharing || _trackingId == null) return;

    try {
      await _firestore.collection('tracking').doc(_trackingId).set({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'altitude': position.altitude,
        'speed': position.speed,
        'speedAccuracy': position.speedAccuracy,
        'heading': position.heading,
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _logger.log(LogLevel.debug, 'LocationTrackingService', 
        'Location updated: ${position.latitude}, ${position.longitude}');
    } catch (e, stackTrace) {
      await _logger.log(LogLevel.error, 'LocationTrackingService', 'Error updating location in Firestore', e, stackTrace);
    }
  }

  @override
  void dispose() {
    stopLocationSharing();
    _positionStreamSubscription?.cancel();
  }

  // Add public stopTracking method
  Future<void> stopTracking() async {
    await stopLocationSharing();
  }

  // Add public isTrackingActive method
  Future<bool> isTrackingActive() async {
    return _isSharing && _trackingId != null;
  }

  // Add public getCurrentTrackingId method
  Future<String?> getCurrentTrackingId() async {
    return _trackingId;
  }
} 