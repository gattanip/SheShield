import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';  // Add this for AppLifecycleState
import 'package:geolocator_android/geolocator_android.dart';

class LocationTrackingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<Position>? _positionStream;
  String? _currentTrackingId;
  Timer? _cleanupTimer;
  Timer? _forceUpdateTimer;
  bool _isTracking = false;
  Position? _lastPosition;
  DateTime? _lastUpdateTime;
  int _updateCount = 0;
  double _lastSpeed = 0.0;
  bool _isHighAccuracyMode = true;

  // Adjust tracking parameters for better reliability and battery life
  static const int _minUpdateInterval = 2; // seconds (increased frequency for better tracking)
  static const int _maxUpdateInterval = 10; // seconds (reduced for better tracking)
  static const double _minDistanceFilter = 2.0; // meters (reduced for more frequent updates)
  static const double _maxDistanceFilter = 5.0; // meters (reduced for smoother tracking)
  static const double _minAccuracy = 5.0; // meters (improved accuracy requirement)
  static const double _maxAccuracy = 20.0; // meters (reduced for better accuracy)
  static const int _maxRetryAttempts = 10; // increased for more robust recovery
  static const Duration _retryDelay = Duration(seconds: 1); // reduced for faster recovery
  static const Duration _positionTimeout = Duration(seconds: 5); // reduced for faster recovery
  static const Duration _recoveryTimeout = Duration(seconds: 15); // reduced for faster recovery
  static const Duration _streamTimeout = Duration(seconds: 3); // reduced for faster recovery
  static const int _maxConsecutiveTimeouts = 5; // reduced for faster recovery
  static const Duration _minRecoveryDelay = Duration(seconds: 2); // reduced for faster recovery
  static const Duration _maxRecoveryDelay = Duration(seconds: 15); // reduced for faster recovery
  static const Duration _forceUpdateInterval = Duration(seconds: 5); // forced update interval
  static const Duration _backgroundUpdateInterval = Duration(seconds: 10); // background update interval
  static const Duration _foregroundUpdateInterval = Duration(seconds: 2); // foreground update interval
  
  int _currentUpdateInterval = _minUpdateInterval;
  double _currentDistanceFilter = _minDistanceFilter;
  int _consecutiveErrors = 0;
  DateTime? _lastSuccessfulUpdate;
  Position? _lastGoodPosition;
  int _retryCount = 0;

  // Add new fields for monitoring
  Timer? _heartbeatTimer;
  Timer? _recoveryTimer;
  bool _isRecovering = false;
  int _recoveryAttempts = 0;
  static const int MAX_RECOVERY_ATTEMPTS = 10; // increased for more resilience
  static const Duration RECOVERY_INTERVAL = Duration(seconds: 10);
  static const Duration HEARTBEAT_INTERVAL = Duration(seconds: 5);

  // Add new fields for background handling
  bool _isInBackground = false;
  Timer? _backgroundTimer;
  static const Duration BACKGROUND_INTERVAL = Duration(seconds: 30);
  static const Duration FOREGROUND_INTERVAL = Duration(seconds: 2);
  static const Duration MAX_RECOVERY_DELAY = Duration(seconds: 5);
  
  // Add new fields for stream management
  StreamSubscription<ServiceStatus>? _locationServiceStream;
  bool _isStreamActive = false;
  DateTime? _lastStreamStart;
  int _streamRestartCount = 0;
  static const int MAX_STREAM_RESTARTS = 10; // increased for more resilience

  // Add new fields for better state management
  int _consecutiveTimeouts = 0;
  DateTime? _lastRecoveryAttempt;
  bool _isLocationServiceEnabled = true;
  Timer? _locationServiceCheckTimer;

  // Add new fields for fallback mechanism
  Timer? _fallbackTimer;
  bool _isUsingFallback = false;
  static const Duration FALLBACK_INTERVAL = Duration(seconds: 10);
  static const Duration LOCATION_CHECK_INTERVAL = Duration(seconds: 5);
  static const int MAX_FALLBACK_ATTEMPTS = 10; // increased for more resilience
  int _fallbackAttempts = 0;

  // Add new fields for better state management
  DateTime? _lastSuccessfulStreamStart;
  bool _isStreamRecovering = false;
  int _consecutiveStreamFailures = 0;
  static const int MAX_STREAM_FAILURES = 3;

  // Generate a unique tracking ID
  String generateTrackingId() {
    return const Uuid().v4();
  }

  // Start tracking location with improved initialization
  Future<String> startTracking() async {
    try {
      if (_currentTrackingId == null) {
        _currentTrackingId = generateTrackingId();
      }
      if (_isTracking) {
        print('🔄 [LocationService] Tracking already active');
        if (_currentTrackingId == null) {
          throw Exception('Tracking ID is null');
        }
        return _currentTrackingId!;
      }

      print('🚀 [LocationService] Starting location tracking...');
      print('📱 [LocationService] Device: ${await _getDeviceInfo()}');
      
      // Check permissions with detailed logging
      final permissionStatus = await _checkPermissions();
      print('🔑 [LocationService] Permission status: $permissionStatus');
      
      if (permissionStatus != LocationPermission.whileInUse && 
          permissionStatus != LocationPermission.always) {
        print('❌ [LocationService] Insufficient permissions: $permissionStatus');
        throw Exception('Location permission not granted');
      }

      // Start location service monitoring
      _startLocationServiceMonitoring();

      // Start periodic location service checks more frequently
      _locationServiceCheckTimer?.cancel();
      _locationServiceCheckTimer = Timer.periodic(
        const Duration(seconds: 15), // Check more frequently
        (_) async {
          if (_isTracking) {
            await _checkLocationServiceAndRecover();
          }
        },
      );

      // Get initial position with retry and high accuracy
      print('🎯 [LocationService] Getting initial position...');
      final initialPosition = await _getInitialPositionWithRetry();
      if (initialPosition == null) {
        throw Exception('Failed to get initial position');
      }

      // Log initial position details
      print('✅ [LocationService] Initial position acquired:');
      print('   - Latitude: ${initialPosition.latitude}');
      print('   - Longitude: ${initialPosition.longitude}');
      print('   - Accuracy: ${initialPosition.accuracy}m');
      print('   - Speed: ${initialPosition.speed}m/s');
      print('   - Speed Accuracy: ${initialPosition.speedAccuracy}m/s');
      print('   - Heading: ${initialPosition.heading}°');
      print('   - Timestamp: ${initialPosition.timestamp}');

      _isTracking = true;
      _lastUpdateTime = DateTime.now();
      _recoveryAttempts = 0;
      _isRecovering = false;
      _streamRestartCount = 0;
      _isHighAccuracyMode = true; // Always start in high accuracy mode

      // Start heartbeat monitoring more frequently
      _startHeartbeat();

      // Start position stream with enhanced error handling
      await _startPositionStream();

      // Start cleanup timer
      _startCleanupTimer();

      // Start force update timer immediately
      _startForceUpdateTimer();

      if (_currentTrackingId == null) {
        throw Exception('Tracking ID is null after initialization');
      }

      // Create initial tracking document
      await _createTrackingDocument(initialPosition);

      return _currentTrackingId!;
    } catch (e, stackTrace) {
      print('❌ [LocationService] Error starting tracking:');
      print('   Error: $e');
      print('   Stack trace: $stackTrace');
      _handleError(e);
      rethrow;
    }
  }

  // Create initial tracking document
  Future<void> _createTrackingDocument(Position position) async {
    if (_currentTrackingId == null) return;

    try {
      final now = DateTime.now();
      final timestamp = Timestamp.fromDate(now);

      await _firestore.collection('emergency_tracking').doc(_currentTrackingId).set({
        'active': true,
        'startedAt': timestamp,
        'lastUpdate': timestamp,
        'currentPosition': {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy': position.accuracy,
          'speed': position.speed,
          'heading': position.heading,
          'timestamp': timestamp,
          'isInitial': true,
          'updateType': 'initial',
          'isHighAccuracy': true
        },
        'positions': [{
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy': position.accuracy,
          'speed': position.speed,
          'heading': position.heading,
          'timestamp': timestamp,
          'isInitial': true,
          'updateType': 'initial',
          'isHighAccuracy': true
        }],
        'deviceInfo': {
          'platform': defaultTargetPlatform.toString(),
          'accuracy': position.accuracy,
          'speed': position.speed,
          'heading': position.heading,
          'lastUpdate': timestamp,
          'updateCount': _updateCount,
          'isHighAccuracy': true,
          'isTracking': true
        }
      });

      print('✅ [LocationService] Initial tracking document created');
    } catch (e) {
      print('❌ [LocationService] Error creating tracking document: $e');
      rethrow;
    }
  }

  // Start optimized position stream
  Future<void> _startPositionStream() async {
    if (_isStreamActive) {
      print('📡 [LocationService] Stream already active, restarting...');
      await _positionStream?.cancel();
      _isStreamActive = false;
    }

    try {
      print('📡 [LocationService] Starting position stream...');
      _lastStreamStart = DateTime.now();
      
      // Configure location settings for high accuracy
      final settings = LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: _minDistanceFilter,
        timeLimit: _positionTimeout,
      );

      // Start position stream with enhanced error handling
      _positionStream = Geolocator.getPositionStream(locationSettings: settings)
          .listen(
        (Position position) async {
          if (!_isTracking) return;

          try {
            print('\n📍 [LocationService] New position received:');
            print('   - Time: ${position.timestamp}');
            print('   - Lat: ${position.latitude}');
            print('   - Lng: ${position.longitude}');
            print('   - Accuracy: ${position.accuracy}m');
            print('   - Speed: ${position.speed}m/s');
            print('   - Speed Accuracy: ${position.speedAccuracy}m/s');
            print('   - Heading: ${position.heading}°');
            print('   - Altitude: ${position.altitude}m');
            print('   - Altitude Accuracy: ${position.altitudeAccuracy}m');
            print('   - Is Background: $_isInBackground');

            // Always update position in high accuracy mode
            await _updatePosition(position);
            
            // Reset error counters on successful update
            _consecutiveErrors = 0;
            _consecutiveTimeouts = 0;
            _recoveryAttempts = 0;
            _isRecovering = false;

            // Stop fallback timer if it's running
            _fallbackTimer?.cancel();
            _fallbackTimer = null;
            _isUsingFallback = false;

          } catch (e, stackTrace) {
            print('❌ [LocationService] Error processing position update:');
            print('   Error: $e');
            print('   Stack trace: $stackTrace');
            _handleError(e);
          }
        },
        onError: (error) {
          print('❌ [LocationService] Position stream error:');
          print('   Error: $error');
          _isStreamActive = false;
          _handleError(error);
        },
        cancelOnError: false,
      );

      _isStreamActive = true;
      print('✅ [LocationService] Position stream started successfully');
    } catch (e) {
      print('❌ [LocationService] Error starting position stream:');
      print('   Error: $e');
      _isStreamActive = false;
      _handleError(e);
    }
  }

  // Update position with improved Firestore sync
  Future<void> _updatePosition(Position position, {bool isInitial = false, bool isForced = false}) async {
    if (_currentTrackingId == null) return;

    try {
      final now = DateTime.now();
      final timestamp = Timestamp.fromDate(now);
      _updateCount++;

      // Calculate movement metrics
      double? speed;
      double? heading;
      if (_lastPosition != null) {
        final distance = Geolocator.distanceBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          position.latitude,
          position.longitude,
        );
        final timeDiff = now.difference(_lastUpdateTime!).inSeconds;
        
        if (timeDiff > 0) {
          speed = distance / timeDiff;
          if (speed > 55.56) speed = position.speed; // Cap at 200 km/h
          
          if (distance > 1) {
            heading = Geolocator.bearingBetween(
              _lastPosition!.latitude,
              _lastPosition!.longitude,
              position.latitude,
              position.longitude,
            );
          }
        }
      }

      // Prepare position data with more details
      final positionData = {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'speed': speed ?? position.speed,
        'heading': heading ?? position.heading,
        'timestamp': timestamp,
        'isInitial': isInitial,
        'forcedUpdate': isForced,
        'updateType': isInitial ? 'initial' : (isForced ? 'forced' : 'normal'),
        'updateCount': _updateCount,
        'isHighAccuracy': true,
        'altitude': position.altitude,
        'altitudeAccuracy': position.altitudeAccuracy,
        'speedAccuracy': position.speedAccuracy,
        'batteryLevel': position.accuracy < _minAccuracy ? 'high' : 
                       position.accuracy < _maxAccuracy ? 'medium' : 'low'
      };

      // Update Firestore with atomic operations
      await _firestore.runTransaction((transaction) async {
        final docRef = _firestore.collection('emergency_tracking').doc(_currentTrackingId);
        final doc = await transaction.get(docRef);

        if (!doc.exists) {
          transaction.set(docRef, {
            'active': true,
            'startedAt': timestamp,
            'currentPosition': positionData,
            'lastUpdate': timestamp,
            'positions': [positionData],
            'deviceInfo': {
              'platform': defaultTargetPlatform.toString(),
              'accuracy': position.accuracy,
              'speed': speed ?? position.speed,
              'heading': heading ?? position.heading,
              'lastUpdate': timestamp,
              'updateCount': _updateCount,
              'isHighAccuracy': true,
              'isTracking': true
            }
          });
        } else {
          transaction.update(docRef, {
            'currentPosition': positionData,
            'lastUpdate': timestamp,
            'positions': FieldValue.arrayUnion([positionData]),
            'deviceInfo.lastUpdate': timestamp,
            'deviceInfo.updateCount': _updateCount,
            'deviceInfo.isHighAccuracy': true,
            'deviceInfo.isTracking': true
          });
        }
      });

      _lastPosition = position;
      _lastUpdateTime = now;
      _lastSuccessfulUpdate = now;
      print('✅ [LocationService] Position updated successfully');
    } catch (e) {
      print('❌ [LocationService] Error updating position: $e');
      _handlePositionError(e);
    }
  }

  // Improved error handling
  void _handlePositionError(dynamic error) {
    print('[ERROR] Handling position error: $error');
    _consecutiveErrors++;
    _adjustTrackingParameters(false);
    print('[ERROR] Consecutive errors: $_consecutiveErrors, Retry count: $_retryCount');
    
    if (_consecutiveErrors >= 5) {
      _retryCount++;
      if (_retryCount <= _maxRetryAttempts) {
        print('[ERROR] Retrying position stream ($_retryCount/$_maxRetryAttempts)');
        Future.delayed(_retryDelay, () => _restartPositionStream());
      } else {
        print('[ERROR] Max retry attempts reached, stopping tracking');
        stopTracking();
      }
    }
  }

  // Add new method for restarting the position stream
  Future<void> _restartPositionStream() async {
    if (!_isTracking) return;
    
    if (_isRecovering) {
      print('🔄 [LocationService] Recovery already in progress');
      return;
    }

    _isRecovering = true;
    _streamRestartCount++;

    print('🔄 [LocationService] Restarting position stream (Attempt $_streamRestartCount/$MAX_STREAM_RESTARTS)');

    if (_streamRestartCount > MAX_STREAM_RESTARTS) {
      print('❌ [LocationService] Max stream restart attempts reached');
      await stopTracking();
      return;
    }

    try {
      await _positionStream?.cancel();
      _positionStream = null;
      _isStreamActive = false;

      // Exponential backoff for retry delay
      final delay = Duration(seconds: min(pow(2, _streamRestartCount - 1).toInt(), MAX_RECOVERY_DELAY.inSeconds));
      print('⏳ [LocationService] Waiting ${delay.inSeconds}s before restart...');
      
      await Future.delayed(delay);
      
      await _startPositionStream();
      print('✅ [LocationService] Stream restarted successfully');
      _isRecovering = false;
    } catch (e) {
      print('❌ [LocationService] Stream restart failed: $e');
      _isRecovering = false;
      _handleError(e);
    }
  }

  // Improved tracking parameter adjustment
  void _adjustTrackingParameters(bool success) {
    if (success) {
      if (_consecutiveErrors > 0) {
        _consecutiveErrors = 0;
        _currentUpdateInterval = _minUpdateInterval;
        _currentDistanceFilter = _minDistanceFilter;
        _isHighAccuracyMode = true;
      }
    } else {
      _consecutiveErrors++;
      if (_consecutiveErrors >= 3) {
        _currentUpdateInterval = min(_currentUpdateInterval * 2, _maxUpdateInterval);
        _currentDistanceFilter = min(_currentDistanceFilter * 1.5, _maxDistanceFilter);
        if (_consecutiveErrors >= 5) {
          _isHighAccuracyMode = false;
        }
      }
    }
  }

  // Start cleanup timer
  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (_currentTrackingId != null) {
        _cleanupOldPositions();
      }
    });
  }

  // Improved cleanup of old positions
  Future<void> _cleanupOldPositions() async {
    if (_currentTrackingId == null) return;

    try {
      final doc = await _firestore
          .collection('emergency_tracking')
          .doc(_currentTrackingId)
          .get();
      
      if (doc.exists) {
        final data = doc.data()!;
        final positions = List<Map<String, dynamic>>.from(data['positions'] ?? []);
        
        // Keep only positions from the last hour and limit array size
        final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
        positions.removeWhere((pos) {
          final timestamp = (pos['timestamp'] as Timestamp).toDate();
          return timestamp.isBefore(oneHourAgo);
        });
        
        // Limit array size to prevent document size issues
        if (positions.length > 1000) {
          positions.removeRange(0, positions.length - 1000);
        }
        
        await doc.reference.update({
          'positions': positions,
          'lastCleanup': Timestamp.now(),
        });
        
        print('Cleaned up positions, kept ${positions.length} positions');
      }
    } catch (e) {
      print('Error cleaning up positions: $e');
    }
  }

  // Stop tracking with proper cleanup
  Future<void> stopTracking() async {
    if (!_isTracking) return;

    try {
      print('🛑 [LocationService] Stopping location tracking...');
      
      if (_currentTrackingId != null) {
        final now = DateTime.now();
        final timestamp = Timestamp.fromDate(now);
        
        await _firestore.collection('emergency_tracking').doc(_currentTrackingId).update({
          'active': false,
          'endedAt': timestamp,
          'lastUpdate': timestamp,
          'deviceInfo.lastUpdate': timestamp,
          'deviceInfo.isTracking': false
        });
      }

      await _positionStream?.cancel();
      _positionStream = null;

      _cleanupTimer?.cancel();
      _cleanupTimer = null;
      _forceUpdateTimer?.cancel();
      _forceUpdateTimer = null;

      _lastPosition = null;
      _lastUpdateTime = null;
      _isTracking = false;
      _updateCount = 0;
      _consecutiveErrors = 0;
      _retryCount = 0;
      _currentTrackingId = null;
      
      print('✅ [LocationService] Tracking stopped successfully');
    } catch (e) {
      print('Error stopping location tracking: $e');
      rethrow;
    }
  }

  // Get tracking status
  Future<bool> isTrackingActive() async {
    if (!_isTracking || _currentTrackingId == null) return false;
    
    try {
      final doc = await _firestore
          .collection('emergency_tracking')
          .doc(_currentTrackingId)
          .get();
      
      return doc.exists && doc.data()?['active'] == true;
    } catch (e) {
      print('Error checking tracking status: $e');
      return false;
    }
  }

  // Get tracking URL
  String getTrackingUrl(String trackingId) {
    return 'https://sheshiled-f0cc6.web.app/track.html?uid=$trackingId';
  }

  // Dispose
  void dispose() {
    _locationServiceStream?.cancel();
    _positionStream?.cancel();
    _heartbeatTimer?.cancel();
    _recoveryTimer?.cancel();
    _cleanupTimer?.cancel();
    _backgroundTimer?.cancel();
    _locationServiceCheckTimer?.cancel();
    _fallbackTimer?.cancel();
    stopTracking();
  }

  Future<String> _getDeviceInfo() async {
    try {
      final deviceInfo = {
        'platform': defaultTargetPlatform.toString(),
        'isHighAccuracyMode': _isHighAccuracyMode,
        'updateInterval': _currentUpdateInterval,
        'distanceFilter': _currentDistanceFilter,
        'lastUpdateTime': _lastUpdateTime?.toIso8601String(),
        'isTracking': _isTracking,
        'consecutiveErrors': _consecutiveErrors,
        'recoveryAttempts': _recoveryAttempts
      };
      return deviceInfo.toString();
    } catch (e) {
      print('❌ [LocationService] Error getting device info: $e');
      return 'Unknown device';
    }
  }

  Future<LocationPermission> _checkPermissions() async {
    try {
      // First check current permission status
      LocationPermission permission = await Geolocator.checkPermission();
      print('🔑 [LocationService] Current permission status: $permission');

      // If denied, request permission
      if (permission == LocationPermission.denied) {
        print('🔑 [LocationService] Requesting location permission...');
        permission = await Geolocator.requestPermission();
        print('🔑 [LocationService] New permission status: $permission');
      }

      // If denied forever, we can't proceed
      if (permission == LocationPermission.deniedForever) {
        print('❌ [LocationService] Location permission permanently denied');
        throw Exception('Location permission permanently denied');
      }

      return permission;
    } catch (e) {
      print('❌ [LocationService] Error checking permissions: $e');
      rethrow;
    }
  }

  Future<bool> _validatePosition(Position position) async {
    try {
      // Check accuracy
      if (position.accuracy > _maxAccuracy) {
        print('❌ [LocationService] Position validation failed: Accuracy too low (${position.accuracy}m > ${_maxAccuracy}m)');
        return false;
      }

      // Check if we have a previous position to compare with
      if (_lastGoodPosition != null) {
        // Calculate distance from last good position
        final distance = Geolocator.distanceBetween(
          _lastGoodPosition!.latitude,
          _lastGoodPosition!.longitude,
          position.latitude,
          position.longitude
        );

        // Calculate time difference
        final timeDiff = position.timestamp?.difference(_lastGoodPosition!.timestamp ?? DateTime.now());
        
        if (timeDiff != null && timeDiff.inSeconds > 0) {
          // Calculate speed
          final speed = distance / timeDiff.inSeconds;
          
          // Validate speed (reject if speed > 200 km/h and last speed was low)
          if (speed > 55.56 && _lastSpeed < 10) {
            print('❌ [LocationService] Position validation failed: Unrealistic speed (${speed.toStringAsFixed(2)} m/s)');
            return false;
          }

          // Validate distance (reject if too close and accuracy is poor)
          if (distance < _currentDistanceFilter && position.accuracy > _minAccuracy) {
            print('❌ [LocationService] Position validation failed: Too close to last position (${distance.toStringAsFixed(2)}m) with poor accuracy');
            return false;
          }
        }
      }

      // All validation passed
      print('✅ [LocationService] Position validation passed:');
      print('   - Accuracy: ${position.accuracy}m');
      print('   - Speed: ${position.speed}m/s');
      print('   - Timestamp: ${position.timestamp}');
      return true;
    } catch (e) {
      print('❌ [LocationService] Error validating position: $e');
      return false;
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(HEARTBEAT_INTERVAL, (timer) {
      if (!_isTracking) {
        print('⚠️ [LocationService] Heartbeat: Tracking not active');
        timer.cancel();
        return;
      }

      final now = DateTime.now();
      final lastUpdate = _lastUpdateTime;
      
      if (lastUpdate != null) {
        final timeSinceLastUpdate = now.difference(lastUpdate);
        print('💓 [LocationService] Heartbeat check:');
        print('   - Last update: $lastUpdate');
        print('   - Time since last update: ${timeSinceLastUpdate.inSeconds}s');
        
        if (timeSinceLastUpdate > const Duration(seconds: 10)) {
          print('⚠️ [LocationService] No updates received for ${timeSinceLastUpdate.inSeconds}s');
          _attemptRecovery();
        }
      }
    });
  }

  void _attemptRecovery() {
    if (_isRecovering || _isStreamRecovering) {
      print('🔄 [LocationService] Recovery already in progress');
      return;
    }

    final now = DateTime.now();
    if (_lastRecoveryAttempt != null) {
      final timeSinceLastRecovery = now.difference(_lastRecoveryAttempt!);
      if (timeSinceLastRecovery < _recoveryTimeout) {
        print('⏳ [LocationService] Too soon to attempt recovery (${timeSinceLastRecovery.inSeconds}s since last attempt)');
        return;
      }
    }

    if (_lastSuccessfulStreamStart != null) {
      final timeSinceLastSuccess = now.difference(_lastSuccessfulStreamStart!);
      if (timeSinceLastSuccess < _minRecoveryDelay) {
        print('⏳ [LocationService] Too soon to attempt recovery after last successful stream start');
        return;
      }
    }

    _isRecovering = true;
    _isStreamRecovering = true;
    _recoveryAttempts++;
    _lastRecoveryAttempt = now;

    print('🔄 [LocationService] Attempting recovery (Attempt $_recoveryAttempts/$MAX_RECOVERY_ATTEMPTS)');

    if (_recoveryAttempts > MAX_RECOVERY_ATTEMPTS) {
      print('❌ [LocationService] Max recovery attempts reached. Will keep retrying in background.');
      _isRecovering = false;
      _isStreamRecovering = false;
      // Instead of stopping, schedule another attempt after a delay
      Future.delayed(const Duration(seconds: 30), _attemptRecovery);
      return;
    }

    // Cancel existing stream
    _positionStream?.cancel();
    _positionStream = null;

    // Calculate delay with exponential backoff and maximum limit
    final baseDelay = pow(2, _recoveryAttempts - 1).toInt();
    final delaySeconds = min(baseDelay, _maxRecoveryDelay.inSeconds);
    final delay = Duration(seconds: max(delaySeconds, _minRecoveryDelay.inSeconds));
    
    print('⏳ [LocationService] Waiting ${delay.inSeconds}s before recovery attempt...');
    
    _recoveryTimer?.cancel();
    _recoveryTimer = Timer(delay, () async {
      try {
        print('🔄 [LocationService] Starting recovery attempt...');
        await _checkLocationServiceAndRecover();
        print('✅ [LocationService] Recovery successful');
        _isRecovering = false;
        _isStreamRecovering = false;
      } catch (e) {
        print('❌ [LocationService] Recovery failed: $e');
        _isRecovering = false;
        _isStreamRecovering = false;
        if (_recoveryAttempts < MAX_RECOVERY_ATTEMPTS) {
          // Add a delay before the next recovery attempt
          await Future.delayed(_minRecoveryDelay);
          _attemptRecovery();
        }
      }
    });
  }

  // Add new method for location service monitoring
  void _startLocationServiceMonitoring() {
    _locationServiceStream?.cancel();
    _locationServiceStream = Geolocator.getServiceStatusStream().listen((status) {
      print('📍 [LocationService] Location service status changed: $status');
      if (status == ServiceStatus.disabled) {
        _handleError(LocationServiceDisabledException());
      } else if (status == ServiceStatus.enabled && _isTracking) {
        _restartPositionStream();
      }
    });
  }

  // Enhanced error handling
  void _handleError(dynamic error) {
    print('❌ [LocationService] Error occurred:');
    print('   Error type: ${error.runtimeType}');
    print('   Error message: $error');
    
    if (error is TimeoutException) {
      print('⏰ [LocationService] Position update timeout');
      _consecutiveTimeouts++;
      if (_consecutiveTimeouts >= _maxConsecutiveTimeouts) {
        print('⚠️ [LocationService] Too many consecutive timeouts, starting fallback mechanism');
        _startFallbackMechanism();
      } else {
        _restartPositionStream();
      }
    } else if (error is LocationServiceDisabledException) {
      print('📍 [LocationService] Location services disabled');
      stopTracking();
    } else if (error is PermissionDeniedException) {
      print('🔒 [LocationService] Location permission denied');
      stopTracking();
    } else if (error is PlatformException) {
      print('📱 [LocationService] Platform error: ${error.code}');
      if (error.code == 'location_service_disabled') {
        stopTracking();
      } else if (error.code == 'google_play_services_not_available') {
        print('⚠️ [LocationService] Google Play Services not available, attempting fallback');
        _startFallbackMechanism();
      } else {
        _restartPositionStream();
      }
    } else {
      print('⚠️ [LocationService] Unknown error, attempting recovery');
      _restartPositionStream();
    }
  }

  // Add method to handle app lifecycle changes
  void onAppLifecycleChanged(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _isInBackground = false;
        if (_isTracking) {
          _restartPositionStream();
        }
        break;
      case AppLifecycleState.paused:
        _isInBackground = true;
        break;
      default:
        break;
    }
  }

  // Add new method for location service check and recovery
  Future<void> _checkLocationServiceAndRecover() async {
    try {
      bool serviceEnabled = false;
      try {
        serviceEnabled = await Geolocator.isLocationServiceEnabled()
            .timeout(_streamTimeout, onTimeout: () {
          print('⚠️ [LocationService] Location service check timed out');
          return false;
        });
      } catch (e) {
        if (e is PlatformException && e.code == 'location_service_disabled') {
          print('❌ [LocationService] Location services are disabled');
          throw LocationServiceDisabledException();
        }
        print('⚠️ [LocationService] Error checking location service: $e');
        serviceEnabled = false;
      }

      if (!serviceEnabled) {
        print('❌ [LocationService] Location services are disabled');
        _isLocationServiceEnabled = false;
        throw LocationServiceDisabledException();
      }
      
      _isLocationServiceEnabled = true;
      print('✅ [LocationService] Location services are enabled, attempting recovery');
      
      // Reset counters
      _consecutiveTimeouts = 0;
      _streamRestartCount = 0;
      _consecutiveStreamFailures = 0;
      
      // If we're not already using fallback, start it
      if (!_isUsingFallback) {
        _startFallbackMechanism();
      }

      // Try to restart the stream
      await _startPositionStream();
    } catch (e) {
      print('❌ [LocationService] Error checking location service: $e');
      if (e is PlatformException && 
          (e.code == 'location_service_disabled' || 
           e.code == 'google_play_services_not_available')) {
        print('❌ [LocationService] Location services not available: ${e.message}');
        throw LocationServiceDisabledException();
      }
      _handleError(e);
    }
  }

  // Add new method for fallback mechanism
  void _startFallbackMechanism() {
    if (_isUsingFallback) {
      print('⚠️ [LocationService] Fallback mechanism already active');
      return;
    }

    _isUsingFallback = true;
    _fallbackAttempts = 0;
    print('🔄 [LocationService] Starting fallback mechanism');

    _fallbackTimer?.cancel();
    _fallbackTimer = Timer.periodic(FALLBACK_INTERVAL, (timer) async {
      if (!_isTracking) {
        timer.cancel();
        return;
      }

      _fallbackAttempts++;
      print('🔄 [LocationService] Fallback attempt $_fallbackAttempts/$MAX_FALLBACK_ATTEMPTS');

      if (_fallbackAttempts > MAX_FALLBACK_ATTEMPTS) {
        print('❌ [LocationService] Max fallback attempts reached. Will keep retrying in background.');
        // Instead of stopping, keep retrying every 30 seconds
        _fallbackAttempts = 0;
        return;
      }

      try {
        // Try to get a single position
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );

        print('✅ [LocationService] Got position in fallback mode:');
        print('   - Lat: ${position.latitude}');
        print('   - Lng: ${position.longitude}');
        print('   - Accuracy: ${position.accuracy}m');

        // If we got a position, try to restart the stream
        await _updatePosition(position);
        await _restartPositionStream();
        
        // If we successfully restarted the stream, stop fallback
        if (_isStreamActive) {
          print('✅ [LocationService] Successfully restarted stream, stopping fallback');
          timer.cancel();
          _isUsingFallback = false;
        }
      } catch (e) {
        print('❌ [LocationService] Fallback attempt failed: $e');
      }
    });
  }

  // Add new method for checking location service with retry
  Future<bool> _checkLocationServiceWithRetry() async {
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled()
            .timeout(const Duration(seconds: 5), onTimeout: () {
          print('⚠️ [LocationService] Location service check timed out');
          return false;
        });

        if (serviceEnabled) return true;

        if (attempt < 3) {
          print('⚠️ [LocationService] Location service disabled, retrying...');
          await Future.delayed(const Duration(seconds: 1));
        }
      } catch (e) {
        if (e is PlatformException && e.code == 'google_play_services_not_available') {
          print('⚠️ [LocationService] Google Play Services not available, attempting to continue');
          return true; // Try to continue anyway
        }
        print('⚠️ [LocationService] Error checking location service: $e');
        if (attempt < 3) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }
    return false;
  }

  // Add new method for getting current position with retry
  Future<Position> _getCurrentPositionWithRetry() async {
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: _isInBackground ? LocationAccuracy.medium : LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        ).timeout(const Duration(seconds: 5), onTimeout: () {
          print('⚠️ [LocationService] Test position request timed out');
          throw TimeoutException('Test position request timed out');
        });
      } catch (e) {
        if (attempt == 3) rethrow;
        print('⚠️ [LocationService] Error getting test position, retrying...');
        await Future.delayed(const Duration(seconds: 1));
      }
    }
    throw Exception('Failed to get test position after 3 attempts');
  }

  // Add new method to determine if an update is important
  bool _isImportantUpdate(Position position) {
    if (_lastPosition == null) return true;
    
    final distance = Geolocator.distanceBetween(
      _lastPosition!.latitude,
      _lastPosition!.longitude,
      position.latitude,
      position.longitude,
    );
    
    final timeDiff = DateTime.now().difference(_lastUpdateTime!).inSeconds;
    
    // Consider update important if:
    // 1. Moving faster than 5 m/s (18 km/h)
    // 2. Distance > 20 meters
    // 3. Time since last update > 10 seconds
    // 4. Accuracy improved significantly
    return position.speed > 5.0 ||
           distance > 20.0 ||
           timeDiff > 10 ||
           (position.accuracy < _lastPosition!.accuracy * 0.5);
  }

  // Add new method for force update timer
  void _startForceUpdateTimer() {
    _forceUpdateTimer?.cancel();
    _forceUpdateTimer = Timer.periodic(_forceUpdateInterval, (timer) async {
      if (!_isTracking) {
        timer.cancel();
        return;
      }

      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: _isInBackground ? LocationAccuracy.medium : LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );

        if (_isImportantUpdate(position)) {
          print('🔄 [LocationService] Forcing position update');
          await _updatePosition(position, isForced: true);
        }
      } catch (e) {
        print('⚠️ [LocationService] Error in force update: $e');
      }
    });
  }
} 