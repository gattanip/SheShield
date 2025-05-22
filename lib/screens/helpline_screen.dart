import 'package:flutter/material.dart';
import 'package:sheshield/services/helpline_service.dart';

class HelplineScreen extends StatelessWidget {
  const HelplineScreen({Key? key}) : super(key: key);

  Widget _buildSpeedDialButtons() {
    // Show only the most important helplines as speed dials
    final speedDials = [
      HelplineService.helplines[0], // Women Helpline
      HelplineService.helplines[1], // Police
      HelplineService.helplines[2], // Ambulance
      HelplineService.helplines[3], // Fire
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              'Quick Dial',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: speedDials.map((helpline) {
              IconData icon;
              switch (helpline.name) {
                case "Police": icon = Icons.local_police; break;
                case "Ambulance": icon = Icons.local_hospital; break;
                case "Fire": icon = Icons.local_fire_department; break;
                case "Women Helpline (All India)": icon = Icons.phone_in_talk; break;
                default: icon = Icons.phone;
              }
              return Column(
                children: [
                  InkWell(
                    onTap: () => HelplineService.dialHelpline(helpline.number),
                    borderRadius: BorderRadius.circular(32),
                    child: CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.red.shade100,
                      child: Icon(icon, color: Colors.red, size: 32),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    helpline.name.split(' ')[0],
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Emergency Helplines")),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Speed Dial section
          _buildSpeedDialButtons(),
          const SizedBox(height: 24),
          // All helplines section
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              'All Emergency Numbers',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // List of all helplines
          ...HelplineService.helplines.map((helpline) => Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: InkWell(
              onTap: () => HelplineService.dialHelpline(helpline.number),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            helpline.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            helpline.number,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.phone,
                      color: Theme.of(context).primaryColor,
                    ),
                  ],
                ),
              ),
            ),
          )).toList(),
        ],
      ),
    );
  }
} 