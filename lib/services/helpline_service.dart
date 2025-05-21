import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class HelplineService {
  static const List<Helpline> helplines = [
    Helpline("Women Helpline (All India)", "1091"),
    Helpline("Police", "100"),
    Helpline("Ambulance", "102"),
    Helpline("Fire", "101"),
    Helpline("Anti Poison", "1066"),
    Helpline("Railway Helpline", "139"),
    Helpline("Senior Citizen Helpline", "14567"),
    Helpline("Child Helpline", "1098"),
    Helpline("Anti Ragging", "1800-180-5522"),
    Helpline("Cyber Crime", "155620")
  ];

  static Future<void> dialHelpline(String number) async {
    final Uri uri = Uri(scheme: "tel", path: number);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      debugPrint("Could not dial helpline number: $number");
    }
  }
}

class Helpline {
  final String name;
  final String number;

  const Helpline(this.name, this.number);
} 