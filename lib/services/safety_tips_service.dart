import 'dart:math';

import 'package:flutter/material.dart';

class SafetyTipsService {
  static const List<String> _safetyTips = [
    "Always share your live location with a trusted contact.",
    "Avoid walking alone at night.",
    "Keep your phone charged.",
    "Trust your instincts.",
    "Use a buddy system.",
    "Be aware of your surroundings.",
    "Carry a whistle.",
    "Use a ride-sharing app.",
    "Avoid isolated areas.",
    "Keep emergency contacts updated."
  ];

  static String getRandomSafetyTip() {
    final random = Random();
    int index = random.nextInt(_safetyTips.length);
    return _safetyTips[index];
  }

  static List<String> getAllSafetyTips() {
    return List.from(_safetyTips);
  }
} 