import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../widgets/location_map.dart';
import '../services/location_service.dart';
import '../services/location_tracking_service.dart';
import 'dart:async';

class TrackingPage extends StatefulWidget {
  final String trackingId;
  final bool isLiveTracking;

  const TrackingPage({
    Key? key,
    required this.trackingId,
    this.isLiveTracking = false,
  }) : super(key: key);

  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends State<TrackingPage> {
  final LocationService _locationService = LocationService();
  final LocationTrackingService _trackingService = LocationTrackingService();
  StreamSubscription<DocumentSnapshot>? _trackingSubscription;
  Map<String, dynamic>? _trackingData;
  Position? _currentPosition;
  bool _isLoading = true;
  String? _error;
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    _initializeTracking();
  }

  @override
  void dispose() {
    _trackingSubscription?.cancel();
    _updateTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeTracking() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Initialize location service if needed
      if (!_locationService.isInitialized) {
        await _locationService.initialize();
      }

      // Start listening to tracking updates
      _startTrackingUpdates();

      // Start periodic updates for current location
      _updateTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!widget.isLiveTracking) {
          _getCurrentLocation();
        }
      });

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      debugPrint('Error initializing tracking: $e');
    }
  }

  void _startTrackingUpdates() {
    // Listen to Firestore updates from the locations collection
    _trackingSubscription = FirebaseFirestore.instance
        .collection('locations')
        .doc(widget.trackingId)
        .snapshots()
        .listen(
      (snapshot) {
        if (!snapshot.exists) {
          setState(() => _error = 'Tracking session not found');
          return;
        }

        final data = snapshot.data() as Map<String, dynamic>;
        setState(() {
          _trackingData = data;
          _error = null;
        });

        // Update current position if available
        if (data['currentPosition'] != null) {
          final position = data['currentPosition'] as Map<String, dynamic>;
          _currentPosition = Position(
            latitude: position['latitude'],
            longitude: position['longitude'],
            timestamp: (position['timestamp'] as Timestamp).toDate(),
            accuracy: position['accuracy']?.toDouble() ?? 0.0,
            altitude: 0.0,
            heading: position['heading']?.toDouble() ?? 0.0,
            speed: position['speed']?.toDouble() ?? 0.0,
            speedAccuracy: 0.0,
            altitudeAccuracy: 0.0,
            headingAccuracy: 0.0,
          );
        }
      },
      onError: (error) {
        setState(() => _error = error.toString());
        debugPrint('Error in tracking subscription: $error');
      },
    );
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );
      setState(() => _currentPosition = position);
    } catch (e) {
      debugPrint('Error getting current location: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Tracking Error'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                'Error: $_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _initializeTracking,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isLiveTracking ? 'Live Tracking' : 'Location History'),
        actions: [
          if (_trackingData != null)
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: () {
                // Share tracking link
                final trackingUrl = 'https://your-domain.com/track/${widget.trackingId}';
                // TODO: Implement share functionality
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LocationMap(
              trackingId: widget.trackingId,
              isLiveTracking: widget.isLiveTracking,
              showControls: true,
              onLocationUpdate: (position) {
                setState(() => _currentPosition = position);
              },
            ),
          ),
          if (_currentPosition != null)
            Container(
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).cardColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Location',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Lat: ${_currentPosition!.latitude.toStringAsFixed(6)}\n'
                          'Lng: ${_currentPosition!.longitude.toStringAsFixed(6)}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Accuracy: ${_currentPosition!.accuracy.toStringAsFixed(1)}m',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (_currentPosition!.speed > 0)
                            Text(
                              'Speed: ${(_currentPosition!.speed * 3.6).toStringAsFixed(1)} km/h',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
} 