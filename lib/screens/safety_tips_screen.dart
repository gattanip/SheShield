import 'package:flutter/material.dart';
import 'package:sheshield/services/safety_tips_service.dart';

class SafetyTipsScreen extends StatelessWidget {
  const SafetyTipsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final safetyTips = SafetyTipsService.getAllSafetyTips();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Safety Tips'),
        backgroundColor: Colors.pink,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.pink.withOpacity(0.1),
              Colors.white,
            ],
          ),
        ),
        child: Column(
          children: [
            // Header section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.pink.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.tips_and_updates,
                    size: 48,
                    color: Colors.pink,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Stay Safe, Stay Smart',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.pink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Important safety tips to help you stay protected',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            // Tips list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: safetyTips.length,
                itemBuilder: (context, index) {
                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: CircleAvatar(
                        backgroundColor: Colors.pink.shade100,
                        radius: 24,
                        child: Icon(
                          _getIconForTip(index),
                          color: Colors.pink.shade700,
                          size: 24,
                        ),
                      ),
                      title: Text(
                        safetyTips[index],
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          _getTipDescription(index),
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIconForTip(int index) {
    // Return different icons based on the tip index
    switch (index % 6) {
      case 0:
        return Icons.location_on;
      case 1:
        return Icons.phone_android;
      case 2:
        return Icons.people;
      case 3:
        return Icons.nightlight_round;
      case 4:
        return Icons.directions_walk;
      case 5:
        return Icons.security;
      default:
        return Icons.tips_and_updates;
    }
  }

  String _getTipDescription(int index) {
    // Return additional descriptions for each tip
    switch (index % 6) {
      case 0:
        return 'Always share your location with trusted contacts when traveling alone.';
      case 1:
        return 'Keep your phone charged and easily accessible at all times.';
      case 2:
        return 'Stay in well-lit, populated areas and avoid isolated places.';
      case 3:
        return 'Be extra cautious at night and avoid walking alone in dark areas.';
      case 4:
        return 'Trust your instincts and be aware of your surroundings.';
      case 5:
        return 'Keep emergency contacts updated and easily accessible.';
      default:
        return 'Stay alert and be prepared for any situation.';
    }
  }
} 