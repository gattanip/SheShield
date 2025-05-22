import 'dart:async';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'safety_zone_service.dart';

/// Service to handle background location tracking
class BackgroundLocationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SafetyZoneService _safetyZoneService = SafetyZoneService();
  
  String? _currentTrackingId;
  bool _isConfigured = false;
  bool _isTracking = false;
  Position? _lastPosition;

  // Background tracking settings
  static const bg.Config _config = bg.Config(
    // Debug
    debug: false,
    logLevel: bg.Config.LOG_LEVEL_VERBOSE,
    
    // Geolocation
    desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
    distanceFilter: 10.0, // meters - increased for battery optimization
    stopOnTerminate: false,
    startOnBoot: true,
    preventSuspend: true,
    
    // Activity Recognition
    activityRecognitionInterval: 1000,
    stopTimeout: 5,
    stopDetectionDelay: 5000,
    
    // Application config
    notification: bg.Notification(
      title: "SheShield Location Tracking",
      text: "Tracking your location for safety",
      channelName: "location_tracking",
      priority: bg.Config.NOTIFICATION_PRIORITY_HIGH,
      smallIcon: "@mipmap/ic_launcher",
      largeIcon: "@mipmap/ic_launcher",
    ),
    
    // HTTP & Persistence
    url: "https://sheshield-f0cc6.web.app/api/location",
    autoSync: true,
    autoSyncThreshold: 5,
    batchSync: true,
    maxBatchSize: 50,
    
    // Android specific
    foregroundService: true,
    enableHeadless: true,
    allowIdenticalLocations: false,
    
    // iOS specific
    pausesLocationUpdatesAutomatically: false,
    showsBackgroundLocationIndicator: true,
    disableElasticity: false,
    locationAuthorizationRequest: "Always",
  );

  /// Initialize background tracking
  Future<void> initialize() async {
    if (_isConfigured) return;

    try {
      // Configure the plugin
      await bg.BackgroundGeolocation.ready(_config);

      // Add event listeners
      _setupEventListeners();

      _isConfigured = true;
      print('✅ [BackgroundLocation] Service initialized');
    } catch (e) {
      print('❌ [BackgroundLocation] Error initializing: $e');
      rethrow;
    }
  }

  void _setupEventListeners() {
    // Location updates
    bg.BackgroundGeolocation.onLocation((bg.Location location) async {
      await _handleLocationUpdate(location);
    });

    // Motion changes
    bg.BackgroundGeolocation.onMotionChange((bg.Location location) {
      _handleMotionChange(location);
    });

    // Activity changes
    bg.BackgroundGeolocation.onActivityChange((bg.ActivityChangeEvent event) {
      _handleActivityChange(event);
    });

    // HTTP responses
    bg.BackgroundGeolocation.onHttp((bg.HttpEvent event) {
      _handleHttpResponse(event);
    });

    // Provider state changes
    bg.BackgroundGeolocation.onProviderChange((bg.ProviderChangeEvent event) {
      _handleProviderChange(event);
    });
  }

  /// Start background tracking
  Future<void> startTracking(String trackingId) async {
    if (!_isConfigured) {
      await initialize();
    }

    try {
      // Check permissions
      await _checkAndRequestPermissions();

      _currentTrackingId = trackingId;
      
      // Get initial position
      final initialPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _lastPosition = initialPosition;
      
      // Start safety zone monitoring
      await _safetyZoneService.startMonitoring(trackingId, initialPosition);
      
      // Start the plugin
      await bg.BackgroundGeolocation.start();
      
      // Enable motion detection
      await bg.BackgroundGeolocation.startMotionDetection();
      
      _isTracking = true;
      print('✅ [BackgroundLocation] Tracking started');
    } catch (e) {
      print('❌ [BackgroundLocation] Error starting tracking: $e');
      rethrow;
    }
  }

  /// Stop background tracking
  Future<void> stopTracking() async {
    if (!_isTracking) return;

    try {
      await bg.BackgroundGeolocation.stop();
      await bg.BackgroundGeolocation.stopMotionDetection();
      await _safetyZoneService.stopMonitoring();
      
      _isTracking = false;
      _currentTrackingId = null;
      _lastPosition = null;
      
      print('🛑 [BackgroundLocation] Tracking stopped');
    } catch (e) {
      print('❌ [BackgroundLocation] Error stopping tracking: $e');
      rethrow;
    }
  }

  /// Handle location updates
  Future<void> _handleLocationUpdate(bg.Location location) async {
    if (_currentTrackingId == null) return;

    try {
      final timestamp = Timestamp.fromDate(location.timestamp);
      final position = Position(
        latitude: location.coords.latitude,
        longitude: location.coords.longitude,
        timestamp: location.timestamp,
        accuracy: location.coords.accuracy,
        altitude: location.coords.altitude,
        heading: location.coords.heading,
        speed: location.coords.speed,
        speedAccuracy: location.coords.speedAccuracy,
      );
      
      _lastPosition = position;
      
      final positionData = {
        'latitude': location.coords.latitude,
        'longitude': location.coords.longitude,
        'accuracy': location.coords.accuracy,
        'speed': location.coords.speed,
        'heading': location.coords.heading,
        'altitude': location.coords.altitude,
        'timestamp': timestamp,
        'isBackground': true,
        'activity': location.activity.type,
        'confidence': location.activity.confidence,
        'batteryLevel': location.battery.level,
        'batteryIsCharging': location.battery.isCharging,
      };

      // Update Firestore
      await _firestore.collection('emergency_tracking').doc(_currentTrackingId).update({
        'currentPosition': positionData,
        'lastUpdate': timestamp,
        'positions': FieldValue.arrayUnion([positionData]),
        'deviceInfo': {
          'lastUpdate': timestamp,
          'isBackground': true,
          'activity': location.activity.type,
          'batteryLevel': location.battery.level,
          'batteryIsCharging': location.battery.isCharging,
        }
      });

      // Update safety zone monitoring
      await _safetyZoneService._checkSafetyZones(position);

      print('📍 [BackgroundLocation] Position updated:');
      print('   - Accuracy: ${location.coords.accuracy}m');
      print('   - Speed: ${location.coords.speed}m/s');
      print('   - Activity: ${location.activity.type}');
    } catch (e) {
      print('❌ [BackgroundLocation] Error updating position: $e');
    }
  }

  void _handleMotionChange(bg.Location location) {
    print('🔄 [BackgroundLocation] Motion changed:');
    print('   - Is moving: ${location.isMoving}');
    print('   - Activity: ${location.activity.type}');
  }

  void _handleActivityChange(bg.ActivityChangeEvent event) {
    print('🏃 [BackgroundLocation] Activity changed:');
    print('   - Activity: ${event.activity}');
    print('   - Confidence: ${event.confidence}');
  }

  void _handleHttpResponse(bg.HttpEvent event) {
    print('🌐 [BackgroundLocation] HTTP response:');
    print('   - Status: ${event.status}');
    print('   - Response: ${event.response}');
  }

  void _handleProviderChange(bg.ProviderChangeEvent event) {
    print('🔄 [BackgroundLocation] Provider changed:');
    print('   - Status: ${event.status}');
    print('   - Enabled: ${event.enabled}');
    print('   - GPS: ${event.gps}');
  }

  /// Check and request necessary permissions
  Future<void> _checkAndRequestPermissions() async {
    // Check location permission
    var locationStatus = await Permission.location.status;
    if (!locationStatus.isGranted) {
      locationStatus = await Permission.location.request();
      if (!locationStatus.isGranted) {
        throw Exception('Location permission denied');
      }
    }

    // Check background location permission
    var backgroundStatus = await Permission.locationAlways.status;
    if (!backgroundStatus.isGranted) {
      backgroundStatus = await Permission.locationAlways.request();
      if (!backgroundStatus.isGranted) {
        throw Exception('Background location permission denied');
      }
    }

    // Check activity recognition permission (Android)
    if (await Permission.activityRecognition.isSupported) {
      var activityStatus = await Permission.activityRecognition.status;
      if (!activityStatus.isGranted) {
        activityStatus = await Permission.activityRecognition.request();
        if (!activityStatus.isGranted) {
          print('⚠️ [BackgroundLocation] Activity recognition permission not granted');
        }
      }
    }
  }

  /// Get current tracking status
  Future<bool> isTracking() async {
    return await bg.BackgroundGeolocation.isStarted();
  }

  /// Dispose the service
  Future<void> dispose() async {
    await stopTracking();
    await bg.BackgroundGeolocation.removeListeners();
    _safetyZoneService.dispose();
  }
} 