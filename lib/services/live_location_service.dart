import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';

/// Enhanced live location service with high accuracy and compass integration
class LiveLocationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Stream controllers
  final _positionController = StreamController<Position>.broadcast();
  final _headingController = StreamController<double>.broadcast();
  final _interpolatedPositionController = StreamController<Position>.broadcast();
  
  // Subscriptions
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<CompassEvent>? _compassSubscription;
  StreamSubscription<DocumentSnapshot>? _trackingSubscription;
  
  // State
  String? _currentTrackingId;
  Position? _lastPosition;
  double? _lastHeading;
  double? _lastCompassHeading;
  DateTime? _lastCompassUpdate;
  bool _isActive = false;
  bool _isHighAccuracyMode = true;

  // Enhanced location settings
  static const LocationSettings _locationSettings = LocationSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: 2, // 2 meters for smoother updates
    timeLimit: Duration(seconds: 5), // Timeout for position requests
  );

  // Movement thresholds
  static const double _minHeadingChange = 2.0; // degrees
  static const double _minMovementDistance = 1.0; // meters
  static const Duration _compassUpdateInterval = Duration(milliseconds: 100);
  static const double _compassAccuracyThreshold = 5.0; // degrees

  // Streams
  Stream<Position> get positionStream => _positionController.stream;
  Stream<double> get headingStream => _headingController.stream;
  Stream<Position> get interpolatedPositionStream => _interpolatedPositionController.stream;

  /// Start live tracking with enhanced accuracy
  Future<void> startLiveTracking(String trackingId) async {
    if (_isActive) return;

    try {
      // Check and request permissions
      await _checkAndRequestPermissions();
      
      // Verify location services
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Location services are disabled');
      }

      _currentTrackingId = trackingId;
      _isActive = true;
      _isHighAccuracyMode = true;

      // Start high-accuracy position stream
      await _startPositionStream();

      // Start compass updates
      await _startCompassUpdates();

      // Listen to Firestore for tracking updates
      _startTrackingUpdates();

      print('✅ [LiveLocation] Tracking started with high accuracy');
    } catch (e) {
      print('❌ [LiveLocation] Error starting tracking: $e');
      rethrow;
    }
  }

  /// Enhanced position stream with high accuracy
  Future<void> _startPositionStream() async {
    _positionSubscription?.cancel();
    
    try {
      // Get initial position with high accuracy
      final initialPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 5),
      );
      
      _handleNewPosition(initialPosition);

      // Start continuous updates
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: _locationSettings,
      ).listen(
        (position) => _handleNewPosition(position),
        onError: (error) {
          print('❌ [LiveLocation] Position stream error: $error');
          _handlePositionError(error);
        },
        cancelOnError: false,
      );
    } catch (e) {
      print('❌ [LiveLocation] Error starting position stream: $e');
      rethrow;
    }
  }

  /// Enhanced compass updates with accuracy threshold
  Future<void> _startCompassUpdates() async {
    try {
      if (await FlutterCompass.hasCompass()) {
        _compassSubscription?.cancel();
        _compassSubscription = FlutterCompass.events?.listen((event) {
          if (event.heading != null) {
            final heading = event.heading!;
            
            // Only update if heading change is significant
            if (_lastCompassHeading == null || 
                (heading - _lastCompassHeading!).abs() > _compassAccuracyThreshold) {
              _lastCompassHeading = heading;
              _lastCompassUpdate = DateTime.now();
              _headingController.add(heading);
              
              // Update Firestore with new heading
              _updateHeadingInFirestore(heading);
            }
          }
        });
        print('✅ [LiveLocation] Compass updates started');
      } else {
        print('⚠️ [LiveLocation] No compass available');
      }
    } catch (e) {
      print('❌ [LiveLocation] Error starting compass: $e');
    }
  }

  /// Enhanced position handling with movement validation
  void _handleNewPosition(Position position) {
    if (!_isActive) return;

    try {
      // Validate position accuracy
      if (!_isValidPosition(position)) {
        print('⚠️ [LiveLocation] Invalid position accuracy: ${position.accuracy}m');
        return;
      }

      // Calculate heading
      double? heading;
      if (_lastCompassHeading != null && 
          _lastCompassUpdate != null &&
          DateTime.now().difference(_lastCompassUpdate!).inSeconds < 2) {
        heading = _lastCompassHeading;
      } else if (_lastPosition != null) {
        heading = Geolocator.bearingBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          position.latitude,
          position.longitude,
        );
      }

      // Check if movement is significant
      bool isSignificant = false;
      if (_lastPosition != null) {
        final distance = Geolocator.distanceBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          position.latitude,
          position.longitude,
        );
        
        isSignificant = distance > _minMovementDistance || 
                       (heading != null && _lastHeading != null && 
                        (heading - _lastHeading!).abs() > _minHeadingChange);
      }

      // Update state
      _lastPosition = position;
      _lastHeading = heading;

      // Emit updates
      _positionController.add(position);
      if (heading != null) {
        _headingController.add(heading);
      }

      // Update Firestore with enhanced position data
      _updatePositionInFirestore(position, heading, isSignificant);

      print('📍 [LiveLocation] Position updated:');
      print('   - Accuracy: ${position.accuracy}m');
      print('   - Speed: ${position.speed}m/s');
      print('   - Heading: ${heading?.toStringAsFixed(1)}°');
      print('   - Significant: $isSignificant');
    } catch (e) {
      print('❌ [LiveLocation] Error handling position: $e');
    }
  }

  /// Validate position accuracy and movement
  bool _isValidPosition(Position position) {
    // Check accuracy
    if (position.accuracy > 20.0) { // 20 meters max accuracy
      return false;
    }

    // Check speed (reject unrealistic speeds)
    if (position.speed > 55.56) { // 200 km/h
      return false;
    }

    // Check if position is significantly different from last
    if (_lastPosition != null) {
      final distance = Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        position.latitude,
        position.longitude,
      );
      
      final timeDiff = DateTime.now().difference(_lastPosition!.timestamp).inSeconds;
      if (timeDiff > 0 && distance / timeDiff > 55.56) { // 200 km/h
        return false;
      }
    }

    return true;
  }

  /// Update position in Firestore with enhanced data
  Future<void> _updatePositionInFirestore(Position position, double? heading, bool isSignificant) async {
    if (_currentTrackingId == null) return;

    try {
      final now = DateTime.now();
      final timestamp = Timestamp.fromDate(now);

      final positionData = {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'speed': position.speed,
        'heading': heading,
        'compassHeading': _lastCompassHeading,
        'timestamp': timestamp,
        'isSignificant': isSignificant,
        'isHighAccuracy': _isHighAccuracyMode,
        'altitude': position.altitude,
        'speedAccuracy': position.speedAccuracy,
      };

      await _firestore.collection('emergency_tracking').doc(_currentTrackingId).update({
        'currentPosition': positionData,
        'lastUpdate': timestamp,
        'positions': FieldValue.arrayUnion([positionData]),
        'deviceInfo': {
          'lastUpdate': timestamp,
          'heading': heading,
          'compassHeading': _lastCompassHeading,
          'isHighAccuracy': _isHighAccuracyMode,
          'isSignificantMovement': isSignificant,
        }
      });
    } catch (e) {
      print('❌ [LiveLocation] Error updating Firestore: $e');
    }
  }

  /// Update heading in Firestore
  Future<void> _updateHeadingInFirestore(double heading) async {
    if (_currentTrackingId == null) return;

    try {
      await _firestore.collection('emergency_tracking').doc(_currentTrackingId).update({
        'deviceInfo.heading': heading,
        'deviceInfo.compassUpdateTime': Timestamp.now(),
      });
    } catch (e) {
      print('❌ [LiveLocation] Error updating heading: $e');
    }
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
        print('⚠️ [LiveLocation] Background location permission not granted');
      }
    }

    // Check compass permission (if needed)
    if (await FlutterCompass.hasCompass()) {
      var compassStatus = await Permission.sensors.status;
      if (!compassStatus.isGranted) {
        compassStatus = await Permission.sensors.request();
        if (!compassStatus.isGranted) {
          print('⚠️ [LiveLocation] Compass permission not granted');
        }
      }
    }
  }

  /// Handle position stream errors
  void _handlePositionError(dynamic error) {
    print('❌ [LiveLocation] Position error: $error');
    
    if (error is TimeoutException) {
      print('⏰ [LiveLocation] Position update timeout');
      _restartPositionStream();
    } else if (error is LocationServiceDisabledException) {
      print('📍 [LiveLocation] Location services disabled');
      stopLiveTracking();
    } else {
      print('⚠️ [LiveLocation] Unknown error, attempting recovery');
      _restartPositionStream();
    }
  }

  /// Restart position stream with exponential backoff
  Future<void> _restartPositionStream() async {
    if (!_isActive) return;

    try {
      await _positionSubscription?.cancel();
      await Future.delayed(const Duration(seconds: 1));
      await _startPositionStream();
    } catch (e) {
      print('❌ [LiveLocation] Error restarting stream: $e');
    }
  }

  /// Stop live tracking
  Future<void> stopLiveTracking() async {
    _isActive = false;
    _currentTrackingId = null;
    
    await _positionSubscription?.cancel();
    await _compassSubscription?.cancel();
    await _trackingSubscription?.cancel();
    
    _positionSubscription = null;
    _compassSubscription = null;
    _trackingSubscription = null;
    
    _lastPosition = null;
    _lastHeading = null;
    _lastCompassHeading = null;
    _lastCompassUpdate = null;
    
    print('🛑 [LiveLocation] Tracking stopped');
  }

  /// Dispose the service
  void dispose() {
    stopLiveTracking();
    _positionController.close();
    _headingController.close();
    _interpolatedPositionController.close();
  }
} 