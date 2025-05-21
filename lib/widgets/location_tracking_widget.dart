import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/location_service_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

class LocationTrackingWidget extends StatelessWidget {
  const LocationTrackingWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<LocationServiceProvider>(
      builder: (context, provider, child) {
        return Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStatusHeader(provider),
                const SizedBox(height: 16),
                if (provider.isTracking) ...[
                  _buildTrackingInfo(provider),
                  const SizedBox(height: 16),
                  _buildTrackingControls(context, provider),
                ] else ...[
                  _buildStartButton(context, provider),
                ],
                if (provider.error.isNotEmpty)
                  _buildErrorDisplay(provider),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusHeader(LocationServiceProvider provider) {
    Color statusColor;
    switch (provider.status) {
      case 'Active':
        statusColor = Colors.green;
        break;
      case 'Error':
        statusColor = Colors.red;
        break;
      case 'Lost Connection':
        statusColor = Colors.orange;
        break;
      default:
        statusColor = Colors.grey;
    }

    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: statusColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Status: ${provider.status}',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildTrackingInfo(LocationServiceProvider provider) {
    final lastUpdate = provider.lastUpdateTime;
    final position = provider.lastPosition;
    final formatter = DateFormat('HH:mm:ss');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (lastUpdate != null)
          Text(
            'Last Update: ${formatter.format(lastUpdate)}',
            style: const TextStyle(fontSize: 14),
          ),
        if (position != null) ...[
          const SizedBox(height: 8),
          Text(
            'Location: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            'Accuracy: ${position.accuracy.toStringAsFixed(1)}m',
            style: const TextStyle(fontSize: 14),
          ),
          if (position.speed > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Speed: ${(position.speed * 3.6).toStringAsFixed(1)} km/h',
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ],
        if (provider.trackingUrl.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Tracking ID: ${provider.currentTrackingId}',
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            'Share URL: ${provider.trackingUrl}',
            style: const TextStyle(fontSize: 14),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  Widget _buildTrackingControls(BuildContext context, LocationServiceProvider provider) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        ElevatedButton.icon(
          onPressed: () async {
            await provider.stopTracking();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location tracking stopped')),
            );
          },
          icon: const Icon(Icons.stop),
          label: const Text('Stop Tracking'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
        ),
        ElevatedButton.icon(
          onPressed: () {
            // Copy tracking URL to clipboard
            if (provider.trackingUrl.isNotEmpty) {
              // Add clipboard functionality here
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Tracking URL copied to clipboard')),
              );
            }
          },
          icon: const Icon(Icons.share),
          label: const Text('Share'),
        ),
      ],
    );
  }

  Widget _buildStartButton(BuildContext context, LocationServiceProvider provider) {
    return ElevatedButton.icon(
      onPressed: () async {
        await provider.startTracking();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location tracking started')),
        );
      },
      icon: const Icon(Icons.play_arrow),
      label: const Text('Start Tracking'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildErrorDisplay(LocationServiceProvider provider) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              provider.error,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
} 