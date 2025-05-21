import 'package:flutter/foundation.dart';

class EmergencyContact {
  final String name;
  final String phoneNumber;
  final String? email;

  EmergencyContact({
    required this.name,
    required this.phoneNumber,
    this.email,
  });

  // Convert Contact to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'phoneNumber': phoneNumber,
      'email': email,
    };
  }

  // Create Contact from JSON
  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      name: json['name'] as String,
      phoneNumber: json['phoneNumber'] as String,
      email: json['email'] as String?,
    );
  }

  // Create a copy of Contact with optional new values
  EmergencyContact copyWith({
    String? name,
    String? phoneNumber,
    String? email,
  }) {
    return EmergencyContact(
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmergencyContact &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          phoneNumber == other.phoneNumber &&
          email == other.email;

  @override
  int get hashCode => name.hashCode ^ phoneNumber.hashCode ^ email.hashCode;
} 