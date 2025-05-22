import 'package:flutter/material.dart';
import '../services/emergency_media_service.dart';

class EmergencyMediaControls extends StatefulWidget {
  final EmergencyMediaService service;
  final VoidCallback onStop;

  const EmergencyMediaControls({
    super.key,
    required this.service,
    required this.onStop,
  });

  @override
  State<EmergencyMediaControls> createState() => _EmergencyMediaControlsState();
}

class _EmergencyMediaControlsState extends State<EmergencyMediaControls> {
  String _selectedStrategy = 'balanced';
  bool _isSharing = false;

  Future<void> _shareMedia() async {
    if (_isSharing) return;

    setState(() => _isSharing = true);
    try {
      final sessionId = widget.service.currentSessionId;
      if (sessionId != null) {
        await widget.service.shareMedia(sessionId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Media shared successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No active media session to share'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing media: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSharing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Media Capture Settings',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedStrategy,
              decoration: const InputDecoration(
                labelText: 'Capture Strategy',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'balanced',
                  child: Text('Balanced (30s interval)'),
                ),
                DropdownMenuItem(
                  value: 'aggressive',
                  child: Text('Aggressive (15s interval + video/audio)'),
                ),
                DropdownMenuItem(
                  value: 'conservative',
                  child: Text('Conservative (60s interval)'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedStrategy = value);
                  widget.service.setCaptureStrategy(value);
                }
              },
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: widget.onStop,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop Capture'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isSharing ? null : _shareMedia,
                  icon: _isSharing 
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.share),
                  label: Text(_isSharing ? 'Sharing...' : 'Share Media'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
} 