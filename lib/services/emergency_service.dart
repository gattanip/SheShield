import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import '../models/contact.dart';
import 'location_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'location_tracking_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'emergency_audio_service.dart';
import 'package:flutter/material.dart';

class EmergencyService {
  static const platform = MethodChannel('com.SheShield.app/emergency');
  static const String _contactsKey = 'emergency_contacts';
  final LocationService _locationService = LocationService();
  final LocationTrackingService _locationTracking = LocationTrackingService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final EmergencyAudioService _audioService = EmergencyAudioService();
  bool _isEmergencyActive = false;
  bool _messageSent = false;

  // Audio settings
  bool _emergencySoundEnabled = true;
  bool _alertSoundEnabled = true;
  bool _vibrationEnabled = true;

  // Get emergency contacts from storage
  Future<List<EmergencyContact>> getContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final contactsJson = prefs.getStringList(_contactsKey) ?? [];
    return contactsJson
        .map((contact) => EmergencyContact.fromJson(json.decode(contact)))
        .toList();
  }

  // Save emergency contact
  Future<void> addContact(EmergencyContact contact) async {
    final prefs = await SharedPreferences.getInstance();
    final contacts = await getContacts();
    
    // Format phone number (ensure it starts with country code)
    String formattedNumber = contact.phoneNumber.trim();
    if (!formattedNumber.startsWith('+')) {
      formattedNumber = '+91$formattedNumber'; // Default to India country code
    }
    final formattedContact = contact.copyWith(phoneNumber: formattedNumber);
    contacts.add(formattedContact);
    
    final contactsJson = contacts
        .map((contact) => json.encode(contact.toJson()))
        .toList();
    
    await prefs.setStringList(_contactsKey, contactsJson);
  }

  // Remove emergency contact
  Future<void> removeContact(EmergencyContact contact) async {
    final prefs = await SharedPreferences.getInstance();
    final contacts = await getContacts();
    
    contacts.removeWhere((c) => c.phoneNumber == contact.phoneNumber);
    
    final contactsJson = contacts
        .map((contact) => json.encode(contact.toJson()))
        .toList();
    
    await prefs.setStringList(_contactsKey, contactsJson);
  }

  Future<void> initialize() async {
    try {
      debugPrint('Initializing emergency service...');
      await _loadSettings();
      await _audioService.initialize();
      debugPrint('Emergency service initialized successfully');
    } catch (e, stackTrace) {
      debugPrint('Error initializing emergency service: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _emergencySoundEnabled = prefs.getBool('emergency_sound_enabled') ?? true;
    _alertSoundEnabled = prefs.getBool('alert_sound_enabled') ?? true;
    _vibrationEnabled = prefs.getBool('vibration_enabled') ?? true;
    debugPrint('Loaded audio settings: emergency=$_emergencySoundEnabled, alert=$_alertSoundEnabled, vibration=$_vibrationEnabled');
  }

  Future<void> sendEmergencyAlert(BuildContext context) async {
    if (_isEmergencyActive) {
      debugPrint('Emergency already active');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Emergency already active!'), backgroundColor: Colors.orange),
      );
      return;
    }

    try {
      debugPrint('Starting emergency alert...');
      _isEmergencyActive = true;
      _messageSent = false;

      // Reload settings in case they changed
      await _loadSettings();

      // Start location tracking first
      debugPrint('Starting location tracking...');
      String trackingId;
      try {
        trackingId = await _locationTracking.startTracking();
        debugPrint('Location tracking started with ID: $trackingId');
      } catch (e) {
        debugPrint('Location permission or tracking error: $e');
        // Don't reset emergency state on tracking error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Location error: $e'), backgroundColor: Colors.red),
        );
        return;
      }

      // Get current position for initial alert
      debugPrint('Getting current position...');
      Position position;
      try {
        position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        debugPrint('Current position: ${position.latitude}, ${position.longitude}');
      } catch (e) {
        debugPrint('Error getting current position: $e');
        // Don't reset emergency state on position error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not get current location: $e'), backgroundColor: Colors.red),
        );
        return;
      }

      // Start emergency sound if enabled
      if (_emergencySoundEnabled) {
        try {
          await _audioService.startEmergencySound();
        } catch (e) {
          debugPrint('Error starting emergency sound: $e');
          // Don't reset emergency state on audio error
        }
      }

      // Send WhatsApp message immediately
      debugPrint('Preparing WhatsApp message...');
      final message = '''
🚨 EMERGENCY ALERT 🚨
I need help! Please check my location:

🗺️ Current Location:
https://maps.google.com/?q=${position.latitude},${position.longitude}

📍 Live Tracking:
https://sheshiled-f0cc6.web.app/track.html?uid=$trackingId

⚠️ This is an automated emergency alert.
''';

      final whatsappUrl = Uri.parse(
        'whatsapp://send?phone=919324582641&text=${Uri.encodeComponent(message)}'
      );

      try {
        if (await canLaunchUrl(whatsappUrl)) {
          debugPrint('Launching WhatsApp...');
          await launchUrl(whatsappUrl);
          _messageSent = true;
          debugPrint('WhatsApp message sent successfully');
        } else {
          debugPrint('Could not launch WhatsApp');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not launch WhatsApp'), backgroundColor: Colors.red),
          );
        }
      } catch (e) {
        debugPrint('WhatsApp launch error: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('WhatsApp error: $e'), backgroundColor: Colors.red),
        );
      }

      // Create emergency document
      debugPrint('Creating emergency document...');
      try {
        await _firestore.collection('emergencies').add({
          'trackingId': trackingId,
          'status': 'active',
          'startedAt': FieldValue.serverTimestamp(),
          'lastUpdate': FieldValue.serverTimestamp(),
          'messageSent': _messageSent,
          'location': {
            'latitude': position.latitude,
            'longitude': position.longitude,
          },
          'settings': {
            'emergencySound': _emergencySoundEnabled,
            'alertSound': _alertSoundEnabled,
            'vibration': _vibrationEnabled,
          },
        });
        debugPrint('Emergency document created');
      } catch (e) {
        debugPrint('Error creating emergency document: $e');
        // Don't reset emergency state on document creation error
      }
    } catch (e) {
      debugPrint('Error in sendEmergencyAlert: $e');
      // Only reset emergency state if there's a critical error
      if (e.toString().contains('critical') || e.toString().contains('fatal')) {
        _isEmergencyActive = false;
        _messageSent = false;
      }
      rethrow;
    }
  }

  Future<void> stopEmergency() async {
    if (!_isEmergencyActive) {
      debugPrint('No emergency active to stop');
      return;
    }

    try {
      debugPrint('Stopping emergency...');
      
      // Stop emergency sound if it was playing
      if (_emergencySoundEnabled) {
        try {
          debugPrint('Stopping emergency sound...');
          await _audioService.stopEmergencySound();
          debugPrint('Emergency sound stopped');
        } catch (e) {
          debugPrint('Error stopping emergency sound: $e');
          // Continue with other cleanup even if sound stop fails
        }
      }
      
      // Stop location tracking
      try {
        debugPrint('Stopping location tracking...');
        await _locationTracking.stopTracking();
        debugPrint('Location tracking stopped');
      } catch (e) {
        debugPrint('Error stopping location tracking: $e');
        // Continue with other cleanup even if tracking stop fails
      }
      
      // Update emergency document
      try {
        final emergencies = await _firestore
            .collection('emergencies')
            .where('status', isEqualTo: 'active')
            .get();
            
        for (var doc in emergencies.docs) {
          await doc.reference.update({
            'status': 'ended',
            'endedAt': FieldValue.serverTimestamp(),
            'messageSent': _messageSent,
          });
        }
        debugPrint('Emergency documents updated');
      } catch (e) {
        debugPrint('Error updating emergency documents: $e');
        // Continue with state cleanup even if document update fails
      }
      
      // Always reset emergency state
      _isEmergencyActive = false;
      _messageSent = false;
      debugPrint('Emergency stopped successfully');
    } catch (e, stackTrace) {
      debugPrint('Error stopping emergency: $e');
      debugPrint('Stack trace: $stackTrace');
      // Ensure emergency state is reset even on error
      _isEmergencyActive = false;
      _messageSent = false;
      rethrow;
    }
  }

  bool get isEmergencyActive => _isEmergencyActive;
  bool get messageSent => _messageSent;

  // Check if tracking is active
  Future<bool> isTrackingActive() async {
    return await _locationTracking.isTrackingActive();
  }

  // Dispose
  void dispose() {
    _locationTracking.dispose();
    _audioService.dispose();
  }

  Future<bool> requestSMSPermissions() async {
    try {
      final bool result = await platform.invokeMethod('requestSMSPermissions');
      return result;
    } catch (e) {
      print('Error requesting SMS permissions: $e');
      return false;
    }
  }
} 