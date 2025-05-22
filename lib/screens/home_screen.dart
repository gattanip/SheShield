import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/contact.dart' as model;
import '../models/emergency_state.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:url_launcher/url_launcher.dart';
import 'package:sheshield/services/emergency_service.dart';
import 'package:sheshield/services/location_service.dart';
import 'package:sheshield/models/emergency_contact.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:sheshield/services/helpline_service.dart';
import 'package:app_settings/app_settings.dart';
import 'package:sheshield/services/emergency_media_service.dart';
import 'dart:async';
import 'package:sheshield/services/logging_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final EmergencyService _emergencyService = EmergencyService();
  final LocationService _locationService = LocationService();
  final EmergencyMediaService _mediaService = EmergencyMediaService();
  final LoggingService _logger = LoggingService();
  
  bool _isLoading = false;
  bool _isEmergencyActive = false;
  bool _isEmergencyInitialized = false;
  bool _messageSent = false;
  bool _isMediaCaptureActive = false;
  DateTime? _emergencyStartTime;
  Timer? _statusUpdateTimer;
  String? _selectedCaptureStrategy;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  StreamSubscription? _emergencyStateSubscription;
  StreamSubscription? _initializationSubscription;
  String? _initializationError;
  EmergencyState _emergencyState = EmergencyState.initializing;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeState();
  }

  Future<void> _initializeState() async {
    try {
      // Initialize pulse animation
      _pulseController = AnimationController(
        duration: const Duration(milliseconds: 1500),
        vsync: this,
      );
      _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
        CurvedAnimation(
          parent: _pulseController,
          curve: Curves.easeInOut,
        ),
      );
      _pulseController.repeat(reverse: true);

      // Initialize services
      await _checkPermissions();
      await _initializeServices();
      _startEmergencyStatusCheck();
      _setupEmergencyServiceListeners();
      
      // Log app lifecycle
      await _logger.logAppLifecycle('App Started');

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e, stackTrace) {
      await _logger.log(LogLevel.error, 'HomeScreen', 'Error initializing state', e, stackTrace);
      if (mounted) {
        setState(() {
          _initializationError = e.toString();
        });
      }
    }
  }

  void _setupEmergencyServiceListeners() {
    _emergencyStateSubscription?.cancel();
    _emergencyStateSubscription = _emergencyService.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _emergencyState = state;
          _isEmergencyActive = state == EmergencyState.active;
          _isEmergencyInitialized = state == EmergencyState.ready || state == EmergencyState.active;
          if (state == EmergencyState.active && _emergencyStartTime == null) {
            _emergencyStartTime = DateTime.now();
          }
        });
        _logger.logEmergencyEvent('State Changed', {'state': state.toString()});
      }
    });

    _initializationSubscription?.cancel();
    _initializationSubscription = _emergencyService.initializationStream.listen((initialized) {
      if (mounted) {
        setState(() {
          _isEmergencyInitialized = initialized;
          if (!initialized) {
            _initializationError = 'Failed to initialize emergency services';
          }
        });
        _logger.logEmergencyEvent('Initialization Status Changed', {'initialized': initialized});
      }
    });
  }

  Future<void> _initializeServices() async {
    try {
      setState(() => _isLoading = true);
      await _logger.logUIInteraction('Initialize Services');
      
      // Initialize services with a longer timeout
      final initFuture = _emergencyService.initialize();
      await initFuture.timeout(
        const Duration(seconds: 30), // Increased timeout
        onTimeout: () {
          throw TimeoutException('Service initialization timed out after 30 seconds');
        },
      );
      
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isEmergencyInitialized = true;
        });
      }
    } catch (e, stackTrace) {
      await _logger.log(LogLevel.error, 'HomeScreen', 'Error initializing services', e, stackTrace);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _initializationError = e.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error initializing emergency services: ${e.toString().split(':').last}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: _initializeServices,
              textColor: Colors.white,
            ),
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
    _statusUpdateTimer?.cancel();
    _statusUpdateTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        _checkEmergencyStatus();
      }
    });
  }

  Future<void> _checkEmergencyStatus() async {
    if (!mounted || !_isInitialized) return;
    
    try {
      final isActive = _emergencyService.isEmergencyActive;
      if (isActive != _isEmergencyActive) {
        setState(() {
          _isEmergencyActive = isActive;
          _messageSent = _emergencyService.messageSent;
          if (isActive && _emergencyStartTime == null) {
            _emergencyStartTime = DateTime.now();
          } else if (!isActive) {
            _emergencyStartTime = null;
          }
        });
      }
    } catch (e) {
      debugPrint('Error checking emergency status: $e');
    }
  }

  Future<bool> _showSafetyConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Emergency SOS'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to activate emergency services? This will:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text('• Share your live location'),
            const Text('• Capture photos and video'),
            const Text('• Record audio'),
            const Text('• Send alerts to your emergency contacts'),
            const SizedBox(height: 16),
            const Text(
              'This action cannot be undone until you manually stop the emergency services.',
              style: TextStyle(color: Colors.red),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Activate SOS'),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }

  Future<void> _sendEmergencyMessages() async {
    try {
      final contacts = await _emergencyService.getContacts();
      if (contacts.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No emergency contacts found."), backgroundColor: Colors.red),
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final locationLink = "https://maps.google.com/?q=${position.latitude},${position.longitude}";
      
      final emergencyMessage = '''
🚨 EMERGENCY ALERT 🚨
I need help! Please check my location:

🗺️ Current Location:
$locationLink

⚠️ This is an automated emergency alert shared by SheShield App.
''';

      for (var contact in contacts) {
        String phoneNumber = contact.phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
        if (phoneNumber.length == 10 && !phoneNumber.startsWith("91")) {
          phoneNumber = "91$phoneNumber";
        }
        
        final whatsappUrl = Uri.parse(
          "whatsapp://send?phone=$phoneNumber&text=${Uri.encodeComponent(emergencyMessage)}"
        );
        
        if (await canLaunchUrl(whatsappUrl)) {
          await launchUrl(whatsappUrl);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Could not open WhatsApp."), backgroundColor: Colors.red),
            );
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("SOS sent via WhatsApp with location and media links."), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error sending emergency messages: $e"), backgroundColor: Colors.red),
        );
      }
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
      // Show confirmation dialog before stopping emergency services
      final shouldStop = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Stop Emergency Services?'),
          content: const Text(
            'Are you sure you want to stop all emergency services? This will stop location sharing and media capture.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No, Keep Active'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Stop Services'),
            ),
          ],
        ),
      );
      
      if (shouldStop == true) {
        await _stopEmergencyServices();
      }
      return;
    }

    // Show confirmation dialog before starting emergency services
    final confirmed = await _showSafetyConfirmation();
    if (!confirmed) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Start services in sequence
      await _emergencyService.startEmergency();
      debugPrint('Emergency service started');
      
      await _locationService.startLocationSharing();
      debugPrint('Location sharing started');
      
      await _mediaService.startMediaCapture();
      debugPrint('Media capture started');
      
      // Send emergency messages
      await _sendEmergencyMessages();
      debugPrint('Emergency messages sent');
      
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isMediaCaptureActive = true;
          _emergencyStartTime = DateTime.now();
          _isEmergencyActive = true;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('Error starting emergency services: $e');
      debugPrint('Stack trace: $stackTrace');
      
      // Stop any services that were started
      try {
        await _emergencyService.stopEmergency();
        await _locationService.stopLocationSharing();
        await _mediaService.stopMediaCapture();
      } catch (stopError) {
        debugPrint('Error stopping services after failure: $stopError');
      }
      
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting emergency services: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _stopEmergencyServices() async {
    try {
      setState(() => _isLoading = true);
      await _logger.logUIInteraction('Stop Emergency');
      
      await _emergencyService.stopEmergency();
      
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isEmergencyActive = false;
          _emergencyStartTime = null;
          _isMediaCaptureActive = false;
        });
      }
    } catch (e, stackTrace) {
      await _logger.log(LogLevel.error, 'HomeScreen', 'Error stopping emergency services', e, stackTrace);
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error stopping emergency services: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading screen if not initialized
    if (!_isInitialized) {
      return Scaffold(
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
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.pink),
                ),
                SizedBox(height: 16),
                Text(
                  'Initializing SheShield...',
                  style: TextStyle(
                    color: Colors.pink,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('SheShield'),
        elevation: 0,
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
                  Colors.pink.withOpacity(0.1),
                  Colors.white,
                ],
              ),
            ),
          ),
          // Main content
          SafeArea(
            child: Column(
              children: [
                // Status banner at the top
                _buildEmergencyStatusBanner(),
                
                // Main content area
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
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
                                Icons.shield_rounded,
                                size: 48,
                                color: Colors.pink,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Your Safety Companion',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.pink,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Stay safe with SheShield',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        
                        // Emergency Status Card when active
                        if (_isEmergencyActive) ...[
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.pink.shade50,
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(color: Colors.pink.shade200),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.pink.withOpacity(0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.warning_amber_rounded, 
                                      color: Colors.pink.shade700,
                                      size: 24,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Emergency Active',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.pink.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Started: ${_formatDuration(_emergencyStartTime!)}',
                                  style: TextStyle(
                                    color: Colors.pink.shade600,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Location sharing and media capture are active',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 14,
                                  ),
                                ),
                                Container(
                                  margin: const EdgeInsets.only(top: 12),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: _isMediaCaptureActive
                                              ? () async {
                                                  setState(() => _isMediaCaptureActive = false);
                                                  await _mediaService.stopMediaCapture();
                                                }
                                              : () async {
                                                  setState(() => _isMediaCaptureActive = true);
                                                  await _mediaService.startMediaCapture();
                                                },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _isMediaCaptureActive ? Colors.pink : Colors.green,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                          ),
                                          icon: Icon(
                                            _isMediaCaptureActive ? Icons.stop_rounded : Icons.play_arrow_rounded,
                                            size: 20,
                                          ),
                                          label: Text(
                                            _isMediaCaptureActive ? 'Stop Media Capture' : 'Resume Media Capture',
                                            style: const TextStyle(fontSize: 14),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 40),
                        ],
                        
                        // SOS Button Container
                        Container(
                          height: MediaQuery.of(context).size.height * 0.4,
                          alignment: Alignment.center,
                          child: AnimatedBuilder(
                            animation: _pulseAnimation,
                            builder: (context, child) {
                              return Transform.scale(
                                scale: _isEmergencyActive ? 1.0 : _pulseAnimation.value,
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: (_isEmergencyActive ? Colors.pink : Colors.pink).withOpacity(0.3),
                                        blurRadius: 20,
                                        spreadRadius: 5,
                                      ),
                                    ],
                                  ),
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : _handleSOS,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _isEmergencyActive ? Colors.pink.shade700 : Colors.pink,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(160, 160),
                                      maximumSize: const Size(160, 160),
                                      shape: const CircleBorder(),
                                      elevation: 8,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _isEmergencyActive ? Icons.stop_rounded : Icons.warning_amber_rounded,
                                          size: 48,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          _isEmergencyActive ? 'STOP' : 'SOS',
                                          style: const TextStyle(
                                            fontSize: 28,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 2,
                                          ),
                                        ),
                                      ],
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
                ),
              ],
            ),
          ),
          // Loading overlay
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.pink),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _emergencyStateSubscription?.cancel();
    _initializationSubscription?.cancel();
    _statusUpdateTimer?.cancel();
    _pulseController.dispose();
    _logger.logAppLifecycle('App Closed');
    super.dispose();
  }

  Widget _buildEmergencyStatusBanner() {
    // Only show banner for error and active states
    if (_emergencyState == EmergencyState.error) {
      return Container(
        color: Colors.red,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                _initializationError?.split(':').last ?? 'Emergency services error',
                style: const TextStyle(color: Colors.white),
              ),
            ),
            TextButton(
              onPressed: _initializeServices,
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    if (_emergencyState == EmergencyState.active) {
      return Container(
        color: Colors.red,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white),
            const SizedBox(width: 16),
            const Expanded(
              child: Text(
                'EMERGENCY ACTIVE - Help is on the way',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            TextButton(
              onPressed: _stopEmergencyServices,
              child: const Text('Stop', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    // Don't show banner for initializing or ready states
    return const SizedBox.shrink();
  }

  String _formatDuration(DateTime startTime) {
    final now = DateTime.now();
    final duration = now.difference(startTime);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
} 