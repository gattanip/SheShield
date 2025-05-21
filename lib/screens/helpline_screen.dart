import 'package:flutter/material.dart';
import 'package:sheshield/services/helpline_service.dart';

class HelplineScreen extends StatelessWidget {
  const HelplineScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Indian Helpline Numbers")),
      body: ListView.builder(
        itemCount: HelplineService.helplines.length,
        itemBuilder: (context, index) {
          Helpline helpline = HelplineService.helplines[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: InkWell(
              onTap: () => HelplineService.dialHelpline(helpline.number),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(helpline.name, style: const TextStyle(fontSize: 16)),
                    Text(helpline.number, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
} 