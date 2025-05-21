import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'location_tracking_service.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';

class LocationServiceProvider extends ChangeNotifier {
  final LocationTrackingService _locationService = LocationTrackingService();
  bool _isTracking = false;
  bool _isInitialized = false;
  String? _currentTrackingId;
  Position? _lastPosition;
  DateTime? _lastUpdateTime;
  bool _isLocationServiceEnabled = false;
  bool _hasLocationPermission = false;
  bool _hasBackgroundPermission = false;
  bool _isHighAccuracyMode = true;
  int _updateCount = 0;
  Timer? _statusCheckTimer;

  // Getters
  bool get isTracking => _isTracking;
  bool get isInitialized => _isInitialized;
  String? get currentTrackingId => _currentTrackingId;
  Position? get lastPosition => _lastPosition;
  DateTime? get lastUpdateTime => _lastUpdateTime;
  bool get isLocationServiceEnabled => _isLocationServiceEnabled;
  bool get hasLocationPermission => _hasLocationPermission;
  bool get hasBackgroundPermission => _hasBackgroundPermission;
  bool get isHighAccuracyMode => _isHighAccuracyMode;
  int get updateCount => _updateCount;

  // Initialize the service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      print('🚀 [LocationProvider] Initializing location service...');
      
      // Check if tracking is already active
      _isTracking = await _locationService.isTrackingActive();
      if (_isTracking) {
        _currentTrackingId = await _locationService.getCurrentTrackingId();
        print('📱 [LocationProvider] Tracking already active with ID: $_currentTrackingId');
      }

      // Check location service status
      _isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
      print('📍 [LocationProvider] Location service enabled: $_isLocationServiceEnabled');

      // Check permissions
      await _checkAndRequestPermissions();

      // Start periodic status checks
      _startStatusCheck();

      _isInitialized = true;
      notifyListeners();
      print('✅ [LocationProvider] Initialization complete');
    } catch (e) {
      print('❌ [LocationProvider] Error initializing: $e');
      rethrow;
    }
  }

  // Check and request permissions
  Future<void> _checkAndRequestPermissions() async {
    try {
      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      _hasLocationPermission = permission == LocationPermission.whileInUse || 
                             permission == LocationPermission.always;
      print('🔑 [LocationProvider] Location permission: $_hasLocationPermission');

      // Check background permission
      if (_hasLocationPermission) {
        permission = await Geolocator.checkPermission();
        _hasBackgroundPermission = permission == LocationPermission.always;
        if (!_hasBackgroundPermission) {
          permission = await Geolocator.requestPermission();
          _hasBackgroundPermission = permission == LocationPermission.always;
        }
        print('🔑 [LocationProvider] Background permission: $_hasBackgroundPermission');
      }

      notifyListeners();
    } catch (e) {
      print('❌ [LocationProvider] Error checking permissions: $e');
      rethrow;
    }
  }

  // Start tracking
  Future<void> startTracking() async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_isTracking) {
      print('⚠️ [LocationProvider] Tracking already active');
      return;
    }

    try {
      print('🚀 [LocationProvider] Starting location tracking...');
      
      // Ensure permissions are granted
      if (!_hasLocationPermission) {
        await _checkAndRequestPermissions();
        if (!_hasLocationPermission) {
          throw Exception('Location permission not granted');
        }
      }

      // Start tracking
      _currentTrackingId = await _locationService.startTracking();
      _isTracking = true;
      _isHighAccuracyMode = true;
      _updateCount = 0;

      // Start listening to position updates
      _locationService.onPositionUpdate.listen((position) {
        _lastPosition = position;
        _lastUpdateTime = DateTime.now();
        _updateCount++;
        notifyListeners();
      });

      notifyListeners();
      print('✅ [LocationProvider] Tracking started successfully');
    } catch (e) {
      print('❌ [LocationProvider] Error starting tracking: $e');
      rethrow;
    }
  }

  // Stop tracking
  Future<void> stopTracking() async {
    if (!_isTracking) {
      print('⚠️ [LocationProvider] Tracking not active');
      return;
    }

    try {
      print('🛑 [LocationProvider] Stopping location tracking...');
      await _locationService.stopTracking();
      _isTracking = false;
      _currentTrackingId = null;
      _lastPosition = null;
      _lastUpdateTime = null;
      _updateCount = 0;
      notifyListeners();
      print('✅ [LocationProvider] Tracking stopped successfully');
    } catch (e) {
      print('❌ [LocationProvider] Error stopping tracking: $e');
      rethrow;
    }
  }

  // Start periodic status check
  void _startStatusCheck() {
    _statusCheckTimer?.cancel();
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        // Check location service status
        final wasEnabled = _isLocationServiceEnabled;
        _isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
        if (wasEnabled != _isLocationServiceEnabled) {
          print('📍 [LocationProvider] Location service status changed: $_isLocationServiceEnabled');
          notifyListeners();
        }

        // Check tracking status
        if (_isTracking) {
          final isStillTracking = await _locationService.isTrackingActive();
          if (!isStillTracking) {
            print('⚠️ [LocationProvider] Tracking stopped unexpectedly');
            _isTracking = false;
            _currentTrackingId = null;
            notifyListeners();
          }
        }

        // Check permissions
        await _checkAndRequestPermissions();
      } catch (e) {
        print('❌ [LocationProvider] Error in status check: $e');
      }
    });
  }

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
    super.dispose();
  }
} 