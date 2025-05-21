import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/contact.dart' as model;
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:url_launcher/url_launcher.dart';
import 'package:sheshield/services/emergency_service.dart';
import 'package:sheshield/services/location_service.dart';
import 'package:sheshield/models/emergency_contact.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:sheshield/services/helpline_service.dart';
import 'package:sheshield/screens/safety_tips_screen.dart';
import 'package:app_settings/app_settings.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final EmergencyService _emergencyService = EmergencyService();
  final LocationService _locationService = LocationService();
  bool _isLoading = false;
  bool _isTracking = false;
  bool _isEmergencyActive = false;
  bool _isEmergencyInitialized = false;
  bool _messageSent = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _checkTrackingStatus();
    _initializeServices();
    _startEmergencyStatusCheck();
  }

  Future<void> _initializeServices() async {
    try {
      await _emergencyService.initialize();
      if (mounted) {
        setState(() {
          _isEmergencyInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('Error initializing services: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error initializing emergency services: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _checkPermissions() async {
    // Request all relevant permissions
    final locationStatus = await Permission.location.request();
    final backgroundLocationStatus = await Permission.locationAlways.request();
    final notificationStatus = await Permission.notification.request();
    final smsStatus = await Permission.sms.request();
    final contactsStatus = await Permission.contacts.request();

    // If any permission is denied, show a dialog guiding the user to settings
    if (!locationStatus.isGranted ||
        !backgroundLocationStatus.isGranted ||
        !notificationStatus.isGranted ||
        !smsStatus.isGranted ||
        !contactsStatus.isGranted) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Permissions Required'),
            content: const Text(
              'Please grant all permissions (Location, Background Location, Notification, SMS, Contacts) for the app to work properly.\n\nTap "Open Settings" to grant permissions.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await openAppSettings();
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _checkTrackingStatus() async {
    final isRunning = await FlutterForegroundTask.isRunningService;
    if (mounted) {
      setState(() {
        _isTracking = isRunning;
      });
    }
  }

  // Get current location
  Future<Position> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled');
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  // Validate phone number format
  bool _isValidPhoneNumber(String phoneNumber) {
    // Remove any non-digit characters
    final digitsOnly = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    // Check if the number has a valid length (between 10 and 15 digits)
    return digitsOnly.length >= 10 && digitsOnly.length <= 15;
  }

  void _startEmergencyStatusCheck() {
    // Check emergency status every 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        _checkEmergencyStatus();
        _startEmergencyStatusCheck(); // Schedule next check
      }
    });
  }

  Future<void> _checkEmergencyStatus() async {
    if (!mounted) return;
    
    try {
      final isActive = _emergencyService.isEmergencyActive;
      if (isActive != _isEmergencyActive) {
        setState(() {
          _isEmergencyActive = isActive;
          _messageSent = _emergencyService.messageSent;
        });
      }
    } catch (e) {
      debugPrint('Error checking emergency status: $e');
    }
  }

  // Handle SOS button press
  Future<void> _handleSOS() async {
    if (!_isEmergencyInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Emergency services are still initializing. Please wait.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_isLoading) {
      return; // Prevent multiple taps while loading
    }

    if (_isEmergencyActive) {
      // Show confirmation dialog to stop emergency
      final shouldStop = await showDialog<bool>(
        context: context,
        barrierDismissible: false, // Prevent dismissing by tapping outside
        builder: (context) => AlertDialog(
          title: const Text('Stop Emergency?'),
          content: const Text(
            'Are you sure you want to stop the emergency alert?\n\n'
            'This will:\n'
            '• Stop location tracking\n'
            '• Stop emergency sound\n'
            '• End the emergency session'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('STOP EMERGENCY'),
            ),
          ],
        ),
      );

      if (shouldStop == true) {
        setState(() => _isLoading = true);
        try {
          await _emergencyService.stopEmergency();
          if (mounted) {
            setState(() {
              _isEmergencyActive = false;
              _messageSent = false;
              _isLoading = false;
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error stopping emergency: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
      return;
    }

    // Show confirmation dialog to start emergency
    final shouldStart = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (context) => AlertDialog(
        title: const Text('Send Emergency Alert?'),
        content: const Text(
          'This will:\n'
          '• Send your location to emergency contacts\n'
          '• Start live location tracking\n'
          '• Play emergency sound (if enabled)\n'
          '• Send WhatsApp message\n\n'
          'Are you sure you want to proceed?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('SEND ALERT'),
          ),
        ],
      ),
    );

    if (shouldStart == true) {
      setState(() => _isLoading = true);
      try {
        // Start the emergency service
        await _emergencyService.sendEmergencyAlert(context);
        
        if (mounted) {
          setState(() {
            _isEmergencyActive = _emergencyService.isEmergencyActive;
            _messageSent = _emergencyService.messageSent;
            _isLoading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isEmergencyActive = false;
            _messageSent = false;
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _stopTracking() async {
    try {
      await _locationService.stopLocationTracking();
      if (mounted) {
        setState(() {
          _isTracking = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location tracking stopped'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error stopping tracking: ${e.toString()}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _openSafetyTips() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SafetyTipsScreen()),
    );
  }

  Widget _buildSpeedDialButtons() {
    // Show only the most important helplines as speed dials
    final speedDials = [
      HelplineService.helplines[0], // Women Helpline
      HelplineService.helplines[1], // Police
      HelplineService.helplines[2], // Ambulance
      HelplineService.helplines[3], // Fire
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
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
              Text(helpline.name.split(' ')[0], style: const TextStyle(fontSize: 12)),
            ],
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SheShield'),
      ),
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Theme.of(context).primaryColor.withOpacity(0.1),
                  Colors.white,
                ],
              ),
            ),
          ),
          // Main content
          SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 20),
                  // App title
                  const Text(
                    'SheShield',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.pink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your Safety Companion',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Safety Tips Button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.tips_and_updates, color: Colors.orange),
                        label: const Text('Safety Tips'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade50,
                          foregroundColor: Colors.orange.shade900,
                          textStyle: const TextStyle(fontWeight: FontWeight.bold),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _openSafetyTips,
                      ),
                    ),
                  ),
                  // Speed Dial Buttons
                  _buildSpeedDialButtons(),
                  const SizedBox(height: 20),
                  // Emergency Status - Always show when active
                  if (_isEmergencyActive)
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red),
                      ),
                      child: Column(
                        children: [
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.warning, color: Colors.red),
                              SizedBox(width: 8),
                              Text(
                                'EMERGENCY ACTIVE',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _isLoading ? null : _handleSOS,
                            icon: const Icon(Icons.stop),
                            label: Text(_isLoading ? 'STOPPING...' : 'STOP EMERGENCY'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              disabledBackgroundColor: Colors.red.withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                  // SOS Button
                  Center(
                    child: GestureDetector(
                      onTap: _isLoading ? null : _handleSOS,
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isLoading
                              ? Colors.grey
                              : _isEmergencyActive
                                  ? Colors.orange
                                  : Colors.red,
                          boxShadow: [
                            BoxShadow(
                              color: (_isLoading
                                      ? Colors.grey
                                      : _isEmergencyActive
                                          ? Colors.orange
                                          : Colors.red)
                                  .withOpacity(0.3),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isEmergencyActive ? Icons.warning : Icons.warning,
                                size: 64,
                                color: Colors.white,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _isLoading
                                    ? 'Sending...'
                                    : _isEmergencyActive
                                        ? 'EMERGENCY ACTIVE'
                                        : 'SOS',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Instructions
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Text(
                          'Instructions:',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isEmergencyActive
                              ? '• Emergency alert is active\n'
                                  '• Emergency sound is playing\n'
                                  '• Location is being tracked\n'
                                  '• Click STOP EMERGENCY to end'
                              : '• Tap the SOS button to send emergency alerts\n'
                                  '• Add emergency contacts in the Contacts tab\n'
                                  '• Keep your phone charged and with you',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _emergencyService.dispose();
    super.dispose();
  }
} 