import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

class LocationMap extends StatefulWidget {
  final String? trackingId;
  final bool isLiveTracking;
  final bool showControls;
  final Function(Position)? onLocationUpdate;

  const LocationMap({
    Key? key,
    this.trackingId,
    this.isLiveTracking = false,
    this.showControls = true,
    this.onLocationUpdate,
  }) : super(key: key);

  @override
  State<LocationMap> createState() => _LocationMapState();
}

class _LocationMapState extends State<LocationMap> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  List<LatLng> _positionHistory = [];
  Position? _currentPosition;
  StreamSubscription<DocumentSnapshot>? _trackingSubscription;
  bool _isFollowing = true;
  bool _isHighAccuracy = true;
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    if (widget.isLiveTracking && widget.trackingId != null) {
      _startTrackingUpdates();
    } else {
      _getCurrentLocation();
    }
  }

  @override
  void dispose() {
    _trackingSubscription?.cancel();
    _updateTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: _isHighAccuracy 
          ? LocationAccuracy.bestForNavigation 
          : LocationAccuracy.medium,
      );
      _updatePosition(position);
    } catch (e) {
      debugPrint('Error getting current location: $e');
    }
  }

  void _startTrackingUpdates() {
    if (widget.trackingId == null) return;

    // Listen to Firestore updates
    _trackingSubscription = FirebaseFirestore.instance
        .collection('locations')
        .doc(widget.trackingId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists) return;

      final data = snapshot.data() as Map<String, dynamic>;
      final position = data['currentPosition'] as Map<String, dynamic>;
      
      final newPosition = Position(
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

      _updatePosition(newPosition);
    });

    // Start periodic updates for current location
    _updateTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!widget.isLiveTracking) {
        _getCurrentLocation();
      }
    });
  }

  void _updatePosition(Position position) {
    if (!mounted) return;

    setState(() {
      _currentPosition = position;
      final latLng = LatLng(position.latitude, position.longitude);
      
      // Update markers
      _markers = {
        Marker(
          markerId: const MarkerId('current_location'),
          position: latLng,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          rotation: position.heading,
          anchor: const Offset(0.5, 0.5),
          infoWindow: InfoWindow(
            title: 'Current Location',
            snippet: 'Accuracy: ${position.accuracy.toStringAsFixed(1)}m',
          ),
        ),
      };

      // Update position history
      _positionHistory.add(latLng);
      if (_positionHistory.length > 100) {
        _positionHistory.removeAt(0);
      }

      // Update polylines
      _polylines = {
        Polyline(
          polylineId: const PolylineId('track'),
          points: _positionHistory,
          color: Colors.blue,
          width: 3,
        ),
      };
    });

    // Move camera if following
    if (_isFollowing && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: latLng,
            zoom: 18,
            bearing: position.heading,
            tilt: 45,
          ),
        ),
      );
    }

    // Notify parent widget
    widget.onLocationUpdate?.call(position);
  }

  @override
  Widget build(BuildContext context) {
    if (_currentPosition == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
            ),
            zoom: 18,
            bearing: _currentPosition!.heading,
            tilt: 45,
          ),
          onMapCreated: (controller) => _mapController = controller,
          markers: _markers,
          polylines: _polylines,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          compassEnabled: true,
          mapToolbarEnabled: false,
          zoomControlsEnabled: false,
          onCameraMove: (position) {
            if (_isFollowing) {
              setState(() => _isFollowing = false);
            }
          },
        ),
        if (widget.showControls)
          Positioned(
            right: 16,
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                  heroTag: 'follow',
                  onPressed: () {
                    setState(() => _isFollowing = true);
                    if (_currentPosition != null) {
                      _mapController?.animateCamera(
                        CameraUpdate.newCameraPosition(
                          CameraPosition(
                            target: LatLng(
                              _currentPosition!.latitude,
                              _currentPosition!.longitude,
                            ),
                            zoom: 18,
                            bearing: _currentPosition!.heading,
                            tilt: 45,
                          ),
                        ),
                      );
                    }
                  },
                  child: Icon(
                    _isFollowing ? Icons.gps_fixed : Icons.gps_not_fixed,
                    color: _isFollowing ? Colors.blue : Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  heroTag: 'accuracy',
                  onPressed: () {
                    setState(() => _isHighAccuracy = !_isHighAccuracy);
                    _getCurrentLocation();
                  },
                  child: Icon(
                    _isHighAccuracy ? Icons.high_quality : Icons.low_quality,
                    color: _isHighAccuracy ? Colors.blue : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
} 