import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';

// Define the callback function for the foreground task
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(LocationTaskHandler());
}

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  static const String _locationChannelId = 'sheshield_location_channel';
  static const String _locationChannelName = 'Location Tracking';
  static const String _locationChannelDesc = 'This notification is used to track your location in case of emergency.';
  
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  String? _trackingId;
  StreamSubscription<Position>? _positionStream;

  String getTrackingUrl() {
    if (_trackingId == null) {
      throw Exception('Location tracking not started');
    }
    // Return the web URL where the location can be tracked
    return 'https://sheshiled-f0cc6.web.app/loc/$_trackingId';
  }

  Future<Position> getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions are permanently denied');
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  Future<void> startLocationTracking() async {
    if (_trackingId != null) return;

    final status = await Permission.location.request();
    if (!status.isGranted) {
      throw Exception('Location permission not granted');
    }

    _trackingId = DateTime.now().millisecondsSinceEpoch.toString();
    final position = await getCurrentLocation();

    await _database.child('locations/$_trackingId').set({
      'latitude': position.latitude,
      'longitude': position.longitude,
      'timestamp': ServerValue.timestamp,
      'status': 'active',
    });

    // Start the foreground service
    await FlutterForegroundTask.startService(
      notificationTitle: 'SheShield Location Tracking',
      notificationText: 'Tracking your location for safety',
      callback: startCallback,
    );

    // Start position updates
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position position) async {
      if (_trackingId != null) {
        try {
          await _database.child('locations/$_trackingId').update({
            'latitude': position.latitude,
            'longitude': position.longitude,
            'timestamp': ServerValue.timestamp,
            'status': 'active',
          });
        } catch (e) {
          debugPrint('Error updating location: $e');
        }
      }
    });
  }

  Future<void> stopLocationTracking() async {
    if (_trackingId == null) return;

    await _positionStream?.cancel();
    _positionStream = null;

    await _database.child('locations/$_trackingId').update({
      'status': 'inactive',
      'timestamp': ServerValue.timestamp,
    });

    await FlutterForegroundTask.stopService();
    _trackingId = null;
  }

  Future<void> shareLocation(String phoneNumber) async {
    final position = await getCurrentLocation();
    final url = 'https://maps.google.com/?q=${position.latitude},${position.longitude}';
    final whatsappUrl = 'https://wa.me/$phoneNumber?text=My current location: $url';

    if (await canLaunchUrl(Uri.parse(whatsappUrl))) {
      await launchUrl(Uri.parse(whatsappUrl));
    } else {
      throw Exception('Could not launch WhatsApp');
    }
  }
}

@pragma('vm:entry-point')
class LocationTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Initialize any resources needed for the background task
  }

  @override
  Future<void> onEvent(DateTime timestamp, SendPort? sendPort) async {
    // This method is called periodically based on the taskInterval
    // We don't need to do anything here as we're using the position stream
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // Clean up any resources when the task is destroyed
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // This method is called when the task is repeated
    // We don't need to implement this as we're using the position stream
  }
} 