import 'package:flutter/material.dart';
import '../services/emergency_media_service.dart';
import '../services/location_service.dart';

class EmergencyStatusDetails extends StatelessWidget {
  final EmergencyMediaService mediaService;
  final LocationService locationService;
  final DateTime startTime;

  const EmergencyStatusDetails({
    super.key,
    required this.mediaService,
    required this.locationService,
    required this.startTime,
  });

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildStatusCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
    Widget? trailing,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final duration = DateTime.now().difference(startTime);
    final locationStatus = locationService.isSharing ? 'Active' : 'Inactive';
    final mediaStatus = mediaService.isActive ? 'Active' : 'Inactive';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStatusCard(
          icon: Icons.timer,
          title: 'Emergency Duration',
          value: _formatDuration(duration),
          color: Colors.orange,
        ),
        _buildStatusCard(
          icon: Icons.location_on,
          title: 'Location Tracking',
          value: locationStatus,
          color: locationStatus == 'Active' ? Colors.green : Colors.red,
          trailing: locationStatus == 'Active'
              ? Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.3),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                )
              : null,
        ),
        _buildStatusCard(
          icon: Icons.photo_camera,
          title: 'Media Capture',
          value: mediaStatus,
          color: mediaStatus == 'Active' ? Colors.green : Colors.red,
          trailing: mediaStatus == 'Active'
              ? Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.3),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                )
              : null,
        ),
        _buildStatusCard(
          icon: Icons.cloud_upload,
          title: 'Upload Status',
          value: 'Google Drive',
          color: Colors.blue,
          trailing: Icon(
            Icons.check_circle,
            color: Colors.green,
            size: 24,
          ),
        ),
        _buildStatusCard(
          icon: Icons.people,
          title: 'Emergency Contacts',
          value: 'Notified',
          color: Colors.purple,
          trailing: Icon(
            Icons.check_circle,
            color: Colors.green,
            size: 24,
          ),
        ),
      ],
    );
  }
} 