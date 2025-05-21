class EmergencyContact {
  final String name;
  final String phoneNumber;
  final String? email;

  EmergencyContact({
    required this.name,
    required this.phoneNumber,
    this.email,
  });

  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      name: json['name'] as String,
      phoneNumber: json['phoneNumber'] as String,
      email: json['email'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'phoneNumber': phoneNumber,
      if (email != null) 'email': email,
    };
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