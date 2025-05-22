import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class SafetyZoneService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  
  // Stream controllers
  final _zoneStatusController = StreamController<ZoneStatus>.broadcast();
  
  // State
  List<SafetyZone> _safetyZones = [];
  Position? _lastPosition;
  Timer? _zoneCheckTimer;
  bool _isMonitoring = false;
  String? _currentTrackingId;
  
  // Constants
  static const Duration _zoneCheckInterval = Duration(seconds: 30);
  static const double _defaultZoneRadius = 100.0; // meters
  static const String _placesApiKey = 'YOUR_GOOGLE_PLACES_API_KEY'; // Replace with your API key
  
  // Streams
  Stream<ZoneStatus> get zoneStatusStream => _zoneStatusController.stream;
  
  SafetyZoneService() {
    _initializeNotifications();
  }
  
  Future<void> _initializeNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await _notifications.initialize(initSettings);
  }
  
  /// Start monitoring safety zones
  Future<void> startMonitoring(String trackingId, Position initialPosition) async {
    if (_isMonitoring) return;
    
    try {
      _currentTrackingId = trackingId;
      _lastPosition = initialPosition;
      _isMonitoring = true;
      
      // Load safety zones from Firestore
      await _loadSafetyZones();
      
      // Start periodic zone checking
      _zoneCheckTimer?.cancel();
      _zoneCheckTimer = Timer.periodic(_zoneCheckInterval, (_) {
        if (_lastPosition != null) {
          _checkSafetyZones(_lastPosition!);
        }
      });
      
      // Initial zone check
      _checkSafetyZones(initialPosition);
      
      print('✅ [SafetyZone] Zone monitoring started');
    } catch (e) {
      print('❌ [SafetyZone] Error starting zone monitoring: $e');
      rethrow;
    }
  }
  
  /// Stop monitoring safety zones
  Future<void> stopMonitoring() async {
    _zoneCheckTimer?.cancel();
    _zoneCheckTimer = null;
    _isMonitoring = false;
    _currentTrackingId = null;
    _safetyZones.clear();
    print('🛑 [SafetyZone] Zone monitoring stopped');
  }
  
  /// Load safety zones from Firestore
  Future<void> _loadSafetyZones() async {
    try {
      final snapshot = await _firestore
          .collection('safety_zones')
          .where('isActive', isEqualTo: true)
          .get();
      
      _safetyZones = snapshot.docs.map((doc) {
        final data = doc.data();
        return SafetyZone(
          id: doc.id,
          name: data['name'] ?? 'Unknown Zone',
          latitude: data['latitude'] ?? 0.0,
          longitude: data['longitude'] ?? 0.0,
          radius: data['radius'] ?? _defaultZoneRadius,
          type: SafetyZoneType.values.firstWhere(
            (type) => type.toString() == data['type'],
            orElse: () => SafetyZoneType.other,
          ),
          description: data['description'] ?? '',
        );
      }).toList();
      
      print('📋 [SafetyZone] Loaded ${_safetyZones.length} safety zones');
    } catch (e) {
      print('❌ [SafetyZone] Error loading safety zones: $e');
      rethrow;
    }
  }
  
  /// Check if position is within any safety zones
  Future<void> _checkSafetyZones(Position position) async {
    if (!_isMonitoring || _currentTrackingId == null) return;
    
    try {
      for (final zone in _safetyZones) {
        final distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          zone.latitude,
          zone.longitude,
        );
        
        final isInZone = distance <= zone.radius;
        final wasInZone = zone.isUserInZone;
        
        if (isInZone != wasInZone) {
          zone.isUserInZone = isInZone;
          await _handleZoneStatusChange(zone, isInZone, position);
        }
      }
    } catch (e) {
      print('❌ [SafetyZone] Error checking safety zones: $e');
    }
  }
  
  /// Handle zone status change
  Future<void> _handleZoneStatusChange(
    SafetyZone zone,
    bool entered,
    Position position,
  ) async {
    try {
      // Update Firestore
      await _firestore.collection('emergency_tracking').doc(_currentTrackingId).update({
        'zoneStatus': {
          'zoneId': zone.id,
          'zoneName': zone.name,
          'zoneType': zone.type.toString(),
          'status': entered ? 'entered' : 'exited',
          'timestamp': FieldValue.serverTimestamp(),
          'position': {
            'latitude': position.latitude,
            'longitude': position.longitude,
            'accuracy': position.accuracy,
          },
        },
      });
      
      // Send notification
      await _sendZoneNotification(zone, entered);
      
      // Broadcast status change
      _zoneStatusController.add(ZoneStatus(
        zone: zone,
        entered: entered,
        position: position,
        timestamp: DateTime.now(),
      ));
      
      print('${entered ? '📍' : '🚶'} [SafetyZone] User ${entered ? 'entered' : 'exited'} zone: ${zone.name}');
    } catch (e) {
      print('❌ [SafetyZone] Error handling zone status change: $e');
    }
  }
  
  /// Send zone notification
  Future<void> _sendZoneNotification(SafetyZone zone, bool entered) async {
    final androidDetails = AndroidNotificationDetails(
      'safety_zone_channel',
      'Safety Zone Alerts',
      channelDescription: 'Notifications for safety zone status changes',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );
    
    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    await _notifications.show(
      zone.hashCode,
      'Safety Zone Alert',
      'You have ${entered ? 'entered' : 'exited'} ${zone.name}',
      details,
      payload: json.encode({
        'zoneId': zone.id,
        'entered': entered,
        'timestamp': DateTime.now().toIso8601String(),
      }),
    );
  }
  
  /// Search for nearby places using Google Places API
  Future<List<SafetyZone>> searchNearbyPlaces(Position position) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
        '?location=${position.latitude},${position.longitude}'
        '&radius=1000'
        '&type=police|hospital|fire_station'
        '&key=$_placesApiKey',
      );
      
      final response = await http.get(url);
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch nearby places');
      }
      
      final data = json.decode(response.body);
      final results = data['results'] as List;
      
      return results.map((place) {
        final location = place['geometry']['location'];
        return SafetyZone(
          id: place['place_id'],
          name: place['name'],
          latitude: location['lat'],
          longitude: location['lng'],
          radius: _defaultZoneRadius,
          type: _getZoneTypeFromPlaceType(place['types']),
          description: place['vicinity'] ?? '',
        );
      }).toList();
    } catch (e) {
      print('❌ [SafetyZone] Error searching nearby places: $e');
      return [];
    }
  }
  
  /// Get zone type from Google Places type
  SafetyZoneType _getZoneTypeFromPlaceType(List<dynamic> types) {
    if (types.contains('police')) return SafetyZoneType.police;
    if (types.contains('hospital')) return SafetyZoneType.hospital;
    if (types.contains('fire_station')) return SafetyZoneType.fireStation;
    return SafetyZoneType.other;
  }
  
  /// Dispose the service
  void dispose() {
    stopMonitoring();
    _zoneStatusController.close();
  }
}

/// Safety zone model
class SafetyZone {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double radius;
  final SafetyZoneType type;
  final String description;
  bool isUserInZone;
  
  SafetyZone({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radius,
    required this.type,
    required this.description,
    this.isUserInZone = false,
  });
  
  LatLng get location => LatLng(latitude, longitude);
}

/// Safety zone types
enum SafetyZoneType {
  police,
  hospital,
  fireStation,
  school,
  home,
  work,
  other,
}

/// Zone status model
class ZoneStatus {
  final SafetyZone zone;
  final bool entered;
  final Position position;
  final DateTime timestamp;
  
  ZoneStatus({
    required this.zone,
    required this.entered,
    required this.position,
    required this.timestamp,
  });
} 