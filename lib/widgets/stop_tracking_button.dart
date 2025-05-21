import 'package:flutter/material.dart';
import '../services/location_tracking_service.dart';

class StopTrackingButton extends StatelessWidget {
  final LocationTrackingService _trackingService;
  final String? trackingId;
  final VoidCallback? onStopped;

  const StopTrackingButton({
    Key? key,
    required LocationTrackingService trackingService,
    this.trackingId,
    this.onStopped,
  }) : super(key: key);

  Future<void> _stopTracking(BuildContext context) async {
    if (trackingId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No active tracking session'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      await _trackingService.stopTracking();
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location tracking stopped'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }

      onStopped?.call();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error stopping tracking: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () => _stopTracking(context),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      icon: const Icon(Icons.location_off),
      label: const Text(
        'Stop Tracking',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }
} 